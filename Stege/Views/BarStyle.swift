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

    /// The box a mark is centred in when nothing narrower will do.
    ///
    /// SF Symbols do not share an advance width: `speaker.wave.3.fill` is 24
    /// points at the bar's size, `mic.fill` is 15, `music.note` is 13, and the
    /// Bluetooth rune is drawn at 8. Without a box, a widget changing state
    /// changes its own width, and because the bar is one `HStack` with a
    /// spacer holding the trailing group to the right edge, every mark to its
    /// left slides. Turning the volume up moved the whole row.
    ///
    /// One box for the whole bar fixed that and bought an uneven row with it:
    /// a mark narrower than the box sits in the middle of it with the slack
    /// showing on both sides, so the gap either side of the microphone read as
    /// half again the gap either side of the Wi-Fi arcs. `barGlyphBox(widest:)`
    /// is the one to reach for, and this is what is left for a mark with no
    /// symbol to measure.
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

    // MARK: - Colour and hover

    /// The bar's ink. Near-black on a light bar, white on a dark one.
    ///
    /// Every mark in the row draws in this rather than in a literal colour, so
    /// the light theme is a theme rather than white on white.
    static let ink = Color("Foreground Outside")
    /// What is knocked out of the ink: the opposite of it, whichever way round
    /// the theme has them.
    static let inkInverse = Color("Foreground Outside Invert")

    /// The wash under a bar item the pointer is on.
    ///
    /// Not the accent colour. macOS lights a menu bar title with a neutral
    /// wash and saves the accent for a menu row that is actually selected, and
    /// a bar that lit up blue on every pass of the pointer would be the
    /// loudest thing on the screen. `ink` at low opacity means it flips with
    /// the theme without a second definition.
    static let hoverFill = ink.opacity(0.15)

    /// The solid surface the bar and its popups are drawn on.
    ///
    /// Black on a dark bar. On a light one, the near-white the Dock and the
    /// system menu bar use, so a light theme is a light bar rather than a dark
    /// one with the ink flipped.
    static let surface = Color("Surface")

    /// One duration for every hover, in the bar and in the popups.
    ///
    /// It was 0.12 seconds on the menu titles, the SwiftUI default on the
    /// workspace pills, and instant in the popups, so the same gesture felt
    /// like three different controls.
    static let hoverAnimation: Animation = .smooth(duration: 0.12)

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
    ///
    /// Prefer `barGlyphBox(widest:)`. This box is as wide as the widest mark in
    /// the bar, so anything narrower than that sits in it with the slack
    /// showing.
    func barGlyphBox() -> some View {
        font(BarStyle.glyphFont)
            .frame(width: BarStyle.glyphWidth)
    }

    /// One size, one weight, and a width that holds still: as wide as the ink
    /// of the widest symbol this particular mark ever draws, and no wider.
    ///
    /// Two things at once, and both are needed for an even row.
    ///
    /// Reserving the widest state is what stops a widget resizing itself when
    /// its state changes, which is what used to slide the rest of the row when
    /// the volume moved.
    ///
    /// Measuring ink rather than the width the symbol asks for is what makes
    /// the gaps equal. Symbols carry their own margins and not the same one:
    /// `speaker.wave.3.fill` asks for 24 points and inks 20, `mic.fill` asks
    /// for 15 and inks 11. Laying out on the asked-for width put a different
    /// amount of nothing between each pair, so one spacing for the row came out
    /// on screen as gaps from 10 to 16 points. On ink it is the spacing
    /// everywhere. See `GlyphInk`.
    ///
    /// Name every state. A symbol left out is one that can outgrow the box and
    /// push the row sideways, which is the bug the reservation is here for.
    func barGlyphBox(widest symbols: String...) -> some View {
        let width = symbols
            .map { GlyphInk.width(of: $0, size: BarStyle.glyphSize) }
            .max()
        return font(BarStyle.glyphFont)
            .frame(width: width ?? BarStyle.glyphWidth)
    }
}

/// Lights a bar item while the pointer is on it.
///
/// One place, because the Apple menu, the application menus and the workspace
/// pills each had their own: two different opacities, two different corner
/// radii, two different animations, and the pills computed a hover state whose
/// two branches were the same colour, so pointing at one did nothing at all.
struct BarHover: ViewModifier {
    var cornerRadius: CGFloat = 5
    var verticalInset: CGFloat = 5
    /// How far the highlight reaches past the item on each side.
    ///
    /// Applied as negative padding on the background, so it costs no layout
    /// width. Giving the item real padding instead widened it, and because the
    /// bar is one `HStack` with a single spacing value, every gap in the row
    /// grew by twice this.
    var horizontalOutset: CGFloat = 0
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isHovered ? BarStyle.hoverFill : .clear)
                    .padding(.vertical, verticalInset)
                    .padding(.horizontal, -horizontalOutset)
            )
            // The whole frame, not the drawing inside it. `onHover` follows the
            // view's shape, and an icon is `scaledToFit` inside a square frame,
            // so a wide glyph only fills a horizontal band across the middle of
            // it. Pointing anywhere else on the icon lit nothing, and crossing
            // the row made the highlight blink on and off. The highlight has
            // always been drawn against the full frame, so this is the hover
            // catching up with what it was already painting.
            .contentShape(Rectangle())
            .animation(BarStyle.hoverAnimation, value: isHovered)
            .onHover { isHovered = $0 }
    }
}

extension View {
    func barHover(
        cornerRadius: CGFloat = 5, verticalInset: CGFloat = 5,
        horizontalOutset: CGFloat = 0
    ) -> some View {
        modifier(
            BarHover(
                cornerRadius: cornerRadius, verticalInset: verticalInset,
                horizontalOutset: horizontalOutset))
    }
}
