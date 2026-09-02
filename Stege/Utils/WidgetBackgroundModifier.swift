import SwiftUI

private struct WidgetBackgroundModifier: ViewModifier {
    @ObservedObject var configManager = ConfigManager.shared
    var foregroundHeight: CGFloat { configManager.config.bar.foreground.resolveHeight() }
    
    let horizontalPadding: CGFloat
    let cornerRadius: CGFloat
    
    /// `@ViewBuilder` rather than a bare `Group`. Without it the conditional
    /// inside is ambiguous enough that the compiler tries `TableColumn`, which
    /// fails, and then every widget chaining off this modifier is left
    /// unchecked because its type is already an error. That hid a genuinely
    /// broken view chain once.
    @ViewBuilder
    func body(content: Content) -> some View {
        if !configManager.config.bar.foreground.widgetsBackground.displayed {
            content
                .scaleEffect(
                    foregroundHeight < 25 ? 0.9 : 1, anchor: .leading)
        } else {
            content
                .frame(height: foregroundHeight < 45 ? 30 : 38)
                .padding(.horizontal, foregroundHeight < 45 && horizontalPadding != 15 ? 0 :
                                foregroundHeight < 30 ? 0 : horizontalPadding
                    )
                .background(configManager.config.bar.foreground.widgetsBackground.blur)
                .cornerRadius(foregroundHeight < 30 ? 0 : cornerRadius)
                .overlay(
                    foregroundHeight < 30 ? nil :
                        Capsule().stroke(Color("NoActive"), lineWidth: 1)
                )
                .scaleEffect(
                    foregroundHeight < 25 ? 0.9 : 1, anchor: .leading)
        }
    }
}

extension View {
    func widgetBackground(
        horizontalPadding: CGFloat = 15,
        cornerRadius: CGFloat
    ) -> some View {
        self.modifier(WidgetBackgroundModifier(
            horizontalPadding: horizontalPadding,
            cornerRadius: cornerRadius
        ))
    }
}
