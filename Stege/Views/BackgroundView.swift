import SwiftUI

struct BackgroundView: View {
    @ObservedObject var configManager = ConfigManager.shared

    private func spacer(_ geometry: GeometryProxy) -> some View {
        let height = configManager.config.bar.background.resolveHeight()
        
        return Color.clear
            .frame(height: height ?? geometry.size.height)
            .preferredColorScheme(configManager.config.colorScheme)
        
    }
    
    var body: some View {
        if configManager.config.bar.background.displayed {
            GeometryReader { geometry in
                if configManager.config.bar.background.black {
                    spacer(geometry)
                        .background(BarStyle.surface)
                        .id("black")
                } else {
                    spacer(geometry)
                        .background(configManager.config.bar.background.blur)
                        .id("blur")
                }
            }
        }
    }
}
