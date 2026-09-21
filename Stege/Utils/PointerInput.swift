import AppKit
import SwiftUI

/// A trackpad reports many small deltas where a wheel reports one large one,
/// so the two are brought onto the same scale before a widget decides what a
/// notch is worth. `nil` when the event carried no motion. Shared by
/// `PointerInput` and `ScrollPassthrough` below, the only two places in the
/// app that read a scroll wheel.
private func normalizedScrollDelta(for event: NSEvent) -> CGFloat? {
    let delta =
        event.hasPreciseScrollingDeltas
        ? event.scrollingDeltaY / 10 : event.scrollingDeltaY
    return delta == 0 ? nil : delta
}

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
            guard let delta = normalizedScrollDelta(for: event) else { return }
            onScroll?(delta)
        }

        override func rightMouseDown(with event: NSEvent) {
            onRightClick?()
        }
    }
}

/// Scroll wheel only, everywhere else it is as if this view were not there.
///
/// A popup has real controls stacked in it, a slider to drag, rows to click,
/// a mute glyph to tap, all plain SwiftUI gestures with nothing of their own
/// in the `NSView` tree. Sitting `PointerInput` over the whole popup would
/// claim every one of those clicks, because a plain `NSView`'s `hitTest`
/// claims any point in its bounds no matter which handlers it overrides.
/// This instead answers `hitTest` with itself only while the event being
/// dispatched is a scroll, and with `nil`, meaning "not me, look further,"
/// for everything else, so a click still lands on whatever SwiftUI drew
/// underneath.
struct ScrollPassthrough: NSViewRepresentable {
    /// Positive scrolling up, in wheel units already normalised for a trackpad.
    var onScroll: (CGFloat) -> Void = { _ in }

    func makeNSView(context: Context) -> ScrollCatcherView {
        let view = ScrollCatcherView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ view: ScrollCatcherView, context: Context) {
        view.onScroll = onScroll
    }

    final class ScrollCatcherView: NSView {
        var onScroll: ((CGFloat) -> Void)?

        /// `NSApp.currentEvent` is the event AppKit is in the middle of
        /// dispatching when it asks a view tree for its hit test target, so
        /// this can tell a scroll apart from a click without the event
        /// itself being passed in. It is an ambient, application-wide value
        /// rather than something scoped to this call, so the window is
        /// checked too, `hitTest` only ever runs for events actually
        /// addressed to this popup's own window, and a stale or unrelated
        /// event sitting in `currentEvent` from elsewhere cannot make this
        /// view claim a point it was not asked about.
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent,
                event.type == .scrollWheel,
                event.window == window
            else { return nil }
            return super.hitTest(point)
        }

        override func scrollWheel(with event: NSEvent) {
            guard let delta = normalizedScrollDelta(for: event) else { return }
            onScroll?(delta)
        }
    }
}
