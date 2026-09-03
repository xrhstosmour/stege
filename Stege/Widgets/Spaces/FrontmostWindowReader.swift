import AppKit
import CoreGraphics

/// Asks the window server for the list `FrontmostWindow` reasons about.
///
/// Kept apart from the rule itself so the rule stays testable without a window
/// server to run against.
///
/// Called from the queue the workspace refresh runs on, not the main thread,
/// which both of these allow. `CGWindowListCopyWindowInfo` is CoreGraphics, and
/// `NSRunningApplication` is declared `NS_SWIFT_SENDABLE` with its properties
/// returned atomically. The documented caveat is that those properties only
/// change as the main run loop turns, so an answer here can be one turn old,
/// which is a fraction of the interval the refresh itself runs at.
enum FrontmostWindowReader {
    static func current() -> Int? {
        guard let front = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        let list =
            CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let entries = list.compactMap { window -> FrontmostWindow.Entry? in
            guard let number = window[kCGWindowNumber as String] as? Int,
                let pid = window[kCGWindowOwnerPID as String] as? pid_t,
                let layer = window[kCGWindowLayer as String] as? Int
            else { return nil }
            return FrontmostWindow.Entry(
                number: number, ownerProcessIdentifier: pid, layer: layer)
        }
        return FrontmostWindow.identifier(
            in: entries, frontmost: front.processIdentifier)
    }
}
