import AppKit
import ApplicationServices

/// Moves a window that opens under the bar down to the bar's bottom edge.
///
/// A window manager's gap only governs the windows it tiles. A floating
/// window, a dialog, or any window in an application it does not manage is
/// placed by the application, which knows nothing of a bar drawn over the
/// system menu bar. Setting a window's position through Accessibility is
/// moving it, not simulating a click.
///
/// Only reacts to a window being created or taking focus, never to a move,
/// so dragging a window up under the bar by hand is left alone. The geometry
/// is `WindowPlacement`, which is the tested part.
final class WindowNudger {
    static let shared = WindowNudger()

    private var observers: [pid_t: AXObserver] = [:]
    private var isRunning = false
    private var isWatchingTrust = false

    /// Every Accessibility call is a synchronous round trip into another
    /// application, and a hung one holds the caller for the default six
    /// seconds. These run here, not on the main thread, so a stuck window
    /// cannot freeze the bar.
    private let queue = DispatchQueue(
        label: "stege.window-nudger", qos: .userInitiated)

    /// Starts or stops to match the configuration. Idempotent, and run again
    /// when the configuration reloads and when macOS announces that
    /// Accessibility trust changed, which is what picks up a grant made after
    /// launch.
    func apply(_ configuration: Config) {
        watchTrust()
        let wanted = configuration.bar.nudgeWindows && AXIsProcessTrusted()
        guard wanted != isRunning else { return }
        isRunning = wanted
        if wanted { start() } else { stop() }
    }

    private func watchTrust() {
        guard !isWatchingTrust else { return }
        isWatchingTrust = true
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"),
            object: nil, queue: .main
        ) { [weak self] _ in
            // The notification can arrive a moment before the answer changes.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.apply(ConfigManager.shared.config)
            }
        }
    }

    private func start() {
        // A slow application answers late, never for six seconds.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.25)
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self, selector: #selector(applicationLaunched(_:)),
            name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        center.addObserver(
            self, selector: #selector(applicationTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        for application in NSWorkspace.shared.runningApplications {
            observe(application)
        }
    }

    private func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        for pid in Array(observers.keys) { unobserve(pid) }
    }

    @objc private func applicationLaunched(_ notification: Notification) {
        guard
            let application = notification.userInfo?[
                NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        else { return }
        observe(application)
    }

    @objc private func applicationTerminated(_ notification: Notification) {
        guard
            let application = notification.userInfo?[
                NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        else { return }
        unobserve(application.processIdentifier)
    }

    private func observe(_ application: NSRunningApplication) {
        let pid = application.processIdentifier
        guard application.activationPolicy == .regular,
            pid != ProcessInfo.processInfo.processIdentifier,
            observers[pid] == nil
        else { return }

        var created: AXObserver?
        let callback: AXObserverCallback = { _, element, _, _ in
            WindowNudger.shared.schedule(element)
        }
        guard AXObserverCreate(pid, callback, &created) == .success,
            let observer = created
        else { return }

        let element = AXUIElementCreateApplication(pid)
        AXObserverAddNotification(
            observer, element, kAXWindowCreatedNotification as CFString, nil)
        AXObserverAddNotification(
            observer, element, kAXFocusedWindowChangedNotification as CFString,
            nil)
        CFRunLoopAddSource(
            CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer),
            .defaultMode)
        observers[pid] = observer
    }

    private func unobserve(_ pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer),
            .defaultMode)
    }

    /// A short wait first. Both a window manager and the application place a
    /// new window just after it exists, and reading its frame before that
    /// would measure a position about to be replaced.
    fileprivate func schedule(_ element: AXUIElement) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.nudge(element)
        }
    }

    private func nudge(_ element: AXUIElement) {
        let configuration = ConfigManager.shared.config
        guard configuration.bar.nudgeWindows, !BarVisibility.shared.isHidden
        else { return }

        // Everything that needs AppKit or the live configuration is read here,
        // on the main thread, and handed to the queue as plain values.
        let screens = NSScreen.screens.map {
            WindowPlacement.Screen(
                frame: $0.frame, visibleFrame: $0.visibleFrame)
        }
        let barHeight = configuration.bar.resolveHeight()
        let provider = AerospaceSpacesProvider()

        queue.async {
            guard let window = Self.windowElement(from: element),
                Self.isOrdinary(window),
                let frame = Self.frame(of: window),
                let placed = WindowPlacement.nudged(
                    frame: frame, screens: screens, barHeight: barHeight)
            else { return }

            // A tiled window is `AeroSpace`'s to place. Moving it here only
            // makes the two take turns, the window jumping on every focus
            // change. Only a floating one, or one `AeroSpace` does not know,
            // is this file's job.
            if let layout = provider.focusedWindowLayout(), layout != "floating" {
                return
            }

            if placed.size != frame.size {
                Self.set(size: placed.size, on: window)
            }
            Self.set(position: placed.origin, on: window)
        }
    }

    /// The notification is delivered on the application for a focus change
    /// and on the window itself for a creation.
    private static func windowElement(from element: AXUIElement) -> AXUIElement? {
        if string(kAXRoleAttribute, of: element) == kAXWindowRole {
            return element
        }
        guard
            let value = value(kAXFocusedWindowAttribute, of: element),
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    /// Standard windows and dialogs only. Not full-screen or minimized ones,
    /// and not a panel, a popover or a menu, which place themselves on
    /// purpose.
    private static func isOrdinary(_ window: AXUIElement) -> Bool {
        let subrole = string(kAXSubroleAttribute, of: window)
        guard subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole
        else { return false }
        return !bool("AXFullScreen", of: window)
            && !bool(kAXMinimizedAttribute, of: window)
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        var position = CGPoint.zero
        var size = CGSize.zero
        guard let positionValue = value(kAXPositionAttribute, of: window),
            let sizeValue = value(kAXSizeAttribute, of: window),
            AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: position, size: size)
    }

    private static func set(position: CGPoint, on window: AXUIElement) {
        var copy = position
        guard let wrapped = AXValueCreate(.cgPoint, &copy) else { return }
        AXUIElementSetAttributeValue(
            window, kAXPositionAttribute as CFString, wrapped)
    }

    private static func set(size: CGSize, on window: AXUIElement) {
        var copy = size
        guard let wrapped = AXValueCreate(.cgSize, &copy) else { return }
        AXUIElementSetAttributeValue(
            window, kAXSizeAttribute as CFString, wrapped)
    }

    private static func value(_ attribute: String, of element: AXUIElement)
        -> CFTypeRef?
    {
        var result: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, attribute as CFString, &result)
                == .success
        else { return nil }
        return result
    }

    private static func string(_ attribute: String, of element: AXUIElement)
        -> String?
    {
        value(attribute, of: element) as? String
    }

    private static func bool(_ attribute: String, of element: AXUIElement)
        -> Bool
    {
        (value(attribute, of: element) as? Bool) ?? false
    }
}
