import AppKit
import Combine
import EventKit
import Foundation

final class CalendarManager: ObservableObject {
    /// One instance. Calendar events are a property of the machine, not of a
    /// bar, and there is one bar per screen: two managers on a two-monitor
    /// setup were each holding their own `EKEventStore`, their own 60s timer
    /// and their own store observer, all reading the same calendars.
    static let shared = CalendarManager()

    @Published var todaysEvents: [EKEvent] = []
    @Published var tomorrowsEvents: [EKEvent] = []
    private let eventStore = EKEventStore()
    private var timer: Timer?
    private var storeObserver: NSObjectProtocol?

    private init() {
        startMonitoring()
    }

    /// Whether the store can be read without asking for anything.
    var isAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    deinit {
        stopMonitoring()
    }

    /// Refreshes when the store changes, plus a slow tick for the clock.
    ///
    /// This used to re-read every event three times a second, five seconds
    /// apart, whether or not anything had changed. `EKEventStoreChanged` fires
    /// on every edit from anywhere, including a sync from an account, which
    /// covers everything except the passage of time: an event starting, or the
    /// day rolling over, moves what counts as next without the store changing
    /// at all. A minute is enough for that, since a minute is all the bar
    /// displays.
    private func startMonitoring() {
        storeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: eventStore,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }

