import AppKit
import Combine

/// Tracks the frontmost application and its top-level menu titles.
///
/// Event-driven on purpose. `NSWorkspace` posts a notification whenever the
/// active application changes, which is the only moment the menu titles can
/// change, so there is no timer here at all.
final class AppMenusManager: ObservableObject {
    /// One instance. What it tracks is the frontmost application, which is a
    /// property of the machine rather than of a bar, and there is one bar per
    /// screen: two managers on a two-monitor setup were doing the same
    /// accessibility read on every application switch and getting the same
    /// answer. A keyboard shortcut also needs to reach it, and cannot reach a
    /// view's `@StateObject`.
    static let shared = AppMenusManager()

    @Published private(set) var applicationName: String = ""
    @Published private(set) var menus: [AppMenuEntry] = []
    @Published private(set) var appleMenu: AppMenuEntry?
    @Published private(set) var isTrusted: Bool = AppMenuReader.isTrusted

    /// Where each menu title is drawn, in screen coordinates, written by the
    /// widget as it lays out. The shortcut needs somewhere to put the menu, and
    /// the only thing that knows is the view.
    var titleFrames: [String: CGRect] = [:]

    private var observers: [NSObjectProtocol] = []
    private var trustPollingTimer: Timer?

    /// Opens the frontmost application's first menu, which is what a keyboard
    /// shortcut is for. `NSMenu` handles the arrows, Return and Escape once it
    /// is up, so nothing here reimplements navigation, and nothing simulates a
    /// press: this is the same call the title's own tap makes.
    func openFirstMenu() {
        refresh()
        guard let first = menus.first else { return }
        AppMenuPresenter.present(
            menu: first, manager: self,
            below: titleFrames[first.id] ?? fallbackFrame())
    }

    /// Where to put a menu when the titles are not drawn, which is every
    /// `visibility` mode but `always`. Under the left of the bar on whichever
    /// screen holds the pointer, which is where the titles would have been.
    private func fallbackFrame() -> CGRect {
        let pointer = NSEvent.mouseLocation
        let screen =
            NSScreen.screens.first { $0.frame.contains(pointer) }
            ?? NSScreen.main
        guard let frame = screen?.frame else { return .zero }
        let height = ConfigManager.shared.config.bar.foreground.resolveHeight()
        return CGRect(
            x: frame.minX + 12, y: frame.minY, width: 1, height: height)
    }

    private init() {
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
        // `refresh()` also calls this on every application switch, so without
        // clearing the previous one a new timer was added each time and they
        // accumulated for the life of the process.
        guard trustPollingTimer == nil else { return }
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
