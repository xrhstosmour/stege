import Combine
import Foundation
import IOKit
import IOKit.ps

/// Monitors the battery, driven by IOKit's power source notifications.
///
/// Upstream polled this once a second. IOKit posts a run loop callback whenever
/// anything about a power source changes, which is the only moment these values
/// can move, so no timer is needed. This is what upstream issue #82 proposed.
class BatteryManager: ObservableObject {
    @Published var batteryLevel: Int = 0
    @Published var isCharging: Bool = false
    @Published var isPluggedIn: Bool = false
    /// Minutes until empty, or until full while charging. Nil while macOS is
    /// still calculating, which it reports as -1 rather than as an error.
    @Published var minutesRemaining: Int?
    /// Health as a fraction of the battery's original capacity.
    @Published var healthFraction: Double?
    @Published var cycleCount: Int?
    @Published var isLowPowerMode: Bool = false
    /// True while the switch is being flipped, so the popup can show the
    /// change is in flight rather than appear to have ignored the click.
    @Published private(set) var isSwitchingPowerMode = false

    private var runLoopSource: CFRunLoopSource?
    private var powerStateObserver: NSObjectProtocol?

    init() {
        updateBatteryStatus()
        startMonitoring()
        // Low Power Mode does not always move a power source, so the IOKit
        // notification below can miss it. This one is posted for exactly this
        // change and nothing else.
        powerStateObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isLowPowerMode = ProcessInfo.processInfo
                .isLowPowerModeEnabled
        }
    }

    deinit {
        stopMonitoring()
        if let powerStateObserver {
            NotificationCenter.default.removeObserver(powerStateObserver)
        }
    }

    /// Flips Low Power Mode.
    ///
    /// There is no API for writing it. `pmset` needs root, and the private
    /// `LowPowerMode` framework answers only entitled callers, so this presses
    /// the switch in the battery menu extra's own panel through the
    /// Accessibility API, the same access the app menus already need. macOS
    /// draws that panel for a moment while it happens.
    func toggleLowPowerMode() {
        guard !isSwitchingPowerMode else { return }
        isSwitchingPowerMode = true
        MenuExtra.press(.battery, path: ["energy-mode-low"]) {
            [weak self] _ in
            self?.isSwitchingPowerMode = false
            // The notification above normally lands first. Reading here as
            // well means a missed one leaves the switch right rather than
            // stuck showing the previous state.
            self?.isLowPowerMode = ProcessInfo.processInfo
                .isLowPowerModeEnabled
        }
    }

    private func startMonitoring() {
        // The callback is C, so it carries `self` across as an opaque pointer.
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard
            let source = IOPSNotificationCreateRunLoopSource(
                { context in
                    guard let context else { return }
                    let manager = Unmanaged<BatteryManager>
                        .fromOpaque(context).takeUnretainedValue()
                    manager.updateBatteryStatus()
                }, context)?.takeRetainedValue()
        else { return }

        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
    }

    private func stopMonitoring() {
        guard let runLoopSource else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        self.runLoopSource = nil
    }

    /// Design and current capacity live on the IOKit service rather than in the
    /// power-source description, so health needs a separate lookup.
    private static func batteryProperties() -> [String: Any]? {
        let matching = IOServiceMatching("AppleSmartBattery")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var properties: Unmanaged<CFMutableDictionary>?
        guard
            IORegistryEntryCreateCFProperties(
                service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
            let dictionary = properties?.takeRetainedValue() as? [String: Any]
        else { return nil }
        return dictionary
    }

    /// Health as a fraction of the battery's original capacity.
    ///
    /// The two keys are not the same kind of number, which is the trap here.
    /// `AppleRawMaxCapacity` is a charge in mAh and divides by `DesignCapacity`.
    /// `MaxCapacity` on Apple Silicon is *already a percentage*, reporting 100
    /// on a machine whose design capacity is 4629, so dividing it the same way
    /// yields 2% on a healthy battery. Each is therefore read on its own terms.
    private static func healthFraction() -> Double? {
        guard let properties = batteryProperties() else { return nil }

        if let raw = properties["AppleRawMaxCapacity"] as? Int,
            let design = properties["DesignCapacity"] as? Int, design > 0,
            raw > 100
        {
            return min(1, Double(raw) / Double(design))
        }
        if let percentage = properties["MaxCapacity"] as? Int, percentage > 0,
            percentage <= 100
        {
            return Double(percentage) / 100
        }
        return nil
    }

    private static func cycleCount() -> Int? {
        batteryProperties()?["CycleCount"] as? Int
    }

    /// Reads the internal battery and publishes its state.
    func updateBatteryStatus() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(snapshot)?
                .takeRetainedValue() as? [CFTypeRef]
        else {
            return
        }

        for source in sources {
            guard
                let description = IOPSGetPowerSourceDescription(
                    snapshot, source)?.takeUnretainedValue() as? [String: Any],
                let currentCapacity = description[
                    kIOPSCurrentCapacityKey as String] as? Int,
                let maxCapacity = description[kIOPSMaxCapacityKey as String]
                    as? Int,
                let charging = description[kIOPSIsChargingKey as String]
                    as? Bool,
                let powerSourceState = description[
                    kIOPSPowerSourceStateKey as String] as? String
            else { continue }

            // IOKit reports a zero maximum transiently, around wake in
            // particular. Integer division by zero traps in Swift, so this
            // guard is the difference between a stale reading and a crash.
            guard maxCapacity > 0 else { continue }

            let isAC = (powerSourceState == kIOPSACPowerValue)

            // `IOPS` reports -1 both while calculating and when the value is
            // unavailable, so anything negative is treated as unknown rather
            // than shown as a negative duration.
            let rawMinutes =
                (charging
                    ? description[kIOPSTimeToFullChargeKey as String] as? Int
                    : description[kIOPSTimeToEmptyKey as String] as? Int) ?? -1
            let minutes = rawMinutes >= 0 ? rawMinutes : nil
            let level = min(100, max(0, (currentCapacity * 100) / maxCapacity))

            let health = Self.healthFraction()
            let cycles = Self.cycleCount()
            let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

            DispatchQueue.main.async {
                self.batteryLevel = level
                self.isCharging = charging
                self.isPluggedIn = isAC
                self.minutesRemaining = minutes
                self.healthFraction = health
                self.cycleCount = cycles
                self.isLowPowerMode = lowPower
            }
            // Only the first usable source is the internal battery. Continuing
            // would let an attached UPS overwrite it.
            return
        }
    }
}
