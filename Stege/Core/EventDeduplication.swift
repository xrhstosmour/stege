import Foundation

/// Which of a list of calendar events are the first occurrence of their kind.
///
/// The same meeting can arrive as more than one event: an attendee's copy
/// alongside the organizer's, or the same account surfaced under more than one
/// source. `identifier` should be EventKit's cross-calendar identity for a
/// meeting where one exists, falling back to the per-calendar-copy identifier
/// for anything never synced anywhere.
///
/// Paired with `startDate`, because a recurring event's occurrences all share
/// the same identifier: without the start date, two different occurrences of
/// the same series landing on the same day would collapse into one. A `nil`
/// identifier is never treated as matching another `nil` identifier, so an
/// event with no identifier at all is always kept rather than risking two
/// unrelated events collapsing into one.
enum EventDeduplication {
    /// A single array of `(identifier, startDate)` pairs, one per event,
    /// rather than two parallel arrays, so there is no length mismatch for a
    /// caller to get wrong.
    static func firstOccurrenceIndices(
        of events: [(identifier: String?, startDate: Date)]
    ) -> [Int] {
        struct Key: Hashable {
            let identifier: String
            let startDate: Date
        }
        var seen = Set<Key>()
        var kept: [Int] = []
        for index in events.indices {
            guard let identifier = events[index].identifier else {
                kept.append(index)
                continue
            }
            let key = Key(
                identifier: identifier, startDate: events[index].startDate)
            if seen.insert(key).inserted {
                kept.append(index)
            }
        }
        return kept
    }

    /// `nil` if `identifier` is `nil` or empty, otherwise `identifier` itself.
    ///
    /// EventKit's `calendarItemExternalIdentifier` is documented as a
    /// cross-calendar identity for a meeting, `nil` when the event was never
    /// synced anywhere, but in practice it comes back `""` for that case, not
    /// `nil`. A caller falling back to a different identifier when there is
    /// no real cross-calendar identity, the way `CalendarManager.deduplicated`
    /// does, needs that empty string normalized to `nil` first, or the
    /// fallback never runs and two unrelated events both key on `""`.
    static func normalizedIdentifier(_ identifier: String?) -> String? {
        guard let identifier, !identifier.isEmpty else { return nil }
        return identifier
    }
}
