# Abaxion

A macOS menu bar replacement, with `AeroSpace` and `yabai` support.

Shows your window manager's workspaces, the frontmost app's menus, and the usual status
widgets, in a panel that replaces the system menu bar.

## Forked from barik

Abaxion is a fork of [`barik`](https://github.com/mocki-toki/barik) by Simon Butenko. Its
author [stopped maintaining it](https://github.com/mocki-toki/barik#readme) and suggested
people fork it, so this one does, keeping the look and fixing three things.

**Efficiency.** Upstream polls the window manager every 0.1 seconds, and each tick spawns four
separate `aerospace` calls. Measured on an M-series laptop, one call costs 14 ms, so the bar
burns around 560 ms of CPU per second, over half a core, permanently. Abaxion refreshes on
window manager events with one call and a slow safety-net poll, roughly 7 ms per second.

**Security.** Upstream's self-updater downloads any `.zip` from a GitHub release and replaces
the app in `/Applications` without checking a code signature. For an app holding Accessibility
permission, a tampered release means a compromised machine. Abaxion has no self-updater and
installs through Homebrew, which verifies checksums.

**App menus.** The frontmost app's menus, File, Edit, View and the rest, drawn in the bar via
the Accessibility API. Prototyped upstream in
[issue #5](https://github.com/mocki-toki/barik/issues/5) but never released.

*Abax*, ἄβαξ, is the flat slab crowning a column, the topmost piece the entablature rests on.

## Install

```bash
brew install --cask xrhstosmour/abaxion/abaxion
```

Then hide the system menu bar in System Settings, Control Center, Automatically hide and show
the menu bar, Always.

## Configuration

Abaxion reads `~/.config/abaxion/config.toml`, falling back to `~/.abaxion-config.toml`. See
[`example/`](example) for a starting point.

## Status

Early. The rebrand has landed, the three changes above are in progress. Not installable yet.

## Credits

`barik` by [Simon Butenko](https://github.com/mocki-toki), MIT. Widget ideas from
[`barik-enhanced`](https://github.com/MateoCerquetella/barik-enhanced) by Mateo Cerquetella,
MIT.

## License

MIT, see [LICENSE](LICENSE). The original copyright notice is kept alongside this fork's.
