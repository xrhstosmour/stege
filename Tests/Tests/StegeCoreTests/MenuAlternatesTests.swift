import Testing

@testable import StegeCore

struct MenuAlternatesTests {
    private typealias Item = MenuAlternates.Item

    private let shift = 1
    private let option = 2
    private let control = 4
    private let noCommand = 8

    @Test func theOptionVersionOfTheEntryAboveIsAnAlternate() {
        let flags = MenuAlternates.flags(for: [
            Item(title: "Get Info", character: "I"),
            Item(title: "Show Inspector", character: "I", modifiers: option),
        ])
        #expect(flags == [false, true])
    }

    /// Finder marks these with Option and no Command, and gives them no
    /// character at all.
    @Test func anAlternateWithNoShortcutIsStillAnAlternate() {
        let flags = MenuAlternates.flags(for: [
            Item(title: "Open With", modifiers: noCommand),
            Item(title: "Always Open With", modifiers: noCommand | option),
        ])
        #expect(flags == [false, true])
    }

    @Test func aDifferentCharacterIsNotAnAlternate() {
        let flags = MenuAlternates.flags(for: [
            Item(title: "Quick Look", character: "Y"),
            Item(title: "Print", character: "P", modifiers: option),
        ])
        #expect(flags == [false, false])
    }

    @Test func anotherModifierIsNotAnAlternate() {
        let flags = MenuAlternates.flags(for: [
            Item(title: "New Finder Window", character: "N"),
            Item(title: "New Folder", character: "N", modifiers: shift),
            Item(
                title: "New Folder with Selection", character: "N",
                modifiers: control),
        ])
        #expect(flags == [false, false, false])
    }

    @Test func theEntryAfterASeparatorIsNeverAnAlternateOfIt() {
        let flags = MenuAlternates.flags(for: [
            Item(title: "Print", character: "P"),
            Item(title: ""),
            Item(title: "Share", modifiers: option),
        ])
        #expect(flags == [false, false, false])
    }

    @Test func anAlternateCarryingOtherModifiersTooIsStillOne() {
        let flags = MenuAlternates.flags(for: [
            Item(title: "Duplicate", character: "D"),
            Item(
                title: "Duplicate Exactly", character: "D",
                modifiers: shift | option),
        ])
        #expect(flags == [false, true])
    }

    /// Finder's File menu lists three, and only the Option one is hidden.
    @Test func onlyTheOptionOneOfARunIsAnAlternate() {
        let flags = MenuAlternates.flags(for: [
            Item(title: "Eject", character: "E"),
            Item(title: "Eject", character: "E", modifiers: control),
            Item(title: "Eject", character: "E", modifiers: option),
        ])
        #expect(flags == [false, false, true])
    }

    @Test func anEmptyMenuIsNoTrouble() {
        #expect(MenuAlternates.flags(for: []).isEmpty)
    }

    @Test func aLoneEntryIsNeverAnAlternate() {
        let flags = MenuAlternates.flags(for: [
            Item(title: "Close", character: "W", modifiers: option)
        ])
        #expect(flags == [false])
    }
}
