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

https://github.com/user-attachments/assets/f1cfe9c2-64ba-4784-99b3-e29cf34c47ad

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

The file Stege writes on first run carries every setting it has, each with the
values it accepts written beside it, so the reference is already on your disk.
It is reproduced in full below, and also lives at
[**`example/config.toml`**](example/config.toml) for copying from directly.

Every widget you can put in the bar:

| | |
| --- | --- |
| `default.appleMenu` | The Apple menu, short or full |
| `default.spaces` | Workspaces from `AeroSpace` or `yabai` |
| `default.applicationMenu` | The frontmost application's menu titles |
| `default.reveal` | The other applications' status items, behind a chevron |
| `default.notifications` | Notifications, and what they came from |
| `default.display` | Brightness |
| `default.audio` | Volume, output device, and what is playing |
| `default.microphone` | Input level and device |
| `default.keyboardLayout` | The input source |
| `default.bluetooth` | The radio and its devices |
| `default.network` | Wi-Fi, its networks, and joining one |
| `default.battery` | Charge, health, and the power source |
| `default.time` | The clock, a calendar, and the day's events |
| `spacer` | Pushes what follows to the right |
| `divider` | A rule |

Location Services in use draws its own small dot next to the corner where
macOS draws the microphone/camera/screen-recording one, always, it is not
a widget and is not in the list above.

The full file:

