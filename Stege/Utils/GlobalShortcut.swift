import Carbon.HIToolbox
import Foundation

/// System-wide shortcuts.
///
/// Registered through Carbon rather than an `NSEvent` global monitor. A monitor
/// only observes, so the key press would still reach whatever application is in
/// front and beep at it, and it needs Accessibility, which Stege should not
/// require for something this small.
///
/// This used to be one hard-coded shortcut with one hot key reference. There are
/// two now, hiding the bar and stepping through it, so registration is keyed by
/// name and each one carries its own action.
final class GlobalShortcut {
    static let shared = GlobalShortcut()

    private struct Registration {
        let reference: EventHotKeyRef
        /// What the file asked for, so an unchanged reload is a no-op rather
        /// than an unregister and register cycle.
        let shortcut: String
    }

    private var registrations: [String: Registration] = [:]
    private var actions: [UInt32: () -> Void] = [:]
    private var handler: EventHandlerRef?
    private var nextIdentifier: UInt32 = 1

    private init() {}

    /// Registers `shortcut` under `name`, replacing whatever was registered
    /// under that name before. A nil or unparseable value leaves none.
    func apply(_ shortcut: String?, name: String, action: @escaping () -> Void)
    {
        let normalised = shortcut?.trimmingCharacters(in: .whitespaces)
            .lowercased()
        if registrations[name]?.shortcut == normalised { return }
        unregister(name)
        guard let normalised, let combination = Self.parse(normalised) else {
            return
        }
        installHandlerIfNeeded()

        let identifier = nextIdentifier
        nextIdentifier += 1
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combination.keyCode, combination.modifiers,
            // Any four-character code will do, it only has to be distinct from
            // other hot keys this process registers.
            EventHotKeyID(signature: OSType(0x5354_4745), id: identifier),
            GetApplicationEventTarget(), 0, &reference)
        guard status == noErr, let reference else { return }
        registrations[name] = Registration(
            reference: reference, shortcut: normalised)
        actions[identifier] = action
    }

    private func unregister(_ name: String) {
        guard let existing = registrations.removeValue(forKey: name) else {
            return
        }
        UnregisterEventHotKey(existing.reference)
    }

    /// One handler for every hot key, which dispatches on the identifier the
    /// event carries.
    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var type = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed))
        // `self` is a singleton that outlives the handler, so passing it
        // unretained is safe and avoids a cycle that would never be broken.
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData, let event else { return noErr }
                var identifier = EventHotKeyID()
                GetEventParameter(
                    event, EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &identifier)
                let shortcut = Unmanaged<GlobalShortcut>
                    .fromOpaque(userData).takeUnretainedValue()
                shortcut.fire(identifier.id)
                return noErr
            },
            1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    private func fire(_ identifier: UInt32) {
        guard let action = actions[identifier] else { return }
        DispatchQueue.main.async(execute: action)
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
    /// from the character and have to be listed.
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
}
