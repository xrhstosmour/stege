import EventKit
import SwiftUI

struct CalendarPopup: View {
    let calendarManager: CalendarManager

    @ObservedObject var configProvider: ConfigProvider

    var body: some View {
        CalendarMonthView(calendarManager: calendarManager)
            .padding(PopupStyle.padding)
            .environmentObject(configProvider)
            .onAppear {
                // Opening the calendar is an unambiguous request to see
                // events, so this is where a first-run install is asked.
                calendarManager.requestAccessIfNeeded()
            }
    }
}

struct CalendarPopup_Previews: PreviewProvider {
    static var previews: some View {
        CalendarMonthView(calendarManager: CalendarManager.shared)
            .padding(PopupStyle.padding)
            .background(BarStyle.surface)
            .frame(height: 600)
            .previewDisplayName("Calendar")
    }
}
