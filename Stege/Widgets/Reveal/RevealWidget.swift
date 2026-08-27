import SwiftUI

/// A chevron that gets Stege out of the way so the real macOS menu bar, and
/// every third-party status item on it, becomes reachable.
///
/// Two modes. `sticky`, the default, collapses the bar until it is expanded
/// again, and leaves a small button at the corner of the screen to do that
/// with. The bar staying put is what makes a status item usable: its menu opens
/// below the menu bar, and a bar that came back on pointer movement would land
/// on top of it. Setting `sticky = false` restores the older behaviour, where
/// the bar returns once the pointer travels far enough down or a timeout
/// expires.
struct RevealWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    var config: ConfigData { configProvider.config }

    /// Stay out of the way until pressed again, rather than coming back on
    /// pointer movement.
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

    var body: some View {
        Image(systemName: sticky ? "chevron.left" : "chevron.right")
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 6)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .background(.black.opacity(0.001))
            .onTapGesture {
                if sticky {
                    visibility.toggleCollapsed()
                } else {
                    visibility.hide(
                        returnThreshold: returnThreshold, timeout: timeout)
                }
            }
            .help("Show the system menu bar")
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
