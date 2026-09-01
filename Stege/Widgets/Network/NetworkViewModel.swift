import AppKit
import CoreLocation
import CoreWLAN
import Network
import SwiftUI
import SystemConfiguration

enum NetworkState: String {
    case connected = "Connected"
    case connectedWithoutInternet = "No Internet"
    case connecting = "Connecting"
    case disconnected = "Disconnected"
    case disabled = "Disabled"
    case notSupported = "Not Supported"
}

enum WifiSignalStrength: String {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case unknown = "Unknown"
}

/// A network seen by the last scan.
struct WifiNetwork: Identifiable, Equatable {
    /// The BSSID is withheld without Location, and two access points can share
    /// an SSID, so the identity is the name plus the channel it was seen on.
    var id: String { "\(ssid)-\(channel)" }
    let ssid: String
    let rssi: Int
    let channel: Int
    let isSecure: Bool
    /// Already has a saved profile, so joining needs no password from us.
    let isKnown: Bool
}

/// Unified view model for monitoring network and Wi‑Fi status.
final class NetworkStatusViewModel: NSObject, ObservableObject,
    CLLocationManagerDelegate, CWEventDelegate
{

    // States for Wi‑Fi and Ethernet obtained via NWPathMonitor.
    @Published var wifiState: NetworkState = .disconnected
    @Published var ethernetState: NetworkState = .disconnected

    // Wi‑Fi details obtained via CoreWLAN.
    @Published var ssid: String = "Not connected"
    @Published var rssi: Int = 0
    @Published var noise: Int = 0
    @Published var channel: String = "N/A"

    /// Other networks in range, newest scan first. Empty until a scan runs.
    @Published var nearbyNetworks: [WifiNetwork] = []
    @Published var isScanning = false
    /// Set when a join was attempted and did not take, so the popup can say so
    /// rather than silently doing nothing.
    @Published var joinFailure: String?
    /// The network a join is currently in flight for, so its row can say so.
    @Published var joining: String?
    /// The name of the VPN carrying traffic, or nil when none is.
    @Published var vpnName: String?

    /// Computed property for signal strength.
    var wifiSignalStrength: WifiSignalStrength {
        // If Wi‑Fi is not connected or the interface is missing – return unknown.
        if ssid == "Not connected" || ssid == "No interface" {
            return .unknown
        }
        if rssi >= -50 {
            return .high
        } else if rssi >= -70 {
            return .medium
        } else {
            return .low
        }
    }

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "NetworkMonitor")

    private var timer: Timer?
    private let locationManager = CLLocationManager()

    override init() {
        super.init()
        locationManager.delegate = self
        startNetworkMonitoring()
        startWiFiMonitoring()
    }

    deinit {
        stopNetworkMonitoring()
        stopWiFiMonitoring()
    }

    // MARK: — NWPathMonitor for overall network status.

    private func startNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            DispatchQueue.main.async {
                // Wi‑Fi
                if path.availableInterfaces.contains(where: { $0.type == .wifi }
                ) {
                    if path.usesInterfaceType(.wifi) {
                        switch path.status {
                        case .satisfied:
                            self.wifiState = .connected
                        case .requiresConnection:
                            self.wifiState = .connecting
                        default:
                            self.wifiState = .connectedWithoutInternet
                        }
                    } else {
                        // If the Wi‑Fi interface is available but not in use – consider it enabled but not connected.
                        self.wifiState = .disconnected
                    }
                } else if CWWiFiClient.shared().interface() != nil {
                    // A radio that is switched off drops out of the path's
                    // interface list entirely, which used to read as no Wi-Fi
                    // hardware at all and hid the icon, leaving nothing in the
                    // bar to switch it back on with.
                    self.wifiState = .disabled
                } else {
                    self.wifiState = .notSupported
                }

                // Ethernet
                if path.availableInterfaces.contains(where: {
                    $0.type == .wiredEthernet
                }) {
                    if path.usesInterfaceType(.wiredEthernet) {
                        switch path.status {
                        case .satisfied:
                            self.ethernetState = .connected
                        case .requiresConnection:
                            self.ethernetState = .connecting
                        default:
                            self.ethernetState = .disconnected
                        }
                    } else {
                        self.ethernetState = .disconnected
                    }
                } else {
                    self.ethernetState = .notSupported
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    private func stopNetworkMonitoring() {
        monitor.cancel()
    }

    // MARK: — Updating Wi‑Fi information via CoreWLAN.

    /// Follows CoreWLAN's own events, with a slow tick for the numbers.
    ///
    /// Joining, leaving and switching network are all announced, so none of
    /// them needs polling. The timer is kept, at 30 seconds rather than 5, for
    /// what the events do not cover: RSSI and noise drift continuously while
    /// connected to the same access point, and `linkQualityDidChange` fires far
    /// too often to drive a view from.
    private func startWiFiMonitoring() {
        let client = CWWiFiClient.shared()
        client.delegate = self
        for event in [CWEventType.ssidDidChange, .linkDidChange, .powerDidChange] {
            try? client.startMonitoringEvent(with: event)
        }

        timer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) {
            [weak self] _ in
            self?.updateWiFiInfo()
        }
        updateWiFiInfo()
    }

    private func stopWiFiMonitoring() {
        timer?.invalidate()
        timer = nil
        try? CWWiFiClient.shared().stopMonitoringAllEvents()
    }

    // MARK: — CWEventDelegate.
    //
    // All three arrive on a CoreWLAN queue, and everything they lead to assigns
    // to published properties, so each hops to the main queue first.

    func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
        DispatchQueue.main.async { [weak self] in self?.updateWiFiInfo() }
    }

    func linkDidChangeForWiFiInterface(withName interfaceName: String) {
        DispatchQueue.main.async { [weak self] in self?.updateWiFiInfo() }
    }

    func powerStateDidChangeForWiFiInterface(withName interfaceName: String) {
        DispatchQueue.main.async { [weak self] in self?.updateWiFiInfo() }
    }

    /// Requests Location only when the network name is actually wanted.
    ///
    /// macOS withholds the SSID from any app without Location authorization.
    /// Upstream asked for it unconditionally at launch, so the app prompted for
    /// Location before the user had any idea why. Nothing but the name needs it.
    func requestSSIDAccessIfNeeded() {
        guard CLLocationManager.authorizationStatus() == .notDetermined else {
            return
        }
        locationManager.requestWhenInUseAuthorization()
    }

    func updateWiFiInfo() {
        vpnName = Self.activeVPN()
        let client = CWWiFiClient.shared()
        if let interface = client.interface() {
            // A nil SSID means "not readable", which is not the same as "not
            // connected". The connection state comes from `NWPathMonitor`.
            self.ssid = interface.ssid()
                ?? (wifiState == .connected ? "Wi-Fi" : "Not connected")
            self.rssi = interface.rssiValue()
            self.noise = interface.noiseMeasurement()
            if let wlanChannel = interface.wlanChannel() {
                let band: String
                switch wlanChannel.channelBand {
                case .bandUnknown:
                    band = "unknown"
                case .band2GHz:
                    band = "2GHz"
                case .band5GHz:
                    band = "5GHz"
                case .band6GHz:
                    band = "6GHz"
                @unknown default:
                    band = "unknown"
                }
                self.channel = "\(wlanChannel.channelNumber) (\(band))"
            } else {
                self.channel = "N/A"
            }
        } else {
            // Interface not available – Wi‑Fi is off.
            self.ssid = "No interface"
            self.rssi = 0
            self.noise = 0
            self.channel = "N/A"
        }
    }

    // MARK: — Scanning and joining.

    /// Scans for networks in range.
    ///
    /// Only ever called when the popup is opened, never on the refresh timer: a
    /// scan takes seconds, and the radio cannot carry traffic while it sweeps
    /// the channels, so polling one would cost throughput permanently.
    func scanForNetworks() {
        guard !isScanning else { return }
        isScanning = true
        joinFailure = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let interface = CWWiFiClient.shared().interface() else {
                DispatchQueue.main.async { self?.isScanning = false }
                return
            }
            // `networkProfiles` is an `NSOrderedSet`, so it has to go through
            // `array` before it can be mapped.
            let saved = Set(
                (interface.configuration()?.networkProfiles.array ?? [])
                    .compactMap { ($0 as? CWNetworkProfile)?.ssid })
            let current = interface.ssid()
            let found = (try? interface.scanForNetworks(withSSID: nil)) ?? []

            // One entry per name, keeping the strongest access point, which is
            // the one a join would land on anyway.
            var strongest: [String: WifiNetwork] = [:]
            for network in found {
                guard let ssid = network.ssid, !ssid.isEmpty, ssid != current
                else { continue }
                let candidate = WifiNetwork(
                    ssid: ssid,
                    rssi: network.rssiValue,
                    channel: network.wlanChannel?.channelNumber ?? 0,
                    isSecure: !network.supportsSecurity(.none),
                    isKnown: saved.contains(ssid))
                if let existing = strongest[ssid], existing.rssi >= candidate.rssi {
                    continue
                }
                strongest[ssid] = candidate
            }

            let sorted = strongest.values.sorted { $0.rssi > $1.rssi }
            DispatchQueue.main.async {
                self?.nearbyNetworks = sorted
                self?.isScanning = false
            }
        }
    }

    /// Joins a network, with a password when one is needed.
    ///
    /// A nil password makes CoreWLAN use the saved keychain entry, which is
    /// what a network with a profile already has. For anything else the popup
    /// asks, and the value is handed straight to `associate` and dropped.
    /// Nothing is stored here: CoreWLAN writes the successful one to the system
    /// keychain itself, which is where it belongs.
    func join(_ network: WifiNetwork, password: String? = nil) {
        joinFailure = nil
        joining = network.ssid

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let interface = CWWiFiClient.shared().interface(),
                let match = (try? interface.scanForNetworks(
                    withSSID: network.ssid.data(using: .utf8)))?.first
            else {
                DispatchQueue.main.async {
                    self?.joining = nil
                    self?.joinFailure = "\(network.ssid) is no longer in range"
                }
                return
            }
            do {
                try interface.associate(to: match, password: password)
                DispatchQueue.main.async {
                    self?.joining = nil
                    self?.updateWiFiInfo()
                    self?.scanForNetworks()
                }
            } catch {
                DispatchQueue.main.async {
                    self?.joining = nil
                    // The framework's own message says whether the password was
                    // wrong or the join timed out, which is the only thing that
                    // helps at this point.
                    self?.joinFailure =
                        "Could not join \(network.ssid). "
                        + error.localizedDescription
                }
            }
        }
    }

    /// Turns the Wi-Fi radio on or off. Everything else in this popup depends
    /// on it, so having to leave for System Settings to flip it made the rest
    /// unreachable exactly when it mattered.
    func setPower(_ on: Bool) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let interface = CWWiFiClient.shared().interface() else {
                return
            }
            do {
                try interface.setPower(on)
                DispatchQueue.main.async {
                    self?.updateWiFiInfo()
                    if on { self?.scanForNetworks() }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.joinFailure =
                        on
                        ? "Could not turn Wi-Fi on"
                        : "Could not turn Wi-Fi off"
                }
            }
        }
    }

    var isPoweredOn: Bool {
        CWWiFiClient.shared().interface()?.powerOn() ?? false
    }

    func openWifiSettings() {
        NSWorkspace.shared.open(
            URL(
                string:
                    "x-apple.systempreferences:com.apple.wifi-settings-extension"
            )!)
    }

    // MARK: - VPN

    /// The VPN service carrying traffic, by name, or nil.
    ///
    /// Not "is there a tunnel interface": macOS keeps four `utun` interfaces up
    /// with no VPN connected at all, for its own services, so the presence of
    /// one says nothing. What does say something is the configuration store:
    /// each network service that currently has an address publishes
    /// `State:/Network/Service/<id>/IPv4` naming the interface it runs over. A
    /// service running over a tunnel is a VPN, and the matching `Setup:` key
    /// carries the name the user gave it.
    private static func activeVPN() -> String? {
        guard
            let store = SCDynamicStoreCreate(
                nil, "stege.network" as CFString, nil, nil),
            let keys = SCDynamicStoreCopyKeyList(
                store, "State:/Network/Service/.*/IPv4" as CFString)
                as? [String]
        else { return nil }

        for key in keys {
            guard
                let value = SCDynamicStoreCopyValue(store, key as CFString)
                    as? [String: Any],
                let interface = value["InterfaceName"] as? String,
                isTunnel(interface)
            else { continue }

            // "State:/Network/Service/<id>/IPv4" -> the service identifier.
            let parts = key.split(separator: "/")
            guard parts.count >= 4 else { return interface }
            let identifier = String(parts[parts.count - 2])
            let setup =
                SCDynamicStoreCopyValue(
                    store, "Setup:/Network/Service/\(identifier)" as CFString)
                as? [String: Any]
            return (setup?["UserDefinedName"] as? String) ?? interface
        }
        return nil
    }

    private static func isTunnel(_ interface: String) -> Bool {
        ["utun", "ipsec", "ppp", "tun", "tap"].contains {
            interface.hasPrefix($0)
        }
    }

    // MARK: — CLLocationManagerDelegate.

    func locationManager(
        _ manager: CLLocationManager,
        didChangeAuthorization status: CLAuthorizationStatus
    ) {
        updateWiFiInfo()
    }
}
