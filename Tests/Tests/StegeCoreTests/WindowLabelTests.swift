import Testing

@testable import StegeCore

struct WindowLabelTests {
    @Test func oneWindowUsesTheApplicationName() {
        #expect(
            WindowLabel.text(
                applicationName: "WezTerm", title: "~", hasSiblings: false,
                alwaysUseApplicationName: false
            ) == "WezTerm"
        )
    }

    @Test func siblingsUseTheTitle() {
        #expect(
            WindowLabel.text(
                applicationName: "Safari", title: "Anthropic", hasSiblings: true,
                alwaysUseApplicationName: false
            ) == "Anthropic"
        )
    }

    @Test func aTitleOfOneCharacterFallsBackToTheName() {
        #expect(
            WindowLabel.text(
                applicationName: "WezTerm", title: "~", hasSiblings: true,
                alwaysUseApplicationName: false
            ) == "WezTerm"
        )
    }

    @Test func aTitleThatIsOnlySpaceFallsBackToTheName() {
        #expect(
            WindowLabel.text(
                applicationName: "WezTerm", title: "   ", hasSiblings: true,
                alwaysUseApplicationName: false
            ) == "WezTerm"
        )
    }

    @Test func aTitleIsTrimmedBeforeItIsShown() {
        #expect(
            WindowLabel.text(
                applicationName: "WezTerm", title: "  build  ", hasSiblings: true,
                alwaysUseApplicationName: false
            ) == "build"
        )
    }

    @Test func twoCharactersIsLongEnough() {
        #expect(
            WindowLabel.text(
                applicationName: "Terminal", title: "vi", hasSiblings: true,
                alwaysUseApplicationName: false
            ) == "vi"
        )
    }

    @Test func anOptedOutApplicationKeepsItsName() {
        #expect(
            WindowLabel.text(
                applicationName: "Finder", title: "Documents", hasSiblings: true,
                alwaysUseApplicationName: true
            ) == "Finder"
        )
    }

    @Test func aMissingTitleFallsBackToTheName() {
        #expect(
            WindowLabel.text(
                applicationName: "WezTerm", title: nil, hasSiblings: true,
                alwaysUseApplicationName: false
            ) == "WezTerm"
        )
    }

    @Test func aMissingNameAndNoUsableTitleIsEmpty() {
        #expect(
            WindowLabel.text(
                applicationName: nil, title: "~", hasSiblings: true,
                alwaysUseApplicationName: false
            ) == ""
        )
    }
}
