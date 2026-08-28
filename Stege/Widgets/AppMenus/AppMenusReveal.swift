import AppKit
import Combine
import Foundation

/// Whether the frontmost application's menus are currently standing in for the
/// workspace pills.
///
/// The two widgets are separate entries in `widgets.displayed`, so neither can
/// see the other. This is the piece between them: the menus widget publishes
/// when it wants the bar, and the spaces widget steps aside for it, which is
/// what makes the swap read as one control changing rather than the bar growing
/// a second row of text.
final class AppMenusReveal: ObservableObject {
    static let shared = AppMenusReveal()

    @Published private(set) var isRevealed = false

    /// False when the menus sit beside the pills rather than in place of them,
    /// which is what `visibility = "always"` does, and while no app menus
    /// widget is in the bar at all.
    @Published var swapsSpaces = false

    /// True under `visibility = "hover"`, where the pointer resting on the pill
    /// of the window that is already focused is what reveals the menus.
    @Published var revealsOnHover = false

    /// True under `visibility = "click"`, where the pill of the window that is
    /// already focused is the thing that reveals the menus.
    ///
    /// Read by the spaces widget, which owns that pill. Clicking the focused
    /// window is otherwise a request to focus what is already focused, so the
    /// gesture costs nothing that was doing anything.
    @Published var togglesOnClick = false

    enum Source {
        case spaces
        case menus
    }

    private var sources: Set<String> = []
    private var pendingHide: DispatchWorkItem?
    private var watchdog: Timer?
    /// The horizontal span each side of the swap occupies, in screen points.
    /// See `isPointerInHoldRegion`.
    private var spans: [String: ClosedRange<CGFloat>] = [:]

    private init() {}

    /// Either widget can hold the reveal open. The pointer crosses from one to
    /// the other as they swap, and for a moment neither reports it, so a hide
    /// waits briefly instead of firing into that gap and flickering.
    func setHovered(_ hovered: Bool, from source: Source) {
        let key = String(describing: source)
        if hovered { sources.insert(key) } else { sources.remove(key) }
        pendingHide?.cancel()
        pendingHide = nil

        guard sources.isEmpty else {
            set(true)
            return
        }
        scheduleHide()
    }

    /// Forgets a trigger that is no longer on screen.
    ///
    /// A tracking area reports the pointer leaving, unless the view carrying it
    /// is taken out of the hierarchy while the pointer is still inside, and
    /// that is exactly what clicking another workspace does: focus moves, the
    /// pill that was the trigger stops being one, and its tracker goes with no
    /// exit ever delivered. The reveal was then held by a source that could
    /// never let go, and the menus stayed up over the workspaces for good.
    func forget(_ source: Source) {
        spans.removeValue(forKey: String(describing: source))
        setHovered(false, from: source)
    }

    /// Where each side of the swap is, so the hold region can follow it.
    ///
    /// Only the horizontal extent is kept. Both views are in the same strip at
    /// the top of the screen, and their `global` frames are measured in a
    /// SwiftUI space whose y runs the other way from `NSEvent.mouseLocation`,
    /// so comparing x and the strip height avoids converting between the two.
    func setSpan(_ frame: CGRect, for source: Source) {
        guard frame.width > 0 else { return }
        spans[String(describing: source)] = frame.minX...frame.maxX
    }

    /// The two views are different widths, so the pointer can end up over the
    /// trigger but past the end of the menus that replaced it, which on its own
    /// would reveal, hide, and reveal again forever. Nothing hides while the
    /// pointer is still over either of them.
    private func scheduleHide() {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard !self.isPointerInHoldRegion else {
                self.scheduleHide()
                return
            }
            self.set(false)
        }
        pendingHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    /// Polled rather than observed. A global `NSEvent` monitor is not delivered
    /// events that land on this process's own windows, and the bar is one, so
    /// it would report the pointer as gone the moment it arrived.
    ///
    /// This used to hold for the whole width of the bar, which is why the
    /// workspaces could not be reached: moving the pointer off the focused
    /// window and onto another workspace's pill kept the menus up, and the
    /// menus were drawn over the pill that was being aimed at. It holds only
    /// over the trigger and the menus now, so anywhere else in the bar puts the
    /// workspaces back.
    private var isPointerInHoldRegion: Bool {
        let location = NSEvent.mouseLocation
        guard
            let screen = NSScreen.screens.first(where: {
                $0.frame.contains(location)
            }) ?? NSScreen.main
        else { return false }
        let height = ConfigManager.shared.config.experimental.foreground
            .resolveHeight()
        guard screen.frame.maxY - location.y <= height else { return false }
        return spans.values.contains { $0.contains(location.x) }
    }

    /// Reveals the menus when they are hidden, and puts the workspaces back
    /// when they are not.
    func toggleRevealed() {
        setRevealed(!isRevealed)
    }

    /// For the modes that do not depend on the pointer, where the answer is
    /// already known and there is no gap to wait out.
    func setRevealed(_ revealed: Bool) {
        pendingHide?.cancel()
        pendingHide = nil
        sources.removeAll()
        set(revealed)
    }

    private func set(_ value: Bool) {
        guard value != isRevealed else { return }
        isRevealed = value
        // Only the pointer-driven mode. Under `click` and `modifier` the
        // pointer is nowhere in particular and the watchdog would close the
        // menus the instant they opened.
        value && revealsOnHover ? startWatchdog() : stopWatchdog()
    }

    /// A second way out, in case a tracker is ever lost the way `forget`
    /// describes and nothing calls it. The pointer's position is the truth
    /// about whether the reveal should still be held, and `sources` is only a
    /// cache of it, so while the menus are up that truth is checked directly.
    private func startWatchdog() {
        stopWatchdog()
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) {
            [weak self] _ in
            guard let self, !self.isPointerInHoldRegion else { return }
            self.sources.removeAll()
            self.pendingHide?.cancel()
            self.pendingHide = nil
            self.set(false)
        }
    }

    private func stopWatchdog() {
        watchdog?.invalidate()
        watchdog = nil
    }
}
