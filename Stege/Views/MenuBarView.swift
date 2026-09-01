import SwiftUI

struct MenuBarView: View {
    @ObservedObject var configManager = ConfigManager.shared

    var body: some View {
        let theme: ColorScheme? =
            switch configManager.config.rootToml.theme {
            case "dark":
                .dark
            case "light":
                .light
            default:
                .none
            }

        let items = configManager.config.rootToml.widgets.displayed

        HStack(spacing: 0) {
            HStack(spacing: configManager.config.experimental.foreground.spacing) {
                ForEach(0..<items.count, id: \.self) { index in
                    let item = items[index]
                    buildView(for: item)
                        // So a widget can tell whether an activation was meant
                        // for it without the bar knowing what each one does.
                        .environment(\.barItemIndex, index)
                        // The ring is the bar's, not each widget's, so every
                        // item shows where the keyboard is.
                        .barFocusRing()
                }
            }
        }
        .onAppear { BarFocus.shared.count = items.count }
        .onChange(of: items.count) { _, count in
            BarFocus.shared.count = count
        }
        .foregroundStyle(Color("Foreground Outside"))
        .frame(height: max(configManager.config.experimental.foreground.resolveHeight(), 1.0))
        .frame(maxWidth: .infinity)
        .padding(.horizontal, configManager.config.experimental.foreground.horizontalPadding)
        // Extra on the right only. macOS draws its recording dot in the corner
        // above every window, so without this the clock is drawn through it.
        .padding(.trailing, configManager.config.experimental.foreground.trailingPadding)
        .background(.black.opacity(0.001))
        .preferredColorScheme(theme)
    }

    @ViewBuilder
    private func buildView(for item: TomlWidgetItem) -> some View {
        let config = ConfigProvider(
            config: configManager.resolvedWidgetConfig(for: item))

        switch item.id {
        case "default.spaces":
            SpacesWidget().environmentObject(config)

        case "default.network":
            NetworkWidget().environmentObject(config)

        case "default.battery":
            BatteryWidget().environmentObject(config)

        case "default.time":
            TimeWidget(calendarManager: CalendarManager(configProvider: config))
                .environmentObject(config)
            
        case "default.keyboardlayout":
            KeyboardLayoutWidget().environmentObject(config)

        case "default.audio":
            AudioWidget().environmentObject(config)

        case "default.updates":
            UpdatesWidget().environmentObject(config)
        case "default.display":
            DisplayWidget().environmentObject(config)
        case "default.microphone":
            MicrophoneWidget().environmentObject(config)

        case "default.bluetooth":
            BluetoothWidget().environmentObject(config)

        case "default.monitor":
            SystemMonitorWidget().environmentObject(config)

        case "default.stayawake":
            StayAwakeWidget().environmentObject(config)

        case "default.privacy":
            PrivacyWidget().environmentObject(config)

        case "default.applemenu":
            AppleMenuWidget().environmentObject(config)

        case "default.appmenus":
            AppMenusWidget().environmentObject(config)

        case "default.nowplaying":
            NowPlayingWidget()
                .environmentObject(config)

        case "default.reveal":
            RevealWidget().environmentObject(config)

        case "default.notifications":
            NotificationsWidget().environmentObject(config)

        case "spacer":
            Spacer().frame(minWidth: 50, maxWidth: .infinity)

        case "divider":
            Rectangle()
                .fill(Color("Active"))
                .frame(width: 2, height: 15)
                .clipShape(Capsule())

        default:
            Text("?\(item.id)?").foregroundColor(.red)
        }
    }
}
