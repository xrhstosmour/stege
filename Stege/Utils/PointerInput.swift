import AppKit
import SwiftUI

/// Scroll wheel and right click, for widgets in the bar.
///
/// SwiftUI has no gesture for either on macOS. `onTapGesture` sees only the
/// left button, and there is no scroll gesture at all outside a scroll view.
///
/// The same reasoning as `HoverTracker` applies to why this is an `NSView`
/// rather than a global event monitor: a monitor is not delivered events that
/// land on this process's own windows, and the bar is one.
/// It takes the left click too. Sitting over the widget it would swallow one
/// aimed at a SwiftUI gesture underneath, so it owns all three buttons rather
/// than leaving one of them half working.
struct PointerInput: NSViewRepresentable {
    var onClick: () -> Void = {}
    /// Positive scrolling up, in wheel units already normalised for a trackpad.
    var onScroll: (CGFloat) -> Void = { _ in }
    var onRightClick: () -> Void = {}

    func makeNSView(context: Context) -> InputView {
        let view = InputView()
        view.onClick = onClick
        view.onScroll = onScroll
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ view: InputView, context: Context) {
        view.onClick = onClick
        view.onScroll = onScroll
        view.onRightClick = onRightClick
    }

    final class InputView: NSView {
        var onClick: (() -> Void)?
        var onScroll: ((CGFloat) -> Void)?
        var onRightClick: (() -> Void)?

        /// The bar is almost never the active application, so without this the
        /// first click would only bring it forward and the second would be the
        /// one that did anything.
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) { onClick?() }

        override func scrollWheel(with event: NSEvent) {
            // A trackpad reports many small deltas where a wheel reports one
            // large one, so the two are brought onto the same scale before the
            // widget decides what a notch is worth.
            let delta =
                event.hasPreciseScrollingDeltas
                ? event.scrollingDeltaY / 10 : event.scrollingDeltaY
            guard delta != 0 else { return }
            onScroll?(delta)
        }

        override func rightMouseDown(with event: NSEvent) {
            onRightClick?()
        }
    }
}
