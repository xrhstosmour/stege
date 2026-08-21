# Stege

A macOS menu bar replacement, with `AeroSpace` and `yabai` support.

Shows your window manager's workspaces, the frontmost app's menus, and the usual status
widgets, in a panel that replaces the system menu bar.

*Stege*, στέγη, is the roof: the shelter over everything beneath it.

## Forked from barik

Stege is a fork of [`barik`](https://github.com/mocki-toki/barik) by Simon Butenko. Its author
[stopped maintaining it](https://github.com/mocki-toki/barik#readme) and suggested people fork
it, so this one does, keeping the look and fixing three things.

**Performance.** Upstream polls the window manager every 0.1 seconds, and each tick spawns
four separate `aerospace` calls. Measured on an M-series laptop, one call costs 14 ms, so the
bar burns around 560 ms of CPU per second, over half a core, permanently. Stege refreshes on
window manager events instead, with one call and a slow safety-net poll.

**Security and privacy.** Upstream's self-updater downloads any `.zip` from a GitHub release
and replaces the app in `/Applications` without checking a code signature. For an app holding
Accessibility permission, a tampered release means a compromised machine. Stege has no
self-updater and installs through Homebrew, which verifies checksums. It makes no outbound
network requests and collects no telemetry.

**App menus.** The frontmost app's menus, File, Edit, View and the rest, drawn in the bar via
the Accessibility API. Prototyped upstream in
[issue #5](https://github.com/mocki-toki/barik/issues/5) but never released.

## Install

```bash
brew tap xrhstosmour/stege
brew install --cask stege
```

Homebrew requires third-party casks to be trusted before install, which the `tap` step
prompts for.

Then hide the system menu bar: System Settings, Control Center, Automatically hide and show
the menu bar, Always.

## Permissions

Stege asks for Accessibility, which it needs to read the frontmost app's menus and to activate
the entry you pick. It is not sandboxed, because the Accessibility API is unavailable to
sandboxed apps.

## Configuration

Stege reads `~/.config/stege/config.toml`, falling back to `~/.stege-config.toml`. See
[`example/`](example) for a starting point.

## Status

Early, and not yet installable. Track progress in the open pull requests.

## Credits

`barik` by [Simon Butenko](https://github.com/mocki-toki), MIT. Widget ideas from
[`barik-enhanced`](https://github.com/MateoCerquetella/barik-enhanced) by Mateo Cerquetella,
MIT.

## License

MIT, see [LICENSE](LICENSE). The original copyright notice is kept alongside this fork's.
