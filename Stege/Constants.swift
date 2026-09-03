import CoreFoundation

struct Constants {
    static let menuBarHeight = CGFloat(55)
    /// How long a popup takes to appear or go away.
    ///
    /// 350 milliseconds with a spring, which is about twice as long as any
    /// panel macOS opens. Control Center and the menu bar extras land in
    /// roughly 150, and a bar that is meant to pass for the system's own
    /// should not be visibly slower than it.
    static let menuBarPopupAnimationDurationInMilliseconds = 150
    /// Extra clearance at the right edge, on top of the horizontal padding,
    /// for the dot macOS draws while the microphone, the camera or the screen
    /// is being read.
    ///
    /// The system draws it above everything, in the corner, whatever is
    /// underneath. Hiding the real menu bar does not take it away, and nothing
    /// can: it is the one mark macOS will not let an application cover. So the
    /// bar stops short of it rather than having the clock drawn through.
    ///
    /// Measured on a running system by capturing the corner with and without a
    /// capture in progress and diffing the two: the dot spans 13.5 to 22.0
    /// points in from the right edge, 8.5 points across. So the bar's content
    /// has to stop 22 points short of the edge, and this is that plus a hair.
    ///
    /// This is the *total* clearance, not an addition. `trailingPadding`
    /// defaults to whatever is left after the horizontal padding, so a wide
    /// padding buys nothing extra and a narrow one is topped up. The previous
    /// value was 4, on top of a measurement that had the dot 11 points in, and
    /// with a horizontal padding of 12 the clock was drawn under it.
    static let privacyIndicatorClearance = CGFloat(24)

    static let menuBarHorizontalPadding = CGFloat(25)
}
