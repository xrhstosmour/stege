import EventKit
import SwiftUI

struct CalendarPopup: View {
    let calendarManager: CalendarManager

    @ObservedObject var configProvider: ConfigProvider
    // `vertical` rather than `box`: box is the month on its own, so it hides
    // the day's events and the button that adds one, which is most of what
    // this popup now does.
    @State private var selectedVariant: MenuBarPopupVariant = .vertical

    var body: some View {
        MenuBarPopupVariantView(
            selectedVariant: selectedVariant,
            onVariantSelected: { variant in
                selectedVariant = variant
                ConfigManager.shared.updateConfigValue(
                    key: "widgets.default.time.popup.view-variant",
                    newValue: variant.rawValue
                )
            },
            box: { CalendarBoxPopup(calendarManager) },
            vertical: { CalendarVerticalPopup(calendarManager) },
            horizontal: { CalendarHorizontalPopup(calendarManager) }
        )
        .environmentObject(configProvider)
        .onAppear {
            // Opening the calendar is an unambiguous request to see events, so
            // this is where a first-run install is asked.
            calendarManager.requestAccessIfNeeded()
            if let variantString = configProvider.config["popup"]?
                .dictionaryValue?["view-variant"]?.stringValue,
                let variant = MenuBarPopupVariant(rawValue: variantString)
            {
                selectedVariant = variant
            } else {
                selectedVariant = .vertical
            }
        }
        .onReceive(configProvider.$config) { newConfig in
            if let variantString = newConfig["popup"]?.dictionaryValue?[
                "view-variant"]?.stringValue,
                let variant = MenuBarPopupVariant(rawValue: variantString)
            {
                selectedVariant = variant
            }
        }
    }
}

struct CalendarBoxPopup: View {
    let calendarManager: CalendarManager

    init(_ calendarManager: CalendarManager) {
        self.calendarManager = calendarManager
    }

    var body: some View {
        CalendarMonthView(calendarManager: calendarManager, layout: .monthOnly)
            .padding(PopupStyle.padding)
    }
}

struct CalendarVerticalPopup: View {
    let calendarManager: CalendarManager

    init(_ calendarManager: CalendarManager) {
        self.calendarManager = calendarManager
    }

    var body: some View {
        CalendarMonthView(calendarManager: calendarManager, layout: .stacked)
            .padding(PopupStyle.padding)
    }
}

struct CalendarHorizontalPopup: View {
    let calendarManager: CalendarManager

    init(_ calendarManager: CalendarManager) {
        self.calendarManager = calendarManager
    }

    var body: some View {
        CalendarMonthView(calendarManager: calendarManager, layout: .sideBySide)
            .padding(PopupStyle.padding)
    }
}

struct CalendarPopup_Previews: PreviewProvider {
    static var previews: some View {
        let calendarManager = CalendarManager.shared

        CalendarBoxPopup(calendarManager)
            .background(BarStyle.surface)
            .previewLayout(.sizeThatFits)
            .previewDisplayName("Box")
        CalendarVerticalPopup(calendarManager)
            .background(BarStyle.surface)
            .frame(height: 600)
            .previewDisplayName("Vertical")
        CalendarHorizontalPopup(calendarManager)
            .background(BarStyle.surface)
            .previewLayout(.sizeThatFits)
            .previewDisplayName("Horizontal")
    }
}
