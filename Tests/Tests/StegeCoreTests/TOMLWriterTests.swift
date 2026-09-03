import Testing

@testable import StegeCore

struct TOMLWriterTests {
    @Test func aKeyInATableIsReplacedInPlace() {
        let original = """
            [widgets.default.reveal]
            mode = "extras"
            hidden = []
            sticky = true
            """
        #expect(
            TOMLWriter.setting(
                original, key: "widgets.default.reveal.hidden",
                rawValue: "[\"1Password\"]")
                == """
                [widgets.default.reveal]
                mode = "extras"
                hidden = ["1Password"]
                sticky = true
                """)
    }

    /// The comments are why the file is edited as text rather than decoded and
    /// written back out, so they have to survive.
    @Test func theCommentsAroundItStay() {
        let original = """
            # The bar, left to right.
            [widgets.default.reveal]
            # Applications that never appear.
            hidden = []
            """
        let updated = TOMLWriter.setting(
            original, key: "widgets.default.reveal.hidden", rawValue: "[]")
        #expect(updated.contains("# The bar, left to right."))
        #expect(updated.contains("# Applications that never appear."))
    }

    /// A list long enough to be worth keeping gets written over several lines
    /// by hand. Replacing only the first of them left the rest behind as
    /// nonsense, and the file stopped parsing.
    @Test func aValueSpreadOverSeveralLinesIsReplacedWhole() {
        let original = """
            [widgets.default.reveal]
            hidden = [
                "1Password",
                "Google Drive",
            ]
            sticky = true
            """
        #expect(
            TOMLWriter.setting(
                original, key: "widgets.default.reveal.hidden",
                rawValue: "[\"1Password\", \"Google Drive\", \"Docker\"]")
                == """
                [widgets.default.reveal]
                hidden = ["1Password", "Google Drive", "Docker"]
                sticky = true
                """)
    }

    @Test func aBracketInsideAStringDoesNotOpenAnArray() {
        let original = """
            [widgets.default.reveal]
            hidden = ["a [ name"]
            sticky = true
            """
        #expect(
            TOMLWriter.setting(
                original, key: "widgets.default.reveal.hidden", rawValue: "[]")
                == """
                [widgets.default.reveal]
                hidden = []
                sticky = true
                """)
    }

    @Test func aTrailingCommentDoesNotOpenAnArray() {
        let original = """
            [widgets.default.reveal]
            hidden = []  # nothing yet [
            sticky = true
            """
        #expect(
            TOMLWriter.setting(
                original, key: "widgets.default.reveal.hidden",
                rawValue: "[\"Docker\"]")
                == """
                [widgets.default.reveal]
                hidden = ["Docker"]
                sticky = true
                """)
    }

    @Test func aMissingKeyIsAddedToItsTable() {
        let original = """
            [widgets.default.reveal]
            mode = "extras"

            [widgets.default.time]
            format = "HH:mm"
            """
        #expect(
            TOMLWriter.setting(
                original, key: "widgets.default.reveal.hidden",
                rawValue: "[\"Docker\"]")
                == """
                [widgets.default.reveal]
                mode = "extras"

                hidden = ["Docker"]
                [widgets.default.time]
                format = "HH:mm"
                """)
    }

    @Test func aMissingKeyIsAddedToTheLastTable() {
        let original = """
            [widgets.default.reveal]
            mode = "extras"
            """
        #expect(
            TOMLWriter.setting(
                original, key: "widgets.default.reveal.hidden", rawValue: "[]")
                == """
                [widgets.default.reveal]
                mode = "extras"
                hidden = []
                """)
    }

    @Test func aMissingTableIsAppended() {
        let original = """
            [widgets.default.time]
            format = "HH:mm"
            """
        #expect(
            TOMLWriter.setting(
                original, key: "widgets.default.reveal.hidden",
                rawValue: "[\"Docker\"]")
                == """
                [widgets.default.time]
                format = "HH:mm"

                [widgets.default.reveal]
                hidden = ["Docker"]
                """)
    }

    /// A commented-out example of the key is the shape the file ships in, and
    /// must not be mistaken for the assignment.
    @Test func aCommentedOutKeyIsNotTheAssignment() {
        let original = """
            [widgets.default.reveal]
            # hidden = ["an example"]
            mode = "extras"
            """
        let updated = TOMLWriter.setting(
            original, key: "widgets.default.reveal.hidden", rawValue: "[]")
        #expect(updated.contains("# hidden = [\"an example\"]"))
        #expect(updated.contains("\nhidden = []"))
    }

    @Test func aTopLevelKeyIsReplaced() {
        let original = """
            theme = "system"
            hidden = false
            """
        #expect(
            TOMLWriter.setting(original, key: "theme", rawValue: "\"dark\"")
                == """
                theme = "dark"
                hidden = false
                """)
    }

    @Test func aMissingTopLevelKeyIsAppended() {
        #expect(
            TOMLWriter.setting("theme = \"system\"", key: "hidden", rawValue: "true")
                == "theme = \"system\"\nhidden = true")
    }

    /// The key that shares a prefix with the one being written must be left
    /// alone: `hidden` is not `hidden-extras`.
    @Test func aKeyIsNotConfusedWithALongerOne() {
        let original = """
            [widgets.default.reveal]
            hidden-extras = true
            hidden = []
            """
        #expect(
            TOMLWriter.setting(
                original, key: "widgets.default.reveal.hidden",
                rawValue: "[\"Docker\"]")
                == """
                [widgets.default.reveal]
                hidden-extras = true
                hidden = ["Docker"]
                """)
    }
}
