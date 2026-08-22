import AppKit
import SwiftUI

/// Reports whether the pointer is over the view it is attached to, even while
/// Stege is not the active application.
///
/// Neither of the obvious approaches works for the bar:
///
/// SwiftUI's `onHover` installs a tracking area scoped to the active
/// application, and the bar lives in a non-activating panel that is almost
/// never active, so it never fires.
///
/// A global `NSEvent` monitor does not see events that land on this process's
/// own windows, and the bar is one, so the pointer effectively disappears the
/// moment it arrives over the thing being tracked.
///
/// An `NSTrackingArea` with `.activeAlways` is delivered regardless of which
/// application is active, which is exactly the case here.
struct HoverTracker: NSViewRepresentable {
    var onChange: (Bool) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.onChange = onChange
    }

    final class TrackingView: NSView {
        var onChange: ((Bool) -> Void)?
        private var trackingArea: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea { removeTrackingArea(trackingArea) }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self)
            addTrackingArea(area)
            trackingArea = area

            // The pointer can already be inside when the area is rebuilt, which
            // happens whenever the view resizes. Without this the state would
            // be stale until the pointer crossed an edge again.
            if let window, let location = window.mouseLocationOutsideOfEventStream
                as CGPoint?
            {
                let point = convert(location, from: nil)
                onChange?(bounds.contains(point))
            }
        }

        override func mouseEntered(with event: NSEvent) { onChange?(true) }
        override func mouseExited(with event: NSEvent) { onChange?(false) }
    }
}
