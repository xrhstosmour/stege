import Foundation
import Testing

@testable import StegeCore

struct EventDestinationTests {
    private func resolve(
        _ link: String?, account: CalendarAccount = .other,
        identifier: String? = nil, address: String? = nil,
        handled: Set<String> = []
    ) -> EventDestination? {
        EventDestination.resolve(
            link: link.flatMap(URL.init(string:)), account: account,
            externalIdentifier: identifier, calendarAddress: address,
            isHandled: { handled.contains($0) })
    }

    @Test func zoomOpensTheAppWhenItIsInstalled() {
        let result = resolve(
            "https://acme.zoom.us/j/123456?pwd=secret", handled: ["zoommtg"])
        #expect(
            result?.url.absoluteString
                == "zoommtg://acme.zoom.us/join?confno=123456&pwd=secret")
        #expect(result?.tooltip == "Join in Zoom")
    }

    @Test func zoomFallsBackToTheBrowserWithoutTheApp() {
        let result = resolve("https://acme.zoom.us/j/123456")
        #expect(result?.url.absoluteString == "https://acme.zoom.us/j/123456")
        #expect(result?.tooltip == "Join in the browser")
    }

    @Test func teamsOpensTheAppWhenItIsInstalled() {
        let result = resolve(
            "https://teams.microsoft.com/l/meetup-join/abc", handled: ["msteams"])
        #expect(
            result?.url.absoluteString
                == "msteams://teams.microsoft.com/l/meetup-join/abc")
        #expect(result?.tooltip == "Join in Teams")
    }

    @Test func googleMeetStaysInTheBrowser() {
        let result = resolve(
            "https://meet.google.com/abc-defg-hij",
            handled: ["zoommtg", "msteams"])
        #expect(result?.url.host == "meet.google.com")
        #expect(result?.url.scheme == "https")
    }

    @Test func googleEventWithoutALinkOpensGoogleCalendar() {
        let result = resolve(
            nil, account: .google, identifier: "abc123@google.com",
            address: "someone@example.com")
        // "abc123 someone@example.com" as unpadded URL-safe base64.
        #expect(
            result?.url.absoluteString
                == "https://calendar.google.com/calendar/event?eid=YWJjMTIzIHNvbWVvbmVAZXhhbXBsZS5jb20")
        #expect(result?.tooltip == "Open in Google Calendar")
    }

    @Test func googleEventWithoutAnAddressFallsBackToCalendar() {
        #expect(
            resolve(nil, account: .google, identifier: "abc123@google.com")
                == nil)
    }

    @Test func otherAccountsWithoutALinkFallBackToCalendar() {
        #expect(
            resolve(
                nil, account: .apple, identifier: "x", address: "a@b.c") == nil)
    }

    @Test func meetingLinkIsFoundInTheLocationThenTheNotes() {
        let location = EventDestination.meetingLink(
            url: nil, location: "Room, https://meet.example.com/a",
            notes: "https://other.example.com/b")
        #expect(location?.absoluteString == "https://meet.example.com/a")
        let notes = EventDestination.meetingLink(
            url: nil, location: "Room 4", notes: "Join: https://x.example.com/c")
        #expect(notes?.absoluteString == "https://x.example.com/c")
        #expect(
            EventDestination.meetingLink(url: nil, location: nil, notes: nil)
                == nil)
    }

    @Test func nonWebURLFieldIsIgnored() {
        let url = URL(string: "tel:123")
        #expect(
            EventDestination.meetingLink(url: url, location: nil, notes: nil)
                == nil)
    }
}
