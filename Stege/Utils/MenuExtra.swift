import AppKit
import ApplicationServices

/// Finds a menu bar status item and presses it, through the Accessibility API.
///
/// What is left of a much larger thing. This used to open Control Center and
/// Notification Center, step into their panels, read lists out of them and
/// press switches inside them, which is how Low Power Mode, the Focus modes,
/// the AirPlay picker and the notification list all worked. Every one of them
/// put a system panel on screen to do it, and all of them have been removed
/// for exactly that.
///
/// Nothing here opens a panel by itself any more. `press` is only ever called
/// because the user pressed something: the Control Center button the bell can
/// be configured to draw, and a borrowed status item in the reveal row, which
/// is that application's own item and opens that application's own menu.
/// `element(for:)` reads the menu bar without pressing anything at all.
enum MenuExtra {
    /// Identifiers rather than descriptions. `AXDescription` is localised, so
    /// matching "Clock" works only in English, while these are stable.
    enum Identifier: String {
        case notificationCentre = "com.apple.menuextra.clock"
        case controlCentre = "com.apple.menuextra.controlcenter"
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
