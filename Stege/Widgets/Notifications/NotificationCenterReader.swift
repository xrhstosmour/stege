import AppKit
import ApplicationServices
import Combine

/// One notification sitting in Notification Center.
struct SystemNotification: Identifiable, Equatable, Codable {
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

/// What macOS has shown a banner for since Stege started.
///
/// Every banner is its own window in Notification Center's process, announced
/// as it is created, and it publishes everything a row in the panel's own list
/// does: a stable identifier, the application name, the title, subtitle and
/// body as separately labelled text, and the timestamp as macOS formatted it.
/// So watching for those windows collects the list without asking macOS for
/// anything. Nothing here opens a panel, presses a control, or moves the
/// pointer. If the user opens Notification Center themselves, that window is
/// read too, because it is already on screen.
///
/// This used to open the panel to read it, and again to dismiss a row or clear
/// the list, which put a system panel on screen every time. That is gone.
///
/// Two other routes exist and are both worse:
///
/// - `~/Library/Group Containers/group.com.apple.usernoted/db2/db` is real and
///   current, contrary to what this comment used to claim, and holds every
///   notification in a `record` table. Reading it needs Full Disk Access, the
///   broadest permission macOS grants, which would also hand this app Mail,
///   Messages and Safari history. Not worth a list in a menu bar.
/// - `UNUserNotificationCenter` only ever reports the calling application's own
///   notifications.
///
/// The cost is honest and worth stating: a notification that arrived before
/// Stege started, or one macOS delivered without drawing a banner, is not in
/// the list at all.
final class NotificationCenterReader: ObservableObject {
    static let shared = NotificationCenterReader()

    @Published private(set) var notifications: [SystemNotification] = [] {
        didSet { if remembersBetweenLaunches { Self.store(notifications) } }
    }

    /// Whether the list survives a restart.
    ///
    /// Off by default, and this is the reason: remembering means writing every
    /// notification's title, subtitle and body to
    /// `~/Library/Preferences`, in plaintext, where anything running as this
    /// user can read them. Message previews are exactly the kind of thing this
    /// app refuses Full Disk Access to avoid reading, so it does not leave them
    /// lying around either. Turned on, a restart keeps what was collected;
    /// left off, the bell starts empty and fills as banners arrive.
    var remembersBetweenLaunches = false {
        didSet {
            if remembersBetweenLaunches {
                if notifications.isEmpty { notifications = Self.stored() }
            } else {
                // Not guarded on the value having changed. The widget sets this
                // on every appearance, and it starts false, so a guard meant
                // that anything written by an earlier version stayed on disk
                // forever: the one thing switching it off is supposed to undo.
                Self.discardStored()
            }
        }
    }
    /// Where the list is kept when the option above is on, so a restart does
    /// not throw away everything collected and leave the bell blank until a
    /// notification happens to arrive.
    private static let storageKey = "stege.notifications.list"
    private var observer: AXObserver?

    private init() {}

    var isTrusted: Bool { AXIsProcessTrusted() }

    /// Whether the bell should show a dot.
    var hasAny: Bool { !notifications.isEmpty }

    // MARK: - Watching

    /// Notices notifications arriving. Notification Center draws each banner as
    /// a window in its own process and announces it, and that announcement is
    /// the only thing that ever fills this list.
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
        // A banner and the panel are both titled `Notification Center`, so the
        // size is what tells them apart. See `isPanel`. When the panel is
        // opened by hand its list is right there to be taken rather than asked
        // for again.
        if Self.isPanel(window) {
            let found = Self.parse(window)
            DispatchQueue.main.async {
                self.notifications = found
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

    // MARK: - Forgetting

    /// Takes an entry off Stege's own list. macOS keeps its copy.
    ///
    /// Not a dismissal. Dismissing for real means pressing the close button on
    /// Notification Center's own row, which means opening its panel, which is
    /// the thing this widget no longer does. What is honest is to say the list
    /// is Stege's: clearing it here is tidying what the bell shows, and
    /// Notification Center still holds what it held.
    func forget(_ notification: SystemNotification) {
        notifications.removeAll { $0.id == notification.id }
    }

    /// Empties Stege's own list, for the same reason.
    func forgetAll() {
        notifications.removeAll()
    }


    private static let panelTitle = "Notification Center"
    /// The group the panel keeps its rows in, and the only thing that tells the
    /// panel apart from a banner, which carries the same window title.
    private static let listIdentifier = "AXNotificationListItems"
    private static let bannerSubrolePrefix = "AXNotificationCenterBanner"
    /// As many as are worth keeping. The popup shows the first handful, and a
    /// list that grows without bound is one more thing to leak.
    private static let limit = 32

    private static func isPanel(_ window: AXUIElement) -> Bool {
        guard string(window, kAXTitleAttribute as String) == panelTitle,
            let height = size(of: window)?.height
        else { return false }
        return height >= Self.tallestDisplayHeight / 2
    }

    /// Read through `CoreGraphics` rather than `NSScreen`, because the panel is
    /// looked for on a background queue and `NSScreen` belongs to the main one.
    private static var tallestDisplayHeight: CGFloat {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0
        else { return 0 }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success
        else { return 0 }
        return displays.map { CGDisplayBounds($0).height }.max() ?? 0
    }

    private static func size(of element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element, kAXSizeAttribute as CFString, &value) == .success,
            let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        var size = CGSize.zero
        AXValueGetValue(value as! AXValue, .cgSize, &size)
        return size
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

    // MARK: - Storage

    private static func stored() -> [SystemNotification] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
            let list = try? JSONDecoder().decode(
                [SystemNotification].self, from: data)
        else { return [] }
        return list
    }

    private static func store(_ list: [SystemNotification]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    /// Clears what an earlier run may have written, so switching the option off
    /// takes the text off disk rather than only stopping new writes.
    private static func discardStored() {
        UserDefaults.standard.removeObject(forKey: storageKey)
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
