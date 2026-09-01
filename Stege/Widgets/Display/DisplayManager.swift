import AppKit
import Combine
import CoreGraphics
import Darwin

/// One display attached to the machine.
struct DisplayInfo: Identifiable, Equatable {
    let id: CGDirectDisplayID
    let name: String
    let isBuiltIn: Bool
    /// 0 to 1, or nil for a display whose backlight is not ours to set, which
    /// is most external monitors.
    let brightness: Float?
}

/// Brightness, Night Shift and True Tone.
///
/// All three are read and written directly. Nothing here opens a panel or
/// presses anything, which is the same standard the Bluetooth switch is held
/// to: where macOS exports a real call, the call is used.
///
/// `DisplayServicesGetBrightness` and `DisplayServicesSetBrightness` are not in
/// any published header, but they are plain C functions exported by
/// `DisplayServices` and they answer without an entitlement, verified on this
/// machine. Night Shift and True Tone are `CBBlueLightClient` and
/// `CBTrueToneClient` in `CoreBrightness`, reached through the Objective-C
/// runtime for the same reason.
final class DisplayManager: ObservableObject {
    @Published private(set) var displays: [DisplayInfo] = []
    @Published private(set) var isNightShiftOn = false
    @Published private(set) var nightShiftStrength: Float = 0
    @Published private(set) var isTrueToneAvailable = false
    @Published private(set) var isTrueToneOn = false
    /// Set when a control could not be reached at all, so the popup can say so
    /// rather than drawing a switch that does nothing.
    @Published private(set) var failure: String?

    private var timer: Timer?

    init() {
        refresh()
        // Brightness moves from the keyboard and from ambient light without
        // telling anyone, so the popup would sit on a stale number. Only while
        // something is watching: the timer is started by the popup.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }
    }

    deinit {
        timer?.invalidate()
    }

