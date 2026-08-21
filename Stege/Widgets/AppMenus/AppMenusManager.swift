import AppKit
import Combine

/// Tracks the frontmost application and its top-level menu titles.
///
/// Event-driven on purpose. `NSWorkspace` posts a notification whenever the
/// active application changes, which is the only moment the menu titles can
/// change, so there is no timer here at all.
final class AppMenusManager: ObservableObject {
    @Published private(set) var applicationName: String = ""
    @Published private(set) var menus: [AppMenuEntry] = []
    @Published private(set) var appleMenu: AppMenuEntry?
    @Published private(set) var isTrusted: Bool = AppMenuReader.isTrusted

    private var observers: [NSObjectProtocol] = []
    private var trustPollingTimer: Timer?

    init() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(
            center.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                self?.refresh()
            })
        // An application that changes its own menus while already frontmost, or
        // one still building them at launch, would otherwise be missed.
        observers.append(
            center.addObserver(
                forName: NSWorkspace.didLaunchApplicationNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                self?.refresh()
            })

        refresh()
        startTrustPollingIfNeeded()
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach { center.removeObserver($0) }
        trustPollingTimer?.invalidate()
    }

    /// Granting Accessibility happens outside the app and posts no notification,
    /// so this is the one place a poll is unavoidable. It runs only while
    /// permission is missing and stops for good once granted.
    private func startTrustPollingIfNeeded() {
        guard !isTrusted else { return }
        trustPollingTimer = Timer.scheduledTimer(
            withTimeInterval: 2.0, repeats: true
        ) { [weak self] timer in
            guard let self else { return }
            guard AppMenuReader.isTrusted else { return }
            timer.invalidate()
            self.trustPollingTimer = nil
            self.isTrusted = true
            self.refresh()
        }
    }

    func refresh() {
        guard AppMenuReader.isTrusted else {
            isTrusted = false
            menus = []
            appleMenu = nil
            startTrustPollingIfNeeded()
            return
        }
        isTrusted = true

        guard let application = NSWorkspace.shared.frontmostApplication else {
            applicationName = ""
            menus = []
            appleMenu = nil
            return
        }
        applicationName = application.localizedName ?? ""
        menus = AppMenuReader.topLevelMenus(of: application)
        appleMenu = AppMenuReader.appleMenu(of: application)
    }

    /// Read on demand rather than cached, because enabled state and check marks
    /// change with selection and a cached copy would show stale entries.
    func entries(for menu: AppMenuEntry) -> [AppMenuEntry] {
        guard let element = menu.element else { return [] }
        return AppMenuReader.entries(under: element)
    }
}
