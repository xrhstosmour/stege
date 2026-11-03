import CoreGraphics
import Testing

@testable import StegeCore

struct BarInsetTests {
    private let notched = CGRect(x: 0, y: 0, width: 1470, height: 956)
    private let notchedVisible = CGRect(x: 0, y: 0, width: 1470, height: 924)
    private let external = CGRect(x: 0, y: 0, width: 2560, height: 1440)

    /// Measured on the built-in display: macOS holds back 32 points, so a 44
    /// point bar plus the 5 point gap needs 17 more.
    @Test func theNotchedStripCountsTowardTheBar() {
        let inset = BarInset.points(
            barHeight: 44, screenFrame: notched, visibleFrame: notchedVisible)
        #expect(inset == 17)
    }

    @Test func aScreenReservingNothingNeedsTheWholeBar() {
        let inset = BarInset.points(
            barHeight: 44, screenFrame: external, visibleFrame: external)
        #expect(inset == 49)
    }

    @Test func aBarShorterThanTheReservedStripClampsToZero() {
        let inset = BarInset.points(
            barHeight: 20, screenFrame: notched, visibleFrame: notchedVisible)
        #expect(inset == 0)
    }

    @Test func aFractionalHeightRoundsUp() {
        let inset = BarInset.points(
            barHeight: 44.4, screenFrame: external, visibleFrame: external)
        #expect(inset == 50)
    }
}
