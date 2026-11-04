import CoreGraphics
import Foundation

/// Finds which `AeroSpace` window an Accessibility window is, and whether
/// `AeroSpace` is the one placing it.
///
/// Pure, so the matching can be tested without a window server. Asking about
/// "the focused window" instead answered for the wrong window whenever focus
/// was somewhere else, such as a floating window being raised while a tiled one
/// held focus.
enum WindowLayout {
    struct Entry: Equatable {
        let number: Int
        let processID: Int32
        let bounds: CGRect
    }

    /// The window number whose process and bounds are the window's own.
    ///
    /// `AeroSpace` identifies a window by its CoreGraphics window number, which
    /// was measured against `list-windows`: Chrome 93 and Herdr 115 matched.
    /// Accessibility exposes no public way to ask for that number, so the
    /// window is matched by where it is, within a point to allow for the
    /// rounding the two sources apply. Two windows of one process in exactly
    /// the same place cannot be told apart, and the first wins, which is only
    /// ever wrong between a tiled and a floating one stacked exactly.
    static func number(
        processID: Int32, frame: CGRect, among entries: [Entry]
    ) -> Int? {
        entries.first {
            $0.processID == processID
                && abs($0.bounds.minX - frame.minX) <= 1
                && abs($0.bounds.minY - frame.minY) <= 1
                && abs($0.bounds.width - frame.width) <= 1
                && abs($0.bounds.height - frame.height) <= 1
        }?.number
    }

    /// `window-id` and `window-layout` per line, as
    /// `list-windows --all --format '%{window-id} %{window-layout}'` prints
    /// them. A line it cannot read is skipped rather than failing the rest.
    static func parse(_ output: String) -> [Int: String] {
        var layouts: [Int: String] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count == 2, let number = Int(parts[0]) else { continue }
            layouts[number] = String(parts[1])
        }
        return layouts
    }

    enum Decision: Equatable {
        /// `AeroSpace` tiles it, so it is not ours to move.
        case leaveToWindowManager
        /// Floating, or not a window `AeroSpace` has listed.
        case mayMove
    }

    static func decision(number: Int?, layouts: [Int: String]) -> Decision {
        guard let number, let layout = layouts[number] else { return .mayMove }
        return layout == "floating" ? .mayMove : .leaveToWindowManager
    }
}
