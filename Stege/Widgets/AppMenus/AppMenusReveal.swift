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

    enum Source {
        case spaces
        case menus
    }

    private var sources: Set<String> = []
    private var pendingHide: DispatchWorkItem?

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

    /// The two views are different widths, so the pointer can end up over the
    /// pills but past the end of the menus that replaced them, which on its own
    /// would reveal, hide, and reveal again forever. Nothing hides while the
    /// pointer is still inside the bar's strip.
    private func scheduleHide() {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard !self.isPointerInBar else {
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
    private var isPointerInBar: Bool {
        let location = NSEvent.mouseLocation
        guard
            let screen = NSScreen.screens.first(where: {
                $0.frame.contains(location)
            }) ?? NSScreen.main
        else { return false }
        let height = ConfigManager.shared.config.experimental.foreground
            .resolveHeight()
        return screen.frame.maxY - location.y <= height
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
    }
}
