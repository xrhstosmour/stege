import SwiftUI

/// Current connection, then the other networks in range.
///
/// Sized and padded like every other popup in the bar. It used to set its own
/// 25 point padding and black background, which made it visibly wider and
/// looser than the ones either side of it.
struct NetworkPopup: View {
    @ObservedObject var viewModel: NetworkStatusViewModel

    /// The network whose password is being typed, and the password itself.
    /// Held here rather than in the view model so it goes away with the popup
    /// and is never anywhere a published value could be read from.
    @State private var promptingFor: String?
    @State private var password = ""
    @FocusState private var passwordFocused: Bool

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
            Text(viewModel.isPoweredOn ? viewModel.ssid : "Wi-Fi Off")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Toggle(
                "",
                isOn: Binding(
                    get: { viewModel.isPoweredOn },
                    set: { viewModel.setPower($0) })
            )
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
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

    @ViewBuilder
    private func networkRow(_ network: WifiNetwork) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            rowLabel(network)
            if promptingFor == network.ssid {
                passwordField(for: network)
            }
        }
    }

    private func passwordField(for network: WifiNetwork) -> some View {
        HStack(spacing: 6) {
            SecureField("Password", text: $password)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($passwordFocused)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.primary.opacity(0.08))
                )
                .onSubmit { submit(network) }
            Image(systemName: "arrow.right.circle.fill")
                .font(.system(size: 14))
                .opacity(password.isEmpty ? 0.3 : 1)
                .contentShape(Rectangle())
                .onTapGesture { submit(network) }
        }
        .padding(.leading, 24)
    }

    private func submit(_ network: WifiNetwork) {
        guard !password.isEmpty else { return }
        viewModel.join(network, password: password)
        password = ""
        promptingFor = nil
    }

    /// A tap joins straight away when the network is open or already saved,
    /// and otherwise opens the password field under the row.
    private func tapped(_ network: WifiNetwork) {
        guard !network.isKnown, network.isSecure else {
            viewModel.join(network)
            return
        }
        password = ""
        promptingFor = promptingFor == network.ssid ? nil : network.ssid
        passwordFocused = promptingFor != nil
    }

    private func rowLabel(_ network: WifiNetwork) -> some View {
        HStack(spacing: 8) {
            // Variable value, not a per-strength symbol name: `wifi.low` and
            // `wifi.medium` do not exist, so every row below the strongest
            // rendered as blank space where its icon should have been.
            Image(systemName: "wifi", variableValue: signalFraction(for: network.rssi))
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
            if viewModel.joining == network.ssid {
                ProgressView().controlSize(.mini)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { tapped(network) }
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

    /// Maps RSSI onto the 0 to 1 range the `wifi` symbol fills its arcs from.
    /// Anything at or above -50 dBm is full, anything at or below -90 is empty.
    private func signalFraction(for rssi: Int) -> Double {
        let clamped = Double(min(-50, max(-90, rssi)))
        return (clamped + 90) / 40
    }
}
