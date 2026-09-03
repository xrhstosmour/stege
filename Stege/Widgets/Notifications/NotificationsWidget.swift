import AppKit
import SwiftUI

/// A bell opening a popup in the bar's own style.
///
/// It lists what macOS has shown a banner for since Stege started, collected as
/// each banner appears. See `NotificationCenterReader`.
///
/// Nothing here opens a system panel. There was a Focus list and a refresh
/// arrow, and both worked by opening Control Center or Notification Center,
/// pressing inside it and closing it again, which put a system panel on screen
/// every time one was used. Reading Focus has no other route: with Do Not
/// Disturb switched on, `AXExtrasMenuBar` publishes no Focus extra and Control
/// Center's own description is unchanged, measured. So the list went rather
/// than the panel stayed, and Focus Settings at the bottom of the popup is
/// where a Focus is switched now.
struct NotificationsWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    var config: ConfigData { configProvider.config }

    /// Also draw a second control opening Control Center, which is the other
    /// panel replacing the menu bar takes away.
    /// Keep the list across restarts. Off by default: remembering writes every
    /// notification's text to the preferences file in plaintext.
    var remembersBetweenLaunches: Bool {
        config["remember-between-launches"]?.boolValue ?? false
    }

    var showControlCentre: Bool {
        config["show-control-centre"]?.boolValue
            ?? config["show-control-center"]?.boolValue ?? false
    }

    @ObservedObject private var centre = NotificationCenterReader.shared
    @State private var rect: CGRect = .zero

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bell")
                .barGlyphBox(widest: "bell")
            // A dot for anything unread, the way every notification icon
            // anywhere says there is something to look at.
            .overlay(alignment: .topTrailing) {
                if centre.hasAny {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 5, height: 5)
                        .offset(x: 3, y: -1)
                }
            }
            .contentShape(Rectangle())
            .background(.black.opacity(0.001))
            .help(helpText)
            .onTapGesture {
                MenuBarPopup.show(rect: rect, id: "notifications") {
                    NotificationsPopup(centre: centre)
                }
            }

            if showControlCentre {
                control(
                    symbol: "switch.2",
                    extra: .controlCentre,
                    help: "Control Center")
            }
        }
        .frame(maxHeight: .infinity)
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear { rect = geometry.frame(in: .global) }
                    .onChange(of: geometry.frame(in: .global)) { _, new in
                        rect = new
                    }
            }
        )
        .onAppear {
            centre.remembersBetweenLaunches = remembersBetweenLaunches
            centre.startWatching()
        }
    }

    private var helpText: String {
        switch centre.notifications.count {
        case 0: return "Notifications"
        case 1: return "1 notification"
        case let count: return "\(count) notifications"
        }
    }

    @ViewBuilder
    private func control(
        symbol: String, extra: MenuExtra.Identifier, help: String
    ) -> some View {
        Image(systemName: symbol)
            .barGlyph()
            .contentShape(Rectangle())
            .background(.black.opacity(0.001))
            .help(help)
            .onTapGesture { MenuExtra.press(extra) }
    }
}

struct NotificationsPopup: View {
    @ObservedObject var centre: NotificationCenterReader

    var body: some View {
        VStack(alignment: .leading, spacing: PopupStyle.spacing) {
            notifications

            PopupSeparator()

            VStack(alignment: .leading, spacing: PopupStyle.rowSpacing) {
                PopupSettingsRow(title: "Notification Settings") {
                    openSettings(
                        "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
                    )
                }

                PopupSettingsRow(title: "Focus Settings", symbol: "moon") {
                    openSettings(
                        "x-apple.systempreferences:com.apple.Focus-Settings.extension"
                    )
                }
            }
        }
        .popupContainer()
    }

    /// What has come in since Stege started.
    ///
    /// Collected from the banners macOS draws, as it draws them. Nothing here
    /// opens Notification Center, presses anything in it, or moves the pointer:
    /// the list is what arrived, and clearing a row clears Stege's copy of it.
    /// macOS keeps its own, and Notification Center is still where a
    /// notification is answered.
    @ViewBuilder
    private var notifications: some View {
        VStack(alignment: .leading, spacing: PopupStyle.rowSpacing) {
            PopupSectionTitle(title: "Notifications") {
                if !centre.notifications.isEmpty {
                    Text("Clear")
                        .font(.system(size: PopupStyle.captionSize))
                        .opacity(0.6)
                        .contentShape(Rectangle())
                        .help("Clear this list. macOS keeps its own")
                        .onTapGesture { centre.forgetAll() }
                }
            }
            .popupStaticRow()

            if !centre.isTrusted {
                Text("Needs Accessibility permission")
                    .font(.system(size: PopupStyle.bodySize))
                    .opacity(0.6)
                    .popupStaticRow()
            } else if centre.notifications.isEmpty {
                Text("Nothing since Stege started")
                    .font(.system(size: PopupStyle.bodySize))
                    .opacity(0.6)
                    .popupStaticRow()
            } else {
                ForEach(centre.notifications.prefix(8)) { entry in
                    notificationRow(entry)
                }
            }
        }
    }

    private func notificationRow(_ entry: SystemNotification) -> some View {
        HStack(alignment: .top, spacing: 10) {
            applicationIcon(for: entry)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(entry.application)
                        .font(
                            .system(
                                size: PopupStyle.captionSize,
                                weight: .semibold)
                        )
                        .opacity(0.6)
                    Spacer(minLength: 4)
                    Text(entry.time)
                        .font(.system(size: PopupStyle.captionSize))
                        .opacity(0.5)
                }
                Text(entry.title)
                    .font(.system(size: PopupStyle.bodySize, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !detail(for: entry).isEmpty {
                    Text(detail(for: entry))
                        .font(.system(size: PopupStyle.captionSize))
                        .opacity(0.75)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .popupRow { centre.forget(entry) }
        .help("Dismiss")
    }

    /// The posting application, in the leading column every other popup row
    /// already lays its icon out in.
    ///
    /// Resolved by display name, because nothing in Notification Center's
    /// accessibility tree carries a bundle identifier. `IconCache` already
    /// handles that lookup and caches it, so this does not open a second one.
    @ViewBuilder
    private func applicationIcon(for entry: SystemNotification) -> some View {
        Group {
            if let icon = IconCache.shared.icon(for: entry.application) {
                Image(nsImage: icon).resizable()
            } else {
                Image(systemName: "app.dashed")
                    .resizable()
                    .scaledToFit()
                    .opacity(0.5)
            }
        }
        .frame(width: PopupStyle.iconColumn, height: PopupStyle.iconColumn)
    }

    private func detail(for entry: SystemNotification) -> String {
        [entry.subtitle, entry.body]
            .filter { !$0.isEmpty }
            .joined(separator: " \u{00B7} ")
    }

}
