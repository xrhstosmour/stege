import SwiftUI

/// Battery detail: charge, time estimate, health, cycles, and the power mode.
///
/// Power mode is opened in System Settings rather than switched here. Changing
/// it requires root, and a menu bar app is not worth a standing privileged
/// helper, which was the same conclusion reached for the earlier `SketchyBar`
/// version of this bar.
struct BatteryPopup: View {
    @ObservedObject var manager: BatteryManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("\(manager.batteryLevel)%")
                    .font(.system(size: 18, weight: .semibold))
                    .monospacedDigit()
                if manager.isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.green)
                } else if manager.isPluggedIn {
                    Image(systemName: "powerplug.portrait.fill")
                        .font(.system(size: 12))
                }
                Spacer(minLength: 12)
            }

            if let estimate = estimateText {
                row("Time remaining", estimate)
            } else {
                row("Time remaining", manager.isPluggedIn ? "On power" : "Calculating…")
            }

            if let health = manager.healthFraction {
                row("Health", "\(Int((health * 100).rounded()))%")
            }
            if let cycles = manager.cycleCount {
                row("Cycles", "\(cycles)")
            }

            Divider()

            HStack(spacing: 8) {
                Image(
                    systemName: manager.isLowPowerMode
                        ? "leaf.fill" : "leaf"
                )
                .font(.system(size: 11))
                .foregroundStyle(manager.isLowPowerMode ? .green : .primary)
                Text(
                    manager.isLowPowerMode
                        ? "Low Power Mode on" : "Low Power Mode off"
                )
                .font(.system(size: 12))
                Spacer(minLength: 12)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .opacity(0.5)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                NSWorkspace.shared.open(
                    URL(
                        string:
                            "x-apple.systempreferences:com.apple.Battery-Settings.extension"
                    )!)
            }
        }
        .padding(14)
        .frame(width: 240, alignment: .leading)
    }

    /// Rendered as hours and minutes, since a bare minute count past an hour is
    /// harder to read at a glance.
    private var estimateText: String? {
        guard let minutes = manager.minutesRemaining, minutes > 0 else {
            return nil
        }
        let hours = minutes / 60
        let rest = minutes % 60
        let duration = hours > 0 ? "\(hours)h \(rest)m" : "\(rest)m"
        return manager.isCharging ? "\(duration) to full" : duration
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(label).font(.system(size: 12)).opacity(0.7)
            Spacer(minLength: 12)
            Text(value).font(.system(size: 12)).monospacedDigit()
        }
    }
}
