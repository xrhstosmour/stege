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
/// mark for sound in general rather than output in particular.
///
/// There used to be a third, a speaker and a microphone kerned together. The
/// microphone is its own widget now, `default.microphone`, so the pair was two
/// ways of drawing the same thing and twice as wide as anything beside it.
enum SoundGlyphStyle: String {
    case speaker
    case waveform
}

struct SoundGlyph: View {
    /// Output volume, 0 to 1.
    var level: Double
    var isOutputMuted: Bool
    var style: SoundGlyphStyle = .speaker
    var size: CGFloat = BarStyle.glyphSize

    var body: some View {
        switch style {
        case .speaker:
            speaker
                .accessibilityLabel("Sound")
        case .waveform:
            Image(systemName: isOutputMuted || level <= 0.001
                ? "waveform.slash" : "waveform")
                .barGlyphBox(widest: "waveform", "waveform.slash")
                .accessibilityLabel("Sound")
        }
    }

    /// One symbol whose arcs fill by value, rather than three symbols swapped
    /// at thresholds.
    ///
    /// `speaker.wave.1/2/3.fill` each add an arc and each is wider than the
    /// last, so crossing a third of the way up the range used to change the
    /// widget's width and push the rest of the bar sideways. A variable value
    /// draws the same shape at every level, which is also what macOS does with
    /// its own volume mark, and what `NetworkPopup` already does for signal
    /// strength.
    @ViewBuilder
    private var speaker: some View {
        if isOutputMuted || level <= 0.001 {
            // Muted and silent are drawn the same way, because they sound the
            // same.
            Image(systemName: "speaker.slash.fill")
                .barGlyphBox(widest: "speaker.wave.3.fill")
        } else {
            // Two passes, because a variable value hides the arcs it has not
            // reached rather than dimming them, and the bar is now laid out on
            // how much of a symbol is inked rather than how much room it asks
            // for. See `GlyphInk`. A mark whose ink shrinks with the volume
            // would take the gap beside it with it.
            //
            // The dim pass draws all three arcs at every level, so the mark
            // inks the same width whatever the volume, and the bright pass says
            // where the level is. Measured, the difference the dim pass covers
            // is half a point between 39% and full volume, and more at the
            // bottom of the range. `symbolVariableValueMode(.color)` would do
            // this in one pass, and it is macOS 15.
            ZStack {
                Image(systemName: "speaker.wave.3.fill")
                    .opacity(0.28)
                Image(
                    systemName: "speaker.wave.3.fill",
                    variableValue: level)
            }
            .barGlyphBox(widest: "speaker.wave.3.fill")
        }
    }
}
