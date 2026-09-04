import SwiftUI

/// Which display this bar is drawn on, counting `NSScreen.screens` from one.
///
/// The same index `AeroSpace` reports for a workspace's monitor, which is what
/// lets one bar draw its own display's workspaces and leave the other's alone.
private struct BarScreenKey: EnvironmentKey {
    static let defaultValue: Int? = nil
}

extension EnvironmentValues {
    var barScreenIndex: Int? {
        get { self[BarScreenKey.self] }
        set { self[BarScreenKey.self] = newValue }
    }
}

struct MenuBarView: View {
    @ObservedObject var configManager = ConfigManager.shared
    /// One-based, matching `NSScreen.screens`. Nil when there is only one bar
    /// or the caller did not say, and then nothing is filtered.
    var screenIndex: Int?

    var body: some View {
        let items = configManager.config.rootToml.widgets.displayed

        HStack(spacing: 0) {
            HStack(spacing: configManager.config.bar.foreground.spacing) {
                ForEach(0..<items.count, id: \.self) { index in
                    let item = items[index]
                    buildView(for: item)
                }
            }
        }
        .foregroundStyle(Color("Foreground Outside"))
        .frame(height: max(configManager.config.bar.foreground.resolveHeight(), 1.0))
        .frame(maxWidth: .infinity)
        .padding(.horizontal, configManager.config.bar.foreground.horizontalPadding)
        // Extra on the right only. macOS draws its recording dot in the corner
        // above every window, so without this the clock is drawn through it.
        .padding(.trailing, configManager.config.bar.foreground.trailingPadding)
        .background(.black.opacity(0.001))
        .contextMenu {
            Button("Permissions…") {
                PermissionsWindowController.shared.show()
            }
        }
        .environment(\.barScreenIndex, screenIndex)
        .preferredColorScheme(configManager.config.colorScheme)
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
            TimeWidget()
                .environmentObject(config)
            
        case "default.keyboardLayout":
            KeyboardLayoutWidget().environmentObject(config)

        case "default.audio":
            AudioWidget().environmentObject(config)

        case "default.display":
            DisplayWidget().environmentObject(config)
        case "default.microphone":
            MicrophoneWidget().environmentObject(config)

        case "default.bluetooth":
            BluetoothWidget().environmentObject(config)

        case "default.appleMenu":
            AppleMenuWidget().environmentObject(config)

        case "default.applicationMenu":
            AppMenusWidget().environmentObject(config)

        case "default.reveal":
            RevealWidget().environmentObject(config)

        case "default.notifications":
            NotificationsWidget().environmentObject(config)

        // Kept as a case so it does not fall through to the unknown-widget
        // marker. There was a now playing widget and there is not any more:
        // what is playing, with its artwork and transport, is in the sound
        // popup. This says so rather than leaving a red `?default.nowplaying?`
        // suggesting the name was mistyped.
        case "default.nowplaying":
            NowPlayingMovedMarker()

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
