import SwiftUI

/// A small blue dot in the same column as macOS's own corner privacy dot,
/// directly beneath it, on while Location Services is in use.
///
/// Positioned by `MenuBarView` as a fixed overlay rather than a widget in the
/// bar's own row: it has to sit in that one column regardless of what else is
/// configured, and never displace anything either side of it the way an
/// ordinary widget would.
struct LocationWidget: View {
    /// Matches the deleted Privacy widget's own dot size, on the display the
    /// real dot's size was last measured on. `MenuBarView` overrides this per
    /// screen from `Constants.privacyIndicatorGeometry`.
    var diameter: CGFloat = 8

    @ObservedObject private var manager = LocationManager.shared

    var body: some View {
        Circle()
            .fill(Color.blue)
            .frame(width: diameter, height: diameter)
            .opacity(manager.isLocationInUse ? 1 : 0)
            // Fully transparent when idle, so hovering it then shouldn't
            // surface a tooltip for a dot the user cannot see.
            .allowsHitTesting(manager.isLocationInUse)
            .help("Location Services in use")
            .animation(.smooth(duration: 0.2), value: manager.isLocationInUse)
    }
}
