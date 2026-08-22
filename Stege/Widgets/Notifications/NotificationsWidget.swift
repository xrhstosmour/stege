import SwiftUI

/// A bell that opens macOS's own Notification Center.
///
/// Stege does not draw the notification list itself. macOS has no public API
/// for it, and the only way to read the contents is a private SQLite database
/// in a TCC-protected group container, which would mean holding Full Disk
/// Access. That permission also grants read access to Mail, Messages and
/// browser data, which is far too much for a menu bar widget, and the schema is
/// undocumented and has already changed between releases.
///
/// Opening the system panel gives the real list, grouped and styled as macOS
/// does, along with its own per-notification dismiss and Clear All, and the
/// click-through into the app that posted it. All of it for free, and correct
/// by construction.
struct NotificationsWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    var config: ConfigData { configProvider.config }

    /// Also draw a second control opening Control Center, which is the other
    /// panel replacing the menu bar takes away.
    var showControlCentre: Bool {
        config["show-control-centre"]?.boolValue
            ?? config["show-control-center"]?.boolValue ?? false
    }

    var body: some View {
        HStack(spacing: 8) {
            control(
                symbol: "bell",
                extra: .notificationCentre,
                help: "Notification Center")

            if showControlCentre {
                control(
                    symbol: "switch.2",
                    extra: .controlCentre,
                    help: "Control Center")
            }
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func control(
        symbol: String, extra: MenuExtra.Identifier, help: String
    ) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 12))
            .contentShape(Rectangle())
            .background(.black.opacity(0.001))
            .help(help)
            .onTapGesture { MenuExtra.press(extra) }
    }
}
