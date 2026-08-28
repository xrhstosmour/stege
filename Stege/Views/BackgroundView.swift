import SwiftUI

struct BackgroundView: View {
    @ObservedObject var configManager = ConfigManager.shared

    private func spacer(_ geometry: GeometryProxy) -> some View {
        let theme: ColorScheme? = {
            switch configManager.config.rootToml.theme {
            case "dark": return .dark
            case "light": return .light
            default: return nil
            }
        }()
        
        let height = configManager.config.experimental.background.resolveHeight()
        
        return Color.clear
            .frame(height: height ?? geometry.size.height)
            .preferredColorScheme(theme)
        
    }
    
    var body: some View {
        if configManager.config.experimental.background.displayed {
            GeometryReader { geometry in
                if configManager.config.experimental.background.black {
                    spacer(geometry)
                        .background(.black)
                        .overlay(BarGloss())
                        .id("black")
                } else {
                    spacer(geometry)
                        .background(configManager.config.experimental.background.blur)
                        .overlay(BarGloss())
                        .id("blur")
                }
            }
        }
    }
}

/// The lighting laid over whichever base the bar is configured with.
///
/// Solid black and a flat material both read as a strip cut out of the screen,
/// with nothing marking where the bar ends and the desktop starts. The Dock
/// gets its depth from three things and this is the same three: light falling
/// off from the top edge, a shadow gathering at the bottom, and a hairline
/// separating it from what is underneath. Drawn as an overlay so it applies to
/// either base without either of them knowing about it.
struct BarGloss: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(0.10), location: 0),
                .init(color: .white.opacity(0.02), location: 0.4),
                .init(color: .black.opacity(0.14), location: 1),
            ],
            startPoint: .top, endPoint: .bottom
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.10))
                .frame(height: 1)
        }
        .allowsHitTesting(false)
    }
}
