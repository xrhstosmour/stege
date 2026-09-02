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
    /// Measured rather than guessed: the dot spans 6 to 11 points in from the
    /// right edge and is 6 points across. The horizontal padding alone already
    /// clears it, so this only buys a visible gap.
    static let privacyIndicatorClearance = CGFloat(4)

    static let menuBarHorizontalPadding = CGFloat(25)
}
