import Foundation

/// Turns "cmd+alt+b" into the modifier mask and virtual key code Carbon wants.
///
/// Separate from `GlobalShortcut` so it can be tested: registering a hot key
/// needs a running application and a Carbon event target, parsing a string does
/// not, and parsing is where the mistakes are.
enum ShortcutParser {
    /// Carbon's modifier bits, spelled out rather than imported, so this file
    /// carries no framework at all. From `Carbon.HIToolbox`: `cmdKey` 0x0100,
    /// `shiftKey` 0x0200, `optionKey` 0x0800, `controlKey` 0x1000.
    enum Modifier: UInt32 {
        case command = 0x0100
        case shift = 0x0200
        case option = 0x0800
        case control = 0x1000
    }

    struct Combination: Equatable {
        let modifiers: UInt32
        let keyCode: UInt32
    }

    /// Nil for anything that would not register: no modifier, an unknown
    /// modifier name, an unknown key, or a bare key on its own. A shortcut with
    /// no modifier would swallow that key everywhere in the system.
    static func parse(_ shortcut: String) -> Combination? {
        let parts = shortcut.lowercased().split(separator: "+").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard let key = parts.last, parts.count > 1 else { return nil }

        var modifiers: UInt32 = 0
        for part in parts.dropLast() {
            switch part {
            case "cmd", "command": modifiers |= Modifier.command.rawValue
            case "opt", "option", "alt": modifiers |= Modifier.option.rawValue
            case "ctrl", "control": modifiers |= Modifier.control.rawValue
            case "shift": modifiers |= Modifier.shift.rawValue
            default: return nil
            }
        }
        guard modifiers != 0, let keyCode = keyCodes[key] else { return nil }
        return Combination(modifiers: modifiers, keyCode: keyCode)
    }

    /// Virtual key codes are positional, not lexical, so they cannot be derived
    /// from the character and have to be listed.
    static let keyCodes: [String: UInt32] = [
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
}
