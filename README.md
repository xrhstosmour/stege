# Stege

A macOS menu bar replacement, with `AeroSpace` and `yabai` support.

Shows your window manager's workspaces, the frontmost app's menus, and the usual status
widgets, in a panel that replaces the system menu bar.

*Stege*, στέγη, is the roof: the shelter over everything beneath it.

![The Stege bar](.github/assets/bar.png)

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

### Gatekeeper

Stege is signed, but with a self-signed certificate rather than an Apple Developer ID, so it
cannot be notarised without a paid Apple account. On first launch macOS will say
`"Stege.app" Not Opened`. Open System Settings, Privacy & Security, scroll to the bottom and
choose Open Anyway.

What stands in for notarisation is that Homebrew checks the download against the `sha256` in
the cask, and every release is built by GitHub Actions with build provenance attestation, so
the archive can be traced back to the commit and workflow that produced it.

## Permissions

Stege asks for permissions only when a widget you have enabled actually needs one, and a
window at first launch lists whatever is still missing.

| Permission | Needed for | Without it |
| --- | --- | --- |
| Accessibility | Reading and driving the frontmost app's menus, the Apple menu, and the system switches the popups expose | The menus are replaced by an "Enable Accessibility" button, and the system switches do nothing |
| Bluetooth | The Bluetooth widget | The glyph shows a small lock and opens the settings pane |
| Location | Showing the Wi-Fi network name, and the nearby network list | The name is hidden, everything else still works |
| Calendars | Events in the clock widget and calendar popup | Events are omitted |

Stege is not sandboxed, because the Accessibility API is unavailable to sandboxed apps.

## Configuration

Everything is set in one file. Stege reads `~/.config/stege/config.toml`, falling back to
`~/.stege-config.toml`. The file is watched, so saving it applies immediately with no restart.

[`example/config.toml`](example/config.toml) is a complete, commented copy of every option.
Start from it:

```bash
mkdir -p ~/.config/stege
curl -o ~/.config/stege/config.toml \
  https://raw.githubusercontent.com/xrhstosmour/stege/main/example/config.toml
```

### Choosing what is in the bar

`widgets.displayed` is the bar, left to right. Add an entry to show a widget, remove it to
hide it, reorder the list to move things around.

```toml
theme = "system"          # system, light, dark
hidden = false            # true takes the bar away entirely, see below
# toggle-shortcut = "cmd+alt+b"  # hides and shows it from anywhere

[widgets]
displayed = [
    "default.applemenu",
    "default.spaces",
    "default.appmenus",
    "spacer",             # pushes everything after it to the right
    "default.audio",
    "default.battery",
    "divider",            # a thin separator
    "default.time",
]
```

Every widget, and what it shows:

| Widget | Shows |
| --- | --- |
| `default.applemenu` | The Apple logo, opening the real Apple menu |
| `default.spaces` | Window manager workspaces, with an icon per window |
| `default.appmenus` | The frontmost app's menus |
| `default.reveal` | A chevron that appends the other applications' menu bar items to the bar |
| `default.monitor` | CPU, memory, and optionally network throughput |
| `default.privacy` | Microphone and camera in-use indicators |
| `default.stayawake` | A cup, while something is keeping the display awake |
| `default.notifications` | A bell listing recent notifications and the Focus modes |
| `default.audio` | Output volume, with a microphone badge when muted |
| `default.keyboardlayout` | The current input source, with a popup for switching between the enabled ones |
| `default.bluetooth` | Bluetooth state and connected device battery |
| `default.network` | Wi-Fi and Ethernet state |
| `default.battery` | Charge, with health and cycles in the popup |
| `default.nowplaying` | What is playing, with transport controls |
| `default.time` | Clock, with a calendar popup |
| `spacer` | Pushes everything after it to the right |
| `divider` | A thin vertical separator |

### Setting a widget up

Each widget takes its settings from its own table. These are the ones worth knowing about,
and `example/config.toml` has the rest.

