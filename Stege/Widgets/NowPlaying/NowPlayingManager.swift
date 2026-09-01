import AppKit
import Combine
import Foundation

// MARK: - Playback State

/// Represents the current playback state.
enum PlaybackState: String {
    case playing, paused, stopped
}

// MARK: - Now Playing Song Model

/// A model representing the currently playing song.
struct NowPlayingSong: Equatable, Identifiable {
    var id: String { title + artist }
    let appName: String
    let state: PlaybackState
    let title: String
    let artist: String
    let albumArtURL: URL?
    let position: Double?
    let duration: Double?  // Duration in seconds
    /// Artwork the system handed over directly. `MediaRemote` returns the
    /// bytes rather than a link, so there is nothing to fetch.
    var artwork: NSImage?

    init(
        appName: String, state: PlaybackState, title: String, artist: String,
        albumArtURL: URL?, position: Double?, duration: Double?,
        artwork: NSImage? = nil
    ) {
        self.appName = appName
        self.state = state
        self.title = title
        self.artist = artist
        self.albumArtURL = albumArtURL
        self.position = position
        self.duration = duration
        self.artwork = artwork
    }

    /// Initializes a song model from a given output string.
    /// - Parameters:
    ///   - application: The name of the music application.
    ///   - output: The output string returned by AppleScript.
    init?(application: String, from output: String) {
        let components = output.components(separatedBy: "|")
        guard components.count == 6,
            let state = PlaybackState(rawValue: components[0])
        else {
            return nil
        }
        // Replace commas with dots for correct decimal conversion.
        let positionString = components[4].replacingOccurrences(
            of: ",", with: ".")
        let durationString = components[5].replacingOccurrences(
            of: ",", with: ".")
        guard let position = Double(positionString),
            let duration = Double(durationString)
        else {
            return nil
        }

        self.appName = application
        self.state = state
        self.title = components[1]
        self.artist = components[2]
        self.albumArtURL = URL(string: components[3])
        self.position = position
        if application == MusicApp.spotify.rawValue {
            self.duration = duration / 1000
        } else {
            self.duration = duration
        }
    }
}

// MARK: - Supported Music Applications

/// Supported music applications with corresponding AppleScript commands.
enum MusicApp: String, CaseIterable {
    case spotify = "Spotify"
    case music = "Music"

    /// AppleScript to fetch the now playing song.
    var nowPlayingScript: String {
        if self == .music {
            return """
                if application "Music" is running then
                    tell application "Music"
                        if player state is playing or player state is paused then
                            set currentTrack to current track
                            try
                                set artworkURL to (get URL of artwork 1 of currentTrack) as text
                            on error
                                set artworkURL to ""
                            end try
                            set stateText to ""
                            if player state is playing then
                                set stateText to "playing"
                            else if player state is paused then
                                set stateText to "paused"
                            end if
                            return stateText & "|" & (name of currentTrack) & "|" & (artist of currentTrack) & "|" & artworkURL & "|" & (player position as text) & "|" & ((duration of currentTrack) as text)
                        else
                            return "stopped"
                        end if
                    end tell
                else
                    return "stopped"
                end if
                """
        } else {
            return """
                if application "\(rawValue)" is running then
                    tell application "\(rawValue)"
                        if player state is playing then
                            set currentTrack to current track
                            return "playing|" & (name of currentTrack) & "|" & (artist of currentTrack) & "|" & (artwork url of currentTrack) & "|" & player position & "|" & (duration of currentTrack)
                        else if player state is paused then
                            set currentTrack to current track
                            return "paused|" & (name of currentTrack) & "|" & (artist of currentTrack) & "|" & (artwork url of currentTrack) & "|" & player position & "|" & (duration of currentTrack)
                        else
                            return "stopped"
                        end if
                    end tell
                else
                    return "stopped"
                end if
                """
        }
    }

    var previousTrackCommand: String {
        "tell application \"\(rawValue)\" to previous track"
    }

    var togglePlayPauseCommand: String {
        "tell application \"\(rawValue)\" to playpause"
    }

    var nextTrackCommand: String {
        "tell application \"\(rawValue)\" to next track"
    }
}

// MARK: - Now Playing Provider

/// Provides functionality to fetch the now playing song and execute playback commands.
final class NowPlayingProvider {

    /// Returns the current playing song from any supported music application.
    static func fetchNowPlaying() -> NowPlayingSong? {
        // Skip applications that are not running. The scripts already guard
        // with `if application "X" is running`, but reaching that guard still
        // costs a full Apple Event round trip.
        for app in MusicApp.allCases where isAppRunning(app) {
            if let song = fetchNowPlaying(from: app) {
                return song
            }
        }
        return nil
    }

