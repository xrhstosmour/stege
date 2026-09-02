import Testing

@testable import StegeCore

/// The renames shipped in 0.31.0. Anyone upgrading past them has a
/// configuration written in the old spelling, and TOML has no schema, so an
/// unknown table is ignored and an unknown widget identifier draws nothing:
/// without this migration the upgrade silently costs four widgets and every
/// appearance setting, with no error anywhere to say why.
struct ConfigMigrationTests {
    @Test func leavesACurrentConfigurationAlone() {
        let current = """
            theme = "system"

            [widgets]
            displayed = ["default.appleMenu", "default.keyboardLayout"]

            [bar.foreground]
            height = 44
            """
        let result = ConfigMigration.migrate(current)
        #expect(result.isChanged == false)
        #expect(result.text == current)
        #expect(result.applied.isEmpty)
    }

    @Test func renamesEveryWidgetIdentifier() {
        let result = ConfigMigration.migrate("""
            displayed = [
                "default.applemenu",
                "default.appmenus",
                "default.keyboardlayout",
            ]
            """)
        #expect(result.isChanged)
        #expect(result.text.contains("default.appleMenu"))
        #expect(result.text.contains("default.applicationMenu"))
        #expect(result.text.contains("default.keyboardLayout"))
        #expect(result.text.contains("applemenu") == false)
        #expect(result.text.contains("appmenus") == false)
        #expect(result.text.contains("keyboardlayout") == false)
    }

    @Test func renamesTheWidgetTableTheIdentifierNames() {
        let result = ConfigMigration.migrate(
            "[widgets.default.appmenus]\nmax-menus = 6")
        #expect(result.text == "[widgets.default.applicationMenu]\nmax-menus = 6")
    }

    @Test func renamesTheAppearanceTables() {
        let result = ConfigMigration.migrate("""
            [experimental.background]
            blur = 7

            [experimental.foreground]
            height = 44
            """)
        #expect(result.text.contains("[bar.background]"))
        #expect(result.text.contains("[bar.foreground]"))
        #expect(result.text.contains("experimental") == false)
    }

    /// The file is rewritten in place and the watcher reloads it, so the
    /// migration runs again on what it just wrote. A second pass must be a
    /// no-op or the backup would be overwritten with already-migrated text.
    @Test func migratingTwiceIsTheSameAsMigratingOnce() {
        let once = ConfigMigration.migrate("""
            displayed = ["default.applemenu", "default.appmenus"]

            [experimental.foreground]
            height = 44
            """)
        let twice = ConfigMigration.migrate(once.text)
        #expect(twice.isChanged == false)
        #expect(once.text == twice.text)
    }

    @Test func reportsWhatItRewrote() {
        let result = ConfigMigration.migrate("[experimental.foreground]")
        #expect(result.applied == ["[experimental. to [bar."])
    }

    /// A whole configuration from before the renames, so a rule that only works
    /// on a fragment cannot pass.
    @Test func rewritesAWholeOlderConfiguration() {
        let result = ConfigMigration.migrate("""
            theme = "system"
            hidden = false

            [widgets]
            displayed = [
                "default.applemenu",
                "default.spaces",
                "default.appmenus",
                "spacer",
                "default.keyboardlayout",
                "default.battery",
                "default.time",
            ]

            [widgets.default.appmenus]
            max-menus = 6

            [widgets.default.keyboardlayout]
            show-full-name = false

            [experimental.background]
            blur = 7

            [experimental.foreground]
            height = 44
            """)
        #expect(result.isChanged)
        #expect(result.applied.count == 4)
        for legacy in ["applemenu", "appmenus", "keyboardlayout", "experimental"] {
            #expect(
                result.text.contains(legacy) == false,
                "\(legacy) survived the migration")
        }
        // Everything that was not a rename is untouched.
        #expect(result.text.contains("default.spaces"))
        #expect(result.text.contains("max-menus = 6"))
        #expect(result.text.contains("blur = 7"))
    }

    /// Ordering matters: a rule that matched inside a longer name would leave
    /// half of it rewritten. Nothing in the table does today, and this fails
    /// if a future rule does.
    @Test func noRenameMatchesInsideAnother() {
        for outer in ConfigMigration.renames {
            for inner in ConfigMigration.renames where inner.old != outer.old {
                #expect(
                    outer.old.contains(inner.old) == false,
                    "\(inner.old) matches inside \(outer.old)")
            }
        }
    }
}
