import Testing

@testable import StegeCore

struct ShortcutParserTests {
    private let command = ShortcutParser.Modifier.command.rawValue
    private let option = ShortcutParser.Modifier.option.rawValue
    private let control = ShortcutParser.Modifier.control.rawValue
    private let shift = ShortcutParser.Modifier.shift.rawValue

    @Test func parsesTheShapeTheConfigurationDocuments() {
        #expect(
            ShortcutParser.parse("cmd+alt+b")
                == .init(modifiers: command | option, keyCode: 11))
    }

    /// Names follow what people write in other menu bar tools, so every spelling
    /// of a modifier has to land on the same bit.
    @Test func everySpellingOfAModifierIsAccepted() {
        #expect(
            ShortcutParser.parse("cmd+a")?.modifiers
                == ShortcutParser.parse("command+a")?.modifiers)
        #expect(
            ShortcutParser.parse("opt+a")?.modifiers
                == ShortcutParser.parse("option+a")?.modifiers)
        #expect(
            ShortcutParser.parse("alt+a")?.modifiers
                == ShortcutParser.parse("option+a")?.modifiers)
        #expect(
            ShortcutParser.parse("ctrl+a")?.modifiers
                == ShortcutParser.parse("control+a")?.modifiers)
    }

    @Test func combinesEveryModifier() {
        #expect(
            ShortcutParser.parse("cmd+ctrl+opt+shift+a")?.modifiers
                == command | control | option | shift)
    }

    @Test func isNotCaseOrSpaceSensitive() {
        #expect(
            ShortcutParser.parse("  CMD + Alt + B  ")
                == ShortcutParser.parse("cmd+alt+b"))
    }

    /// A shortcut with no modifier would swallow that key everywhere in the
    /// system, so it must not register at all.
    @Test func refusesABareKey() {
        #expect(ShortcutParser.parse("b") == nil)
        #expect(ShortcutParser.parse("space") == nil)
    }

    @Test func refusesAnUnknownModifier() {
        #expect(ShortcutParser.parse("hyper+b") == nil)
        #expect(ShortcutParser.parse("fn+b") == nil)
    }

    @Test func refusesAnUnknownKey() {
        #expect(ShortcutParser.parse("cmd+f19") == nil)
        #expect(ShortcutParser.parse("cmd+pageup") == nil)
    }

    @Test func refusesNonsense() {
        #expect(ShortcutParser.parse("") == nil)
        #expect(ShortcutParser.parse("+") == nil)
        #expect(ShortcutParser.parse("cmd+") == nil)
    }

    /// Positional, not lexical. A few spot checks against the values Carbon
    /// actually uses, because a wrong entry here registers a shortcut that
    /// silently fires on the wrong key.
    @Test func theKeyCodesArePositional() {
        #expect(ShortcutParser.keyCodes["a"] == 0)
        #expect(ShortcutParser.keyCodes["b"] == 11)
        #expect(ShortcutParser.keyCodes["z"] == 6)
        #expect(ShortcutParser.keyCodes["space"] == 49)
        #expect(ShortcutParser.keyCodes["escape"] == 53)
    }

    /// Two keys sharing a code would make one of them unregisterable and the
    /// other fire twice.
    @Test func noTwoKeysShareACode() {
        let codes = ShortcutParser.keyCodes.values
        #expect(Set(codes).count == codes.count)
    }
}
