import Combine
import Foundation
import IOBluetooth

/// A connected Bluetooth device and its battery level, when it reports one.
struct BluetoothDevice: Identifiable {
    let id: String
    let name: String
    /// 0 to 1, or nil when the device does not report a battery level.
    let batteryLevel: Double?
}

/// Bluetooth power state and connected devices.
///
/// `IOBluetooth` is used rather than `CoreBluetooth`: `CoreBluetooth` describes
/// devices this app could connect to as a client, and would prompt for
/// permission, while the bar only needs to report what the system is already
/// connected to.
final class BluetoothManager: ObservableObject {
    @Published private(set) var isPoweredOn = false
    @Published private(set) var devices: [BluetoothDevice] = []

    private var timer: Timer?

    init(interval: TimeInterval = 5.0) {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) {
            [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        timer?.invalidate()
    }

    private func refresh() {
        let powered = IOBluetoothHostController.default()?.powerState == kBluetoothHCIPowerStateON
        let connected = Self.connectedDevices()
        guard powered != isPoweredOn || connected.map(\.id) != devices.map(\.id)
            || connected.map(\.batteryLevel) != devices.map(\.batteryLevel)
        else { return }
        isPoweredOn = powered
        devices = connected
    }

    private static func connectedDevices() -> [BluetoothDevice] {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]
        else { return [] }
        return paired.filter { $0.isConnected() }.map { device in
            BluetoothDevice(
                id: device.addressString ?? UUID().uuidString,
                name: device.name ?? device.addressString ?? "Unknown",
                batteryLevel: batteryLevel(for: device))
        }
    }

    /// Battery level, where the device publishes one.
    ///
    /// There is no public API for this. macOS stores it per device address under
    /// the Bluetooth preferences domain, which is readable without any
    /// permission, and absent for devices that do not report a level.
    private static func batteryLevel(for device: IOBluetoothDevice) -> Double? {
        guard let address = device.addressString?.replacingOccurrences(
            of: ":", with: "-").lowercased(),
            let defaults = UserDefaults(suiteName: "com.apple.Bluetooth"),
            let cache = defaults.dictionary(forKey: "DeviceCache"),
            let entry = cache[address] as? [String: Any]
        else { return nil }

        // Single-battery devices report one percentage. Split devices, AirPods
        // and their case, report several, and the lowest is the one worth
        // surfacing.
        let keys = [
            "BatteryPercent", "BatteryPercentSingle", "BatteryPercentLeft",
            "BatteryPercentRight", "BatteryPercentCase",
        ]
        let levels = keys.compactMap { entry[$0] as? Double }.filter { $0 > 0 }
        guard let lowest = levels.min() else { return nil }
        // Stored as a fraction by some devices and a percentage by others.
        return lowest > 1 ? lowest / 100 : lowest
    }
}
