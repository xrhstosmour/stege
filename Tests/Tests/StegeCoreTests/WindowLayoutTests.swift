import CoreGraphics
import Testing

@testable import StegeCore

struct WindowLayoutTests {
    private let entries: [WindowLayout.Entry] = [
        .init(number: 93, processID: 10, bounds: CGRect(x: 5, y: 49, width: 700, height: 400)),
        .init(number: 115, processID: 20, bounds: CGRect(x: 800, y: 49, width: 600, height: 500)),
    ]

    @Test func matchesAWindowByProcessAndPosition() {
        let number = WindowLayout.number(
            processID: 20, frame: CGRect(x: 800, y: 49, width: 600, height: 500),
            among: entries)
        #expect(number == 115)
    }

    @Test func toleratesAPointOfRounding() {
        let number = WindowLayout.number(
            processID: 10, frame: CGRect(x: 5.4, y: 49.6, width: 699.5, height: 400.4),
            among: entries)
        #expect(number == 93)
    }

    @Test func doesNotMatchAnotherProcessInTheSameSpot() {
        let number = WindowLayout.number(
            processID: 99, frame: CGRect(x: 5, y: 49, width: 700, height: 400),
            among: entries)
        #expect(number == nil)
    }

    @Test func doesNotMatchAWindowThatMoved() {
        let number = WindowLayout.number(
            processID: 10, frame: CGRect(x: 5, y: 80, width: 700, height: 400),
            among: entries)
        #expect(number == nil)
    }

    @Test func parsesOneWindowPerLine() {
        let layouts = WindowLayout.parse("93 h_tiles\n115 floating\n")
        #expect(layouts == [93: "h_tiles", 115: "floating"])
    }

    @Test func skipsLinesItCannotRead() {
        let layouts = WindowLayout.parse("junk\n7 floating\nx y\n\n8 v_tiles extra\n")
        #expect(layouts == [7: "floating"])
    }

    @Test func aTiledWindowIsLeftToTheWindowManager() {
        #expect(WindowLayout.decision(number: 93, layouts: [93: "h_tiles"]) == .leaveToWindowManager)
        #expect(WindowLayout.decision(number: 93, layouts: [93: "v_accordion"]) == .leaveToWindowManager)
    }

    @Test func aFloatingWindowMayBeMoved() {
        #expect(WindowLayout.decision(number: 115, layouts: [115: "floating"]) == .mayMove)
    }

    @Test func aWindowAeroSpaceDoesNotListMayBeMoved() {
        #expect(WindowLayout.decision(number: 55, layouts: [93: "h_tiles"]) == .mayMove)
        #expect(WindowLayout.decision(number: nil, layouts: [93: "h_tiles"]) == .mayMove)
    }
}
