import AppKit
import ApplicationServices
import Combine

/// One notification sitting in Notification Center.
struct SystemNotification: Identifiable, Equatable {
    /// Notification Center's own identifier for it, which is stable across
    /// reads and is what dismissing one is keyed on.
    let id: String
    let application: String
    let title: String
    let subtitle: String
    let body: String
    /// The time exactly as macOS wrote it, "11:35" or "Yesterday, 20:46". Not
    /// re-derived, because Notification Center is the one that knows.
    let time: String
}

/// The notifications macOS is holding, read out of Notification Center itself.
///
/// There is no public API for this list and no file to read: the database it
/// used to live in is gone on macOS 26 and the group container that held it is
/// empty. What there is, is Notification Center's own accessibility tree, which
/// is complete. Its panel publishes a group identified `AXNotificationListItems`
/// holding one element per notification, each carrying a stable identifier, the
/// application name, the title, subtitle and body as separately labelled text,
/// the timestamp as macOS formatted it, and the actions to dismiss it. There is
/// a Clear All button beside them.
///
/// The catch is that the panel has to exist. When it is closed the process
/// publishes only its widgets, so a read opens Notification Center, takes what
/// it needs, and closes it again, which is the same thing the Focus list does
/// with Control Center. That is why the list is read when the popup opens
/// rather than on a timer.
///
/// Dismissing and clearing are the real ones. Pressing an entry's last action
/// is what the close button on the notification does, and the button at the top
/// of the list is Clear All, so both go through macOS rather than hiding
/// anything locally.
final class NotificationCenterReader: ObservableObject {
    static let shared = NotificationCenterReader()

    @Published private(set) var notifications: [SystemNotification] = []
    @Published private(set) var isReading = false
    /// Set when a banner appears while the popup is closed, so the bell can
    /// show a dot without opening Notification Center to find out.
    @Published private(set) var hasArrived = false
    @Published private(set) var failure: String?

    private var observer: AXObserver?

    private init() {}

    var isTrusted: Bool { AXIsProcessTrusted() }

    /// Whether the bell should show a dot.
    var hasAny: Bool { hasArrived || !notifications.isEmpty }

    // MARK: - Watching

    /// Notices notifications arriving, which is the only part that can be known
    /// without opening anything. Notification Center draws each banner as a
    /// window in its own process and announces it.
    func startWatching() {
        guard observer == nil, isTrusted else { return }
        guard let centre = Self.centre() else { return }

        let element = AXUIElementCreateApplication(centre.processIdentifier)
        var created: AXObserver?
        let callback: AXObserverCallback = { _, window, _, context in
            guard let context else { return }
            let reader = Unmanaged<NotificationCenterReader>
                .fromOpaque(context).takeUnretainedValue()
            reader.windowAppeared(window)
        }
        guard
            AXObserverCreate(
                centre.processIdentifier, callback, &created) == .success,
            let created
        else { return }

        AXObserverAddNotification(
            created, element, kAXWindowCreatedNotification as CFString,
            Unmanaged.passUnretained(self).toOpaque())
        CFRunLoopAddSource(
            CFRunLoopGetMain(), AXObserverGetRunLoopSource(created),
            .defaultMode)
        observer = created
    }

    private func windowAppeared(_ window: AXUIElement) {
        // The panel itself, opened by hand rather than by this class. Its list
        // is right there, so it is taken rather than asked for again.
        if Self.string(window, kAXTitleAttribute as String) == Self.panelTitle {
            let found = Self.parse(window)
            DispatchQueue.main.async {
                self.notifications = found
                self.hasArrived = false
            }
            return
        }
        // Anything else Notification Center draws with text in it is a banner.
        guard Self.hasText(window) else { return }
        DispatchQueue.main.async { self.hasArrived = true }
    }

    // MARK: - Reading