        timer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) {
            [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    private func refresh() {
        fetchTodaysEvents()
        fetchTomorrowsEvents()
    }

    private func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        if let storeObserver {
            NotificationCenter.default.removeObserver(storeObserver)
        }
        storeObserver = nil
    }

    /// Asks for calendar access, but only the first time and only when
    /// something is actually about to read events.
    ///
    /// This used to run from `init`, so a fresh install put a calendar prompt
    /// on screen the moment the bar appeared, whether or not the events were
    /// ever going to be looked at. The prompt now comes from the two places
    /// that need the answer: the next event line in the bar, when it is turned
    /// on, and the popup being opened.
    ///
    /// Called more than once, because both of those can happen repeatedly.
    /// `notDetermined` is the only state that asks, so the rest are no-ops.
    func requestAccessIfNeeded() {
        guard EKEventStore.authorizationStatus(for: .event) == .notDetermined
        else { return }
        eventStore.requestFullAccessToEvents { [weak self] granted, error in
            guard granted, error == nil else { return }
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    /// Applies an allow/deny list of calendar names to a set of events.
    ///
    /// Takes the lists as parameters rather than reading them off a stored
    /// config, because a single shared instance cannot own one screen's
    /// config over another's: the widget that knows which config applies
    /// passes the lists in at the point of filtering instead.
    static func filterEvents(
        _ events: [EKEvent], allowList: [String], denyList: [String]
    ) -> [EKEvent] {
        var filtered = events
        if !allowList.isEmpty {
            filtered = filtered.filter { allowList.contains($0.calendar.title) }
        }
        if !denyList.isEmpty {
            filtered = filtered.filter { !denyList.contains($0.calendar.title) }
        }
        return filtered
    }

    func fetchTodaysEvents() {
        let calendars = eventStore.calendars(for: .event)
        let now = Date()
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: now)
        guard
            let endOfDay = calendar.date(
                bySettingHour: 23, minute: 59, second: 59, of: now)
        else {
            Log.calendar.error("Could not work out the end of the day")
            return
        }
        let predicate = eventStore.predicateForEvents(
            withStart: startOfDay, end: endOfDay, calendars: calendars)
        let events = eventStore.events(matching: predicate)
            .filter { $0.endDate >= now }
            .sorted { $0.startDate < $1.startDate }
        DispatchQueue.main.async {
            self.todaysEvents = events
        }
    }

    func fetchTomorrowsEvents() {
        let calendars = eventStore.calendars(for: .event)
        let now = Date()
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        guard
            let startOfTomorrow = calendar.date(
                byAdding: .day, value: 1, to: startOfToday),
            let endOfTomorrow = calendar.date(
                bySettingHour: 23, minute: 59, second: 59, of: startOfTomorrow)
        else {
            Log.calendar.error("Could not work out tomorrow's range")
            return
        }
        let predicate = eventStore.predicateForEvents(
            withStart: startOfTomorrow, end: endOfTomorrow, calendars: calendars
        )
        let events = eventStore.events(matching: predicate).sorted {
            $0.startDate < $1.startDate
        }
        DispatchQueue.main.async {
            self.tomorrowsEvents = events
        }
    }
}

// MARK: - Browsing, opening and creating

extension CalendarManager {
    /// Every calendar the user can actually write to, grouped under the account
    /// it belongs to. Read-only ones, holiday feeds and subscribed calendars,
    /// are excluded: offering them and then failing to save would be worse than
    /// not offering them.
    var writableCalendars: [EKCalendar] {
        eventStore.calendars(for: .event)
            .filter { $0.allowsContentModifications }
            .sorted {
                ($0.source.title, $0.title) < ($1.source.title, $1.title)
            }
    }

    /// The calendar new events default to, which is the one macOS itself
    /// defaults to when it has an opinion.
    var defaultCalendar: EKCalendar? {
        eventStore.defaultCalendarForNewEvents
            ?? writableCalendars.first
    }

    /// Events on one day, from every account the system knows about, with the
    /// widget's allow and deny lists applied.
    ///
    /// All-day events sort first, then by start time, which is the order both
    /// macOS Calendar and the system menu bar use.
    func events(
        on date: Date, allowList: [String] = [], denyList: [String] = []
    ) -> [EKEvent] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start)
        else { return [] }

        let predicate = eventStore.predicateForEvents(
            withStart: start, end: end,
            calendars: eventStore.calendars(for: .event))
        return Self.filterEvents(
            eventStore.events(matching: predicate),
            allowList: allowList, denyList: denyList
        )
        .sorted {
            if $0.isAllDay != $1.isAllDay { return $0.isAllDay }
            return $0.startDate < $1.startDate
        }
    }

    /// Whether a day has anything on it, for the dot under the date in the grid.
    func hasEvents(
        on date: Date, allowList: [String] = [], denyList: [String] = []
    ) -> Bool {
        !events(on: date, allowList: allowList, denyList: denyList).isEmpty
    }

    /// Opens an event where it belongs: a meeting link in the browser, anything
    /// else in Calendar, showing that event rather than just that day.
    func open(_ event: EKEvent) {
        if let link = meetingLink(for: event) {
            NSWorkspace.shared.open(link)
            return
        }
        guard let identifier = event.eventIdentifier else { return }
        // The identifier contains a colon and an at sign for events synced from
        // Google, and both have to survive as literals inside the path.
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: ":@")
        let escaped =
            identifier.addingPercentEncoding(withAllowedCharacters: allowed)
            ?? identifier
        guard
            let url = URL(
                string: "ical://ekevent/\(escaped)?method=show&options=more")
        else { return }
        NSWorkspace.shared.open(url)
    }

    /// A joinable meeting link, if the event carries one.
    ///
    /// Providers put it in different places: the dedicated URL field, the
    /// location, or loose in the notes, so all three are checked before giving
    /// up and opening Calendar instead.
    func meetingLink(for event: EKEvent) -> URL? {
        if let url = event.url, url.scheme?.hasPrefix("http") == true {
            return url
        }
        for text in [event.location, event.notes].compactMap({ $0 }) {
            guard
                let detector = try? NSDataDetector(
                    types: NSTextCheckingResult.CheckingType.link.rawValue)
            else { continue }
            let range = NSRange(text.startIndex..., in: text)
            if let match = detector.firstMatch(in: text, range: range),
                let url = match.url, url.scheme?.hasPrefix("http") == true
            {
                return url
            }
        }
        return nil
    }

    /// Creates a one hour event at the next whole hour on `date`, or at nine in
    /// the morning when `date` is not today, and returns whether it saved.
    @discardableResult
    func createEvent(title: String, on date: Date, in calendar: EKCalendar)
        -> Bool
    {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let current = Calendar.current
        let start: Date
        if current.isDateInToday(date) {
            // Next whole hour, so a same-day event does not land in the past.
            let next = current.date(
                byAdding: .hour, value: 1, to: Date()) ?? Date()
            start =
                current.date(
                    bySetting: .minute, value: 0, of: next) ?? next
        } else {
            start =
                current.date(
                    bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
        }

        let event = EKEvent(eventStore: eventStore)
        event.title = trimmed
        event.startDate = start
        event.endDate = current.date(byAdding: .hour, value: 1, to: start)
            ?? start
        event.calendar = calendar

        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
            fetchTodaysEvents()
            fetchTomorrowsEvents()
            return true
        } catch {
            return false
        }
    }
}
