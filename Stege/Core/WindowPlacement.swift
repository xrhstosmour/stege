import CoreGraphics

/// Where a window has to move so it does not sit under the bar.
///
/// Pure geometry, kept apart from the Accessibility calls so the coordinate
/// flip can be tested. Accessibility measures downward from the top-left of the
/// primary screen, AppKit upward from its bottom-left, and a screen above or
/// beside the primary is where the two disagree.
enum WindowPlacement {
    struct Screen: Equatable {
        /// AppKit coordinates, as `NSScreen.frame` and `visibleFrame` give them.
        let frame: CGRect
        let visibleFrame: CGRect
    }

    /// The new frame in Accessibility coordinates, or nil when the window
    /// already clears the bar, or sits on no screen.
    ///
    /// The window is shrunk by whatever it is pushed past the bottom of the
    /// visible area, which is above the Dock where there is one, otherwise its
    /// bottom edge would leave the screen. It is never shrunk below a sliver,
    /// so a window the user made tiny is not collapsed.
    static func nudged(
        frame: CGRect, screens: [Screen], barHeight: CGFloat
    ) -> CGRect? {
        guard let primary = screens.first else { return nil }
        let flip: (CGRect) -> CGRect = { rect in
            CGRect(
                x: rect.minX, y: primary.frame.maxY - rect.maxY,
                width: rect.width, height: rect.height)
        }
        let probe = CGPoint(x: frame.midX, y: frame.minY + 1)
        guard let screen = screens.first(where: { flip($0.frame).contains(probe) })
        else { return nil }

        let top = flip(screen.frame).minY
        let barBottom = top + barHeight
        let shift = barBottom - frame.minY
        guard shift > 0.5 else { return nil }

        var result = frame
        result.origin.y = barBottom
        let visibleBottom = flip(screen.visibleFrame).maxY
        if result.maxY > visibleBottom {
            result.size.height = max(visibleBottom - barBottom, 100)
        }
        return result
    }
}
