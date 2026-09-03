import SwiftUI

/// The microphone on its own, for a bar that wants input and output as two
/// separate controls rather than one.
///
/// Both widgets share `AudioManager.shared` and open the same popup, so which
/// one is clicked only changes where the popup is anchored.
struct MicrophoneWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    var config: ConfigData { configProvider.config }

    /// Show the input level beside the glyph.
    var showPercentage: Bool { config["show-percentage"]?.boolValue ?? false }

    @ObservedObject private var manager = AudioManager.shared
    @State private var rect: CGRect = .zero

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: manager.isInputMuted ? "mic.slash.fill" : "mic.fill")
                .barGlyphBox(widest: "mic.fill", "mic.slash.fill")
                .foregroundStyle(manager.isInputMuted ? Color.red : Color.primary)

            if showPercentage, let level = manager.inputVolume {
                Text(
                    manager.isInputMuted
                        ? "Muted"
                        : "\(Int((level * 100).rounded()))%"
                )
                .font(BarStyle.labelFont)
                .monospacedDigit()
            }
        }
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear { rect = geometry.frame(in: .global) }
                    .onChange(of: geometry.frame(in: .global)) { _, new in
                        rect = new
                    }
            }
        )
        .overlay(
            PointerInput(
                onClick: { showPopup() },
                onScroll: { manager.nudgeInputVolume(by: Double($0) * 0.05) },
                onRightClick: { manager.toggleInputMute() })
        )
        .help(tooltip)
        .opacity(manager.hasInput ? 1 : 0.4)
    }

    private func showPopup() {
        MenuBarPopup.show(rect: rect, id: "microphone") {
            AudioPopup(manager: manager, scope: .input)
        }
    }

    private var tooltip: String {
        guard manager.hasInput else { return "No microphone" }
        guard !manager.isInputMuted else { return "Microphone muted" }
        guard let level = manager.inputVolume else { return "Microphone on" }
        return "Microphone at \(Int((level * 100).rounded()))%"
    }
}
