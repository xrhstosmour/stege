import AppKit
import Darwin
import Foundation

/// Now playing straight from the system, whatever is playing it.
///
/// The widget's other source drives `Spotify` and `Music` through AppleScript,
/// which means an Automation grant per application and, more to the point,
/// covers only those two. Anything played in a browser, which is most of what
/// people play, was invisible.
///
/// `MediaRemote` is the system's own now-playing service, the one Control
/// Center's module reads, and every well behaved player publishes to it,
/// browsers included. It is a private framework, so the functions are reached
/// by name, the same way the Bluetooth power switch is.
///
/// Recent macOS restricts the information to entitled callers, and an
/// unentitled one is handed an empty dictionary rather than an error, which is
/// indistinguishable from nothing playing. So this is a source rather than the
/// source: when it answers, it wins, and when it does not the AppleScript path
/// still covers the two applications it always did.
enum MediaRemoteSource {
    struct Snapshot {
        let title: String
        let artist: String
        let isPlaying: Bool
        let position: Double?
        let duration: Double?
        let artwork: NSImage?
        let application: String?
    }

    static var isAvailable: Bool { getNowPlayingInfo != nil }

    /// Asks the system what is playing. The answer arrives on `queue`.
    static func read(
        into queue: DispatchQueue = .main,
        completion: @escaping (Snapshot?) -> Void
    ) {
        guard let get = getNowPlayingInfo else {
            queue.async { completion(nil) }
            return
        }
        // Never the main queue: the caller may be waiting on it, and the
        // callback would then never run.
        get(callbackQueue) { information in
            let snapshot = Self.snapshot(from: information)
            queue.async { completion(snapshot) }
        }
    }

    private static func snapshot(from information: [String: Any]) -> Snapshot? {
        let title = information[
            "kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
        let artist = information[
            "kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
        // An empty dictionary means nothing is playing, or that this build of
        // macOS withholds it. Either way there is nothing to show.
        guard !title.isEmpty || !artist.isEmpty else { return nil }

        let rate = information["kMRMediaRemoteNowPlayingInfoPlaybackRate"]
            as? Double
        let artwork =
            (information["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data)
            .flatMap(NSImage.init(data:))

        return Snapshot(
            title: title,
            artist: artist,
            isPlaying: (rate ?? 0) > 0,
            position: information["kMRMediaRemoteNowPlayingInfoElapsedTime"]
                as? Double,
            duration: information["kMRMediaRemoteNowPlayingInfoDuration"]
                as? Double,
            artwork: artwork,
            application: nil)
    }

    private static let callbackQueue = DispatchQueue(
        label: "stege.mediaremote", qos: .userInitiated)

    private typealias GetNowPlayingInfo = @convention(c) (
        DispatchQueue, @escaping ([String: Any]) -> Void
    ) -> Void

    private static let handle: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
        RTLD_LAZY)

    private static let getNowPlayingInfo: GetNowPlayingInfo? = {
        guard let handle,
            let symbol = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo")
        else { return nil }
        return unsafeBitCast(symbol, to: GetNowPlayingInfo.self)
    }()
}
