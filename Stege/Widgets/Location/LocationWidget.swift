import SwiftUI

/// Purple while Location Services is in use, matching the colour macOS uses
/// for it, mirroring the indicator the real menu bar would otherwise draw.
struct LocationWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    var config: ConfigData { configProvider.config }

    /// Keep it visible, dimmed, when idle rather than hiding it.
    ///
    /// macOS itself only shows its indicator while Location is in use, which
    /// is the default here too. That makes the widget invisible most of the
    /// time and indistinguishable from one that is broken, so this offers the
    /// opposite.
    var alwaysShow: Bool { config["always-show"]?.boolValue ?? false }

    @ObservedObject private var manager = LocationManager.shared

    var body: some View {
        if manager.isLocationInUse || alwaysShow {
            Image(systemName: "location.fill")
                .barGlyphBox(widest: "location.fill")
                .foregroundStyle(manager.isLocationInUse ? Color.purple : Color.secondary)
                .opacity(manager.isLocationInUse ? 1 : 0.3)
                .help(
                    manager.isLocationInUse
                        ? "Location Services in use" : "Location Services idle")
                .animation(.smooth(duration: 0.2), value: manager.isLocationInUse)
        }
    }
}
