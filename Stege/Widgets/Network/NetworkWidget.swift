import SwiftUI

/// Widget for the menu, displaying Wi‑Fi and Ethernet icons.
struct NetworkWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    var config: ConfigData { configProvider.config }

    /// Show the network name beside the icon. Off by default, because reading
    /// it requires Location permission and that is not worth prompting for
    /// unless the name is actually wanted.
    var showName: Bool { config["show-name"]?.boolValue ?? false }
    /// Hide the widget entirely while nothing is connected.
    var hideWhenDisconnected: Bool {
        config["hide-when-disconnected"]?.boolValue ?? false
    }

    @StateObject private var viewModel = NetworkStatusViewModel()
    @State private var rect: CGRect = .zero

    var body: some View {
        HStack(spacing: 15) {
            if hideWhenDisconnected, viewModel.wifiState != .connected,
                viewModel.ethernetState != .connected
            {
                EmptyView()
            } else if viewModel.wifiState != .notSupported {
                wifiIcon
                    .frame(width: BarStyle.glyphWidth)
                    // A VPN is a property of the connection, not a second
                    // thing in the bar, so it rides on the mark that already
                    // stands for the connection.
                    .overlay(alignment: .bottomTrailing) {
                        if viewModel.vpnName != nil {
                            Image(systemName: "lock.fill")
                                .font(.system(size: BarStyle.badgeSize))
                                .offset(x: 3, y: 2)
                        }
                    }
            }
            if viewModel.ethernetState != .notSupported {
                ethernetIcon.frame(width: BarStyle.glyphWidth)
            }
            if showName, viewModel.wifiState == .connected {
                Text(viewModel.ssid).font(.system(size: 11)).lineLimit(1)
            }
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear { rect = geometry.frame(in: .global) }
                    .onChange(of: geometry.frame(in: .global)) { _, newValue in
                        rect = newValue
                    }
            }
        )
        .contentShape(Rectangle())
        .barGlyph()
        .experimentalConfiguration(cornerRadius: 15)
        .frame(maxHeight: .infinity)
        .background(.black.opacity(0.001))
        .onTapGesture {
            // The popup is where the network name is shown, so this is the
            // first moment Location is actually needed.
            viewModel.requestSSIDAccessIfNeeded()
            // The widget's own view model, not a second one. Each carries an
            // `NWPathMonitor` and a refresh timer, so building one here meant
            // one widget ran two of each.
            MenuBarPopup.show(rect: rect, id: "network") {
                NetworkPopup(viewModel: viewModel)
            }
        }
        .barFocusable {
            // The popup is where the network name is shown, so this is the
            // first moment Location is actually needed.
            viewModel.requestSSIDAccessIfNeeded()
            // The widget's own view model, not a second one. Each carries an
            // `NWPathMonitor` and a refresh timer, so building one here meant
            // one widget ran two of each.
            MenuBarPopup.show(rect: rect, id: "network") {
                NetworkPopup(viewModel: viewModel)
            }
        }
        .help(tooltip)
    }

    /// What the icon cannot say on its own, on hover: which network, and on
    /// which band. The name is not put in the bar by default because reading
    /// it needs Location permission, so this is where it shows up for anyone
    /// who has granted it.
    private var tooltip: String {
        if viewModel.ethernetState == .connected,
            viewModel.wifiState != .connected
        {
            return "Ethernet, connected"
        }
        switch viewModel.wifiState {
        case .connected:
            let base =
                viewModel.channel == "N/A"
                ? viewModel.ssid : "\(viewModel.ssid) · \(viewModel.channel)"
            guard let vpn = viewModel.vpnName else { return base }
            return "\(base) · \(vpn)"
        case .connectedWithoutInternet:
            return "\(viewModel.ssid), no internet"
        case .connecting: return "Connecting…"
        case .disconnected: return "Not connected"
        case .disabled: return "Wi-Fi off"
        case .notSupported: return "No Wi-Fi"
        }
    }

    private var wifiIcon: some View {
        // Driven by `NWPathMonitor` alone. This used to short-circuit to a red
        // slash whenever the SSID was unreadable, but the SSID is unreadable
        // without Location permission even while fully connected, so a working
        // connection was drawn as no connection at all.
        switch viewModel.wifiState {
        case .connected:
            return Image(systemName: "wifi")
                .foregroundColor(Color("Foreground Outside"))
        case .connecting:
            return Image(systemName: "wifi")
                .foregroundColor(.yellow)
        case .connectedWithoutInternet:
            return Image(systemName: "wifi.exclamationmark")
                .foregroundColor(.yellow)
        case .disconnected:
            return Image(systemName: "wifi.slash")
                .foregroundColor(.gray)
        case .disabled:
            return Image(systemName: "wifi.slash")
                .foregroundColor(.red)
        case .notSupported:
            return Image(systemName: "wifi.exclamationmark")
                .foregroundColor(.gray)
        }
    }

    private var ethernetIcon: some View {
        switch viewModel.ethernetState {
        case .connected:
            return Image(systemName: "network")
                .foregroundColor(.primary)
        case .connectedWithoutInternet:
            return Image(systemName: "network")
                .foregroundColor(.yellow)
        case .connecting:
            return Image(systemName: "network.slash")
                .foregroundColor(.yellow)
        case .disconnected:
            return Image(systemName: "network.slash")
                .foregroundColor(.red)
        case .disabled, .notSupported:
            return Image(systemName: "questionmark.circle")
                .foregroundColor(.gray)
        }
    }
}

struct NetworkWidget_Previews: PreviewProvider {
    static var previews: some View {
        NetworkWidget()
            .frame(width: 200, height: 100)
            .background(Color.black)
    }
}
