import CoreGraphics
import Foundation

/// How far down from the top of a screen a window has to start to clear the
/// bar.
///
/// The bar is drawn over the screen, so macOS reserves nothing for it. What
/// macOS does reserve is its own menu bar strip, which `visibleFrame` already
/// excludes, and a window manager lays windows out inside `visibleFrame`. The
/// bar only has to claim the part of itself that strip does not already cover,
/// so a hand-written number goes wrong the moment the bar height changes or a
/// screen reserves a different strip, which the notch does not share with an
/// external display.
enum BarInset {
    /// Matches the window manager's own gap between windows, so the bar looks
    /// spaced like one more neighbour rather than a wall.
    static let windowGap: CGFloat = 5

    /// Whole points, rounded up: a fractional inset leaves a seam of the
    /// window underneath showing, a larger one costs nothing visible.
    static func points(
        barHeight: CGFloat, screenFrame: CGRect, visibleFrame: CGRect,
        gap: CGFloat = windowGap
    ) -> Int {
        let reserved = max(0, screenFrame.maxY - visibleFrame.maxY)
        return Int(max(0, barHeight + gap - reserved).rounded(.up))
    }
}
