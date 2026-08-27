import Carbon
import Combine
import Foundation

/// One selectable keyboard input source.
struct KeyboardInputSource: Identifiable {
    let id: String
    let name: String
    let code: String
    let source: TISInputSource
}

/// The current keyboard input source, and the ones that can be switched to.
///
/// Event-driven: the text input system posts a distributed notification when the
/// selected source changes, which is the only moment this value can move.
final class KeyboardLayoutManager: ObservableObject {
    @Published private(set) var abbreviation: String = ""
    @Published private(set) var name: String = ""
    /// Everything enabled in Keyboard settings, so the popup offers exactly
    /// what the system's own input menu does.
    @Published private(set) var sources: [KeyboardInputSource] = []
    @Published private(set) var currentID: String = ""

    private var observer: NSObjectProtocol?

    init() {
        refresh()
        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(
                kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        if let observer {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }

    private func refresh() {
        sources = Self.selectableSources()
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
        else { return }
        name = Self.string(from: source, key: kTISPropertyLocalizedName) ?? ""
        abbreviation = Self.abbreviation(for: source, fallback: name)
        currentID = Self.string(from: source, key: kTISPropertyInputSourceID) ?? ""
    }

    /// Switches the system's input source, which is what the menu bar's own
    /// input menu does.
    ///
    /// The notification alone is not enough here. It arrives before this
    /// process's own view of the current source has caught up, so the read it
    /// triggers returns the source that was just replaced and the bar goes on
    /// showing it. Switching to `ABC` from the popup left the bar reading `EL`
    /// indefinitely while the system was already on `ABC`. So the change is
    /// also read back a few times afterwards, stopping as soon as it lands.
    func select(_ source: KeyboardInputSource) {
        let previous = currentID
        TISSelectInputSource(source.source)
        readBack(until: previous, attempt: 0)
    }

    private func readBack(until previous: String, attempt: Int) {
        guard attempt < 6 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            self.refresh()
            guard self.currentID == previous else { return }
            self.readBack(until: previous, attempt: attempt + 1)
        }
    }

    /// Keyboard layouts and input modes that the user has enabled, filtered the
    /// same way the system input menu filters them. Palettes and the character
    /// viewer are input sources too, and would otherwise be offered as things
    /// to type in.
    private static func selectableSources() -> [KeyboardInputSource] {
        let filter =
            [
                kTISPropertyInputSourceIsEnableCapable as String: true,
                kTISPropertyInputSourceIsSelectCapable as String: true,
            ] as CFDictionary
        guard
            let list = TISCreateInputSourceList(filter, false)?
                .takeRetainedValue() as? [TISInputSource]
        else { return [] }

        return list.compactMap { source in
            guard
                let category = string(
                    from: source, key: kTISPropertyInputSourceCategory),
                category == (kTISCategoryKeyboardInputSource as String),
                let identifier = string(
                    from: source, key: kTISPropertyInputSourceID),
                let name = string(from: source, key: kTISPropertyLocalizedName)
            else { return nil }
            return KeyboardInputSource(
                id: identifier, name: name,
                code: abbreviation(for: source, fallback: name),
                source: source)
        }
    }

    private static func string(
        from source: TISInputSource, key: CFString
    ) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue()
            as String
    }

    /// The region's two-letter code, `US` or `GR`.
    ///
    /// macOS writes `ABC` for the US keyboard and the language code for the
    /// rest, which reads as two different kinds of thing in the same slot.
    /// Every input source resolves to a region instead, so the width never
    /// changes and every layout is labelled the same way.
    ///
    /// The region comes from the input source's own identifier when it ends in
    /// one, `com.apple.keylayout.US`, and otherwise from the language: CLDR
    /// knows which region a language is most likely written in, which is how
    /// `el` becomes `GR`.
    private static func abbreviation(
        for source: TISInputSource, fallback: String
    ) -> String {
        if let identifier = string(from: source, key: kTISPropertyInputSourceID),
            let last = identifier.split(separator: ".").last, last.count == 2,
            last.allSatisfy({ $0.isUppercase })
        {
            return String(last)
        }
        if let pointer = TISGetInputSourceProperty(
            source, kTISPropertyInputSourceLanguages)
        {
            let languages =
                Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue()
                as? [String] ?? []
            if let language = languages.first {
                if let region = Locale.Language(identifier: language).region?
                    .identifier, region.count == 2
                {
                    return region.uppercased()
                }
                return language.prefix(2).uppercased()
            }
        }
        return String(fallback.prefix(2)).uppercased()
    }
}
