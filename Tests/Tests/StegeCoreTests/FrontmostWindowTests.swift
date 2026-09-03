import Testing

@testable import StegeCore

struct FrontmostWindowTests {
    private func entry(_ number: Int, _ pid: Int32, _ layer: Int)
        -> FrontmostWindow.Entry
    {
        FrontmostWindow.Entry(
            number: number, ownerProcessIdentifier: pid, layer: layer)
    }

    @Test func theFrontmostWindowOfTheFrontmostApplication() {
        #expect(
            FrontmostWindow.identifier(
                in: [entry(10, 500, 0), entry(11, 600, 0)], frontmost: 500)
                == 10
        )
    }

    @Test func anotherApplicationInFrontIsSkipped() {
        #expect(
            FrontmostWindow.identifier(
                in: [entry(10, 600, 0), entry(11, 500, 0)], frontmost: 500)
                == 11
        )
    }

    @Test func aPaletteAboveTheWindowIsSkipped() {
        #expect(
            FrontmostWindow.identifier(
                in: [entry(9, 500, 3), entry(10, 500, 0)], frontmost: 500)
                == 10
        )
    }

    @Test func theFirstOfSeveralWindowsWins() {
        #expect(
            FrontmostWindow.identifier(
                in: [entry(10, 500, 0), entry(11, 500, 0)], frontmost: 500)
                == 10
        )
    }

    @Test func anApplicationWithNoOrdinaryWindowHasNone() {
        #expect(
            FrontmostWindow.identifier(
                in: [entry(9, 500, 3), entry(10, 600, 0)], frontmost: 500)
                == nil
        )
    }

    @Test func anEmptyListHasNone() {
        #expect(FrontmostWindow.identifier(in: [], frontmost: 500) == nil)
    }
}
