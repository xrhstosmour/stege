import Testing

@testable import StegeCore

struct RevealFilterTests {
    @Test func aBundleIdentifierMatches() {
        #expect(
            RevealFilter.matches(
                bundleIdentifier: "com.1password.1password", name: "1Password",
                list: ["com.1password.1password"]))
    }

    /// The case this was written for: somebody types what the row shows them.
    @Test func aNameMatches() {
        #expect(
            RevealFilter.matches(
                bundleIdentifier: "com.1password.1password", name: "1Password",
                list: ["1Password"]))
    }

    @Test func aNameMatchesWhateverItsCase() {
        #expect(
            RevealFilter.matches(
                bundleIdentifier: "com.google.drivefs", name: "Google Drive",
                list: ["  google drive  "]))
    }

    /// Names get copied out of Finder, and Finder shows the extension when it
    /// is asked to.
    @Test func theApplicationSuffixIsIgnored() {
        #expect(
            RevealFilter.matches(
                bundleIdentifier: "com.google.drivefs", name: "Google Drive",
                list: ["Google Drive.app"]))
    }

    @Test func theTwoKindsMixInOneList() {
        let list = ["1Password", "com.google.drivefs"]
        #expect(
            RevealFilter.matches(
                bundleIdentifier: "com.1password.1password", name: "1Password",
                list: list))
        #expect(
            RevealFilter.matches(
                bundleIdentifier: "com.google.drivefs", name: "Google Drive",
                list: list))
        #expect(
            !RevealFilter.matches(
                bundleIdentifier: "org.pqrs.Karabiner", name: "Karabiner",
                list: list))
    }

    /// A partial name is not a match. `Drive` next to `Google Drive` would
    /// otherwise take away an application nobody named.
    @Test func aPartialNameDoesNotMatch() {
        #expect(
            !RevealFilter.matches(
                bundleIdentifier: "com.google.drivefs", name: "Google Drive",
                list: ["Drive"]))
    }

    @Test func anEmptyListMatchesNothing() {
        #expect(
            !RevealFilter.matches(
                bundleIdentifier: "com.google.drivefs", name: "Google Drive",
                list: []))
    }

    /// A blank entry, which is what a trailing comma or an empty string in the
    /// file leaves behind, must not match the applications that have no name.
    @Test func aBlankEntryMatchesNothing() {
        #expect(
            !RevealFilter.matches(
                bundleIdentifier: nil, name: "", list: ["", "   "]))
    }

    @Test func theBundleIdentifierIsWhatIsWritten() {
        #expect(
            RevealFilter.entry(
                bundleIdentifier: "com.google.drivefs", name: "Google Drive")
                == "com.google.drivefs")
    }

    @Test func theNameIsWrittenWhenThereIsNoBundleIdentifier() {
        #expect(
            RevealFilter.entry(bundleIdentifier: nil, name: "Google Drive")
                == "Google Drive")
        #expect(
            RevealFilter.entry(bundleIdentifier: "", name: "Google Drive")
                == "Google Drive")
    }

    @Test func nothingIsWrittenForAnApplicationWithNeither() {
        #expect(RevealFilter.entry(bundleIdentifier: nil, name: "  ") == nil)
    }

    @Test func theArrayIsWrittenAsTOML() {
        #expect(
            RevealFilter.tomlArray(["1Password", "com.google.drivefs"])
                == "[\"1Password\", \"com.google.drivefs\"]")
        #expect(RevealFilter.tomlArray([]) == "[]")
    }

    /// A name can hold a quote. Writing it unescaped would leave the whole
    /// configuration file unparseable.
    @Test func aQuoteInANameIsEscaped() {
        #expect(
            RevealFilter.tomlArray(["Bob's \"App\""])
                == "[\"Bob's \\\"App\\\"\"]")
        #expect(RevealFilter.tomlArray(["back\\slash"]) == "[\"back\\\\slash\"]")
    }
}
