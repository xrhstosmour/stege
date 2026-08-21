import SwiftUI

/// Orange when the microphone is in use, green when the camera is, mirroring the
/// indicators macOS draws in the menu bar that Stege covers up.
struct PrivacyWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    var config: ConfigData { configProvider.config }

    /// Dots match the system's own indicator. Icons are clearer about which
    /// device is active, which is why they are the default here.
    var useDots: Bool { config["style"]?.stringValue == "dot" }

    @StateObject private var manager = PrivacyManager()

    var body: some View {
        HStack(spacing: 5) {
            if manager.isMicrophoneActive {
                indicator(symbol: "mic.fill", color: .orange)
                    .help("Microphone in use")
            }
            if manager.isCameraActive {
                indicator(symbol: "video.fill", color: .green)
                    .help("Camera in use")
            }
        }
        .frame(maxHeight: .infinity)
        .animation(.smooth(duration: 0.2), value: manager.isMicrophoneActive)
        .animation(.smooth(duration: 0.2), value: manager.isCameraActive)
    }

    @ViewBuilder
    private func indicator(symbol: String, color: Color) -> some View {
        if useDots {
            Circle().fill(color).frame(width: 8, height: 8)
        } else {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(color)
        }
    }
}
