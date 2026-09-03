import Foundation

/// Whether a window-manager binary is safe to run.
///
/// `yabai.path` and `aerospace.path` come straight from the user's config
/// file, which is live-reloaded on every write, so a path pointing outside
/// where these binaries are ever actually installed, or a binary another
/// local account could have swapped out, is refused rather than executed.
enum TrustedExecutable {
    /// Where `yabai` and `aerospace` are ever actually installed, matching
    /// `YabaiConfig`'s and `AerospaceConfig`'s own defaults.
    private static let allowedDirectories = [
        "/opt/homebrew/bin/",
        "/usr/local/bin/",
        "/usr/bin/",
    ]

    static func isTrusted(_ path: String) -> Bool {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        guard allowedDirectories.contains(where: { normalized.hasPrefix($0) })
        else {
            return false
        }
        // Follow symlinks: Homebrew's `bin/yabai` is one, and it is the real
        // file's permissions that decide who can overwrite it.
        let resolved = URL(fileURLWithPath: normalized)
            .resolvingSymlinksInPath().path
        guard
            let attributes = try? FileManager.default.attributesOfItem(
                atPath: resolved),
            let permissions = attributes[.posixPermissions] as? Int
        else {
            return false
        }
        let groupOrWorldWritable = 0o022
        return permissions & groupOrWorldWritable == 0
    }
}
