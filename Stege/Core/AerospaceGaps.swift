import Foundation

/// Keeps the `outer.top` line of an `aerospace.toml` equal to what the bar
/// needs, and touches nothing else in the file.
///
/// Pure text in and out, like `ConfigMigration`, so the rewrite can be tested
/// without a file system. `AerospaceGapSync` does the reading, the backup and
/// the writing.
enum AerospaceGaps {
    struct Entry: Equatable {
        /// `built-in` is AeroSpace's own keyword. Anything else is a screen's
        /// name, which AeroSpace reads as a case-insensitive regular
        /// expression.
        let monitor: String
        let points: Int
        let isBuiltIn: Bool
    }

    struct Screen: Equatable {
        let name: String
        let isBuiltIn: Bool
        let points: Int
    }

    /// The entries worth writing, for any mix of displays.
    ///
    /// The fallback is the inset a display with nothing reserved at its top
    /// needs, which is the most any display ever needs, so a display that
    /// needs it gets no entry and no name is written for it. That is what makes
    /// this work for any monitor: an external, an identical pair, a dock, an
    /// AirPlay or Sidecar display coming and going all fall to the fallback
    /// without touching the file. Only a display macOS reserves a strip on,
    /// the notch, or an external with a visible menu bar, needs its own entry.
    ///
    /// Ordered by name rather than by attach order, so replugging does not
    /// reshuffle the line and dirty a tracked dotfile. Two displays sharing a
    /// name cannot be told apart by `AeroSpace`, so the larger inset wins, it
    /// can leave a little extra gap but never a window under the bar. A
    /// display with no name is left to the fallback, since an empty pattern
    /// would match every display.
    static func entries(for screens: [Screen], fallback: Int) -> [Entry] {
        var byKey: [String: Entry] = [:]
        for screen in screens {
            let points = min(screen.points, fallback)
            let name = screen.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard points < fallback, screen.isBuiltIn || !name.isEmpty else {
                continue
            }
            let key = screen.isBuiltIn ? "built-in" : name
            let existing = byKey[key]?.points ?? 0
            byKey[key] = Entry(
                monitor: screen.isBuiltIn ? "built-in" : name,
                points: max(existing, points), isBuiltIn: screen.isBuiltIn)
        }
        return byKey.values.sorted {
            $0.isBuiltIn != $1.isBuiltIn
                ? $0.isBuiltIn : $0.monitor < $1.monitor
        }
    }

    /// Sits above the line it owns. Its presence is how a later run tells a
    /// line it wrote from one the user did, and the file says why the line
    /// changes by itself.
    static let marker =
        "# Managed by Stege so windows start below its bar. Turn off with manage-aerospace-gaps = false."

    static func outerTopValue(entries: [Entry], fallback: Int) -> String {
        let items = entries.map { entry -> String in
            let key = entry.isBuiltIn ? "built-in" : quoted(escapedPattern(entry.monitor))
            return "{ monitor.\(key) = \(entry.points) }"
        }
        return "[" + (items + [String(fallback)]).joined(separator: ", ") + "]"
    }

    /// The new text, or nil when the file cannot be edited safely and must be
    /// left exactly as it is: an `outer.top` written across several lines, or
    /// a file with two `[gaps]` tables, would be corrupted by a line edit.
    static func rewrite(_ text: String, outerTop value: String) -> String? {
        // Split on the file's own line ending. A CRLF file split on "\n" keeps
        // a "\r" on every line, which no header or key ever equals, so each run
        // appended a second `[gaps]` table and AeroSpace dropped the file.
        let ending = text.contains("\r\n") ? "\r\n" : "\n"
        var lines = text.components(separatedBy: ending)
        // Gaps written as root dotted or inline keys cannot be told apart from
        // a table by line matching, and appending `[gaps]` would redefine it.
        if lines.contains(where: { isRootGapsKey($0) }) { return nil }
        let assignment = "outer.top = \(value)"

        guard let header = lines.firstIndex(where: { isTable($0, named: "gaps") })
        else {
            let separator = text.isEmpty || text.hasSuffix(ending) ? "" : ending
            return text + separator + ending + "[gaps]" + ending + marker
                + ending + assignment + ending
        }
        if lines[(header + 1)...].contains(where: { isTable($0, named: "gaps") }) {
            return nil
        }

        let end =
            lines[(header + 1)...].firstIndex(where: { isAnyTable($0) })
            ?? lines.count
        let existing = (header + 1..<end).first { index in
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("outer.top") else { return false }
            return trimmed.dropFirst("outer.top".count)
                .trimmingCharacters(in: .whitespaces).hasPrefix("=")
        }

        guard let index = existing else {
            lines.insert(contentsOf: [marker, assignment], at: header + 1)
            return lines.joined(separator: ending)
        }

        let current = lines[index]
        guard isSingleLine(current) else { return nil }
        let hasMarker = index > 0 && lines[index - 1] == marker
        if hasMarker && current == assignment { return text }
        lines[index] = assignment
        if !hasMarker { lines.insert(marker, at: index) }
        return lines.joined(separator: ending)
    }

    /// A header with its trailing comment and inner spaces ignored, all legal
    /// TOML: `[ gaps ]` and `[gaps] # why` are the same table as `[gaps]`.
    private static func header(_ line: String) -> String? {
        let code = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? line
        let squeezed = code.filter { !$0.isWhitespace }
        return squeezed.hasPrefix("[") ? squeezed : nil
    }

    private static func isTable(_ line: String, named name: String) -> Bool {
        header(line) == "[\(name)]"
    }

    private static func isAnyTable(_ line: String) -> Bool {
        header(line) != nil
    }

    private static func isRootGapsKey(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("gaps.") || trimmed.hasPrefix("gaps ")
            || trimmed.hasPrefix("gaps=")
    }

    /// A value whose brackets close on the same line it opens.
    private static func isSingleLine(_ line: String) -> Bool {
        guard let equals = line.firstIndex(of: "=") else { return false }
        let value = line[line.index(after: equals)...]
        return value.filter { $0 == "[" }.count == value.filter { $0 == "]" }.count
    }

    private static func escapedPattern(_ name: String) -> String {
        NSRegularExpression.escapedPattern(for: name)
    }

    private static func quoted(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
