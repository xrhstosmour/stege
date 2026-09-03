import AppKit
import ApplicationServices
import CoreGraphics

/// Puts back the windows the window manager has stopped reporting.
///
/// `AeroSpace` drops a window from `list-windows --all` the moment it is
/// minimized, and exposes no placeholder to ask about one, so minimizing a
/// window took it off its workspace pill and minimizing the last one took the
/// whole workspace off the bar. `MinimizedWindowLedger` decides what is still
/// real; this asks the window server and the accessibility API on its behalf.
///
/// Everything here runs on the one background queue that refreshes the
/// workspaces, and nothing else touches it.
final class MinimizedWindowMemory {
    static let shared = MinimizedWindowMemory()

    private static let storageKey = "stege.minimizedWindows"

    /// Kept across launches so an application update does not lose every window
    /// that happened to be minimized at the time.
    private var notes: [Int: MinimizedWindowNote] = [:]

    private init() {
        guard
            let data = UserDefaults.standard.data(forKey: Self.storageKey),
            let stored = try? JSONDecoder().decode(
                [MinimizedWindowNote].self, from: data)
        else { return }
        notes = Dictionary(
            stored.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Notes where every reported window is, then draws back the ones that have
    /// gone missing since the last pass and still exist.
    func reconcile(_ spaces: [AnySpace]) -> [AnySpace] {
        let reported = spaces.flatMap { space in
            space.windows.map { window in
                MinimizedWindowNote(
                    id: window.id,
                    workspace: space.id,
                    title: window.title,
                    appName: window.appName,
                    bundleID: window.bundleID,
                    monitorScreenID: space.monitorScreenID)
            }
        }

        guard
            MinimizedWindowLedger.hasUnreported(notes: notes, reported: reported)
        else {
            store(MinimizedWindowLedger.noting(notes, reported: reported))
            return spaces
        }

        let outcome = MinimizedWindowLedger.reconcile(
            notes: notes, reported: reported,
            liveOwners: Self.liveWindowOwners(),
            minimizedTitles: Self.minimizedWindowTitles(
                for: MinimizedWindowLedger.unreportedOwners(
                    notes: notes, reported: reported)))
        store(outcome.keep)

        guard !outcome.restore.isEmpty else { return spaces }
        return Self.insert(outcome.restore, into: spaces)
    }

    private func store(_ value: [Int: MinimizedWindowNote]) {
        guard value != notes else { return }
        notes = value
        guard let data = try? JSONEncoder().encode(Array(value.values)) else {
            return
        }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    /// Every ordinary window on the system, by identifier, with the name of the
    /// application that owns it. Layer zero only, which drops the panels,
    /// tooltips and helper windows no window manager reports either.
    ///
    /// This asks for no window titles, so it needs no Screen Recording
    /// permission.
    private static func liveWindowOwners() -> [Int: String] {
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard
            let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
                as? [[String: Any]]
        else { return [:] }

        var owners: [Int: String] = [:]
        for entry in list {
            guard entry[kCGWindowLayer as String] as? Int == 0 else { continue }
            guard let id = entry[kCGWindowNumber as String] as? Int else {
                continue
            }
            owners[id] = entry[kCGWindowOwnerName as String] as? String ?? ""
        }
        return owners
    }

    /// What each named application says is minimized right now, by title.
    ///
    /// The window server cannot answer this. Closing a window does not destroy
    /// it, so a closed window sits in the list at layer zero and off screen for
    /// as long as its application runs, indistinguishable from a minimized one.
    /// An application's own window list does not contain a closed window at
    /// all, and marks the minimized ones, so it can tell them apart.
    ///
    /// Asked only of the applications that own a note missing from this pass,
    /// which is usually none and never many. Walking every running application
    /// would be a far heavier thing to do once a second.
    private static func minimizedWindowTitles(for owners: Set<String>)
        -> [String: Set<String>]
    {
        guard !owners.isEmpty else { return [:] }
        var result: [String: Set<String>] = [:]
        for application in NSWorkspace.shared.runningApplications {
            guard let name = application.localizedName,
                owners.contains(name),
                application.processIdentifier > 0
            else { continue }

            let element = AXUIElementCreateApplication(
                application.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.2)
            guard
                let windows = copy(element, kAXWindowsAttribute as String)
                    as? [AXUIElement]
            else { continue }

            for window in windows {
                guard
                    copy(window, kAXMinimizedAttribute as String) as? Bool
                        == true
                else { continue }
                let title =
                    copy(window, kAXTitleAttribute as String) as? String ?? ""
                result[name, default: []].insert(title)
            }
        }
        return result
    }

    /// The type is not cast here, the caller checks it, because an application
    /// answers with whatever it put there.
    private static func copy(_ element: AXUIElement, _ attribute: String)
        -> Any?
    {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element, attribute as CFString, &value) == .success
        else { return nil }
        return value
    }

    /// Puts each remembered window back in its workspace, recreating the
    /// workspace when nothing else is left in it.
    private static func insert(
        _ windows: [MinimizedWindowNote], into spaces: [AnySpace]
    ) -> [AnySpace] {
        var byWorkspace: [String: [MinimizedWindowNote]] = [:]
        for window in windows {
            byWorkspace[window.workspace, default: []].append(window)
        }

        var result: [AnySpace] = []
        var handled: Set<String> = []
        for space in spaces {
            guard let extras = byWorkspace[space.id] else {
                result.append(space)
                continue
            }
            handled.insert(space.id)
            result.append(
                AnySpace(
                    id: space.id,
                    isFocused: space.isFocused,
                    windows: sorted(space.windows + extras.map(window(from:))),
                    monitorScreenID: space.monitorScreenID))
        }

        for (workspace, extras) in byWorkspace where !handled.contains(workspace)
        {
            result.append(
                AnySpace(
                    id: workspace,
                    isFocused: false,
                    windows: sorted(extras.map(window(from:))),
                    monitorScreenID: extras.first?.monitorScreenID))
        }
        return result
    }

    private static func window(from note: MinimizedWindowNote) -> AnyWindow {
        AnyWindow(
            id: note.id,
            title: note.title,
            appName: note.appName,
            bundleID: note.bundleID,
            isFocused: false,
            isMinimized: true,
            appIcon: IconCache.shared.icon(
                bundleID: note.bundleID, appName: note.appName))
    }

    /// The same order the providers use, so a window does not change position
    /// when it is minimized and restored.
    private static func sorted(_ windows: [AnyWindow]) -> [AnyWindow] {
        windows.sorted { $0.id < $1.id }
    }

    /// Puts a minimized window back on screen.
    ///
    /// The window manager cannot: `aerospace focus --window-id` on a minimized
    /// window answers "doesn't belong to any monitor", and it starts tracking
    /// the window again only once it is no longer minimized. Accessibility can,
    /// and `AXMinimized` is a real attribute to write, not a click on the Dock
    /// synthesised to look like one.
    ///
    /// The window is found by title among the application's minimized ones,
    /// because the accessibility API exposes no identifier to match the window
    /// server's. A lone minimized window is taken whatever it is called, which
    /// covers the untitled ones.
    ///
    /// Returns whether a window was restored. Blocks, so it belongs on a
    /// background queue.
    @discardableResult
    static func unminimize(_ window: AnyWindow) -> Bool {
        guard let application = runningApplication(for: window) else {
            return false
        }
        let element = AXUIElementCreateApplication(application.processIdentifier)

        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element, kAXWindowsAttribute as CFString, &value) == .success,
            let windows = value as? [AXUIElement]
        else { return false }

        let minimized = windows.filter { isMinimized($0) }
        guard !minimized.isEmpty else { return false }

        let target =
            minimized.first { title(of: $0) == window.title }
            ?? (minimized.count == 1 ? minimized[0] : nil)
        guard let target else { return false }

        let result = AXUIElementSetAttributeValue(
            target, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        guard result == .success else {
            Log.spaces.error(
                "a minimized window could not be restored: \(result.rawValue, privacy: .public)")
            return false
        }
        return true
    }

    private static func runningApplication(
        for window: AnyWindow
    ) -> NSRunningApplication? {
        let running = NSWorkspace.shared.runningApplications
        if let bundleID = window.bundleID,
            let match = running.first(where: { $0.bundleIdentifier == bundleID })
        {
            return match
        }
        guard let appName = window.appName else { return nil }
        return running.first { $0.localizedName == appName }
    }

    private static func isMinimized(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                window, kAXMinimizedAttribute as CFString, &value) == .success
        else { return false }
        return (value as? Bool) ?? false
    }

    private static func title(of window: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                window, kAXTitleAttribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }
}
