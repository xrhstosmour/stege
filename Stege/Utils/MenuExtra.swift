import AppKit
import ApplicationServices

/// Presses one of macOS's own menu bar extras, and the controls inside the
/// panel it opens, through the Accessibility API.
///
/// This is how Stege reaches Notification Center and Control Center without
/// reimplementing either. Neither has a public API, a URL scheme, or an
/// application that can be opened, and the only other route to their contents
/// is the private database behind Full Disk Access. Pressing the system's own
/// control means macOS draws the real panel, with its real contents, its own
/// clear and dismiss behaviour, and no extra permission beyond the
/// Accessibility access the app menus already require.
///
/// The same reasoning covers the switches. Low Power Mode and Focus have no
/// public API either, and the private frameworks behind them, `LowPowerMode`
/// and `DoNotDisturb`, answer only processes carrying Apple-issued
/// entitlements: an unentitled caller gets an XPC error or a call that never
/// returns, confirmed against both. What is left is the control the user would
/// have clicked, which is exactly what this presses.
enum MenuExtra {
    /// Identifiers rather than descriptions. `AXDescription` is localised, so
    /// matching "Clock" works only in English, while these are stable.
    enum Identifier: String {
        case notificationCentre = "com.apple.menuextra.clock"
        case controlCentre = "com.apple.menuextra.controlcenter"
        case battery = "com.apple.menuextra.battery"
    }

    /// Whether the extra exists and can be pressed, so a widget can say the
    /// feature is unavailable rather than doing nothing when clicked.
    static func isAvailable(_ identifier: Identifier) -> Bool {
        element(for: identifier) != nil
    }

    @discardableResult
    static func press(_ identifier: Identifier) -> Bool {
        guard let element = element(for: identifier) else { return false }
        return AXUIElementPerformAction(element, kAXPressAction as CFString)
            == .success
    }

    /// Opens an extra's panel and presses a control inside it.
    ///
    /// `path` is a chain, because some controls sit behind another one: the
    /// Focus tile has to be pressed before the mode inside it exists. Each
    /// entry is an `AXIdentifier`, which Control Center ships untranslated,
    /// unlike the descriptions next to them.
    ///
    /// Runs off the main thread. Every step waits for the panel macOS is still
    /// drawing, and doing that on the main thread would stall the whole bar.
    static func press(
        _ identifier: Identifier, path: [String],
        completion: @escaping (Bool) -> Void = { _ in }
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = pressSynchronously(identifier, path: path)
            DispatchQueue.main.async { completion(result) }
        }
    }

    private static func pressSynchronously(
        _ identifier: Identifier, path: [String]
    ) -> Bool {
        guard let extra = element(for: identifier),
            AXUIElementPerformAction(extra, kAXPressAction as CFString)
                == .success
        else { return false }

        // Closed however this ends. A panel left open would sit over the bar
        // and swallow the next click.
        defer { closePanel(openedBy: extra) }

        for step in path {
            guard let control = waitForControl(identified: step),
                AXUIElementPerformAction(control, kAXPressAction as CFString)
                    == .success
            else { return false }
        }
        return true
    }

    /// Whether a control inside an extra's panel is currently on.
    ///
    /// Opening the panel to read it is the cost of there being no API for the
    /// value either. Only worth it for a state nothing else reports, which is
    /// why Low Power Mode reads through `ProcessInfo` instead.
    static func isOn(
        _ identifier: Identifier, path: [String],
        completion: @escaping (Bool?) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            var value: Bool?
            if let extra = element(for: identifier),
                AXUIElementPerformAction(extra, kAXPressAction as CFString)
                    == .success
            {
                var control: AXUIElement?
                for step in path {
                    control = waitForControl(identified: step)
                    guard let control else { break }
                    // The last entry is the one being read, so it is not
                    // pressed. Everything before it only opens the next panel.
                    if step != path.last {
                        AXUIElementPerformAction(
                            control, kAXPressAction as CFString)
                    }
                }
                if let control,
                    let number = attribute(control, kAXValueAttribute as String)
                        as? NSNumber
                {
                    value = number.boolValue
                }
                closePanel(openedBy: extra)
            }
            DispatchQueue.main.async { completion(value) }
        }
    }

    // MARK: - Panels

    /// Presses the extra again, but only while its panel is still up.
    ///
    /// Some controls dismiss the panel themselves when pressed, and pressing
    /// the extra then would open it back up rather than close it.
    private static func closePanel(openedBy extra: AXUIElement) {
        guard controlCentreApplication().map(hasPanel) == true else { return }
        AXUIElementPerformAction(extra, kAXPressAction as CFString)
    }

    private static func hasPanel(_ application: AXUIElement) -> Bool {
        let windows =
            attribute(application, kAXWindowsAttribute as String)
            as? [AXUIElement]
        return windows?.isEmpty == false
    }

    /// Polls rather than sleeps a fixed time. The panel is drawn in another
    /// process, so how long it takes is not this app's to know: measured at
    /// around 100ms here, and a fixed wait would be either wrong on a slower
    /// machine or wasted on a faster one.
    private static func waitForControl(identified identifier: String)
        -> AXUIElement?
    {
        guard let application = controlCentreApplication() else { return nil }
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if let windows = attribute(
                application, kAXWindowsAttribute as String) as? [AXUIElement]
            {
                for window in windows {
                    if let match = descendant(
                        of: window, identified: identifier, depth: 0)
                    {
                        return match
                    }
                }
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return nil
    }

    private static func descendant(
        of element: AXUIElement, identified identifier: String, depth: Int
    ) -> AXUIElement? {
        // The panels are shallow, and a bound keeps a cycle in someone else's
        // hierarchy from becoming an infinite walk in this one.
        guard depth < 12 else { return nil }
        if attribute(element, "AXIdentifier") as? String == identifier {
            return element
        }
        guard
            let children = attribute(element, kAXChildrenAttribute as String)
                as? [AXUIElement]
        else { return nil }
        for child in children {
            if let match = descendant(
                of: child, identified: identifier, depth: depth + 1)
            {
                return match
            }
        }
        return nil
    }

    // MARK: - Elements

    private static func controlCentreApplication() -> AXUIElement? {
        guard
            let controlCentre = NSWorkspace.shared.runningApplications.first(
                where: { $0.bundleIdentifier == "com.apple.controlcenter" })
        else { return nil }
        return AXUIElementCreateApplication(controlCentre.processIdentifier)
    }

    private static func element(for identifier: Identifier) -> AXUIElement? {
        guard let application = controlCentreApplication() else { return nil }
        // Menu bar extras hang off `AXExtrasMenuBar`, not `AXMenuBar`. The
        // latter is the application's own menus, which Control Center does not
        // publish, so reading it returns nothing at all.
        guard
            let bar = attribute(application, "AXExtrasMenuBar")
                as! AXUIElement?,
            let items = attribute(bar, kAXChildrenAttribute as String)
                as? [AXUIElement]
        else { return nil }

        return items.first {
            attribute($0, "AXIdentifier") as? String == identifier.rawValue
        }
    }

    private static func attribute(_ element: AXUIElement, _ name: String)
        -> CFTypeRef?
    {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, name as CFString, &value)
                == .success
        else { return nil }
        return value
    }
}
