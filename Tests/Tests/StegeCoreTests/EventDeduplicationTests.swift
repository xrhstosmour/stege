import Foundation
import Testing

@testable import StegeCore

struct EventDeduplicationTests {
    @Test func aRepeatedIdentifierAtTheSameStartDateIsCollapsed() {
        let startDate = Date()
        #expect(
            EventDeduplication.firstOccurrenceIndices(of: [
                (identifier: "team-sync", startDate: startDate),
                (identifier: "team-sync", startDate: startDate),
            ]) == [0])
    }

    /// A recurring event's occurrences all share the same identifier, so two
    /// of them landing on the same day must not collapse into one.
    @Test func theSameIdentifierAtDifferentStartDatesBothSurvive() {
        let first = Date()
        let second = first.addingTimeInterval(3600)
        #expect(
            EventDeduplication.firstOccurrenceIndices(of: [
                (identifier: "hourly-reminder", startDate: first),
                (identifier: "hourly-reminder", startDate: second),
            ]) == [0, 1])
    }

    /// Two events with no identifier at all are not the same event just
    /// because neither has one.
    @Test func twoNilIdentifiersAreNeverCollapsedTogether() {
        let startDate = Date()
        #expect(
            EventDeduplication.firstOccurrenceIndices(of: [
                (identifier: nil, startDate: startDate),
                (identifier: nil, startDate: startDate),
            ]) == [0, 1])
    }

    @Test func distinctIdentifiersAllSurvive() {
        let startDate = Date()
        #expect(
            EventDeduplication.firstOccurrenceIndices(of: [
                (identifier: "a", startDate: startDate),
                (identifier: "b", startDate: startDate),
                (identifier: "c", startDate: startDate),
            ]) == [0, 1, 2])
    }

    /// `calendarItemExternalIdentifier` comes back `""`, not `nil`, for an
    /// event that was never synced anywhere.
    @Test func normalizedIdentifierTreatsEmptyStringAsNil() {
        #expect(EventDeduplication.normalizedIdentifier("") == nil)
        #expect(EventDeduplication.normalizedIdentifier(nil) == nil)
        #expect(
            EventDeduplication.normalizedIdentifier("team-sync")
                == "team-sync")
    }
}
