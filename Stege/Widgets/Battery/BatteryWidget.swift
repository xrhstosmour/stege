import SwiftUI

struct BatteryWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    var config: ConfigData { configProvider.config }
    var showPercentage: Bool { config["show-percentage"]?.boolValue ?? true }
    var warningLevel: Int { config["warning-level"]?.intValue ?? 30 }
    var criticalLevel: Int { config["critical-level"]?.intValue ?? 10 }

    /// How the charge is drawn.
    ///
    /// `inside` is the default: the level filled in behind the number, which
    /// sits in the body of the battery. `plain` puts the number beside the
    /// battery instead, which is what macOS itself does, and lets the fill be
    /// drawn at full strength because nothing has to stay legible over it.
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
        .widgetBackground(cornerRadius: 15)
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

    /// The number beside the battery, which is where macOS puts it.
    private var plainBody: some View {
        HStack(spacing: 4) {
            if showPercentage {
                Text("\(level)%")
                    .font(BarStyle.labelFont)
                    .monospacedDigit()
            }
            BatteryBody(
                level: level, fill: fillColor, fillOpacity: 1,
                outline: Color("Foreground Outside")
            ) {
                chargingBolt
            }
        }
        .animation(.smooth(duration: 0.2), value: level)
        .animation(.smooth(duration: 0.2), value: isCharging)
    }

    /// The number in the body of the battery.
    private var insideBody: some View {
        BatteryBody(
            level: level, fill: fillColor, fillOpacity: fillOpacity,
            outline: Color("Foreground Outside")
        ) {
            if showPercentage {
                number
            } else {
                chargingBolt
            }
        }
        .animation(.smooth(duration: 0.2), value: level)
        .animation(.smooth(duration: 0.2), value: isCharging)
    }

    /// Drawn in the background colour, so it reads as knocked out of the fill
    /// rather than laid on top of it. This is the only mark inside the body
    /// when the number is off, which is what macOS does.
    @ViewBuilder
    private var chargingBolt: some View {
        if isCharging {
            Image(systemName: "bolt.fill")
                .font(.system(size: 9))
                .foregroundStyle(Color("Foreground Outside Invert"))
        }
    }

    private var number: some View {
        HStack(spacing: 0) {
            // Sized to the body it sits in, which grew with the rest of the
            // bar. Any larger and the digits cross the outline top and bottom
            // and read as printed over the battery rather than inside it.
            Text("\(level)")
                .font(.system(size: 10.5, weight: .semibold))
                .monospacedDigit()
                .transition(.blurReplace)
            // Kept at 100 too. A machine on the charger is charging whether or
            // not it has finished, and dropping the mark at exactly full made
            // the one unambiguous state the only one with nothing to say.
            if isCharging {
                Image(systemName: "bolt.fill").font(.system(size: 8))
            } else if isPluggedIn {
                Image(systemName: "powerplug.portrait.fill")
                    .font(.system(size: 8))
                    .padding(.leading, 1)
            }
        }
        .foregroundStyle(Color("Foreground Outside"))
    }

    /// Colour says something is wrong, or that the machine is on the charger,
    /// and nothing else. A battery that is simply not full is drawn in the
    /// bar's own foreground like every other mark in the row.
    private var fillColor: Color {
        if isCharging { return .green }
        if level <= criticalLevel { return .red }
        if level <= warningLevel { return .orange }
        return Color("Foreground Outside")
    }

    /// How solid the level is drawn.
    ///
    /// macOS fills its battery at full strength because it puts nothing on
    /// top. With the number in the body the fill is a background before it is
    /// a reading, and white digits have to stay legible over it at every
    /// level, so the plain white one is held well back. The three that mean
    /// something are not, because they are the ones worth noticing.
    private var fillOpacity: Double {
        guard showPercentage else { return 1 }
        if isCharging { return 0.75 }
        if level <= criticalLevel { return 1 }
        if level <= warningLevel { return 0.85 }
        return 0.35
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
}

/// The battery, drawn rather than assembled out of an SF Symbol.
///
/// It used to be `battery.0` with a `Rectangle` laid over it, the rectangle's
/// inset, corner radius and offset each tuned by eye against the symbol it had
/// to sit inside. They never lined up: the fill reached the outline on every
/// side, so at a glance the widget was a coloured lozenge and the outline it
/// was meant to sit in could not be seen at all.
///
/// macOS draws its own as an outline with the fill held well inside it, and a
/// terminal on the end, which at this size is most of what says battery rather
/// than pill. Drawing it from shapes is the only way to get that inset exact.
private struct BatteryBody<Overlay: View>: View {
    let level: Int
    let fill: Color
    let fillOpacity: Double
    let outline: Color
    @ViewBuilder var overlay: Overlay

    static var width: CGFloat { 30 }
    static var height: CGFloat { 13.5 }
    private static var inset: CGFloat { 1.75 }

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(outline.opacity(0.5), lineWidth: 1)

                RoundedRectangle(cornerRadius: 2.25, style: .continuous)
                    .fill(fill.opacity(fillOpacity))
                    .frame(
                        width: fillWidth,
                        height: Self.height - Self.inset * 2
                    )
                    .padding(.leading, Self.inset)

                // Centred on the body rather than on the body and terminal
                // together, so the number does not sit a point to the right of
                // the middle of the thing it is in.
                overlay
                    .frame(width: Self.width, height: Self.height)
            }
            .frame(width: Self.width, height: Self.height)

            UnevenRoundedRectangle(
                bottomTrailingRadius: 1.75, topTrailingRadius: 1.75,
                style: .continuous
            )
            .fill(outline.opacity(0.5))
            .frame(width: 1.75, height: 5)
        }
    }

    /// Never quite nothing. A battery that has just run out still has a
    /// battery's shape, and a fill of zero width reads as a drawing error.
    private var fillWidth: CGFloat {
        let inner = Self.width - Self.inset * 2
        return max(1.5, inner * CGFloat(min(100, max(0, level))) / 100)
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
