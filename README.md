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
collects no telemetry. The only request it ever makes is for album artwork, and only when the
now playing widget is showing a track whose player gave a link rather than the image itself, which
in practice means `Spotify`. `fetch-artwork = false` refuses even that.

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
| Automation | Reading and controlling `Spotify` and `Music` for the now playing widget | The widget draws a music note with a warning mark, and its tooltip says which player it could not reach |

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
| `default.monitor` | CPU and memory, with disk and throughput in the popup |
| `default.privacy` | Microphone and camera in-use indicators |
| `default.stayawake` | A cup, while something is keeping the display awake |
| `default.notifications` | A bell listing the notifications macOS is holding, and the Focus modes |
| `default.audio` | Output volume |
| `default.display` | Screen brightness, with Night Shift and True Tone in the popup |
| `default.updates` | A mark while macOS or Homebrew has something waiting |
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
glyph = "speaker"                   # or "waveform"

[widgets.default.display]
show-percentage = false             # the glyph already fills with the level

[widgets.default.updates]
always-show = false                 # hidden while there is nothing waiting
macos = true
homebrew = true
refresh-interval = 30               # minutes

[widgets.default.network]
show-name = false                   # showing the name asks for Location
hide-when-disconnected = false

[widgets.default.bluetooth]
hide-when-off = false
show-battery = true                 # the connected device with least left

[widgets.default.battery]
style = "inside"                    # number in the battery, or "plain" for beside it
show-percentage = true
warning-level = 30
critical-level = 10

[widgets.default.time]
format = "E d MMM  HH:mm"
calendar.show-events = true
calendar.countdown = true           # "in 25m" rather than the start time
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

### Now playing

`default.nowplaying` reads `Spotify` and `Music` over `AppleScript`, which is why it wants
Automation. It also asks `MediaRemote`, the system's own now-playing service that Control Center
reads, which would cover anything playing in a browser. On macOS 26 that returns an empty answer
to any caller without Apple's own entitlement, and an empty answer is indistinguishable from
nothing playing, so in practice the two scriptable applications are the coverage.

When a player is running and cannot be read, the widget draws a music note with a warning mark
rather than disappearing, and clicking it opens Privacy & Security, Automation. Nothing playing
and cannot see what is playing used to look the same from the bar, which is the worst way to
report a permission that was never granted.

### Hiding the bar

`hidden = true` takes the bar away entirely, leaving the real macOS menu bar and every
third-party status item reachable. `toggle-shortcut` gives the same switch from the keyboard,
written as modifiers then a key joined with `+`, at least one modifier required.

The `default.reveal` chevron works from the bar and has two modes. `extras`, the default, appends
the other applications' status items to the bar, read through the Accessibility API under
`AXExtrasMenuBar`. Clicking one presses the real item, so that application opens its real menu.
Items macOS has parked under the notch are left out, because they are never drawn there either.

Where an application ships the glyph it draws in the menu bar, that is what appears. Nothing
publishes one through the accessibility API, but the name is often reachable: an item's `AXTitle`
is frequently the image's own name, and applications name the asset conventionally,
`StatusBarMenuImage` or `StatusBarItemIcon` or `MenubarIcon`. Asking the bundle for those by name
reaches the same compiled asset catalog the application uses. Applications naming their assets for
the state they show, or shipping no menu bar template at all, keep their application icon instead,
so the row is a mix.
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

The speaker's arcs fill by level the way macOS's own does. `glyph = "waveform"` is the neutral
alternative. Scrolling on the icon changes the volume and right-clicking mutes, so the popup is
only needed for picking a device.

The sound popup lists what is making noise while the popup is open. Not a level per application,
which macOS does not offer: the audio process objects added in macOS 14.4 carry a process
identifier and whether it is running output, but no volume and no mute. Setting a level per
application means installing a virtual audio device that becomes the default output, which is a
system driver and an administrator prompt, and is not what this is.

`default.microphone` puts the microphone in the bar as its own icon, with the same scroll and
right-click over the input level.

Each icon opens its own popup: the speaker opens `Sound`, the microphone opens `Microphone`, and
each holds a level slider and the devices to choose between. Clicking the glyph left of the slider
mutes that half. A muted device reads `Muted` where its percentage would be, in the popup and in
the bar under `show-percentage`, while the slider keeps the level it will come back to.

Output devices that carry no mute property, the built-in speakers among them, are muted by
dropping the level to zero and put back where they were on the way out. An input device that
exposes no settable gain, which is most USB and Bluetooth microphones, shows muted or not in the
slider's place.

![The sound popup](.github/assets/sound.png)

### Display

Brightness in the bar, scrollable without opening anything, with a slider per
attached display in the popup, plus Night Shift and its warmth, and True Tone on
the Macs that have the sensor.

