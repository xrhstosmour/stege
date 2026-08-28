import SwiftUI

/// CPU and memory usage, optionally with network throughput.
struct SystemMonitorWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    var config: ConfigData { configProvider.config }

    var showNetwork: Bool { config["show-network"]?.boolValue ?? false }
    var warningLevel: Double {
        Double(config["warning-level"]?.intValue ?? 80) / 100
    }

    @StateObject private var manager = SystemMonitorManager()

    var body: some View {
        HStack(spacing: 8) {
            reading(symbol: "cpu", value: manager.cpuUsage)
            reading(symbol: "memorychip", value: manager.memoryUsage)

            if showNetwork {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 8, weight: .bold))
                    Text(Self.rate(manager.bytesReceivedPerSecond))
                    Image(systemName: "arrow.up")
                        .font(.system(size: 8, weight: .bold))
                    Text(Self.rate(manager.bytesSentPerSecond))
                }
                .font(.system(size: 11))
                // Monospaced digits, so the bar does not jitter as the numbers
                // change width several times a second.
                .monospacedDigit()
                .opacity(0.8)
            }
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func reading(symbol: String, value: Double) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).barGlyph()
            Text("\(Int((value * 100).rounded()))%")
                .font(.system(size: 12))
                .monospacedDigit()
        }
        .foregroundStyle(value >= warningLevel ? Color.orange : Color.primary)
    }

    /// Compact throughput, the way macOS itself abbreviates it.
    private static func rate(_ bytesPerSecond: Double) -> String {
        let units = ["B", "K", "M", "G"]
        var value = max(0, bytesPerSecond)
        var index = 0
        while value >= 1000, index < units.count - 1 {
            value /= 1000
            index += 1
        }
        return value >= 100 || index == 0
            ? "\(Int(value))\(units[index])"
            : String(format: "%.1f%@", value, units[index])
    }
}
