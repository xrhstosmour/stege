import Foundation
import SwiftUI
import TOMLDecoder

final class ConfigManager: ObservableObject {
    static let shared = ConfigManager()

    @Published private(set) var config = Config()
    @Published private(set) var initError: String?
    
    private var fileWatchSource: DispatchSourceFileSystemObject?
    private var fileDescriptor: CInt = -1
    private var configFilePath: String?

    private init() {
        loadOrCreateConfigIfNeeded()
    }

    private func loadOrCreateConfigIfNeeded() {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        let path1 = "\(homePath)/.stege-config.toml"
        let path2 = "\(homePath)/.config/stege/config.toml"
        var chosenPath: String?

        if FileManager.default.fileExists(atPath: path1) {
            chosenPath = path1
        } else if FileManager.default.fileExists(atPath: path2) {
            chosenPath = path2
        } else {
            do {
                try createDefaultConfig(at: path1)
                chosenPath = path1
            } catch {
                initError = "Error creating default config: \(error.localizedDescription)"
                Log.configuration.error(
                    "Could not write a default configuration: \(error.localizedDescription, privacy: .public)")
                return
            }
        }

        if let path = chosenPath {
            configFilePath = path
            migrateIfNeeded(at: path)
            parseConfigFile(at: path)
            startWatchingFile(at: path)
        }
    }

