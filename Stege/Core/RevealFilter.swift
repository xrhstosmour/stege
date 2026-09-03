import Foundation

/// Whether a borrowed menu bar item is on one of the reveal row's lists.
///
/// The lists, `hidden` and `always-show`, are written from two directions. The
/// row's own right-click writes a bundle identifier, which survives a rename
/// and a translated interface. A person editing the configuration file writes
/// what they can see, which is the application's name, because nothing in the
/// bar or in macOS's own settings ever shows them `com.1password.1password`.
///
/// So an entry is compared against both, and a list may hold a mixture of the
/// two without anybody having to know which kind they wrote.
enum RevealFilter {
    /// One entry as it is compared: case folded, trimmed, and without the
    /// `.app` that a name copied out of Finder carries. Both sides go through
    /// this, so stripping the suffix cannot make two different things equal.
    private static func normalised(_ value: String) -> String {
        var folded = value.trimmingCharacters(in: .whitespaces).lowercased()
        if folded.hasSuffix(".app") { folded.removeLast(4) }
        return folded
    }

    static func matches(
        bundleIdentifier: String?, name: String, list: [String]
    ) -> Bool {
        guard !list.isEmpty else { return false }
        return matches(
            bundleIdentifier: bundleIdentifier, name: name,
            in: normalisedSet(list))
    }

    /// A list, normalised once, ready to be checked against many items
    /// without re-normalising the same list on every one.
    static func normalisedSet(_ list: [String]) -> Set<String> {
        Set(list.map(normalised).filter { !$0.isEmpty })
    }

    /// Same check as `matches(bundleIdentifier:name:list:)`, against a list
    /// already normalised by `normalisedSet(_:)`.
    static func matches(
        bundleIdentifier: String?, name: String, in entries: Set<String>
    ) -> Bool {
        guard !entries.isEmpty else { return false }
        if let bundleIdentifier, entries.contains(normalised(bundleIdentifier))
        {
            return true
        }
        let candidate = normalised(name)
        return !candidate.isEmpty && entries.contains(candidate)
    }

    /// What a right-click writes into the list: the bundle identifier when the
    /// application has one, the name when it does not, and nothing at all when
    /// it has neither, which would otherwise write an entry matching every
    /// application without a name.
    static func entry(bundleIdentifier: String?, name: String) -> String? {
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            return bundleIdentifier
        }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The list as a TOML array, ready to be written back to the file.
    ///
    /// Escaped, because these are names rather than identifiers and a name can
    /// hold a quote. An unescaped one would leave the configuration file
    /// unparseable, and the file is the only place the list lives.
    static func tomlArray(_ list: [String]) -> String {
        let quoted = list.map { entry -> String in
            let escaped = entry
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        return "[\(quoted.joined(separator: ", "))]"
    }
}
