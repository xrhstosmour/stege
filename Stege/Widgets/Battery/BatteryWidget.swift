import SwiftUI

struct BatteryWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    var config: ConfigData { configProvider.config }
    var showPercentage: Bool { config["show-percentage"]?.boolValue ?? true }
    var warningLevel: Int { config["warning-level"]?.intValue ?? 30 }
    var criticalLevel: Int { config["critical-level"]?.intValue ?? 10 }

    /// How the charge is drawn.
    ///
    /// `inside` is the default: the battery outline with the level filled in
    /// behind the number, which sits in the body of the battery. `plain` puts
    /// the outline and the number side by side, which is what macOS itself
    /// does.
    ///
    /// Neither is the filled white pill this started as. The outline is drawn
    /// like every other glyph in the bar, and the number sits inside it rather
    /// than beside it.
    enum Style: String {
        case inside
        case plain
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
                BatteryPopup(
                    manager: batteryManager,
                    warningLevel: warningLevel,
                    criticalLevel: criticalLevel)
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
                // The bolt rides on the level rather than replacing it. The
                // symbol used to be `battery.100.bolt` whenever charging, so a
                // battery at a tenth on the charger drew as a full one.
                .overlay(alignment: .center) {
                    if isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: BarStyle.badgeSize))
                            .foregroundStyle(Color("Foreground Outside Invert"))
                    }
                }
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
    /// the rate the battery does. Charging is a bolt drawn over this rather
    /// than a symbol of its own, so the level still reads while on the charger.
    private var symbolName: String {
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
        if level <= warningLevel { return .orange }
        return Color("Foreground Outside")
    }

    /// The outline, the level filled in behind it, and the number in the body.
    ///
    /// The number is drawn once, in the bar's own foreground, over a fill kept
    /// dark enough to read it against. It used to be drawn twice, each copy
    /// clipped to one side of the fill edge, dark on the filled part and light
    /// on the empty part, because the fill was full-strength white. That meant
    /// a battery at anything but nearly full or nearly empty put the edge
    /// through the middle of the digits and drew half of each one in each
    /// colour, which is the least legible place the edge could be.
    private var insideBody: some View {
        ZStack(alignment: .leading) {
            BatteryBodyView(mask: false)
                .opacity(showPercentage ? 0.3 : 0.4)
            BatteryBodyView(mask: true)
                .clipShape(Rectangle().path(in: fillRect))
                .foregroundStyle(batteryColor)

            batteryText.foregroundStyle(Color("Foreground Outside"))
        }
        .frame(width: 30, height: 10)
    }

    private var batteryText: some View {
        BatteryText(
            level: level, isCharging: isCharging, isPluggedIn: isPluggedIn)
    }

    /// How much of the body the level covers. Out of 100, not the 110 it used
    /// to be divided by, which left a full battery drawing 27 of its 30 points
    /// and never looking full.
    private var fillRect: CGRect {
        CGRect(
            x: showPercentage ? 0 : 2,
            y: 0,
            width: CGFloat(30 * level / 100),
            height: 40)
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

    /// The level behind the number.
    ///
    /// Every one of these is dark enough that white digits read on top of it,
    /// which is the constraint the whole thing is drawn under: the number sits
    /// inside the battery, so the fill is a background before it is anything
    /// else. Yellow is the one this rules out, since white on yellow is barely
    /// two to one, and it is orange here for that reason and no other.
    ///
    /// It is still bright enough against the empty part of the body, which is
    /// the bar's black, that the level reads at a glance.
    private var batteryColor: Color {
        if isCharging { return .green.opacity(0.7) }
        if level <= criticalLevel { return .red }
        if level <= warningLevel { return .orange.opacity(0.8) }
        return Color("Foreground Outside").opacity(0.5)
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
                // Ten, not twelve. At twelve the digits stood taller than the
                // ten point body they sit in, so they crossed the outline top
                // and bottom and the number read as printed over the battery
                // rather than inside it.
                Text("\(level)")
                    .font(.system(size: 10))
                    .transition(.blurReplace)
            }

            // Kept at 100 too. A machine on the charger is charging whether
            // or not it has finished, and dropping the mark at exactly full
            // made the one unambiguous state the only one with nothing to say.
            if isCharging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: showPercentage ? 7 : 10))
            }

            if !isCharging && isPluggedIn {
                Image(systemName: "powerplug.portrait.fill")
                    .font(.system(size: 7))
                    .padding(.leading, 1)
            }
        }
        .fontWeight(.semibold)
        .transition(.blurReplace)
        .animation(.smooth, value: isCharging)
        .frame(width: 26, height: 10)
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
