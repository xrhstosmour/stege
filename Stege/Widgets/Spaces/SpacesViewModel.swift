import AppKit
import Combine
import Foundation

class SpacesViewModel: ObservableObject {
    @Published var spaces: [AnySpace] = []
    private var timer: Timer?
    private var provider: AnySpacesProvider?
    private var observers: [NSObjectProtocol] = []
    private var isLoading = false

    /// Safety net only. Refreshes are driven by workspace notifications, and
    /// this catches the cases they cannot see, such as a window opening in
    /// another workspace without the focused application changing.
    private let safetyNetInterval: TimeInterval = 1.0

    init() {
        let runningApps = NSWorkspace.shared.runningApplications.compactMap {
            $0.localizedName?.lowercased()
        }
        if runningApps.contains("yabai") {
            provider = AnySpacesProvider(YabaiSpacesProvider())
        } else if runningApps.contains("aerospace") {
            provider = AnySpacesProvider(AerospaceSpacesProvider())
        } else {
            provider = nil
        }
        startMonitoring()
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

        timer = Timer.scheduledTimer(
            withTimeInterval: safetyNetInterval, repeats: true
        ) { [weak self] _ in
            self?.loadSpaces()
        }
        loadSpaces()
    }

    private func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach { center.removeObserver($0) }
        observers.removeAll()
    }

    private func loadSpaces() {
        // A refresh spawns processes, so overlapping ones would pile up when
        // several notifications arrive together, which they routinely do.
        guard !isLoading else { return }
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let spaces = self.provider?.getSpacesWithWindows()
            let sorted = spaces?.sorted { $0.id < $1.id } ?? []
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
            self.provider?.focusSpace(spaceId: space.id, needWindowFocus: false)
            usleep(100_000)
            self.provider?.focusWindow(windowId: String(window.id))
        }
    }

    func switchToWindow(_ window: AnyWindow) {
        DispatchQueue.global(qos: .userInitiated).async {
            self.provider?.focusWindow(windowId: String(window.id))
        }
    }
}

class IconCache {
    static let shared = IconCache()
    private let cache = NSCache<NSString, NSImage>()
    private init() {}

    /// Resolved by bundle identifier where possible. `NSWorkspace` can map a
    /// bundle identifier straight to an application URL, whereas resolving by
    /// display name means scanning every running application and picks the
    /// wrong one when two share a name.
    func icon(bundleID: String?, appName: String?) -> NSImage? {
        let key = (bundleID ?? appName ?? "") as NSString
        guard key.length > 0 else { return nil }
        if let cached = cache.object(forKey: key) { return cached }

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
        guard let url else { return nil }

        let icon = workspace.icon(forFile: url.path)
        cache.setObject(icon, forKey: key)
        return icon
    }

    func icon(for appName: String) -> NSImage? {
        icon(bundleID: nil, appName: appName)
    }
}
