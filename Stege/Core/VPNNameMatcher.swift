import Foundation

/// Matches a running application's name against the candidate strings tied to
/// a VPN tunnel that registers no Network Extension provider, WARP included.
///
/// Two passes: every running application's name is checked for an exact
/// match first, across the whole list, before any fallback runs. A same-vendor
/// app with a longer name, "Proton Mail" next to a tunnel called "Proton",
/// would otherwise win a substring match before the tunnel's actual owner got
/// a chance to match exactly, and `NSWorkspace.shared.runningApplications`
/// carries no defined order to make that safe.
enum VPNNameMatcher {
    /// One candidate or app name, normalised the same way on both sides: case
    /// folded and stripped of spaces, so "Cloudflare WARP" and
    /// "cloudflarewarp" compare equal.
    static func normalise(_ value: String) -> String {
        value.replacingOccurrences(of: " ", with: "").lowercased()
    }

    /// The candidates worth comparing an app name against. A service
    /// identifier the system assigned, a UUID, carries no name signal in
    /// either direction, and anything shorter than four characters can only
    /// ever match by coincidence.
    static func candidates(from values: [String?]) -> [String] {
        values.compactMap { $0 }
            .filter { UUID(uuidString: $0) == nil }
            .map(normalise)
            .filter { $0.count >= 4 }
    }

    /// The index, among `names`, of the running application that carries the
    /// tunnel, or nil if none does.
    static func bestMatch(candidates: [String], names: [String]) -> Int? {
        guard !candidates.isEmpty else { return nil }
        let normalisedNames = names.map(normalise)

        if let exactIndex = normalisedNames.firstIndex(where: {
            candidates.contains($0)
        }) {
            return exactIndex
        }

        // The app's name turning up inside the tunnel's is a real signal
        // either way, but a short app name can turn up inside an unrelated
        // candidate by coincidence, so that direction only counts once the
        // app name itself is long enough not to be one.
        return normalisedNames.firstIndex { normalisedName in
            guard normalisedName.count >= 4 else { return false }
            return candidates.contains { candidate in
                normalisedName.contains(candidate)
                    || (normalisedName.count >= 6
                        && candidate.contains(normalisedName))
            }
        }
    }
}
