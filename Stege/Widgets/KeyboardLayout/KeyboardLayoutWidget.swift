import SwiftUI

/// The current input source as a two-letter region code, with a popup for
/// switching to any other source that is enabled.
struct KeyboardLayoutWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    var config: ConfigData { configProvider.config }

    /// Show the full name, "Greek", rather than the code, "GR".
    var showFullName: Bool { config["show-full-name"]?.boolValue ?? false }

    @ObservedObject private var manager = KeyboardLayoutManager.shared
    @State private var rect: CGRect = .zero

    var body: some View {
        Text(showFullName ? manager.name : manager.abbreviation)
            .font(BarStyle.labelFont)
            // The code is always two characters, but the face is proportional,
            // so `EN` and `GR` still measure differently. The box was the
            // bar's glyph width, 20 points against about 15 of letterform, and
            // since the marks either side of it are laid out on their ink that
            // slack showed as the two widest gaps in the row. Two capitals at
            // this size differ by well under a point, which is less than the
            // five points the box was adding.
            .fixedSize()
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .background(.black.opacity(0.001))
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { rect = geometry.frame(in: .global) }
                        .onChange(of: geometry.frame(in: .global)) { _, new in
                            rect = new
                        }
                }
            )
            .onTapGesture {
                MenuBarPopup.show(rect: rect, id: "keyboardLayout") {
                    KeyboardLayoutPopup(manager: manager)
                }
            }
            .help(manager.name)
    }
}

/// Every enabled input source, with the current one ticked.
///
/// Switching is the system's own `TISSelectInputSource`, so anything watching
/// the input source, including this widget, hears about it the usual way.
struct KeyboardLayoutPopup: View {
    @ObservedObject var manager: KeyboardLayoutManager

    var body: some View {
        VStack(alignment: .leading, spacing: PopupStyle.spacing) {
            VStack(alignment: .leading, spacing: PopupStyle.rowSpacing) {
                ForEach(manager.sources) { source in
                    row(source)
                }
            }

            PopupSeparator()

            // Adding and removing input sources belongs to the system, and this
            // popup only switches between the ones already enabled.
            PopupSettingsRow(title: "Keyboard Settings") {
                openSettings(
                    "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"
                )
            }
        }
        .popupContainer()
    }

    private func row(_ source: KeyboardInputSource) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .semibold))
                .opacity(source.id == manager.currentID ? 1 : 0)
                .frame(width: PopupStyle.iconColumn)
            Text(source.name)
                .font(.system(size: PopupStyle.bodySize))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(source.code)
                .font(.system(size: PopupStyle.captionSize, weight: .medium))
                .opacity(0.6)
        }
        .popupRow {
            manager.select(source)
            MenuBarPopup.hide()
        }
    }
}
