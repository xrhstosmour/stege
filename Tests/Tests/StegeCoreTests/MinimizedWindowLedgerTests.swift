import Testing

@testable import StegeCore

struct MinimizedWindowLedgerTests {
    private func note(
        _ id: Int, workspace: String = "2", app: String? = "Google Chrome"
    ) -> MinimizedWindowNote {
        MinimizedWindowNote(
            id: id, workspace: workspace, title: "A window",
            appName: app, bundleID: "com.google.Chrome", monitorScreenID: 1)
    }

    private func notes(_ values: [MinimizedWindowNote])
        -> [Int: MinimizedWindowNote]
    {
        Dictionary(uniqueKeysWithValues: values.map { ($0.id, $0) })
    }

    @Test func remembersWhereEveryReportedWindowIs() {
        let result = MinimizedWindowLedger.noting(
            [:], reported: [note(1), note(2, workspace: "3")])
        #expect(result.count == 2)
        #expect(result[1]?.workspace == "2")
        #expect(result[2]?.workspace == "3")
    }

    @Test func aReportedWindowOverwritesWhatWasKnownAboutIt() {
        let result = MinimizedWindowLedger.noting(
            notes([note(1, workspace: "2")]),
            reported: [note(1, workspace: "5")])
        #expect(result[1]?.workspace == "5")
    }

    @Test func nothingIsUnreportedWhenEveryNoteIsListed() {
        #expect(
            !MinimizedWindowLedger.hasUnreported(
                notes: notes([note(1)]), reported: [note(1)]))
    }

    @Test func aNoteWithNoReportIsUnreported() {
        #expect(
            MinimizedWindowLedger.hasUnreported(
                notes: notes([note(1), note(2)]), reported: [note(1)]))
    }

    @Test func anUnreportedWindowThatStillExistsIsRestored() {
        let outcome = MinimizedWindowLedger.reconcile(
            notes: notes([note(1), note(2)]),
            reported: [note(1)],
            liveOwners: [1: "Google Chrome", 2: "Google Chrome"],
            minimizedTitles: ["Google Chrome": ["A window"]])
        #expect(outcome.restore.map(\.id) == [2])
        #expect(outcome.keep.keys.sorted() == [1, 2])
    }

    @Test func anUnreportedWindowThatIsGoneIsForgotten() {
        let outcome = MinimizedWindowLedger.reconcile(
            notes: notes([note(1), note(2)]),
            reported: [note(1)],
            liveOwners: [1: "Google Chrome"],
            minimizedTitles: ["Google Chrome": ["A window"]])
        #expect(outcome.restore.isEmpty)
        #expect(outcome.keep.keys.sorted() == [1])
    }

    /// The window server reuses identifiers across a restart and these notes
    /// outlive one, so an identifier alone would draw the wrong icon.
    @Test func anIdentifierTakenOverByAnotherApplicationIsForgotten() {
        let outcome = MinimizedWindowLedger.reconcile(
            notes: notes([note(2, app: "Google Chrome")]),
            reported: [],
            liveOwners: [2: "Spotify"],
            minimizedTitles: ["Google Chrome": ["A window"]])
        #expect(outcome.restore.isEmpty)
        #expect(outcome.keep.isEmpty)
    }

    @Test func aNoteWithNoApplicationNameIsMatchedOnTheIdentifierAlone() {
        let outcome = MinimizedWindowLedger.reconcile(
            notes: notes([note(2, app: nil)]),
            reported: [],
            liveOwners: [2: "Spotify"],
            minimizedTitles: ["Google Chrome": ["A window"]])
        #expect(outcome.restore.map(\.id) == [2])
    }

    @Test func restoredWindowsComeBackInIdentifierOrder() {
        let outcome = MinimizedWindowLedger.reconcile(
            notes: notes([note(9), note(3), note(6)]),
            reported: [],
            liveOwners: [
                9: "Google Chrome", 3: "Google Chrome", 6: "Google Chrome",
            ],
            minimizedTitles: ["Google Chrome": ["A window"]])
        #expect(outcome.restore.map(\.id) == [3, 6, 9])
    }

    @Test func aWindowThatComesBackIsNoLongerRestored() {
        let first = MinimizedWindowLedger.reconcile(
            notes: notes([note(1), note(2)]),
            reported: [note(1)],
            liveOwners: [1: "Google Chrome", 2: "Google Chrome"],
            minimizedTitles: ["Google Chrome": ["A window"]])
        let second = MinimizedWindowLedger.reconcile(
            notes: first.keep,
            reported: [note(1), note(2, workspace: "4")],
            liveOwners: [1: "Google Chrome", 2: "Google Chrome"],
            minimizedTitles: ["Google Chrome": ["A window"]])
        #expect(second.restore.isEmpty)
        #expect(second.keep[2]?.workspace == "4")
    }

    /// `Google Drive` kept its closed main window in the window server's list
    /// at layer zero and off screen for as long as it ran, so the identifier
    /// check passed and workspace two grew a pill for a window that was not
    /// there. The application itself does not call that window minimized.
    @Test func aClosedWindowTheWindowServerStillListsIsForgotten() {
        let outcome = MinimizedWindowLedger.reconcile(
            notes: notes([note(2)]),
            reported: [],
            liveOwners: [2: "Google Chrome"],
            minimizedTitles: [:])
        #expect(outcome.restore.isEmpty)
        #expect(outcome.keep.isEmpty)
    }

    @Test func aWindowMinimizedUnderAnotherTitleIsForgotten() {
        let outcome = MinimizedWindowLedger.reconcile(
            notes: notes([note(2)]),
            reported: [],
            liveOwners: [2: "Google Chrome"],
            minimizedTitles: ["Google Chrome": ["A different window"]])
        #expect(outcome.restore.isEmpty)
    }

    @Test func onlyTheOwnersOfAMissingNoteAreAsked() {
        #expect(
            MinimizedWindowLedger.unreportedOwners(
                notes: notes([note(1), note(2, app: "Spotify")]),
                reported: [note(1)]) == ["Spotify"]
        )
    }

    @Test func nothingIsAskedWhenEveryNoteWasReported() {
        #expect(
            MinimizedWindowLedger.unreportedOwners(
                notes: notes([note(1)]), reported: [note(1)]).isEmpty
        )
    }
}
