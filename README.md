# StatusCollapse

An easy to use, simple, lightweight and minimal menu bar icon collapsing tool for macOS. One
button hides and shows your menu bar icons with a single click, with no clutter and nothing else
to learn.

> **Requires macOS 27 or later, on a Mac with Apple silicon.** Tested on a MacBook Pro with an M5 Pro
> chip running macOS 27 (see [Compatibility](#compatibility)).

It adds a single **button** (a chevron) to the menu bar. Click it to collapse, and every icon to
its left disappears. Click it again to bring them back. Everything to the right of the button
(Control Center, the clock, ...) is never touched.

## Features

- **One-click collapse and expand** with an animated button. Everything to the right of the
  button is never touched.
- **19 icon styles** plus your own text (up to four characters), with adjustable size, weight and
  fade when icons are hidden.
- **Global keyboard shortcut** (default ⌃⌥S, one-handed) that you can change or turn off.
- **Reveal on hover**, and a right-click menu with Hide/Show, Settings and Quit.
- **Auto-hide** after a delay you choose, optionally only on battery or only on mains power.
- **Privacy**: hide the icons when the Mac locks or sleeps, or when a display is mirrored.
- **Works across displays**, notched or not, adapting whenever displays are connected or changed.
- **Hide the button itself** while the icons are hidden, and bring everything back with the shortcut.
- **Launch at login**, and **export and import** of your settings.
- **Update check**: an optional daily look for a newer release. It only links to it; nothing is
  downloaded or installed.
- **36 languages**, defaulting to British English and following macOS.
- **No permissions needed.** It only manages its own menu bar items. One optional setting for more
  than one display uses the Device Control and Data Access permission (see [Behaviour](#behaviour)).

## Requirements

- macOS 27 or later on a Mac with Apple silicon (macOS 27 does not run on Intel Macs)
- To build: Xcode 27 or later (Swift 6.4)

## Install

Download the DMG from the [releases page](https://github.com/andyboltondev/status-collapse/releases),
open it and drag StatusCollapse to Applications. StatusCollapse isn't notarized by Apple (that
needs a paid Apple Developer account), so macOS blocks it the first time you open it:

1. Open StatusCollapse. When macOS says it can't verify the app, click **Done**.
2. Open **System Settings › Privacy & Security** and click **Open Anyway** next to the message
   about StatusCollapse.
3. Confirm with **Open Anyway** and your password. This is only needed once.

## Build and run

```bash
./build.sh
open build/StatusCollapse.app
```

`./build.sh` is the one command for everything. By default it runs the tests, builds an Apple
silicon release binary into an ad-hoc signed app with the hardened runtime
(`build/StatusCollapse.app`), then verifies the result (architecture, signature, version, minimum
macOS, changelog and languages). Options choose the stages:

| Option | Effect |
|---|---|
| `--dmg` | also package a drag-to-Applications DMG in `build/` |
| `--tests-only` | only run the tests |
| `--skip-tests` | skip the tests |
| `--skip-build` | skip building (verify or package the existing app) |
| `--skip-verify` | skip verifying the built app |

Quit any installed copy before opening a build, so the two don't both add a button.

## Usage

1. Hold **⌘** and drag the button (or other icons) so the icons you want to hide sit to its left.
   Icons to the right of the button always stay visible.
2. Click the button to collapse or expand. The tooltip shows how many icons are hidden.
3. Right-click (or Control-click) the button for **Hide/Show**, **Settings** and **Quit**.
4. Or press the keyboard shortcut (⌃⌥S by default) from anywhere.

The first launch walks you through arranging your icons and turning on Open at login. Run it again
any time from **Settings › General › Run Setup**.

While Settings is open the icons stay shown so they are easy to arrange, and auto-hide pauses.
When you close it, they return to the state they were in. If nothing sits to the left of the
button yet, it is dimmed to show it has nothing to hide.

## Settings

Open Settings from the right-click menu. It has three tabs, and the window resizes to fit each tab
as you switch, so a tab shows without scrolling (up to 80% of your screen's height). You can also
resize it yourself.

### Menu bar

| Setting | What it does |
|---|---|
| Icon | The button's look: native double chevron, chevron, light chevron, circled chevron, arrow, triangle, eye, dots, ellipsis, dot, lock, tray, grid, sidebar, menu bar, plus and minus, pin, moon, bolt, or custom text |
| Text when icons are shown / hidden | For the custom style: up to four characters each, such as ▸ or ••• |
| Size, Weight | How large and heavy the button is drawn |
| Opacity when icons are hidden | Fades the button while it isn't needed (20% to 100%) |
| Show the button | **Always**, or **Only when icons are shown**, which needs the keyboard shortcut to bring them back |

### Behaviour

| Setting | What it does |
|---|---|
| Keyboard shortcut | Turns the global shortcut on or off and lets you record another. If macOS or another app already uses it, you are asked to choose another |
| Auto-hide | Hides the icons again after 5 to 120 seconds (or Never) |
| Auto-hide on | Limits auto-hide to battery power or mains power |
| Reveal on hover | Shows the icons when the pointer touches the button, then hides them again after the auto-hide delay (2 seconds if auto-hide is off) |
| Hide when the Mac locks or sleeps | So the icons are hidden when you return (on by default) |
| Hide when mirroring a display | For projectors and AirPlay screens |
| Prevent click highlights | With more than one display, stops a click on the empty menu bar beside the button from briefly highlighting it on a display you aren't using. Needs the **Device Control and Data Access** permission (Accessibility, before macOS 27), which turning it on asks for. Settings shows whether it's allowed and opens **Privacy & Security** for you (off by default) |

### General

| Setting | What it does |
|---|---|
| Open at login | Starts StatusCollapse when you sign in |
| Language | One of 36 languages, or follow your Mac |
| Check for updates | Looks for a newer release once a day, or use **Check now**. It only links to the release page |
| Export / Import | Saves your settings to a file, or loads them on another Mac. Only preferences are included, not the current state or button position |
| Run Setup, Reset Layout, System Settings | Repeat the walkthrough, recreate a missing button, or open Menu Bar settings in System Settings |

Click the version line at the bottom of Settings to open **What's New** for this version.

## Troubleshooting

- **The button is missing.** Open StatusCollapse again from Finder (or Spotlight) to bring up
  Settings, then use **Reset Layout** in the General tab.
- **The shortcut does nothing.** Another app may use the same keys. Record a different shortcut.
  With no working shortcut, the button is kept visible so you can still click it.
- **Icons won't hide.** Only icons to the left of the button are hidden. ⌘-drag them there.
  macOS doesn't let apps move other apps' icons, so arranging is manual.
- **Two buttons appear.** Quit any other copy first, such as an installed copy while testing a build.
- **Clicking the empty menu bar on another display flashes a highlight.** Turn on
  **Settings › Behaviour › Prevent click highlights** and allow StatusCollapse under
  **System Settings › Privacy & Security › Device Control and Data Access**.
- **Prevent click highlights keeps waiting for access, but StatusCollapse is already allowed.**
  StatusCollapse isn't signed with a developer certificate, so macOS treats each update (or each
  build you make yourself) as a new app. Turn StatusCollapse off and on again in that list.
- **"Couldn't check for updates".** The check needs a published release and an internet connection.
  Turn it off under Settings › General if you prefer.

## How it works

macOS lays status items out right to left. StatusCollapse keeps a few invisible items that share the
button's autosave name, which makes macOS place them immediately left of the button (and keep them
there if the button is ⌘-dragged). Collapsing makes each just under half as wide as the narrowest
display, the widest an item can be before macOS ejects it from that display's menu bar, and there
are enough of them to span the widest display, so macOS cannot fit them all. It hides the ones that
don't fit and every item to their left. The button never changes size, so it can't be pushed out of
view. Expanding makes the invisible items wider than half the widest display, so macOS ejects them
from every menu bar and they take up no room.

The invisible items are kept rather than added on each collapse: macOS brings a new item into each
display's menu bar separately, so on a wide display the icons could jump left before fading out.
For the same reason, collapsing first nudges one of the ejected items, which changes nothing on
screen, so that the menu bar takes the rest of the changes together.

A display without a notch has more free menu bar than any one item may take, so there one invisible
item still fits beside the button. macOS draws a highlight over any status item while it's pressed,
which would show it as a long empty bar. So while the pointer is over that item, StatusCollapse
covers it with a clear window that takes the press and does nothing, like empty menu bar. The
item's own hover events say where it is. macOS only sends those for the display whose menu bar is
active, so on another display the first press there can still show the highlight. That press makes
its menu bar the active one, and the cover works from then on.

With **Prevent click highlights** on, the cover works on every display from the start.
MenuBarAgent, the part of macOS that lays out each display's menu bar, lists what is placed where
through the Accessibility API, which the Device Control and Data Access permission allows. So
StatusCollapse asks it where its invisible item is on the display under the pointer. It only reads
those positions, and only while the icons are hidden, more than one display is connected and the
pointer is on the menu bar of a display that isn't active. Reading
them takes about a millisecond and happens off the main thread.

This relies on observed menu bar behavior rather than documented API, so it may need adjusting
after system updates.

## Compatibility

- **macOS 27 on Apple silicon only.** The app requires macOS 27 and uses its menu bar behavior,
  which the hiding technique depends on. macOS 27 runs on Apple silicon only, so there is no
  Intel build.
- **Tested on** a MacBook Pro with an M5 Pro chip and its built-in notched display, running
  macOS 27, alone and extended onto a 2560 × 1440 external display without a notch.
- **Displays.** The invisible items' width and number are worked out in points from the narrowest
  and widest displays, so they adapt to any resolution or scaling, and they are recalculated
  whenever displays change. An external display used on its own has not been tested.

## Changelog and license

See [CHANGELOG.md](CHANGELOG.md); the latest entry is also shown in the What's New window when you
click the version line in Settings. StatusCollapse is source-available under the
[PolyForm Noncommercial License 1.0.0](LICENSE). You may use, modify and share it for any
noncommercial purpose, free of charge, but you must keep the `Required Notice:` credit line and
a copy of the license (or its URL) with anything you share. Selling it or using it commercially
is not permitted. Strictly speaking this is not an OSI "open source" license, because it
restricts commercial use.

## Project layout

- `Sources/StatusCollapse/Controller.swift`: status items, collapse logic, auto-hide
- `Sources/StatusCollapse/MenuBarShield.swift`: the clear cover that keeps the empty menu bar beside
  the button from highlighting when pressed
- `Sources/StatusCollapse/Views.swift`, `AppDelegate.swift`, `main.swift`: settings UI and app setup
- `Sources/StatusCollapse/HotKey.swift`, `UpdateCheck.swift`, `Localization.swift`: the global shortcut,
  the update check and the 36 languages (`Resources/Localization/`)
- `Resources/Info.plist`: app bundle metadata (menu bar only, no Dock icon)
- `build.sh`: tests, builds, verifies and packages the app (see [Build and run](#build-and-run))
- `tools/`: build verification (`verify-build.sh`), DMG packaging (`make-dmg.sh`, `make-dmg-background.swift`) and the icon renderer (`make-icon.swift`)
- `.github/workflows/release.yml`: runs `./build.sh --dmg` on GitHub's `xcode-27` runner (macOS 27, Apple silicon) and publishes a release for `v*` tags
- `.github/dependabot.yml`: weekly pull requests that update the pinned GitHub Actions