```toml
[widgets.default.spaces]
space.show-key = true               # the workspace number or letter
window.show-title = true            # the focused window's title
window.title.max-length = 50

[widgets.default.appmenus]
max-menus = 6                       # Chrome exposes 11, which crowds a laptop bar
show-application-name = true        # draw the app's own menu in bold, as macOS does
visibility = "always"               # always, hover, modifier, click
modifier-key = "option"             # option, command, control, shift, function

[widgets.default.audio]
show-percentage = false             # the icon already conveys the level
glyph = "speaker"                   # or "waveform", or "speaker-and-microphone"
show-microphone = true              # `speaker-and-microphone` only

[widgets.default.network]
show-name = false                   # showing the name asks for Location
hide-when-disconnected = false

[widgets.default.battery]
style = "inside"                    # number in the battery, or "plain" for beside it
show-percentage = true
warning-level = 30
critical-level = 10

[widgets.default.notifications]
show-control-centre = false         # a second control for Control Center

[widgets.default.time]
format = "E d MMM  HH:mm"
calendar.show-events = true
# calendar.allow-list = ["Home", "Personal"]

[widgets.default.time.popup]
# vertical is the month with the day's events under it, horizontal puts them
# beside it, box is the month on its own.
view-variant = "vertical"
```

### Hiding the bar

`hidden = true` takes the bar away entirely, leaving the real macOS menu bar and
every third-party status item on it reachable. The file is watched, so it takes effect as soon
as you save, with no restart.

The `default.reveal` chevron works from the bar and has two modes.

`extras`, the default, appends the other applications' status items to the bar: 1Password,
Docker, Dropbox and whatever else is running. Clicking one presses the real item, so that
application opens its real menu, with no pointer movement and without the menu bar coming down.

Every application publishes its status item through the Accessibility API, under
`AXExtrasMenuBar`, so the item can be found, ordered the way macOS orders it, and pressed,
using the same permission the app menus already need. Nothing is screenshotted and no window is
moved.

The row shows what the menu bar shows and no more. A menu bar out of room does not drop items,
it parks them under the notch, where they keep a window, a position and a real width and are
simply never drawn, so those are left out.

`always-show` keeps chosen applications in the bar permanently, outside the chevron, and
`hidden` drops ones you never want to see. Both take bundle identifiers, which you can read off
the row's tooltip target with `osascript -e 'id of app "1Password"'`. Three icons in the bar and
the rest behind the chevron is the point of a tray manager, more than matching the system's own
glyphs is, and it needs no permission.

The icon drawn is the application's own, in one colour by default, because a row of full-colour
icons beside Stege's single-weight glyphs looks like two bars stapled together. It is not the
glyph the application actually puts in the menu bar. Reading that means photographing the item,
which is what Bartender and Ice do: it costs a Screen Recording grant, and because a hidden
status item is parked off screen where `ScreenCaptureKit` refuses to capture it, the menu bar
has to be pulled down for every refresh.

`collapse` is the older behaviour. It takes Stege away so the real menu bar underneath becomes
reachable, and leaves a small button in the middle of the menu bar, just left of the notch on a
display that has one, to bring it back. The middle because both ends are taken: the Apple menu
is at one and the status items this just uncovered are at the other. It stays collapsed until
that button is pressed, because a status item's menu opens below the menu bar and a bar that
came back on its own would land on top of it.

```toml
[widgets.default.reveal]
mode = "extras"        # or "collapse"
icon-size = 15         # `extras` only: how big the appended icons are drawn
icon-style = "monochrome"  # `extras` only: or "colour" to leave them as they ship
always-show = []       # `extras` only: bundle ids that sit in the bar permanently
hidden = []            # `extras` only: bundle ids that never appear at all
sticky = true          # `collapse` only, false: come back on pointer movement
return-threshold = 80  # `collapse` and `sticky = false` only: points the pointer must drop
timeout = 10           # `collapse` and `sticky = false` only: seconds before it returns
```

`toggle-shortcut` gives you the same switch from the keyboard, anywhere:

```toml
toggle-shortcut = "cmd+alt+b"
```

Write it as modifiers then a key, joined with `+`. `cmd`, `command`, `opt`, `option`, `alt`,
`ctrl`, `control` and `shift` all resolve, and the key can be a letter, a digit, a function
key, or one of `space`, `return`, `tab`, `escape`, `delete`, `left`, `right`, `up`, `down`.
At least one modifier is required. Leave the setting out to register nothing.

