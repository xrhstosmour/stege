import Combine
import Foundation

/// Which Focus, if any, is currently on.
///
/// There is no public API for this. macOS keeps the state in
/// `~/Library/DoNotDisturb/DB`, which unlike the notification database is not
/// behind Full Disk Access, so it can be read with nothing granted. Only two
/// small JSON files are touched, and neither contains message content.
///
/// `Assertions.json` exists only while a Focus is on, so its absence is the
/// answer rather than a failure. `ModeConfigurations.json` maps the identifier
/// in it to a display name, including any Focus the user has made themselves.
final class FocusReader: ObservableObject {
    /// The active Focus's display name, or nil when none is on.
    @Published private(set) var activeFocus: String?
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
            return
        }
        isReadable = true

        let assertions = directory.appendingPathComponent("Assertions.json")
        guard let identifier = activeModeIdentifier(at: assertions) else {
            activeFocus = nil
            return
        }
        activeFocus = name(of: identifier, in: configurations) ?? "Focus"
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

    private func name(of identifier: String, in url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
            let root = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any],
            let entries = root["data"] as? [[String: Any]]
        else { return nil }

        for entry in entries {
            guard
                let configurations = entry["modeConfigurations"]
                    as? [String: Any],
                let configuration = configurations[identifier]
                    as? [String: Any],
                let mode = configuration["mode"] as? [String: Any]
            else { continue }
            return mode["name"] as? String
        }
        return nil
    }
}
