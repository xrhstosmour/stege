import SwiftUI

/// The Bluetooth rune, drawn rather than taken from SF Symbols.
///
/// SF Symbols ships no Bluetooth glyph, so the widget stood in a `wave.3.right`
/// antenna, which reads as Wi-Fi or AirPlay and sat next to the real Wi-Fi icon
/// looking like a duplicate. The mark itself is six straight strokes, so
/// drawing it is both exact and cheaper than bundling an image.
struct BluetoothGlyph: View {
    /// Height in points. The rune is roughly half as wide as it is tall, which
    /// is the proportion the real mark uses.
    var height: CGFloat = 13
    /// Struck through, for a controller that is switched off.
    var slashed: Bool = false

    private var width: CGFloat { height * 0.58 }
    private var lineWidth: CGFloat { max(1, height * 0.11) }

    var body: some View {
        ZStack {
            rune
                .stroke(
                    style: StrokeStyle(
                        lineWidth: lineWidth, lineCap: .round,
                        lineJoin: .round))

            if slashed {
                // Drawn in two passes: a cut-out in the background colour under
                // the stroke, so the slash reads as a break in the rune rather
                // than a line crossing it, which is how macOS draws its own
                // slashed glyphs.
                slash
                    .stroke(
                        style: StrokeStyle(
                            lineWidth: lineWidth * 2.6, lineCap: .round)
                    )
                    .blendMode(.destinationOut)
                slash
                    .stroke(
                        style: StrokeStyle(
                            lineWidth: lineWidth, lineCap: .round))
            }
        }
        .compositingGroup()
        .frame(width: width, height: height)
        .accessibilityLabel(slashed ? "Bluetooth off" : "Bluetooth")
    }

    /// The rune as one continuous stroke: up the right side to the top point,
    /// straight down the centre, then out and back along the bottom half.
    private var rune: Path {
        Path { path in
            let inset = lineWidth / 2
            let left = inset
            let right = width - inset
            let centre = width / 2
            let top = inset
            let bottom = height - inset
            let upper = height * 0.29
            let lower = height * 0.71

            path.move(to: CGPoint(x: left, y: lower))
            path.addLine(to: CGPoint(x: right, y: upper))
            path.addLine(to: CGPoint(x: centre, y: top))
            path.addLine(to: CGPoint(x: centre, y: bottom))
            path.addLine(to: CGPoint(x: right, y: lower))
            path.addLine(to: CGPoint(x: left, y: upper))
        }
    }

    private var slash: Path {
        Path { path in
            path.move(to: CGPoint(x: width * 0.05, y: height * 0.05))
            path.addLine(to: CGPoint(x: width * 0.95, y: height * 0.95))
        }
    }
}

/// Written as a `PreviewProvider` rather than with the `#Preview` macro, like
/// every other preview here. The macro needs Xcode's plugin to expand, and
/// there is no Xcode on the machine this is checked on, so it failed to expand
/// and stopped the compiler before it type-checked anything else in the app.
struct BluetoothGlyph_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 16) {
            BluetoothGlyph()
            BluetoothGlyph(slashed: true)
            BluetoothGlyph(height: 24)
            BluetoothGlyph(height: 24, slashed: true)
        }
        .padding()
        .foregroundStyle(.white)
        .background(.black)
    }
}