```toml
# Stege configuration.
#
# Read from ~/.config/stege/config.toml, falling back to ~/.stege-config.toml.
# The file is watched, so saving it applies immediately with no restart.
#
# This file is the reference: every setting Stege understands is here, with the
# values it accepts written above it. Anything not listed here is not a setting.
#
# Types, so the notation below is unambiguous:
#   "a" | "b"     one of these strings, quoted
#   true | false  a boolean, unquoted
#   0 to 100      an integer in that range
#   []            a list, of strings unless it says otherwise
#
# A setting left out falls back to the default shown. A configuration written
# for an older version is rewritten in place on first launch, with the original
# kept beside it as config.toml.backup.

# "system" | "light" | "dark"
# system follows System Settings, or force it with one of the other two.
#
# light draws the bar and every popup the way the Dock is drawn: a near-white
# surface with near-black marks on it. Set background.blur to 7 for a solid
# surface in whichever colour the theme calls for, or 1 to 6 to let the desktop
# through.
theme = "system"

# true | false
# Hides the bar entirely, leaving the real macOS menu bar and every
# third-party status item on it reachable. This file is watched, so
# flipping it takes effect immediately with no restart.
hidden = false

# System-wide shortcuts. Modifiers then a key, joined with "+". At least one
# modifier is required, because a bare key would be swallowed everywhere in the
# system. Leave one out to register nothing.
#
# cmd, command / opt, option, alt / ctrl, control / shift, then a letter, a
# digit, a punctuation key, space, return, tab, escape, delete, an arrow, or f1
# through f12.

# Hides and shows the bar, so you do not have to reach for the reveal chevron.
# toggle-shortcut = "cmd+alt+b"

# Appends the other applications' status items to the bar. Only opens the
# row, same as clicking the chevron once.
# reveal-shortcut = "cmd+alt+m"

# Takes the other applications' status items away, and only that. The only
# key that closes the row: `reveal-shortcut` above does not, pressing it
# again while the row is open does nothing.
# reveal-hide-shortcut = "ctrl+."

# Shows the frontmost application's menu titles in place of the workspace
# pills, the same row hovering the focused pill gives, and holds it there.
# Pressing the shortcut again puts it away, so does switching application,
# whose menus these are not. The titles are clicked rather than walked with the
# keyboard, see issue 218.
#
# A combination another application already holds is refused by macOS. Stege
# says so in the system log rather than doing nothing:
#
#     log stream --predicate 'subsystem == "com.xrhstosmour.stege"'
# menu-shortcut = "cmd+alt+f"

[widgets]
# The bar, left to right. Remove an entry to hide that widget entirely, reorder
# the list to move things around. Every identifier Stege understands:
#
#   default.appleMenu        the Apple logo, opening the Apple menu
#   default.spaces           the window manager's workspaces, an icon per window
#   default.applicationMenu  the frontmost application's menus
#   default.reveal           a chevron that appends the other apps' status items
#   default.notifications    a bell, and what has come in since Stege started
#   default.keyboardLayout   the current input source, with a switcher
#   default.display          brightness, resolution, Night Shift, True Tone
#   default.audio            output volume, and what is playing
#   default.microphone       the microphone on its own
#   default.bluetooth        Bluetooth state and connected device battery
#   default.network          Wi-Fi and Ethernet state
#   default.battery          charge, with health and cycles in the popup
#   default.time             the clock, with a calendar popup
#   spacer                   pushes everything after it to the right
#   divider                  a thin vertical separator
#
# default.nowplaying is still accepted so an older configuration is not broken,
# but it is not in the list above because it no longer draws anything useful:
# what is playing moved into the sound popup. It leaves a dimmed note that opens
# that popup and says so. Remove the entry to drop the mark.
#
# Location Services in use draws its own small dot next to the corner where
# macOS draws the microphone/camera/screen-recording one, always: it is not
# a widget, has no identifier, and nothing above or in `displayed` below
# controls it.
displayed = [
    "default.appleMenu",
    "default.spaces",
    "default.applicationMenu",
    "spacer",
    "default.reveal",
    "default.keyboardLayout",
    "default.display",
    "default.audio",
    "default.microphone",
    "default.bluetooth",
    "default.network",
    "default.battery",
    "divider",
    "default.notifications",
    "default.time",
]

# --- Left ------------------------------------------------------------------

[widgets.default.appleMenu]
# any number of points, default 14
icon-size = 14
# The short menu, drawn in the bar's own style, with About This Mac,
# System Information, Log Out, Restart and Shut Down. Set to false to hand
# over to the full system menu instead, which also carries the duplicated
# option-key entries macOS gives no way to tell apart.
short-menu = true

[widgets.default.spaces]
# The workspace number or letter.
space.show-key = true
# The focused window's title.
window.show-title = true
window.title.max-length = 50
# Always show the app name rather than the window title for these.
window.title.always-display-app-name-for = ["Mail", "Chrome", "Arc"]
# Keep minimized windows on their workspace pill across a restart. On by
# default, or an application update would lose every window that happened to
# be minimized at the time. Off, the same window titles this widget already
# draws in the bar stop being written to ~/Library/Preferences in plaintext.
remember-minimized-windows = true

[widgets.default.applicationMenu]
# any whole number, default 6. Chrome exposes 11, which crowds a laptop bar.
max-menus = 6
# Draws the application's own name menu, the first one, in bold, as macOS
# does. That menu is always shown either way, since it holds About and Quit.
show-application-name = true
# When the menus are drawn.
#   always   in the bar beside the workspace pills, as macOS does
#   hover    in place of the pills, while the pointer is in the bar
#   modifier in place of the pills, while modifier-key is held
# hover uses the pills as its target, so keep default.spaces in the bar for it.
visibility = "always"
# "option" | "command" | "control" | "shift" | "function"
modifier-key = "option"

# --- Right -----------------------------------------------------------------

[widgets.default.reveal]
# "extras" | "collapse"
mode = "extras"
# any number of points, default 18. extras only: how big those icons are drawn.
icon-size = 18
# "colour" | "monochrome". extras only: as the applications ship them, or
# flattened to one colour.
icon-style = "colour"
# Applications kept in the bar permanently rather than behind the chevron.
# extras only. Either list takes a bundle identifier or the application's name,
# whichever is easier to write, and the two can be mixed:
#
#   always-show = ["1Password", "com.docker.docker"]
#
# A name is matched whole and without regard to case, so "google drive" and
# "Google Drive.app" both find Google Drive, and "Drive" finds nothing.
always-show = []
# Applications that never appear, behind the chevron or otherwise. Right-click
# an icon in the row and choose Hide to add it here, so it stays gone across
# restarts. Take it out of this list to bring it back.
hidden = []
# true | false, default true. collapse only: stay away until the corner button
# is pressed, rather than coming back when the pointer moves.
sticky = true
# Points the pointer must drop before the bar returns. collapse with
# sticky = false only.
return-threshold = 80
# Seconds before it returns even if the pointer never moves. collapse with
# sticky = false only.
timeout = 10

[widgets.default.notifications]
# The popup lists what macOS has shown a banner for since Stege started.
#
# Every banner is a window Notification Center announces as it draws it, and it
# carries everything a row in the panel does, so the list fills itself without
# Stege opening, pressing or reading anything. The cost: a notification that
# arrived before Stege started, or one macOS delivered without a banner, is not
# in the list at all. Clearing a row clears Stege's copy; macOS keeps its own.
#
# There is no Focus list any more. It came from Control Center, which meant
# opening its panel on screen to read the modes and again to switch one, and
# there is no other route: the store needs Full Disk Access, the private
# DoNotDisturb framework needs an Apple-issued entitlement, and an active Focus
# publishes nothing to the menu bar to read. Focus Settings at the bottom of the
# popup opens where macOS switches them.
# Adds a second control opening Control Center beside the bell.
show-control-centre = false
# Keep the list across restarts. Off by default, because remembering means
# writing every notification's title, subtitle and body to ~/Library/Preferences
# in plaintext, where anything running as you can read them. Left off, the bell
# starts empty after a restart and fills as banners arrive.
remember-between-launches = false
# Notifications clear themselves once they are this many hours old, or the
# moment the lid closes, whichever comes first. Zero turns the automatic
# clearing off.
auto-clear-after-hours = 24

# The screen. Brightness in the bar and on the scroll wheel, and in the popup
# a brightness slider per display, the resolution and refresh rate of each one,
# Night Shift and True Tone. A resolution picked here is applied for the login
# session only, never written permanently.
#
# An external monitor's slider talks DDC/CI over the display cable, the same
# protocol its own buttons use, so it moves the backlight rather than dimming
# the picture in software. A monitor that does not answer says so instead of
# showing a slider that does nothing.
#
# There is no mirror switch. Mirroring two attached monitors onto each other is
# not what people mean by screen mirroring, and AirPlay, which is, cannot be
# offered: macOS keeps the receiver list behind an Apple-only entitlement, so
# every system output context answers an ordinary application with nothing.
# Display Settings at the bottom of the popup is where AirPlay receivers are
# offered, under Add Display.
[widgets.default.display]
# Brightness in the bar, with Night Shift and True Tone in the popup. All three
# are set directly, so nothing opens a system panel. Scrolling the icon changes
# the brightness. The glyph fills with the level, so the number is off by
# default.
show-percentage = false

[widgets.default.audio]
# "speaker" | "waveform"
glyph = "speaker"
# The icon already conveys the level.
show-percentage = false
# What is playing sits in this popup, under the application making the sound,
# with previous, play and next. Album artwork is fetched from the player's own
# servers when the system does not hand the image over directly, which in
# practice means Spotify. It is the only outbound request Stege makes, so it
# can be refused.
fetch-artwork = true

[widgets.default.keyboardLayout]
# "Greek" rather than "GR".
show-full-name = false

[widgets.default.bluetooth]
# The battery of the connected device with least left, beside the mark.
# Connected only: a headset left in a drawer reporting its last known charge is
# worse than saying nothing.
show-battery = true
hide-when-off = false

[widgets.default.network]
# Showing the name requires Location permission, which is only requested when
# this is on, or when the popup that displays it is opened.
show-name = false
hide-when-disconnected = false

[widgets.default.battery]
# "inside" | "plain", inside putting the number in the battery and plain beside
# it, which is what macOS does
style = "inside"
# true | false
show-percentage = true
# 0 to 100. At or below warning-level the fill turns orange, at or below
# critical-level red. Charging is green whatever the level.
warning-level = 30
critical-level = 10

[widgets.default.time]
# A pattern containing J is treated as a locale template, where J means the
# locale decides 12 or 24 hour. Anything else is used literally.
format = "E d MMM  HH:mm"
# time-zone = "America/Los_Angeles"
calendar.format = "HH:mm"
calendar.show-events = true
# "Dinner (in 25m)" rather than "Dinner (20:30)". The useful question from a bar
# is how long you have, not what the clock will read when it starts.
calendar.countdown = true
# calendar.title-max-length = 20
# calendar.allow-list = ["Home", "Personal"]
# calendar.deny-list = ["Work"]

# --- Appearance ------------------------------------------------------------

[bar.background]
displayed = true
# 1 to 6 blur the desktop behind the bar. 7 is the theme's own solid surface,
# black in the dark theme, near-white in the light one, which makes the notch
# disappear into the bar on a notched display.
blur = 7
# "menu-bar" | "default" | a number of points
height = "menu-bar"

[bar.foreground]
# "menu-bar" | "default" | a number of points
height = "menu-bar"
horizontal-padding = 12
# Extra clearance on the right only, on top of horizontal-padding. macOS draws
# its microphone, camera and recording dot in the top corner above every window,
# including this one, and nothing can cover it, and the dot's size and column
# differ by screen. Left out, each screen defaults to whatever
# horizontal-padding still leaves short of its own dot, so the total is right
# on every screen whatever the padding is. Set it only to widen the gap
# further, the same amount on every screen.
# trailing-padding = 12
spacing = 10
```

