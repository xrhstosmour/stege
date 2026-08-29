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
    static let menuBarHorizontalPadding = CGFloat(25)
}
