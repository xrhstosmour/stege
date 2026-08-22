import AppKit
import Combine

/// Where the pointer is, in screen coordinates.
///
/// SwiftUI's `onHover` cannot be used for this. It installs a tracking area
/// scoped to the active application, and the bar lives in a non-activating
/// panel that is almost never the active application, so the callback simply
/// never fires. A global event monitor is how the reveal chevron already
/// solves the same problem.
///
/// Shared and reference counted, so a configuration that never asks for
/// pointer tracking installs no monitor at all.
final class PointerMonitor: ObservableObject {
    static let shared = PointerMonitor()

    @Published private(set) var location: CGPoint = .zero

    private var monitor: Any?
    private var subscribers = 0

    private init() {}

    func retain() {
        subscribers += 1
        guard subscribers == 1 else { return }
        location = NSEvent.mouseLocation
        // Global monitors only observe, they never swallow the event, so this
        // cannot interfere with clicking whatever it is tracking over.
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) {
            [weak self] _ in
            self?.location = NSEvent.mouseLocation
        }
    }

    func release() {
        subscribers = max(0, subscribers - 1)
        guard subscribers == 0 else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// Whether the pointer is inside a rectangle expressed in the coordinate
    /// space SwiftUI reports through `frame(in: .global)`.
    ///
    /// That space has its origin at the top left of the panel, which covers the
    /// whole screen, while `mouseLocation` has its origin at the bottom left of
    /// the desktop. The conversion has to be made against the display the
    /// pointer is actually on, or it is wrong by the height of another screen.
    func isInside(_ rect: CGRect) -> Bool {
        guard !rect.isEmpty else { return false }
        let point = location
        guard
            let screen = NSScreen.screens.first(where: {
                $0.frame.contains(point)
            }) ?? NSScreen.main
        else { return false }
        let converted = CGPoint(
            x: point.x - screen.frame.minX,
            y: screen.frame.maxY - point.y)
        return rect.contains(converted)
    }
}
