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
        VStack(alignment: .leading, spacing: 4) {
            header

            // Left out entirely when the state cannot be read, rather than
            // reporting Focus as off when that is simply not known.
            if focus.isReadable, !focus.modes.isEmpty {
                ForEach(focus.modes) { mode in
                    focusRow(mode)
                }
            }

            Divider().padding(.vertical, 4)

            row(
                "bell.badge", "Open Notification Center",
                trailing: "chevron.right"
            ) {
                MenuBarPopup.hide()
                // After the popup is gone, so the two panels are not on screen
                // together.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    MenuExtra.press(.notificationCentre)
                }
            }

            row("gearshape", "Notification Settings", trailing: "chevron.right") {
                open("x-apple.systempreferences:com.apple.Notifications-Settings.extension")
            }

            row("moon", "Focus Settings", trailing: "chevron.right") {
                open("x-apple.systempreferences:com.apple.Focus-Settings.extension")
            }
        }
        .padding(12)
        .frame(width: 240, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "bell.fill").font(.system(size: 12))
            Text("Notifications").font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 8)
        }
        .padding(.bottom, 2)
    }

    /// One row per Focus, switching it on or, when it is the one already on,
    /// back off.
    private func focusRow(_ mode: FocusMode) -> some View {
        let isOn = focus.activeIdentifier == mode.id
        return HStack(spacing: 10) {
            Image(systemName: mode.symbol)
                .font(.system(size: 11))
                .foregroundStyle(isOn ? Color.purple : Color.secondary)
                .frame(width: 16)
            Text(mode.name)
                .font(.system(size: 12))
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
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture { focus.toggle(mode) }
    }

    private func row(
        _ symbol: String, _ title: String, trailing: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 11)).frame(width: 16)
            Text(title).font(.system(size: 12))
            Spacer(minLength: 8)
            Image(systemName: trailing)
                .font(.system(size: 9, weight: .semibold))
                .opacity(0.45)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }

    private func open(_ target: String) {
        guard let url = URL(string: target) else { return }
        NSWorkspace.shared.open(url)
    }
}
