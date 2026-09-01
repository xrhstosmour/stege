import AppKit
import Combine
import Foundation

/// One thing waiting to be updated.
struct PendingUpdate: Identifiable, Equatable {
    var id: String { "\(source.rawValue)-\(name)" }
    let name: String
    /// The version being offered, where the source names one.
    let version: String?
    let source: Source

    enum Source: String {
        case system
        case homebrew
    }
}

/// What is waiting to be updated, read without asking anyone's servers.
///
/// Stege makes no outbound network requests and that is worth keeping, so
/// neither half of this checks for updates. Both read what has already been
/// found locally:
///
/// macOS writes what its own last check turned up to
/// `/Library/Preferences/com.apple.SoftwareUpdate`, along with the date of that
/// check, which is readable without root. `softwareupdate -l` would be the
/// live answer and is exactly the call not being made.
///
/// Homebrew's `outdated` compares what is installed against the formula data
/// already on disk from the last `brew update`. It does not fetch. It does fork
/// a process, so it runs on a slow timer and off the main thread.
final class UpdatesManager: ObservableObject {
    @Published private(set) var updates: [PendingUpdate] = []
    @Published private(set) var isReading = false
    /// When macOS last looked, so the popup can say how old its answer is
    /// rather than presenting a stale count as current.
    @Published private(set) var systemLastChecked: Date?

    var count: Int { updates.count }

    private var timer: Timer?
    private let queue = DispatchQueue(
        label: "stege.updates", qos: .utility)

    /// Both sources, on or off.
    var includesSystem = true
    var includesHomebrew = true

    init() {
        refresh()
    }

    /// Configured from the widget once it knows what the file asked for, since
    /// a `StateObject` is built before the configuration is in scope. Calling
    /// it again with the same numbers does nothing.
    func configure(
        interval: TimeInterval, system: Bool, homebrew: Bool
    ) {
        let unchanged =
            timer?.timeInterval == interval && includesSystem == system
            && includesHomebrew == homebrew
        guard !unchanged else { return }
        includesSystem = system
        includesHomebrew = homebrew
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true)
        { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    deinit {
        timer?.invalidate()
    }

    func refresh() {
        guard !isReading else { return }
        isReading = true
        let wantsSystem = includesSystem
        let wantsHomebrew = includesHomebrew

        queue.async { [weak self] in
            var found: [PendingUpdate] = []
            var checked: Date?
            if wantsSystem {
                let system = Self.systemUpdates()
                found.append(contentsOf: system.updates)
                checked = system.lastChecked
            }
            if wantsHomebrew {
                found.append(contentsOf: Self.homebrewUpdates())
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isReading = false
                self.systemLastChecked = checked
                if found != self.updates { self.updates = found }
            }
        }
    }

    // MARK: - macOS

    private static func systemUpdates() -> (
        updates: [PendingUpdate], lastChecked: Date?
    ) {
        let path = "/Library/Preferences/com.apple.SoftwareUpdate.plist"
        guard let data = FileManager.default.contents(atPath: path),
            let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any]
        else { return ([], nil) }

        let checked = plist["LastSuccessfulDate"] as? Date
        guard let recommended = plist["RecommendedUpdates"] as? [[String: Any]]
        else { return ([], checked) }

        return (
            recommended.compactMap { entry in
                guard
                    let name = entry["Display Name"] as? String
                        ?? entry["Identifier"] as? String
                else { return nil }
                return PendingUpdate(
                    name: name,
                    version: entry["Display Version"] as? String,
                    source: .system)
            }, checked
        )
    }

    // MARK: - Homebrew

    private static func homebrewUpdates() -> [PendingUpdate] {
        guard let binary = homebrewBinary else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["outdated", "--quiet"]
        // `outdated` reads the tap data already on disk. Saying so explicitly
        // means a future Homebrew cannot decide to fetch on our behalf.
        process.environment = ProcessInfo.processInfo.environment.merging([
            "HOMEBREW_NO_AUTO_UPDATE": "1",
            "HOMEBREW_NO_ANALYTICS": "1",
        ]) { _, new in new }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
            let text = String(data: data, encoding: .utf8)
        else { return [] }

        return
            text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { PendingUpdate(name: $0, version: nil, source: .homebrew) }
    }

    /// Both the Apple silicon and the Intel prefix, so this works on either
    /// without being told which.
    private static let homebrewBinary: String? = {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }()

    // MARK: - Acting

    func openSoftwareUpdate() {
        MenuBarPopup.hide()
        NSWorkspace.shared.open(
            URL(
                string:
                    "x-apple.systempreferences:com.apple.Software-Update-Settings.extension"
            )!)
    }

    /// The command, on the clipboard, rather than run for you. Upgrading can
    /// restart services and ask for a password, and a menu bar is not where
    /// that should start.
    func copyHomebrewCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("brew upgrade", forType: .string)
    }
}
