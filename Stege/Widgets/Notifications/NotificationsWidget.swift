import AppKit
import SwiftUI

/// A bell opening a popup in the bar's own style.
///
/// The popup does not list the notifications themselves. macOS has no public
/// API for that, and the only source is a private SQLite database in a
/// TCC-protected group container, which would mean holding Full Disk Access.
/// That permission also grants read access to Mail, Messages and browser data,
/// which is far more than a menu bar widget should ask for, so the list stays
/// where macOS keeps it and the popup opens it.
///
/// What the popup can do without any of that is report and switch Focus, read
/// from `~/Library/DoNotDisturb/DB`, which is not behind Full Disk Access, and
/// written through Control Center's own switches.
struct NotificationsWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    var config: ConfigData { configProvider.config }

    /// Also draw a second control opening Control Center, which is the other
    /// panel replacing the menu bar takes away.
    var showControlCentre: Bool {
        config["show-control-centre"]?.boolValue
            ?? config["show-control-center"]?.boolValue ?? false
    }

    @StateObject private var focus = FocusReader()
    @State private var rect: CGRect = .zero

    var body: some View {
        HStack(spacing: 8) {
            Image(
                systemName: focus.activeFocus == nil ? "bell" : "bell.slash"
            )
            .font(.system(size: 12))
            .contentShape(Rectangle())
            .background(.black.opacity(0.001))
            .help(focus.activeFocus ?? "Notifications")
            .onTapGesture {
                // Read again on open rather than only on the timer, so a Focus
                // switched on a moment ago is already right.
                focus.refresh()
                MenuBarPopup.show(rect: rect, id: "notifications") {
                    NotificationsPopup(focus: focus)
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

struct NotificationsPopup: View {
    @ObservedObject var focus: FocusReader

    var body: some View {
        VStack(alignment: .leading, spacing: PopupStyle.spacing) {
            PopupHeader(
                symbol: focus.activeFocus == nil
                    ? "bell.fill" : "bell.slash.fill",
                title: focus.activeFocus ?? "Notifications",
                tint: focus.activeFocus == nil ? .primary : .purple)

            // Left out entirely when the state cannot be read, rather than
            // reporting Focus as off when that is simply not known.
            if focus.isReadable, !focus.modes.isEmpty {
                VStack(alignment: .leading, spacing: PopupStyle.rowSpacing) {
                    PopupSectionTitle("Focus").popupStaticRow()
                    ForEach(focus.modes) { mode in
                        focusRow(mode)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: PopupStyle.rowSpacing) {
                PopupSettingsRow(
                    title: "Notification Center", symbol: "bell.badge"
                ) {
                    MenuBarPopup.hide()
                    // After the popup is gone, so the two panels are not on
                    // screen together.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        MenuExtra.press(.notificationCentre)
                    }
                }

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

    /// One row per Focus, switching it on or, when it is the one already on,
    /// back off.
    private func focusRow(_ mode: FocusMode) -> some View {
        let isOn = focus.activeIdentifier == mode.id
        return HStack(spacing: 10) {
            Image(systemName: mode.symbol)
                .font(.system(size: PopupStyle.captionSize))
                .foregroundStyle(isOn ? Color.purple : Color.secondary)
                .frame(width: PopupStyle.iconColumn)
            Text(mode.name)
                .font(.system(size: PopupStyle.bodySize))
                .lineLimit(1)
            Spacer(minLength: 8)
            if focus.switching == mode.id {
                ProgressView().controlSize(.mini)
            } else if isOn {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.purple)
            }
        }
        .popupRow { focus.toggle(mode) }
    }
}
