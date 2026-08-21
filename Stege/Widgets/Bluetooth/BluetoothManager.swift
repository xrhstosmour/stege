import Combine
import CoreBluetooth
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
    /// Whether the app is allowed to read Bluetooth at all.
    ///
    /// Read through `CBManager.authorization`, which reports the current state
    /// without instantiating a central manager and therefore without prompting.
    /// `IOBluetooth` exposes no equivalent, and without this a denied
    /// permission is indistinguishable from Bluetooth simply being switched
    /// off, so the widget cannot tell the user which one it is.
    @Published private(set) var isAuthorized = true

    private var timer: Timer?
    /// Serialises reads so a slow one cannot overlap the next tick.
    private let queue = DispatchQueue(label: "stege.bluetooth", qos: .utility)
    private var isReading = false

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

    /// Reads on a background queue, never on the main thread.
    ///
    /// `IOBluetooth` access is gated by TCC, and the very first call blocks
    /// while the system decides whether to prompt. Doing that on the main
    /// thread freezes the whole bar, not just this widget: every other widget
    /// stops rendering until it returns.
    private func refresh() {
        guard !isReading else { return }
        isReading = true

        let authorized = CBManager.authorization == .allowedAlways

        queue.async { [weak self] in
            guard let self else { return }
            guard authorized else {
                DispatchQueue.main.async {
                    self.isReading = false
                    self.isAuthorized = false
                    self.isPoweredOn = false
                    self.devices = []
                }
                return
            }
            let powered =
                IOBluetoothHostController.default()?.powerState
                == kBluetoothHCIPowerStateON
            let connected = Self.connectedDevices()

            DispatchQueue.main.async {
                self.isReading = false
                self.isAuthorized = true
                guard powered != self.isPoweredOn
                    || connected.map(\.id) != self.devices.map(\.id)
                    || connected.map(\.batteryLevel)
                        != self.devices.map(\.batteryLevel)
                else { return }
                self.isPoweredOn = powered
                self.devices = connected
            }
        }
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
