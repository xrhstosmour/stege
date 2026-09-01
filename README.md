# Stege

A macOS menu bar replacement, with `AeroSpace` and `yabai` support.

Shows your window manager's workspaces, the frontmost app's menus, and the usual status
widgets, in a panel that replaces the system menu bar.

*Stege*, στέγη, is the roof: the shelter over everything beneath it.

![The Stege bar](.github/assets/bar.png)

## Forked from barik

Stege is a fork of [`barik`](https://github.com/mocki-toki/barik) by Simon Butenko, whose author
stopped maintaining it and suggested people fork it. This fork keeps the look and changes three
things.

**Performance.** Upstream polls the window manager every 0.1 seconds with four `aerospace` calls
per tick. Stege refreshes on window manager events instead, with one call and a slow safety-net
poll.

**Security.** Upstream's self-updater replaces the app in `/Applications` without checking a
signature. Stege has no self-updater and installs through Homebrew, which verifies checksums. It
makes no outbound network requests and collects no telemetry.

**App menus.** The frontmost app's menus drawn in the bar via the Accessibility API.

## Install

```bash
brew tap xrhstosmour/stege
brew install --cask stege
```

Then hide the system menu bar: System Settings, Control Center, Automatically hide and show the
menu bar, Always.

Stege is signed with a self-signed certificate rather than an Apple Developer ID, so it cannot be
notarised. On first launch macOS says `"Stege.app" Not Opened`. Open System Settings, Privacy &
Security, scroll to the bottom and choose Open Anyway.

What stands in for notarisation is Homebrew's `sha256` check, plus build provenance attestation
on every release, so the archive traces back to the commit and workflow that produced it.

## Permissions

Stege asks only when a widget you have enabled needs one, and a window at first launch lists
whatever is still missing.

| Permission | Needed for | Without it |
| --- | --- | --- |
| Accessibility | The frontmost app's menus, the Apple menu, and the system switches the popups expose | The menus become an "Enable Accessibility" button, and the switches do nothing |
| Bluetooth | The Bluetooth widget | The glyph shows a small lock and opens the settings pane |
| Location | The Wi-Fi network name and the nearby network list | The name is hidden, everything else still works |
| Calendars | Events in the clock widget and calendar popup | Events are omitted |

Stege is not sandboxed, because the Accessibility API is unavailable to sandboxed apps.

## Configuration

Stege reads `~/.config/stege/config.toml`, falling back to `~/.stege-config.toml`. The file is
watched, so saving it applies immediately with no restart.

[`example/config.toml`](example/config.toml) is a complete, commented copy of every option. Start
from it:

```bash
mkdir -p ~/.config/stege
curl -o ~/.config/stege/config.toml \
  https://raw.githubusercontent.com/xrhstosmour/stege/main/example/config.toml
```

### What is in the bar

`widgets.displayed` is the bar, left to right. Add an entry to show a widget, remove it to hide
it, reorder the list to move things around.

```toml
theme = "system"          # system, light, dark
hidden = false            # true takes the bar away entirely
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

| Widget | Shows |
| --- | --- |
| `default.applemenu` | The Apple logo, opening the real Apple menu |
| `default.spaces` | Window manager workspaces, with an icon per window |
| `default.appmenus` | The frontmost app's menus |
| `default.reveal` | A chevron that appends the other applications' menu bar items to the bar |
| `default.monitor` | CPU, memory, and optionally network throughput |
| `default.privacy` | Microphone and camera in-use indicators |
| `default.stayawake` | A cup, while something is keeping the display awake |
| `default.notifications` | A bell listing the notifications macOS is holding, and the Focus modes |
| `default.audio` | Output volume |
| `default.microphone` | The microphone on its own |
| `default.keyboardlayout` | The current input source, with a popup for switching |
| `default.bluetooth` | Bluetooth state and connected device battery |
| `default.network` | Wi-Fi and Ethernet state |
| `default.battery` | Charge, with health and cycles in the popup |
| `default.nowplaying` | What is playing, with transport controls |
| `default.time` | Clock, with a calendar popup |
| `spacer` | Pushes everything after it to the right |
| `divider` | A thin vertical separator |

### Widget settings

Each widget takes its settings from its own table. These are the ones worth knowing about, and
`example/config.toml` has the rest.

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

[widgets.default.network]
show-name = false                   # showing the name asks for Location
hide-when-disconnected = false

[widgets.default.bluetooth]
hide-when-off = false

[widgets.default.battery]
style = "inside"                    # number in the battery, or "plain" for beside it
show-percentage = true
warning-level = 30
critical-level = 10

[widgets.default.time]
format = "E d MMM  HH:mm"
calendar.show-events = true
# calendar.allow-list = ["Home", "Personal"]

[widgets.default.time.popup]
view-variant = "vertical"           # vertical, horizontal, box
```

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

### Hiding the bar

`hidden = true` takes the bar away entirely, leaving the real macOS menu bar and every
third-party status item reachable. `toggle-shortcut` gives the same switch from the keyboard,
written as modifiers then a key joined with `+`, at least one modifier required.

The `default.reveal` chevron works from the bar and has two modes. `extras`, the default, appends
the other applications' status items to the bar, read through the Accessibility API under
`AXExtrasMenuBar`. Clicking one presses the real item, so that application opens its real menu.
Items macOS has parked under the notch are left out, because they are never drawn there either.
`collapse` takes Stege away so the real menu bar underneath becomes reachable, and leaves a small
button just left of the notch to bring it back.

```toml
[widgets.default.reveal]
mode = "extras"            # or "collapse"
icon-size = 15             # `extras` only
icon-style = "monochrome"  # `extras` only, or "colour"
always-show = []           # `extras` only: bundle ids kept in the bar permanently
hidden = []                # `extras` only: bundle ids that never appear
sticky = true              # `collapse` only, false: come back on pointer movement
return-threshold = 80      # `collapse` and `sticky = false` only
timeout = 10               # `collapse` and `sticky = false` only: seconds
```

## What it looks like

### App menus

Clicking a title opens Stege's own rendering of that menu. Selecting an entry presses the real
Accessibility element, so the app behaves exactly as it would through its own menu bar.

![The File menu open](.github/assets/appmenu.png)

`visibility` decides when they appear.

| Value | Behaviour |
| --- | --- |
| `always` | The menus sit in the bar next to the workspace pills |
| `hover` | The menus take the pills' place while the pointer rests on the focused window's pill |
| `modifier` | The same swap, held open by a key instead of the pointer |
| `click` | The same swap, made by clicking the focused window's pill |

Under `hover`, `modifier` and `click` the menus replace the pills rather than crowding in beside
them, so the bar never grows. `hover` and `click` use the pills as the target, so keep
`default.spaces` in `widgets.displayed` for those, or use `modifier`, which needs no target.

### Apple menu

About This Mac, System Information, then Sleep, Restart, Shut Down and Log Out. Each row presses
the real menu item, so the confirmations macOS raises are its own. `short-menu = false` opens the
full system menu instead, all fifteen entries including the option-key alternates.

![The Apple menu open](.github/assets/applemenu.png)

### Sound

The speaker's arcs say the level the way macOS's own does. `glyph = "waveform"` is the neutral
alternative. Scrolling on the icon changes the volume and right-clicking mutes, so the popup is
only needed for picking a device.

The popup is two matching blocks, output and input, each with what it is, a level slider, and the
devices to choose between. Clicking the glyph left of either slider mutes that half. A muted
device reads `Muted` where its percentage would be, in the popup and in the bar under
`show-percentage`, while the slider keeps the level it will come back to.

`default.microphone` puts the microphone in the bar as its own icon, with the same scroll and
right-click over the input level. Both icons open the same popup.

Output devices that carry no mute property, the built-in speakers among them, are muted by
dropping the level to zero and put back where they were on the way out. An input device that
exposes no settable gain, which is most USB and Bluetooth microphones, shows muted or not in the
slider's place.

![The sound popup](.github/assets/sound.png)

### Wi-Fi

The current connection and its signal, then the networks in range, with a switch for the radio
itself. Clicking a network you have joined before, or an open one, connects straight away. A
secured network you have not saved opens a password field under its row.

The password is handed to CoreWLAN and dropped. `associate` writes the successful one to the
system keychain, the same place the system Wi-Fi settings put it, so the next connection needs no
password at all.

The icon stays in the bar with the radio off, drawn as a red slash, so the switch is still
reachable. `hide-when-disconnected = true` takes it away instead.

![The Wi-Fi popup](.github/assets/wifi.png)

### Notifications

A bell whose popup lists the notifications that have come in and every Focus, including any you
have made yourself. Clicking a row dismisses that notification and Clear All clears the lot.

The list is macOS's own. There is no public API for it and no file to read, so it comes from
Notification Center's own accessibility tree, which publishes one element per notification with
the application name, the title, subtitle and body as separately labelled text, the timestamp, and
the actions that dismiss it.

Opening the bell opens nothing. The panel has to exist to be read, so it is read once a few
seconds after launch, and every banner macOS draws afterwards goes straight into the list, because
a banner publishes the same identifier and the same text a row in the panel does. Opening
Notification Center by hand is read too, so a list gone stale corrects itself, and the circular
arrow next to the `Notifications` heading asks macOS again. A notification delivered without a
banner, an application whose alert style is `None`, or anything that arrives under a Focus, is not
seen until one of those reads, which is what the arrow is for.

Dismissals are queued rather than pressed as you click: the row leaves the list at once, and the
real close button, or Clear All, is pressed in one visit after the popup has gone. So the panel
macOS insists on drawing is never on screen at the same time as the popup, and the list still
cannot drift apart from the system's.

The Focus list and the switching go through Control Center's own controls, for the same reason:
`~/Library/DoNotDisturb/DB` needs Full Disk Access and the private `DoNotDisturb` framework
answers only callers holding an Apple-issued entitlement. The list is read once and kept, and the
circular arrow next to the `Focus` heading reads it again, which is what to press after adding a
Focus in System Settings.

`show-control-centre = true` adds a second control for Control Center.

### Bluetooth

Every paired device is listed, connected ones first, with a battery bar for the devices that
report a level. Clicking a device connects or disconnects it. `Scan` looks for devices that are
not paired yet, and stops as soon as the popup closes, because an inquiry keeps the radio busy.

The switch in the header turns the controller on and off directly, with nothing appearing on
screen. `IOBluetoothPreferenceSetControllerPowerState` is not in any published header but it is a
plain C function `IOBluetooth` exports, and it is what `blueutil` has always used. The icon stays
in the bar with the controller off unless `hide-when-off = true`.

![The Bluetooth popup](.github/assets/bluetooth.png)

### Battery

Charge, time estimate, health and cycles, and a switch for Low Power Mode.

The charge is drawn as the battery outline with the level filled in behind the number, which sits
in the body of the battery. The fill is dimmed so the battery is not the brightest object on
screen, with full brightness kept for low and for charging. `style = "plain"` puts the outline and
the number side by side instead, which is what macOS does.

![The battery popup](.github/assets/battery.png)

### Calendar

Page between months, pick a day to see its events from every account the system knows about, and
click one to open it. A meeting link goes to the browser, anything else opens Calendar showing
that event. The plus adds an event to whichever calendar you choose.

![The calendar popup](.github/assets/calendar.png)

## Known limitations

**Option-key menu entries are always visible.** macOS hides alternate menu items until Option is
held. The Accessibility API exposes no attribute that tells an alternate from an ordinary item, so
Stege shows both at once.

**Low Power Mode and Focus flash the system panel.** Both switches are the ones macOS puts in its
own panels, pressed through the Accessibility API, because nothing else can write those settings:
`pmset` needs root, `~/Library/DoNotDisturb/DB` needs Full Disk Access, and the private
`LowPowerMode` and `DoNotDisturb` frameworks answer only callers holding an Apple-issued
entitlement. Notification Center is the same, which is why the list is read once at launch rather
than on every click.

**No screen recording indicator.** There is no public API to detect another app capturing the
screen, so the privacy widget covers the microphone and camera only.

**Bluetooth microphones report as inactive.** A platform limitation of the property the privacy
widget reads.

## Credits

`barik` by [Simon Butenko](https://github.com/mocki-toki), MIT. Widget ideas from
[`barik-enhanced`](https://github.com/MateoCerquetella/barik-enhanced) by Mateo Cerquetella, MIT.

## License

MIT, see [LICENSE](LICENSE). The original copyright notice is kept alongside this fork's.
