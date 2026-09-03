import Foundation

/// Which window has focus, from the window list macOS already keeps.
///
/// `AeroSpace` publishes `workspace-is-focused` on every window it lists, so
/// one `list-windows --all` says which *workspace* has focus. It publishes no
/// `window-is-focused`, so which *window* took a second invocation, and the
/// pills are refreshed often enough that the second process was half of
/// everything `Stege` spawns.
///
/// macOS already knows. The frontmost application is one property, and its
/// frontmost ordinary window is the first entry the window server lists for
/// that process, since the list comes back front to back. `AeroSpace`'s window
/// identifiers are `CGWindowID`s, so the number found this way is the same
/// number the window list uses and the two can be compared directly.
///
/// Measured against `list-windows --focused` over 147 samples, across five
/// workspace switches and six focus moves inside a workspace, with no
/// disagreement. The caller still checks the answer against the windows it
/// just listed and falls back to asking `AeroSpace` when it does not appear
/// there, so a case this rule does not cover costs the process it costs today
/// rather than the wrong pill.
enum FrontmostWindow {
    /// One entry of the on-screen window list, in the order it came back.
    struct Entry: Equatable {
        let number: Int
        let ownerProcessIdentifier: Int32
        /// Zero is an ordinary window. Panels and palettes sit above it, and an
        /// application's own floating palette is not the window with focus.
        let layer: Int
    }

    static func identifier(in entries: [Entry], frontmost pid: Int32) -> Int? {
        entries.first {
            $0.ownerProcessIdentifier == pid && $0.layer == 0
        }?.number
    }
}
