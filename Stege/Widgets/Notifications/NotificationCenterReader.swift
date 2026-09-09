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
    /// The process `observer` was created against, kept alongside it so a
    /// teardown can address the right process rather than whatever `centre()`
    /// happens to return by the time it runs.
    private var observedProcessIdentifier: pid_t?
    private var retryTimer: Timer?
    /// Watches for Notification Center's own process restarting, so a crash,
    /// a macOS update, or an MDM-triggered relaunch after `startWatching()`
    /// already attached an observer does not leave the bell silently dead for
    /// the rest of the run: `observer` would otherwise still be non-`nil` and
    /// pointing at a process that is gone.
    private var workspaceObservers: [NSObjectProtocol] = []

    private init() {}

    deinit {
        retryTimer?.invalidate()
        workspaceObservers.forEach {
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
    }

    var isTrusted: Bool { AXIsProcessTrusted() }

    /// Whether the bell should show a dot.
    var hasAny: Bool { !notifications.isEmpty }

    // MARK: - Watching

    /// Notices notifications arriving. Notification Center draws each banner as
    /// a window in its own process and announces it, and that announcement is
    /// the only thing that ever fills this list.
    func startWatching() {
        watchForRestart()
        guard observer == nil else { return }
        guard isTrusted else {
            Log.notifications.notice(
                "Not watching: Accessibility is not trusted")
            startRetryingIfNeeded()
            return
        }
        // Notification Center's process is not always up yet the one time this
        // is called, from the widget's own `onAppear`, and nothing posts a
        // notification back once it is, so without a retry a launch that beat
        // it left every banner uncaught for the rest of the run.
        guard let centre = Self.centre() else {
            Log.notifications.notice(
                "Not watching: Notification Center's process is not running")
            startRetryingIfNeeded()
            return
        }

        let pid = centre.processIdentifier
        let element = AXUIElementCreateApplication(pid)
        var created: AXObserver?
        let callback: AXObserverCallback = { _, window, _, context in
            guard let context else { return }
            let reader = Unmanaged<NotificationCenterReader>
                .fromOpaque(context).takeUnretainedValue()
            reader.windowAppeared(window)
        }
        guard
            AXObserverCreate(pid, callback, &created) == .success,
            let created
        else {
            Log.notifications.error(
                "AXObserverCreate failed, pid \(pid, privacy: .public)")
            startRetryingIfNeeded()
            return
        }

        AXObserverAddNotification(
            created, element, kAXWindowCreatedNotification as CFString,
            Unmanaged.passUnretained(self).toOpaque())
        CFRunLoopAddSource(
            CFRunLoopGetMain(), AXObserverGetRunLoopSource(created),
            .defaultMode)
        observer = created
        observedProcessIdentifier = pid
        retryTimer?.invalidate()
        retryTimer = nil
        Log.notifications.notice(
            "Watching Notification Center, pid \(pid, privacy: .public)")
    }

    /// Drops the current observer, unregistering it from the run loop and the
    /// process it was watching first. `CFRunLoopAddSource` retains its source,
    /// which retains the observer, so clearing the property alone leaks both
    /// and leaves a dead source registered against a pid that is gone.
    private func detachObserver() {
        guard let observer, let pid = observedProcessIdentifier else {
            return
        }
        let element = AXUIElementCreateApplication(pid)
        AXObserverRemoveNotification(
            observer, element, kAXWindowCreatedNotification as CFString)
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer),
            .defaultMode)
        self.observer = nil
        observedProcessIdentifier = nil
    }

    /// Re-attaches if Notification Center's own process restarts. Without
    /// this, `observer` stays non-`nil` and pointing at a dead process, so
    /// `startWatching()`'s own guard would skip re-creating it forever.
    private func watchForRestart() {
        guard workspaceObservers.isEmpty else { return }
        workspaceObservers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification,
                object: nil, queue: .main
            ) { [weak self] notification in
                guard
                    let application = notification.userInfo?[
                        NSWorkspace.applicationUserInfoKey]
                        as? NSRunningApplication,
                    application.bundleIdentifier
                        == Self.notificationCenterBundleIdentifier
                else { return }
                Log.notifications.notice(
                    "Notification Center's process terminated, will retry attaching"
                )
                // Not `startWatching()` directly: `NSWorkspace.runningApplications`
                // is a cached snapshot that can still list the dying process
                // for a moment, and the replacement is not up yet either.
                // Attaching to either produces an observer that never fires
                // again, silently, which is the exact bug this is fixing.
                // The retry timer waits it out instead.
                self?.detachObserver()
                self?.startRetryingIfNeeded()
            })
    }

    /// Retries until watching actually starts. Granting Accessibility happens
    /// outside the app and posts no notification, the same reason
    /// `AppMenusManager` polls for it, and Notification Center's own process
    /// can equally not be running yet at launch.
    private func startRetryingIfNeeded() {
        guard retryTimer == nil else { return }
        Log.notifications.notice("Retrying every 2s until watching starts")
        retryTimer = Timer.scheduledTimer(
            withTimeInterval: 2.0, repeats: true
        ) { [weak self] _ in
            self?.startWatching()
        }
    }

    /// Tells a banner from the real panel by what is inside it rather than by
    /// its size. Both used to carry the same window title with only the
    /// panel tall enough to fill half the screen, but on some macOS versions
    /// a single banner's window reports that same full-screen height, which
    /// made every banner misread as an empty panel and dropped silently.
    /// `Self.parse` returns `nil`, not an empty array, when the window is not
    /// the panel at all, so a genuinely empty panel still clears the list
    /// instead of being indistinguishable from a banner carrying nothing. Both
    /// searches move off this, the observer callback's own thread: the panel
    /// search only looks a fixed few levels down when the window actually is
    /// the panel, but walks the whole subtree, up to the same depth an
    /// Electron banner needs its own search to reach, before giving up when it
    /// is not, which is every banner, so it is not cheap enough to run on the
    /// main thread unconditionally.
    private func windowAppeared(_ window: AXUIElement) {
        DispatchQueue.global(qos: .userInitiated).async {
            if let found = Self.parse(window) {
                Log.notifications.notice(
                    "Notification list read, \(found.count, privacy: .public) entries"
                )
                DispatchQueue.main.async { self.notifications = found }
                return
            }
            let arriving = Self.parseArriving(in: window)
            guard !arriving.isEmpty else {
                Log.notifications.notice(
                    "Notification window appeared but nothing was parsed from it"
                )
                return
            }
            Log.notifications.notice(
                "Banner arrived, parsed \(arriving.count, privacy: .public) entries"
            )
            DispatchQueue.main.async { self.merge(arriving) }
        }
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


    private static let notificationCenterBundleIdentifier =
        "com.apple.notificationcenterui"
    /// The group the panel keeps its rows in, the marker `windowAppeared`
    /// uses to tell it apart from a banner.
    private static let listIdentifier = "AXNotificationListItems"
    private static let bannerSubrolePrefix = "AXNotificationCenterBanner"
    /// How deep a banner's own accessibility tree is searched, for its subrole
    /// and for its text. A native app's banner is a handful of levels deep, but
    /// an Electron/Chromium one, Slack among them, wraps its content in enough
    /// extra layers that 8 gave up before reaching either, and the banner was
    /// silently skipped as if it carried nothing at all.
    private static let maximumSearchDepth = 16
    /// As many as are worth keeping. The popup shows the first handful, and a
    /// list that grows without bound is one more thing to leak.
    private static let limit = 32

    // MARK: - Parsing

    /// `nil` when `panel` is not the real panel at all, an empty array when it
    /// is and simply has nothing in it. Collapsing those two into one empty
    /// array is what let a banner misread as the panel drop every entry it
    /// carried, the bug this file exists to fix.
    private static func parse(_ panel: AXUIElement) -> [SystemNotification]? {
        guard
            let list = descendant(
                of: panel, identifiedBy: listIdentifier, depth: 0)
        else { return nil }
        return entries(banners(in: list), arrivedAt: nil)
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
                Log.notifications.notice(
                    "Dropped a banner element with no AXIdentifier")
                return nil
            }
            var labelled: [String: String] = [:]
            var untagged: [String] = []
            collectText(entry, into: &labelled, untagged: &untagged, depth: 0)

            let title = labelled["title"] ?? untagged.first ?? ""
            guard !title.isEmpty else {
                // `identifier` is not marked `.public`: it is text the
                // notifying application supplied, not something this app
                // controls, so it is not known safe for a system-wide log.
                Log.notifications.notice(
                    "Dropped a banner with no readable title text, id \(identifier)"
                )
                return nil
            }
            return SystemNotification(
                id: identifier,
                application: application(of: entry, fallback: title),
                title: title,
                subtitle: labelled["subtitle"] ?? "",
                body: labelled["body"] ?? "",
                // A banner writes no timestamp, because it is arriving as it is
                // read, so `arrivedAt` stands in for one until a read replaces
                // it. Checked first: an Electron banner's untagged text can
                // otherwise win by being non-empty, and it is prose, not a
                // time.
                time: arrivedAt ?? untagged.last ?? "")
        }
    }

    private static func bannerElements(
        under element: AXUIElement, depth: Int
    ) -> [AXUIElement] {
        guard depth < maximumSearchDepth else { return [] }
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

    /// One element per notification, out of the panel's own list. A stack,
    /// where several from the same application are collapsed together, has
    /// its own subrole and is treated as the one entry macOS is showing.
    private static func banners(in list: AXUIElement) -> [AXUIElement] {
        children(of: list).filter {
            guard let subrole = string($0, kAXSubroleAttribute as String)
            else { return false }
            return subrole.hasPrefix(bannerSubrolePrefix)
        }
    }

    private static func collectText(
        _ element: AXUIElement, into labelled: inout [String: String],
        untagged: inout [String], depth: Int
    ) {
        guard depth < maximumSearchDepth else { return }
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
            $0.bundleIdentifier == notificationCenterBundleIdentifier
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
