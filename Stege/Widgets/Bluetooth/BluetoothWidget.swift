import SwiftUI

/// Bluetooth state, with a popup listing connected devices and their battery
/// levels where they report one.
struct BluetoothWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    var config: ConfigData { configProvider.config }

    /// Hide the widget entirely while Bluetooth is off, the way macOS hides a
    /// menu extra that has nothing to report.
    var hideWhenOff: Bool { config["hide-when-off"]?.boolValue ?? false }
    /// The battery of the connected device that has least left, beside the
    /// mark. On by default, because a headset running out is the one thing
    /// about Bluetooth worth interrupting for.
    var showBattery: Bool { config["show-battery"]?.boolValue ?? true }

    /// Connected devices only. It used to be every paired device, so a headset
    /// left in a drawer reported its last known charge as though it were on
    /// your head.
    private var lowestConnectedBattery: Double? {
        manager.devices
            .filter(\.isConnected)
            .compactMap(\.batteryLevel)
            .min()
    }

    @StateObject private var manager = BluetoothManager()
    @State private var rect: CGRect = .zero

    var body: some View {
        Group {
            if hideWhenOff && !manager.isPoweredOn {
                EmptyView()
            } else {
                content
            }
        }
    }

    /// Which devices are on, on hover. A bare "Bluetooth" said nothing the
    /// glyph had not already said.
    private var tooltip: String {
        guard manager.isAuthorized else {
            return "Stege needs Bluetooth permission"
        }
        guard manager.isPoweredOn else { return "Bluetooth off" }
        let connected = manager.devices.filter(\.isConnected)
        guard !connected.isEmpty else { return "Bluetooth on, nothing connected" }
        return connected.map(\.name).joined(separator: ", ")
    }

    private var content: some View {
        HStack(spacing: 4) {
            // A bare lock is unidentifiable: it says something is locked but
            // not what. Keeping the Bluetooth glyph and badging it with a small
            // lock says which permission is missing, which is the whole point.
            ZStack(alignment: .bottomTrailing) {
                BluetoothGlyph(
                    height: BarStyle.glyphSize,
                    slashed: !(manager.isPoweredOn && manager.isAuthorized))

                if !manager.isAuthorized {
                    Image(systemName: "lock.fill")
                        .font(.system(size: BarStyle.badgeSize, weight: .bold))
                        .offset(x: 4, y: 2)
                }
            }
            if showBattery, let lowest = lowestConnectedBattery {
                Text("\(Int((lowest * 100).rounded()))%")
                    .font(BarStyle.labelFont)
                    .monospacedDigit()
                    // Three characters wide whatever the number, so the row
                    // does not shift as a headset drains.
                    .frame(width: 30, alignment: .trailing)
                    .foregroundStyle(lowest <= 0.2 ? Color.red : .primary)
            }
        }
        .opacity(manager.isAuthorized && !manager.isPoweredOn ? 0.45 : 1)
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
        .help(tooltip)
        .onTapGesture {
            guard manager.isAuthorized else {
                NSWorkspace.shared.open(
                    URL(
                        string:
                            "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth"
                    )!)
                return
            }
            MenuBarPopup.show(rect: rect, id: "bluetooth") {
                BluetoothPopup(manager: manager)
            }
        }
    }
}

struct BluetoothPopup: View {
    @ObservedObject var manager: BluetoothManager

    var body: some View {
        VStack(alignment: .leading, spacing: PopupStyle.spacing) {
            header

            if !manager.isAuthorized {
                note(
                    "Stege cannot read Bluetooth until it is allowed in Privacy & Security."
                )
            } else if !manager.isPoweredOn {
                // Gated on the radio, not only on the list being empty. The
                // list is cleared on power-off now, but a popup that would draw
                // whatever happened to be in it is a popup that will show stale
                // devices again the next time a read lands late.
                note("Turn Bluetooth on to connect a device")
            } else if manager.devices.isEmpty {
                note("Nothing paired yet")
            } else {
                VStack(alignment: .leading, spacing: PopupStyle.rowSpacing) {
                    ForEach(manager.devices) { device in
                        deviceRow(device)
                    }
                }
            }

            if let failure = manager.failure {
                Text(failure)
                    .font(.system(size: PopupStyle.captionSize))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .popupStaticRow()
            }

            if manager.isPoweredOn, manager.isAuthorized {
                PopupSeparator()
                nearby
            }

            PopupSeparator()

            PopupSettingsRow(
                title: manager.isAuthorized
                    ? "Bluetooth Settings" : "Open Privacy & Security"
            ) {
                openSettings(
                    manager.isAuthorized
                        ? "x-apple.systempreferences:com.apple.BluetoothSettings"
                        : "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth"
                )
            }
        }
        .popupContainer()
        // Scanning on open, the way the Wi-Fi popup already lists what is in
        // range without being asked. The inquiry keeps the radio busy, so it
        // still stops the moment the popup goes away.
        .onAppear { if manager.isPoweredOn { manager.startScan() } }
        .onDisappear { manager.stopScan() }
    }

