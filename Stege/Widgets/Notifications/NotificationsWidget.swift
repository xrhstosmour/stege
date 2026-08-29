import AppKit
import SwiftUI

/// A bell opening a popup in the bar's own style.
///
/// It lists the notifications macOS is holding, and switches Focus. Both come
/// out of the system's own accessibility tree rather than from a file or a
/// picture of the screen. See `NotificationCenterReader` and `FocusReader`.
///
/// There is no row that opens Notification Center. There used to be, and a row
/// whose whole job is to hand off to the panel the bar was meant to replace is
/// not worth a row.
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
    @ObservedObject private var centre = NotificationCenterReader.shared
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
                // Only when there is nothing to show yet. A read opens a
                // Control Center panel, which is not something to do every
                // time the bell is clicked.
                focus.refreshIfNeeded()
                centre.refresh()
                MenuBarPopup.show(rect: rect, id: "notifications") {
                    NotificationsPopup(focus: focus, centre: centre)
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
        .onAppear { centre.startWatching() }
    }

    private var helpText: String {
        if let focusName = focus.activeFocus { return focusName }
        switch centre.notifications.count {
        case 0: return centre.hasAny ? "New notification" : "Notifications"
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
    @ObservedObject var focus: FocusReader
    @ObservedObject var centre: NotificationCenterReader

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

    /// The notifications macOS is holding, read out of Notification Center.
    ///
    /// Clear and the per-row dismissal are Notification Center's own, so this
    /// list and the system's cannot drift apart.
    @ViewBuilder
    private var notifications: some View {
        VStack(alignment: .leading, spacing: PopupStyle.rowSpacing) {
            PopupSectionTitle(title: "Notifications") {
                if centre.isReading {
                    ProgressView().controlSize(.mini)
                } else if !centre.notifications.isEmpty {
                    Text("Clear All")
                        .font(.system(size: PopupStyle.captionSize))
                        .opacity(0.6)
                        .contentShape(Rectangle())
                        .onTapGesture { centre.clearAll() }
                }
            }
            .popupStaticRow()

            if !centre.isTrusted {
                Text("Needs Accessibility permission")
                    .font(.system(size: PopupStyle.bodySize))
                    .opacity(0.6)
                    .popupStaticRow()
            } else if let failure = centre.failure {
                Text(failure)
                    .font(.system(size: PopupStyle.captionSize))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .popupStaticRow()
            } else if centre.notifications.isEmpty {
                Text(centre.isReading ? "Reading\u{2026}" : "No notifications")
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
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Text(entry.application)
                    .font(
                        .system(size: PopupStyle.captionSize, weight: .semibold)
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
        .popupRow { centre.dismiss(entry) }
        .help("Dismiss")
    }

    private func detail(for entry: SystemNotification) -> String {
        [entry.subtitle, entry.body]
            .filter { !$0.isEmpty }
            .joined(separator: " \u{00B7} ")
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
