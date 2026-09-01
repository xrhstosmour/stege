import SwiftUI

/// Bluetooth state, with a popup listing connected devices and their battery
/// levels where they report one.
struct BluetoothWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    var config: ConfigData { configProvider.config }

    /// Hide the widget entirely while Bluetooth is off, the way macOS hides a
    /// menu extra that has nothing to report.
    var hideWhenOff: Bool { config["hide-when-off"]?.boolValue ?? false }

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
            if let lowest = manager.devices.compactMap(\.batteryLevel).min() {
                Text("\(Int((lowest * 100).rounded()))%")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .opacity(0.8)
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
            } else if manager.devices.isEmpty {
                note(
                    manager.isPoweredOn
                        ? "Nothing paired yet"
                        : "Turn Bluetooth on to connect a device")
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
        .onDisappear { manager.stopScan() }
    }

    /// The glyph is drawn rather than an SF Symbol, so the header is built by
    /// hand instead of using `PopupHeader`.
    private var header: some View {
        HStack(spacing: 8) {
            BluetoothGlyph(
                height: 15,
                slashed: !(manager.isPoweredOn && manager.isAuthorized)
            )
            .foregroundStyle(
                manager.isPoweredOn && manager.isAuthorized
                    ? Color.blue : .secondary
            )
            .frame(width: 18)

            // Not "Bluetooth on" or "Bluetooth off". The switch beside it
            // already says which, and a header that repeats the control next
            // to it is a header saying nothing.
            Text(manager.isAuthorized ? "Bluetooth" : "Bluetooth unavailable")
                .font(.system(size: PopupStyle.titleSize, weight: .semibold))

            Spacer(minLength: 8)

            if manager.isSwitchingPower {
                ProgressView().controlSize(.mini)
            } else if manager.isAuthorized {
                PopupSwitch(isOn: manager.isPoweredOn) {
                    manager.setPower(!manager.isPoweredOn)
                }
            }
        }
        .padding(.horizontal, PopupStyle.rowHorizontalPadding)
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
                if manager.isScanning {
                    ProgressView().controlSize(.mini)
                    Text("Stop")
                        .font(.system(size: PopupStyle.captionSize))
                        .opacity(0.7)
                        .contentShape(Rectangle())
                        .onTapGesture { manager.stopScan() }
                } else {
                    Text("Scan")
                        .font(.system(size: PopupStyle.captionSize))
                        .opacity(0.7)
                        .contentShape(Rectangle())
                        .onTapGesture { manager.startScan() }
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
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 6))
                    .foregroundStyle(device.isConnected ? Color.blue : .clear)
                    .frame(width: PopupStyle.iconColumn)
                // Names are user-set and can be long, and the popup is a fixed
                // width.
                Text(device.name)
                    .font(.system(size: PopupStyle.bodySize))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 16)
                if manager.busy == device.id {
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
        .popupRow { manager.toggleConnection(device) }
        .help(device.isConnected ? "Disconnect" : "Connect")
    }
}
