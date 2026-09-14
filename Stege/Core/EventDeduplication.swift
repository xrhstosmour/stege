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
///
/// A second pass then catches what the identifier match cannot: the same
/// meeting handed out under two different identifiers by two different
/// sources, which happens on a shared or delegated calendar that mints its
/// own identifier for a copy of an invite a personal calendar already carries
/// under its own. Matched on title, start date and end date together, because
/// two unrelated meetings sharing only one or two of those is far more likely
/// than sharing all three. An empty title is never treated as matching another
/// empty title, the same guard the identifier pass applies to `nil`.
enum EventDeduplication {
    /// A single array of event fields, one tuple per event, rather than
    /// parallel arrays, so there is no length mismatch for a caller to get
    /// wrong.
    static func firstOccurrenceIndices(
        of events: [
            (identifier: String?, title: String, startDate: Date, endDate: Date)
        ]
    ) -> [Int] {
        struct IdentifierKey: Hashable {
            let identifier: String
            let startDate: Date
        }
        struct TitleKey: Hashable {
            let title: String
            let startDate: Date
            let endDate: Date
        }
        var seenIdentifiers = Set<IdentifierKey>()
        var seenTitles = Set<TitleKey>()
        var kept: [Int] = []
        for index in events.indices {
            let event = events[index]
            let identifierKey = event.identifier.map {
                IdentifierKey(identifier: $0, startDate: event.startDate)
            }
            let title = event.title
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let titleKey =
                title.isEmpty
                ? nil
                : TitleKey(
                    title: title, startDate: event.startDate,
                    endDate: event.endDate)

            // Checked against both sets before either is written to: an
            // event dropped as a title duplicate must not also burn its
            // identifier, or a later, genuinely distinct event sharing that
            // identifier by coincidence would be dropped as well, losing a
            // meeting this pass was never meant to touch.
            if let identifierKey, seenIdentifiers.contains(identifierKey) {
                continue
            }
            if let titleKey, seenTitles.contains(titleKey) { continue }

            if let identifierKey { seenIdentifiers.insert(identifierKey) }
            if let titleKey { seenTitles.insert(titleKey) }
            kept.append(index)
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
