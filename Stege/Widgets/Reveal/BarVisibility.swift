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

    @Published private(set) var isHidden = false

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
        isHidden = true
        NotificationCenter.default.post(name: .stegeBarVisibilityChanged, object: nil)
        startWatchingPointer()
    }

    func show() {
        guard isHidden else { return }
        isHidden = false
        stopWatchingPointer()
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
