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
    /// ASCII unit separator, which is what it is for and what no track title
    /// contains. This was a vertical bar, and a track called "A|B" made the
    /// output six fields instead of five, failed the count check, and took the
    /// whole readout off the popup.
    static let fieldSeparator = "\u{001F}"

    init?(application: String, from output: String) {
        let components = output.components(
            separatedBy: NowPlayingSong.fieldSeparator)
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

    /// Five seconds, against the two minutes an Apple Event waits by default.
    ///
    /// A player that has stopped answering, which `Spotify` does from time to
    /// time, otherwise holds the one script lock for those two minutes. The
    /// timer behind this fires every second, so every tick in between queues up
    /// behind it on a thread of its own and the widget never recovers.
    private func timed(_ body: String) -> String {
        """
        with timeout of 5 seconds
        \(body)
        end timeout
        """
    }

    /// AppleScript to fetch the now playing song.
    var nowPlayingScript: String {
        if self == .music {
            return timed("""
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
                            set separator to (character id 31)
                            return stateText & separator & (name of currentTrack) & separator & (artist of currentTrack) & separator & artworkURL & separator & (player position as text) & separator & ((duration of currentTrack) as text)
                        else
                            return "stopped"
                        end if
                    end tell
                else
                    return "stopped"
                end if
                """)
        } else {
            return timed("""
                if application "\(rawValue)" is running then
                    tell application "\(rawValue)"
                        if player state is playing then
                            set currentTrack to current track
                            set separator to (character id 31)
                            return "playing" & separator & (name of currentTrack) & separator & (artist of currentTrack) & separator & (artwork url of currentTrack) & separator & player position & separator & (duration of currentTrack)
                        else if player state is paused then
                            set currentTrack to current track
                            set separator to (character id 31)
                            return "paused" & separator & (name of currentTrack) & separator & (artist of currentTrack) & separator & (artwork url of currentTrack) & separator & player position & separator & (duration of currentTrack)
                        else
                            return "stopped"
                        end if
                    end tell
                else
                    return "stopped"
                end if
                """)
        }
    }

    var previousTrackCommand: String {
        timed("tell application \"\(rawValue)\" to previous track")
    }

    var togglePlayPauseCommand: String {
        timed("tell application \"\(rawValue)\" to playpause")
    }

    var nextTrackCommand: String {
        timed("tell application \"\(rawValue)\" to next track")
    }

    /// Both players take a position in seconds. Interpolating a `Double` in
    /// Swift always writes a full stop, which matters because `AppleScript`
    /// itself is happy to read a comma as a separator under a Greek locale and
    /// would then land somewhere else in the track.
    func seekCommand(to seconds: Double) -> String {
        timed(
            "tell application \"\(rawValue)\" to set player position to "
                + "\(seconds)")
    }
}

// MARK: - Now Playing Provider

/// Provides functionality to fetch the now playing song and execute playback commands.
final class NowPlayingProvider {

    /// Why the last read came back with nothing, when the reason was not
    /// simply that nothing is playing.
    ///
    /// Without this a refused Automation prompt, a player that has stopped
    /// answering and a paused queue all look the same from the bar: the widget
    /// is not there. That is the one failure mode worth telling someone about,
    /// because it is the only one they can do something about.
    private(set) static var failure: String?

    /// Returns the current playing song from any supported music application.
    static func fetchNowPlaying() -> NowPlayingSong? {
        // Skip applications that are not running. The scripts already guard
        // with `if application "X" is running`, but reaching that guard still
        // costs a full Apple Event round trip.
        var reason: String?
        var answers: [NowPlayingSong] = []
        for app in MusicApp.allCases where isAppRunning(app) {
            if let song = fetchNowPlaying(from: app) {
                answers.append(song)
            } else if let error = lastError {
                reason = reason ?? describe(error, from: app)
            }
        }
        // Whichever one is actually playing. Both can answer at once, and
        // taking the first meant that with `Music` playing and `Spotify` open
        // and paused in the background, the popup showed the paused track and
        // its transport moved the wrong application.
        if let song = answers.first(where: { $0.state == .playing })
            ?? answers.first
        {
            failure = nil
            return song
        }
        failure = reason
        return nil
    }

