import Foundation

/// Picking a fixed-length run out of a longer list, centred on one item.
///
/// Written for the resolution list, which shows six of however many a display
/// offers. Taking the first six showed the six largest, and on a MacBook Air
/// the mode actually in use is the eighth of fourteen, so the list held six
/// resolutions, none of them the current one, and no checkmark anywhere.
enum ListWindow {
    /// The range of `count` items centred on `index`.
    ///
    /// Slid back inside the list at either end, so the result is always
    /// `count` long whenever the list is long enough. With no index to centre
    /// on, the run starts at the beginning.
    static func range(count: Int, around index: Int?, total: Int) -> Range<Int> {
        guard count > 0, total > 0 else { return 0..<0 }
        guard total > count else { return 0..<total }
        guard let index, index >= 0, index < total else { return 0..<count }
        // The odd item goes below the centre, so a run of six around item 7
        // starts at 5 and the current one sits third of six rather than fourth.
        var start = index - (count - 1) / 2
        start = max(0, min(start, total - count))
        return start..<(start + count)
    }
}
