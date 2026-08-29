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
    /// Which mark stands for sound in the bar. See `SoundGlyphStyle`.
    var glyphStyle: SoundGlyphStyle {
        SoundGlyphStyle(rawValue: config["glyph"]?.stringValue ?? "speaker")
            ?? .speaker
    }

    /// Only read by the `speaker-and-microphone` style, which is the only one
    /// with a microphone half to leave out.
    var showMicrophone: Bool { config["show-microphone"]?.boolValue ?? true }

    @ObservedObject private var manager = AudioManager.shared
    @State private var rect: CGRect = .zero

    var body: some View {
        HStack(spacing: 4) {
            SoundGlyph(
                level: manager.volume,
                isOutputMuted: manager.isOutputMuted,
                isInputMuted: manager.isInputMuted,
                hasInput: showMicrophone && manager.hasInput,
                style: glyphStyle)

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
        // Scroll and right click are the two things a sound control in a menu
        // bar is expected to do without opening anything. All three buttons go
        // through here rather than leaving the left one to SwiftUI, because a
        // view sitting over a tap gesture swallows it.
        .overlay(
            PointerInput(
                onClick: {
                    MenuBarPopup.show(rect: rect, id: "audio") {
                        AudioPopup(manager: manager)
                    }
                },
                onScroll: { manager.nudgeVolume(by: Double($0) * 0.05) },
                onRightClick: { manager.toggleOutputMute() })
        )
        .help(tooltip)
    }

    private var tooltip: String {
        let level = Int((manager.volume * 100).rounded())
        let output =
            manager.isOutputMuted || level == 0
            ? "Muted" : "Playing at \(level)%"
        guard manager.hasInput else { return output }
        return output
            + (manager.isInputMuted
                ? ", microphone muted" : ", microphone on")
    }

}

struct AudioPopup: View {
    @ObservedObject var manager: AudioManager

    /// Output and input as two matching blocks, rather than one slider, two
    /// device lists and then a second slider stranded at the bottom under a
    /// divider. Each block is the same three things in the same order: what it
    /// is, how loud it is, and which device it is using. The two halves of the
    /// widget then read the same way as the one glyph that stands for them.
    var body: some View {
        VStack(alignment: .leading, spacing: PopupStyle.spacing) {
            header

            section(
                title: "Output",
                symbol: manager.isOutputMuted || manager.volume <= 0.001
                    ? "speaker.slash.fill" : "speaker.wave.2.fill",
                isMuted: manager.isOutputMuted,
                level: manager.volume,
                setLevel: { manager.setVolume($0) },
                toggleMute: { manager.toggleOutputMute() },
                devices: manager.outputDevices,
                selected: manager.currentOutputID,
                input: false)

            if manager.hasInput {
                section(
                    title: "Input",
                    symbol: manager.isInputMuted ? "mic.slash.fill" : "mic.fill",
                    isMuted: manager.isInputMuted,
                    level: manager.inputVolume,
                    setLevel: { manager.setInputVolume($0) },
                    toggleMute: { manager.toggleInputMute() },
                    devices: manager.inputDevices,
                    selected: manager.currentInputID,
                    input: true)
            }

            PopupSeparator()

            PopupSettingsRow(title: "Sound Settings") {
                openSettings(
                    "x-apple.systempreferences:com.apple.Sound-Settings.extension"
                )
            }
        }
        .popupContainer(wide: true)
    }

    private var header: some View {
        HStack(spacing: 8) {
            SoundGlyph(
                level: manager.volume,
                isOutputMuted: manager.isOutputMuted,
                isInputMuted: manager.isInputMuted,
                hasInput: manager.hasInput,
                style: .speaker,
                size: PopupStyle.titleSize)
            Text("Sound")
                .font(.system(size: PopupStyle.titleSize, weight: .semibold))
            Spacer(minLength: 8)
        }
        .padding(.horizontal, PopupStyle.rowHorizontalPadding)
    }

    /// One half of the popup.
    ///
    /// `level` is optional because an input device need not expose a settable
    /// gain, which is true of most USB and Bluetooth microphones. Those get a
    /// muted or not line in the slider's place, since a slider that cannot move
    /// is worse than no slider.
    @ViewBuilder
    private func section(
        title: String, symbol: String, isMuted: Bool, level: Double?,
        setLevel: @escaping (Double) -> Void, toggleMute: @escaping () -> Void,
        devices: [AudioDevice], selected: AudioObjectID, input: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: PopupStyle.rowSpacing) {
            PopupSectionTitle(title).popupStaticRow()

            HStack(spacing: 10) {
                // The glyph is the mute button. macOS puts mute on the same
                // icon, and a separate switch for it would be a fourth control
                // in a row that already has three.
                Image(systemName: symbol)
                    .font(.system(size: PopupStyle.bodySize))
                    .foregroundStyle(isMuted ? Color.red : Color.primary)
                    .frame(width: PopupStyle.iconColumn)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: toggleMute)
                    .help(isMuted ? "Unmute" : "Mute")

                if let level {
                    Slider(
                        value: Binding(get: { level }, set: setLevel), in: 0...1
                    )
                    .disabled(isMuted)
                    .opacity(isMuted ? 0.4 : 1)

                    Text("\(Int((level * 100).rounded()))%")
                        .font(.system(size: PopupStyle.captionSize))
                        .monospacedDigit()
                        .opacity(0.6)
                        .frame(width: 32, alignment: .trailing)
                } else {
                    Text(isMuted ? "Muted" : "On")
                        .font(.system(size: PopupStyle.bodySize))
                        .opacity(0.7)
                    Spacer(minLength: 8)
                }
            }
            .popupStaticRow()

            ForEach(devices) { device in
                deviceRow(device, selected: selected, input: input)
            }
        }
    }

    private func deviceRow(
        _ device: AudioDevice, selected: AudioObjectID, input: Bool
    ) -> some View {
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
