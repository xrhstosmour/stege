import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    // One pair of panels per screen. A single panel sized to `NSScreen.main`
    // leaves every other display with no bar at all.
    private var backgroundPanels: [NSPanel] = []
    private var menuBarPanels: [NSPanel] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let error = ConfigManager.shared.initError {
            showFatalConfigError(message: error)
            return
        }

        MenuBarPopup.setup()
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
                    level: Int(CGWindowLevelForKey(.desktopWindow)))
                reposition(
                    menuBarPanels[index], to: frame,
                    level: Int(CGWindowLevelForKey(.backstopMenu)))
            } else {
                backgroundPanels.append(
                    makePanel(
                        frame: frame,
                        level: Int(CGWindowLevelForKey(.desktopWindow)),
                        hostingRootView: AnyView(BackgroundView())))
                menuBarPanels.append(
                    makePanel(
                        frame: frame,
                        level: Int(CGWindowLevelForKey(.backstopMenu)),
                        hostingRootView: AnyView(MenuBarView())))
            }
        }
    }

    /// The level is re-applied as well as the frame, because a sleep or wake
    /// cycle can leave a panel behind other windows even though its frame is
    /// still correct.
    private func reposition(_ panel: NSPanel, to frame: CGRect, level: Int) {
        panel.setFrame(frame, display: true)
        panel.level = NSWindow.Level(rawValue: level)
        panel.orderFrontRegardless()
    }

    private func makePanel(frame: CGRect, level: Int, hostingRootView: AnyView)
        -> NSPanel
    {
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
        panel.orderFront(nil)
        return panel
    }

    private func showFatalConfigError(message: String) {
        let alert = NSAlert()
        alert.messageText = "Configuration Error"
        alert.informativeText = "\(message)\n\nPlease double check ~/.stege-config.toml and try again."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Quit")
        
        alert.runModal()
        NSApplication.shared.terminate(nil)
    }
}
