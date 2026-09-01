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
/// The catch is that the panel has to exist. Closed, the process publishes only
/// its widgets, confirmed by dumping its windows, so the list cannot be read
/// cold without opening Notification Center.
///
/// So it is read once, shortly after launch, and kept current from there. Every
/// banner macOS draws is its own window in the same process, and a banner
/// publishes exactly what a row in the list does: the same identifier, the same
/// labelled title, subtitle and body, the same actions. Folding arriving
/// banners into the list means opening the popup opens nothing, which is the
/// whole point of the bell being in the bar rather than being a shortcut to the
/// panel. Opening Notification Center by hand is read too, so a list gone stale
/// corrects itself.
///
/// Dismissing and clearing are the real ones. Pressing an entry's last action
/// is what the close button on the notification does, and the button at the top
/// of the list is Clear All, so both go through macOS rather than hiding
/// anything locally. They are queued while the popup is open and pressed in one
/// visit once it has gone, so the row disappears the moment it is clicked and
/// the panel that has to be opened to press it is never on screen at the same
/// time as the popup.
final class NotificationCenterReader: ObservableObject {
    static let shared = NotificationCenterReader()

    @Published private(set) var notifications: [SystemNotification] = []
    @Published private(set) var isReading = false
    @Published private(set) var failure: String?
    /// Whether the one read at launch has landed. Until it does the list holds
    /// only what has arrived since, which is not the same as macOS holding
    /// nothing.
    private var hasSeeded = false
    /// Rows dismissed in the popup, waiting for their real close button.
    private var pendingDismissals: [String] = []
    private var pendingClearAll = false

    private var observer: AXObserver?

    private init() {}

    var isTrusted: Bool { AXIsProcessTrusted() }

    /// Whether the bell should show a dot.
    var hasAny: Bool { !notifications.isEmpty }

    // MARK: - Watching

    /// Notices notifications arriving. Notification Center draws each banner as
    /// a window in its own process and announces it, which is what keeps the
    /// list current between the one read at launch and the next one the user
    /// asks for.
    func startWatching() {
        guard observer == nil, isTrusted else { return }
        guard let centre = Self.centre() else { return }
        defer { seed() }

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
        // A banner and the panel are both titled `Notification Center`, so the
        // list is what tells them apart. The panel is the one carrying it, and
        // when it is opened by hand its list is right there to be taken rather
        // than asked for again.
        if Self.descendant(of: window, identifiedBy: Self.listIdentifier, depth: 0)
            != nil
        {
            let found = Self.parse(window)
            DispatchQueue.main.async {
                self.notifications = found
                self.hasSeeded = true
            }
            return
        }
        // Anything else is a banner arriving, carrying everything a row in the
        // list carries, so it goes straight into the list.
        let arriving = Self.parseArriving(in: window)
        guard !arriving.isEmpty else { return }
        DispatchQueue.main.async { self.merge(arriving) }
    }

    /// Folds arriving banners into the list. A banner publishes the identifier
    /// the panel does, so a second banner for a notification already listed
    /// replaces its entry instead of doubling it.
    private func merge(_ arriving: [SystemNotification]) {
        var merged = notifications
        for entry in arriving {
            merged.removeAll { $0.id == entry.id }
            merged.insert(entry, at: 0)
        }
        notifications = Array(merged.prefix(Self.limit))
    }

