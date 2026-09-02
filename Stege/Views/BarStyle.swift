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
    /// Every glyph.
    ///
    /// Fifteen, not thirteen. Measured on this machine: the system menu bar is
    /// 32 points tall, this bar is 44, and yet the band of ink across the
    /// system's own row of icons and clock came to 20.5 points against 16 for
    /// this one. The bar was both taller than the system's and drawn smaller
    /// inside it, so the marks floated in a lot of black.
    static let glyphSize: CGFloat = 15
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
    static let glyphWidth: CGFloat = 20

    /// Text standing in for a glyph, such as the input source code. Two points
    /// smaller than a glyph, because a letterform at the same point size reads
    /// larger than a symbol does. Only two: a capital at 12 points stands 8.6
    /// points tall against 11 to 14 for the symbols beside it, which was the
    /// one mark in the row that read as undersized rather than as different.
    static let labelSize: CGFloat = 13

    /// A mark riding on a glyph rather than beside it: the charging bolt, the
    /// lock on a widget missing its permission.
    static let badgeSize: CGFloat = 9

    /// Chevrons and other pure navigation marks, which macOS also draws
    /// smaller than the things they act on.
    static let chevronSize: CGFloat = 12

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
