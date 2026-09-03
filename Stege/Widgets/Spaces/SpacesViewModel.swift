import AppKit
import Combine
import Foundation

class SpacesViewModel: ObservableObject {
    /// One per process, not one per bar.
    ///
    /// This was a `@StateObject` on `SpacesWidget`, and there is one of those
    /// per display, so two monitors meant two of everything behind it: two
    /// timers, two sets of notification observers, and four `aerospace`
    /// processes a second for one answer. Nothing in here is per-display, the
    /// workspaces are filtered by screen in the view, so one is enough.
    static let shared = SpacesViewModel()

    @Published var spaces: [AnySpace] = []
    private var timer: Timer?
    private var provider: AnySpacesProvider?
    private var observers: [NSObjectProtocol] = []
    private var isLoading = false
    /// Whether anything is looking at the workspaces.
    ///
    /// False while the bar is off screen, either stepped aside for the real
    /// menu bar, collapsed, hidden by the shortcut or turned off in the
    /// configuration, and false while the displays are asleep. A refresh spawns
    /// two `aerospace` processes, and doing that once a second to redraw
    /// something nobody can see is the one piece of work here that buys
    /// nothing.
    private var isWatched = true

    /// Safety net only. Refreshes are driven by workspace notifications, and
    /// this catches the cases they cannot see, such as a window opening in
    /// another workspace without the focused application changing.
    private let safetyNetInterval: TimeInterval = 1.0

    private init() {
        resolveProvider()
        startMonitoring()
    }

    /// Which window manager is running, asked again when there was none.
    ///
    /// This used to run once, in `init`. Stege starts at login alongside the
    /// window manager, so whichever of them wins the race decided whether the
    /// bar had any workspaces at all, and losing it meant an empty left half
    /// until the application was restarted by hand.
    private func resolveProvider() {
        guard provider == nil else { return }
        let running = NSWorkspace.shared.runningApplications.compactMap {
            $0.localizedName?.lowercased()
        }
        if running.contains("yabai") {
            provider = AnySpacesProvider(YabaiSpacesProvider())
        } else if running.contains("aerospace") {
            provider = AnySpacesProvider(AerospaceSpacesProvider())
        }
    }

    deinit {
        stopMonitoring()
    }

