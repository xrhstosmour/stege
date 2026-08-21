import SwiftUI

/// A chevron that hides Stege so the real macOS menu bar, and every third-party
/// status item on it, becomes reachable. The bar returns as soon as the pointer
/// leaves the menu bar strip.
struct RevealWidget: View {
    // Not observed: the widget draws the same chevron either way, and while
    // the bar is hidden there is nothing on screen to update.
    private let visibility = BarVisibility.shared

    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 6)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .background(.black.opacity(0.001))
            .onTapGesture { visibility.hide() }
            .help("Reveal the system menu bar")
    }
}
