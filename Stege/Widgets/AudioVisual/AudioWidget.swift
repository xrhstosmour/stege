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
    /// Draw the microphone half of the glyph. Off leaves the speaker on its
    /// own, for a bar that has no room or a machine with no input device worth
    /// showing.
    var showMicrophone: Bool { config["show-microphone"]?.boolValue ?? true }

    @StateObject private var manager = AudioManager()
    @State private var rect: CGRect = .zero

    var body: some View {
        HStack(spacing: 4) {
            SoundGlyph(
                level: manager.volume,
                isOutputMuted: manager.isOutputMuted,
                isInputMuted: manager.isInputMuted,
                hasInput: showMicrophone && manager.hasInput)

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

}

struct AudioPopup: View {
    @ObservedObject var manager: AudioManager

    var body: some View {
        VStack(alignment: .leading, spacing: PopupStyle.spacing) {
            header

            HStack(spacing: 10) {
                Image(systemName: "speaker.fill").font(.system(size: 10))
                Slider(
                    value: Binding(
                        get: { manager.volume },
                        set: { manager.setVolume($0) }
                    ), in: 0...1)
                Image(systemName: "speaker.wave.3.fill").font(.system(size: 10))
            }
            .popupStaticRow()

            deviceSection(
                title: "Output", devices: manager.outputDevices,
                selected: manager.currentOutputID, input: false)

            if !manager.inputDevices.isEmpty {
                deviceSection(
                    title: "Input", devices: manager.inputDevices,
                    selected: manager.currentInputID, input: true)

                Divider()
                microphoneLevel
            }
        }
        .popupContainer(wide: true)
    }

    /// `PopupHeader` takes one symbol name, and this header is one mark drawn
    /// from two, so the row is laid out here with the same metrics rather than
    /// widening that type for the only popup that needs it.
    private var header: some View {
        HStack(spacing: 8) {
            SoundGlyph(
                level: manager.volume,
                isOutputMuted: manager.isOutputMuted,
                isInputMuted: manager.isInputMuted,
                hasInput: manager.hasInput,
                size: PopupStyle.titleSize)
            Text("Sound")
                .font(.system(size: PopupStyle.titleSize, weight: .semibold))
            Spacer(minLength: 8)
        }
    }

    /// A level slider rather than an on/off row, so the microphone reads the
    /// same way as output. Devices that expose no settable gain, most USB and
    /// Bluetooth microphones, fall back to the mute toggle, since a slider that
    /// cannot move is worse than no slider.
    @ViewBuilder
    private var microphoneLevel: some View {
        if let level = manager.inputVolume {
            HStack(spacing: 10) {
                microphoneGlyph
                Slider(
                    value: Binding(
                        get: { level },
                        set: { manager.setInputVolume($0) }
                    ), in: 0...1
                )
                .disabled(manager.isInputMuted)
                .opacity(manager.isInputMuted ? 0.4 : 1)
            }
            .popupStaticRow()
        } else {
            HStack(spacing: 10) {
                microphoneGlyph
                Text(
                    manager.isInputMuted
                        ? "Microphone muted" : "Microphone on"
                )
                .font(.system(size: PopupStyle.bodySize))
                Spacer(minLength: 12)
            }
            .popupRow { manager.toggleInputMute() }
        }
    }

    private var microphoneGlyph: some View {
        Image(systemName: manager.isInputMuted ? "mic.slash.fill" : "mic.fill")
            .font(.system(size: PopupStyle.captionSize))
            .foregroundStyle(manager.isInputMuted ? .red : .primary)
            .frame(width: 14)
            .contentShape(Rectangle())
            .onTapGesture { manager.toggleInputMute() }
    }

    @ViewBuilder
    private func deviceSection(
        title: String, devices: [AudioDevice], selected: AudioObjectID,
        input: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: PopupStyle.rowSpacing) {
            PopupSectionTitle(title).popupStaticRow()
            ForEach(devices) { device in
                HStack(spacing: 10) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .opacity(device.id == selected ? 1 : 0)
                        .frame(width: PopupStyle.iconColumn)
                    Text(device.name)
                        .font(.system(size: PopupStyle.bodySize))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 8)
                }
                .popupRow { manager.selectDevice(device, input: input) }
            }
        }
    }
}
