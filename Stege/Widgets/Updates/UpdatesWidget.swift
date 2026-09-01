import SwiftUI

/// A mark while something is waiting to be updated.
///
/// Hidden when there is nothing, which is most of the time, so the bar stays as
/// short as it can. `always-show` keeps it visible and dimmed instead, the way
/// the stay-awake cup does.
struct UpdatesWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    var config: ConfigData { configProvider.config }

    var alwaysShow: Bool { config["always-show"]?.boolValue ?? false }
    /// The count beside the mark. Off by default: the bar says there is
    /// something, the popup says what.
    var showCount: Bool { config["show-count"]?.boolValue ?? false }
    var includesSystem: Bool { config["macos"]?.boolValue ?? true }
    var includesHomebrew: Bool { config["homebrew"]?.boolValue ?? true }
    /// How often to look, in minutes. Reading Homebrew forks a process, so this
    /// is deliberately slow.
    var interval: Int { config["refresh-interval"]?.intValue ?? 30 }

    @StateObject private var manager = UpdatesManager()
    @State private var rect: CGRect = .zero

    var body: some View {
        Group {
            if manager.count > 0 || alwaysShow {
                content
            }
        }
        .frame(maxHeight: .infinity)
        .onAppear {
            manager.configure(
                interval: TimeInterval(max(1, interval) * 60),
                system: includesSystem,
                homebrew: includesHomebrew)
        }
    }

    private var content: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.down.circle")
                .barGlyphBox()
                .opacity(manager.count > 0 ? 1 : 0.35)

            if showCount, manager.count > 0 {
                Text("\(manager.count)")
                    .font(BarStyle.labelFont)
                    .monospacedDigit()
            }
        }
        .contentShape(Rectangle())
        .background(.black.opacity(0.001))
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear { rect = geometry.frame(in: .global) }
                    .onChange(of: geometry.frame(in: .global)) { _, new in
                        rect = new
                    }
            }
        )
        .onTapGesture {
            MenuBarPopup.show(rect: rect, id: "updates") {
                UpdatesPopup(manager: manager)
            }
        }
        .help(tooltip)
    }

    private var tooltip: String {
        switch manager.count {
        case 0: return "Nothing to update"
        case 1: return "1 update"
        case let count: return "\(count) updates"
        }
    }
}

struct UpdatesPopup: View {
    @ObservedObject var manager: UpdatesManager

    private var system: [PendingUpdate] {
        manager.updates.filter { $0.source == .system }
    }
    private var homebrew: [PendingUpdate] {
        manager.updates.filter { $0.source == .homebrew }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PopupStyle.spacing) {
            PopupHeader(
                symbol: "arrow.down.circle.fill", title: "Updates"
            ) {
                if manager.isReading {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .opacity(0.5)
                        .contentShape(Rectangle())
                        .onTapGesture { manager.refresh() }
                        .help("Look again")
                }
            }

            if manager.updates.isEmpty {
                Text(manager.isReading ? "Looking…" : "Everything is up to date")
                    .font(.system(size: PopupStyle.bodySize))
                    .opacity(0.6)
                    .popupStaticRow()
            }

            if !system.isEmpty {
                VStack(alignment: .leading, spacing: PopupStyle.rowSpacing) {
                    PopupSectionTitle("macOS").popupStaticRow()
                    ForEach(system) { update in
                        row(update, symbol: "apple.logo")
                    }
                    // Said out loud, because this is what macOS found when it
                    // last looked rather than what is true right now. Stege
                    // does not check, on purpose.
                    if let checked = manager.systemLastChecked {
                        Text("Checked \(Self.relative(checked))")
                            .font(.system(size: PopupStyle.captionSize))
                            .opacity(0.5)
                            .popupStaticRow()
                    }
                    PopupSettingsRow(
                        title: "Software Update", symbol: "gearshape"
                    ) {
                        manager.openSoftwareUpdate()
                    }
                }
            }

            if !homebrew.isEmpty {
                VStack(alignment: .leading, spacing: PopupStyle.rowSpacing) {
                    PopupSectionTitle("Homebrew").popupStaticRow()
                    ForEach(homebrew.prefix(8)) { update in
                        row(update, symbol: "shippingbox")
                    }
                    if homebrew.count > 8 {
                        Text("and \(homebrew.count - 8) more")
                            .font(.system(size: PopupStyle.captionSize))
                            .opacity(0.5)
                            .popupStaticRow()
                    }
                    // Copied rather than run. Upgrading can restart services
                    // and ask for a password, which is not something a menu bar
                    // should start on one click.
                    PopupSettingsRow(
                        title: "Copy `brew upgrade`", symbol: "doc.on.doc"
                    ) {
                        manager.copyHomebrewCommand()
                        MenuBarPopup.hide()
                    }
                }
            }
        }
        .popupContainer()
    }

    private func row(_ update: PendingUpdate, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: PopupStyle.captionSize))
                .frame(width: PopupStyle.iconColumn)
            Text(update.name)
                .font(.system(size: PopupStyle.bodySize))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            if let version = update.version {
                Text(version)
                    .font(.system(size: PopupStyle.captionSize))
                    .opacity(0.6)
            }
        }
        .popupStaticRow()
    }

    private static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
