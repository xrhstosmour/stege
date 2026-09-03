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
        /// Opens straight onto the output list, AirPlay receivers included.
        case sound = "com.apple.menuextra.sound"
        /// Only published when the module is set to always show in the menu
        /// bar. `screenMirroringRoute` falls back to Control Center when it is
        /// not there.
        case screenMirroring = "com.apple.menuextra.screen-mirroring"
    }

    /// The shortest way to a picker, given what the menu bar is publishing.
    ///
    /// Every one of these panels belongs to Control Center, and it will open
    /// them two ways: through its own panel and then a tile, or straight from a
    /// dedicated extra when the user has that module set to always show. The
    /// second is one press instead of two and the panel that opens is already
    /// the picker, so it is preferred whenever it exists.
    static func route(to module: Identifier, tile: String)
        -> (extra: Identifier, path: [String])
    {
        if element(for: module) != nil { return (module, []) }
        return (.controlCentre, [tile])
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
    /// Nothing is revealed and the pointer is not touched. Control Center's own
    /// extras have to be brought on screen before they answer to a press, and
    /// other applications' status items turn out not to: pressing one parked at
    /// y = -28 opens its menu just the same. So there is no menu bar sliding
    /// down and no pointer jumping to the top of the screen, both of which the
    /// reveal used to cause.
    ///
    /// The panel is left open, because opening that application's menu is the
    /// whole point rather than a step on the way to a control.
    static func press(
        element: AXUIElement, completion: @escaping (Bool) -> Void = { _ in }
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
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
        // The panel that is about to open takes key, and a popup that loses key
        // hides itself. Flipping Low Power Mode or a Focus used to take the
        // popup that asked for it off the screen.
        MenuBarPopup.beginSystemPanelInteraction()
        DispatchQueue.global(qos: .userInitiated).async {
            let result = pressSynchronously(identifier, path: path)
            DispatchQueue.main.async {
                MenuBarPopup.endSystemPanelInteraction()
                completion(result)
            }
        }
    }

    private static func pressSynchronously(
        _ identifier: Identifier, path: [String]
    ) -> Bool {
        guard let extra = element(for: identifier) else { return false }

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

    /// Opens an extra's panel, steps into one of its tiles, and leaves it on
    /// screen for the user.
    ///
    /// The other end of `press`, which closes the panel because there the panel
    /// was only the route to a switch. Here the panel is the answer: macOS
    /// keeps the AirPlay receivers and the screen mirroring targets behind an
    /// Apple-only entitlement, and every system output context answers an
    /// ordinary application with nil, so its own picker is the only place they
    /// can be chosen. This opens exactly the picker the user would have opened
    /// by hand.
    ///
    /// Stege's own popup is taken off the screen first, because the panel opens
    /// where the popup was standing.
    static func open(
        _ identifier: Identifier, path: [String],
        completion: @escaping (Bool) -> Void = { _ in }
    ) {
        MenuBarPopup.hide()
        DispatchQueue.global(qos: .userInitiated).async {
            let result = openSynchronously(identifier, path: path)
            DispatchQueue.main.async { completion(result) }
        }
    }

    private static func openSynchronously(
        _ identifier: Identifier, path: [String]
    ) -> Bool {
        guard let extra = element(for: identifier) else { return false }

        guard
            AXUIElementPerformAction(extra, kAXPressAction as CFString)
                == .success
        else { return false }

        for step in path {
            guard let control = waitForControl(identified: step),
                AXUIElementPerformAction(control, kAXPressAction as CFString)
                    == .success
            else {
                // Only on the way out. A panel opened and then left half way
                // into a step that failed is worse than no panel.
                closePanel(openedBy: extra)
                return false
            }
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
        MenuBarPopup.beginSystemPanelInteraction()
        DispatchQueue.global(qos: .userInitiated).async {
            let controls = readSynchronously(
                identifier, path: path, matching: prefix)
            DispatchQueue.main.async {
                MenuBarPopup.endSystemPanelInteraction()
                completion(controls)
            }
        }
    }

    private static func readSynchronously(
        _ identifier: Identifier, path: [String], matching prefix: String
    ) -> [PanelControl] {
        guard let extra = element(for: identifier) else { return [] }
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
        // Pressable, because this is only ever called to press the result.
        // Identifiers are not unique inside a panel: Bluetooth labels both its
        // heading and the switch next to it `bluetooth-header`, and the label
        // comes first in the walk, so without this the switch would never be
        // the one found and the press would land on a piece of text.
        waitForControl(identifiedBy: { $0 == identifier }, pressable: true)
    }

    private static func waitForControl(
        identifiedBy matches: (String) -> Bool, pressable: Bool = false
    ) -> AXUIElement? {
        guard let application = controlCentreApplication() else { return nil }
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            for window in panels(of: application) {
                if let match = descendant(
                    of: window, matching: matches, pressable: pressable,
                    depth: 0)
                {
                    return match
                }
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return nil
    }

    /// Whether the element answers to a press at all, which is what separates a
    /// control from the text labelling it.
    private static func isPressable(_ element: AXUIElement) -> Bool {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success,
            let actions = names as? [String]
        else { return false }
        return actions.contains(kAXPressAction as String)
    }

    /// The first match in a depth-first walk.
    ///
    /// First, not any, matters: while a Focus is on, Control Center adds
    /// duration rows underneath it that carry the same identifier as the mode
    /// itself, and the mode is the one above them.
    private static func descendant(
        of element: AXUIElement, matching matches: (String) -> Bool,
        pressable: Bool, depth: Int
    ) -> AXUIElement? {
        // The panels are shallow, and a bound keeps a cycle in someone else's
        // hierarchy from becoming an infinite walk in this one.
        guard depth < 12 else { return nil }
        if let identifier = attribute(element, "AXIdentifier") as? String,
            matches(identifier), !pressable || isPressable(element)
        {
            return element
        }
        guard
            let children = attribute(element, kAXChildrenAttribute as String)
                as? [AXUIElement]
        else { return nil }
        for child in children {
            if let match = descendant(
                of: child, matching: matches, pressable: pressable,
                depth: depth + 1)
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

    static func element(for identifier: Identifier) -> AXUIElement? {
        guard let application = controlCentreApplication() else { return nil }
        // Menu bar extras hang off `AXExtrasMenuBar`, not `AXMenuBar`. The
        // latter is the application's own menus, which Control Center does not
        // publish, so reading it returns nothing at all.
        // The type is checked before the cast. This was a force cast on
        // whatever Control Center happened to return, and anything that was not
        // an element would have taken the application down with it.
        guard let barValue = attribute(application, "AXExtrasMenuBar"),
            CFGetTypeID(barValue) == AXUIElementGetTypeID()
        else { return nil }
        let bar = barValue as! AXUIElement
        guard
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
