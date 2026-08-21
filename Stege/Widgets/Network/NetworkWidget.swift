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
            }
            if viewModel.ethernetState != .notSupported {
                ethernetIcon
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
        .font(.system(size: 15))
        .experimentalConfiguration(cornerRadius: 15)
        .frame(maxHeight: .infinity)
        .background(.black.opacity(0.001))
        .onTapGesture {
            // The popup is where the network name is shown, so this is the
            // first moment Location is actually needed.
            viewModel.requestSSIDAccessIfNeeded()
            MenuBarPopup.show(rect: rect, id: "network") { NetworkPopup() }
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
                .foregroundColor(.foregroundOutside)
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
