import AppKit
import ApplicationServices
import Combine

/// One notification Stege saw arrive.
struct NotificationEntry: Identifiable, Equatable {
    let id = UUID()
    let application: String
    let title: String
    let body: String
    let date: Date
}

/// A running list of the notifications that have come in, kept by Stege.
///
/// macOS's own list is not readable. There is no public API for it, the
/// database it used to live in is gone on macOS 26, the group container that
/// held it is empty, and the only place the list appears is inside the
/// Notification Center panel's own accessibility tree, which exists only while
/// that panel is on screen. Scraping it would mean throwing the real panel open
/// over a third of the display every time the list was refreshed, which is
/// worse than not having it.
///
/// What is readable is a notification *arriving*. Notification Center draws
/// each banner as a window in its own process, and that process publishes its
/// windows over the Accessibility API that the bar already holds. So this
/// watches for those windows and keeps what it reads out of them.
///
/// Two honest limits, both of which the popup says out loud. The list starts
/// when Stege starts, so anything delivered before that is not in it. And
/// clearing is Stege's own list, not macOS's, because nothing here can write to
/// macOS's.
final class NotificationLog: ObservableObject {
    static let shared = NotificationLog()

    @Published private(set) var entries: [NotificationEntry] = []

    /// Enough to be a history, few enough that the popup does not become a
    /// scrolling wall.
    private let limit = 50

    /// The windows Notification Center keeps open all the time: the panel
    /// itself and the widgets in it. None of them is a notification.
    private static let ignoredTitles: Set<String> = ["Notification Center"]

    private var observer: AXObserver?
    private var application: AXUIElement?

    private init() {}

    var isTrusted: Bool { AXIsProcessTrusted() }

    /// Starts watching, once. Safe to call from a view's `onAppear`.
    func start() {
        guard observer == nil, isTrusted else { return }
        guard
            let centre = NSWorkspace.shared.runningApplications.first(where: {
                $0.bundleIdentifier == "com.apple.notificationcenterui"
            })
        else { return }

        let element = AXUIElementCreateApplication(centre.processIdentifier)
        var created: AXObserver?
        let callback: AXObserverCallback = { _, window, _, context in
            guard let context else { return }
            Unmanaged<NotificationLog>.fromOpaque(context)
                .takeUnretainedValue()
                .windowAppeared(window)
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
        application = element
    }

    func clear() {
        entries = []
    }

    func remove(_ entry: NotificationEntry) {
        entries.removeAll { $0.id == entry.id }
    }

    // MARK: - Reading

    private func windowAppeared(_ window: AXUIElement) {
        let title = string(window, kAXTitleAttribute as String) ?? ""
        guard !Self.ignoredTitles.contains(title) else { return }
        // The widget windows carry an identifier of their own, and the panel
        // republishes them whenever it opens.
        if let identifier = string(window, "AXIdentifier"),
            identifier.hasPrefix("widget-local:")
        {
            return
        }

        var lines: [String] = []
        collect(from: window, into: &lines, depth: 0)
        // A banner always says something. A window with nothing readable in it
        // is one of Notification Center's own, not a notification.
        guard !lines.isEmpty else { return }

        let entry = NotificationEntry(
            application: title.isEmpty ? lines[0] : title,
            title: lines[0],
            body: lines.dropFirst().joined(separator: " "),
            date: Date())

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Notification Center redraws a banner as it animates, so the same
            // one can arrive twice within a moment.
            if let last = self.entries.first, last.title == entry.title,
                last.body == entry.body,
                entry.date.timeIntervalSince(last.date) < 2
            {
                return
            }
            self.entries.insert(entry, at: 0)
            if self.entries.count > self.limit {
                self.entries.removeLast(self.entries.count - self.limit)
            }
        }
    }

    /// Every piece of text in the window, in the order it is laid out, which
    /// for a banner is the application, then the title, then the body.
    private func collect(
        from element: AXUIElement, into lines: inout [String], depth: Int
    ) {
        guard depth < 10 else { return }
        if let role = string(element, kAXRoleAttribute as String),
            role == kAXStaticTextRole as String,
            let value = string(element, kAXValueAttribute as String)
        {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { lines.append(trimmed) }
        }
        var children: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element, kAXChildrenAttribute as CFString, &children)
                == .success,
            let list = children as? [AXUIElement]
        else { return }
        for child in list { collect(from: child, into: &lines, depth: depth + 1) }
    }

    private func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element, attribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }
}
