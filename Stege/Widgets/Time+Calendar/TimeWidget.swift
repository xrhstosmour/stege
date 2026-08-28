import EventKit
import SwiftUI

struct TimeWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    var config: ConfigData { configProvider.config }
    var calendarConfig: ConfigData? { config["calendar"]?.dictionaryValue }

    var format: String { config["format"]?.stringValue ?? "E d, J:mm" }
    var timeZone: String? { config["time-zone"]?.stringValue }

    var calendarFormat: String {
        calendarConfig?["format"]?.stringValue ?? "J:mm"
    }
    var calendarShowEvents: Bool {
        calendarConfig?["show-events"]?.boolValue ?? true
    }

    @State private var currentTime = Date()

    /// Owned, not handed in. It was built inline by `MenuBarView` and passed as
    /// a plain property, so every re-evaluation of that view constructed a
    /// fresh one, each with its own `EKEventStore`, its own timer and its own
    /// store observer. It was also not observed, so the next event line only
    /// changed when something else happened to redraw the widget.
    @StateObject private var calendarManager: CalendarManager

    init(calendarManager: @autoclosure @escaping () -> CalendarManager) {
        _calendarManager = StateObject(wrappedValue: calendarManager())
    }

    @State private var rect = CGRect()

    private let timer = Timer.publish(every: 1, on: .main, in: .common)
        .autoconnect()

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(formattedTime(pattern: format, from: currentTime))
                .fontWeight(.semibold)
            if let event = calendarManager.nextEvent, calendarShowEvents {
                Text(eventText(for: event))
                    .opacity(0.8)
                    .font(.subheadline)
            }
        }
        .font(.headline)
        .foregroundStyle(.foregroundOutside)
        .shadow(color: .foregroundShadowOutside, radius: 3)
        .onReceive(timer) { date in
            currentTime = date
        }
        .onAppear {
            // Only when the next event is actually going to be drawn. With
            // `show-events = false` the bar shows a clock, and a clock has no
            // business asking for a calendar.
            guard calendarShowEvents else { return }
            calendarManager.requestAccessIfNeeded()
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        rect = geometry.frame(in: .global)
                    }
                    .onChange(of: geometry.frame(in: .global)) {
                        oldState, newState in
                        rect = newState
                    }
            }
        )
        .experimentalConfiguration(cornerRadius: 15)
        .frame(maxHeight: .infinity)
        .background(.black.opacity(0.001))
        .monospacedDigit()
        .onTapGesture {
            MenuBarPopup.show(rect: rect, id: "calendar") {
                CalendarPopup(
                    calendarManager: calendarManager,
                    configProvider: configProvider)
            }
        }
    }

    // Format the current time.
    private func formattedTime(pattern: String, from time: Date) -> String {
        let formatter = DateFormatter()
        // `setLocalizedDateFormatFromTemplate` treats the pattern as a
        // *template*: it reorders components to suit the locale and discards
        // literal text, so "E d MMM  HH:mm" comes back as "Fri, Aug 21 at 22:40".
        // That is the right behaviour only for patterns using template-only
        // symbols such as `J`, the locale-decides-12-or-24 hour. Anything else
        // is treated as a literal format, so a pattern is rendered as written.
        if pattern.contains("J") {
            formatter.setLocalizedDateFormatFromTemplate(pattern)
        } else {
            formatter.dateFormat = pattern
        }

        if let timeZone = timeZone,
            let tz = TimeZone(identifier: timeZone)
        {
            formatter.timeZone = tz
        } else {
            formatter.timeZone = TimeZone.current
        }

        return formatter.string(from: time)
    }

    // Create text for the calendar event.
    private func eventText(for event: EKEvent) -> String {
        var text = event.title ?? ""
        if !event.isAllDay {
            text += " ("
            text += formattedTime(
                pattern: calendarFormat, from: event.startDate)
            text += ")"
        }
        return text
    }
}

struct TimeWidget_Previews: PreviewProvider {
    static var previews: some View {
        let provider = ConfigProvider(config: ConfigData())
        let manager = CalendarManager(configProvider: provider)

        ZStack {
            TimeWidget(calendarManager: manager)
                .environmentObject(provider)
        }.frame(width: 500, height: 100)
    }
}