All of it is set directly. `DisplayServicesGetBrightness` and
`DisplayServicesSetBrightness` are plain C functions `DisplayServices` exports,
and Night Shift and True Tone are `CBBlueLightClient` and `CBTrueToneClient` in
`CoreBrightness`, so no panel appears and no extra permission is asked for. A
monitor whose backlight is not ours to set is still listed, saying so, rather
than being dropped.

### Updates

A mark while macOS or Homebrew has something waiting, hidden the rest of the time. The popup lists
what, and hands off rather than acting: Software Update opens the settings pane, and Homebrew
copies `brew upgrade` to the clipboard, because upgrading can restart services and ask for a
password and a menu bar is not where that should start on one click.

Neither half checks anything, and neither reaches the network, so the macOS side reads
the result of the system's own last check out of `com.apple.SoftwareUpdate` and says how old that
answer is, and the Homebrew side runs `brew outdated`, which compares what is installed against
the tap data already on disk.

### Wi-Fi

The current connection and its signal, then the networks in range, with a switch for the radio
itself. A VPN carrying traffic is named in the popup and badges the bar mark with a small lock,
and the popup carries the throughput going through it.

Whether a VPN is up is read from the system configuration store rather than from the interface
list: macOS keeps four `utun` interfaces up with no VPN connected at all, so their presence says
nothing. What says something is a network service with an address whose interface is a tunnel. Clicking a network you have joined before, or an open one, connects straight away. A
secured network you have not saved opens a password field under its row.

The password is handed to CoreWLAN and dropped. `associate` writes the successful one to the
system keychain, the same place the system Wi-Fi settings put it, so the next connection needs no
password at all.

The icon stays in the bar with the radio off, drawn as a red slash, so the switch is still
reachable. `hide-when-disconnected = true` takes it away instead.

Every mark in the bar is drawn in a box of one width, so a widget changing state changes what it
draws and never where anything sits. The speaker fills its arcs by level rather than swapping
between three symbols of three different widths, which is what used to shove the whole row
sideways when the volume crossed a third of the way up.

![The Wi-Fi popup](.github/assets/wifi.png)

### System monitor

Processor and memory in the bar, and in the popup those two drawn as meters alongside disk space
and the current throughput. Disk uses the figure Finder shows, which counts what macOS would evict
if it needed the room, rather than the raw free figure that reads far lower.

### Notifications

A bell whose popup lists the notifications that have come in and every Focus, including any you
have made yourself. Clicking a row dismisses that notification and Clear All clears the lot.

The list is macOS's own. There is no public API for it and no file to read, so it comes from
Notification Center's own accessibility tree, which publishes one element per notification with
the application name, the title, subtitle and body as separately labelled text, the timestamp, and
the actions that dismiss it.

Nothing here opens Notification Center on its own. The panel has to exist to be read, so instead
every banner macOS draws goes straight into the list, because a
banner publishes the same identifier and the same text a row in the panel does. Opening
Notification Center by hand is read too, so a list gone stale corrects itself, and the circular
arrow next to the `Notifications` heading asks macOS outright. A notification that arrived before
Stege started, one delivered without a banner, an application whose alert style is `None`, or
anything that arrives under a Focus, is not in the list until one of those reads, which is what
the arrow is for. Each row carries the posting application's icon.

The list does not survive a restart unless `remember-between-launches = true`. Remembering means
writing every notification's title, subtitle and body to `~/Library/Preferences` in plaintext,
where anything running as you can read them, and message previews are the kind of thing this app
refuses Full Disk Access to avoid reading in the first place.

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

Every paired device is listed, connected ones first, with a device symbol, a battery bar for the
ones that report a level, and `Connecting…` or `Disconnecting…` on the row while an action is in
flight. Clicking a device connects or disconnects it, and the other rows dim while that runs. The
popup scans for unpaired devices as it opens and stops as soon as it closes, because an inquiry
keeps the radio busy. With the radio off the list is empty rather than listing devices that cannot
be reached.

The switch in the header turns the controller on and off directly, with nothing appearing on
screen. `IOBluetoothPreferenceSetControllerPowerState` is not in any published header but it is a
plain C function `IOBluetooth` exports, and it is what `blueutil` has always used. The icon stays
in the bar with the controller off unless `hide-when-off = true`.

![The Bluetooth popup](.github/assets/bluetooth.png)

### Battery

Charge, time estimate, health and cycles, and a switch for Low Power Mode.

The charge is drawn as the battery outline with the level filled in behind the number, which sits
in the body of the battery. The fill is white, yellow past `warning-level`, red past
`critical-level`, and green with a bolt while charging. The number is drawn twice and each copy
clipped to the side of the fill edge it falls on, dark on the level and light on the empty part, so
it stays legible at any charge. `style = "plain"` puts the outline and the number side by side
instead, which is what macOS does.

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
