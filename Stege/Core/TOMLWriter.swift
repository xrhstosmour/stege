import Foundation

/// Sets one key in a TOML file, in place, leaving everything else alone.
///
/// Stege writes back to the file the user is editing rather than to a settings
/// store of its own, so the file has to survive the round trip: the comments
/// stay, the ordering stays, and what somebody wrote by hand yesterday is
/// still there after a widget writes to it today. That rules out decoding the
/// file and re-encoding it, and leaves editing the text.
///
/// Not a TOML parser. It finds the assignment, replaces the value, and adds
/// the table and the key when they are missing.
enum TOMLWriter {
    static func setting(
        _ original: String, key: String, rawValue: String
    ) -> String {
        key.contains(".")
            ? settingInTable(original, key: key, rawValue: rawValue)
            : settingAtTopLevel(original, key: key, rawValue: rawValue)
    }

    private static func settingInTable(
        _ original: String, key: String, rawValue: String
    ) -> String {
        let components = key.split(separator: ".").map(String.init)
        guard components.count >= 2 else { return original }

        let tablePath = components.dropLast().joined(separator: ".")
        let actualKey = components.last!
        let tableHeader = "[\(tablePath)]"

        var newLines: [String] = []
        var insideTargetTable = false
        var updatedKey = false
        var foundTable = false
        var openArrayDepth = 0

        for line in original.components(separatedBy: "\n") {
            // The tail of a value that ran past its own line. It belonged to
            // the assignment just replaced, so it is dropped rather than left
            // behind to be read as a value of its own.
            if openArrayDepth > 0 {
                openArrayDepth += depthChange(in: line)
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                if insideTargetTable && !updatedKey {
                    newLines.append("\(actualKey) = \(rawValue)")
                    updatedKey = true
                }
                insideTargetTable = trimmed == tableHeader
                if insideTargetTable { foundTable = true }
                newLines.append(line)
                continue
            }

            if insideTargetTable, !updatedKey, let value = value(of: actualKey, in: line) {
                newLines.append("\(actualKey) = \(rawValue)")
                updatedKey = true
                openArrayDepth = max(0, depthChange(in: value))
                continue
            }
            newLines.append(line)
        }

        if foundTable && insideTargetTable && !updatedKey {
            newLines.append("\(actualKey) = \(rawValue)")
        }
        if !foundTable {
            newLines.append("")
            newLines.append(tableHeader)
            newLines.append("\(actualKey) = \(rawValue)")
        }
        return newLines.joined(separator: "\n")
    }

    private static func settingAtTopLevel(
        _ original: String, key: String, rawValue: String
    ) -> String {
        var newLines: [String] = []
        var updatedAtLeastOnce = false
        var openArrayDepth = 0

        for line in original.components(separatedBy: "\n") {
            if openArrayDepth > 0 {
                openArrayDepth += depthChange(in: line)
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.hasPrefix("#"), !updatedAtLeastOnce,
                let value = value(of: key, in: line)
            {
                newLines.append("\(key) = \(rawValue)")
                updatedAtLeastOnce = true
                openArrayDepth = max(0, depthChange(in: value))
                continue
            }
            newLines.append(line)
        }
        if !updatedAtLeastOnce {
            newLines.append("\(key) = \(rawValue)")
        }
        return newLines.joined(separator: "\n")
    }

    /// What the line assigns to `key`, or nil when the line is not that
    /// assignment. Anchored at the start of the line, which is what keeps a
    /// commented-out `# hidden = []` from being taken for the real thing.
    private static func value(of key: String, in line: String) -> String? {
        let pattern = "^\(NSRegularExpression.escapedPattern(for: key))\\s*="
        guard let match = line.range(of: pattern, options: .regularExpression)
        else { return nil }
        return String(line[match.upperBound...])
    }

    /// How many array brackets the text leaves open: 0 for a value written on
    /// one line, more for one that carries on to the next.
    ///
    /// Brackets inside a string do not count, so a name holding one cannot
    /// swallow the rest of the file, and neither does anything after a `#`,
    /// which is a comment.
    private static func depthChange(in text: String) -> Int {
        var depth = 0
        var insideString = false
        var escaped = false
        for character in text {
            if escaped {
                escaped = false
                continue
            }
            if insideString {
                switch character {
                case "\\": escaped = true
                case "\"": insideString = false
                default: break
                }
                continue
            }
            switch character {
            case "\"": insideString = true
            case "[": depth += 1
            case "]": depth -= 1
            case "#": return depth
            default: break
            }
        }
        return depth
    }
}
