import SwiftUI

/// Output volume, with a slider popup, and an optional microphone mute toggle.
struct AudioWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    var config: ConfigData { configProvider.config }

    var showMicrophone: Bool { config["show-microphone"]?.boolValue ?? true }
    var showPercentage: Bool { config["show-percentage"]?.boolValue ?? false }

    @StateObject private var manager = AudioManager()
    @State private var rect: CGRect = .zero

    var body: some View {
        HStack(spacing: 8) {
            volume
            if showMicrophone, manager.hasInput, manager.isInputMuted {
                // Only shown while muted. An always-visible microphone icon
                // says nothing, and a muted one is the state worth noticing.
                Image(systemName: "mic.slash.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .contentShape(Rectangle())
                    .onTapGesture { manager.toggleInputMute() }
                    .help("Microphone muted, click to unmute")
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var volume: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 12))
            if showPercentage {
                Text("\(Int((manager.volume * 100).rounded()))%")
                    .font(.system(size: 11))
                    .monospacedDigit()
            }
        }
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
        .onTapGesture {
            MenuBarPopup.show(rect: rect, id: "audio") {
                AudioPopup(manager: manager)
            }
        }
    }

    private var symbol: String {
        if manager.isOutputMuted || manager.volume == 0 {
            return "speaker.slash.fill"
        }
        switch manager.volume {
        case ..<0.33: return "speaker.wave.1.fill"
        case ..<0.66: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }
}

struct AudioPopup: View {
    @ObservedObject var manager: AudioManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Volume").font(.system(size: 13, weight: .semibold))

            HStack(spacing: 8) {
                Image(systemName: "speaker.fill").font(.system(size: 10))
                Slider(
                    value: Binding(
                        get: { manager.volume },
                        set: { manager.setVolume($0) }
                    ), in: 0...1)
                Image(systemName: "speaker.wave.3.fill").font(.system(size: 10))
            }

            if manager.hasInput {
                Divider()
                HStack(spacing: 8) {
                    Image(
                        systemName: manager.isInputMuted
                            ? "mic.slash.fill" : "mic.fill"
                    )
                    .font(.system(size: 11))
                    Text(manager.isInputMuted ? "Microphone muted" : "Microphone on")
                        .font(.system(size: 12))
                    Spacer(minLength: 12)
                }
                .contentShape(Rectangle())
                .onTapGesture { manager.toggleInputMute() }
            }
        }
        .padding(14)
        .frame(minWidth: 240, alignment: .leading)
    }
}