The shortcut is independent of `hidden`: with `hidden = true` in the file the bar stays away
whatever you press, since the file is the stronger statement.

### Appearance

```toml
[experimental.background]
displayed = true
# 1 to 6 blur the desktop behind the bar. 7 is solid black, which makes the
# notch disappear into the bar on a notched display.
blur = 7
height = "menu-bar"                 # menu-bar, default, or a number of points

[experimental.foreground]
height = "menu-bar"
horizontal-padding = 12
spacing = 10
```

## What it looks like

### App menus

Clicking a title opens Stege's own rendering of that menu. Selecting an entry presses the real
Accessibility element, so the app behaves exactly as it would through its own menu bar.

![The File menu open](.github/assets/appmenu.png)

`visibility` decides when they appear:

| Value | Behaviour |
| --- | --- |
| `always` | The menus sit in the bar next to the workspace pills, the way macOS shows them |
| `hover` | The menus take the workspace pills' place while the pointer rests on the pill of the window that is already focused, and fade back out when it moves off them |
| `modifier` | The same swap, held open by a key instead of the pointer |
| `click` | The same swap, made by clicking the pill of the window that is already focused, and undone by clicking the application icon the menus appear next to |

Under `hover`, `modifier` and `click` the menus replace the pills rather than crowding in
beside them, so the bar shows one or the other and never grows. `hover` and `click` use the
pills themselves as the target, so keep `default.spaces` in `widgets.displayed` for those, or
use `modifier`, which needs no target.

Under `hover` and `click` only one pill is the target, the window that is already focused, and
under `hover` the menus fall away again as soon as the pointer moves off them. Both of those
are there so the rest of the bar stays usable: with every pill a target and the reveal held for
the whole width of the bar, aiming at another workspace swapped it out for the menus on the way
and no window in it could be clicked at all.

### Apple menu

About This Mac, System Information, then Sleep, Restart, Shut Down and Log Out. Each row presses
the real menu item, so the confirmations macOS raises are its own. The system menu carries
fifteen entries, several duplicated because macOS keeps the option-key alternates in the same
list, and `short-menu = false` opens that one instead.

![The Apple menu open](.github/assets/applemenu.png)

### Sound

