import SwiftUI

/// A chevron that brings back what hiding the real menu bar took away.
///
/// Two modes.
///
/// `extras`, the default, appends the other applications' status items to the
/// bar: 1Password, Docker, Dropbox and the rest, drawn as their own icons and
/// pressed for real when clicked. Nothing leaves the screen and Stege's own
/// widgets stay where they are. See `MenuBarExtrasReader` for how the items are
/// found without screenshotting them.
///
/// `collapse` is the older behaviour, where the bar gets out of the way so the
/// real menu bar underneath becomes reachable. It is the fallback for anything
/// the Accessibility route cannot reach. `sticky` keeps it out of the way until
/// it is expanded again, leaving a small button in the middle of the menu bar
/// to do that with, and `sticky = false` brings it back once the pointer
/// travels far enough down or a timeout expires.
struct RevealWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    var config: ConfigData { configProvider.config }

    enum Mode: String {
        case extras
        case collapse
    }

    var mode: Mode {
        Mode(rawValue: config["mode"]?.stringValue ?? "extras") ?? .extras
    }

    var iconSize: CGFloat {
        CGFloat(config["icon-size"]?.intValue ?? 15)
    }

    /// Stay out of the way until pressed again, rather than coming back on
    /// pointer movement. `collapse` only.
    var sticky: Bool { config["sticky"]?.boolValue ?? true }
    /// How far the pointer must move down before the bar returns. Unused in
    /// sticky mode.
    var returnThreshold: Double {
        Double(config["return-threshold"]?.intValue ?? 80)
    }
    /// Seconds after which the bar returns even if the pointer never moves.
    /// Unused in sticky mode.
    var timeout: Double { Double(config["timeout"]?.intValue ?? 10) }

    private let visibility = BarVisibility.shared
    @ObservedObject private var reader = MenuBarExtrasReader.shared
    @State private var isShowingExtras = false

    var body: some View {
        HStack(spacing: 6) {
            chevron
            if mode == .extras, isShowingExtras {
                extras
            }
        }
        .animation(.smooth(duration: 0.2), value: isShowingExtras)
        .animation(.smooth(duration: 0.2), value: reader.items.count)
    }

    private var chevron: some View {
        Image(systemName: chevronSymbol)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 4)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .background(.black.opacity(0.001))
            .onTapGesture(perform: toggle)
            .help(helpText)
    }

    private var chevronSymbol: String {
        switch mode {
        case .extras: return isShowingExtras ? "chevron.left" : "chevron.right"
        case .collapse: return sticky ? "chevron.left" : "chevron.right"
        }
    }

    private var helpText: String {
        switch mode {
        case .extras:
            return isShowingExtras
                ? "Hide the other menu bar items"
                : "Show the other menu bar items"
        case .collapse:
            return "Show the system menu bar"
        }
    }

    private func toggle() {
        switch mode {
        case .extras:
            if !isShowingExtras {
                reader.startWatching()
                reader.refresh()
            }
            isShowingExtras.toggle()
        case .collapse:
            if sticky {
                visibility.toggleCollapsed()
            } else {
                visibility.hide(
                    returnThreshold: returnThreshold, timeout: timeout)
            }
        }
    }

    @ViewBuilder
    private var extras: some View {
        if !reader.isTrusted {
            Image(systemName: "lock.fill")
                .font(.system(size: 10))
                .help("Stege needs Accessibility permission to read these")
        } else if reader.items.isEmpty {
            Text("None")
                .font(.system(size: 11))
                .opacity(0.5)
        } else {
            HStack(spacing: 6) {
                ForEach(reader.items) { item in
                    extraIcon(item)
                }
            }
        }
    }

    private func extraIcon(_ item: MenuBarExtraItem) -> some View {
        Group {
            if let icon = item.icon {
                Image(nsImage: icon).resizable()
            } else {
                Image(systemName: "app.dashed").resizable()
            }
        }
        .frame(width: iconSize, height: iconSize)
        .contentShape(Rectangle())
        .onTapGesture { reader.press(item) }
        .help(item.name)
    }
}

/// The button left behind while the bar is collapsed.
///
/// Drawn on its own tiny panel rather than inside the bar, because the bar is
/// gone: what is on screen underneath is the real menu bar, and a full-width
/// panel over it would swallow the clicks meant for the status items it just
/// revealed.
struct CollapsedRevealView: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .contentShape(Rectangle())
            .onTapGesture { BarVisibility.shared.toggleCollapsed() }
            .help("Bring Stege back")
    }
}
