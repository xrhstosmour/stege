import CoreAudio
import SwiftUI

/// Output volume and microphone state in one control, with a popup for the
/// slider and for choosing input and output devices.
struct AudioWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    var config: ConfigData { configProvider.config }

    /// Off by default. The icon already conveys the level, and a percentage
    /// that changes width makes the whole right side of the bar shift.
    var showPercentage: Bool { config["show-percentage"]?.boolValue ?? false }
    /// Draw the microphone beside the speaker.
    var showMicrophone: Bool { config["show-microphone"]?.boolValue ?? true }

    @StateObject private var manager = AudioManager()
    @State private var rect: CGRect = .zero

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: speakerSymbol).font(.system(size: 12))

            // The microphone shares this control rather than sitting apart,
            // because output and input are the one thing people come here for.
            if showMicrophone, manager.hasInput {
                Image(
                    systemName: manager.isInputMuted ? "mic.slash" : "mic"
                )
                .font(.system(size: 11))
                .foregroundStyle(manager.isInputMuted ? .red : .primary)
            }

            if showPercentage {
                Text("\(Int((manager.volume * 100).rounded()))%")
                    .font(.system(size: 11))
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
        .onTapGesture {
            MenuBarPopup.show(rect: rect, id: "audio") {
                AudioPopup(manager: manager)
            }
        }
    }

    private var speakerSymbol: String {
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
        VStack(alignment: .leading, spacing: 12) {
            Text("Sound").font(.system(size: 13, weight: .semibold))

            HStack(spacing: 8) {
                Image(systemName: "speaker.fill").font(.system(size: 10))
                Slider(
                    value: Binding(
                        get: { manager.volume },
                        set: { manager.setVolume($0) }
                    ), in: 0...1)
                Image(systemName: "speaker.wave.3.fill").font(.system(size: 10))
            }

            deviceSection(
                title: "Output", symbol: "hifispeaker",
                devices: manager.outputDevices,
                selected: manager.currentOutputID, input: false)

            if !manager.inputDevices.isEmpty {
                deviceSection(
                    title: "Input", symbol: "mic",
                    devices: manager.inputDevices,
                    selected: manager.currentInputID, input: true)

                Divider()
                HStack(spacing: 8) {
                    Image(
                        systemName: manager.isInputMuted
                            ? "mic.slash.fill" : "mic.fill"
                    )
                    .font(.system(size: 11))
                    Text(
                        manager.isInputMuted
                            ? "Microphone muted" : "Microphone on"
                    )
                    .font(.system(size: 12))
                    Spacer(minLength: 12)
                }
                .contentShape(Rectangle())
                .onTapGesture { manager.toggleInputMute() }
            }
        }
        .padding(14)
        // Fixed, not a minimum: `Slider` expands to fill whatever it is offered
        // and the popup panel spans the whole screen.
        .frame(width: 280, alignment: .leading)
    }

    @ViewBuilder
    private func deviceSection(
        title: String, symbol: String, devices: [AudioDevice],
        selected: AudioObjectID, input: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 10)).opacity(0.7)
                Text(title).font(.system(size: 11, weight: .medium)).opacity(0.7)
            }
            ForEach(devices) { device in
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .opacity(device.id == selected ? 1 : 0)
                        .frame(width: 10)
                    Text(device.name).font(.system(size: 12)).lineLimit(1)
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
                .onTapGesture { manager.selectDevice(device, input: input) }
            }
        }
    }
}