    /// Called when the popup opens and closes. Reading brightness is a cheap
    /// call, but there is no reason to make it while nothing is on screen.
    func startPolling() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) {
            [weak self] _ in self?.refresh()
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Reading

    func refresh() {
        displays = Self.activeDisplays()
        isNightShiftOn = Self.readNightShift()
        nightShiftStrength = Self.readNightShiftStrength()
        isTrueToneAvailable = Self.readTrueToneAvailable()
        isTrueToneOn = Self.readTrueTone()
    }

    private static func activeDisplays() -> [DisplayInfo] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0
        else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success
        else { return [] }

        return ids.map { id in
            DisplayInfo(
                id: id,
                name: name(of: id),
                isBuiltIn: CGDisplayIsBuiltin(id) != 0,
                brightness: brightness(of: id))
        }
        // The built-in panel first, which is the one a laptop's brightness keys
        // act on and the one most people mean.
        .sorted { $0.isBuiltIn && !$1.isBuiltIn }
    }

    /// The name macOS shows in System Settings, where it publishes one.
    private static func name(of id: CGDirectDisplayID) -> String {
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID)
                == id
        }
        if let name = screen?.localizedName, !name.isEmpty { return name }
        return CGDisplayIsBuiltin(id) != 0 ? "Built-in Display" : "Display"
    }

    // MARK: - Brightness

    func setBrightness(_ value: Float, on display: DisplayInfo) {
        guard let set = Self.setBrightnessFunction else {
            failure = "Brightness cannot be set on this system"
            return
        }
        let clamped = min(1, max(0, value))
        guard set(display.id, clamped) == 0 else { return }
        // Written straight back rather than waiting for the next poll, so the
        // slider does not spring back under the pointer.
        if let index = displays.firstIndex(where: { $0.id == display.id }) {
            displays[index] = DisplayInfo(
                id: display.id, name: display.name,
                isBuiltIn: display.isBuiltIn, brightness: clamped)
        }
    }

    /// Moves the built-in display by `delta`, for the widget's scroll wheel.
    func nudgeBrightness(by delta: Float) {
        guard let display = displays.first(where: { $0.brightness != nil }),
            let current = display.brightness
        else { return }
        setBrightness(current + delta, on: display)
    }

    private static func brightness(of id: CGDirectDisplayID) -> Float? {
        guard let get = getBrightnessFunction else { return nil }
        var value: Float = 0
        guard get(id, &value) == 0 else { return nil }
        return value
    }

    private typealias GetBrightness = @convention(c) (
        CGDirectDisplayID, UnsafeMutablePointer<Float>
    ) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float)
        -> Int32

    private static let displayServices: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
        RTLD_LAZY)

    private static let getBrightnessFunction: GetBrightness? = {
        guard let handle = displayServices,
            let symbol = dlsym(handle, "DisplayServicesGetBrightness")
        else { return nil }
        return unsafeBitCast(symbol, to: GetBrightness.self)
    }()

    private static let setBrightnessFunction: SetBrightness? = {
        guard let handle = displayServices,
            let symbol = dlsym(handle, "DisplayServicesSetBrightness")
        else { return nil }
        return unsafeBitCast(symbol, to: SetBrightness.self)
    }()

    // MARK: - Night Shift

    func setNightShift(_ on: Bool) {
        guard let client = Self.blueLightClient else {
            failure = "Night Shift is not available on this system"
            return
        }
        _ = client.perform(Selector(("setEnabled:")), with: on as NSNumber)
        isNightShiftOn = Self.readNightShift()
    }

    func setNightShiftStrength(_ value: Float) {
        guard let client = Self.blueLightClient,
            let method = class_getInstanceMethod(
                type(of: client), Selector(("setStrength:commit:")))
        else { return }
        typealias SetStrength = @convention(c) (
            AnyObject, Selector, Float, Bool
        ) -> Bool
        let implementation = unsafeBitCast(
            method_getImplementation(method), to: SetStrength.self)
        let clamped = min(1, max(0, value))
        _ = implementation(
            client, Selector(("setStrength:commit:")), clamped, true)
        nightShiftStrength = clamped
    }

    /// `getBlueLightStatus:` fills a struct whose first two bytes are whether
    /// the tint is available and whether it is switched on, confirmed by
    /// toggling it and watching which byte moved. Only those two are read, so
    /// a later macOS reordering the rest of the struct cannot mislead this.
    private static func readNightShift() -> Bool {
        guard let client = blueLightClient,
            let method = class_getInstanceMethod(
                type(of: client), Selector(("getBlueLightStatus:")))
        else { return false }
        typealias GetStatus = @convention(c) (
            AnyObject, Selector, UnsafeMutableRawPointer
        ) -> Bool
        let implementation = unsafeBitCast(
            method_getImplementation(method), to: GetStatus.self)
        var buffer = [UInt8](repeating: 0, count: 256)
        return buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                implementation(
                    client, Selector(("getBlueLightStatus:")), base)
            else { return false }
            return raw[1] != 0
        }
    }

    private static func readNightShiftStrength() -> Float {
        guard let client = blueLightClient,
            let method = class_getInstanceMethod(
                type(of: client), Selector(("getStrength:")))
        else { return 0 }
        typealias GetStrength = @convention(c) (
            AnyObject, Selector, UnsafeMutablePointer<Float>
        ) -> Bool
        let implementation = unsafeBitCast(
            method_getImplementation(method), to: GetStrength.self)
        var value: Float = 0
        guard implementation(client, Selector(("getStrength:")), &value) else {
            return 0
        }
        return value
    }

    private static let blueLightClient: NSObject? = {
        _ = dlopen(
            "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness",
            RTLD_LAZY)
        guard let type = NSClassFromString("CBBlueLightClient") as? NSObject.Type
        else { return nil }
        return type.init()
    }()

    // MARK: - True Tone

    func setTrueTone(_ on: Bool) {
        guard let client = Self.trueToneClient else { return }
        client.setValue(on, forKey: "enabled")
        isTrueToneOn = Self.readTrueTone()
    }

    private static func readTrueTone() -> Bool {
        guard let client = trueToneClient,
            let value = client.value(forKey: "enabled") as? Bool
        else { return false }
        return value
    }

    /// Only Macs with the sensor have it at all, so the row is left out rather
    /// than drawn as a switch that cannot move.
    private static func readTrueToneAvailable() -> Bool {
        guard let client = trueToneClient else { return false }
        let available = client.value(forKey: "available") as? Bool ?? false
        let supported = client.value(forKey: "supported") as? Bool ?? false
        return available && supported
    }

    private static let trueToneClient: NSObject? = {
        _ = dlopen(
            "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness",
            RTLD_LAZY)
        guard let type = NSClassFromString("CBTrueToneClient") as? NSObject.Type
        else { return nil }
        return type.init()
    }()
}
