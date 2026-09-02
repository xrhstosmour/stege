import SwiftUI

/// Current connection, then the other networks in range.
///
/// Sized and padded like every other popup in the bar. It used to set its own
/// 25 point padding and black background, which made it visibly wider and
/// looser than the ones either side of it.
struct NetworkPopup: View {
    /// Throughput is already measured for the monitor widget, so the popup
    /// borrows that rather than counting the same interfaces a second time.
    @ObservedObject private var traffic = SystemMonitorManager.shared
    @ObservedObject var viewModel: NetworkStatusViewModel

    /// The network whose password is being typed, and the password itself.
    /// Held here rather than in the view model so it goes away with the popup
    /// and is never anywhere a published value could be read from.
    @State private var promptingFor: String?
    @State private var password = ""
    @State private var isPasswordVisible = false
    @FocusState private var passwordFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: PopupStyle.spacing) {
            if viewModel.wifiState != .notSupported {
                current
                details
                PopupSeparator()
                nearby
            }

            if viewModel.ethernetState != .notSupported {
                PopupSeparator()
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
        // The connection, not the word "Wi-Fi". Clicking the Wi-Fi glyph is
        // already the answer to which popup this is, so the row spends its
        // width on the network instead.
        PopupPowerRow(state: viewModel.isPoweredOn ? viewModel.ssid : "Off") {
            Image(systemName: wifiSymbol)
                .font(.system(size: PopupStyle.bodySize))
                .foregroundStyle(isConnected ? Color.blue : .secondary)
        } trailing: {
            PopupSwitch(isOn: viewModel.isPoweredOn) {
                viewModel.setPower(!viewModel.isPoweredOn)
            }
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
                if let vpn = viewModel.vpnName {
                    detailRow("VPN", vpn)
                }
                detailRow("Down", Self.rate(traffic.bytesReceivedPerSecond))
                detailRow("Up", Self.rate(traffic.bytesSentPerSecond))
            }
        }
    }

    /// Compact, the way macOS abbreviates a rate.
    private static func rate(_ bytesPerSecond: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .binary
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: Int64(max(0, bytesPerSecond)))
            + "/s"
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

            // Only while no card is open. A failure belongs next to the
            // network it is about, and the card puts it there.
            if let failure = viewModel.joinFailure, promptingFor == nil {
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
                joinCard(for: network)
            }
        }
    }

    // MARK: - Joining

    /// What appears under a secured network that has not been joined before.
    ///
    /// This used to be a bare secure field with an arrow next to it, indented
    /// under the row, with no heading, no way to check what had been typed and
    /// no way out other than clicking the row again. It reads as a small sheet
    /// now: it says which network it is asking about, it can show the password
    /// back, and it has both of the two answers as buttons.
    private func joinCard(for network: WifiNetwork) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Password for “\(network.ssid)”")
                .font(.system(size: PopupStyle.captionSize))
                .opacity(0.7)
                .lineLimit(1)
                .truncationMode(.middle)

            passwordField(for: network)

            if let failure = viewModel.joinFailure {
                Text(failure)
                    .font(.system(size: PopupStyle.captionSize))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 6) {
                Spacer(minLength: 0)
                cardButton("Cancel", filled: false, enabled: true) {
                    dismissCard()
                }
                cardButton("Join", filled: true, enabled: !password.isEmpty) {
                    submit(network)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.white.opacity(0.10), lineWidth: 1)
                )
        )
    }

    /// The field itself, secure by default with the usual way to look at what
    /// was typed. A long Wi-Fi key is easy to get wrong and impossible to check
    /// against a row of dots.
    private func passwordField(for network: WifiNetwork) -> some View {
        HStack(spacing: 6) {
            Group {
                if isPasswordVisible {
                    TextField("Password", text: $password)
                } else {
                    SecureField("Password", text: $password)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .focused($passwordFocused)
            .onSubmit { submit(network) }

            Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                .font(.system(size: 11))
                .opacity(0.6)
                .contentShape(Rectangle())
                .onTapGesture { isPasswordVisible.toggle() }
                .help(isPasswordVisible ? "Hide the password" : "Show the password")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.black.opacity(0.25))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private func cardButton(
        _ title: String, filled: Bool, enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Text(title)
            .font(.system(size: PopupStyle.bodySize, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(filled ? Color.accentColor : .white.opacity(0.10))
            )
            .opacity(enabled ? 1 : 0.4)
            .contentShape(Rectangle())
            .onTapGesture {
                guard enabled else { return }
                action()
            }
    }

    private func submit(_ network: WifiNetwork) {
        guard !password.isEmpty else { return }
        viewModel.join(network, password: password)
        dismissCard()
    }

    private func dismissCard() {
        password = ""
        isPasswordVisible = false
        promptingFor = nil
        passwordFocused = false
    }

    /// A tap joins straight away when the network is open or already saved,
    /// and otherwise opens the join card under the row.
    private func tapped(_ network: WifiNetwork) {
        guard !network.isKnown, network.isSecure else {
            viewModel.join(network)
            return
        }
        if promptingFor == network.ssid {
            dismissCard()
            return
        }
        password = ""
        isPasswordVisible = false
        viewModel.joinFailure = nil
        promptingFor = network.ssid
        passwordFocused = true
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
