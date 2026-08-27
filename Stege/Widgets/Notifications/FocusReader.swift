import Combine
import Foundation

/// A Focus the user can switch on, whether one macOS ships or one they made.
struct FocusMode: Identifiable {
    /// The mode identifier macOS uses, such as
    /// `com.apple.donotdisturb.mode.default`. Control Center names its own
    /// switch after this, which is how a mode is turned on.
    let id: String
    let name: String
    /// The SF Symbol macOS shows for it, where it names one.
    let symbol: String
}

/// Which Focus, if any, is on, and switching between them.
///
/// There is no public API for either. macOS keeps the state in
/// `~/Library/DoNotDisturb/DB`, which unlike the notification database is not
/// behind Full Disk Access, so it can be read with nothing granted. Only two
/// small JSON files are touched, and neither contains message content.
///
/// `Assertions.json` exists only while a Focus is on, so its absence is the
/// answer rather than a failure. `ModeConfigurations.json` maps the identifier
/// in it to a display name, including any Focus the user has made themselves.
///
/// Writing goes the other way, through Control Center, because the private
/// `DoNotDisturb` framework refuses an unentitled caller: every call on
/// `DNDModeAssertionService` comes back as an XPC error, checked here.
final class FocusReader: ObservableObject {
    /// The active Focus's display name, or nil when none is on.
    @Published private(set) var activeFocus: String?
    /// The active Focus's mode identifier, which is what the switch is named
    /// after, unlike the display name.
    @Published private(set) var activeIdentifier: String?
    /// Every Focus that can be switched on, in the order macOS lists them.
    @Published private(set) var modes: [FocusMode] = []
    /// The mode a switch is in flight for.
    @Published private(set) var switching: String?
    /// Set when the switch could not be reached, so the popup says so instead
    /// of leaving a row that appears to have ignored the click.
    @Published private(set) var failure: String?
    /// False when the files cannot be read at all, so the widget can leave the
    /// row out rather than claim Focus is off when it does not know.
    @Published private(set) var isReadable = true

    private let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/DoNotDisturb/DB")
    private var timer: Timer?

    /// Polled rather than watched. The directory is rewritten wholesale when a
    /// Focus changes, so a descriptor on either file goes stale immediately,
    /// and this is only read while something is looking at it.
    init(interval: TimeInterval = 10) {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) {
            [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        timer?.invalidate()
    }

    func refresh() {
        let configurations = directory
            .appendingPathComponent("ModeConfigurations.json")
        guard FileManager.default.isReadableFile(atPath: configurations.path)
        else {
            isReadable = false
            activeFocus = nil
            activeIdentifier = nil
            modes = []
            return
        }
        isReadable = true
        modes = availableModes(in: configurations)

        let assertions = directory.appendingPathComponent("Assertions.json")
        guard let identifier = activeModeIdentifier(at: assertions) else {
            activeFocus = nil
            activeIdentifier = nil
            return
        }
        activeIdentifier = identifier
        activeFocus =
            modes.first { $0.id == identifier }?.name ?? "Focus"
    }

    /// Switches a Focus on, or off when it is the one already on.
    ///
    /// Control Center's Focus tile has to be opened before the switch inside it
    /// exists, hence the two step path. Both are `AXIdentifier`s, which macOS
    /// ships untranslated, so this does not depend on the system language.
    func toggle(_ mode: FocusMode) {
        guard switching == nil else { return }
        switching = mode.id
        failure = nil
        MenuExtra.press(
            .controlCentre,
            path: ["controlcenter-focus-modes", "focus-mode-activity-\(mode.id)"]
        ) { [weak self] pressed in
            self?.switching = nil
            // Control Center's Focus tile can be removed from the panel, and
            // then there is nothing to press.
            self?.failure =
                pressed ? nil : "Could not reach Control Center's Focus control"
            // The files are rewritten as the assertion is taken, but not
            // always before the press returns, so this reads once more a
            // moment later rather than showing the previous state until the
            // timer comes round.
            self?.refresh()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self?.refresh()
            }
        }
    }

    private func activeModeIdentifier(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
            let root = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any],
            let storeAssertions = root["data"] as? [[String: Any]]
        else { return nil }

        for entry in storeAssertions {
            guard
                let records = entry["storeAssertionRecords"] as? [[String: Any]]
            else { continue }
            for record in records {
                if let details = record["assertionDetails"] as? [String: Any],
                    let identifier = details[
                        "assertionDetailsModeIdentifier"] as? String
                {
                    return identifier
                }
            }
        }
        return nil
    }

    private func availableModes(in url: URL) -> [FocusMode] {
        guard let data = try? Data(contentsOf: url),
            let root = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any],
            let entries = root["data"] as? [[String: Any]]
        else { return [] }

        var found: [FocusMode] = []
        var seen: Set<String> = []
        for entry in entries {
            guard
                let configurations = entry["modeConfigurations"]
                    as? [String: Any]
            else { continue }
            for (identifier, value) in configurations {
                guard !seen.contains(identifier),
                    let configuration = value as? [String: Any],
                    let mode = configuration["mode"] as? [String: Any],
                    let name = mode["name"] as? String
                else { continue }
                seen.insert(identifier)
                found.append(
                    FocusMode(
                        id: identifier, name: name,
                        symbol: mode["symbolImageName"] as? String
                            ?? "moon.fill"))
            }
        }
        // The file is a dictionary, so its order is not the order macOS shows.
        // Sorted by name so the list at least does not move between reads.
        return found.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
