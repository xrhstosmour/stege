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
    /// Keep the list across restarts. Off by default: remembering writes every
    /// notification's text to the preferences file in plaintext.
    var remembersBetweenLaunches: Bool {
        config["remember-between-launches"]?.boolValue ?? false
    }

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
            .barGlyphBox(widest: "bell", "bell.slash")
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
                // Neither reader is asked for anything here, which is what
                // keeps opening the bell from putting a Control Center panel on
                // screen. The Focus list is read by its refresh arrow and kept,
                // the notification list by its own, and the banner observer
                // keeps that one current on its own. This used to call
                // `refreshIfNeeded`, which flashed a panel on the first open
                // after every install, in flat contradiction of the comment
                // that stood here.
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
        .onAppear {
            centre.remembersBetweenLaunches = remembersBetweenLaunches
            centre.startWatching()
        }
    }

    private var helpText: String {
        if let focusName = focus.activeFocus { return focusName }
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
    @ObservedObject var focus: FocusReader
    @ObservedObject var centre: NotificationCenterReader

    var body: some View {
        VStack(alignment: .leading, spacing: PopupStyle.spacing) {
            notifications

            PopupSeparator()

            VStack(alignment: .leading, spacing: PopupStyle.rowSpacing) {
                PopupSectionTitle(title: "Focus") {
                    PopupRefresh(
                        isBusy: focus.isLoading,
                        help: "Read the list from Control Center again"
                    ) {
                        focus.refresh()
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
        // Both of the ways this popup goes away: clicked away, or replaced by
        // another widget's popup.
        .onReceive(
            NotificationCenter.default.publisher(for: .willHideWindow)
        ) { _ in centre.flushPending() }
        .onReceive(
            NotificationCenter.default.publisher(for: .willChangeContent)
        ) { _ in centre.flushPending() }
    }

    /// The notifications macOS is holding, read out of Notification Center.
    ///
    /// Clear and the per-row dismissal are Notification Center's own, so this
    /// list and the system's cannot drift apart.
    @ViewBuilder
    private var notifications: some View {
        VStack(alignment: .leading, spacing: PopupStyle.rowSpacing) {
            PopupSectionTitle(title: "Notifications") {
                if !centre.isReading, !centre.notifications.isEmpty {
                    Text("Clear All")
                        .font(.system(size: PopupStyle.captionSize))
                        .opacity(0.6)
                        .contentShape(Rectangle())
                        .onTapGesture { centre.clearAll() }
                }
                // The list keeps itself current from the banners as they
                // arrive, which cannot see a notification dismissed somewhere
                // else. This is the way to ask macOS again.
                PopupRefresh(
                    isBusy: centre.isReading,
                    help: "Read the list from Notification Center again"
                ) {
                    centre.refresh()
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
        .popupRow { centre.dismiss(entry) }
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
