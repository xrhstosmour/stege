import SwiftUI

/// The screen: brightness, resolution, mirroring, Night Shift and True Tone.
///
/// The mark is a display rather than a sun. It was a sun, filled by the
/// brightness level, which said one true thing and hid the rest: this popup is
/// where the resolution and the mirror switch live, and neither has anything
/// to do with brightness. Scrolling still changes the brightness without
/// opening anything, the way the speaker already works.
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
            Image(systemName: symbol)
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
        .help(tooltip)
    }

    /// Two displays are two rectangles, which is what macOS puts on its own
    /// screen mirroring item, and mirroring gets the symbol that says so.
    private var symbol: String {
        if manager.isMirrored { return "rectangle.on.rectangle" }
        return manager.displays.count > 1 ? "display.2" : "display"
    }

    private func showPopup() {
        MenuBarPopup.show(rect: rect, id: "display") {
            DisplayPopup(manager: manager)
        }
    }

    private var tooltip: String {
        var parts: [String] = []
        if manager.displays.first?.brightness != nil {
            parts.append("Brightness \(Int((level * 100).rounded()))%")
        }
        if manager.isMirrored { parts.append("Mirroring") }
        if let first = manager.displays.first, first.resolution.width > 0 {
            parts.append(
                "\(Int(first.resolution.width)) × "
                    + "\(Int(first.resolution.height))")
        }
        return parts.isEmpty ? "Display" : parts.joined(separator: ", ")
    }
}

struct DisplayPopup: View {
    @ObservedObject var manager: DisplayManager

    var body: some View {
        VStack(alignment: .leading, spacing: PopupStyle.spacing) {
            VStack(alignment: .leading, spacing: PopupStyle.rowSpacing) {
                if manager.isLidClosed {
                    HStack(spacing: 10) {
                        Image(systemName: "macbook.slash")
                            .font(.system(size: PopupStyle.bodySize))
                            .foregroundStyle(.secondary)
                            .frame(width: PopupStyle.iconColumn)
                        Text("Lid closed")
                            .font(.system(size: PopupStyle.bodySize))
                        Spacer(minLength: 8)
                        Text("built-in display off")
                            .font(.system(size: PopupStyle.captionSize))
                            .opacity(0.5)
                    }
                    .popupStaticRow()
                }
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

            ForEach(manager.displays) { display in
                resolutions(for: display)
            }

            PopupSeparator()

            // Where AirPlay lives too. macOS keeps the receiver list behind an
            // Apple-only entitlement: every system output context,
            // `sharedSystemScreenContext` among them, answers an ordinary
            // application with nil, so there is nothing to draw a list from,
            // and this pane is where those receivers are offered.
            PopupSettingsRow(title: "Display Settings") {
                openSettings(
                    "x-apple.systempreferences:com.apple.Displays-Settings.extension"
                )
            }
        }
        .popupContainer()
        .onAppear {
            manager.startPolling()
            manager.readExternalBrightness()
        }
        .onDisappear { manager.stopPolling() }
    }

    /// The resolutions a display will take, as System Settings lists them.
    ///
    /// Applied for this login session only. Writing a display mode
    /// permanently is System Settings' job, and a menu bar should not leave a
    /// display in a state that survives a restart without being asked to.
    @ViewBuilder
    private func resolutions(for display: DisplayInfo) -> some View {
        let modes = manager.modes(for: display)
        if modes.count > 1 {
            PopupSeparator()

            VStack(alignment: .leading, spacing: PopupStyle.rowSpacing) {
                PopupSectionTitle(
                    title: manager.displays.count > 1
                        ? display.name : "Resolution"
                ) {
                    if manager.displays.count > 1 {
                        Text("Resolution")
                            .font(
                                .system(
                                    size: PopupStyle.captionSize,
                                    weight: .semibold)
                            )
                            .opacity(0.5)
                    }
                }
                .popupStaticRow()

                ForEach(modes) { mode in
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark")
                            .font(.system(size: PopupStyle.captionSize,
                                          weight: .semibold))
                            .opacity(mode.isCurrent ? 1 : 0)
                            .frame(width: PopupStyle.iconColumn)
                        Text(mode.label)
                            .font(.system(size: PopupStyle.bodySize))
                            .monospacedDigit()
                        Spacer(minLength: 8)
                        if let rate = mode.refreshLabel {
                            Text(rate)
                                .font(.system(size: PopupStyle.captionSize))
                                .monospacedDigit()
                                .opacity(0.5)
                        }
                        if mode.isRetina {
                            Text("Retina")
                                .font(.system(size: PopupStyle.captionSize))
                                .opacity(0.5)
                        }
                    }
                    .popupRow {
                        guard !mode.isCurrent else { return }
                        manager.setMode(mode, on: display)
                    }
                }
            }
        }
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
