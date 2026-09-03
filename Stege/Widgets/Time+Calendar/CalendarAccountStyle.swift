import EventKit
import SwiftUI

/// The colour an event is marked with, taken from the service its calendar
/// came from rather than from the calendar itself.
///
/// A calendar's own colour is whatever the user picked in Google Calendar or
/// Outlook years ago, so a row of events came out in colours that said nothing
/// about anything. The account does say something, and there are only a few
/// accounts anybody has.
enum CalendarAccountStyle {
    /// Google's four, in the order the logo runs. Drawn as a gradient down the
    /// bar rather than picking one of them, because no single one of the four
    /// reads as Google.
    private static let google: [Color] = [
        Color(red: 0.259, green: 0.522, blue: 0.957),  // #4285F4
        Color(red: 0.918, green: 0.263, blue: 0.208),  // #EA4335
        Color(red: 0.984, green: 0.737, blue: 0.020),  // #FBBC05
        Color(red: 0.204, green: 0.659, blue: 0.325),  // #34A853
    ]

    /// Microsoft's own blue, the one the four squares sit next to in the
    /// wordmark.
    private static let microsoft = Color(
        red: 0.000, green: 0.471, blue: 0.831)  // #0078D4

    /// Apple ships no brand colour to borrow, so its calendars are drawn the
    /// way the rest of the bar is: one neutral mark.
    private static let apple = Color.white.opacity(0.85)

    static func account(for calendar: EKCalendar) -> CalendarAccount {
        CalendarAccount.of(
            sourceTitle: calendar.source.title, kind: kind(calendar.source))
    }

    /// What to fill the bar beside an event with.
    @ViewBuilder
    static func bar(for calendar: EKCalendar) -> some View {
        switch account(for: calendar) {
        case .google:
            LinearGradient(
                colors: google, startPoint: .top, endPoint: .bottom)
        case .microsoft:
            microsoft
        case .apple:
            apple
        case .other:
            // The calendar's own colour, which is what every event used to be
            // marked with and is still the only thing there is to go on.
            Color(nsColor: calendar.color ?? .systemGray)
        }
    }

    private static func kind(_ source: EKSource) -> CalendarAccount.Kind {
        switch source.sourceType {
        case .exchange: return .exchange
        case .mobileMe: return .cloud
        case .local: return .local
        case .calDAV: return .calDAV
        case .subscribed: return .subscribed
        default: return .other
        }
    }
}
