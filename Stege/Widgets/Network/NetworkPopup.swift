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
        VStack(alignment: .leading, spacing: PopupStyle.spacing) {
            if viewModel.wifiState != .notSupported {
                current
                details
                Divider()
                nearby
            }

            if viewModel.ethernetState != .notSupported {
                Divider()
                HStack(spacing: 10) {
                    Image(systemName: ethernetSymbol)
                        .font(.system(size: PopupStyle.bodySize))
                        .frame(width: PopupStyle.iconColumn)
                    Text("Ethernet").font(.system(size: PopupStyle.bodySize))
                    Spacer(minLength: 12)
                    Text(viewModel.ethernetState.rawValue)
                        .font(.system(size: PopupStyle.bodySize))
                        .opacity(0.7)
                }
                .popupStaticRow()
            }
        }
        .popupContainer()
        .onAppear {
            viewModel.requestSSIDAccessIfNeeded()
            viewModel.scanForNetworks()
        }
    }

    // MARK: - Current connection

    private var current: some View {
        PopupHeader(
            symbol: wifiSymbol,
            title: viewModel.isPoweredOn ? viewModel.ssid : "Wi-Fi Off",
            tint: isConnected ? .blue : .secondary
        ) {
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
            VStack(alignment: .leading, spacing: PopupStyle.rowSpacing) {
                detailRow("Signal", viewModel.wifiSignalStrength.rawValue)
                detailRow("RSSI", "\(viewModel.rssi) dBm")
                detailRow("Noise", "\(viewModel.noise) dBm")
                detailRow("Channel", viewModel.channel)
            }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: PopupStyle.captionSize)).opacity(0.6)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: PopupStyle.captionSize))
                .monospacedDigit()
                .opacity(0.85)
        }
        .popupStaticRow()
    }

    // MARK: - Other networks

    @ViewBuilder
    private var nearby: some View {
        VStack(alignment: .leading, spacing: PopupStyle.rowSpacing) {
            PopupSectionTitle(title: "Other Networks") {
                if viewModel.isScanning {
                    ProgressView().controlSize(.mini)
                }
            }
            .popupStaticRow()

            if let failure = viewModel.joinFailure {
                Text(failure)
                    .font(.system(size: PopupStyle.captionSize))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .popupStaticRow()
            }

            if viewModel.nearbyNetworks.isEmpty {
                Text(viewModel.isScanning ? "Scanning…" : "None in range")
                    .font(.system(size: PopupStyle.bodySize))
                    .opacity(0.6)
                    .popupStaticRow()
            } else {
                // Capped so a busy area cannot grow the popup past the screen.
                // The rest are reachable through the system settings row below.
                ForEach(viewModel.nearbyNetworks.prefix(6)) { network in
                    networkRow(network)
                }
            }
        }

        PopupSettingsRow(title: "Wi-Fi Settings") {
            MenuBarPopup.hide()
            viewModel.openWifiSettings()
        }
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
        .padding(.leading, PopupStyle.iconColumn + 16)
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
        HStack(spacing: 10) {
            // Variable value, not a per-strength symbol name: `wifi.low` and
            // `wifi.medium` do not exist, so every row below the strongest
            // rendered as blank space where its icon should have been.
            Image(
                systemName: "wifi",
                variableValue: signalFraction(for: network.rssi)
            )
            .font(.system(size: PopupStyle.captionSize))
            .frame(width: PopupStyle.iconColumn)
            Text(network.ssid)
                .font(.system(size: PopupStyle.bodySize))
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
        .popupRow { tapped(network) }
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
