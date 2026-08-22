import AppKit
import Combine

/// Whether a chosen modifier key is being held right now.
///
/// Shared rather than one per view: the monitors are process-wide, so a second
/// instance would register a second pair of them for the same key presses.
final class ModifierKeyMonitor: ObservableObject {
    static let shared = ModifierKeyMonitor()

    @Published private(set) var flags: NSEvent.ModifierFlags = []

    private var globalMonitor: Any?
    private var localMonitor: Any?
    /// How many views currently care. The monitors are torn down at zero so a
    /// configuration that never asks for a modifier costs nothing.
    private var subscribers = 0

    private init() {}

    func retain() {
        subscribers += 1
        guard subscribers == 1 else { return }
        flags = NSEvent.modifierFlags
        // Both are needed: the global monitor sees events destined for other
        // applications, the local one sees events this process receives, and
        // neither sees the other's.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: .flagsChanged
        ) { [weak self] event in
            self?.flags = event.modifierFlags
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .flagsChanged
        ) { [weak self] event in
            self?.flags = event.modifierFlags
            return event
        }
    }

    func release() {
        subscribers = max(0, subscribers - 1)
        guard subscribers == 0 else { return }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        flags = []
    }

    func isHolding(_ modifier: NSEvent.ModifierFlags) -> Bool {
        flags.contains(modifier)
    }

    /// Parses the name used in the configuration file.
    static func modifier(named name: String) -> NSEvent.ModifierFlags {
        switch name.lowercased() {
        case "command", "cmd": return .command
        case "control", "ctrl": return .control
        case "shift": return .shift
        case "function", "fn": return .function
        default: return .option
        }
    }
}