    private func startMonitoring() {
        let center = NSWorkspace.shared.notificationCenter
        // Switching workspace focuses a window, which changes the active
        // application in almost every case, so these carry the refresh and the
        // timer below rarely has anything to do.
        for name: NSNotification.Name in [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
        ] {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) {
                    [weak self] _ in
                    self?.loadSpaces()
                })
        }

        observers.append(
            center.addObserver(
                forName: NSWorkspace.screensDidSleepNotification, object: nil,
                queue: .main
            ) { [weak self] _ in self?.setWatched(false) })
        observers.append(
            center.addObserver(
                forName: NSWorkspace.screensDidWakeNotification, object: nil,
                queue: .main
            ) { [weak self] _ in self?.setWatched(true) })
        // The bar going away and coming back, which on a machine with the menu
        // bar set to hide happens many times an hour.
        observers.append(
            NotificationCenter.default.addObserver(
                forName: .stegeBarVisibilityChanged, object: nil, queue: .main
            ) { [weak self] _ in
                self?.setWatched(!BarVisibility.shared.isHidden)
            })
        isWatched = !BarVisibility.shared.isHidden

        timer = Timer.scheduledTimer(
            withTimeInterval: safetyNetInterval, repeats: true
        ) { [weak self] _ in
            self?.loadSpaces()
        }
        loadSpaces()
    }

    /// Stops or resumes the refresh, and catches up the moment it resumes so
    /// the bar is never drawn from a stale list.
    private func setWatched(_ watched: Bool) {
        guard watched != isWatched else { return }
        isWatched = watched
        if watched { loadSpaces() }
    }

    private func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        // Both centres, because the visibility notification is posted on the
        // default one and the workspace ones are not. Removing an observer from
        // the wrong centre is a no-op rather than an error, so this is safe
        // either way and there is no need to remember which came from where.
        let workspace = NSWorkspace.shared.notificationCenter
        observers.forEach {
            workspace.removeObserver($0)
            NotificationCenter.default.removeObserver($0)
        }
        observers.removeAll()
    }

    private func loadSpaces() {
        guard isWatched else { return }
        resolveProvider()
        // A refresh spawns processes, so overlapping ones would pile up when
        // several notifications arrive together, which they routinely do.
        guard !isLoading else { return }
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let spaces = self.provider?.getSpacesWithWindows()
            // `AeroSpace` stops reporting a window the moment it is minimized,
            // so without this a minimized window left its workspace pill and
            // an all-minimized workspace left the bar entirely.
            let restored = spaces.map {
                MinimizedWindowMemory.shared.reconcile($0)
            }
            let sorted = restored?.sorted { $0.id < $1.id } ?? []
            DispatchQueue.main.async {
                self.isLoading = false
                // Assigning an identical value still republishes and redraws
                // the bar, so only publish real changes.
                if self.spaces != sorted { self.spaces = sorted }
            }
        }
    }

    func switchToSpace(_ space: AnySpace, needWindowFocus: Bool = false) {
        DispatchQueue.global(qos: .userInitiated).async {
            self.provider?.focusSpace(
                spaceId: space.id, needWindowFocus: needWindowFocus)
        }
    }

    /// Switches workspace and then focuses a window inside it.
    ///
    /// The pause between the two lets the workspace switch settle before the
    /// focus request lands. It runs on a background queue: the caller used to
    /// `usleep` inline from the tap handler, which froze the interface for
    /// 100 ms on every click.
    func switchToSpaceAndWindow(_ space: AnySpace, window: AnyWindow) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            // A minimized window has to come back on screen first. The window
            // manager cannot focus one it is not tracking, and it only starts
            // tracking it again once it is no longer minimized.
            if window.isMinimized {
                guard MinimizedWindowMemory.unminimize(window) else { return }
                usleep(150_000)
                // The window manager starts tracking the window again the
                // moment it is no longer minimized, and files it under whatever
                // workspace is focused right then rather than the one it was
                // minimized in. Verified: a window minimized in workspace 2 came
                // back in workspace 1.
                self.provider?.moveWindow(
                    windowId: String(window.id), toSpace: space.id)
                usleep(100_000)
            }
            self.provider?.focusSpace(spaceId: space.id, needWindowFocus: false)
            usleep(100_000)
            self.provider?.focusWindow(windowId: String(window.id))
        }
    }

    func switchToWindow(_ window: AnyWindow) {
        DispatchQueue.global(qos: .userInitiated).async {
            if window.isMinimized {
                guard MinimizedWindowMemory.unminimize(window) else { return }
                usleep(150_000)
            }
            self.provider?.focusWindow(windowId: String(window.id))
        }
    }
}

class IconCache {
    static let shared = IconCache()
    private let cache = NSCache<NSString, NSImage>()
    /// Keys that resolved to nothing.
    ///
    /// A miss costs a scan of every running application, and nothing was
    /// remembering that it had already failed. The notification popup asks for
    /// an icon by application name while it draws each row, so an application
    /// that is not running was rescanned for on every render of every row it
    /// appeared in.
    private var misses: Set<String> = []
    /// `NSCache` is thread safe, a Swift `Set` is not, and this one is touched
    /// from both ends: the window list is decoded on the workspace queue and
    /// asks for an icon per window, while the notification rows ask for one per
    /// row as SwiftUI draws them on the main thread. Two threads mutating the
    /// same set is a corrupted set, not a stale one.
    private let lock = NSLock()
    private init() {}

    /// Resolved by bundle identifier where possible. `NSWorkspace` can map a
    /// bundle identifier straight to an application URL, whereas resolving by
    /// display name means scanning every running application and picks the
    /// wrong one when two share a name.
    func icon(bundleID: String?, appName: String?) -> NSImage? {
        let key = (bundleID ?? appName ?? "") as NSString
        guard key.length > 0 else { return nil }
        if let cached = cache.object(forKey: key) { return cached }
        lock.lock()
        let missed = misses.contains(key as String)
        lock.unlock()
        if missed { return nil }

        let workspace = NSWorkspace.shared
        var url: URL?
        if let bundleID {
            url = workspace.urlForApplication(withBundleIdentifier: bundleID)
        }
        if url == nil, let appName {
            url = workspace.runningApplications
                .first { $0.localizedName == appName }?
                .bundleURL
        }
        guard let url else {
            lock.lock()
            misses.insert(key as String)
            lock.unlock()
            return nil
        }

        let icon = workspace.icon(forFile: url.path)
        cache.setObject(icon, forKey: key)
        return icon
    }

    func icon(for appName: String) -> NSImage? {
        icon(bundleID: nil, appName: appName)
    }

    /// Applications come and go, so a name that failed once may resolve later.
    /// Called when the set of running applications changes.
    func forgetMisses() {
        lock.lock()
        misses.removeAll()
        lock.unlock()
    }
}
