import Foundation
import Testing

@testable import StegeCore

struct EventDeduplicationTests {
    @Test func aRepeatedIdentifierAtTheSameStartDateIsCollapsed() {
        let startDate = Date()
        let endDate = startDate.addingTimeInterval(1800)
        #expect(
            EventDeduplication.firstOccurrenceIndices(of: [
                (
                    identifier: "team-sync", title: "Team Sync",
                    startDate: startDate, endDate: endDate
                ),
                (
                    identifier: "team-sync", title: "Team Sync",
                    startDate: startDate, endDate: endDate
                ),
            ]) == [0])
    }

    /// A recurring event's occurrences all share the same identifier, so two
    /// of them landing on the same day must not collapse into one.
    @Test func theSameIdentifierAtDifferentStartDatesBothSurvive() {
        let first = Date()
        let second = first.addingTimeInterval(3600)
        #expect(
            EventDeduplication.firstOccurrenceIndices(of: [
                (
                    identifier: "hourly-reminder", title: "Hourly Reminder",
                    startDate: first, endDate: first.addingTimeInterval(900)
                ),
                (
                    identifier: "hourly-reminder", title: "Hourly Reminder",
                    startDate: second, endDate: second.addingTimeInterval(900)
                ),
            ]) == [0, 1])
    }

    /// Two events with no identifier and different titles are not the same
    /// event just because neither has an identifier.
    @Test func twoNilIdentifiersWithDifferentTitlesBothSurvive() {
        let startDate = Date()
        let endDate = startDate.addingTimeInterval(1800)
        #expect(
            EventDeduplication.firstOccurrenceIndices(of: [
                (
                    identifier: nil, title: "Focus Time",
                    startDate: startDate, endDate: endDate
                ),
                (
                    identifier: nil, title: "Lunch",
                    startDate: startDate, endDate: endDate
                ),
            ]) == [0, 1])
    }

    @Test func distinctIdentifiersWithDistinctTitlesAllSurvive() {
        let startDate = Date()
        let endDate = startDate.addingTimeInterval(1800)
        #expect(
            EventDeduplication.firstOccurrenceIndices(of: [
                (identifier: "a", title: "A", startDate: startDate, endDate: endDate),
                (identifier: "b", title: "B", startDate: startDate, endDate: endDate),
                (identifier: "c", title: "C", startDate: startDate, endDate: endDate),
            ]) == [0, 1, 2])
    }

    /// The gap the identifier match alone could not close: a meeting synced
    /// into two calendars under two different identifiers, which the title
    /// pass still recognises as one meeting.
    @Test func distinctIdentifiersWithTheSameTitleAndTimesCollapse() {
        let startDate = Date()
        let endDate = startDate.addingTimeInterval(1800)
        #expect(
            EventDeduplication.firstOccurrenceIndices(of: [
                (
                    identifier: "personal-copy", title: "Roadmap Review",
                    startDate: startDate, endDate: endDate
                ),
                (
                    identifier: "shared-copy", title: "Roadmap Review",
                    startDate: startDate, endDate: endDate
                ),
            ]) == [0])
    }

    /// Two untitled events are not the same event just because neither has a
    /// title, the same reasoning the identifier pass already applies to
    /// `nil`.
    @Test func twoEmptyTitlesAreNeverCollapsedByTitleAlone() {
        let startDate = Date()
        let endDate = startDate.addingTimeInterval(1800)
        #expect(
            EventDeduplication.firstOccurrenceIndices(of: [
                (identifier: nil, title: "", startDate: startDate, endDate: endDate),
                (identifier: nil, title: "", startDate: startDate, endDate: endDate),
            ]) == [0, 1])
    }

    /// Same title and start, different end: two back-to-back meetings that
    /// happen to share a name, kept apart because only two of the three match.
    @Test func sameTitleAndStartButDifferentEndSurvivesBoth() {
        let startDate = Date()
        #expect(
            EventDeduplication.firstOccurrenceIndices(of: [
                (
                    identifier: nil, title: "1:1", startDate: startDate,
                    endDate: startDate.addingTimeInterval(900)
                ),
                (
                    identifier: nil, title: "1:1", startDate: startDate,
                    endDate: startDate.addingTimeInterval(1800)
                ),
            ]) == [0, 1])
    }

    /// An event dropped as a title duplicate must not also burn its
    /// identifier: event 1 collides with event 0 on title and is dropped,
    /// and event 2 shares event 1's identifier but has a distinct title of
    /// its own and must survive, since it was never actually a duplicate of
    /// anything.
    @Test func anEventDroppedByTitleDoesNotAlsoDropALaterDistinctIdentifier() {
        let startDate = Date()
        let endDate = startDate.addingTimeInterval(1800)
        #expect(
            EventDeduplication.firstOccurrenceIndices(of: [
                (
                    identifier: nil, title: "Standup", startDate: startDate,
                    endDate: endDate
                ),
                (
                    identifier: "x", title: "Standup", startDate: startDate,
                    endDate: endDate
                ),
                (
                    identifier: "x", title: "Different Meeting",
                    startDate: startDate, endDate: endDate
                ),
            ]) == [0, 2])
    }

    /// A title synced case-differently by two sources is still one meeting.
    @Test func titleMatchingIsCaseInsensitive() {
        let startDate = Date()
        let endDate = startDate.addingTimeInterval(1800)
        #expect(
            EventDeduplication.firstOccurrenceIndices(of: [
                (
                    identifier: nil, title: "Roadmap Review",
                    startDate: startDate, endDate: endDate
                ),
                (
                    identifier: nil, title: "roadmap review",
                    startDate: startDate, endDate: endDate
                ),
            ]) == [0])
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