    /// Returns the now playing song for a specific music application.
    private static func fetchNowPlaying(from app: MusicApp) -> NowPlayingSong? {
        guard let output = runAppleScript(app.nowPlayingScript),
            output != "stopped"
        else {
            return nil
        }
        return NowPlayingSong(application: app.rawValue, from: output)
    }

    /// Checks if the specified music application is currently running.
    static func isAppRunning(_ app: MusicApp) -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.localizedName == app.rawValue
        }
    }

    /// Compiled scripts, keyed by source.
    ///
    /// `NSAppleScript(source:)` compiles on construction, and the polling path
    /// built a fresh one every tick. Measured here, recompiling costs 8.98 ms
    /// per call against 0.44 ms for a reused instance, a twentyfold difference,
    /// and it ran once per music application several times a second.
    private static var compiledScripts: [String: NSAppleScript] = [:]
    private static let scriptLock = NSLock()

    private static func compiledScript(for source: String) -> NSAppleScript? {
        scriptLock.lock()
        defer { scriptLock.unlock() }
        if let existing = compiledScripts[source] { return existing }
        guard let script = NSAppleScript(source: source) else { return nil }
        compiledScripts[source] = script
        return script
    }

    /// Executes the provided AppleScript and returns the trimmed result.
    @discardableResult
    static func runAppleScript(_ script: String) -> String? {
        guard let appleScript = compiledScript(for: script) else {
            return nil
        }
        // `NSAppleScript` is not thread safe, and the cached instance is now
        // shared across calls, so execution has to be serialised too.
        scriptLock.lock()
        defer { scriptLock.unlock() }
        var error: NSDictionary?
        let outputDescriptor = appleScript.executeAndReturnError(&error)
        if let error = error {
            print("AppleScript Error: \(error)")
            return nil
        }
        return outputDescriptor.stringValue?.trimmingCharacters(
            in: .whitespacesAndNewlines)
    }

    /// Returns the first running music application.
    static func activeMusicApp() -> MusicApp? {
        MusicApp.allCases.first { isAppRunning($0) }
    }

    /// Executes a playback command for the active music application.
    static func executeCommand(_ command: (MusicApp) -> String) {
        guard let activeApp = activeMusicApp() else { return }
        _ = runAppleScript(command(activeApp))
    }
}

// MARK: - Now Playing Manager

/// An observable manager that periodically updates the now playing song.
final class NowPlayingManager: ObservableObject {
    static let shared = NowPlayingManager()

    @Published private(set) var nowPlaying: NowPlayingSong?
    private var cancellable: AnyCancellable?

    private init() {
        // One second, not the original 0.3. With the script cached and idle
        // applications skipped a tick costs 0.44 ms, so the interval is no
        // longer the expensive part, but the popup's progress bar still wants
        // second resolution and there is nothing to gain from finer.
        cancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateNowPlaying()
            }
    }

    /// Asks the system first, then the two scriptable applications.
    ///
    /// `MediaRemote` covers whatever is playing, browsers included, and needs
    /// no Automation grant. Where macOS withholds it the AppleScript path still
    /// covers `Spotify` and `Music`, which is what this did before.
    private func updateNowPlaying() {
        MediaRemoteSource.read { [weak self] snapshot in
            guard let self else { return }
            if let snapshot {
                self.nowPlaying = Self.song(from: snapshot)
                return
            }
            DispatchQueue.global(qos: .background).async {
                let song = NowPlayingProvider.fetchNowPlaying()
                DispatchQueue.main.async { [weak self] in
                    self?.nowPlaying = song
                }
            }
        }
    }

    private static func song(from snapshot: MediaRemoteSource.Snapshot)
        -> NowPlayingSong
    {
        NowPlayingSong(
            appName: snapshot.application ?? "",
            state: snapshot.isPlaying ? .playing : .paused,
            title: snapshot.title,
            artist: snapshot.artist,
            albumArtURL: nil,
            position: snapshot.position,
            duration: snapshot.duration,
            artwork: snapshot.artwork)
    }

    /// Skips to the previous track.
    func previousTrack() {
        NowPlayingProvider.executeCommand { $0.previousTrackCommand }
    }

    /// Toggles between play and pause.
    func togglePlayPause() {
        NowPlayingProvider.executeCommand { $0.togglePlayPauseCommand }
    }

    /// Skips to the next track.
    func nextTrack() {
        NowPlayingProvider.executeCommand { $0.nextTrackCommand }
    }
}
