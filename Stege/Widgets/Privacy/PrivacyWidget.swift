import SwiftUI

/// Orange when the microphone is in use, green when the camera is, purple when
/// the screen is being recorded, mirroring the indicators macOS draws in the
/// menu bar that Stege covers up.
struct PrivacyWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    var config: ConfigData { configProvider.config }

    /// Dots match the system's own indicator. Icons are clearer about which
    /// device is active, which is why they are the default here.
    var useDots: Bool { config["style"]?.stringValue == "dot" }
    /// Draw both indicators dimmed when idle rather than hiding them.
    ///
    /// macOS itself only shows its dot while a device is in use, which is the
    /// default here too. That makes the widget invisible most of the time and
    /// indistinguishable from one that is broken, so this offers the opposite.
    var alwaysShow: Bool { config["always-show"]?.boolValue ?? false }

    @ObservedObject private var manager = PrivacyManager.shared

    var body: some View {
        HStack(spacing: 5) {
            if manager.isMicrophoneActive || alwaysShow {
                indicator(symbol: "mic.fill", color: .orange)
                    .opacity(manager.isMicrophoneActive ? 1 : 0.3)
                    .help(
                        manager.isMicrophoneActive
                            ? "Microphone in use" : "Microphone idle")
            }
            if manager.isCameraActive || alwaysShow {
                indicator(symbol: "video.fill", color: .green)
                    .opacity(manager.isCameraActive ? 1 : 0.3)
                    .help(
                        manager.isCameraActive ? "Camera in use" : "Camera idle")
            }
            if manager.isScreenRecordingActive || alwaysShow {
                // Purple, which is the colour macOS uses for it.
                indicator(
                    symbol: "rectangle.dashed.badge.record", color: .purple
                )
                .opacity(manager.isScreenRecordingActive ? 1 : 0.3)
                .help(
                    manager.isScreenRecordingActive
                        ? "Screen being recorded" : "Screen not being recorded")
            }
        }
        .frame(maxHeight: .infinity)
        .animation(.smooth(duration: 0.2), value: manager.isMicrophoneActive)
        .animation(.smooth(duration: 0.2), value: manager.isCameraActive)
        .animation(
            .smooth(duration: 0.2), value: manager.isScreenRecordingActive)
    }

    @ViewBuilder
    private func indicator(symbol: String, color: Color) -> some View {
        if useDots {
            Circle().fill(color).frame(width: 8, height: 8)
        } else {
            Image(systemName: symbol)
                .barGlyphBox(widest: symbol)
                .foregroundStyle(color)
        }
    }
}
