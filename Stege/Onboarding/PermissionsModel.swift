import AppKit
import AVFoundation
import CoreBluetooth
import CoreLocation
import Combine
import EventKit

/// A permission Stege can ask for, and what stops working without it.
struct PermissionItem: Identifiable {
    enum Kind: String { case accessibility, bluetooth, calendar, location }

    let id: Kind
    let title: String
    let explanation: String
    let settingsURL: String
    var isGranted: Bool
    /// Whether any configured widget actually needs it. Nothing is asked for
    /// unless something in the bar uses it.
    var isRequired: Bool
}

/// Tracks which permissions are needed by the current configuration and which
/// of those are still missing.
final class PermissionsModel: ObservableObject {
    @Published private(set) var items: [PermissionItem] = []
    var missing: [PermissionItem] { items.filter { $0.isRequired && !$0.isGranted } }

    private var timer: Timer?
    /// Read once and kept, rather than a fresh `CLLocationManager()` on every
    /// tick of the timer below, which would otherwise repeat its XPC setup
    /// with `locationd` every 1.5 seconds for as long as polling runs.
    private let locationManager = CLLocationManager()

    init() { refresh() }

    deinit { timer?.invalidate() }

    /// Starts polling for changes made in System Settings, which posts
    /// nothing back. Call when the window becomes visible.
    ///
    /// `PermissionsModel` used to start this timer from `init`, but it is a
    /// stored property of `PermissionsWindowController.shared`, which never
    /// deallocates, so `deinit` never ran and every launch polled four
    /// authorization APIs every 1.5 seconds for the rest of the process,
    /// window shown or not.
    func startPolling() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) {
            [weak self] _ in
            self?.refresh()
        }
    }

    /// Stops polling. Call when the window is no longer visible.
    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        let displayed = ConfigManager.shared.config.rootToml.widgets.displayed
            .map(\.id)
        func uses(_ ids: [String]) -> Bool {
            ids.contains { displayed.contains($0) }
        }

        items = [
            PermissionItem(
                id: .accessibility,
                title: "Accessibility",
                explanation:
                    "Read the frontmost app's menus and open the Apple menu.",
                settingsURL:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
                isGranted: AppMenuReader.isTrusted,
                isRequired: uses(["default.applicationMenu", "default.appleMenu"])),
            PermissionItem(
                id: .bluetooth,
                title: "Bluetooth",
                explanation: "Show connected devices and their battery levels.",
                settingsURL:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth",
                isGranted: CBManager.authorization == .allowedAlways,
                isRequired: uses(["default.bluetooth"])),
            PermissionItem(
                id: .calendar,
                title: "Calendar",
                explanation: "Show today's events in the clock popup.",
                settingsURL:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars",
                isGranted: EKEventStore.authorizationStatus(for: .event)
                    == .fullAccess,
                isRequired: uses(["default.time"])),
            PermissionItem(
                id: .location,
                title: "Location",
                explanation:
                    "Read the Wi-Fi network name. The connection itself is shown without it.",
                settingsURL:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices",
                isGranted: locationManager.authorizationStatus
                    == .authorizedAlways,
                isRequired: uses(["default.network"])),
        ]
    }

    /// Asks the system directly where an app can, and opens the relevant
    /// settings pane otherwise. Accessibility and Location can prompt in place,
    /// Bluetooth only prompts on first use, which has already happened by now.
    func request(_ item: PermissionItem) {
        switch item.id {
        case .accessibility:
            AppMenuReader.requestTrust()
        case .calendar:
            // Not a fresh `EKEventStore()`: nothing here would keep it alive
            // long enough for the async round trip to `tccd` to finish, so the
            // request died silently and the row never left "Grant".
            CalendarManager.shared.requestAccessIfNeeded()
        case .bluetooth, .location:
            NSWorkspace.shared.open(URL(string: item.settingsURL)!)
        }
    }

    func openSettings(_ item: PermissionItem) {
        NSWorkspace.shared.open(URL(string: item.settingsURL)!)
    }
}
