import Combine
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var configObserver: AnyCancellable?
    private var shortcutObserver: AnyCancellable?
    // One pair of panels per screen. A single panel sized to `NSScreen.main`
    // leaves every other display with no bar at all.
    private var backgroundPanels: [NSPanel] = []
    private var menuBarPanels: [NSPanel] = []

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
        ToggleShortcut.shared.apply(ConfigManager.shared.config.toggleShortcut)
        shortcutObserver = ConfigManager.shared.$config
            .map(\.toggleShortcut)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { shortcut in
                ToggleShortcut.shared.apply(shortcut)
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
    }

    @objc private func screenParametersDidChange(_ notification: Notification) {
        setupPanels()
    }

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

        for (index, screen) in screens.enumerated() {
            let frame = screen.frame
            if index < backgroundPanels.count {
                reposition(
                    backgroundPanels[index], to: frame,
                    level: Int(CGWindowLevelForKey(.desktopWindow)),
                    show: shouldShow)
                reposition(
                    menuBarPanels[index], to: frame,
                    level: Int(CGWindowLevelForKey(.backstopMenu)),
                    show: shouldShow)
            } else {
                backgroundPanels.append(
                    makePanel(
                        frame: frame,
                        level: Int(CGWindowLevelForKey(.desktopWindow)),
                        hostingRootView: AnyView(BackgroundView()),
                        show: shouldShow))
                menuBarPanels.append(
                    makePanel(
                        frame: frame,
                        level: Int(CGWindowLevelForKey(.backstopMenu)),
                        hostingRootView: AnyView(MenuBarView()),
                        show: shouldShow))
            }
        }
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
        let hostingView = NSHostingView(rootView: hostingRootView)
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
