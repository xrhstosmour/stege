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
    /// Album artwork is fetched from the player's own servers when the system
    /// does not hand the image over directly, which in practice means
    /// `Spotify`. It is the only outbound request Stege makes, so it can be
    /// refused. It moved here with the popup that draws it.
    var fetchesArtwork: Bool {
        config["fetch-artwork"]?.boolValue ?? true
    }

    @ObservedObject private var manager = AudioManager.shared
    @State private var rect: CGRect = .zero

    var body: some View {
        HStack(spacing: 4) {
            SoundGlyph(
                level: manager.volume,
                isOutputMuted: manager.isOutputMuted,
                style: glyphStyle)

            if showPercentage {
                Text(
                    manager.isOutputMuted || manager.volume <= 0.001
                        ? "Muted"
                        : "\(Int((manager.volume * 100).rounded()))%"
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
        // Scroll and right click are the two things a sound control in a menu
        // bar is expected to do without opening anything. All three buttons go
        // through here rather than leaving the left one to SwiftUI, because a
        // view sitting over a tap gesture swallows it.
        .overlay(
            PointerInput(
                onClick: { showPopup() },
                onScroll: { manager.nudgeVolume(by: Double($0) * 0.05) },
                onRightClick: { manager.toggleOutputMute() })
        )
        .help(tooltip)
    }

    private func showPopup() {
        MenuBarPopup.show(rect: rect, id: "audio") {
            AudioPopup(
                manager: manager, scope: .output,
                fetchesArtwork: fetchesArtwork)
        }
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

/// Which half of the sound hardware a popup is for.
///
/// The speaker and the microphone are separate entries in the bar, so they get
/// separate popups. One popup listing both meant clicking either icon opened
/// the same thing, and the icon you clicked said nothing about what you got.
enum AudioScope {
    case output
    case input
}

struct AudioPopup: View {
    @ObservedObject var manager: AudioManager
    /// What is playing, under the application playing it.
    ///
    /// This is where Control Center puts it, and it is where it is worth
    /// having: the two questions asked of a speaker icon are how loud it is
    /// and what is coming out of it, and the second used to need a widget of
    /// its own in the bar to answer.
    @ObservedObject private var playing = NowPlayingManager.shared
    let scope: AudioScope
    /// Whether the artwork may be fetched over the network. Read from the
    /// audio widget's own settings now that the now playing widget, which used
    /// to carry it, is gone.
    let fetchesArtwork: Bool

    /// One block: how loud it is, and which device it is using. No opening
    /// line naming the popup, because clicking the speaker is already the
    /// answer to what this is.
    var body: some View {
        VStack(alignment: .leading, spacing: PopupStyle.spacing) {
            switch scope {
            case .output:
                section(
                    symbol: manager.isOutputMuted || manager.volume <= 0.001
                        ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    isMuted: manager.isOutputMuted,
                    level: manager.volume,
                    setLevel: { manager.setOutputLevel($0) },
                    toggleMute: { manager.toggleOutputMute() },
                    devices: manager.outputDevices,
                    selected: manager.currentOutputID,
                    input: false)
            case .input:
                if manager.hasInput {
                    section(
                        symbol: manager.isInputMuted
                            ? "mic.slash.fill" : "mic.fill",
                        isMuted: manager.isInputMuted,
                        level: manager.inputVolume,
                        setLevel: { manager.setInputLevel($0) },
                        toggleMute: { manager.toggleInputMute() },
                        devices: manager.inputDevices,
                        selected: manager.currentInputID,
                        input: true)
                } else {
                    Text("No microphone")
                        .font(.system(size: PopupStyle.bodySize))
                        .opacity(0.6)
                        .popupStaticRow()
                }
            }

            if scope == .output,
                !manager.sources.isEmpty || playing.nowPlaying != nil
                    || playing.failure != nil
            {
                PopupSeparator()
                VStack(alignment: .leading, spacing: PopupStyle.rowSpacing) {
                    // "Playing  Spotify", not "Playing" with a row under it
                    // saying Spotify. The application is the rest of the
                    // sentence the heading starts, and it cost a whole row to
                    // say it on its own.
                    PopupSectionTitle(title: "Playing") { playingIn }
                        .popupStaticRow()

                    // Under the application making the sound, not above the
                    // volume slider. The track belongs to that application,
                    // and putting it at the top of the popup left the two
                    // halves of one answer at opposite ends of it.
                    nowPlaying
                }
            }

            PopupSeparator()

            PopupSettingsRow(title: "Sound Settings") {
                openSettings(
                    "x-apple.systempreferences:com.apple.Sound-Settings.extension"
                )
            }
        }
        .popupContainer()
        .onAppear {
            guard scope == .output else { return }
            manager.startWatchingSources()
            playing.fetchesArtwork = fetchesArtwork
            playing.startWatching()
        }
        .onDisappear {
            guard scope == .output else { return }
            manager.stopWatchingSources()
            playing.stopWatching()
        }
    }

    /// The applications making sound, beside the heading.
    ///
    /// Read from `CoreAudio`, which knows about every one of them, so a
    /// browser playing something from a website is named here even though
    /// nothing can be read about what it is playing.
    @ViewBuilder
    private var playingIn: some View {
        if let first = manager.sources.first {
            HStack(spacing: 5) {
                if let icon = first.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 13, height: 13)
                }
                Text(
                    manager.sources.map(\.name).joined(separator: ", ")
                )
                .font(.system(size: PopupStyle.captionSize, weight: .semibold))
                .opacity(0.75)
                .lineLimit(1)
                .truncationMode(.tail)
            }
        }
    }

    /// The track, and the three controls worth having on it.
    ///
    /// Nothing is drawn when nothing is playing, rather than an empty frame
    /// with dead buttons, so the popup is the same height it always was for
    /// anyone not playing anything.
    @ViewBuilder
    private var nowPlaying: some View {
        if let song = playing.nowPlaying {
            VStack(alignment: .leading, spacing: PopupStyle.rowSpacing) {
                HStack(spacing: 10) {
                    AlbumArtView(song: song, side: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(song.title)
                            .font(
                                .system(
                                    size: PopupStyle.bodySize, weight: .medium)
                            )
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(song.artist)
                            .font(.system(size: PopupStyle.captionSize))
                            .opacity(0.6)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 4)
                }
                .popupStaticRow()

                HStack(spacing: 4) {
                    Spacer(minLength: 0)
                    PopupIconButton(symbol: "backward.fill") {
                        playing.previousTrack()
                    }
                    PopupIconButton(
                        symbol: song.state == .playing
                            ? "pause.fill" : "play.fill",
                        size: 14
                    ) {
                        playing.togglePlayPause()
                    }
                    PopupIconButton(symbol: "forward.fill") {
                        playing.nextTrack()
                    }
                    Spacer(minLength: 0)
                }
                .popupStaticRow()

                if let elapsed = progress {
                    ProgressView(value: elapsed)
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                        .popupStaticRow()
                }
            }
        } else if let failure = playing.failure {
            Text(failure)
                .font(.system(size: PopupStyle.captionSize))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
                .popupStaticRow()
        }
    }

    /// Where the track has got to, when the player reports both numbers.
    private var progress: Double? {
        guard let song = playing.nowPlaying,
            let position = song.position,
            let duration = song.duration, duration > 0
        else { return nil }
        return min(1, max(0, position / duration))
    }

    /// One half of the popup.
    ///
    /// `level` is optional because an input device need not expose a settable
    /// gain, which is true of most USB and Bluetooth microphones. Those get a
    /// muted or not line in the slider's place, since a slider that cannot move
    /// is worse than no slider.
    @ViewBuilder
    private func section(
        symbol: String, isMuted: Bool, level: Double?,
        setLevel: @escaping (Double) -> Void, toggleMute: @escaping () -> Void,
        devices: [AudioDevice], selected: AudioObjectID, input: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: PopupStyle.rowSpacing) {
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
                    // Live while muted. Dragging it up is how the sound comes
                    // back, so disabling it took away the one control someone
                    // reaching for the slider was reaching for.
                    Slider(
                        value: Binding(get: { level }, set: setLevel), in: 0...1
                    )

                    // Muted says muted. The level is still there behind it
                    // and the slider still shows where it will come back to,
                    // but a muted output reading 83% is two different answers
                    // to the same question.
                    Text(isMuted ? "Muted" : "\(Int((level * 100).rounded()))%")
                        .font(.system(size: PopupStyle.captionSize))
                        .monospacedDigit()
                        .opacity(0.6)
                        .frame(width: 40, alignment: .trailing)
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
