import Combine
import Foundation
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

    private var runLoopSource: CFRunLoopSource?

    init() {
        updateBatteryStatus()
        startMonitoring()
    }

    deinit {
        stopMonitoring()
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
            let level = min(100, max(0, (currentCapacity * 100) / maxCapacity))

            DispatchQueue.main.async {
                self.batteryLevel = level
                self.isCharging = charging
                self.isPluggedIn = isAC
            }
            // Only the first usable source is the internal battery. Continuing
            // would let an attached UPS overwrite it.
            return
        }
    }
}
