import SwiftUI

/// The current input source as a two-letter region code, with a popup for
/// switching to any other source that is enabled.
struct KeyboardLayoutWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    var config: ConfigData { configProvider.config }

    /// Show the full name, "Greek", rather than the code, "GR".
    var showFullName: Bool { config["show-full-name"]?.boolValue ?? false }

    @StateObject private var manager = KeyboardLayoutManager()
    @State private var rect: CGRect = .zero

    var body: some View {
        Text(showFullName ? manager.name : manager.abbreviation)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 4)
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
                MenuBarPopup.show(rect: rect, id: "keyboardlayout") {
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
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: "keyboard").font(.system(size: 11))
                Text("Input Sources")
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 4)

            ForEach(manager.sources) { source in
                row(source)
            }

            Divider().padding(.vertical, 4)

            settingsRow
        }
        .padding(10)
        .frame(width: 240, alignment: .leading)
    }

    private func row(_ source: KeyboardInputSource) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .opacity(source.id == manager.currentID ? 1 : 0)
                .frame(width: 10)
            Text(source.name).font(.system(size: 12)).lineLimit(1)
            Spacer(minLength: 8)
            Text(source.code)
                .font(.system(size: 11, weight: .medium))
                .opacity(0.6)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            manager.select(source)
            MenuBarPopup.hide()
        }
    }

    private var settingsRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "gearshape").font(.system(size: 11)).frame(width: 10)
            Text("Keyboard Settings").font(.system(size: 12))
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold)).opacity(0.5)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            MenuBarPopup.hide()
            // Adding and removing input sources belongs to the system, and this
            // popup only switches between the ones already enabled.
            NSWorkspace.shared.open(
                URL(
                    string:
                        "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"
                )!)
        }
    }
}
