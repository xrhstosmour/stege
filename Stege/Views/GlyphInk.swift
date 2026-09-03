import AppKit

/// How much of a symbol is actually drawn, as opposed to how much room it asks
/// for.
///
/// SF Symbols carry their own margins, and they are not the same margin: at the
/// bar's size `speaker.wave.3.fill` asks for 24 points and inks 20 of them,
/// `mic.fill` asks for 15 and inks 11, `music.note` asks for 13 and inks 9.
/// Laying the bar out on the width each symbol asks for therefore puts a
/// different amount of nothing between each pair of marks, which is why the gap
/// before the microphone read wider than the gap before the Wi-Fi arcs even
/// though the row set one spacing for all of them.
///
/// Measuring the ink instead makes every gap the spacing and nothing else. The
/// margins are symmetric, measured on every symbol the bar draws, so a box the
/// width of the ink leaves the drawing centred where it was.
enum GlyphInk {
    /// Points of ink across, for a symbol drawn at `size`.
    ///
    /// Falls back to the symbol's own width when it cannot be measured, which
    /// is the behaviour this replaced rather than a broken layout.
    static func width(of symbol: String, size: CGFloat) -> CGFloat {
        let key = "\(symbol)@\(size)"
        if let cached = cache[key] { return cached }
        let measured = measure(symbol, size: size)
        cache[key] = measured
        return measured
    }

    /// Read once per symbol per size and kept. Rendering a bitmap is far too
    /// expensive to do while laying out a bar that redraws on every workspace
    /// change, and the answer cannot change: it depends on the symbol and the
    /// point size, both of which are fixed by the time this is asked.
    ///
    /// Main-thread only, which every caller is: these are SwiftUI layouts.
    private static var cache: [String: CGFloat] = [:]

    /// Four samples per point. One is not enough to place an edge within a
    /// point, and the whole exercise is worth a fraction of a point.
    private static let oversample: CGFloat = 4

    private static func measure(_ symbol: String, size: CGFloat) -> CGFloat {
        let configuration = NSImage.SymbolConfiguration(
            pointSize: size, weight: .regular)
        guard
            let image = NSImage(
                systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration)
        else { return size }

        let width = Int((image.size.width * oversample).rounded(.up))
        let height = Int((image.size.height * oversample).rounded(.up))
        guard width > 0, height > 0,
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
                bitsPerPixel: 0)
        else { return image.size.width }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.set()
        image.draw(
            in: NSRect(
                x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        NSGraphicsContext.restoreGraphicsState()

        guard let data = bitmap.bitmapData else { return image.size.width }
        let bytesPerRow = bitmap.bytesPerRow
        let bytesPerPixel = bitmap.bitsPerPixel / 8
        var first = -1
        var last = -1
        for x in 0..<width {
            var inked = false
            for y in 0..<height {
                // The alpha byte is last in an RGBA sample. Anything faint
                // enough to sit under this is not what sets an edge.
                let alpha = data[y * bytesPerRow + x * bytesPerPixel + 3]
                if alpha > 16 {
                    inked = true
                    break
                }
            }
            if inked {
                if first < 0 { first = x }
                last = x
            }
        }
        guard first >= 0 else { return image.size.width }
        return CGFloat(last - first + 1) / oversample
    }
}