    func refresh() {
        guard !isReading, isTrusted else { return }
        isReading = true
        failure = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let found = Self.readSynchronously()
            DispatchQueue.main.async {
                self.isReading = false
                guard let found else {
                    self.failure = "Could not open Notification Center"
                    return
                }
                self.notifications = found
                self.hasArrived = false
            }
        }
    }

    /// Dismisses one, the way its own close button does.
    func dismiss(_ notification: SystemNotification) {
        act { panel in
            guard
                let entry = Self.banners(in: panel).first(where: {
                    Self.string($0, "AXIdentifier") == notification.id
                })
            else { return }
            Self.performLastAction(on: entry)
        }
    }

    /// Presses Notification Center's own Clear All.
    func clearAll() {
        act { panel in
            guard let button = Self.clearAllButton(in: panel) else { return }
            AXUIElementPerformAction(button, kAXPressAction as CFString)
        }
    }

    /// Opens the panel, does something to it, closes it, and reads the result.
    private func act(_ body: @escaping (AXUIElement) -> Void) {
        guard !isReading, isTrusted else { return }
        isReading = true
        DispatchQueue.global(qos: .userInitiated).async {
            var found: [SystemNotification] = []
            Self.withPanel { panel in
                body(panel)
                // Long enough for the row to leave the list before it is read
                // back, short enough not to be felt.
                Thread.sleep(forTimeInterval: 0.25)
                found = Self.parse(panel)
            }
            DispatchQueue.main.async {
                self.isReading = false
                self.notifications = found
            }
        }
    }

    /// Nil when the panel never opened, which is different from an empty list
    /// and is worth saying so on screen.
    private static func readSynchronously() -> [SystemNotification]? {
        var found: [SystemNotification]?
        withPanel { panel in found = parse(panel) }
        return found
    }

    /// Opens Notification Center, hands the panel over, and closes it again.
    ///
    /// Closed however this ends. A panel left open covers a third of the screen
    /// and sits on top of the popup that asked for it.
    private static func withPanel(_ body: (AXUIElement) -> Void) {
        guard let extra = MenuExtra.element(for: .notificationCentre) else {
            return
        }
        // The extra does not answer to a press while it is parked off screen,
        // unlike another application's status item.
        let pointer = MenuExtra.revealMenuBarIfHidden(for: extra)
        defer { pointer.map(MenuExtra.restorePointer) }

        guard
            AXUIElementPerformAction(extra, kAXPressAction as CFString)
                == .success
        else { return }
        defer { close(extra) }

        guard let panel = waitForPanel() else { return }
        body(panel)
    }

    private static func close(_ extra: AXUIElement) {
        for _ in 0..<3 {
            guard findPanel() != nil else { return }
            AXUIElementPerformAction(extra, kAXPressAction as CFString)
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    private static func waitForPanel() -> AXUIElement? {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if let panel = findPanel() { return panel }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return nil
    }

    private static let panelTitle = "Notification Center"

    private static func findPanel() -> AXUIElement? {
        guard let centre = centre() else { return nil }
        let application = AXUIElementCreateApplication(centre.processIdentifier)
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                application, kAXWindowsAttribute as CFString, &value)
                == .success,
            let windows = value as? [AXUIElement]
        else { return nil }
        return windows.first {
            string($0, kAXTitleAttribute as String) == panelTitle
        }
    }

    // MARK: - Parsing

    private static func parse(_ panel: AXUIElement) -> [SystemNotification] {
        banners(in: panel).compactMap { entry in
            guard let identifier = string(entry, "AXIdentifier") else {
                return nil
            }
            var labelled: [String: String] = [:]
            var untagged: [String] = []
            collectText(entry, into: &labelled, untagged: &untagged, depth: 0)

            let title = labelled["title"] ?? untagged.first ?? ""
            guard !title.isEmpty else { return nil }
            return SystemNotification(
                id: identifier,
                application: application(of: entry, fallback: title),
                title: title,
                subtitle: labelled["subtitle"] ?? "",
                body: labelled["body"] ?? "",
                time: untagged.last ?? "")
        }
    }

    /// The application's name is the first thing in the element's description,
    /// which reads "Amphetamine, Amphetamine is keeping your Mac awake, …".
    private static func application(
        of entry: AXUIElement, fallback: String
    ) -> String {
        guard
            let description = string(entry, kAXDescriptionAttribute as String),
            let first = description.split(separator: ",").first
        else { return fallback }
        return first.trimmingCharacters(in: .whitespaces)
    }

    /// One element per notification. A stack, where several from the same
    /// application are collapsed together, has its own subrole and is treated
    /// as the one entry macOS is showing.
    private static func banners(in panel: AXUIElement) -> [AXUIElement] {
        guard let list = descendant(of: panel, identifiedBy: "AXNotificationListItems", depth: 0)
        else { return [] }
        return children(of: list).filter {
            guard let subrole = string($0, kAXSubroleAttribute as String)
            else { return false }
            return subrole.hasPrefix("AXNotificationCenterBanner")
        }
    }

    /// The button above the list. Found by position rather than by its label,
    /// which is translated, and it carries no identifier of its own.
    private static func clearAllButton(in panel: AXUIElement) -> AXUIElement? {
        guard let list = descendant(of: panel, identifiedBy: "AXNotificationListItems", depth: 0)
        else { return nil }
        return children(of: list).first {
            string($0, kAXRoleAttribute as String) == (kAXButtonRole as String)
        }
    }

    /// A notification's own dismissal, which macOS puts last in its action
    /// list: `Close` on a single one, `Clear All` on a stack. Taken by position
    /// because the names are translated, and the first action is always
    /// `AXPress`, which opens the notification rather than dismissing it.
    private static func performLastAction(on entry: AXUIElement) {
        var value: CFArray?
        guard AXUIElementCopyActionNames(entry, &value) == .success,
            let actions = value as? [String], actions.count > 1,
            let last = actions.last, last != (kAXPressAction as String)
        else { return }
        AXUIElementPerformAction(entry, last as CFString)
    }

    private static func collectText(
        _ element: AXUIElement, into labelled: inout [String: String],
        untagged: inout [String], depth: Int
    ) {
        guard depth < 8 else { return }
        if string(element, kAXRoleAttribute as String)
            == (kAXStaticTextRole as String),
            let value = string(element, kAXValueAttribute as String)
        {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                if let key = string(element, "AXIdentifier") {
                    labelled[key] = trimmed
                } else {
                    untagged.append(trimmed)
                }
            }
        }
        for child in children(of: element) {
            collectText(
                child, into: &labelled, untagged: &untagged, depth: depth + 1)
        }
    }

    private static func hasText(_ element: AXUIElement, depth: Int = 0) -> Bool {
        guard depth < 6 else { return false }
        if string(element, kAXRoleAttribute as String)
            == (kAXStaticTextRole as String)
        {
            return true
        }
        return children(of: element).contains { hasText($0, depth: depth + 1) }
    }

    // MARK: - Accessibility

    private static func centre() -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == "com.apple.notificationcenterui"
        }
    }

    private static func descendant(
        of element: AXUIElement, identifiedBy identifier: String, depth: Int
    ) -> AXUIElement? {
        guard depth < 10 else { return nil }
        if string(element, "AXIdentifier") == identifier { return element }
        for child in children(of: element) {
            if let match = descendant(
                of: child, identifiedBy: identifier, depth: depth + 1)
            {
                return match
            }
        }
        return nil
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element, kAXChildrenAttribute as CFString, &value) == .success
        else { return [] }
        return (value as? [AXUIElement]) ?? []
    }

    private static func string(_ element: AXUIElement, _ attribute: String)
        -> String?
    {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element, attribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }
}
