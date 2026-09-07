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

    /// Where each menu title is drawn, per screen, written by that screen's
    /// widget as it lays out. The shortcut needs somewhere to put the menu, and
    /// the only thing that knows is the view.
    ///
    /// Keyed by screen because there is one bar per screen and each reports its
    /// titles in that bar's own panel-local coordinates: a single shared
    /// dictionary had every screen's widget overwrite the same key, so whichever
    /// one last laid out decided where the keyboard shortcut opened the menu on
    /// every screen, not just its own.
    var titleFrames: [Int: [String: CGRect]] = [:]

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
            below: titleFrames[currentScreenIndex]?[first.id] ?? fallbackFrame())
    }

    /// Which screen's title frames to use, matching `AppMenuPresenter.present`'s
    /// own screen resolution: the one under the pointer is the one the menu
    /// will actually be popped up on.
    private var currentScreenIndex: Int {
        let pointer = NSEvent.mouseLocation
        let index =
            NSScreen.screens.firstIndex { $0.frame.contains(pointer) } ?? 0
        return index + 1
    }

    /// Where to put a menu when the titles are not drawn, which is every
    /// `visibility` mode but `always`, or before layout has happened at all.
    /// Under the left of the bar, in the same panel-local coordinates a
    /// drawn title would report: `AppMenuPresenter.present` resolves the real
    /// screen and its origin itself, so this only has to describe where on
    /// that screen's own bar the titles would have been.
    private func fallbackFrame() -> CGRect {
        let height = ConfigManager.shared.config.bar.foreground.resolveHeight()
        return CGRect(x: 12, y: 0, width: 1, height: height)
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

        guard let application = Self.applicationToRead() else {
            applicationName = ""
            menus = []
            appleMenu = nil
            return
        }
        Self.lastOrdinaryApplication = application
        applicationName = application.localizedName ?? ""
        menus = AppMenuReader.topLevelMenus(of: application)
        appleMenu = AppMenuReader.appleMenu(of: application)
    }

    /// Whose menus belong in the bar.
    ///
    /// Not simply the frontmost application. Stege activates itself to give the
    /// menus row the keyboard, which makes Stege frontmost, and reading that
    /// left the row showing Stege's own menus, or `UserNotificationCenter`'s
    /// when macOS handed frontmost to a system process on the way. Neither is
    /// an application whose menus anyone asked for.
    ///
    /// So Stege and everything that is not an ordinary application are skipped,
    /// and the most recently active one that is left is the answer. That is the
    /// application the person was working in, which is whose menus these are.
    private static func applicationToRead() -> NSRunningApplication? {
        let ownIdentifier = Bundle.main.bundleIdentifier
        if let frontmost = NSWorkspace.shared.frontmostApplication,
            frontmost.bundleIdentifier != ownIdentifier,
            frontmost.activationPolicy == .regular
        {
            return frontmost
        }
        return NSWorkspace.shared.runningApplications.first {
            $0.isActive && $0.bundleIdentifier != ownIdentifier
                && $0.activationPolicy == .regular
        } ?? lastOrdinaryApplication
    }

    /// The last ordinary application seen in front, kept because once Stege has
    /// activated there is nothing left to ask.
    private static var lastOrdinaryApplication: NSRunningApplication?

    /// Read on demand rather than cached, because enabled state and check marks
    /// change with selection and a cached copy would show stale entries.
    func entries(for menu: AppMenuEntry) -> [AppMenuEntry] {
        guard let element = menu.element else { return [] }
        return AppMenuReader.entries(under: element)
    }
}
