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
        guard let normalised, let combination = ShortcutParser.parse(normalised) else {
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
}
