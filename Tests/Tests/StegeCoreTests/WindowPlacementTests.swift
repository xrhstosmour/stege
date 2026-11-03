import CoreGraphics
import Testing

@testable import StegeCore

struct WindowPlacementTests {
    private let primary = WindowPlacement.Screen(
        frame: CGRect(x: 0, y: 0, width: 1470, height: 956),
        visibleFrame: CGRect(x: 0, y: 80, width: 1470, height: 844))
    /// Sits above the primary, so in Accessibility coordinates its top is
    /// negative.
    private let above = WindowPlacement.Screen(
        frame: CGRect(x: 0, y: 956, width: 2560, height: 1440),
        visibleFrame: CGRect(x: 0, y: 956, width: 2560, height: 1440))

    @Test func aWindowUnderTheBarMovesToItsBottomEdge() throws {
        let moved = try #require(
            WindowPlacement.nudged(
                frame: CGRect(x: 100, y: 0, width: 600, height: 400),
                screens: [primary], barHeight: 44))
        #expect(moved.origin.y == 44)
        #expect(moved.height == 400)
    }

    @Test func aWindowAlreadyBelowTheBarIsLeftAlone() {
        let moved = WindowPlacement.nudged(
            frame: CGRect(x: 100, y: 60, width: 600, height: 400),
            screens: [primary], barHeight: 44)
        #expect(moved == nil)
    }

    @Test func aWindowPushedPastTheDockIsShrunkToTheVisibleBottom() throws {
        let moved = try #require(
            WindowPlacement.nudged(
                frame: CGRect(x: 0, y: 0, width: 600, height: 900),
                screens: [primary], barHeight: 44))
        // Visible bottom is 956 - 80 = 876 from the top.
        #expect(moved.maxY == 876)
    }

    @Test func aScreenAboveThePrimaryUsesItsOwnTop() throws {
        // Flipped, its top is 956 - 2396 = -1440, so the bar's bottom is at
        // -1396.
        let moved = try #require(
            WindowPlacement.nudged(
                frame: CGRect(x: 100, y: -1440, width: 600, height: 400),
                screens: [primary, above], barHeight: 44))
        #expect(moved.origin.y == -1396)
    }

    @Test func aWindowOnNoScreenIsLeftAlone() {
        let moved = WindowPlacement.nudged(
            frame: CGRect(x: 9000, y: 9000, width: 600, height: 400),
            screens: [primary], barHeight: 44)
        #expect(moved == nil)
    }
}
