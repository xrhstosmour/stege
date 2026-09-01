import SwiftUI

/// The one size, weight and colour every mark in the bar is drawn at.
///
/// macOS draws its own status items as a single family: one optical size, one
/// stroke weight, one colour, and colour used only to say something is wrong.
/// The bar had drifted a long way from that. Counting the widgets on their own,
/// there were eight different font sizes in one row, 6, 7, 8, 10, 11, 12, 13
/// and 15, next to a battery drawn as a filled white pill with the number
/// inside it, a hand-drawn Bluetooth path, SF Symbols, and plain text for the
/// input source. Five ways of drawing an icon, side by side.
///
/// Widgets take these instead of choosing for themselves. A widget that needs
/// to differ should say why.
enum BarStyle {
    /// Every glyph. Matches the optical size of a macOS status item on a bar
    /// this tall.
    static let glyphSize: CGFloat = 13
    static let glyphWeight: Font.Weight = .regular

    /// The box every single-symbol mark is centred in.
    ///
    /// SF Symbols do not share an advance width: `speaker.wave.1.fill` through
    /// `speaker.wave.3.fill` each add an arc, `bell.slash` is wider than
    /// `bell`, `wifi.exclamationmark` is wider than `wifi`. Without a box, a
    /// widget changing state changes its own width, and because the bar is one
    /// `HStack` with a spacer holding the trailing group to the right edge,
    /// every mark to its left slides. Turning the volume up moved the whole
    /// row.
    static let glyphWidth: CGFloat = 18

    /// Text standing in for a glyph, such as the input source code. A point
    /// smaller than a glyph, because a letterform at the same point size reads
    /// larger than a symbol does.
    static let labelSize: CGFloat = 12

    /// A mark riding on a glyph rather than beside it: the charging bolt, the
    /// lock on a widget missing its permission.
    static let badgeSize: CGFloat = 8

    /// Chevrons and other pure navigation marks, which macOS also draws
    /// smaller than the things they act on.
    static let chevronSize: CGFloat = 11

    static var glyphFont: Font {
        .system(size: glyphSize, weight: glyphWeight)
    }

    static var labelFont: Font {
        .system(size: labelSize, weight: .medium)
    }
}

extension View {
    /// One size and one weight, for any symbol drawn in the bar.
    ///
    /// Font only, because several widgets apply this to a container so the
    /// symbols inside inherit it. A single mark that changes shape with state
    /// wants `barGlyphBox` instead.
    func barGlyph() -> some View {
        font(BarStyle.glyphFont)
    }

    /// One size, one weight, and one width: a mark that holds its place in the
    /// row whatever it is currently drawing.
    func barGlyphBox() -> some View {
        font(BarStyle.glyphFont)
            .frame(width: BarStyle.glyphWidth)
    }
}
