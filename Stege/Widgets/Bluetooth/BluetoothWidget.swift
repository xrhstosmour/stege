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
            // SF Symbols has no Bluetooth glyph, so the wave stands in for it.
            ZStack(alignment: .bottomTrailing) {
                Image(
                    systemName: manager.isPoweredOn && manager.isAuthorized
                        ? "wave.3.right" : "wave.3.right.slash"
                )
                .font(.system(size: 12))

                if !manager.isAuthorized {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 7, weight: .bold))
                        .offset(x: 3, y: 2)
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
        VStack(alignment: .leading, spacing: 8) {
            Text(
                !manager.isAuthorized
                    ? "Bluetooth permission needed"
                    : (manager.isPoweredOn ? "Bluetooth on" : "Bluetooth off")
            )
                .font(.system(size: 13, weight: .semibold))

            if manager.devices.isEmpty {
                Text("No devices connected")
                    .font(.system(size: 12))
                    .opacity(0.7)
            } else {
                ForEach(manager.devices) { device in
                    HStack(spacing: 10) {
                        Text(device.name).font(.system(size: 12))
                        Spacer(minLength: 16)
                        if let level = device.batteryLevel {
                            Text("\(Int((level * 100).rounded()))%")
                                .font(.system(size: 12))
                                .monospacedDigit()
                                .opacity(0.7)
                        }
                    }
                }
            }

            Divider()

            Text("Bluetooth Settings")
                .font(.system(size: 12))
                .contentShape(Rectangle())
                .onTapGesture {
                    NSWorkspace.shared.open(
                        URL(
                            string:
                                "x-apple.systempreferences:com.apple.BluetoothSettings"
                        )!)
                }
        }
        .padding(14)
        .frame(minWidth: 220, alignment: .leading)
    }
}
