import AppKit
import CoreLocation
import CoreWLAN
import Network
import SwiftUI

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

    /// Joins a network that already has a saved profile.
    ///
    /// Only known networks are joined from here. Anything else needs a
    /// password, and asking for one in this popup would mean Stege handling a
    /// credential it has no business seeing, so those hand off to the system
    /// Wi-Fi settings instead.
    func join(_ network: WifiNetwork) {
        guard network.isKnown else {
            openWifiSettings()
            return
        }
        joinFailure = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let interface = CWWiFiClient.shared().interface(),
                let match = (try? interface.scanForNetworks(
                    withSSID: network.ssid.data(using: .utf8)))?.first
            else {
                DispatchQueue.main.async {
                    self?.joinFailure = "\(network.ssid) is no longer in range"
                }
                return
            }
            do {
                // A nil password makes CoreWLAN use the saved keychain entry,
                // which is the whole reason this is limited to known networks.
                try interface.associate(to: match, password: nil)
                DispatchQueue.main.async { self?.updateWiFiInfo() }
            } catch {
                DispatchQueue.main.async {
                    self?.joinFailure = "Could not join \(network.ssid)"
                }
            }
        }
    }

    func openWifiSettings() {
        NSWorkspace.shared.open(
            URL(
                string:
                    "x-apple.systempreferences:com.apple.wifi-settings-extension"
            )!)
    }

    // MARK: — CLLocationManagerDelegate.

    func locationManager(
        _ manager: CLLocationManager,
        didChangeAuthorization status: CLAuthorizationStatus
    ) {
        updateWiFiInfo()
    }
}