    /// What the radio is attached to, and the switch. Not the word
    /// "Bluetooth": the glyph that opened this popup already said that.
    private var header: some View {
        PopupPowerRow(state: connectionText) {
            BluetoothGlyph(
                height: 13,
                slashed: !(manager.isPoweredOn && manager.isAuthorized)
            )
            .foregroundStyle(
                manager.isPoweredOn && manager.isAuthorized
                    ? Color.blue : .secondary
            )
        } trailing: {
            if manager.isSwitchingPower {
                ProgressView().controlSize(.mini)
            } else if manager.isAuthorized {
                PopupSwitch(isOn: manager.isPoweredOn) {
                    manager.setPower(!manager.isPoweredOn)
                }
            }
        }
    }

    /// One device is named, several are counted. Naming three of them would
    /// take more width than the popup has.
    private var connectionText: String {
        guard manager.isAuthorized else { return "Unavailable" }
        guard manager.isPoweredOn else { return "Off" }
        let connected = manager.devices.filter { $0.isConnected }
        switch connected.count {
        case 0: return "Not Connected"
        case 1: return connected[0].name
        case let count: return "\(count) Connected"
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: PopupStyle.bodySize))
            .opacity(0.6)
            .fixedSize(horizontal: false, vertical: true)
            .popupStaticRow()
    }

    // MARK: - Nearby

    /// Devices that are not paired yet, behind an explicit scan. An inquiry
    /// keeps the radio busy and degrades whatever is already connected, so it
    /// never runs unless it was asked for.
    @ViewBuilder
    private var nearby: some View {
        VStack(alignment: .leading, spacing: PopupStyle.rowSpacing) {
            PopupSectionTitle(title: "Other Devices") {
                PopupRefresh(
                    isBusy: manager.isScanning, help: "Look for devices again"
                ) {
                    manager.startScan()
                }
            }
            .popupStaticRow()

            if manager.discovered.isEmpty {
                note(manager.isScanning ? "Looking…" : "None found")
            } else {
                ForEach(manager.discovered) { device in
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: PopupStyle.captionSize))
                            .opacity(0.6)
                            .frame(width: PopupStyle.iconColumn)
                        Text(device.name)
                            .font(.system(size: PopupStyle.bodySize))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 12)
                        if manager.busy == device.id {
                            ProgressView().controlSize(.mini)
                        } else {
                            Text("Pair")
                                .font(
                                    .system(
                                        size: PopupStyle.captionSize,
                                        weight: .medium)
                                )
                                .opacity(0.7)
                        }
                    }
                    .popupRow { manager.pair(device) }
                }
            }
        }
    }

    /// Name on one line, a battery bar underneath for devices that report one.
    /// A bare percentage was easy to miss next to a long device name.
    @ViewBuilder
    private func deviceRow(_ device: BluetoothDevice) -> some View {
        let isBusy = manager.busy == device.id
        let isBlocked = manager.busy != nil && !isBusy

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                // What the device is, not a bare dot. A dot said only that
                // something was connected; the symbol says what.
                Image(systemName: Self.symbol(for: device))
                    .font(.system(size: PopupStyle.bodySize))
                    .foregroundStyle(
                        device.isConnected ? Color.blue : .secondary
                    )
                    .frame(width: PopupStyle.iconColumn)
                // Names are user-set and can be long, and the popup is a fixed
                // width.
                Text(device.name)
                    .font(.system(size: PopupStyle.bodySize))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 16)
                // Unconditional, unlike the battery percentage it used to hide
                // behind: a device that reports no level showed nothing at all
                // while it connected.
                if isBusy {
                    if let activity = manager.activity {
                        Text(activity.label)
                            .font(.system(size: PopupStyle.captionSize))
                            .opacity(0.6)
                    }
                    ProgressView().controlSize(.mini)
                } else if let level = device.batteryLevel {
                    Text("\(Int((level * 100).rounded()))%")
                        .font(.system(size: PopupStyle.bodySize))
                        .monospacedDigit()
                        .opacity(0.7)
                }
            }

            if let level = device.batteryLevel {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.primary.opacity(0.15))
                        Capsule()
                            .fill(level <= 0.2 ? Color.red : Color.green)
                            .frame(width: max(2, geometry.size.width * level))
                    }
                }
                .frame(height: 3)
                .padding(.leading, PopupStyle.iconColumn + 10)
            }
        }
        .opacity(isBlocked ? 0.4 : 1)
        .popupRow {
            // One action at a time, the way Wi-Fi refuses a second join.
            guard !isBlocked, !isBusy else { return }
            manager.toggleConnection(device)
        }
        .help(device.isConnected ? "Disconnect" : "Connect")
    }

    /// What the device says it is. The name is only consulted for a device
    /// whose class of device record says nothing, which is rare.
    private static func symbol(for device: BluetoothDevice) -> String {
        switch device.kind {
        case .keyboard: return "keyboard"
        case .pointing: return "magicmouse"
        case .headphones: return "headphones"
        case .speaker: return "hifispeaker"
        case .phone: return "iphone"
        case .computer: return "laptopcomputer"
        case .watch: return "applewatch"
        case .unknown: return fallbackSymbol(for: device.name)
        }
    }

    private static func fallbackSymbol(for name: String) -> String {
        let lowered = name.lowercased()
        if lowered.contains("keyboard") { return "keyboard" }
        if lowered.contains("mouse") || lowered.contains("trackpad") {
            return "magicmouse"
        }
        if lowered.contains("airpod") || lowered.contains("headphone")
            || lowered.contains("buds") || lowered.contains("headset")
        {
            return "headphones"
        }
        if lowered.contains("speaker") { return "hifispeaker" }
        return "dot.radiowaves.left.and.right"
    }
}