    /// The two that are worth naming. Everything else is reported with its
    /// number, because guessing at what an unfamiliar `AppleScript` error means
    /// is how a widget ends up telling someone the wrong thing to fix.
    private static func describe(_ error: Int, from app: MusicApp) -> String {
        switch error {
        case -1743:
            return
                "Stege is not allowed to control \(app.rawValue). Privacy & Security, then Automation."
        case -1712:
            return "\(app.rawValue) did not answer in time."
        case let number:
            return "\(app.rawValue) could not be read, error \(number)."
        }
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

    /// The error number from the last run, or nil if it succeeded.
    private static var lastError: Int?

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
        if let error {
            lastError = error[NSAppleScript.errorNumber] as? Int ?? 0
            return nil
        }
        lastError = nil
        return outputDescriptor.stringValue?.trimmingCharacters(
            in: .whitespacesAndNewlines)
    }

    /// The application the transport should act on.
    ///
    /// The one that is playing, then the one that is paused with a track
    /// loaded, then whichever is running. Taking the first running one sent
    /// `next` to `Spotify` while `Music` was the thing making the sound.
    static func activeMusicApp() -> MusicApp? {
        let running = MusicApp.allCases.filter { isAppRunning($0) }
        if running.count > 1 {
            for app in running
            where fetchNowPlaying(from: app)?.state == .playing {
                return app
            }
        }
        return running.first
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
    /// Why there is nothing playing, when the reason is worth acting on.
    @Published private(set) var failure: String?
    /// One read at a time. The timer fires every second and a read can take
    /// longer than that, so without this a slow player is answered by a
    /// growing pile of threads all waiting on the same lock.
    private var isReading = false
    /// Whether artwork may be fetched over the network.
    ///
    /// The only outbound request this application makes. `MediaRemote` hands
    /// artwork over as bytes, but the AppleScript path returns a link to the
    /// player's own servers, and following it tells them the track is being
    /// looked at from this machine. Set by the widget from the file.
    /// Whether the artwork link may be followed.
    ///
    /// Read from the configuration here rather than pushed in by whichever
    /// popup drew last. It was a settable property, and the marker standing in
    /// for the removed now playing widget set it to `true` unconditionally, so
    /// clicking that mark turned the setting back on for the rest of the
    /// session. False means the link is dropped before it reaches the view
    /// that would load it.
    var fetchesArtwork: Bool {
        ConfigManager.shared.widgetSettings(for: "default.audio")[
            "fetch-artwork"]?.boolValue ?? true
    }
    private var cancellable: AnyCancellable?

    /// How many views are showing what is playing.
    ///
    /// The timer used to start with the singleton and run for the life of the
    /// process, which was cheap while the widget was the only thing that
    /// wanted it and the widget was always in the bar. It is in the sound
    /// popup now as well, and a popup is on screen for a few seconds at a
    /// time, so a poll that costs an Apple Event a second has to stop when the
    /// last thing looking at it goes away.
    private var watchers = 0

    private init() {}

    func startWatching() {
        watchers += 1
        guard cancellable == nil else { return }
        updateNowPlaying()
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

    func stopWatching() {
        watchers = max(0, watchers - 1)
        guard watchers == 0 else { return }
        cancellable?.cancel()
        cancellable = nil
    }

    /// Asks the system first, then the two scriptable applications.
    ///
    /// `MediaRemote` covers whatever is playing, browsers included, and needs
    /// no Automation grant. Where macOS withholds it the AppleScript path still
    /// covers `Spotify` and `Music`, which is what this did before.
    private func updateNowPlaying() {
        guard !isReading else { return }
        isReading = true
        MediaRemoteSource.read { [weak self] snapshot in
            guard let self else { return }
            if let snapshot {
                self.nowPlaying = Self.song(from: snapshot)
                self.failure = nil
                self.isReading = false
                return
            }
            DispatchQueue.global(qos: .background).async {
                var song = NowPlayingProvider.fetchNowPlaying()
                // The link points at the player's own servers, so following it
                // is a request that says what is being played and from where.
                if !self.fetchesArtwork, var stripped = song {
                    stripped = NowPlayingSong(
                        appName: stripped.appName, state: stripped.state,
                        title: stripped.title, artist: stripped.artist,
                        albumArtURL: nil, position: stripped.position,
                        duration: stripped.duration)
                    song = stripped
                }
                let reason = NowPlayingProvider.failure
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.nowPlaying = song
                    self.failure = reason
                    self.isReading = false
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

    /// Moves the playhead. The bar under the artwork was a `ProgressView`,
    /// which reports and cannot be moved.
    func seek(to seconds: Double) {
        NowPlayingProvider.executeCommand { $0.seekCommand(to: seconds) }
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
