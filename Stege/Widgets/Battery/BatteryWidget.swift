import SwiftUI

struct BatteryWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    var config: ConfigData { configProvider.config }
    var showPercentage: Bool { config["show-percentage"]?.boolValue ?? true }
    var warningLevel: Int { config["warning-level"]?.intValue ?? 20 }
    var criticalLevel: Int { config["critical-level"]?.intValue ?? 10 }

    /// How the charge is drawn.
    ///
    /// `inside` is the default: the battery outline with the level filled in
    /// behind the number, which sits in the body of the battery. `plain` puts
    /// the outline and the number side by side, which is what macOS itself
    /// does. `bar` is accepted as the old name for `inside`.
    ///
    /// Neither of the first two is the filled white pill this started as. The
    /// outline is drawn like every other glyph in the bar and the level behind
    /// the number is dimmed, so the battery stops being the brightest object on
    /// screen while still being the only one that carries a number.
    enum Style: String {
        case inside
        case plain
        case bar
    }

    var style: Style {
        Style(rawValue: config["style"]?.stringValue ?? "inside") ?? .inside
    }

    @StateObject private var batteryManager = BatteryManager()
    private var level: Int { batteryManager.batteryLevel }
    private var isCharging: Bool { batteryManager.isCharging }
    private var isPluggedIn: Bool { batteryManager.isPluggedIn }

    @State private var rect: CGRect = CGRect()

    var body: some View {
        Group {
            if style == .plain { plainBody } else { insideBody }
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear { rect = geometry.frame(in: .global) }
                    .onChange(of: geometry.frame(in: .global)) { _, new in
                        rect = new
                    }
            }
        )
        .experimentalConfiguration(cornerRadius: 15)
        .frame(maxHeight: .infinity)
        .background(.black.opacity(0.001))
        .onTapGesture {
            MenuBarPopup.show(rect: rect, id: "battery") {
                BatteryPopup(manager: batteryManager)
            }
        }
        .help(tooltip)
    }

    /// The charge as a glyph, and the number as text next to it.
    private var plainBody: some View {
        HStack(spacing: 3) {
            Image(systemName: symbolName)
                .barGlyph()
                .foregroundStyle(symbolTint)
            if showPercentage {
                Text("\(level)%")
                    .font(BarStyle.labelFont)
                    .monospacedDigit()
                    .foregroundStyle(symbolTint)
            }
        }
        .animation(.smooth(duration: 0.2), value: level)
        .animation(.smooth(duration: 0.2), value: isCharging)
    }

    /// The five steps SF Symbols draws, picked so the glyph empties at roughly
    /// the rate the battery does. Charging and plugged in have their own marks,
    /// the way macOS shows them.
    private var symbolName: String {
        if isCharging { return "battery.100.bolt" }
        switch level {
        case ...5: return "battery.0"
        case ...30: return "battery.25"
        case ...60: return "battery.50"
        case ...85: return "battery.75"
        default: return "battery.100"
        }
    }

    /// Colour says something is wrong and nothing else. A battery that is
    /// simply not full is drawn like every other glyph in the bar.
    private var symbolTint: Color {
        if isCharging { return .green }
        if level <= criticalLevel { return .red }
        if level <= warningLevel { return .yellow }
        return .foregroundOutside
    }

    /// The outline, the level filled in behind it, and the number in the body.
    private var insideBody: some View {
        ZStack {
            ZStack(alignment: .leading) {
                BatteryBodyView(mask: false)
                    .opacity(showPercentage ? 0.3 : 0.4)
                BatteryBodyView(mask: true)
                    .clipShape(
                        Rectangle().path(
                            in: CGRect(
                                x: showPercentage ? 0 : 2,
                                y: 0,
                                width: 30 * Int(level)
                                    / (showPercentage ? 110 : 130),
                                height: .bitWidth
                            )
                        )
                    )
                    .foregroundStyle(batteryColor)
                BatteryText(
                    level: level, isCharging: isCharging,
                    isPluggedIn: isPluggedIn
                )
                .foregroundStyle(batteryTextColor)
            }
            .frame(width: 30, height: 10)
        }
    }

    /// The charge is already on the icon, so the useful part on hover is how
    /// long it lasts, which is the one thing the bar has no room for.
    private var tooltip: String {
        var parts = ["\(level)%"]
        if isCharging {
            parts.append("charging")
        } else if isPluggedIn {
            parts.append("plugged in")
        }
        if let minutes = batteryManager.minutesRemaining, minutes > 0 {
            let hours = minutes / 60
            let rest = minutes % 60
            let time = hours > 0 ? "\(hours)h \(rest)m" : "\(rest)m"
            parts.append(isCharging ? "\(time) until full" : "\(time) left")
        }
        if batteryManager.isLowPowerMode {
            parts.append("Low Power Mode")
        }
        return parts.joined(separator: ", ")
    }

    /// The number reads on the fill behind it in every state, so it is one
    /// colour. It used to flip to black once the level dropped past the
    /// warning, which meant the one moment the number mattered most was the one
    /// moment it was drawn in the darkest colour available.
    private var batteryTextColor: Color {
        .foregroundOutside
    }

    /// The level behind the number, dimmed so the battery is not the brightest
    /// thing in the bar. Full brightness is kept for the states that are worth
    /// interrupting for.
    private var batteryColor: Color {
        if isCharging { return .green }
        if level <= criticalLevel { return .red }
        if level <= warningLevel { return .yellow }
        return Color.foregroundOutside.opacity(0.35)
    }
}

private struct BatteryText: View {
    @EnvironmentObject var configProvider: ConfigProvider
    var config: ConfigData { configProvider.config }
    var showPercentage: Bool { config["show-percentage"]?.boolValue ?? true }

    let level: Int
    let isCharging: Bool
    let isPluggedIn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: -1) {
            if showPercentage {
                Text("\(level)")
                    .font(.system(size: 12))
                    .transition(.blurReplace)
            }

            if isCharging && level != 100 {
                Image(systemName: "bolt.fill")
                    .font(.system(size: showPercentage ? 8 : 10))
            }

            if !isCharging && isPluggedIn && level != 100 {
                Image(systemName: "powerplug.portrait.fill")
                    .font(.system(size: 8))
                    .padding(.leading, 1)
            }
        }
        .foregroundStyle(
            showPercentage ? .foregroundOutsideInvert : .foregroundOutside
        )
        .fontWeight(.semibold)
        .transition(.blurReplace)
        .animation(.smooth, value: isCharging)
        .frame(width: 26, height: 15)
    }
}

private struct BatteryBodyView: View {
    let mask: Bool

    @EnvironmentObject var configProvider: ConfigProvider
    var config: ConfigData { configProvider.config }
    var showPercentage: Bool { config["show-percentage"]?.boolValue ?? true }

    var body: some View {
        ZStack {
            if showPercentage || !mask {
                Image(systemName: "battery.0")
                    .resizable()
                    .scaledToFit()
            }
            if showPercentage || mask {
                Rectangle()
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .padding(.horizontal, showPercentage ? 3 : 4.4)
                    .padding(.vertical, showPercentage ? 2 : 3.5)
                    .offset(
                        x: showPercentage ? -2 : -1.77,
                        y: showPercentage ? 0 : 0.2)
            }
        }
        .compositingGroup()
    }
}

struct BatteryWidget_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            BatteryWidget()
        }.frame(width: 200, height: 100)
            .background(.yellow)
            .environmentObject(ConfigProvider(config: [:]))
    }
}
