import EventKit
import SwiftUI

/// A month you can page through, with the events of whichever day is selected
/// listed underneath and a way to add one.
///
/// The previous grid was built from three global computed properties that all
/// read `Date()`, so it could only ever draw the current month and there was
/// nothing to navigate with. This holds the visible month and the selected day
/// as state instead.
struct CalendarMonthView: View {
    /// How the month and the day's events are arranged. The three values match
    /// the popup variants the time widget already offered, so switching variant
    /// still changes something now that all three navigate.
    enum Layout {
        /// The month on its own.
        case monthOnly
        /// The month, with the day's events under it.
        case stacked
        /// The month, with the day's events beside it.
        case sideBySide
    }

    let calendarManager: CalendarManager
    var layout: Layout = .stacked

    @EnvironmentObject var configProvider: ConfigProvider
    private var calendarConfig: ConfigData? {
        configProvider.config["calendar"]?.dictionaryValue
    }
    private var allowList: [String] { calendarNames(for: "allow-list") }
    private var denyList: [String] { calendarNames(for: "deny-list") }
    private func calendarNames(for key: String) -> [String] {
        calendarConfig?[key]?.arrayValue?
            .compactMap { $0.stringValue }
            .filter { !$0.isEmpty } ?? []
    }

    /// First of the month being shown.
    @State private var visibleMonth: Date = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: Date()))
        ?? Date()
    @State private var selectedDate: Date = Calendar.current.startOfDay(
        for: Date())
    @State private var events: [EKEvent] = []
    @State private var daysWithEvents: Set<Date> = []
    @State private var isAddingEvent = false
    @State private var newEventTitle = ""
    @State private var newEventCalendar: EKCalendar?
    @State private var saveFailed = false

    private let calendar = Calendar.current
    /// One day. Twenty-six, not thirty: a day holds a two digit number at 12
    /// points and a 3 point dot under it, which is 19 points of ink, and the
    /// four points the cell used to add on top of that bought nothing but a
    /// taller popup. Five week rows carry the saving five times over.
    private let cell: CGFloat = 26

    /// As wide as every other popup, rather than a width of its own. This was
    /// 268 inside 14 points of padding, so the calendar came out 296 wide
    /// against the 280 of everything else in the bar, and the difference showed
    /// as soon as two popups were opened one after the other.
    private static let contentWidth =
        PopupStyle.width - PopupStyle.padding * 2

    /// The gap between day columns, set so seven cells fill the width rather
    /// than leaving the grid stranded against the left edge.
    private var columnSpacing: CGFloat { (Self.contentWidth - cell * 7) / 6 }

    var body: some View {
        content
            .foregroundStyle(BarStyle.ink)
            .onAppear(perform: reload)
            .onChange(of: selectedDate) { _, _ in reloadEvents() }
            .onChange(of: visibleMonth) { _, _ in reload() }
    }

    @ViewBuilder
    private var content: some View {
        switch layout {
        case .monthOnly:
            monthSection.frame(width: Self.contentWidth)

        case .stacked:
            VStack(alignment: .leading, spacing: 0) {
                monthSection
                Divider().padding(.vertical, 6)
                daySection
            }
            .frame(width: Self.contentWidth)

        case .sideBySide:
            HStack(alignment: .top, spacing: 16) {
                monthSection.frame(width: Self.contentWidth)
                Divider()
                daySection.frame(width: 220)
            }
        }
    }

    private var monthSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            weekdays
            grid
        }
    }

    /// No trailing `Spacer`. There was one, and the popup is placed in a panel
    /// the size of the whole screen, so the spacer took every point of it: the
    /// month and the day's events drew at the top and several hundred points of
    /// empty popup hung underneath them, all the way down the display. The
    /// side-by-side layout is already top aligned by its `HStack`, which is the
    /// only thing the spacer was there for.
    private var daySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            dayHeading
            eventList
            addEvent
        }
    }

    // MARK: - Month header

    private var header: some View {
        HStack(spacing: 4) {
            Text(monthTitle)
                .font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 8)

            // Only shown when it would do something, so the row stays quiet on
            // the month you are already looking at.
            if !calendar.isDate(visibleMonth, equalTo: Date(), toGranularity: .month)
                || !calendar.isDateInToday(selectedDate)
            {
                stepButton("arrow.uturn.backward", help: "Today") {
                    selectedDate = calendar.startOfDay(for: Date())
                    visibleMonth = startOfMonth(for: Date())
                }
            }
            stepButton("chevron.left", help: "Previous month") { step(-1) }
            stepButton("chevron.right", help: "Next month") { step(1) }
        }
        .padding(.bottom, 8)
    }

    private func stepButton(
        _ symbol: String, help: String, action: @escaping () -> Void
    ) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 10, weight: .semibold))
            .frame(width: 20, height: 20)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .help(help)
    }

    private func step(_ months: Int) {
        guard
            let moved = calendar.date(
                byAdding: .month, value: months, to: visibleMonth)
        else { return }
        withAnimation(.smooth(duration: 0.15)) { visibleMonth = moved }
    }

    // MARK: - Grid

    private var weekdays: some View {
        HStack(spacing: columnSpacing) {
            ForEach(Array(orderedWeekdaySymbols.enumerated()), id: \.offset) {
                _, symbol in
                Text(symbol)
                    .font(.system(size: 10))
                    .frame(width: cell)
                    .opacity(0.55)
            }
        }
        .padding(.bottom, 4)
    }

    private var grid: some View {
        VStack(spacing: 3) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: columnSpacing) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        if let day {
                            dayCell(day)
                        } else {
                            Color.clear.frame(width: cell, height: cell)
                        }
                    }
                }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(date)
        let isWeekend = calendar.isDateInWeekend(date)

        return ZStack {
            if isSelected {
                Circle().fill(BarStyle.ink).frame(width: cell, height: cell)
            } else if isToday {
                Circle()
                    .strokeBorder(BarStyle.ink.opacity(0.5), lineWidth: 1)
                    .frame(width: cell, height: cell)
            }

            VStack(spacing: 1) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(size: 12, weight: isToday ? .semibold : .regular))
                    .foregroundStyle(
                        isSelected
                            ? Color.black : (isWeekend ? .gray : .white))
                // A dot rather than a count: the number is in the list below,
                // and a digit at this size is unreadable anyway.
                Circle()
                    .fill(isSelected ? BarStyle.inkInverse : BarStyle.ink)
                    .frame(width: 3, height: 3)
                    .opacity(daysWithEvents.contains(calendar.startOfDay(for: date)) ? 0.8 : 0)
            }
        }
        .frame(width: cell, height: cell)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedDate = calendar.startOfDay(for: date)
            isAddingEvent = false
        }
    }

    // MARK: - Events

    private var dayHeading: some View {
        HStack(spacing: 8) {
            Text(selectedDayTitle)
                .font(.system(size: 12, weight: .semibold))
            Spacer(minLength: 8)
            AddEventButton(isCancelling: isAddingEvent) {
                isAddingEvent.toggle()
                saveFailed = false
                if isAddingEvent, newEventCalendar == nil {
                    newEventCalendar = calendarManager.defaultCalendar
                }
            }
        }
        .padding(.bottom, 6)
    }

    /// How tall the list of events is allowed to get before it scrolls.
    ///
    /// Five rows, which is a full working day's worth. Without a bound the
    /// popup was as tall as the day was busy: it grew a row per event and a
    /// full day ran off the bottom of the screen, month grid and all. A day
    /// with nothing on takes one line, as it always did.
    ///
    /// Five rather than the four it was, because the month above it lost 60
    /// points: the list can hold one more day's event and the popup is still
    /// shorter than it used to be with four.
    private static let eventListMaximumHeight: CGFloat = 180

    @ViewBuilder
    private var eventList: some View {
        if events.isEmpty {
            Text("Nothing scheduled")
                .font(.system(size: 12))
                .opacity(0.5)
                .padding(.bottom, 6)
        } else {
            // Room under the last row before the popup ends. Without it the
            // events sat flush against the bottom edge, which reads as the
            // popup having been cut off rather than having finished.
            let rows = VStack(alignment: .leading, spacing: 2) {
                ForEach(events, id: \.eventIdentifier) { event in
                    eventRow(event)
                }
            }
            .padding(.bottom, 6)

            // Only a scroller once there is something to scroll. A `ScrollView`
            // always takes the height it is offered, so wrapping a short list in
            // one would put back the fixed block this is here to remove.
            if events.count > 5 {
                ScrollView(.vertical, showsIndicators: true) { rows }
                    .frame(maxHeight: Self.eventListMaximumHeight)
            } else {
                rows
            }
        }
    }

    private func eventRow(_ event: EKEvent) -> some View {
        EventRow(
            event: event,
            meetingLink: calendarManager.meetingLink(for: event) != nil,
            time: timeLabel(for: event)
        ) {
            calendarManager.open(event)
        }
    }

    /// Start and end, or "All day". Uses a `j` template so the locale decides
    /// 12 or 24 hour. Minutes are always shown, because stripping them off a
    /// whole hour leaves a range like "20 to 23:55", where the two sides no
    /// longer read as the same kind of thing.
    private func timeLabel(for event: EKEvent) -> String {
        guard !event.isAllDay else {
            return NSLocalizedString("ALL_DAY", comment: "")
        }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("j:mm")
        let start = formatter.string(from: event.startDate)
        let end = formatter.string(from: event.endDate)
        return "\(start) — \(end)"
    }

    // MARK: - Adding

    @ViewBuilder
    private var addEvent: some View {
        if isAddingEvent {
            VStack(alignment: .leading, spacing: 6) {
                Divider().padding(.vertical, 4)

                TextField("Event title", text: $newEventTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(BarStyle.ink.opacity(0.12))
                    )
                    .onSubmit(save)

                HStack(spacing: 8) {
                    // Grouped by account, so two calendars called Personal from
                    // different providers are still tellable apart.
                    Picker("", selection: $newEventCalendar) {
                        ForEach(calendarManager.writableCalendars, id: \.calendarIdentifier) {
                            calendar in
                            Text("\(calendar.source.title) · \(calendar.title)")
                                .tag(calendar as EKCalendar?)
                        }
                    }
                    .labelsHidden()
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity)

                    Text("Add")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(canSave ? Color.accentColor : BarStyle.ink.opacity(0.15))
                        )
                        .contentShape(Rectangle())
                        .onTapGesture(perform: save)
                        .opacity(canSave ? 1 : 0.5)
                }

                if saveFailed {
                    Text("Could not save to that calendar")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private var canSave: Bool {
        !newEventTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && newEventCalendar != nil
    }

    private func save() {
        guard canSave, let target = newEventCalendar else { return }
        if calendarManager.createEvent(
            title: newEventTitle, on: selectedDate, in: target)
        {
            newEventTitle = ""
            isAddingEvent = false
            saveFailed = false
            reload()
        } else {
            saveFailed = true
        }
    }

    // MARK: - Data

    private func reload() {
        reloadEvents()
        reloadDots()
    }

    private func reloadEvents() {
        events = calendarManager.events(
            on: selectedDate, allowList: allowList, denyList: denyList)
    }

    /// Which days in the visible month have something on them.
    private func reloadDots() {
        var found: Set<Date> = []
        for date in monthDates
        where calendarManager.hasEvents(
            on: date, allowList: allowList, denyList: denyList)
        {
            found.insert(calendar.startOfDay(for: date))
        }
        daysWithEvents = found
    }

    // MARK: - Dates

    private func startOfMonth(for date: Date) -> Date {
        calendar.date(
            from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("yMMMM")
        return formatter.string(from: visibleMonth).capitalized
    }

    private var selectedDayTitle: String {
        if calendar.isDateInToday(selectedDate) { return "Today" }
        if calendar.isDateInTomorrow(selectedDate) { return "Tomorrow" }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return formatter.string(from: selectedDate)
    }

    private var orderedWeekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var monthDates: [Date] {
        guard
            let range = calendar.range(of: .day, in: .month, for: visibleMonth)
        else { return [] }
        return range.compactMap {
            calendar.date(byAdding: .day, value: $0 - 1, to: visibleMonth)
        }
    }

    private var weeks: [[Date?]] {
        let dates = monthDates
        guard let first = dates.first else { return [] }
        let weekday = calendar.component(.weekday, from: first)
        let leading = (weekday - calendar.firstWeekday + 7) % 7

        var cells: [Date?] = Array(repeating: nil, count: leading)
        cells.append(contentsOf: dates.map { Optional($0) })
        if cells.count % 7 != 0 {
            cells.append(
                contentsOf: Array(repeating: nil, count: 7 - cells.count % 7))
        }
        return stride(from: 0, to: cells.count, by: 7).map {
            Array(cells[$0..<min($0 + 7, cells.count)])
        }
    }
}

/// One event, drawn as a row that lights up under the pointer the way every
/// other row in every other popup does.
///
/// The highlight is drawn as a background that bleeds outwards rather than as
/// padding, so the row reads as a full-width row without indenting the title
/// away from the month grid above it. Same argument as `BarHover`.
private struct EventRow: View {
    let event: EKEvent
    let meetingLink: Bool
    let time: String
    let open: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // The calendar's own colour, so an event is traceable back to the
            // account it came from without naming it on every row.
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color(nsColor: event.calendar.color ?? .systemGray))
                .frame(width: 3)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 1) {
                Text(event.title ?? "Untitled")
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(time)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .opacity(0.6)
            }

            Spacer(minLength: 6)

            // Says which of the two a click does, rather than leaving it to be
            // discovered.
            Image(systemName: meetingLink ? "video.fill" : "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .opacity(isHovered ? 0.8 : 0.45)
                .padding(.top, 2)
        }
        .padding(.vertical, 4)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(BarStyle.ink.opacity(isHovered ? 0.12 : 0))
                .padding(.horizontal, -6)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(perform: open)
        .help(meetingLink ? "Join in the browser" : "Open in Calendar")
    }
}

/// The control that starts a new event, and cancels one being written.
///
/// Round, and it fills under the pointer. It was a bare glyph in an 18 point
/// box, which gave no sign it could be pressed until it was.
private struct AddEventButton: View {
    let isCancelling: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Image(systemName: isCancelling ? "xmark" : "plus")
            .font(.system(size: 10, weight: .semibold))
            .frame(width: 20, height: 20)
            .background(
                Circle().fill(BarStyle.ink.opacity(isHovered ? 0.15 : 0))
            )
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .onTapGesture(perform: action)
            .help(isCancelling ? "Cancel" : "New event")
    }
}
