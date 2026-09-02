import AppKit

/// Hides Stege's panels so the real macOS menu bar underneath becomes reachable,
/// then brings them back once the pointer leaves the menu bar strip.
///
/// This is how third-party status items stay reachable. Stege cannot draw them
/// itself: a status item is rendered by the process that owns it, and nothing
/// short of screen capture can reproduce it, which is not a permission this app
/// is willing to ask for.
final class BarVisibility: ObservableObject {
    static let shared = BarVisibility()

    /// Hidden because the chevron was clicked, which is temporary, because the
    /// shortcut was pressed, which lasts until it is pressed again, or because
    /// the config file says so, which lasts until the file changes. Kept as
    /// separate flags so pointing away from a chevron-hidden bar cannot
    /// override either of the other two.
    var isHidden: Bool {
        isHiddenByConfig || isHiddenByShortcut || isHiddenByChevron
            || isCollapsed
    }

    @Published private(set) var isHiddenByChevron = false
    @Published private(set) var isHiddenByConfig = false
    @Published private(set) var isHiddenByShortcut = false
    /// Hidden by the chevron in its sticky mode, which unlike the others leaves
    /// a small button on screen, because nothing else would bring the bar back.
    @Published private(set) var isCollapsed = false

    /// Whether the other applications' status items are appended to the bar.
    ///
    /// Here rather than in `RevealWidget` because a keyboard shortcut has to
    /// reach it, and a shortcut cannot touch a view's own `@State`. The widget
    /// reads and writes this instead of holding its own copy, so both routes
    /// drive one piece of state rather than a click and a key press
    /// disagreeing about whether the row is open.
    @Published var isShowingExtras = false

    /// How far down the pointer must travel before the bar comes back. Slightly
    /// more than the menu bar's own height by default, so the bar does not
    /// reappear while the pointer is still inside a menu the user just opened.
    /// Supplied by the widget so it can be configured.
    private var returnThreshold: CGFloat = 80
    private var timeout: TimeInterval = 10

    private var pointerMonitor: Any?
    private var fallbackTimer: Timer?

    private init() {}

    func hide(returnThreshold: Double = 80, timeout: Double = 10) {
        guard !isHidden else { return }
        self.returnThreshold = CGFloat(returnThreshold)
        self.timeout = timeout
        isHiddenByChevron = true
        NotificationCenter.default.post(name: .stegeBarVisibilityChanged, object: nil)
        startWatchingPointer()
    }

    /// Collapses the bar, and expands it again on the second call.
    ///
    /// Unlike `hide`, this does not come back on its own. The pointer has to be
    /// free to travel down into a status item's menu without the bar snapping
    /// back over it, which is the whole point of a mode that stays put, so the
    /// small button `AppDelegate` leaves on screen is the way back.
    func toggleCollapsed() {
        let wasHidden = isHidden
        isCollapsed.toggle()
        if isCollapsed {
            // A temporary hide already in flight would otherwise expand the bar
            // again on the next mouse move.
            stopWatchingPointer()
            isHiddenByChevron = false
        }
        guard isHidden != wasHidden else { return }
        NotificationCenter.default.post(name: .stegeBarVisibilityChanged, object: nil)
    }

    /// Applies `hidden` from the config file.
    ///
    /// Unlike the chevron this does not watch the pointer or start a timer: the
    /// bar stays hidden until the file says otherwise, which is the whole point
    /// of writing it down rather than clicking.
    func setHiddenByConfig(_ hidden: Bool) {
        guard hidden != isHiddenByConfig else { return }
        let wasHidden = isHidden
        isHiddenByConfig = hidden
        if hidden {
            // A chevron hide already in flight is now redundant, and leaving its
            // pointer monitor running would show the bar again on the next
            // mouse move despite the file saying to keep it hidden.
            stopWatchingPointer()
            isHiddenByChevron = false
            // The collapsed button goes too. The file is now the reason the bar
            // is away, and a button offering to bring it back would not work.
            isCollapsed = false
        }
        guard isHidden != wasHidden else { return }
        NotificationCenter.default.post(name: .stegeBarVisibilityChanged, object: nil)
    }

    /// Flips the shortcut's own hidden state.
    ///
    /// Unlike the chevron this does not watch the pointer or start a timer. The
    /// shortcut that hid the bar is the way back, so there is nothing to
    /// recover from, and a bar that reappeared on its own would fight the key
    /// press that put it away.
    func toggleByShortcut() {
        let wasHidden = isHidden
        isHiddenByShortcut.toggle()
        if isHiddenByShortcut {
            // A chevron hide already in flight would otherwise show the bar
            // again on the next mouse move, undoing the shortcut.
            stopWatchingPointer()
            isHiddenByChevron = false
            isCollapsed = false
        }
        guard isHidden != wasHidden else { return }
        NotificationCenter.default.post(name: .stegeBarVisibilityChanged, object: nil)
    }

    func show() {
        guard isHiddenByChevron else { return }
        isHiddenByChevron = false
        stopWatchingPointer()
        // Still hidden for another reason, so nothing on screen changed.
        guard !isHiddenByConfig, !isHiddenByShortcut, !isCollapsed else {
            return
        }
        NotificationCenter.default.post(name: .stegeBarVisibilityChanged, object: nil)
    }

    private func startWatchingPointer() {
        // Global monitors only observe, they never swallow the event, so this
        // cannot interfere with clicking the menu bar it just revealed.
        pointerMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown]
        ) { [weak self] _ in
            self?.checkPointer()
        }
        // Safety net for the case where the pointer never moves again, for
        // instance when focus goes to another space entirely.
        fallbackTimer = Timer.scheduledTimer(
            withTimeInterval: timeout, repeats: false
        ) { [weak self] _ in
            self?.show()
        }
    }

    private func stopWatchingPointer() {
        if let monitor = pointerMonitor { NSEvent.removeMonitor(monitor) }
        pointerMonitor = nil
        fallbackTimer?.invalidate()
        fallbackTimer = nil
    }

    private func checkPointer() {
        let location = NSEvent.mouseLocation
        // Measure against the display the pointer is actually on, otherwise the
        // bar returns at the wrong moment on a second monitor whose top edge
        // sits at a different height.
        let screen =
            NSScreen.screens.first { $0.frame.contains(location) }
            ?? NSScreen.main
        guard let screen else { return }
        // `mouseLocation` is bottom-left origin, so distance from the top edge
        // is the screen's top minus the pointer's y.
        let distanceFromTop = screen.frame.maxY - location.y
        if distanceFromTop > returnThreshold { show() }
    }
}

extension Notification.Name {
    static let stegeBarVisibilityChanged = Notification.Name(
        "stegeBarVisibilityChanged")
}
