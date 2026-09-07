import Testing

@testable import StegeCore

struct VPNNameMatcherTests {
    @Test func aUUIDServiceIdentifierIsExcluded() {
        #expect(
            VPNNameMatcher.candidates(from: [
                "ABCDEFAB-1234-1234-1234-1234567890AB", nil,
            ]) == [])
    }

    @Test func aCandidateShorterThanFourCharactersIsExcluded() {
        #expect(VPNNameMatcher.candidates(from: ["abc"]) == [])
    }

    @Test func candidatesAreNormalised() {
        #expect(
            VPNNameMatcher.candidates(from: ["Cloudflare WARP"])
                == ["cloudflarewarp"])
    }

    /// The case this was written for: a same-vendor app with a longer name
    /// must not win a substring match before the tunnel's actual owner gets
    /// its exact-match chance, whatever order the running applications came
    /// in.
    @Test func anExactMatchWinsOverASameVendorSubstringMatch() {
        let candidates = VPNNameMatcher.candidates(from: ["Proton", nil])
        #expect(
            VPNNameMatcher.bestMatch(
                candidates: candidates, names: ["Proton Mail", "Proton"])
                == 1)
    }

    @Test func substringMatchingStillFallsBackWhenNothingMatchesExactly() {
        let candidates = VPNNameMatcher.candidates(from: ["proton", nil])
        #expect(
            VPNNameMatcher.bestMatch(
                candidates: candidates, names: ["ProtonMailBridge"])
                == 0)
    }

    @Test func aLongAppNameMatchesAShorterCandidateItContains() {
        let candidates = VPNNameMatcher.candidates(from: [
            "cloudflarewarp", nil,
        ])
        #expect(
            VPNNameMatcher.bestMatch(
                candidates: candidates, names: ["Cloudflare"])
                == 0)
    }

    @Test func noMatchReturnsNil() {
        let candidates = VPNNameMatcher.candidates(from: ["proton", nil])
        #expect(
            VPNNameMatcher.bestMatch(candidates: candidates, names: ["Safari"])
                == nil)
    }

    @Test func emptyCandidatesNeverMatch() {
        #expect(
            VPNNameMatcher.bestMatch(candidates: [], names: ["Anything"])
                == nil)
    }
}
