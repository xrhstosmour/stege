import AppKit
import ApplicationServices

/// Presses one of macOS's own menu bar extras through the Accessibility API.
///
/// This is how Stege reaches Notification Center and Control Center without
/// reimplementing either. Neither has a public API, a URL scheme, or an
/// application that can be opened, and the only other route to their contents
/// is the private database behind Full Disk Access. Pressing the system's own
/// control means macOS draws the real panel, with its real contents, its own
/// clear and dismiss behaviour, and no extra permission beyond the
/// Accessibility access the app menus already require.
enum MenuExtra {
    /// Identifiers rather than descriptions. `AXDescription` is localised, so
    /// matching "Clock" works only in English, while these are stable.
    enum Identifier: String {
        case notificationCentre = "com.apple.menuextra.clock"
        case controlCentre = "com.apple.menuextra.controlcenter"
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

    private static func element(for identifier: Identifier) -> AXUIElement? {
        guard
            let controlCentre = NSWorkspace.shared.runningApplications.first(
                where: { $0.bundleIdentifier == "com.apple.controlcenter" })
        else { return nil }

        let application = AXUIElementCreateApplication(
            controlCentre.processIdentifier)
        // Menu bar extras hang off `AXExtrasMenuBar`, not `AXMenuBar`. The
        // latter is the application's own menus, which Control Center does not
        // publish, so reading it returns nothing at all.
        guard
            let bar = copy(application, "AXExtrasMenuBar") as! AXUIElement?,
            let items = copy(bar, kAXChildrenAttribute as String)
                as? [AXUIElement]
        else { return nil }

        return items.first {
            copy($0, "AXIdentifier") as? String == identifier.rawValue
        }
    }

    private static func copy(_ element: AXUIElement, _ name: String)
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
