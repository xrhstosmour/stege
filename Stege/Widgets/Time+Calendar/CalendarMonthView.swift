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
    private let cell: CGFloat = 30

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
            monthSection.frame(width: 268)

        case .stacked:
            VStack(alignment: .leading, spacing: 0) {
                monthSection
                Divider().padding(.vertical, 10)
                daySection
            }
            .frame(width: 268)

        case .sideBySide:
            HStack(alignment: .top, spacing: 16) {
                monthSection.frame(width: 268)
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

    private var daySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            dayHeading
            eventList
            addEvent
            Spacer(minLength: 0)
        }
    }

    // MARK: - Month header

    private var header: some View {
        HStack(spacing: 4) {
            Text(monthTitle)
                .font(.system(size: 14, weight: .semibold))
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
        .padding(.bottom, 12)
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
        HStack(spacing: 8) {
            ForEach(Array(orderedWeekdaySymbols.enumerated()), id: \.offset) {
                _, symbol in
                Text(symbol)
                    .font(.system(size: 11))
                    .frame(width: cell)
                    .opacity(0.55)
            }
        }
        .padding(.bottom, 6)
    }

    private var grid: some View {
        VStack(spacing: 6) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 8) {
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

            VStack(spacing: 2) {
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
            Image(systemName: isAddingEvent ? "xmark" : "plus")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
                .onTapGesture {
                    isAddingEvent.toggle()
                    saveFailed = false
                    if isAddingEvent, newEventCalendar == nil {
                        newEventCalendar = calendarManager.defaultCalendar
                    }
                }
                .help(isAddingEvent ? "Cancel" : "New event")
        }
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var eventList: some View {
        if events.isEmpty {
            Text("Nothing scheduled")
                .font(.system(size: 12))
                .opacity(0.5)
                .padding(.bottom, 4)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(events, id: \.eventIdentifier) { event in
                    eventRow(event)
                }
            }
            .padding(.bottom, 4)
        }
    }

    private func eventRow(_ event: EKEvent) -> some View {
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
                Text(timeLabel(for: event))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .opacity(0.6)
            }

            Spacer(minLength: 6)

            // Says which of the two a click does, rather than leaving it to be
            // discovered.
            Image(
                systemName: calendarManager.meetingLink(for: event) != nil
                    ? "video.fill" : "chevron.right"
            )
            .font(.system(size: 9, weight: .semibold))
            .opacity(0.45)
            .padding(.top, 2)
        }
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
        .onTapGesture { calendarManager.open(event) }
        .help(
            calendarManager.meetingLink(for: event) != nil
                ? "Join in the browser" : "Open in Calendar")
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
        events = calendarManager.events(on: selectedDate)
    }

    /// Which days in the visible month have something on them.
    private func reloadDots() {
        var found: Set<Date> = []
        for date in monthDates where calendarManager.hasEvents(on: date) {
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
