import SwiftUI

/// A dot, blue while Location Services is in use, mirroring the corner dot
/// macOS draws for the sensors it does have one for.
struct LocationWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    var config: ConfigData { configProvider.config }

    /// Keep the dot visible, dimmed, when idle rather than hiding it.
    ///
    /// macOS itself only shows its indicator while Location is in use, which
    /// is the default here too. That makes the widget invisible most of the
    /// time and indistinguishable from one that is broken, so this offers the
    /// opposite.
    var alwaysShow: Bool { config["always-show"]?.boolValue ?? false }

    @ObservedObject private var manager = LocationManager.shared

    /// Matches the deleted Privacy widget's own dot size.
    private let diameter: CGFloat = 8

    var body: some View {
        // Always in the layout, never conditionally added or removed: that
        // shifted every widget after it sideways each time Location Services
        // started or stopped, which read as the whole bar twitching rather
        // than one indicator changing.
        Circle()
            .fill(Color.blue)
            .frame(width: diameter, height: diameter)
            .frame(maxHeight: .infinity)
            .opacity(manager.isLocationInUse ? 1 : (alwaysShow ? 0.3 : 0))
            .help(
                manager.isLocationInUse
                    ? "Location Services in use" : "Location Services idle")
            .animation(.smooth(duration: 0.2), value: manager.isLocationInUse)
    }
}
