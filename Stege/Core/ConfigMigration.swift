import Foundation

/// Rewrites a configuration written for an older version of Stege.
///
/// Pure text in, pure text out, with no file system and no logging, so the
/// rename table can be tested without a configuration file existing. The one
/// caller that does touch the disk is `ConfigManager.migrateIfNeeded`.
enum ConfigMigration {
    /// Names that changed, and what they changed to.
    ///
    /// Ordered so a rule cannot half-rewrite a longer name that contains it.
    /// `[experimental.` is last for that reason: it is a prefix rather than a
    /// whole identifier.
    static let renames: [(old: String, new: String)] = [
        ("default.keyboardlayout", "default.keyboardLayout"),
        ("default.applemenu", "default.appleMenu"),
        ("default.appmenus", "default.applicationMenu"),
        ("[experimental.", "[bar."),
    ]

    struct Result: Equatable {
        let text: String
        /// What was rewritten, for the log. Empty means nothing was.
        let applied: [String]

        var isChanged: Bool { !applied.isEmpty }
    }

    /// TOML has no schema, so an unknown table is ignored and an unknown widget
    /// identifier draws nothing. Upgrading past the renames would otherwise
    /// have quietly cost the Apple menu, the application menus, the input
    /// source and every appearance setting, with no error anywhere to say why.
    static func migrate(_ original: String) -> Result {
        var text = original
        var applied: [String] = []
        for rename in renames where text.contains(rename.old) {
            text = text.replacingOccurrences(of: rename.old, with: rename.new)
            applied.append("\(rename.old) to \(rename.new)")
        }
        return Result(text: text, applied: applied)
    }
}
