import Testing

@testable import StegeCore

struct AerospaceGapsTests {
    private let value = "[{ monitor.built-in = 17 }, 49]"
    private var line: String { "outer.top = \(value)" }

    @Test func buildsTheValueWithBuiltInKeywordAndFallbackLast() {
        let result = AerospaceGaps.outerTopValue(
            entries: [.init(monitor: "Built-in Retina Display", points: 17, isBuiltIn: true)],
            fallback: 49)
        #expect(result == value)
    }

    @Test func writesABareNumberWhenNoScreenDiffersFromTheFallback() {
        let result = AerospaceGaps.outerTopValue(entries: [], fallback: 49)
        #expect(result == "49")
    }

    @Test func escapesAnExternalNameForAeroSpaceRegularExpression() {
        let result = AerospaceGaps.outerTopValue(
            entries: [.init(monitor: "LG (27)", points: 49, isBuiltIn: false)],
            fallback: 49)
        #expect(result == #"[{ monitor."LG \\(27\\)" = 49 }, 49]"#)
    }

    @Test func replacesAHandWrittenLineAndAddsTheMarker() {
        let original = "[gaps]\nouter.left = 5\nouter.top = 20\nouter.right = 5\n"
        let result = AerospaceGaps.rewrite(original, outerTop: value)
        #expect(
            result
                == "[gaps]\nouter.left = 5\n\(AerospaceGaps.marker)\n\(line)\nouter.right = 5\n")
    }

    @Test func isIdempotent() throws {
        let once = try #require(
            AerospaceGaps.rewrite("[gaps]\nouter.top = 20\n", outerTop: value))
        #expect(AerospaceGaps.rewrite(once, outerTop: value) == once)
    }

    @Test func updatesALineItAlreadyOwnsWithoutAddingASecondMarker() throws {
        let once = try #require(
            AerospaceGaps.rewrite("[gaps]\nouter.top = 20\n", outerTop: value))
        let twice = try #require(
            AerospaceGaps.rewrite(once, outerTop: "[{ monitor.built-in = 3 }, 9]"))
        #expect(twice.components(separatedBy: AerospaceGaps.marker).count == 2)
        #expect(twice.contains("outer.top = [{ monitor.built-in = 3 }, 9]"))
    }

    @Test func insertsUnderGapsWhenTheKeyIsMissing() {
        let result = AerospaceGaps.rewrite("[gaps]\ninner.vertical = 5\n", outerTop: value)
        #expect(
            result == "[gaps]\n\(AerospaceGaps.marker)\n\(line)\ninner.vertical = 5\n")
    }

    @Test func appendsATableWhenThereIsNone() {
        let result = AerospaceGaps.rewrite("start-at-login = true\n", outerTop: value)
        #expect(
            result
                == "start-at-login = true\n\n[gaps]\n\(AerospaceGaps.marker)\n\(line)\n")
    }

    @Test func leavesAnotherTablesOuterTopAlone() {
        let original = "[gaps]\ninner.vertical = 5\n[other]\nouter.top = 1\n"
        let result = AerospaceGaps.rewrite(original, outerTop: value)
        #expect(result?.hasSuffix("[other]\nouter.top = 1\n") == true)
    }

    @Test func refusesAMultiLineValue() {
        let original = "[gaps]\nouter.top = [\n  49,\n]\n"
        #expect(AerospaceGaps.rewrite(original, outerTop: value) == nil)
    }

    @Test func refusesTwoGapsTables() {
        #expect(AerospaceGaps.rewrite("[gaps]\n[gaps]\n", outerTop: value) == nil)
    }

    @Test func keepsACarriageReturnFileOnItsOwnLineEnding() throws {
        let original = "[gaps]\r\nouter.top = 20\r\n"
        let result = try #require(AerospaceGaps.rewrite(original, outerTop: value))
        #expect(!result.replacingOccurrences(of: "\r\n", with: "").contains("\n"))
        #expect(result.components(separatedBy: "[gaps]").count == 2)
        #expect(AerospaceGaps.rewrite(result, outerTop: value) == result)
    }

    @Test func recognisesAHeaderWithSpacesAndATrailingComment() throws {
        let result = try #require(
            AerospaceGaps.rewrite("[ gaps ] # spacing\nouter.top = 20\n", outerTop: value))
        #expect(!result.contains("\n[gaps]"))
        #expect(result.contains(line))
    }

    @Test func refusesGapsWrittenAsRootDottedKeys() {
        #expect(AerospaceGaps.rewrite("gaps.outer.top = 10\n", outerTop: value) == nil)
        #expect(AerospaceGaps.rewrite("gaps = { outer.top = 10 }\n", outerTop: value) == nil)
    }

    private func screen(_ name: String, builtIn: Bool = false, _ points: Int)
        -> AerospaceGaps.Screen
    {
        .init(name: name, isBuiltIn: builtIn, points: points)
    }

    @Test func aDisplayThatNeedsTheFallbackGetsNoEntry() {
        let entries = AerospaceGaps.entries(
            for: [screen("Dell", 49), screen("LG", 49)], fallback: 49)
        #expect(entries.isEmpty)
    }

    @Test func aNotchedBuiltInGetsTheBuiltInKeywordEntry() {
        let entries = AerospaceGaps.entries(
            for: [screen("Dell", 49), screen("Built-in Retina Display", builtIn: true, 17)],
            fallback: 49)
        #expect(entries == [.init(monitor: "built-in", points: 17, isBuiltIn: true)])
    }

    @Test func anExternalWithAReservedStripGetsANamedEntry() {
        let entries = AerospaceGaps.entries(
            for: [screen("Dell", 25)], fallback: 49)
        #expect(entries == [.init(monitor: "Dell", points: 25, isBuiltIn: false)])
    }

    @Test func twoIdenticalNamesKeepTheLargerInset() {
        let entries = AerospaceGaps.entries(
            for: [screen("Dell", 10), screen("Dell", 25)], fallback: 49)
        #expect(entries.map(\.points) == [25])
    }

    @Test func aDisplayWithNoNameIsLeftToTheFallback() {
        let entries = AerospaceGaps.entries(
            for: [screen("  ", 10)], fallback: 49)
        #expect(entries.isEmpty)
    }

    @Test func theOrderDoesNotDependOnAttachOrder() {
        let a = [screen("B", 10), screen("A", 20), screen("N", builtIn: true, 5)]
        let first = AerospaceGaps.entries(for: a, fallback: 49)
        let second = AerospaceGaps.entries(for: a.reversed(), fallback: 49)
        #expect(first == second)
        #expect(first.map(\.monitor) == ["built-in", "A", "B"])
    }
}
