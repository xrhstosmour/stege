import AppKit
import Foundation
import TOMLDecoder

/// Keeps `outer.top` in `aerospace.toml` equal to what the bar needs on each
/// screen, then asks `AeroSpace` to reload.
///
/// The number used to be written by hand and went stale whenever the bar
/// height changed, and its value for an external display was a guess. The
/// rewrite itself is `AerospaceGaps`, which is the tested part. This is the
/// file and process handling around it.
enum AerospaceGapSync {
    private static let queue = DispatchQueue(
        label: "stege.aerospace-gap-sync", qos: .utility)

    /// Safe to call as often as the configuration or the screens change: the
    /// file is only written, and `AeroSpace` only reloaded, when the line
    /// actually differs.
    static func sync() {
        let configuration = ConfigManager.shared.config
        guard configuration.bar.manageAerospaceGaps else { return }

        let barHeight = configuration.bar.resolveHeight()
        guard !NSScreen.screens.isEmpty else { return }

        // What a display with nothing reserved at its top needs, the most any
        // display needs. Every display not listed below falls to it.
        let fallback = Int((barHeight + BarInset.windowGap).rounded(.up))
        let screens = NSScreen.screens.map { screen in
            AerospaceGaps.Screen(
                name: screen.localizedName, isBuiltIn: isBuiltIn(screen),
                points: BarInset.points(
                    barHeight: barHeight, screenFrame: screen.frame,
                    visibleFrame: screen.visibleFrame))
        }
        let value = AerospaceGaps.outerTopValue(
            entries: AerospaceGaps.entries(for: screens, fallback: fallback),
            fallback: fallback)
        // Built here, on the main thread: it reads the live configuration for
        // the binary's path, which is not safe from the background queue.
        let provider = AerospaceSpacesProvider()
        queue.async { write(value, reloading: provider) }
    }

    private static func write(_ value: String, reloading provider: AerospaceSpacesProvider) {
        guard let url = configurationURL() else { return }
        // Written through the link: a dotfile manager usually symlinks this
        // file, and an atomic write to the link itself would replace it with a
        // regular file the manager no longer owns.
        let target = url.resolvingSymlinksInPath()
        guard let original = try? String(contentsOf: target, encoding: .utf8),
            let modified = modificationDate(of: target)
        else { return }

        guard let rewritten = AerospaceGaps.rewrite(original, outerTop: value)
        else {
            Log.spaces.error(
                "aerospace.toml has an outer.top this cannot edit safely, leaving it alone.")
            return
        }
        guard rewritten != original else { return }

        // The line editor matches text, and TOML has more spellings than it
        // knows. A rewrite that does not parse as TOML would cost the user
        // their whole AeroSpace configuration at the next reload, so a file
        // that parsed before and no longer does is never written.
        if isValidTOML(original), !isValidTOML(rewritten) {
            Log.spaces.error(
                "Rewriting aerospace.toml would make it invalid, leaving it alone.")
            return
        }

        // The backup is what makes the rewrite reversible, so no backup means
        // no rewrite.
        let backup = target.appendingPathExtension("stege-backup")
        if !FileManager.default.fileExists(atPath: backup.path) {
            do {
                try FileManager.default.copyItem(at: target, to: backup)
            } catch {
                Log.spaces.error(
                    "aerospace.toml backup failed, not rewriting: \(error.localizedDescription, privacy: .public)")
                return
            }
        }
        // Saved in an editor since it was read: that edit would be lost to
        // this write, so the next run starts over from the new text.
        guard modificationDate(of: target) == modified else { return }
        do {
            try rewritten.write(to: target, atomically: true, encoding: .utf8)
        } catch {
            Log.spaces.error(
                "aerospace.toml could not be written: \(error.localizedDescription, privacy: .public)")
            return
        }
        provider.reloadConfiguration()
    }

    private static func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[
            .modificationDate] as? Date
    }

    private struct AnyTable: Decodable {}

    private static func isValidTOML(_ text: String) -> Bool {
        (try? TOMLDecoder().decode(AnyTable.self, from: text)) != nil
    }

    /// The first file `AeroSpace` itself would read.
    private static func configurationURL() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let configurationHome =
            ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
            .map { URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".config")
        return [
            home.appendingPathComponent(".aerospace.toml"),
            configurationHome.appendingPathComponent("aerospace/aerospace.toml"),
        ].first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func isBuiltIn(_ screen: NSScreen) -> Bool {
        guard
            let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return false }
        return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0
    }
}