One icon in the bar, the speaker, whose arcs say the level the way macOS's own does. `glyph =
"waveform"` is the neutral alternative, and `"speaker-and-microphone"` restores the pair. The
microphone lives in the popup either way, and the privacy widget is what says when something is
listening.

The popup is built as two matching blocks. Output and input each get the same three things in the same order: what it is,
a level slider with its percentage, and the devices to choose between. Clicking the glyph at
the left of either slider mutes that half.

Scrolling on the icon changes the volume and right-clicking it mutes, so the popup is only
needed for picking a device. Output devices that carry no mute property, the built-in speakers
among them, are muted by dropping the level to zero and put back where they were on the way
out. An input device that
exposes no settable gain, which is most USB and Bluetooth microphones, shows muted or not in
the slider's place, since a slider that cannot move is worse than no slider.

![The sound popup](.github/assets/sound.png)

### Wi-Fi

The current connection and its signal, then the networks in range, with a switch for the
radio itself. Clicking a network you have joined before, or an open one, connects straight
away. A secured network you have not saved opens a password field under its row.

The password is handed to CoreWLAN and dropped. Stege never stores it: `associate` writes the
successful one to the system keychain, which is the same place the system Wi-Fi settings put
it, and the next connection to that network needs no password at all.

![The Wi-Fi popup](.github/assets/wifi.png)

### Notifications

A bell whose popup lists the notifications that have come in and every Focus, including any you
have made yourself.

The notification list is Stege's own. macOS's list is not readable: there is no public API, the
database it used to live in is gone on macOS 26 and the group container that held it is empty,
and the only place it appears is inside the Notification Center panel's accessibility tree,
which exists only while that panel is on screen. Scraping it would mean throwing the real panel
open over a third of the display on every refresh. What is readable is a notification
*arriving*, because Notification Center draws each banner as a window in its own process, so the
bar watches for those and keeps what it reads. Two limits follow, and the popup says both: the
list starts when Stege starts, and Clear empties Stege's list rather than macOS's.

It does not show the notifications and it does not open Notification Center. There is no public
API for the notification list, and the private database behind it would mean holding Full Disk
Access, which also grants read access to Mail, Messages and browser data. Handing off to
Notification Center is no better: it slides over the screen and takes the popup with it, so the
two are never usefully on screen together, and the trackpad gesture and the shortcut in
Keyboard settings already do it without a row here. `show-control-centre` adds a second control
for Control Center.

The Focus list and the switching both go through Control Center's own controls. `~/Library/DoNotDisturb/DB`, where macOS
keeps the state, turns out to need Full Disk Access, and the private `DoNotDisturb` framework
answers only callers holding an Apple-issued entitlement, so Control Center is the only route
left.

Reading it means opening a Control Center panel, so the list is read once and kept, not on
every popup. The circular arrow next to the `Focus` heading reads it again, which is what to
press after adding a Focus in System Settings. Between switches the tick can be stale if a
Focus is changed from somewhere else.

### Bluetooth

Every paired device is listed, connected ones first, with a battery bar for the devices that
report a level. Clicking a device connects or disconnects it. `Scan` looks for devices that are
not paired yet and offers to pair them, and stops as soon as the popup closes, because an
inquiry keeps the radio busy and degrades whatever is already connected.

The switch in the header turns the controller on and off. macOS has no public API for that, so
it presses the switch in Control Center's own Bluetooth panel, the same route Low Power Mode
and Focus take.

![The Bluetooth popup](.github/assets/bluetooth.png)

### Battery

Charge, time estimate, health and cycles, and a switch for Low Power Mode.

The charge is drawn as the battery outline with the level filled in behind the
number, which sits in the body of the battery. The outline is the same weight as
every other glyph in the bar and the fill is dimmed, so the battery stops being
the brightest object on screen while staying the only one carrying a number.
Full brightness is kept for low and for charging. `style = "plain"` puts the
outline and the number side by side instead, which is what macOS itself does.

The switch is the one macOS puts in the battery menu extra's own panel, pressed through the
Accessibility API. Nothing else can write that setting: `pmset` needs root, and the private
`LowPowerMode` framework answers only callers holding an Apple-issued entitlement. macOS
therefore draws its own panel for a moment while the switch flips.

If you have set the macOS menu bar to hide, which most people running Stege have, the pointer
also goes to the top of the screen and back for about half a second. A hidden menu bar parks
its items above the screen, where pressing them does nothing, and only real pointer movement
brings them back.

![The battery popup](.github/assets/battery.png)

### Calendar

Page between months, pick a day to see its events from every account the system knows about,
and click one to open it. A meeting link goes to the browser, anything else opens Calendar
showing that event. The plus adds an event to whichever calendar you choose, labelled by
account.

![The calendar popup](.github/assets/calendar.png)

### Popup style

Every popup uses one width, one padding and one row shape, defined in
[`Stege/MenuBarPopup/PopupStyle.swift`](Stege/MenuBarPopup/PopupStyle.swift). Rows that do
something highlight under the pointer, the way the menus they replace do, and rows that only
report something do not.

## Known limitations

**Option-key menu entries are always visible.** macOS hides alternate menu items until Option
is held, so Finder's File menu shows `Close Window` and, on Option, `Close All`. Stege shows
both at once. The Accessibility API exposes no attribute that distinguishes an alternate from
an ordinary item, confirmed by dumping every attribute of both, so there is no way to tell
them apart without guessing, and a guess would hide real entries in other apps.

**No screen recording indicator.** There is no public API to detect another app capturing the
screen, so the privacy widget covers the microphone and camera only.

**Bluetooth microphones report as inactive.** A platform limitation of the property the
privacy widget reads.

## Credits

`barik` by [Simon Butenko](https://github.com/mocki-toki), MIT. Widget ideas from
[`barik-enhanced`](https://github.com/MateoCerquetella/barik-enhanced) by Mateo Cerquetella,
MIT.

## License

MIT, see [LICENSE](LICENSE). The original copyright notice is kept alongside this fork's.
