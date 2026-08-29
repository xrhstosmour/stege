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
    @ObservedObject private var log = NotificationLog.shared
    @State private var rect: CGRect = .zero

    var body: some View {
        HStack(spacing: 8) {
            Image(
                systemName: focus.activeFocus == nil ? "bell" : "bell.slash"
            )
            .barGlyph()
            // A dot for anything unread, the way every notification icon
            // anywhere says there is something to look at.
            .overlay(alignment: .topTrailing) {
                if !log.entries.isEmpty {
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
                // Only when there is nothing to show yet. A read opens a
                // Control Center panel, which is not something to do every
                // time the bell is clicked.
                focus.refreshIfNeeded()
                MenuBarPopup.show(rect: rect, id: "notifications") {
                    NotificationsPopup(focus: focus, log: log)
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
        .onAppear { log.start() }
    }

    private var helpText: String {
        if let focusName = focus.activeFocus { return focusName }
        let count = log.entries.count
        switch count {
        case 0: return "Notifications"
        case 1: return "1 notification"
        default: return "\(count) notifications"
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
    @ObservedObject var focus: FocusReader
    @ObservedObject var log: NotificationLog

    var body: some View {
        VStack(alignment: .leading, spacing: PopupStyle.spacing) {
            PopupHeader(
                symbol: focus.activeFocus == nil
                    ? "bell.fill" : "bell.slash.fill",
                title: focus.activeFocus ?? "Notifications",
                tint: focus.activeFocus == nil ? .primary : .purple)

            notifications

            PopupSeparator()

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

    /// What has come in since Stege started.
    ///
    /// Not macOS's list, which cannot be read, and Clear empties this one
    /// rather than macOS's, which cannot be written. Both of those are said on
    /// screen rather than left to be discovered.
    @ViewBuilder
    private var notifications: some View {
        VStack(alignment: .leading, spacing: PopupStyle.rowSpacing) {
            PopupSectionTitle(title: "Recent") {
                if !log.entries.isEmpty {
                    Text("Clear")
                        .font(.system(size: PopupStyle.captionSize))
                        .opacity(0.6)
                        .contentShape(Rectangle())
                        .onTapGesture { log.clear() }
                        .help("Empties Stege's list, not Notification Center")
                }
            }
            .popupStaticRow()

            if !log.isTrusted {
                Text("Needs Accessibility permission")
                    .font(.system(size: PopupStyle.bodySize))
                    .opacity(0.6)
                    .popupStaticRow()
            } else if log.entries.isEmpty {
                Text("Nothing since Stege started")
                    .font(.system(size: PopupStyle.bodySize))
                    .opacity(0.6)
                    .popupStaticRow()
            } else {
                ForEach(log.entries.prefix(8)) { entry in
                    notificationRow(entry)
                }
            }
        }
    }

    private func notificationRow(_ entry: NotificationEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                    .font(.system(size: PopupStyle.bodySize, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !entry.body.isEmpty {
                    Text(entry.body)
                        .font(.system(size: PopupStyle.captionSize))
                        .opacity(0.7)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            Text(entry.date, style: .time)
                .font(.system(size: PopupStyle.captionSize))
                .monospacedDigit()
                .opacity(0.5)
        }
        .popupRow { log.remove(entry) }
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
