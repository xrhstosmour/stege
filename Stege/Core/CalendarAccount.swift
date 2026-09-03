import Foundation

/// Which service a calendar came from, worked out from the account it lives in.
///
/// `EventKit` names the account but not the provider: a Google calendar is a
/// `CalDAV` source whose title is the address it was added under, an Outlook
/// one is either `Exchange` or `CalDAV`, and iCloud is its own kind. The
/// provider is worth knowing because an event's colour should say where it came
/// from, and the colour the calendar itself carries is whatever the user picked
/// in Google Calendar years ago.
enum CalendarAccount: String, Equatable {
    case google
    case microsoft
    case apple
    /// Everything else, including a local calendar and a subscribed feed. Kept
    /// deliberately: an account nobody has a brand colour for keeps the colour
    /// the calendar itself carries, which is the behaviour this replaced.
    case other

    /// How `EventKit` classifies the account, without `EventKit` itself, so
    /// this stays testable.
    enum Kind {
        case exchange
        /// iCloud.
        case cloud
        case local
        case calDAV
        case subscribed
        case other
    }

    static func of(sourceTitle: String, kind: Kind) -> CalendarAccount {
        let title = sourceTitle.lowercased()

        // The title first, because it is the only thing that separates one
        // `CalDAV` account from another, and `CalDAV` is how both Google and
        // Outlook.com arrive.
        if title.contains("google") || title.contains("gmail") {
            return .google
        }
        if title.contains("outlook") || title.contains("microsoft")
            || title.contains("office365") || title.contains("office 365")
            || title.contains("hotmail") || title.contains("live.com")
        {
            return .microsoft
        }
        if title.contains("icloud") || title.contains("apple") {
            return .apple
        }

        switch kind {
        case .exchange: return .microsoft
        case .cloud: return .apple
        // A calendar macOS keeps itself, which is the one on a Mac with no
        // accounts added at all.
        case .local: return .apple
        case .calDAV, .subscribed, .other: return .other
        }
    }
}
