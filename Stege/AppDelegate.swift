import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var configObserver: AnyCancellable?
    private var shortcutObserver: AnyCancellable?
    // One pair of panels per screen. A single panel sized to `NSScreen.main`
    // leaves every other display with no bar at all.
    private var backgroundPanels: [NSPanel] = []
    private var menuBarPanels: [NSPanel] = []
    /// One per screen, holding nothing but the button that expands the bar
    /// again. Only on screen while the bar is collapsed.
    private var collapsedPanels: [NSPanel] = []

    /// Big enough to hit without looking, small enough to cover almost none of
    /// the menu bar it is sitting on.
    private static let collapsedButtonSize = CGSize(width: 26, height: 22)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A second copy would draw an overlapping bar on every display and
        // double every timer and `aerospace` invocation behind it.
        let sameApp = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        if sameApp.count > 1 {
            NSApp.terminate(nil)
            return
        }

        if let error = ConfigManager.shared.initError {
            showFatalConfigError(message: error)
            return
        }

        MenuBarPopup.setup()
        // After the panels exist, so the window appears over a drawn bar
        // rather than an empty screen. Shows nothing when everything needed is
        // already granted.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            PermissionsWindowController.shared.showIfNeeded()
        }


        // Before the panels are built, not after: `setupPanels` reads the
        // visibility state to decide whether to order them in, so applying this
        // later would flash the bar on screen and immediately hide it again.
        BarVisibility.shared.setHiddenByConfig(ConfigManager.shared.config.hidden)

        setupPanels()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil)

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(screenParametersDidChange(_:)),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(barVisibilityDidChange(_:)),
            name: .stegeBarVisibilityChanged,
            object: nil)

        observeHiddenSetting()
        observeToggleShortcut()
    }

    /// Applies `hidden` from the config file, now and on every reload.
    ///
    /// The file is watched, so toggling the setting hides or shows the bar
    /// without a restart, which is what makes it usable as a switch rather than
    /// a launch option.
    private func observeHiddenSetting() {
        configObserver = ConfigManager.shared.$config
            .map(\.hidden)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { hidden in
                BarVisibility.shared.setHiddenByConfig(hidden)
            }
    }

    /// Registers the shortcut from the config file, now and on every reload,
    /// so changing it takes effect without a restart.
    private func observeToggleShortcut() {
        observeRunningApplications()
        applyShortcuts(ConfigManager.shared.config)
        applyAppearance(ConfigManager.shared.config)
        shortcutObserver = ConfigManager.shared.$config
            .receive(on: DispatchQueue.main)
            .sink { [weak self] configuration in
                self?.applyShortcuts(configuration)
                self?.applyAppearance(configuration)
            }
    }

    /// Puts the theme on the panels themselves.
    ///
    /// `preferredColorScheme` inside the view is not enough. Changing `theme`
    /// from `light` back to `system` left the bar light, because
    /// `preferredColorScheme(nil)` means "no preference" and no preference does
    /// not undo an override already applied. A nil `NSWindow.appearance` does
    /// undo it: nil there means inherit from the application, which follows
    /// System Settings.
    private func applyAppearance(_ configuration: Config) {
        let appearance = configuration.appearance
        for panel in backgroundPanels + menuBarPanels + collapsedPanels {
            panel.appearance = appearance
        }
        MenuBarPopup.applyAppearance(appearance)
    }

    /// An application that was not running when its icon was asked for may be
    /// running now, so the record of what failed is dropped when the set
    /// changes rather than being kept for the life of the process.
    private func observeRunningApplications() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil, queue: .main
        ) { _ in IconCache.shared.forgetMisses() }
    }

    private func applyShortcuts(_ configuration: Config) {
        GlobalShortcut.shared.apply(
            configuration.toggleShortcut, name: "toggle"
        ) {
            BarVisibility.shared.toggleByShortcut()
        }
        // Each of these calls what the click calls. Nothing synthesises a
        // press: a shortcut that worked by clicking its own bar would break
        // the moment the bar was hidden, which is exactly when it is wanted.
        GlobalShortcut.shared.apply(
            configuration.revealShortcut, name: "reveal"
        ) {
            let visibility = BarVisibility.shared
            if !visibility.isShowingExtras {
                MenuBarExtrasReader.shared.refresh()
            }
            visibility.isShowingExtras.toggle()
        }
        GlobalShortcut.shared.apply(
            configuration.menuShortcut, name: "menu"
        ) {
            AppMenusManager.shared.openFirstMenu()
        }
    }

    /// Orders Stege's panels out so the system menu bar underneath is reachable,
    /// and back in once `BarVisibility` decides the pointer has moved away.
    @objc private func barVisibilityDidChange(_ notification: Notification) {
        let hidden = BarVisibility.shared.isHidden
        for panel in backgroundPanels + menuBarPanels {
            if hidden {
                panel.orderOut(nil)
            } else {
                panel.orderFrontRegardless()
            }
        }
        // Only the collapsed mode leaves a way back on screen. The config file
        // and the shortcut each have their own, and the temporary hide comes
        // back on its own.
        let collapsed = BarVisibility.shared.isCollapsed
        for panel in collapsedPanels {
            if collapsed {
                panel.orderFrontRegardless()
            } else {
                panel.orderOut(nil)
            }
        }
    }

    @objc private func screenParametersDidChange(_ notification: Notification) {
        setupPanels()
        // A panel built for a newly attached screen starts with no appearance.
        applyAppearance(ConfigManager.shared.config)
    }

    /// Just under the real menu bar.
    ///
    /// These used to be the desktop level and `backstopMenu`, which is -20, so
    /// the whole bar sat *behind* every ordinary window. It looked right only
    /// because a tiling window manager was keeping a gap at the top of the
    /// screen for it. On a second display with no such gap, or under any
    /// window placed at the top of the screen, the bar was simply not there.
    ///
    /// Below the real menu bar rather than above it, at 24, so moving the
    /// pointer to the top of the screen still reveals the system's own bar
    /// over this one. That is what the reveal chevron and the extras row are
    /// built on.
    private static var barLevel: Int {
        Int(CGWindowLevelForKey(.mainMenuWindow)) - 1
    }
    private static var backgroundLevel: Int { barLevel - 1 }

    /// Creates or updates one background and one menu bar panel per screen.
    ///
    /// Re-run whenever the screen layout changes or the displays wake, which
    /// also repairs panels whose frame or level did not survive a sleep cycle.
    private func setupPanels() {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }

        // `setupPanels` runs on display changes and on wake, both of which can
        // happen while the bar is deliberately hidden by the reveal chevron.
        // Ordering panels in regardless would undo that, so the hidden state is
        // carried through to every panel this pass touches or creates.
        let shouldShow = !BarVisibility.shared.isHidden

        // Displays were removed, so drop the panels that no longer have one.
        while backgroundPanels.count > screens.count {
            backgroundPanels.removeLast().close()
        }
        while menuBarPanels.count > screens.count {
            menuBarPanels.removeLast().close()
        }
        while collapsedPanels.count > screens.count {
            collapsedPanels.removeLast().close()
        }

        for (index, screen) in screens.enumerated() {
            let frame = screen.frame
            if index < backgroundPanels.count {
                reposition(
                    backgroundPanels[index], to: frame,
                    level: Self.backgroundLevel,
                    show: shouldShow)
                reposition(
                    menuBarPanels[index], to: frame,
                    level: Self.barLevel,
                    show: shouldShow)
                reposition(
                    collapsedPanels[index], to: collapsedFrame(on: screen),
                    level: Int(CGWindowLevelForKey(.popUpMenuWindow)),
                    show: BarVisibility.shared.isCollapsed)
            } else {
                backgroundPanels.append(
                    makePanel(
                        frame: frame,
                        level: Self.backgroundLevel,
                        hostingRootView: AnyView(BackgroundView()),
                        show: shouldShow))
                menuBarPanels.append(
                    makePanel(
                        frame: frame,
                        level: Self.barLevel,
                        hostingRootView: AnyView(
                            MenuBarView(screenIndex: index + 1)),
                        show: shouldShow))
                // Above the menu bar rather than behind it, because the whole
                // point is to stay reachable while the real menu bar is the
                // thing on screen.
                collapsedPanels.append(
                    makePanel(
                        frame: collapsedFrame(on: screen),
                        level: Int(CGWindowLevelForKey(.popUpMenuWindow)),
                        hostingRootView: AnyView(CollapsedRevealView()),
                        show: BarVisibility.shared.isCollapsed))
            }
        }
    }

    /// Where the button that brings the bar back sits while it is away.
    ///
    /// Neither end of the menu bar is free. The trailing end is the status
    /// items, which are the whole reason the bar stepped aside, and the leading
    /// end is the Apple menu, which this used to sit squarely on top of: 26
    /// points from the left edge covers the logo, so collapsing the bar made
    /// the Apple menu unclickable.
    ///
    /// The middle is the part nothing occupies. Menus fill from the left and
    /// status items from the right, and on a display with a notch the middle is
    /// not even drawable. `auxiliaryTopLeftArea` is the usable strip to the
    /// left of the notch, so its trailing end is as close to the middle as this
    /// can get while staying visible. Displays without a notch do not publish
    /// one, and there the middle is the middle.
    private func collapsedFrame(on screen: NSScreen) -> CGRect {
        let size = Self.collapsedButtonSize
        let frame = screen.frame
        let x: CGFloat
        if let leftOfNotch = screen.auxiliaryTopLeftArea {
            x = leftOfNotch.maxX - size.width
        } else {
            x = frame.midX - size.width / 2
        }
        return CGRect(
            x: x,
            y: frame.maxY - size.height,
            width: size.width,
            height: size.height)
    }

    /// The level is re-applied as well as the frame, because a sleep or wake
    /// cycle can leave a panel behind other windows even though its frame is
    /// still correct.
    private func reposition(
        _ panel: NSPanel, to frame: CGRect, level: Int, show: Bool
    ) {
        panel.setFrame(frame, display: true)
        panel.level = NSWindow.Level(rawValue: level)
        if show { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
    }

    private func makePanel(
        frame: CGRect, level: Int, hostingRootView: AnyView, show: Bool = true
    ) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.level = NSWindow.Level(rawValue: level)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Without this a panel is released when a display is disconnected, and
        // reconnecting it then messages a deallocated window.
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [
            .canJoinAllSpaces, .fullScreenAuxiliary, .stationary,
        ]
        // Top aligned inside the panel, because the panel is the whole screen
        // and the bar is a fixed height. Without this SwiftUI centres it, and
        // the bar would be drawn halfway down the display.
        let hostingView = NSHostingView(
            rootView: AnyView(
                hostingRootView.frame(
                    maxWidth: .infinity, maxHeight: .infinity, alignment: .top)))
        // The panel keeps the frame it is given. `NSHostingView` publishes its
        // root view's intrinsic size by default, and AppKit resizes the window
        // to match, so the screen-sized menu bar panel shrank to the 44 points
        // its content wanted. A window that small is then subject to
        // `constrainFrameRect`, which pushes it clear of the menu bar area: on
        // a notched built-in display that is 32 points, and the whole bar was
        // drawn 32 points too low with its bottom edge cut off. Measured, not
        // guessed: the panel reported (0, 880, 1470, 44) instead of
        // (0, 0, 1470, 956).
        hostingView.sizingOptions = []
        hostingView.wantsLayer = true
        hostingView.layer?.isOpaque = false
        panel.contentView = hostingView
        if show { panel.orderFront(nil) }
        return panel
    }

    private func showFatalConfigError(message: String) {
        let alert = NSAlert()
        alert.messageText = "Configuration Error"
        alert.informativeText = "\(message)\n\nPlease double check ~/.stege-config.toml and try again."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Quit")

        // An accessory app is not activated on launch, so without this the
        // alert can open behind whatever is in front and look like a silent
        // failure to start.
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
        NSApplication.shared.terminate(nil)
    }
}
