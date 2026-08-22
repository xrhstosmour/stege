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

    private var content: some View {
        HStack(spacing: 4) {
            // A bare lock is unidentifiable: it says something is locked but
            // not what. Keeping the Bluetooth glyph and badging it with a small
            // lock says which permission is missing, which is the whole point.
            ZStack(alignment: .bottomTrailing) {
                BluetoothGlyph(
                    height: 13,
                    slashed: !(manager.isPoweredOn && manager.isAuthorized))

                if !manager.isAuthorized {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 7, weight: .bold))
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
        .help(
            manager.isAuthorized
                ? "Bluetooth" : "Stege needs Bluetooth permission"
        )
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
        VStack(alignment: .leading, spacing: 10) {
            header

            if !manager.isAuthorized {
                Text("Stege cannot read Bluetooth until it is allowed in Privacy & Security.")
                    .font(.system(size: 11))
                    .opacity(0.7)
                    .fixedSize(horizontal: false, vertical: true)
            } else if manager.devices.isEmpty {
                Text(
                    manager.isPoweredOn
                        ? "No devices connected" : "Turn Bluetooth on to connect a device"
                )
                .font(.system(size: 12))
                .opacity(0.7)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(manager.devices) { device in
                        deviceRow(device)
                    }
                }
            }

            Divider()

            settingsRow
        }
        .padding(14)
        // A fixed width, not a minimum. `Divider` reports an ideal width of
        // infinity, so under `minWidth` it stretched the popup to the full
        // width of the screen-sized panel behind it, which then pushed the
        // left-aligned text off the edge of the display.
        .frame(width: 250, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 8) {
            BluetoothGlyph(
                height: 15,
                slashed: !(manager.isPoweredOn && manager.isAuthorized)
            )
            .foregroundStyle(
                manager.isPoweredOn && manager.isAuthorized ? Color.blue : .secondary)

            Text(
                !manager.isAuthorized
                    ? "Bluetooth unavailable"
                    : (manager.isPoweredOn ? "Bluetooth on" : "Bluetooth off")
            )
            .font(.system(size: 13, weight: .semibold))

            Spacer(minLength: 8)
        }
    }

    /// Name on one line, a battery bar underneath for devices that report one.
    /// A bare percentage was easy to miss next to a long device name.
    @ViewBuilder
    private func deviceRow(_ device: BluetoothDevice) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                // Names are user-set and can be long, and the popup is a fixed
                // width.
                Text(device.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 16)
                if let level = device.batteryLevel {
                    Text("\(Int((level * 100).rounded()))%")
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .opacity(0.7)
                }
            }

            if let level = device.batteryLevel {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.15))
                        Capsule()
                            .fill(level <= 0.2 ? Color.red : Color.green)
                            .frame(width: max(2, geometry.size.width * level))
                    }
                }
                .frame(height: 3)
            }
        }
    }

    private var settingsRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "gearshape")
                .font(.system(size: 11))
            Text(
                manager.isAuthorized
                    ? "Bluetooth Settings" : "Open Privacy & Security"
            )
            .font(.system(size: 12))
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .opacity(0.5)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            let target =
                manager.isAuthorized
                ? "x-apple.systempreferences:com.apple.BluetoothSettings"
                : "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth"
            NSWorkspace.shared.open(URL(string: target)!)
        }
    }
}
