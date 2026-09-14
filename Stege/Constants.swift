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
    /// The corner dot's own size and column, keyed by `NSScreen.backingScaleFactor`.
    ///
    /// The system draws it above everything, in the corner, whatever is
    /// underneath, while the microphone, the camera or the screen is being
    /// read. Hiding the real menu bar does not take it away, and nothing can:
    /// it is the one mark macOS will not let an application cover.
    ///
    /// A dot drawn a fixed number of points wide should in principle look the
    /// same size everywhere, but the real system dot is composited by the
    /// WindowServer directly, a code path apps cannot inspect, and it does
    /// not: on an external display at a different scale factor both the size
    /// and the right-edge span it was measured at can be wrong, and are not a
    /// simple multiple of the Retina measurement either. Each entry has to be
    /// measured on its own scale factor rather than derived from another by a
    /// formula.
    struct PrivacyIndicatorGeometry {
        let diameter: CGFloat
        let columnCenter: CGFloat
    }

    private static let privacyIndicatorGeometryByScale:
        [Int: PrivacyIndicatorGeometry] = [
            // Measured on the built-in Retina panel by capturing the corner
            // with and without a capture in progress and diffing the two: the
            // dot spans 13.5 to 22.0 points in from the right edge, 8.5 points
            // across.
            2: PrivacyIndicatorGeometry(
                diameter: 8, columnCenter: CGFloat(13.5 + 22.0) / 2),
            // Measured the same way on two 1920x1080 external monitors, both
            // reporting a backingScaleFactor of 1: the dot spans 5 to 11
            // points in from the right edge, 6 points across. Nowhere near
            // double the Retina measurement in either direction.
            1: PrivacyIndicatorGeometry(
                diameter: 6, columnCenter: CGFloat(5 + 11) / 2),
        ]

    /// Falls back to the Retina measurement for a scale factor that has not
    /// been measured yet, on the same "closest available" basis the seeded
    /// entries used to sit on, rather than crashing on an external monitor
    /// nobody has checked.
    static func privacyIndicatorGeometry(forScale scale: CGFloat)
        -> PrivacyIndicatorGeometry
    {
        privacyIndicatorGeometryByScale[Int(scale.rounded())]
            ?? privacyIndicatorGeometryByScale[2]!
    }

    /// Extra clearance at the right edge, on top of the horizontal padding,
    /// so the bar's own content stops short of the dot above rather than
    /// having the clock drawn through it.
    ///
    /// Scaled to the screen the bar is drawn on, because the dot itself is:
    /// applying the Retina clearance to a 1x external monitor as well left a
    /// stretch of unused padding on the external that nothing there needed to
    /// reserve.
    ///
    /// A hair beyond the dot's own outer edge, not flush with it: flush is
    /// where an earlier, smaller measurement still had the clock drawn under
    /// the dot on the built-in panel.
    static func privacyIndicatorClearance(forScale scale: CGFloat) -> CGFloat {
        let geometry = privacyIndicatorGeometry(forScale: scale)
        return geometry.columnCenter + geometry.diameter / 2 + 2
    }

    static let menuBarHorizontalPadding = CGFloat(25)
}
