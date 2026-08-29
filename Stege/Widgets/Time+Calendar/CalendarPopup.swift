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
            .padding(20)
    }
}

struct CalendarVerticalPopup: View {
    let calendarManager: CalendarManager

    init(_ calendarManager: CalendarManager) {
        self.calendarManager = calendarManager
    }

    var body: some View {
        CalendarMonthView(calendarManager: calendarManager, layout: .stacked)
            .padding(20)
    }
}

struct CalendarHorizontalPopup: View {
    let calendarManager: CalendarManager

    init(_ calendarManager: CalendarManager) {
        self.calendarManager = calendarManager
    }

    var body: some View {
        CalendarMonthView(calendarManager: calendarManager, layout: .sideBySide)
            .padding(20)
    }
}

struct CalendarPopup_Previews: PreviewProvider {
    var configProvider: ConfigProvider = ConfigProvider(config: ConfigData())
    var calendarManager: CalendarManager

    init() {
        self.calendarManager = CalendarManager(configProvider: configProvider)
    }

    static var previews: some View {
        let configProvider = ConfigProvider(config: ConfigData())
        let calendarManager = CalendarManager(configProvider: configProvider)

        CalendarBoxPopup(calendarManager)
            .background(Color.black)
            .previewLayout(.sizeThatFits)
            .previewDisplayName("Box")
        CalendarVerticalPopup(calendarManager)
            .background(Color.black)
            .frame(height: 600)
            .previewDisplayName("Vertical")
        CalendarHorizontalPopup(calendarManager)
            .background(Color.black)
            .previewLayout(.sizeThatFits)
            .previewDisplayName("Horizontal")
    }
}
