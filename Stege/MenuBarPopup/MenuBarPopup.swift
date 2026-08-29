import SwiftUI

private var panel: NSPanel?

class HidingPanel: NSPanel, NSWindowDelegate {
    var hideTimer: Timer?

    override var canBecomeKey: Bool {
        return true
    }

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing bufferingType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect, styleMask: style, backing: bufferingType,
            defer: flag)
        self.delegate = self
    }

    func windowDidResignKey(_ notification: Notification) {
        // A popup that is in the middle of driving one of macOS's own panels
        // is not being dismissed, it is waiting. Notification Center and
        // Control Center both take key while they are open, so without this
        // the popup that asked for the read is the thing the read closes.
        guard !MenuBarPopup.isDrivingSystemPanel else { return }
        NotificationCenter.default.post(name: .willHideWindow, object: nil)
        hideTimer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(
                Constants.menuBarPopupAnimationDurationInMilliseconds) / 1000.0,
            repeats: false
        ) { [weak self] _ in
            self?.orderOut(nil)
        }
    }
}

class MenuBarPopup {
    static var lastContentIdentifier: String? = nil

    /// Set while a popup is reading or pressing something inside one of
    /// macOS's own panels. See `HidingPanel.windowDidResignKey`.
    private(set) static var isDrivingSystemPanel = false

    /// Wraps work that opens a system panel, so the popup behind it neither
    /// disappears while it runs nor stays dead afterwards.
    ///
    /// `end` puts the popup back in front, because the panel it was waiting on
    /// took key and giving it back is not automatic: without it the popup stays
    /// on screen but stops responding to anything.
    static func beginSystemPanelInteraction() {
        isDrivingSystemPanel = true
    }

    static func endSystemPanelInteraction() {
        isDrivingSystemPanel = false
        guard let panel, panel.isVisible else { return }
        panel.makeKeyAndOrderFront(nil)
    }

    /// The screen the popup is currently being shown on. Read by
    /// `MenuBarPopupView` to keep the popup inside that display's edges rather
    /// than the main display's.
    static var currentScreenFrame: CGRect = .zero

    /// Moves the shared popup panel onto whichever screen the widget that was
    /// clicked lives on, so a popup opened from the bar on a second display
    /// does not appear on the first.
    private static func moveToScreen(containing rect: CGRect) -> CGRect {
        let screen =
            NSScreen.screens.first { $0.frame.intersects(rect) }
            ?? NSScreen.main
        guard let frame = screen?.frame else { return .zero }
        currentScreenFrame = frame
        panel?.setFrame(frame, display: false)
        return frame
    }

    static func show<Content: View>(
        rect: CGRect, id: String, @ViewBuilder content: @escaping () -> Content
    ) {
        guard let panel = panel else { return }
        let screenFrame = moveToScreen(containing: rect)

        if panel.isKeyWindow, lastContentIdentifier == id {
            NotificationCenter.default.post(name: .willHideWindow, object: nil)
            let duration =
                Double(Constants.menuBarPopupAnimationDurationInMilliseconds)
                / 1000.0
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                panel.orderOut(nil)
                lastContentIdentifier = nil
            }
            return
        }

        let isContentChange =
            panel.isKeyWindow
            && (lastContentIdentifier != nil && lastContentIdentifier != id)
        lastContentIdentifier = id

        if let hidingPanel = panel as? HidingPanel {
            hidingPanel.hideTimer?.invalidate()
            hidingPanel.hideTimer = nil
        }

        if panel.isKeyWindow {
            NotificationCenter.default.post(
                name: .willChangeContent, object: nil)
            let baseDuration =
                Double(Constants.menuBarPopupAnimationDurationInMilliseconds)
                / 1000.0
            let duration = isContentChange ? baseDuration / 2 : baseDuration
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                panel.contentView = NSHostingView(
                    rootView:
                        ZStack {
                            MenuBarPopupView {
                                content()
                            }
                            .position(x: rect.midX - screenFrame.minX)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .id(UUID())
                )
                panel.makeKeyAndOrderFront(nil)
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .willShowWindow, object: nil)
                }
            }
        } else {
            panel.contentView = NSHostingView(
                rootView:
                    ZStack {
                        MenuBarPopupView {
                            content()
                        }
                        .position(x: rect.midX - screenFrame.minX)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            )
            panel.makeKeyAndOrderFront(nil)
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .willShowWindow, object: nil)
            }
        }
    }

    /// Dismisses the popup from code, for a row that has acted and should not
    /// leave the panel sitting over whatever it just opened.
    static func hide() {
        guard let panel, panel.isVisible else { return }
        NotificationCenter.default.post(name: .willHideWindow, object: nil)
        let duration =
            Double(Constants.menuBarPopupAnimationDurationInMilliseconds) / 1000.0
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            panel.orderOut(nil)
            lastContentIdentifier = nil
        }
    }

    static func setup() {
        // Placeholder geometry only. `show(rect:id:)` moves the panel onto
        // whichever screen the widget was clicked on before it is ever
        // displayed, so this must not fail when there is no main screen, and
        // must not bake in that screen's size either.
        let panelFrame =
            NSScreen.main?.frame ?? NSScreen.screens.first?.frame
            ?? NSRect(x: 0, y: 0, width: 1, height: 1)

        let newPanel = HidingPanel(
            contentRect: panelFrame,
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        newPanel.level = NSWindow.Level(
            rawValue: Int(CGWindowLevelForKey(.floatingWindow)))
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = false
        newPanel.collectionBehavior = [.canJoinAllSpaces]

        panel = newPanel
    }
}
