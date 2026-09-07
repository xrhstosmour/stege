import Combine
import Foundation

/// Reports whether Location Services is in use by any application.
///
/// Replacing the menu bar hides the indicator macOS would otherwise draw for
/// this, and unlike microphone/camera/screen recording it gets no corner dot
/// of its own, so it disappears entirely once the real menu bar is set to
/// auto-hide. This restores that signal.
final class LocationManager: ObservableObject {
    /// One instance. Location activity is a property of the machine, not of
    /// a bar, and there is one bar per screen.
    static let shared = LocationManager()

    @Published private(set) var isLocationInUse = false

    private var timer: Timer?
    /// One read at a time. A slow answer must not queue the next tick behind it.
    private var isReading = false

    /// Control Center exposes no notification for this, only its own
    /// `AXDescription` changing, so it is polled the same way screen
    /// recording used to be.
    private let interval: TimeInterval = 2.0

    private init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) {
            [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        timer?.invalidate()
    }

    /// Off the main thread: this crosses into Control Center over the
    /// accessibility API, several round trips of it, and an application that
    /// is slow to answer would stall the bar for as long as it took, every
    /// two seconds.
    ///
    /// Skipped entirely without Accessibility, which the read depends on:
    /// otherwise every tick paid for a full process listing and AX walk only
    /// to fail, forever, on a machine that never granted it. The timer itself
    /// keeps running so a grant takes effect on its own next tick.
    private func refresh() {
        guard AppMenuReader.isTrusted else {
            if isLocationInUse { isLocationInUse = false }
            return
        }
        guard !isReading else { return }
        isReading = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let inUse = LocationServicesReader.isInUse()
            DispatchQueue.main.async {
                guard let self else { return }
                self.isReading = false
                guard inUse != self.isLocationInUse else { return }
                self.isLocationInUse = inUse
            }
        }
    }
}
