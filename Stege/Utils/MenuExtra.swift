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

    /// Presses a status item belonging to some other application.
    ///
    /// Used by the row of menu bar extras, where the element comes from that
    /// application's own `AXExtrasMenuBar` rather than from `Identifier`.
    ///
    /// Two differences from the presses above. The panel is left open, because
    /// opening that application's menu is the whole point rather than a step on
    /// the way to a control. And the pointer stays where the item is instead of
    /// going back: the menu opens anchored to the item, so leaving the pointer
    /// there puts it on the menu that just appeared, and on a menu bar set to
    /// hide, moving away is what would send it back up underneath.
    static func press(
        element: AXUIElement, completion: @escaping (Bool) -> Void = { _ in }
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            _ = revealMenuBarIfHidden(for: element)
            let pressed =
                AXUIElementPerformAction(element, kAXPressAction as CFString)
                == .success
            DispatchQueue.main.async { completion(pressed) }
        }
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
        guard let extra = element(for: identifier) else { return false }

        let pointer = revealMenuBarIfHidden(for: extra)
        defer { pointer.map(restorePointer) }

        guard
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

    /// One control read out of a panel.
    struct PanelControl {
        let identifier: String
        /// The label macOS shows next to it, which unlike the identifier is
        /// translated, and is therefore what to put on screen.
        let label: String
        let isOn: Bool
    }

    /// Opens a panel and reads every control whose identifier starts with
    /// `prefix`, rather than pressing one.
    ///
    /// This is how a list macOS keeps to itself can be shown without the
    /// permission its own storage is behind. `path` is the chain of controls to
    /// press to reach the panel holding them, exactly as in `press`.
    static func read(
        _ identifier: Identifier, path: [String], matching prefix: String,
        completion: @escaping ([PanelControl]) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let controls = readSynchronously(
                identifier, path: path, matching: prefix)
            DispatchQueue.main.async { completion(controls) }
        }
    }

    private static func readSynchronously(
        _ identifier: Identifier, path: [String], matching prefix: String
    ) -> [PanelControl] {
        guard let extra = element(for: identifier) else { return [] }
        let pointer = revealMenuBarIfHidden(for: extra)
        defer { pointer.map(restorePointer) }

        guard
            AXUIElementPerformAction(extra, kAXPressAction as CFString)
                == .success
        else { return [] }
        defer { closePanel(openedBy: extra) }

        for step in path {
            guard let control = waitForControl(identified: step),
                AXUIElementPerformAction(control, kAXPressAction as CFString)
                    == .success
            else { return [] }
        }

        // The panel is drawn a moment after the press returns, so wait for
        // anything matching to appear before collecting the rest.
        guard waitForControl(identifiedBy: { $0.hasPrefix(prefix) }) != nil
        else { return [] }

        guard let application = controlCentreApplication() else { return [] }
        var found: [PanelControl] = []
        var seen: Set<String> = []
        for window in panels(of: application) {
            collect(
                from: window, prefix: prefix, into: &found, seen: &seen,
                depth: 0)
        }
        return found
    }

    private static func collect(
        from element: AXUIElement, prefix: String,
        into found: inout [PanelControl], seen: inout Set<String>, depth: Int
    ) {
        guard depth < 12 else { return }
        if let identifier = attribute(element, "AXIdentifier") as? String,
            identifier.hasPrefix(prefix), !seen.contains(identifier)
        {
            seen.insert(identifier)
            found.append(
                PanelControl(
                    identifier: identifier,
                    label: attribute(element, kAXDescriptionAttribute as String)
                        as? String ?? identifier,
                    isOn: (attribute(element, kAXValueAttribute as String)
                        as? NSNumber)?.boolValue ?? false))
        }
        guard
            let children = attribute(element, kAXChildrenAttribute as String)
                as? [AXUIElement]
        else { return }
        for child in children {
            collect(
                from: child, prefix: prefix, into: &found, seen: &seen,
                depth: depth + 1)
        }
    }

    // MARK: - The hidden menu bar

    /// Brings the menu bar back on screen when it is set to hide, and reports
    /// where the pointer was so it can be put back.
    ///
    /// Pressing an extra whose menu bar is hidden silently does nothing: macOS
    /// parks the item above the top of the screen, at a negative y, and opens
    /// no panel for it. The reveal is driven by pointer movement, and by a real
    /// event, not by where the pointer happens to be, so moving it there
    /// without one leaves the bar hidden. Warping it back afterwards is enough,
    /// because the panel stays up once it is open.
    ///
    /// Returns nil when the bar was already on screen, which is the common case
    /// for anyone who has not set it to hide, and then nothing touches the
    /// pointer at all.
    private static func revealMenuBarIfHidden(for extra: AXUIElement)
        -> CGPoint?
    {
        guard isOffScreen(extra) else { return nil }
        let origin = CGEvent(source: nil)?.location ?? .zero
        movePointer(to: CGPoint(x: origin.x, y: 0))

        let deadline = Date().addingTimeInterval(1.5)
        while isOffScreen(extra), Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        // The item is back at a drawable position before the bar has finished
        // arriving, and pressing it in between opens nothing.
        Thread.sleep(forTimeInterval: 0.35)
        return origin
    }

    /// Moved by an event, not warped.
    ///
    /// A warp puts the pointer back without telling anything it moved, and a
    /// menu bar set to hide only goes back up on a real movement. Warping left
    /// it down, on top of Stege's own bar, swallowing the next click meant for
    /// a widget, until the user happened to move the mouse.
    private static func restorePointer(to origin: CGPoint) {
        movePointer(to: origin)
    }

    private static func movePointer(to point: CGPoint) {
        guard
            let event = CGEvent(
                mouseEventSource: nil, mouseType: .mouseMoved,
                mouseCursorPosition: point, mouseButton: .left)
        else { return }
        event.post(tap: .cghidEventTap)
    }

    private static func isOffScreen(_ extra: AXUIElement) -> Bool {
        guard let value = attribute(extra, kAXPositionAttribute as String),
            CFGetTypeID(value) == AXValueGetTypeID()
        else { return false }
        var point = CGPoint.zero
        guard
            AXValueGetValue(
                unsafeBitCast(value, to: AXValue.self), .cgPoint, &point)
        else { return false }
        return point.y < 0
    }

    // MARK: - Panels

    /// Presses the extra again, but only while its panel is still up.
    ///
    /// Some controls dismiss the panel themselves when pressed, and pressing
    /// the extra then would open it back up rather than close it. Repeated
    /// because one press does not always take when the panel has been stepped
    /// into: the first goes back a level rather than closing.
    private static func closePanel(openedBy extra: AXUIElement) {
        for _ in 0..<3 {
            guard controlCentreApplication().map(hasPanel) == true else {
                return
            }
            AXUIElementPerformAction(extra, kAXPressAction as CFString)
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    private static func hasPanel(_ application: AXUIElement) -> Bool {
        !panels(of: application).isEmpty
    }

    /// The panel windows, filtered by role.
    ///
    /// Control Center answers `AXWindows` with itself when it has no panel up,
    /// an element whose role is the application's rather than a window's and
    /// whose children walk back into the menu bar. Counting the array is
    /// therefore not enough, and searching it would find menu bar items in
    /// place of panel controls.
    private static func panels(of application: AXUIElement) -> [AXUIElement] {
        let windows =
            attribute(application, kAXWindowsAttribute as String)
            as? [AXUIElement]
        return
            windows?.filter {
                attribute($0, kAXRoleAttribute as String) as? String
                    == kAXWindowRole as String
            } ?? []
    }

    /// Polls rather than sleeps a fixed time. The panel is drawn in another
    /// process, so how long it takes is not this app's to know: measured at
    /// around 100ms here, and a fixed wait would be either wrong on a slower
    /// machine or wasted on a faster one.
    private static func waitForControl(identified identifier: String)
        -> AXUIElement?
    {
        waitForControl(identifiedBy: { $0 == identifier })
    }

    private static func waitForControl(
        identifiedBy matches: (String) -> Bool
    ) -> AXUIElement? {
        guard let application = controlCentreApplication() else { return nil }
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            for window in panels(of: application) {
                if let match = descendant(
                    of: window, matching: matches, depth: 0)
                {
                    return match
                }
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return nil
    }

    /// The first match in a depth-first walk.
    ///
    /// First, not any, matters: while a Focus is on, Control Center adds
    /// duration rows underneath it that carry the same identifier as the mode
    /// itself, and the mode is the one above them.
    private static func descendant(
        of element: AXUIElement, matching matches: (String) -> Bool, depth: Int
    ) -> AXUIElement? {
        // The panels are shallow, and a bound keeps a cycle in someone else's
        // hierarchy from becoming an infinite walk in this one.
        guard depth < 12 else { return nil }
        if let identifier = attribute(element, "AXIdentifier") as? String,
            matches(identifier)
        {
            return element
        }
        guard
            let children = attribute(element, kAXChildrenAttribute as String)
                as? [AXUIElement]
        else { return nil }
        for child in children {
            if let match = descendant(
                of: child, matching: matches, depth: depth + 1)
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
