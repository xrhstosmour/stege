import Combine
import Foundation

/// A Focus the user can switch on, whether one macOS ships or one they made.
struct FocusMode: Identifiable, Codable, Equatable {
    /// Control Center names its switch `focus-mode-activity-<id>`, which is how
    /// this is turned on.
    let id: String
    /// What macOS calls it, translated, so this is what goes on screen.
    let name: String
}

/// The Focus modes, and switching between them.
///
/// Both go through Control Center, which is the only route that does not need a
/// permission Stege is unwilling to ask for.
///
/// This used to read `~/Library/DoNotDisturb/DB` directly, on the belief that
/// the directory was not protected. It is: an app without Full Disk Access gets
/// `Operation not permitted` opening `ModeConfigurations.json`, confirmed with
/// a throwaway bundle, and only a terminal that already holds Full Disk Access
/// can read it. So the row never appeared in a real install, which is exactly
/// what it was written to do when it could not read the state.
///
/// The private `DoNotDisturb` framework is no better: every call on
/// `DNDModeAssertionService` comes back as an XPC error without an Apple-issued
/// entitlement.
///
/// What is left is Control Center's own Focus panel, where each mode is a
/// switch carrying its identifier, its translated name, and whether it is on.
/// Reading it means opening that panel, so the list is fetched once and kept,
/// and refreshed whenever a switch is made, since the panel is open anyway.
final class FocusReader: ObservableObject {
    /// Every Focus that can be switched on, in the order Control Center lists
    /// them.
    @Published private(set) var modes: [FocusMode] = []
    /// The active Focus's identifier, or nil when none is on.
    @Published private(set) var activeIdentifier: String?
    /// The active Focus's display name, for the widget's tooltip and glyph.
    var activeFocus: String? {
        guard let activeIdentifier else { return nil }
        return modes.first { $0.id == activeIdentifier }?.name ?? "Focus"
    }
    /// The mode a switch is in flight for.
    @Published private(set) var switching: String?
    /// True while the list is being read out of Control Center.
    @Published private(set) var isLoading = false
    /// Set when Control Center's Focus control could not be reached.
    @Published private(set) var failure: String?

    /// Kept between launches so the panel only has to be opened once, rather
    /// than every time the popup is shown.
    private static let storageKey = "stege.focus.modes"

    init() {
        modes = Self.storedModes()
    }

    /// Reads the list and the active mode out of Control Center.
    ///
    /// Only worth calling when something is about to be shown or has just been
    /// changed: it opens a panel on screen, and moves the pointer to the top of
    /// the display when the menu bar is set to hide.
    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        MenuExtra.read(
            .controlCentre, path: ["controlcenter-focus-modes"],
            matching: Self.identifierPrefix
        ) { [weak self] controls in
            guard let self else { return }
            self.isLoading = false
            guard !controls.isEmpty else {
                // Leave whatever was stored on screen rather than emptying the
                // list because one read did not land.
                self.failure = "Could not read Control Center's Focus modes"
                return
            }
            self.failure = nil
            self.modes = controls.map {
                FocusMode(
                    id: String($0.identifier.dropFirst(
                        Self.identifierPrefix.count)),
                    name: $0.label)
            }
            self.activeIdentifier =
                controls.first { $0.isOn }
                .map { String($0.identifier.dropFirst(
                    Self.identifierPrefix.count)) }
            Self.store(self.modes)
        }
    }

    /// Reads the list only when there is nothing to show yet, so opening the
    /// popup does not flash a Control Center panel every time.
    func refreshIfNeeded() {
        guard modes.isEmpty else { return }
        refresh()
    }

    /// Switches a Focus on, or off when it is the one already on.
    ///
    /// Control Center's Focus tile has to be pressed before the switch inside
    /// it exists, hence the two step path. Both are `AXIdentifier`s, which
    /// macOS ships untranslated.
    func toggle(_ mode: FocusMode) {
        guard switching == nil else { return }
        switching = mode.id
        failure = nil
        MenuExtra.press(
            .controlCentre,
            path: [
                "controlcenter-focus-modes",
                Self.identifierPrefix + mode.id,
            ]
        ) { [weak self] pressed in
            guard let self else { return }
            self.switching = nil
            guard pressed else {
                // Control Center's Focus tile can be taken out of the panel,
                // and then there is nothing to press.
                self.failure = "Could not reach Control Center's Focus control"
                return
            }
            // Believed rather than read back, so the row ticks immediately.
            // The next `refresh` corrects it if the switch did something else.
            self.activeIdentifier =
                self.activeIdentifier == mode.id ? nil : mode.id
        }
    }

    // MARK: - Storage

    private static let identifierPrefix = "focus-mode-activity-"

    private static func storedModes() -> [FocusMode] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
            let modes = try? JSONDecoder().decode([FocusMode].self, from: data)
        else { return [] }
        return modes
    }

    private static func store(_ modes: [FocusMode]) {
        guard let data = try? JSONEncoder().encode(modes) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
