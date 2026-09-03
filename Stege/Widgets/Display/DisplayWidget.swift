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

    @ObservedObject private var manager = DisplayManager.shared
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

    /// What is actually lit, not just how many displays there are.
    ///
    /// The laptop panel on its own is a laptop; anything else is one screen or
    /// several. With the lid shut the built-in panel is not among the active
    /// displays at all, so a machine driving one external monitor from a closed
    /// laptop correctly draws a single screen rather than two.
    ///
    /// Laptop-plus-external is drawn as two screens rather than as a laptop
    /// beside a monitor, because SF Symbols has no such mark. Checked:
    /// `laptopcomputer.and.display`, `macbook.and.display`,
    /// `display.and.laptopcomputer` and `laptopcomputer.and.monitor` are all
    /// absent. The popup names each display, which is where that distinction
    /// actually matters.
    private var symbol: String {
        if manager.isMirrored { return "rectangle.on.rectangle" }
        let displays = manager.displays
        if displays.count == 1, displays[0].isBuiltIn { return "laptopcomputer" }
        return displays.count > 1 ? "display.2" : "display"
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
        if manager.isLidClosed { parts.append("lid closed") }
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

    /// Which displays have their resolution list open.
    ///
    /// Folded away by default. Two monitors put two dozen resolution rows in
    /// the popup and pushed everything under them, Screen Mirroring and Display
    /// Settings included, past the bottom of the screen. The header still says
    /// what each display is set to, so folding costs no information, only the
    /// alternatives.
    @State private var expanded: Set<CGDirectDisplayID> = []

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

            // macOS keeps the receiver list behind an Apple-only entitlement:
            // every system output context, `sharedSystemScreenContext` among
            // them, answers an ordinary application with nil, so there is
            // nothing to draw a list from. Control Center's own picker is where
            // those receivers are, and it opens to a real press.
            // One press when Screen Mirroring is set to always show in the
            // menu bar, two through Control Center when it is not.
            PopupSettingsRow(
                title: "Screen Mirroring", symbol: "airplayvideo"
            ) {
                let route = MenuExtra.route(
                    to: .screenMirroring,
                    tile: "controlcenter-screen-mirroring")
                MenuExtra.open(route.extra, path: route.path)
            }

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

            let isOpen = expanded.contains(display.id)
            VStack(alignment: .leading, spacing: PopupStyle.rowSpacing) {
                resolutionHeader(for: display, isOpen: isOpen)

                if isOpen {
                    ForEach(modes) { mode in
                        resolutionRow(mode, on: display)
                    }
                }
            }
            .animation(.smooth(duration: 0.15), value: isOpen)
        }
    }

    /// The row that folds the list.
    private func resolutionHeader(for display: DisplayInfo, isOpen: Bool)
        -> some View
    {
        HStack(spacing: 6) {
            Text(manager.displays.count > 1 ? display.name : "Resolution")
                .font(
                    .system(size: PopupStyle.captionSize, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 8)
            // Nothing but the chevron. The resolution in use is marked inside
            // the list, where the tick is, rather than repeated out here.
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .rotationEffect(.degrees(isOpen ? 90 : 0))
                .opacity(0.5)
        }
        .popupRow {
            if isOpen {
                expanded.remove(display.id)
            } else {
                expanded.insert(display.id)
            }
        }
    }

    private func resolutionRow(_ mode: DisplayMode, on display: DisplayInfo)
        -> some View
    {
        HStack(spacing: 10) {
            // The accent colour, the way macOS marks the chosen item in its own
            // lists. A checkmark that is the same colour as everything else
            // reads as another row rather than as the answer.
            PopupSelectionMark(isSelected: mode.isCurrent)
            Text(mode.label)
                .font(.system(size: PopupStyle.bodySize))
                .monospacedDigit()
                .fontWeight(mode.isCurrent ? .semibold : .regular)
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
