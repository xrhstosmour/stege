<div align="center">

<img src=".github/assets/icon.png" width="128" alt="Stege">

# Stege

**A macOS menu bar replacement, with `AeroSpace` and `yabai` support.**

Your window manager's workspaces, the frontmost application's menus, and the
usual status widgets, in a panel that replaces the system menu bar.

The name is Greek: *στέγη*, *stégi*, the roof. The shelter over everything
beneath it, which is what a menu bar is.

</div>

![The Stege bar](.github/assets/bar.png)

## Install

```bash
brew tap xrhstosmour/stege
brew install --cask stege
```

Then hide the system menu bar: **System Settings → Control Center → Automatically
hide and show the menu bar → Always**.

Stege is signed with a self-signed certificate rather than an Apple Developer ID,
so it cannot be notarised. What stands in for that is Homebrew's `sha256` check
and a build provenance attestation on every release, so the archive traces back
to the commit and workflow that produced it:

```bash
gh attestation verify Stege.zip --repo xrhstosmour/stege
```

## Configure

Stege reads `~/.config/stege/config.toml`. The file is watched, so saving it
applies immediately with no restart.

```bash
mkdir -p ~/.config/stege
curl -o ~/.config/stege/config.toml \
  https://raw.githubusercontent.com/xrhstosmour/stege/main/example/config.toml
```

[**`example/config.toml`**](example/config.toml) is the reference. Every setting
is in it, with the values it accepts written above it. This file deliberately
does not repeat them.

The shape of it:

```toml
theme = "system"                 # system, light, dark

[widgets]
displayed = [                    # the bar, left to right
    "default.appleMenu", "default.spaces", "default.applicationMenu",
    "spacer",
    "default.reveal", "default.display", "default.audio",
    "default.bluetooth", "default.network", "default.battery",
    "divider", "default.notifications", "default.time",
]

[widgets.default.battery]        # each widget's own table
style = "inside"

[bar.foreground]                 # the bar itself
height = "menu-bar"
```

Three optional shortcuts: `toggle-shortcut` hides and shows the bar,
`reveal-shortcut` appends the other applications' status items,
`menu-shortcut` opens the frontmost application's first menu.

## What it does

**Workspaces** from `AeroSpace` or `yabai`, with an icon per window, each bar
showing only its own display's.

**The frontmost application's menus**, drawn in the bar and opened as real
`NSMenu`s, so arrows, Return, Escape and type-select all work.

**The other applications' status items**, appended behind a chevron and read
through the Accessibility API rather than photographed, so it needs no Screen
Recording. Right-click one to hide it for good.

**Sound**, with what is playing underneath it.

![The sound popup](.github/assets/sound.png)

**The screen**: a brightness slider per display, spoken to over DDC/CI on
external monitors so it moves the real backlight, the resolution and refresh rate
of each, Night Shift and True Tone. It says when the lid is shut.

![The display popup](.github/assets/display.png)

**The battery**, with health and cycle count.

![The battery popup](.github/assets/battery.png)

**The clock and calendar**, with the month and the day's events.

![The calendar popup](.github/assets/calendar.png)

**Wi-Fi**, **Bluetooth**, **notifications**, **updates waiting**, **CPU and
memory**, **the input source**, and **microphone, camera and screen recording
in-use indicators**.

## What it will not do

Stege never presses a control in one of macOS's own panels to get at something,
and never moves the pointer. Everything it shows is either public API or read
from the menu bar, and everything it changes, it changes directly.

That rules some things out, and they are gone rather than faked: switching Focus
or Low Power Mode, and the AirPlay and screen mirroring pickers. Notifications
are collected from the banners macOS draws as they arrive, so anything delivered
before Stege started is not in the list.

Each one is written up in [the open issues](https://github.com/xrhstosmour/stege/issues)
with what was measured, why it is like that, and what would close it.

## Permissions

Asked for only when a widget you have enabled needs one. A window at first launch
lists whatever is still missing.

| Permission | Needed for |
| --- | --- |
| Accessibility | The application menus, the Apple menu, the appended status items, the notification list |
| Bluetooth | The Bluetooth widget |
| Location | The Wi-Fi network name |
| Calendars | Events in the clock and calendar popup |
| Automation | Reading `Spotify` and `Music` for what is playing |

No Full Disk Access, ever. It would read Mail, Messages and Safari history along
with everything else, which is too much for a menu bar.

## Privacy

No telemetry, no self-updater, and one outbound request: album artwork, fetched
from the player's own servers only when the sound popup is open on a track whose
player gave a link rather than the image. `fetch-artwork = false` refuses even
that.

## Forked from barik

A fork of [`barik`](https://github.com/mocki-toki/barik) by Simon Butenko, whose
author stopped maintaining it and suggested people fork it. This fork keeps the
look and changes three things: it refreshes on window manager events instead of
polling four times a second, it has no self-updater, and it draws the frontmost
application's menus.

## Contributing

[`AGENTS.md`](AGENTS.md) has the conventions and how to verify a change without
Xcode. `cd Tests && swift test`.

## Releasing

A release is a tag. Pushing one builds, signs, attests and publishes the archive,
and the version comes from the tag, so nothing in the project needs bumping
first.

```bash
git tag v0.X.Y && git push origin v0.X.Y

# Watch that tag's run, not the newest one. `--limit 1` on its own catches the
# previous tag's finished run, which has published a checksum taken from a 404.
gh run list --branch v0.X.Y --limit 1
```

Then bump the cask in [`homebrew-stege`](https://github.com/xrhstosmour/homebrew-stege),
which is a separate repository and a separate pull request. Take the checksum
from the archive the release actually serves, never from a local build:

```bash
curl -sL -o Stege.zip \
  https://github.com/xrhstosmour/stege/releases/download/v0.X.Y/Stege.zip
shasum -a 256 Stege.zip
```

Put that in `Casks/stege.rb` with the new `version`, then `brew style Casks/stege.rb`
and open the pull request. The tap's own CI re-downloads the archive and checks the
declared `sha256` against it, so a bump written before the release has finished
publishing fails there rather than at `brew install`.

Once it is merged, `brew upgrade --cask stege`.

## Credits

`barik` by [Simon Butenko](https://github.com/mocki-toki), MIT. Widget ideas from
[`barik-enhanced`](https://github.com/MateoCerquetella/barik-enhanced) by Mateo
Cerquetella, MIT.

## License

MIT, see [LICENSE](LICENSE). The original copyright notice is kept alongside this
fork's.
