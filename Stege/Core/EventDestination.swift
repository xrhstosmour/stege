import Foundation

/// Where clicking a calendar event should take the user.
///
/// A meeting link goes to the app that owns the service when one is installed,
/// and to the browser otherwise, because a link handed to `NSWorkspace` as
/// `https` always lands in the browser even with the app present. An event with
/// no link goes to the web calendar of its account when that can be built, and
/// returns nil otherwise so the caller falls back to Calendar. The checks that
/// need the system, which schemes have an app, are passed in to keep this
/// testable.
struct EventDestination: Equatable {
    let url: URL
    let tooltip: String

    /// A joinable link in the dedicated URL field, the location, or loose in
    /// the notes, in that order, because providers put it in different places.
    static func meetingLink(url: URL?, location: String?, notes: String?)
        -> URL?
    {
        if let url, isWeb(url) { return url }
        guard
            let detector = try? NSDataDetector(
                types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return nil }
        for text in [location, notes].compactMap({ $0 }) {
            let range = NSRange(text.startIndex..., in: text)
            if let match = detector.firstMatch(in: text, range: range),
                let url = match.url, isWeb(url)
            {
                return url
            }
        }
        return nil
    }

    static func resolve(
        link: URL?,
        account: CalendarAccount,
        externalIdentifier: String?,
        calendarAddress: String?,
        isHandled: (String) -> Bool
    ) -> EventDestination? {
        if let link {
            return meeting(link, isHandled: isHandled)
        }
        if account == .google,
            let url = googleEvent(
                externalIdentifier: externalIdentifier,
                calendarAddress: calendarAddress)
        {
            return EventDestination(
                url: url, tooltip: "Open in Google Calendar")
        }
        return nil
    }

    private static func meeting(
        _ link: URL, isHandled: (String) -> Bool
    ) -> EventDestination {
        let host = link.host?.lowercased() ?? ""

        if host == "zoom.us" || host.hasSuffix(".zoom.us"),
            isHandled("zoommtg"), let app = zoomApp(link)
        {
            return EventDestination(url: app, tooltip: "Join in Zoom")
        }
        if host == "teams.microsoft.com" || host == "teams.live.com",
            isHandled("msteams"),
            var components = URLComponents(
                url: link, resolvingAgainstBaseURL: false)
        {
            components.scheme = "msteams"
            if let app = components.url {
                return EventDestination(url: app, tooltip: "Join in Teams")
            }
        }
        return EventDestination(url: link, tooltip: "Join in the browser")
    }

    /// `https://host/j/<id>?pwd=<p>` as the form the Zoom client takes.
    private static func zoomApp(_ link: URL) -> URL? {
        let parts = link.path.split(separator: "/")
        guard parts.count >= 2, parts[0] == "j", let host = link.host else {
            return nil
        }
        var components = URLComponents()
        components.scheme = "zoommtg"
        components.host = host
        components.path = "/join"
        components.queryItems = [URLQueryItem(name: "confno", value: String(parts[1]))]
        let password = URLComponents(url: link, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "pwd" }?.value
        if let password {
            components.queryItems?.append(
                URLQueryItem(name: "pwd", value: password))
        }
        return components.url
    }

    /// Google's own event address: the event ID and the calendar it lives in,
    /// joined by a space and encoded as unpadded URL-safe base64. `CalDAV`
    /// hands the ID over as `<id>@google.com`, and the suffix is not part of it.
    private static func googleEvent(
        externalIdentifier: String?, calendarAddress: String?
    ) -> URL? {
        guard let externalIdentifier, let calendarAddress,
            calendarAddress.contains("@")
        else { return nil }
        let identifier =
            externalIdentifier.components(separatedBy: "@google.com").first
            ?? externalIdentifier
        guard !identifier.isEmpty else { return nil }
        let encoded = Data("\(identifier) \(calendarAddress)".utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return URL(
            string: "https://calendar.google.com/calendar/event?eid=\(encoded)")
    }

    private static func isWeb(_ url: URL) -> Bool {
        url.scheme?.hasPrefix("http") == true
    }
}
