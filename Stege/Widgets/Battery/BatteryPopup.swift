import SwiftUI

/// Battery detail: charge, time estimate, health, cycles, and the power mode.
struct BatteryPopup: View {
    @ObservedObject var manager: BatteryManager
    /// The same two numbers the bar glyph colours itself by. They used to be a
    /// hardcoded 20 here, so setting either one made the popup disagree with
    /// the mark that opened it.
    let warningLevel: Int
    let criticalLevel: Int

    var body: some View {
        VStack(alignment: .leading, spacing: PopupStyle.spacing) {
            VStack(alignment: .leading, spacing: PopupStyle.rowSpacing) {
                // The charge is a reading like the three under it rather than
                // a heading over them. It used to open the popup as a large
                // number next to a symbol, which is the same charge the glyph
                // that was just clicked is already drawing.
                detail("Charge", chargeText)
                if let estimate = estimateText {
                    detail("Time remaining", estimate)
                } else {
                    detail(
                        "Time remaining",
                        manager.isPluggedIn ? "On power" : "Calculating…")
                }
                if let health = manager.healthFraction {
                    detail("Health", "\(Int((health * 100).rounded()))%")
                }
                if let cycles = manager.cycleCount {
                    detail("Cycles", "\(cycles)")
                }
            }

            PopupSeparator()

            VStack(alignment: .leading, spacing: PopupStyle.rowSpacing) {
                PopupSettingsRow(title: "Battery Settings") {
                    openSettings(
                        "x-apple.systempreferences:com.apple.Battery-Settings.extension"
                    )
                }
            }
        }
        .popupContainer()
    }

    /// The charge, and what is happening to it. Charging and merely plugged
    /// in are different states and the glyph in the bar draws them
    /// differently, so the reading says which.
    private var chargeText: String {
        let charge = "\(manager.batteryLevel)%"
        if manager.isCharging { return "\(charge), charging" }
        if manager.isPluggedIn { return "\(charge), plugged in" }
        return charge
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

    private func detail(_ label: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: PopupStyle.captionSize)).opacity(0.6)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: PopupStyle.captionSize))
                .monospacedDigit()
                .opacity(0.85)
        }
        .popupStaticRow()
    }
}
