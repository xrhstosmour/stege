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
            # Stege's configuration. Saving this file applies it, no restart.
            #
            # Every setting Stege has is listed below with the values it takes.
            # What is commented out is off; uncomment to turn it on. The fuller
            # reference, with the reasoning behind each one, is at
            # https://github.com/xrhstosmour/stege/blob/main/example/config.toml

            theme = "system"                # system, light, dark
            hidden = false                  # start with the bar out of the way

            # Where yabai or aerospace live, if you did not install them with
            # Homebrew. Only a path inside /opt/homebrew/bin, /usr/local/bin or
            # /usr/bin is accepted, and only if no one but you can write to it.
            # yabai.path = "/run/current-system/sw/bin/yabai"
            # aerospace.path = "/run/current-system/sw/bin/aerospace"

            # System-wide shortcuts. Modifiers then a key joined with "+", at least
            # one modifier. cmd, opt/alt, ctrl, shift, then a letter, digit,
            # punctuation key, space, return, tab, escape, delete, an arrow, or f1
            # to f12. A combination another application already holds is refused,
            # and Stege says so in the system log.
            # toggle-shortcut = "cmd+ctrl+b"  # hide the bar and bring it back
            # reveal-shortcut = "cmd+ctrl+u"  # the other apps' status items
            # menu-shortcut = "cmd+ctrl+m"    # the menus row, then arrows and Return

            [widgets]
            # The bar, left to right. Remove an entry to drop that widget, reorder
            # to move it. "spacer" pushes what follows to the right, "divider"
            # draws a rule.
            #
            # Everything available:
            #   default.appleMenu    default.spaces      default.applicationMenu
            #   default.reveal       default.monitor     default.privacy
            #   default.stayawake    default.notifications
            #   default.updates      default.display     default.audio
            #   default.microphone   default.keyboardLayout
            #   default.bluetooth    default.network     default.battery
            #   default.time         spacer              divider
            displayed = [
                "default.appleMenu",
                "default.spaces",
                "default.applicationMenu",
                "spacer",
                "default.reveal",
                "default.display",
                "default.audio",
                "default.bluetooth",
                "default.network",
                "default.notifications",
                "default.battery",
                "divider",
                "default.time",
            ]

            [widgets.default.appleMenu]
            icon-size = 14
            short-menu = true               # About, Settings, Sleep, Lock, Log Out

            [widgets.default.spaces]
            space.show-key = true           # the workspace number or letter
            window.show-title = true        # the focused window's title
            window.title.max-length = 50
            # Applications whose window title never says which window it is.
            # window.title.always-display-app-name-for = ["Mail", "Chrome"]

            [widgets.default.applicationMenu]
            max-menus = 6
            show-application-name = true
            # always, hover, click, modifier.
            visibility = "hover"
            modifier-key = "option"         # for visibility = "modifier"

            [widgets.default.reveal]
            mode = "extras"                 # extras, hidden, off
            icon-size = 18
            icon-style = "colour"           # colour, mono
            sticky = true                   # stay open until asked to close
            return-threshold = 80
            timeout = 10
            # always-show = ["Docker"]      # never behind the chevron
            # hidden = ["1Password"]        # never shown at all, by name or id

            [widgets.default.monitor]
            show-network = false            # upload and download throughput
            warning-level = 80

            [widgets.default.privacy]
            always-show = false             # a dot even when nothing is listening
            style = "icon"                  # icon, dot

            [widgets.default.stayawake]
            always-show = false

            [widgets.default.notifications]
            show-control-centre = false
            # Off because remembering writes every notification's title, subtitle
            # and body to ~/Library/Preferences in plaintext.
            remember-between-launches = false

            [widgets.default.updates]
            always-show = false             # hidden while nothing is waiting
            show-count = false
            macos = true                    # what macOS found last time it looked
            homebrew = true                 # brew outdated, local data only
            refresh-interval = 30

            [widgets.default.display]
            show-percentage = false

            [widgets.default.audio]
            glyph = "speaker"               # speaker, waves
            show-percentage = false
            fetch-artwork = true            # the one network request Stege makes

            [widgets.default.keyboardLayout]
            show-full-name = false          # "Greek" rather than "GR"

            [widgets.default.bluetooth]
            show-battery = true
            hide-when-off = false

            [widgets.default.network]
            show-name = false
            hide-when-disconnected = false

            [widgets.default.battery]
            style = "inside"                # inside, beside, off
            show-percentage = true
            warning-level = 30
            critical-level = 10

            [widgets.default.time]
            format = "E d MMM  HH:mm"
            calendar.format = "HH:mm"
            calendar.show-events = true
            calendar.countdown = true
            # calendar.allow-list = ["Home"]  # only these calendars
            # calendar.deny-list = ["Work"]   # every calendar but these

            [widgets.default.time.popup]
            view-variant = "box"            # box, vertical

            [bar.foreground]
            height = "menu-bar"             # "menu-bar" or a number of points
            horizontal-padding = 12
            trailing-padding = 12
            spacing = 10

            [bar.background]
            displayed = true
            blur = 7                        # 0 clear to 7 solid
            height = "menu-bar"
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
    ///
    /// Called from UI actions, so the read and the write happen off the main
    /// thread: the file is small and the cost is usually negligible, but
    /// there is no reason to block a button press on disk I/O.
    func updateConfigValue(key: String, rawValue: String) {
        guard let path = configFilePath else {
            Log.configuration.error("No configuration file path is set")
            return
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            do {
                let currentText = try String(
                    contentsOfFile: path, encoding: .utf8)
                let updatedText = TOMLWriter.setting(
                    currentText, key: key, rawValue: rawValue)
                // Atomically, because this is the user's own file and it is
                // rewritten whole. A failure part way through a direct write
                // leaves it truncated, and the file watcher would then reload
                // whatever fragment survived. Writing to a temporary file and
                // renaming means the file on disk is only ever the old one or
                // the new one.
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
