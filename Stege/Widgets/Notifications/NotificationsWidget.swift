import AppKit
import SwiftUI

/// A bell opening a popup in the bar's own style.
///
/// The popup does not list the notifications themselves. macOS has no public
/// API for that, and the only source is a private SQLite database in a
/// TCC-protected group container, which would mean holding Full Disk Access.
/// That permission also grants read access to Mail, Messages and browser data,
/// which is far more than a menu bar widget should ask for.
///
/// It does not open Notification Center either. It used to, and a row whose
/// whole job is to hand off to the panel the bar was meant to replace is not
/// worth a row: pressing it slides Notification Center over the screen and the
/// popup underneath it disappears, so the two are never usefully on screen
/// together. The trackpad gesture and the shortcut in Keyboard settings both
/// still open it, and neither goes through here.
///
/// What the popup does is list the Focus modes and switch between them,
/// through Control Center's own controls. See `FocusReader` for why that is the
/// only route.
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
            .barGlyph()
            .contentShape(Rectangle())
            .background(.black.opacity(0.001))
            .help(focus.activeFocus ?? "Notifications")
            .onTapGesture {
                // Only when there is nothing to show yet. A read opens a
                // Control Center panel, which is not something to do every
                // time the bell is clicked.
                focus.refreshIfNeeded()
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
            .barGlyph()
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

            VStack(alignment: .leading, spacing: PopupStyle.rowSpacing) {
                PopupSectionTitle(title: "Focus") {
                    if focus.isLoading {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                            .opacity(0.5)
                            .contentShape(Rectangle())
                            .onTapGesture { focus.refresh() }
                            .help("Read the list from Control Center again")
                    }
                }
                .popupStaticRow()

                if focus.modes.isEmpty {
                    Text(
                        focus.isLoading
                            ? "Reading Control Center…"
                            : "No Focus modes read yet"
                    )
                    .font(.system(size: PopupStyle.bodySize))
                    .opacity(0.6)
                    .popupStaticRow()
                } else {
                    ForEach(focus.modes) { mode in
                        focusRow(mode)
                    }
                }

                if let failure = focus.failure {
                    Text(failure)
                        .font(.system(size: PopupStyle.captionSize))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .popupStaticRow()
                }
            }

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

    /// One row per Focus, switching it on or, when it is the one already on,
    /// back off.
    private func focusRow(_ mode: FocusMode) -> some View {
        let isOn = focus.activeIdentifier == mode.id
        return HStack(spacing: 10) {
            Image(systemName: isOn ? "moon.fill" : "moon")
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
