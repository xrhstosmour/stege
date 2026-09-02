import SwiftUI

/// CPU and memory usage, optionally with network throughput.
struct SystemMonitorWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    var config: ConfigData { configProvider.config }

    var showNetwork: Bool { config["show-network"]?.boolValue ?? false }
    var warningLevel: Double {
        Double(config["warning-level"]?.intValue ?? 80) / 100
    }

    @ObservedObject private var manager = SystemMonitorManager.shared
    @State private var rect: CGRect = .zero

    var body: some View {
        content
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { rect = geometry.frame(in: .global) }
                        .onChange(of: geometry.frame(in: .global)) { _, new in
                            rect = new
                        }
                }
            )
            .contentShape(Rectangle())
            .background(.black.opacity(0.001))
            .onTapGesture {
                manager.updateDisk()
                MenuBarPopup.show(rect: rect, id: "monitor") {
                    SystemMonitorPopup(manager: manager)
                }
            }
            .barFocusable {
                manager.updateDisk()
                MenuBarPopup.show(rect: rect, id: "monitor") {
                    SystemMonitorPopup(manager: manager)
                }
            }
    }

    private var content: some View {
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
            Image(systemName: symbol).barGlyphBox()
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


/// What the bar has no room for: the readings spelled out, and the disk, which
/// changes too slowly to be worth a permanent slot.
struct SystemMonitorPopup: View {
    @ObservedObject var manager: SystemMonitorManager

    var body: some View {
        VStack(alignment: .leading, spacing: PopupStyle.spacing) {
            VStack(alignment: .leading, spacing: PopupStyle.rowSpacing) {
                meter("Processor", symbol: "cpu", value: manager.cpuUsage)
                meter("Memory", symbol: "memorychip", value: manager.memoryUsage)
                if let free = manager.diskFree, let total = manager.diskTotal,
                    total > 0
                {
                    meter(
                        "Disk", symbol: "internaldrive",
                        value: Double(total - free) / Double(total),
                        detail: "\(Self.size(free)) free")
                }
            }

            PopupSeparator()

            VStack(alignment: .leading, spacing: PopupStyle.rowSpacing) {
                rateRow(
                    "Download", symbol: "arrow.down",
                    bytes: manager.bytesReceivedPerSecond)
                rateRow(
                    "Upload", symbol: "arrow.up",
                    bytes: manager.bytesSentPerSecond)
            }

            PopupSeparator()

            PopupSettingsRow(title: "Activity Monitor", symbol: "chart.bar") {
                MenuBarPopup.hide()
                NSWorkspace.shared.open(
                    URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
            }
        }
        .popupContainer()
        .onAppear { manager.updateDisk() }
    }

    /// A reading with a bar under it, so the number and the shape of it say the
    /// same thing.
    private func meter(
        _ title: String, symbol: String, value: Double, detail: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: PopupStyle.bodySize))
                    .frame(width: PopupStyle.iconColumn)
                Text(title)
                    .font(.system(size: PopupStyle.bodySize))
                Spacer(minLength: 8)
                Text(detail ?? "\(Int((value * 100).rounded()))%")
                    .font(.system(size: PopupStyle.captionSize))
                    .monospacedDigit()
                    .opacity(0.6)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.15))
                    Capsule()
                        .fill(value >= 0.9 ? Color.red : Color.accentColor)
                        .frame(
                            width: max(
                                2, geometry.size.width * min(1, max(0, value))))
                }
            }
            .frame(height: 3)
            .padding(.leading, PopupStyle.iconColumn + 10)
        }
        .popupStaticRow()
    }

    private func rateRow(_ title: String, symbol: String, bytes: Double)
        -> some View
    {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: PopupStyle.bodySize))
                .frame(width: PopupStyle.iconColumn)
            Text(title)
                .font(.system(size: PopupStyle.bodySize))
            Spacer(minLength: 8)
            Text(Self.size(Int64(max(0, bytes))) + "/s")
                .font(.system(size: PopupStyle.captionSize))
                .monospacedDigit()
                .opacity(0.6)
        }
        .popupStaticRow()
    }

    private static func size(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .binary
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: bytes)
    }
}
