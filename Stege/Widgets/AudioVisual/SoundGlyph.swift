import SwiftUI

/// The mark that stands for sound in the bar.
///
/// One glyph, not two. This was a speaker and a microphone kerned together,
/// which is one mark by construction but reads as two things stuck side by
/// side, and it is twice as wide as everything around it.
///
/// `speaker` is the default and is what macOS puts in its own menu bar: the
/// arcs say the level, so the icon is worth looking at rather than only worth
/// clicking. `waveform` is the neutral alternative for anyone who wants one
/// mark for sound in general rather than output in particular. The microphone
/// lives in the popup either way, and the privacy widget is what says when
/// something is listening.
enum SoundGlyphStyle: String {
    case speaker
    case waveform
    /// The old pair, for anyone who preferred it.
    case speakerAndMicrophone = "speaker-and-microphone"
}

struct SoundGlyph: View {
    /// Output volume, 0 to 1.
    var level: Double
    var isOutputMuted: Bool
    var isInputMuted: Bool
    /// Only drawn by the pair style, and only when there is an input device.
    var hasInput: Bool = true
    var style: SoundGlyphStyle = .speaker
    var size: CGFloat = BarStyle.glyphSize

    var body: some View {
        switch style {
        case .speaker:
            Image(systemName: speakerSymbol)
                .font(.system(size: size))
                .accessibilityLabel("Sound")
        case .waveform:
            Image(systemName: isOutputMuted || level <= 0.001
                ? "waveform.slash" : "waveform")
                .font(.system(size: size))
                .accessibilityLabel("Sound")
        case .speakerAndMicrophone:
            HStack(spacing: size * 0.08) {
                Image(systemName: speakerSymbol)
                    .font(.system(size: size))
                if hasInput {
                    Image(
                        systemName: isInputMuted ? "mic.slash.fill" : "mic.fill"
                    )
                    .font(.system(size: size * 0.8))
                    .foregroundStyle(isInputMuted ? Color.red : Color.primary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Sound")
        }
    }

    /// Muted and silent are drawn the same way, because they sound the same.
    private var speakerSymbol: String {
        if isOutputMuted || level <= 0.001 { return "speaker.slash.fill" }
        switch level {
        case ..<0.33: return "speaker.wave.1.fill"
        case ..<0.66: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }
}