Four optional shortcuts, none set by default. `toggle-shortcut` hides and
shows the bar. `reveal-shortcut` appends the other applications' status items,
the same thing the chevron does, and only opens the row: it does nothing if
the row is already open. `reveal-hide-shortcut` is the only key that closes
it again. `menu-shortcut` shows the frontmost application's menu titles in
place of the workspace pills and holds them there until you press it again or
switch application.

A combination another application already holds is refused by macOS, and Stege
says which and why in the system log rather than doing nothing:

```bash
log stream --predicate 'subsystem == "com.xrhstosmour.stege"'
```

## What it does

**Workspaces** from `AeroSpace` or `yabai`, with an icon per window, each bar
showing only its own display's.

**The frontmost application's menus**, drawn in the bar and opened as real
`NSMenu`s, so arrows, Return, Escape and type-select all work.

**The other applications' status items**, appended behind a chevron and read
through the Accessibility API rather than photographed, so it needs no Screen
Recording. Right-click one to hide it for good.

**Sound**, with what is playing underneath it.

**The screen**: a brightness slider per display, spoken to over DDC/CI on
external monitors so it moves the real backlight, the resolution and refresh rate
of each, Night Shift and True Tone. It says when the lid is shut.

**The battery**, with health and cycle count.

**The clock and calendar**, with the month and the day's events.

**Wi-Fi**, **Bluetooth**, **notifications**, **the input source**, and
**Location Services in use**, the one sensor macOS draws no corner dot for.

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
lists whatever is still missing, and right-clicking the bar and choosing
Permissions reopens it at any time, to grant, review, or jump to System
Settings and revoke.

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
bin/release.sh [patch|minor|major]   # patch by default
```

Bumps the latest `vX.Y.Z` tag, tags `main`, pushes and watches that tag's run,
not the newest one. `gh run list --branch v0.X.Y --limit 1` on its own catches
the previous tag's finished run, which has published a checksum taken from a
404.

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
