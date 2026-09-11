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

    /// Keyed by screen, one-based to match `NSScreen.screens`. There is one
    /// bar, and one independent `AppMenusWidget`/`SpacesWidget` pair, per
    /// screen, and this used to be a single flat value all of them shared: a
    /// hover on one screen cross-faded every screen's row, since every bar
    /// observes this same object. Keying every piece of per-interaction state
    /// here by screen is what keeps one screen's reveal from leaking into
    /// another's, the same fix already applied once to the sibling
    /// `AppMenusManager.titleFrames` for the same reason.
    @Published private(set) var isRevealed: [Int: Bool] = [:]

    /// False when the menus sit beside the pills rather than in place of them,
    /// which is what `visibility = "always"` does, and while no app menus
    /// widget is in the bar at all.
    ///
    /// Global rather than keyed by screen: every bar reads the same config
    /// file, so every screen's widget always writes the same value here. There
    /// is nothing screen-specific to key.
    @Published var swapsSpaces = false

    /// True under `visibility = "hover"`, where the pointer resting on the pill
    /// of the window that is already focused is what reveals the menus.
    ///
    /// Global, for the same reason as `swapsSpaces`.
    @Published var revealsOnHover = false

    /// True under `visibility = "click"`, where the pill of the window that is
    /// already focused is the thing that reveals the menus.
    ///
    /// Read by the spaces widget, which owns that pill. Clicking the focused
    /// window is otherwise a request to focus what is already focused, so the
    /// gesture costs nothing that was doing anything.
    ///
    /// Global, for the same reason as `swapsSpaces`.
    @Published var togglesOnClick = false

    enum Source {
        case spaces
        case menus
    }

    /// Held open by the shortcut rather than by the pointer, per screen.
    ///
    /// Under `hover` the reveal is only ever as long as the pointer rests on
    /// the pill, and a watchdog closes it a quarter of a second after the
    /// pointer moves off. A shortcut has no pointer behind it, so without this
    /// the row appeared and was shut again before it could be read. While
    /// latched the pointer decides nothing: the row stays until the shortcut is
    /// pressed again, or until another application comes to the front.
    @Published private(set) var isLatched: [Int: Bool] = [:]

    /// One observer for every screen: the frontmost application is a property
    /// of the machine, not of a screen, so a single `NSWorkspace` observer is
    /// enough to unlatch whichever screens are currently latched.
    private var applicationObserver: NSObjectProtocol?

    private var sources: [Int: Set<String>] = [:]
    private var pendingHide: [Int: DispatchWorkItem] = [:]
    private var watchdog: [Int: Timer] = [:]
    /// See `suppressUntilPointerLeaves`.
    private var isSuppressed: [Int: Bool] = [:]
    private var suppression: [Int: Timer] = [:]
    /// The horizontal span each side of the swap occupies on that screen, in
    /// that screen's own panel-local points. See `isPointerInHoldRegion`.
    private var spans: [Int: [String: ClosedRange<CGFloat>]] = [:]

    private init() {}

    /// Either widget can hold the reveal open. The pointer crosses from one to
    /// the other as they swap, and for a moment neither reports it, so a hide
    /// waits briefly instead of firing into that gap and flickering.
    func setHovered(_ hovered: Bool, from source: Source, screen: Int) {
        guard !(isLatched[screen] ?? false) else { return }
        guard !(hovered && (isSuppressed[screen] ?? false)) else { return }
        let key = String(describing: source)
        if hovered {
            sources[screen, default: []].insert(key)
        } else {
            sources[screen]?.remove(key)
        }
        pendingHide[screen]?.cancel()
        pendingHide[screen] = nil

        guard sources[screen]?.isEmpty ?? true else {
            set(true, screen: screen)
            return
        }
        scheduleHide(screen: screen)
    }

    /// Holds the reveal off until the pointer has left and come back.
    ///
    /// Clicking a window in another workspace focuses it, which makes its pill
    /// the new trigger, and that pill is already under the pointer because it
    /// is what was just clicked. A tracking area reports the pointer as inside
    /// the moment it is installed, so the menus opened straight away on top of
    /// the workspaces, as if the click had asked for them. It had not: it asked
    /// to switch windows. Hovering is what asks for the menus, so the next
    /// hover has to be a real one.
    func suppressUntilPointerLeaves(screen: Int) {
        isSuppressed[screen] = true
        setRevealed(false, screen: screen)
        startSuppressionWatch(screen: screen)
    }

    /// The pointer leaving cannot be waited for as an event. The view carrying
    /// the tracking area is rebuilt by the focus change itself, so the exit
    /// that would clear this is exactly the one that never arrives.
    private func startSuppressionWatch(screen: Int) {
        suppression[screen]?.invalidate()
        suppression[screen] = Timer.scheduledTimer(
            withTimeInterval: 0.15, repeats: true
        ) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            guard !self.isPointerInHoldRegion(for: screen) else { return }
            self.isSuppressed[screen] = false
            timer.invalidate()
            self.suppression[screen] = nil
        }
    }

    /// Forgets a trigger that is no longer on screen.
    ///
    /// A tracking area reports the pointer leaving, unless the view carrying it
    /// is taken out of the hierarchy while the pointer is still inside, and
    /// that is exactly what clicking another workspace does: focus moves, the
    /// pill that was the trigger stops being one, and its tracker goes with no
    /// exit ever delivered. The reveal was then held by a source that could
    /// never let go, and the menus stayed up over the workspaces for good.
    func forget(_ source: Source, screen: Int) {
        spans[screen]?.removeValue(forKey: String(describing: source))
        setHovered(false, from: source, screen: screen)
    }

    /// Where each side of the swap is on that screen, so the hold region can
    /// follow it.
    ///
    /// Only the horizontal extent is kept. Both views are in the same strip at
    /// the top of the screen, and their `global` frames are measured in a
    /// SwiftUI space whose y runs the other way from `NSEvent.mouseLocation`,
    /// so comparing x and the strip height avoids converting between the two.
    /// `global` is local to that bar's own panel, not to the desktop, which is
    /// why this is kept per screen rather than compared against another
    /// screen's span.
    func setSpan(_ frame: CGRect, for source: Source, screen: Int) {
        guard frame.width > 0 else { return }
        spans[screen, default: [:]][String(describing: source)] =
            frame.minX...frame.maxX
    }

    /// The two views are different widths, so the pointer can end up over the
    /// trigger but past the end of the menus that replaced it, which on its own
    /// would reveal, hide, and reveal again forever. Nothing hides while the
    /// pointer is still over either of them.
    private func scheduleHide(screen: Int) {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard !self.isPointerInHoldRegion(for: screen) else {
                self.scheduleHide(screen: screen)
                return
            }
            self.set(false, screen: screen)
        }
        pendingHide[screen] = work
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
    ///
    /// Requires the pointer to actually be over the screen this check is for,
    /// not just anywhere spans happens to have an entry for: a span is in that
    /// screen's own panel-local coordinates, so comparing it against the
    /// pointer while on a different screen is comparing two different origins.
    ///
    /// The pointer itself also has to be translated into that same local
    /// space before it can be compared: `NSEvent.mouseLocation` is a desktop
    /// coordinate, at 0 only on whichever screen sits at the desktop's own
    /// origin, so on every other screen comparing it directly against a
    /// panel-local span, which starts at 0 on every screen alike, never
    /// matched. `AppMenuPresenter.present` hit and fixed this same mismatch
    /// once already, translating the other direction, panel-local to
    /// desktop, before handing a rect to `NSMenu`.
    private func isPointerInHoldRegion(for screen: Int) -> Bool {
        let location = NSEvent.mouseLocation
        guard
            let index = NSScreen.screens.firstIndex(where: {
                $0.frame.contains(location)
            })
        else { return false }
        guard index + 1 == screen else { return false }
        let nsScreen = NSScreen.screens[index]
        let height = ConfigManager.shared.config.bar.foreground
            .resolveHeight()
        guard nsScreen.frame.maxY - location.y <= height else { return false }
        let localX = location.x - nsScreen.frame.minX
        return spans[screen]?.values.contains { $0.contains(localX) } ?? false
    }

    /// Reveals the menus when they are hidden, and puts the workspaces back
    /// when they are not.
    func toggleRevealed(screen: Int) {
        setRevealed(!(isRevealed[screen] ?? false), screen: screen)
    }

    /// What the `menu-shortcut` calls. Shows the menus row in place of the
    /// workspace pills and holds it there, or puts it away again, on whichever
    /// screen the pointer is over when the shortcut is pressed.
    func toggleLatched(screen: Int) {
        (isLatched[screen] ?? false) ? unlatch(screen: screen) : latch(screen: screen)
    }

    private func latch(screen: Int) {
        pendingHide[screen]?.cancel()
        pendingHide[screen] = nil
        sources[screen] = []
        isLatched[screen] = true
        set(true, screen: screen)
        watchApplicationSwitch()
    }

    func unlatch(screen: Int) {
        guard isLatched[screen] ?? false else { return }
        isLatched[screen] = false
        if !isLatched.values.contains(true) {
            stopWatchingApplicationSwitch()
        }
        set(false, screen: screen)
    }

    /// Switching application while a row is up puts it away. Its titles
    /// belong to the application that was in front, so holding it open over a
    /// different one would be showing the wrong menus.
    ///
    /// Except Stege's own activation, which is how a row gets the keyboard in
    /// the first place. Without that exception opening the row fired this and
    /// shut it again in the same breath, and the shortcut looked like it did
    /// nothing at all.
    private func watchApplicationSwitch() {
        stopWatchingApplicationSwitch()
        let ownIdentifier = Bundle.main.bundleIdentifier
        applicationObserver = NSWorkspace.shared.notificationCenter
            .addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil, queue: .main
            ) { [weak self] note in
                let application =
                    note.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication
                guard application?.bundleIdentifier != ownIdentifier else {
                    return
                }
                guard let self else { return }
                let latchedScreens = self.isLatched.filter { $0.value }
                    .map(\.key)
                latchedScreens.forEach { self.unlatch(screen: $0) }
            }
    }

    private func stopWatchingApplicationSwitch() {
        if let applicationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(
                applicationObserver)
        }
        applicationObserver = nil
    }

    /// Drops every piece of state for a screen index that no longer has a
    /// panel, so a display that is no longer connected cannot leave stale
    /// reveal state behind for a future display to inherit at the same
    /// index. `AppDelegate.setupPanels()` calls this with the current screen
    /// count whenever the screen layout changes.
    func forgetScreens(beyond count: Int) {
        let knownScreens =
            Set(isRevealed.keys)
            .union(isLatched.keys)
            .union(sources.keys)
            .union(pendingHide.keys)
            .union(watchdog.keys)
            .union(isSuppressed.keys)
            .union(suppression.keys)
            .union(spans.keys)
        for screen in knownScreens where screen > count {
            if isLatched[screen] ?? false {
                unlatch(screen: screen)
            }
            watchdog[screen]?.invalidate()
            suppression[screen]?.invalidate()
            pendingHide[screen]?.cancel()
            isRevealed.removeValue(forKey: screen)
            isLatched.removeValue(forKey: screen)
            sources.removeValue(forKey: screen)
            pendingHide.removeValue(forKey: screen)
            watchdog.removeValue(forKey: screen)
            isSuppressed.removeValue(forKey: screen)
            suppression.removeValue(forKey: screen)
            spans.removeValue(forKey: screen)
        }
    }

    /// For the modes that do not depend on the pointer, where the answer is
    /// already known and there is no gap to wait out.
    func setRevealed(_ revealed: Bool, screen: Int) {
        pendingHide[screen]?.cancel()
        pendingHide[screen] = nil
        sources[screen] = []
        set(revealed, screen: screen)
    }

    private func set(_ value: Bool, screen: Int) {
        guard value != (isRevealed[screen] ?? false) else { return }
        isRevealed[screen] = value
        // Only the pointer-driven mode, and only when the pointer is what is
        // holding it. Under `click`, `modifier` and the shortcut's latch the
        // pointer is nowhere in particular and the watchdog would close the
        // menus the instant they opened.
        value && revealsOnHover && !(isLatched[screen] ?? false)
            ? startWatchdog(screen: screen) : stopWatchdog(screen: screen)
    }

    /// A second way out, in case a tracker is ever lost the way `forget`
    /// describes and nothing calls it. The pointer's position is the truth
    /// about whether the reveal should still be held, and `sources` is only a
    /// cache of it, so while the menus are up that truth is checked directly.
    private func startWatchdog(screen: Int) {
        stopWatchdog(screen: screen)
        watchdog[screen] = Timer.scheduledTimer(
            withTimeInterval: 0.25, repeats: true
        ) { [weak self] _ in
            guard let self, !self.isPointerInHoldRegion(for: screen) else {
                return
            }
            self.sources[screen] = []
            self.pendingHide[screen]?.cancel()
            self.pendingHide[screen] = nil
            self.set(false, screen: screen)
        }
    }

    private func stopWatchdog(screen: Int) {
        watchdog[screen]?.invalidate()
        watchdog[screen] = nil
    }
}