    /// Rewrites a configuration written for an older version, once, in place.
    ///
    /// The rename table and the rewriting live in `ConfigMigration`, which
    /// takes text and returns text, so they can be tested without a file. This
    /// is the half that touches the disk.
    ///
    /// The original is kept beside the file as `.backup` before anything is
    /// written, because this edits something the user owns.
    private func migrateIfNeeded(at path: String) {
        guard let original = try? String(contentsOfFile: path, encoding: .utf8)
        else { return }

        let result = ConfigMigration.migrate(original)
        guard result.isChanged else { return }

        let backup = path + ".backup"
        do {
            try? FileManager.default.removeItem(atPath: backup)
            try original.write(toFile: backup, atomically: true, encoding: .utf8)
            try result.text.write(toFile: path, atomically: true, encoding: .utf8)
            Log.configuration.notice(
                "Migrated the configuration: \(result.applied.joined(separator: ", "), privacy: .public). The original is at \(backup, privacy: .public)")
        } catch {
            Log.configuration.error(
                "Could not migrate the configuration: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func parseConfigFile(at path: String) {
        do {
            let content = try String(contentsOfFile: path, encoding: .utf8)
            let decoder = TOMLDecoder()
            let rootToml = try decoder.decode(RootToml.self, from: content)
            DispatchQueue.main.async {
                self.config = Config(rootToml: rootToml)
            }
        } catch {
            // `initError` is `@Published`, and this runs on the file watch
            // queue, so it has to hop to the main thread like `config` does.
            let message = "Error parsing TOML file: \(error.localizedDescription)"
            DispatchQueue.main.async { self.initError = message }
            Log.configuration.error(
                "Could not parse the configuration: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func createDefaultConfig(at path: String) throws {
        let defaultTOML = """
            # If you installed yabai or aerospace without using Homebrew,
            # manually set the path to the binary. For example:
            #
            # yabai.path = "/run/current-system/sw/bin/yabai"
            # aerospace.path = ...
            
            theme = "system" # system, light, dark

            [widgets]
            displayed = [ # widgets on menu bar
                "default.spaces",
                "spacer",
                "default.network",
                "default.battery",
                "divider",
                # { "default.time" = { time-zone = "America/Los_Angeles", format = "E d, hh:mm" } },
                "default.time"
            ]

            [widgets.default.spaces]
            space.show-key = true        # show space number (or character, if you use AeroSpace)
            window.show-title = true
            window.title.max-length = 50

            [widgets.default.battery]
            show-percentage = true
            warning-level = 30
            critical-level = 10

            [widgets.default.time]
            format = "E d, J:mm"
            calendar.format = "J:mm"

            calendar.show-events = true
            # calendar.allow-list = ["Home", "Personal"] # show only these calendars
            # calendar.deny-list = ["Work", "Boss"] # show all calendars except these

            [widgets.default.time.popup]
            view-variant = "box"

            [bar.background]
            displayed = true
            """
        try defaultTOML.write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// Watches the configuration file for changes.
    ///
    /// `.rename` and `.delete` matter as much as `.write`. Most editors save
    /// atomically, writing a temporary file and renaming it over the original,
    /// which replaces the inode. A descriptor opened on the old inode then
    /// never reports anything again, so watching only `.write` means live
    /// reload silently stops working after the first edit made in a real
    /// editor. On those events the watch is torn down and re-established
    /// against the new file.
    private func startWatchingFile(at path: String) {
        stopWatchingFile()

        fileDescriptor = open(path, O_EVTONLY)
        if fileDescriptor == -1 { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete, .extend],
            queue: DispatchQueue.global())

        source.setEventHandler { [weak self] in
            guard let self, let path = self.configFilePath else { return }
            let events = source.data

            self.parseConfigFile(at: path)

            if events.contains(.rename) || events.contains(.delete) {
                // Re-open against whatever now lives at the path. A small delay
                // lets the replacing file land before the descriptor is taken.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.startWatchingFile(at: path)
                }
            }
        }

        source.setCancelHandler { [fileDescriptor] in
            if fileDescriptor != -1 { close(fileDescriptor) }
        }

        fileWatchSource = source
        source.resume()
    }

    private func stopWatchingFile() {
        fileWatchSource?.cancel()
        fileWatchSource = nil
        // The cancel handler owns closing the descriptor.
        fileDescriptor = -1
    }

    func updateConfigValue(key: String, newValue: String) {
        updateConfigValue(key: key, rawValue: "\"\(newValue)\"")
    }

    /// Writes the value exactly as given, for anything that is not a string:
    /// an array, a number, a boolean.
    func updateConfigValue(key: String, rawValue: String) {
        guard let path = configFilePath else {
            Log.configuration.error("No configuration file path is set")
            return
        }
        do {
            let currentText = try String(contentsOfFile: path, encoding: .utf8)
            let updatedText = updatedTOMLString(
                original: currentText, key: key, rawValue: rawValue)
            // Atomically, because this is the user's own file and it is
            // rewritten whole. A failure part way through a direct write leaves
            // it truncated, and the file watcher would then reload whatever
            // fragment survived. Writing to a temporary file and renaming means
            // the file on disk is only ever the old one or the new one.
            try updatedText.write(
                toFile: path, atomically: true, encoding: .utf8)
            DispatchQueue.main.async {
                self.parseConfigFile(at: path)
            }
        } catch {
            Log.configuration.error(
                "Could not update the configuration: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func updatedTOMLString(
        original: String, key: String, rawValue: String
    ) -> String {
        if key.contains(".") {
            let components = key.split(separator: ".").map(String.init)
            guard components.count >= 2 else {
                return original
            }

            let tablePath = components.dropLast().joined(separator: ".")
            let actualKey = components.last!

            let tableHeader = "[\(tablePath)]"
            let lines = original.components(separatedBy: "\n")
            var newLines: [String] = []
            var insideTargetTable = false
            var updatedKey = false
            var foundTable = false

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                    if insideTargetTable && !updatedKey {
                        newLines.append("\(actualKey) = \(rawValue)")
                        updatedKey = true
                    }
                    if trimmed == tableHeader {
                        foundTable = true
                        insideTargetTable = true
                    } else {
                        insideTargetTable = false
                    }
                    newLines.append(line)
                } else {
                    if insideTargetTable && !updatedKey {
                        let pattern =
                            "^\(NSRegularExpression.escapedPattern(for: actualKey))\\s*="
                        if line.range(of: pattern, options: .regularExpression)
                            != nil
                        {
                            newLines.append("\(actualKey) = \(rawValue)")
                            updatedKey = true
                            continue
                        }
                    }
                    newLines.append(line)
                }
            }

            if foundTable && insideTargetTable && !updatedKey {
                newLines.append("\(actualKey) = \(rawValue)")
            }

            if !foundTable {
                newLines.append("")
                newLines.append("[\(tablePath)]")
                newLines.append("\(actualKey) = \(rawValue)")
            }
            return newLines.joined(separator: "\n")
        } else {
            let lines = original.components(separatedBy: "\n")
            var newLines: [String] = []
            var updatedAtLeastOnce = false

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.hasPrefix("#") {
                    let pattern =
                        "^\(NSRegularExpression.escapedPattern(for: key))\\s*="
                    if line.range(of: pattern, options: .regularExpression)
                        != nil
                    {
                        newLines.append("\(key) = \(rawValue)")
                        updatedAtLeastOnce = true
                        continue
                    }
                }
                newLines.append(line)
            }
            if !updatedAtLeastOnce {
                newLines.append("\(key) = \(rawValue)")
            }
            return newLines.joined(separator: "\n")
        }
    }

    func globalWidgetConfig(for widgetId: String) -> ConfigData {
        config.rootToml.widgets.config(for: widgetId) ?? [:]
    }

    /// A widget's settings as the bar resolves them, inline parameters and all,
    /// for code that is not the widget and so has no `ConfigProvider`.
    ///
    /// Falls back to the global block when the widget is not in the bar at all,
    /// so a setting still reads correctly for something drawn from a popup.
    func widgetSettings(for widgetId: String) -> ConfigData {
        guard
            let item = config.rootToml.widgets.displayed.first(where: {
                $0.id == widgetId
            })
        else { return globalWidgetConfig(for: widgetId) }
        return resolvedWidgetConfig(for: item)
    }

    func resolvedWidgetConfig(for item: TomlWidgetItem) -> ConfigData {
        let global = globalWidgetConfig(for: item.id)
        if item.inlineParams.isEmpty {
            return global
        }
        var merged = global
        for (key, value) in item.inlineParams {
            merged[key] = value
        }
        return merged
    }
}
