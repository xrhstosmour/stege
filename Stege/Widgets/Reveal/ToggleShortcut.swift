import Carbon.HIToolbox
import Foundation

/// A system-wide shortcut that hides and shows the bar.
///
/// The reveal chevron already does this, but it is only reachable while the bar
/// is on screen, so getting back to a hidden bar means waiting for the pointer
/// to leave the strip. A shortcut works in both directions from anywhere.
///
/// Registered through Carbon rather than an `NSEvent` global monitor. A monitor
/// only observes, so the key press would still reach whatever app is in front
/// and beep at it, and it needs Accessibility, which Stege should not require
/// for something this small.
final class ToggleShortcut {
    static let shared = ToggleShortcut()

    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    /// What is currently registered, so an unchanged config reload is a no-op
    /// rather than an unregister and register cycle.
    private var current: String?

    private init() {}

    /// Registers `shortcut`, replacing whatever was registered before. A nil or
    /// unparseable value leaves no shortcut registered.
    func apply(_ shortcut: String?) {
        let normalised = shortcut?.trimmingCharacters(in: .whitespaces)
            .lowercased()
        guard normalised != current else { return }
        current = normalised
        unregister()
        guard let normalised, let combination = Self.parse(normalised) else {
            return
        }
        register(combination)
    }

    // MARK: - Parsing

    private struct Combination {
        let modifiers: UInt32
        let keyCode: UInt32
    }

    /// Accepts "cmd+alt+b" and the like. Names follow what people write in
    /// other menu bar tools, so `cmd`, `command`, `opt`, `option`, `alt`,
    /// `ctrl`, `control` and `shift` all resolve.
    private static func parse(_ shortcut: String) -> Combination? {
        let parts = shortcut.split(separator: "+").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard let key = parts.last, parts.count > 1 else { return nil }

        var modifiers: UInt32 = 0
        for part in parts.dropLast() {
            switch part {
            case "cmd", "command": modifiers |= UInt32(cmdKey)
            case "opt", "option", "alt": modifiers |= UInt32(optionKey)
            case "ctrl", "control": modifiers |= UInt32(controlKey)
            case "shift": modifiers |= UInt32(shiftKey)
            default: return nil
            }
        }
        guard modifiers != 0, let keyCode = keyCodes[key] else { return nil }
        return Combination(modifiers: modifiers, keyCode: keyCode)
    }

    /// Virtual key codes are positional, not lexical, so they cannot be derived
    /// from the character and have to be listed. Letters, digits and the keys
    /// people actually reach for in a shortcut.
    private static let keyCodes: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
        "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
        "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
        "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
        "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37,
        "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44,
        "n": 45, "m": 46, ".": 47, "`": 50,
        "space": 49, "return": 36, "tab": 48, "escape": 53, "delete": 51,
        "left": 123, "right": 124, "down": 125, "up": 126,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
    ]

    // MARK: - Registration

    private func register(_ combination: Combination) {
        var type = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed))
        // `self` is a singleton that outlives the handler, so passing it
        // unretained is safe and avoids a cycle that would never be broken.
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let shortcut = Unmanaged<ToggleShortcut>
                    .fromOpaque(userData).takeUnretainedValue()
                shortcut.fire()
                return noErr
            },
            1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)

        // Any four-character code will do, it only has to be distinct from
        // other hot keys this process registers, and this is the only one.
        let identifier = EventHotKeyID(
            signature: OSType(0x5354_4745), id: 1)  // "STGE".
        RegisterEventHotKey(
            combination.keyCode, combination.modifiers, identifier,
            GetApplicationEventTarget(), 0, &reference)
    }

    private func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }

    private func fire() {
        DispatchQueue.main.async {
            BarVisibility.shared.toggleByShortcut()
        }
    }
}
