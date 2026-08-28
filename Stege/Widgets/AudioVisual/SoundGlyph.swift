import SwiftUI

/// Output and input as one mark.
///
/// The widget covers both, so it drew a speaker with a microphone tacked on as
/// a badge, and only when that microphone was muted. That reads as a speaker
/// most of the time and as a speaker with a warning on it the rest, never as
/// one control that owns both halves of the machine's sound.
///
/// This is one glyph instead: the speaker on the left, the microphone on the
/// right, kerned tight enough that the pair has a single silhouette. The
/// speaker keeps its wave arcs, so the level is still legible at a glance,
/// which a genuinely single SF Symbol could not do, and either half can carry
/// its own slash when it is muted.
struct SoundGlyph: View {
    /// Output volume, 0 to 1.
    var level: Double
    var isOutputMuted: Bool
    var isInputMuted: Bool
    /// Drawn only when the machine has an input device at all.
    var hasInput: Bool = true
    var size: CGFloat = BarStyle.glyphSize

    var body: some View {
        HStack(spacing: size * 0.08) {
            Image(systemName: speakerSymbol)
                .font(.system(size: size))
            if hasInput {
                Image(systemName: isInputMuted ? "mic.slash.fill" : "mic.fill")
                    .font(.system(size: size * 0.8))
                    .foregroundStyle(isInputMuted ? Color.red : Color.primary)
            }
        }
        // One accessibility element, because it is one control.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sound")
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
