import SwiftUI

/// Current connection, then the other networks in range.
///
/// Sized and padded like every other popup in the bar. It used to set its own
/// 25 point padding and black background, which made it visibly wider and
/// looser than the ones either side of it.
struct NetworkPopup: View {
    @StateObject private var viewModel = NetworkStatusViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.wifiState != .notSupported {
                current
                details
                Divider()
                nearby
            }

            if viewModel.ethernetState != .notSupported {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: ethernetSymbol)
                        .font(.system(size: 12))
                        .frame(width: 16)
                    Text("Ethernet")
                        .font(.system(size: 12))
                    Spacer(minLength: 12)
                    Text(viewModel.ethernetState.rawValue)
                        .font(.system(size: 12))
                        .opacity(0.7)
                }
            }
        }
        .padding(14)
        // Fixed, not a minimum: `Divider` reports an ideal width of infinity
        // and the popup panel behind it spans the whole screen.
        .frame(width: 260, alignment: .leading)
        .onAppear {
            viewModel.requestSSIDAccessIfNeeded()
            viewModel.scanForNetworks()
        }
    }

    // MARK: - Current connection

    private var current: some View {
        HStack(spacing: 8) {
            Image(systemName: wifiSymbol)
                .font(.system(size: 13))
                .foregroundStyle(isConnected ? Color.blue : .secondary)
                .frame(width: 18)
            Text(viewModel.ssid)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
        }
    }

    @ViewBuilder
    private var details: some View {
        if isConnected {
            VStack(alignment: .leading, spacing: 3) {
                detailRow("Signal", viewModel.wifiSignalStrength.rawValue)
                detailRow("RSSI", "\(viewModel.rssi) dBm")
                detailRow("Noise", "\(viewModel.noise) dBm")
                detailRow("Channel", viewModel.channel)
            }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(label).font(.system(size: 11)).opacity(0.6)
            Spacer(minLength: 12)
            Text(value).font(.system(size: 11)).monospacedDigit().opacity(0.85)
        }
    }

    // MARK: - Other networks

    @ViewBuilder
    private var nearby: some View {
        HStack(spacing: 6) {
            Text("Other Networks")
                .font(.system(size: 11, weight: .semibold))
                .opacity(0.6)
            Spacer(minLength: 8)
            if viewModel.isScanning {
                ProgressView().controlSize(.mini)
            }
        }

        if let failure = viewModel.joinFailure {
            Text(failure)
                .font(.system(size: 11))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }

        if viewModel.nearbyNetworks.isEmpty {
            Text(viewModel.isScanning ? "Scanning…" : "None in range")
                .font(.system(size: 12))
                .opacity(0.6)
        } else {
            // Capped so a busy area cannot grow the popup past the screen. The
            // rest are reachable through the system settings row below.
            VStack(alignment: .leading, spacing: 6) {
                ForEach(viewModel.nearbyNetworks.prefix(6)) { network in
                    networkRow(network)
                }
            }
        }

        HStack(spacing: 8) {
            Image(systemName: "gearshape").font(.system(size: 11)).frame(width: 16)
            Text("Wi-Fi Settings").font(.system(size: 12))
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .opacity(0.5)
        }
        .contentShape(Rectangle())
        .onTapGesture { viewModel.openWifiSettings() }
    }

    private func networkRow(_ network: WifiNetwork) -> some View {
        HStack(spacing: 8) {
            Image(systemName: signalSymbol(for: network.rssi))
                .font(.system(size: 11))
                .frame(width: 16)
            Text(network.ssid)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            if network.isSecure {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9))
                    .opacity(0.5)
            }
            // Anything without a saved profile opens the system picker rather
            // than joining here, so the chevron says which of the two happens.
            if !network.isKnown {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .opacity(0.4)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { viewModel.join(network) }
    }

    // MARK: - Symbols

    private var isConnected: Bool {
        viewModel.wifiState == .connected
            || viewModel.wifiState == .connectedWithoutInternet
    }

    private var wifiSymbol: String {
        switch viewModel.wifiState {
        case .connected: return "wifi"
        case .connectedWithoutInternet: return "wifi.exclamationmark"
        case .connecting: return "wifi"
        case .disconnected, .disabled: return "wifi.slash"
        case .notSupported: return "wifi.exclamationmark"
        }
    }

    private var ethernetSymbol: String {
        switch viewModel.ethernetState {
        case .connected, .connectedWithoutInternet: return "network"
        default: return "network.slash"
        }
    }

    private func signalSymbol(for rssi: Int) -> String {
        switch rssi {
        case (-60)...: return "wifi"
        case (-75)..<(-60): return "wifi.medium"
        default: return "wifi.low"
        }
    }
}