    /// The one read at launch, deferred so it lands after the bar has drawn and
    /// macOS has finished the login rush rather than in the middle of it.
    ///
    /// Asked again if it does not land. At login Notification Center's menu
    /// extra is often not there to be pressed three seconds in, and a read that
    /// misses would otherwise leave the list empty until a notification
    /// happened to arrive.
    private func seed(attempt: Int = 0) {
        guard !hasSeeded, attempt < 3 else { return }
        let delay = Double(3 * (attempt + 1))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.hasSeeded else { return }
            self.refresh()
            self.seed(attempt: attempt + 1)
        }
    }

    // MARK: - Reading

    /// Opens Notification Center, reads the list, closes it again. The one
    /// thing here that puts a panel on screen, so it runs at launch and then
    /// only when the user asks for it.
    func refresh() {
        guard !isReading, isTrusted else { return }
        isReading = true
        failure = nil
        MenuBarPopup.beginSystemPanelInteraction()
        DispatchQueue.global(qos: .userInitiated).async {
            let found = Self.readSynchronously()
            DispatchQueue.main.async {
                MenuBarPopup.endSystemPanelInteraction()
                self.isReading = false
                guard let found else {
                    self.failure = "Could not open Notification Center"
                    return
                }
                self.notifications = found
                self.hasSeeded = true
            }
        }
    }

    /// Dismisses one. The row leaves the list straight away and the real close
    /// button is pressed later, by `flushPending`, so clicking a row in the
    /// popup does what clicking a row anywhere does instead of dropping a
    /// system panel over the popup that asked for it.
    func dismiss(_ notification: SystemNotification) {
        notifications.removeAll { $0.id == notification.id }
        pendingDismissals.append(notification.id)
    }

    /// Clears the list, pressing Notification Center's own Clear All later, for
    /// the same reason.
    func clearAll() {
        notifications.removeAll()
        pendingDismissals.removeAll()
        pendingClearAll = true
    }

    /// Presses everything the popup queued, in one visit to the panel.
    ///
    /// Called as the popup goes away, which is the whole point: the panel macOS
    /// draws to be pressed appears once, after the thing it would have covered
    /// has gone, rather than once per row while it is still on screen.
    func flushPending() {
        guard !pendingDismissals.isEmpty || pendingClearAll else { return }
        // A read can still be in the panel, and `act` would turn straight back
        // around, dropping what the popup queued. Wait for it instead.
        guard !isReading else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                [weak self] in self?.flushPending()
            }
            return
        }
        let identifiers = pendingDismissals
        let clearing = pendingClearAll
        pendingDismissals = []
        pendingClearAll = false
        act { panel in
            if clearing {
                if let button = Self.clearAllButton(in: panel) {
                    AXUIElementPerformAction(button, kAXPressAction as CFString)
                }
                return
            }
            for identifier in identifiers {
                // Looked up again each time. Pressing one row rebuilds the
                // list, so elements found before the first press are not worth
                // holding on to.
                guard
                    let entry = Self.banners(in: panel).first(where: {
                        Self.string($0, "AXIdentifier") == identifier
                    })
                else { continue }
                Self.performLastAction(on: entry)
                Thread.sleep(forTimeInterval: 0.12)
            }
        }
    }

    /// Opens the panel, does something to it, closes it, and reads the result.
    private func act(_ body: @escaping (AXUIElement) -> Void) {
        guard !isReading, isTrusted else { return }
        isReading = true
        MenuBarPopup.beginSystemPanelInteraction()
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
                MenuBarPopup.endSystemPanelInteraction()
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
    /// The group the panel keeps its rows in, and the only thing that tells the
    /// panel apart from a banner, which carries the same window title.
    private static let listIdentifier = "AXNotificationListItems"
    private static let bannerSubrolePrefix = "AXNotificationCenterBanner"
    /// As many as are worth keeping. The popup shows the first handful, and a
    /// list that grows without bound is one more thing to leak.
    private static let limit = 32

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
        // A banner on screen is a window with the same title, so matching on
        // the title alone can hand back a banner and then wait for a panel that
        // is already open. The list is what only the panel has.
        return windows.first {
            string($0, kAXTitleAttribute as String) == panelTitle
                && descendant(of: $0, identifiedBy: listIdentifier, depth: 0)
                    != nil
        }
    }

    // MARK: - Parsing

    private static func parse(_ panel: AXUIElement) -> [SystemNotification] {
        entries(banners(in: panel), arrivedAt: nil)
    }

    /// The banners in a window Notification Center has just drawn. They sit
    /// under a scroll area rather than under the panel's list, so they are
    /// found by subrole wherever they are rather than by a known path.
    private static func parseArriving(in window: AXUIElement)
        -> [SystemNotification]
    {
        entries(
            bannerElements(under: window, depth: 0),
            arrivedAt: arrivalFormatter.string(from: Date()))
    }

    private static func entries(
        _ elements: [AXUIElement], arrivedAt: String?
    ) -> [SystemNotification] {
        elements.compactMap { entry in
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
                // A banner writes no timestamp, because it is arriving as it is
                // read. The panel would have written the clock time, so that is
                // what stands in until a read replaces it.
                time: untagged.last ?? arrivedAt ?? "")
        }
    }

    private static func bannerElements(
        under element: AXUIElement, depth: Int
    ) -> [AXUIElement] {
        guard depth < 8 else { return [] }
        if let subrole = string(element, kAXSubroleAttribute as String),
            subrole.hasPrefix(bannerSubrolePrefix)
        {
            return [element]
        }
        return children(of: element).flatMap {
            bannerElements(under: $0, depth: depth + 1)
        }
    }

    private static let arrivalFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

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
        guard
            let list = descendant(
                of: panel, identifiedBy: listIdentifier, depth: 0)
        else { return [] }
        return children(of: list).filter {
            guard let subrole = string($0, kAXSubroleAttribute as String)
            else { return false }
            return subrole.hasPrefix(bannerSubrolePrefix)
        }
    }

    /// The button above the list. Found by position rather than by its label,
    /// which is translated, and it carries no identifier of its own.
    private static func clearAllButton(in panel: AXUIElement) -> AXUIElement? {
        guard
            let list = descendant(
                of: panel, identifiedBy: listIdentifier, depth: 0)
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
