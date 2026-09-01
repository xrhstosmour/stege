import SwiftUI

/// Brightness in the bar, with Night Shift and True Tone in the popup.
///
/// One mark, no number by default, in keeping with the rest of the bar.
/// Scrolling changes the brightness without opening anything, the way the
/// speaker already works.
struct DisplayWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    var config: ConfigData { configProvider.config }

    /// Off by default. The glyph already fills with the level.
    var showPercentage: Bool { config["show-percentage"]?.boolValue ?? false }

    @StateObject private var manager = DisplayManager()
    @State private var rect: CGRect = .zero

    private var level: Float { manager.displays.first?.brightness ?? 0 }

    var body: some View {
        HStack(spacing: 4) {
            // Fills by value rather than swapping symbols, so the mark keeps
            // its width at every level.
            Image(systemName: "sun.max.fill", variableValue: Double(level))
                .barGlyphBox()

            if showPercentage {
                Text("\(Int((level * 100).rounded()))%")
                    .font(BarStyle.labelFont)
                    .monospacedDigit()
            }
        }
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear { rect = geometry.frame(in: .global) }
                    .onChange(of: geometry.frame(in: .global)) { _, new in
                        rect = new
                    }
            }
        )
        .overlay(
            PointerInput(
                onClick: { showPopup() },
                onScroll: { manager.nudgeBrightness(by: Float($0) * 0.05) },
                onRightClick: {})
        )
        .barFocusable { showPopup() }
        .help(tooltip)
    }

    private func showPopup() {
        MenuBarPopup.show(rect: rect, id: "display") {
            DisplayPopup(manager: manager)
        }
    }

    private var tooltip: String {
        guard manager.displays.first?.brightness != nil else {
            return "Display"
        }
        return "Brightness \(Int((level * 100).rounded()))%"
    }
}

struct DisplayPopup: View {
    @ObservedObject var manager: DisplayManager

    var body: some View {
        VStack(alignment: .leading, spacing: PopupStyle.spacing) {
            PopupHeader(symbol: "sun.max.fill", title: "Display")

            VStack(alignment: .leading, spacing: PopupStyle.rowSpacing) {
                ForEach(manager.displays) { display in
                    brightnessRow(display)
                }
                if manager.displays.allSatisfy({ $0.brightness == nil }) {
                    Text("No display reports a settable brightness")
                        .font(.system(size: PopupStyle.bodySize))
                        .opacity(0.6)
                        .fixedSize(horizontal: false, vertical: true)
                        .popupStaticRow()
                }
            }

            PopupSeparator()

            VStack(alignment: .leading, spacing: PopupStyle.rowSpacing) {
                HStack(spacing: 10) {
                    Image(systemName: "moon.circle.fill")
                        .font(.system(size: PopupStyle.bodySize))
                        .foregroundStyle(
                            manager.isNightShiftOn ? Color.orange : .secondary
                        )
                        .frame(width: PopupStyle.iconColumn)
                    Text("Night Shift")
                        .font(.system(size: PopupStyle.bodySize))
                    Spacer(minLength: 8)
                    PopupSwitch(isOn: manager.isNightShiftOn) {
                        manager.setNightShift(!manager.isNightShiftOn)
                    }
                }
                .popupStaticRow()

                if manager.isNightShiftOn {
                    HStack(spacing: 10) {
                        Spacer().frame(width: PopupStyle.iconColumn)
                        Slider(
                            value: Binding(
                                get: { Double(manager.nightShiftStrength) },
                                set: {
                                    manager.setNightShiftStrength(Float($0))
                                }), in: 0...1)
                        Text("Warm")
                            .font(.system(size: PopupStyle.captionSize))
                            .opacity(0.6)
                    }
                    .popupStaticRow()
                }

                if manager.isTrueToneAvailable {
                    HStack(spacing: 10) {
                        Image(systemName: "sun.max.circle.fill")
                            .font(.system(size: PopupStyle.bodySize))
                            .foregroundStyle(
                                manager.isTrueToneOn ? Color.blue : .secondary
                            )
                            .frame(width: PopupStyle.iconColumn)
                        Text("True Tone")
                            .font(.system(size: PopupStyle.bodySize))
                        Spacer(minLength: 8)
                        PopupSwitch(isOn: manager.isTrueToneOn) {
                            manager.setTrueTone(!manager.isTrueToneOn)
                        }
                    }
                    .popupStaticRow()
                }
            }

            if let failure = manager.failure {
                Text(failure)
                    .font(.system(size: PopupStyle.captionSize))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .popupStaticRow()
            }

            PopupSeparator()

            PopupSettingsRow(title: "Display Settings") {
                openSettings(
                    "x-apple.systempreferences:com.apple.Displays-Settings.extension"
                )
            }
        }
        .popupContainer()
        .onAppear { manager.startPolling() }
        .onDisappear { manager.stopPolling() }
    }

    /// One row per display. A monitor whose backlight is not ours to set is
    /// still listed, so the popup says which displays exist rather than
    /// silently dropping them.
    @ViewBuilder
    private func brightnessRow(_ display: DisplayInfo) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if manager.displays.count > 1 {
                Text(display.name)
                    .font(.system(size: PopupStyle.captionSize))
                    .opacity(0.6)
                    .lineLimit(1)
            }
            HStack(spacing: 10) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: PopupStyle.bodySize))
                    .frame(width: PopupStyle.iconColumn)
                if let brightness = display.brightness {
                    Slider(
                        value: Binding(
                            get: { Double(brightness) },
                            set: {
                                manager.setBrightness(Float($0), on: display)
                            }), in: 0...1)
                    Text("\(Int((brightness * 100).rounded()))%")
                        .font(.system(size: PopupStyle.captionSize))
                        .monospacedDigit()
                        .opacity(0.6)
                        .frame(width: 40, alignment: .trailing)
                } else {
                    Text("Not adjustable from here")
                        .font(.system(size: PopupStyle.bodySize))
                        .opacity(0.6)
                    Spacer(minLength: 8)
                }
            }
        }
        .popupStaticRow()
    }
}
