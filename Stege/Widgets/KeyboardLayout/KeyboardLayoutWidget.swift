import SwiftUI

/// The current input source, as the short code macOS shows in its own menu bar.
struct KeyboardLayoutWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    var config: ConfigData { configProvider.config }

    /// Show the full name, "Greek", rather than the code, "EL".
    var showFullName: Bool { config["show-full-name"]?.boolValue ?? false }

    @StateObject private var manager = KeyboardLayoutManager()

    var body: some View {
        Text(showFullName ? manager.name : manager.abbreviation)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 4)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .background(.black.opacity(0.001))
            .onTapGesture {
                // Opens the pane where input sources are managed, since
                // switching them belongs to the system, not to the bar.
                NSWorkspace.shared.open(
                    URL(
                        string:
                            "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"
                    )!)
            }
            .help(manager.name)
    }
}
