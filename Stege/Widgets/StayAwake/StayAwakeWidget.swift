import SwiftUI

/// Lit while something is keeping the Mac awake.
struct StayAwakeWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    var config: ConfigData { configProvider.config }

    /// Draw the icon dimmed when nothing is holding the machine awake, rather
    /// than hiding it.
    var alwaysShow: Bool { config["always-show"]?.boolValue ?? false }

    @StateObject private var manager = StayAwakeManager()

    var body: some View {
        Group {
            if manager.isActive || alwaysShow {
                Image(systemName: manager.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .barGlyphBox()
                    .opacity(manager.isActive ? 1 : 0.35)
                    .help(helpText)
            }
        }
        .frame(maxHeight: .infinity)
        .animation(.smooth(duration: 0.2), value: manager.isActive)
    }

    private var helpText: String {
        guard manager.isActive else { return "Sleep is not being prevented" }
        return "Keeping this Mac awake: " + manager.holders.joined(separator: ", ")
    }
}
