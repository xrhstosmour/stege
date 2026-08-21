import Carbon
import Combine
import Foundation

/// The current keyboard input source.
///
/// Event-driven: the text input system posts a distributed notification when the
/// selected source changes, which is the only moment this value can move.
final class KeyboardLayoutManager: ObservableObject {
    @Published private(set) var abbreviation: String = ""
    @Published private(set) var name: String = ""

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
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
        else { return }
        name = Self.string(from: source, key: kTISPropertyLocalizedName) ?? ""
        abbreviation = Self.abbreviation(for: source, fallback: name)
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

    /// The short code macOS shows in its own menu bar, `ABC` or `EL`.
    ///
    /// Derived from the input source's language rather than by truncating its
    /// name, which would turn "Greek" into "Gre" instead of "EL".
    private static func abbreviation(
        for source: TISInputSource, fallback: String
    ) -> String {
        if let pointer = TISGetInputSourceProperty(
            source, kTISPropertyInputSourceLanguages)
        {
            let languages =
                Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue()
                as? [String] ?? []
            if let language = languages.first {
                // `en` is shown as ABC by macOS, matching the keyboard itself
                // rather than the language.
                if language.hasPrefix("en") { return "ABC" }
                return language.prefix(2).uppercased()
            }
        }
        return String(fallback.prefix(3)).uppercased()
    }
}
