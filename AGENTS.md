# Stege agent guide

Tips and rules for any AI agent (Claude Code, opencode, others) working in this repository. Read
this first. General coding, commit and communication conventions are summarized here so this guide
is self-contained.

## What this repository is

Stege is a macOS menu bar replacement written in Swift and SwiftUI, forked from
[`barik`](https://github.com/mocki-toki/barik). It draws its own panel over the system menu bar and
shows the window manager's workspaces, the frontmost application's menus, and the usual status
widgets.

- `Stege/Widgets/`: one directory per widget. A widget is a bar view, usually a manager that reads
  the state, and usually a popup.
- `Stege/Core/`: the parts that are pure logic and no drawing. Everything here is under test.
- `Stege/MenuBarPopup/`: the single shared popup panel and the styling every popup uses.
- `Stege/Views/`: the bar itself, its background, and `BarStyle`, which owns every size and colour.
- `Stege/Config/`: the TOML model, the file watcher, and the migration for older files.
- `example/config.toml`: a complete, commented copy of every option. It is the reference, not the
  README, which points at it.
- `Tests/`: a SwiftPM package testing `Stege/Core`.

## Four rules the owner set

1. **Sparse bar, rich popups.** The bar is glyphs. Detail belongs in the popup behind them.
2. **No network requests.** Album artwork is the single disclosed exception and is refusable with
   `fetch-artwork = false`. Nothing else may make one, and there is no telemetry and no self-updater.
3. **Cut hard and report removals.** Prefer deleting to keeping something that does not earn its
   place, and say plainly in the pull request what went.
4. **The application never simulates a click.** Not on macOS's own panels, and not on its own bar
   either: a shortcut that worked by clicking the chevron would break the moment the bar was
   hidden, which is exactly when it is wanted. Where macOS exports a real call, use the call; where
   it exports an accessibility action, press the element. Simulating clicks to *verify* a change by
   hand is fine, `cliclick` is the tool.

## Known limitations

What macOS will not let Stege do is tracked in
[the open issues](https://github.com/xrhstosmour/stege/issues), not in the README. Before concluding
that something is impossible, read them: each says what was measured and what would close it. Before
adding a new one, measure it the same way rather than asserting it.

## Verifying a change

There is no Xcode on the owner's machine, only Command Line Tools, so `xcodebuild` cannot be run
locally. Two things can:

```bash
# Type-check the whole application. The baseline is ZERO errors.
swiftc -typecheck -sdk $(xcrun --show-sdk-path --sdk macosx) \
  -target arm64-apple-macos14.0 \
  -I <path to a built TOMLDecoder>/.build/debug/Modules \
  $(find Stege -name '*.swift')

# Run the tests.
cd Tests && swift test
```

**Never accept a non-empty type-check baseline.** This has been near useless twice, and looked fine
both times. `swiftc` cannot see the asset-catalog accessors Xcode generates, so writing
`Color.noActive` instead of `Color("Foreground Outside")` makes a view an error type and everything
chaining off it goes unchecked. Worse, a `#Preview` macro that cannot expand is **fatal**: the
compiler stops before type-checking anything else, so a run reporting only that error means nothing.
Use `PreviewProvider`, never `#Preview`. Never filter compiler output by broad patterns.

`swift test` needs the `Testing` framework put on the search path when only Command Line Tools are
installed. `Tests/README.md` has the invocation.

## Merge workflow

- Rebase the feature branch onto `main`, push, then merge with:
  ```bash
  gh pr merge <n> --merge --delete-branch --subject 'Merge branch `<branch>`'
  ```
- CI must be green first. Both jobs, `Test` and `Build`. If it is red, fix on the branch and push,
  never merge around it.
- Never push to `main`. Force-push is fine on a feature branch with `--force-with-lease`, never on
  `main`.
- Keep pull requests single-topic, non-stacked and independently mergeable.
- Assign the author and add one existing label to every pull request. Never create a label.

## Releasing

A release is a tag. Pushing `v*` builds, signs, attests and publishes the archive. The version comes
from the tag, so `MARKETING_VERSION` in the project is not the release version and does not need
bumping.

### 1. Tag the application

```bash
bin/release.sh [patch|minor|major]   # patch by default
```

Bumps the latest `vX.Y.Z` tag, confirms before doing anything, tags `main`, pushes, and watches the
tagged run rather than `--limit 1` on its own, which catches the previous tag's finished run and has
published a checksum taken from a 404 page. Refuses to run off `main`, with a dirty tree, or with
`main` behind `origin/main`.

The `Notarize` and `Update the Homebrew tap` steps show as skipped. That is expected: there is no
paid Apple account and no `TAP_TOKEN`, so the build is self-signed and the tap is bumped by hand.

### 2. Bump the tap

[`homebrew-stege`](https://github.com/xrhstosmour/homebrew-stege) is a separate repository, cloned
locally at `/opt/homebrew/Library/Taps/xrhstosmour/homebrew-stege`, and takes its own single-topic
pull request.

Take the checksum from the archive the release actually serves. Never from a local build, and never
before the release run has finished:

```bash
curl -sL -o Stege.zip \
  https://github.com/xrhstosmour/stege/releases/download/v0.X.Y/Stege.zip
shasum -a 256 Stege.zip
```

Edit `version` and `sha256` in `Casks/stege.rb`, then:

```bash
brew style Casks/stege.rb
brew audit --cask --strict xrhstosmour/stege/stege   # by name, a path is refused
```

Branch as `bump/stege-0.X.Y`, commit as ``Bump `stege` to 0.X.Y``, open the pull request, wait for
its `Audit` checks, merge it. The tap's CI re-downloads the archive and checks the declared `sha256`
against it, so a bump written too early fails there rather than at `brew install`.

### 3. Install and verify

```bash
brew upgrade --cask stege
osascript -e 'tell application "Stege" to quit'
open -a Stege
```

`brew upgrade` does not restart the application, so verifying without the quit and relaunch above
checks the old binary. Then actually look at what changed, on screen.

## Changing the configuration file

Renaming anything in `config.toml` is a breaking change with no error attached to it. TOML has no
schema: an unknown table is ignored and an unknown widget identifier draws nothing, so an upgrade
silently loses whatever was renamed. **Add the old and new spelling to `ConfigMigration.renames` in
the same commit**, and add a test. The migration rewrites the file in place once and keeps the
original as `.backup`.

## Conventions

- Swift 6 toolchain, deployment target 14.0, no external dependencies but `TOMLDecoder`.
- **Keep the deployment target on a whole release.** Homebrew's `depends_on macos:` only accepts
  named releases, so a floor of 14.6 cannot be expressed in the cask: it said `:sonoma`, and 14.0
  through 14.5 could install a binary macOS then refused to launch, with nothing useful said about
  why. Check with `otool -l <binary> | grep minos`.
- **Sizes and colours come from `BarStyle`**, never from a literal. A view writing `.white` or
  `Color.black` breaks the light theme, which is a real theme with its own asset values, not a
  flipped dark one. Hover comes from `BarStyle.hoverFill` and `BarStyle.hoverAnimation` or the
  `.barHover()` modifier, so the same gesture behaves the same way everywhere.
- Asset colours are read as `Color("Foreground Outside")`. See the type-check warning above.
- **A popup that starts something must stop it.** `MenuBarPopup.dismissPanel` drops the hosting view
  so `onDisappear` fires. Pair every `onAppear` that starts a timer, a scan or an observer with an
  `onDisappear`. Four popups once ran their work for the life of the process because ordering the
  panel out does not tear down the SwiftUI tree. Verify with
  `sample $(pgrep -x Stege) 5 -f out.txt`, not `ps -o pcpu`, which is a decaying average that hides
  it. `top -l 5 -pid <pid> -stats pid,cpu` for instantaneous numbers.
- Private frameworks are reached through `dlopen`/`dlsym` with a `@convention(c)` signature, or the
  Objective-C runtime. Several answer an unentitled caller with nothing rather than an error:
  `MRMediaRemoteGetNowPlayingInfo` returns an empty dictionary, and every
  `AVOutputContext` system context returns nil. **Probe before building on one.**
- Use single whole words everywhere: `documents` not `docs`, `configuration` not `config`,
  `reference` not `ref`, `temporary` not `tmp`, `previous` not `prev`, `error` not `err`,
  `maximum` not `max`, `index` not `idx`. Common acronyms are fine: `ID`, `URL`, `API`, `HTTP`.
- Comments end with a period and sit above the code they describe, never to the right of it. Say
  why, not what, and record what was measured or ruled out rather than asserting it.
- Commits are single-line, imperative, present tense, one topic, technical identifiers in backticks,
  no co-authors, no trailing punctuation. Around 100 lines each, split anything over 300.
- Pull request titles are short and descriptive with no type prefixes. Bodies use What, Why and
  Testing. Testing lists scenarios actually exercised, never "ran the suite".
- Communication is compact and direct. No em dashes, no semicolons, no emojis, no decorative
  dividers.

## Screenshots

Screenshots in `.github/assets/` are taken on the owner's own machine, so they carry network names,
calendar events and notification text. Redact before committing, and never take a fresh one of the
Wi-Fi, calendar or notifications popup without checking what is in it.
