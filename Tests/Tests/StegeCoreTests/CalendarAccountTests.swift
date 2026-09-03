import Testing

@testable import StegeCore

struct CalendarAccountTests {
    @Test func googleIsFoundByItsAccountTitle() {
        #expect(
            CalendarAccount.of(sourceTitle: "Google", kind: .calDAV) == .google)
        #expect(
            CalendarAccount.of(
                sourceTitle: "someone@gmail.com", kind: .calDAV) == .google)
    }

    @Test func outlookIsMicrosoftWhateverItArrivesAs() {
        #expect(
            CalendarAccount.of(sourceTitle: "Outlook", kind: .calDAV)
                == .microsoft)
        #expect(
            CalendarAccount.of(sourceTitle: "someone@hotmail.com", kind: .calDAV)
                == .microsoft)
        #expect(
            CalendarAccount.of(sourceTitle: "Work", kind: .exchange)
                == .microsoft)
    }

    @Test func iCloudAndLocalAreApple() {
        #expect(CalendarAccount.of(sourceTitle: "iCloud", kind: .cloud) == .apple)
        #expect(CalendarAccount.of(sourceTitle: "On My Mac", kind: .local) == .apple)
    }

    /// The title wins over the kind, because a Google account arrives as
    /// `CalDAV` and so does everything else that is not Exchange or iCloud.
    @Test func theTitleDecidesBeforeTheKind() {
        #expect(
            CalendarAccount.of(sourceTitle: "Google", kind: .exchange)
                == .google)
    }

    /// Anything with no brand keeps the colour the calendar itself carries,
    /// which is what `other` is for.
    @Test func anUnknownAccountIsOther() {
        #expect(
            CalendarAccount.of(sourceTitle: "Fastmail", kind: .calDAV) == .other)
        #expect(
            CalendarAccount.of(sourceTitle: "Holidays", kind: .subscribed)
                == .other)
    }

    @Test func matchingIgnoresCase() {
        #expect(
            CalendarAccount.of(sourceTitle: "GOOGLE", kind: .other) == .google)
        #expect(
            CalendarAccount.of(sourceTitle: "iCloud", kind: .other) == .apple)
    }
}
