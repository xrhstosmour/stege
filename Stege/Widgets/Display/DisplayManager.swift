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
    /// What the desktop is currently drawn at, in points.
    let resolution: CGSize
}

/// One resolution a display will accept.
struct DisplayMode: Identifiable, Equatable {
    /// The size in points, which is what System Settings lists and what
    /// everything is laid out in. A Retina mode is half its pixel size.
    let size: CGSize
    let isCurrent: Bool
    /// Two pixels per point. Worth saying, because a display offers the same
    /// point size both ways and one of them is blurry.
    let isRetina: Bool
    let mode: CGDisplayMode

    var id: String {
        "\(Int(size.width))x\(Int(size.height))\(isRetina ? "@2x" : "")"
    }
    var label: String {
        "\(Int(size.width)) × \(Int(size.height))"
    }
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
    /// Whether the displays are showing the same picture.
    @Published private(set) var isMirrored = false
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
        ) { [weak self] _ in
            // A monitor unplugged and plugged back in can land on a different
            // port, so the cached mapping has to go with it.
            DisplayDataChannel.forget()
            self?.refresh()
        }
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
        isMirrored = CGDisplayIsInMirrorSet(CGMainDisplayID()) != 0
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
            let mode = CGDisplayCopyDisplayMode(id)
            return DisplayInfo(
                id: id,
                name: name(of: id),
                isBuiltIn: CGDisplayIsBuiltin(id) != 0,
                brightness: brightness(of: id),
                resolution: CGSize(
                    width: mode?.width ?? 0, height: mode?.height ?? 0))
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

    // MARK: - Resolution

    /// The resolutions a display will accept, as System Settings lists them.
    ///
    /// `CGDisplayCopyAllDisplayModes` hands back everything the panel can do,
    /// which is dozens of entries: every refresh rate, every pixel encoding,
    /// and modes macOS will not put a desktop on. Only the usable ones are
    /// kept, one per point size, preferring the Retina version where a
    /// display offers the same size both ways, and the list is capped so a
    /// monitor with twenty modes does not make a popup taller than the screen.
    func modes(for display: DisplayInfo) -> [DisplayMode] {
        let options =
            [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue]
            as CFDictionary
        guard
            let all = CGDisplayCopyAllDisplayModes(display.id, options)
                as? [CGDisplayMode]
        else { return [] }

        let current = CGDisplayCopyDisplayMode(display.id)
        var best: [String: DisplayMode] = [:]
        for mode in all where mode.isUsableForDesktopGUI() {
            let size = CGSize(width: mode.width, height: mode.height)
            let isRetina = mode.pixelWidth > mode.width
            let key = "\(mode.width)x\(mode.height)"
            let candidate = DisplayMode(
                size: size,
                isCurrent: mode.ioDisplayModeID == current?.ioDisplayModeID,
                isRetina: isRetina,
                mode: mode)
            // The current mode always wins its slot, so the tick is never on a
            // row that is not the one in use. Otherwise the sharper of the two.
            if let existing = best[key] {
                if existing.isCurrent { continue }
                if candidate.isCurrent || (isRetina && !existing.isRetina) {
                    best[key] = candidate
                }
            } else {
                best[key] = candidate
            }
        }
        return best.values
            .sorted { $0.size.width * $0.size.height > $1.size.width * $1.size.height }
            .prefix(6)
            .map { $0 }
    }

    /// Applied inside a configuration transaction, which is what makes the
    /// change atomic and lets macOS put it back if the display cannot show it.
    func setMode(_ mode: DisplayMode, on display: DisplayInfo) {
        var configuration: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&configuration) == .success,
            let configuration
        else {
            failure = "The resolution could not be changed"
            return
        }
        CGConfigureDisplayWithDisplayMode(
            configuration, display.id, mode.mode, nil)
        // For this login session only. Writing it permanently is System
        // Settings' job, and a menu bar should not leave a display in a state
        // that survives a restart without being asked to.
        guard CGCompleteDisplayConfiguration(configuration, .forSession)
            == .success
        else {
            failure = "The resolution could not be changed"
            return
        }
        refresh()
    }

    // MARK: - Mirroring

    /// Every display shows what the main one shows, or none of them do.
    func setMirroring(_ on: Bool) {
        var configuration: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&configuration) == .success,
            let configuration
        else {
            failure = "Mirroring could not be changed"
            return
        }
        let main = CGMainDisplayID()
        for display in displays where display.id != main {
            CGConfigureDisplayMirrorOfDisplay(
                configuration, display.id, on ? main : kCGNullDirectDisplay)
        }
        guard CGCompleteDisplayConfiguration(configuration, .forSession)
            == .success
        else {
            failure = "Mirroring could not be changed"
            return
        }
        // The display list changes shape when mirroring turns on, and the
        // system takes a moment to settle before it reports the new one.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.refresh()
        }
    }

    // MARK: - Brightness

    func setBrightness(_ value: Float, on display: DisplayInfo) {
        let clamped = min(1, max(0, value))
        if !display.isBuiltIn {
            Self.externalBrightness[display.id] = clamped
            store(clamped, on: display)
            // The write waits on the monitor, so it does not belong in front of
            // a slider being dragged.
            DispatchQueue.global(qos: .userInitiated).async {
                DisplayDataChannel.setBrightness(clamped, on: display.id)
            }
            return
        }
        guard let set = Self.setBrightnessFunction else {
            failure = "Brightness cannot be set on this system"
            return
        }
        guard set(display.id, clamped) == 0 else { return }
        store(clamped, on: display)
    }

    /// Written straight back rather than waiting for the next poll, so the
    /// slider does not spring back under the pointer.
    private func store(_ value: Float, on display: DisplayInfo) {
        guard let index = displays.firstIndex(where: { $0.id == display.id })
        else { return }
        displays[index] = DisplayInfo(
            id: display.id, name: display.name,
            isBuiltIn: display.isBuiltIn, brightness: value,
            resolution: display.resolution)
    }

    /// Moves one display by `delta`, for the widget's scroll wheel.
    ///
    /// The built-in panel when there is one, because that is what the
    /// brightness keys act on and what a scroll over the bar most obviously
    /// means. With the lid shut there is none, so the first monitor that
    /// answers over the cable takes it instead.
    func nudgeBrightness(by delta: Float) {
        let display = displays.first { $0.isBuiltIn && $0.brightness != nil }
            ?? displays.first { $0.brightness != nil }
        guard let display, let current = display.brightness else { return }
        setBrightness(current + delta, on: display)
    }

    /// The built-in panel answers `DisplayServices` directly. An external one
    /// only answers over the cable, which costs a round trip and cannot be on
    /// the once-a-second poll, so the last reading is used and
    /// `readExternalBrightness` is what refreshes it.
    private static func brightness(of id: CGDirectDisplayID) -> Float? {
        if CGDisplayIsBuiltin(id) == 0 { return externalBrightness[id] }
        guard let get = getBrightnessFunction else { return nil }
        var value: Float = 0
        guard get(id, &value) == 0 else { return nil }
        return value
    }

    /// What each external monitor last said its backlight was set to.
    nonisolated(unsafe) private static var externalBrightness:
        [CGDirectDisplayID: Float] = [:]

    /// Asks every external monitor over the cable, off the main thread.
    ///
    /// Called when the popup opens, not on the poll: a DDC exchange waits on
    /// the monitor and takes tens of milliseconds even when it goes well, and
    /// three times that when the first reply lands early.
    func readExternalBrightness() {
        let ids = displays.filter { !$0.isBuiltIn }.map(\.id)
        guard !ids.isEmpty, DisplayDataChannel.isAvailable else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            var found: [CGDirectDisplayID: Float] = [:]
            for id in ids {
                if let value = DisplayDataChannel.brightness(of: id) {
                    found[id] = value
                }
            }
            guard !found.isEmpty else { return }
            DispatchQueue.main.async {
                for (id, value) in found { Self.externalBrightness[id] = value }
                self.refresh()
            }
        }
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

    /// Called through a typed function pointer rather than `perform(_:with:)`.
    ///
    /// `setEnabled:` takes a `BOOL`, a primitive, and `perform(_:with:)` passes
    /// an object. The method then reads the pointer as its boolean, and a
    /// non-nil pointer is always true, so the switch turned Night Shift on and
    /// could never turn it off again.
    func setNightShift(_ on: Bool) {
        guard let client = Self.blueLightClient,
            let method = class_getInstanceMethod(
                type(of: client), Selector(("setEnabled:")))
        else {
            failure = "Night Shift is not available on this system"
            return
        }
        typealias SetEnabled = @convention(c) (AnyObject, Selector, Bool) -> Bool
        let implementation = unsafeBitCast(
            method_getImplementation(method), to: SetEnabled.self)
        _ = implementation(client, Selector(("setEnabled:")), on)
        // Believed straight away so the switch moves under the pointer, then
        // read back once the change has settled. Reading immediately catches
        // the old value.
        isNightShiftOn = on
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            self.isNightShiftOn = Self.readNightShift()
            self.nightShiftStrength = Self.readNightShiftStrength()
        }
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
        isTrueToneOn = on
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.isTrueToneOn = Self.readTrueTone()
        }
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
