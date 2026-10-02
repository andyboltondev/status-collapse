# StatusCollapse

An easy to use, simple, lightweight and minimal menu bar icon collapsing tool for macOS. One
button hides and shows your menu bar icons with a single click, with no clutter and nothing else
to learn.

> **Tested on macOS 27 only.** It is built for macOS 26 and later, but has not been tested on
> macOS 26 yet (see [Compatibility](#compatibility)).

It adds a single **button** (a chevron) to the menu bar. Click it to collapse, and every icon to
its left disappears. Click it again to bring them back. Everything to the right of the button
(Control Center, the clock, ...) is never touched.

## Features

- One-click collapse/expand with an animated chevron
- Auto-hide after 5, 10, 30 or 60 seconds once the pointer leaves the menu bar
- Eight icon styles: native double chevron, chevron, circled chevron, arrow, eye, dots, dot, lock
- Icons stay visible while Settings is open so they are easy to rearrange
- Launch at login
- Right-click (or Control-click) the button for Settings and Quit

## Requirements

- macOS 26 or later, on Apple silicon or Intel (see [Compatibility](#compatibility))
- To build: Swift 6.2 toolchain (Xcode 26 or later)

## Install

Download a DMG from the [releases page](https://github.com/andyboltondev/status-menu-collapse/releases):

- **Universal** runs on any Mac. Pick this if you're unsure.
- **Apple silicon** is for Macs with an M-series chip, **Intel** for Intel Macs.

Open it and drag StatusCollapse to Applications. StatusCollapse isn't notarized by Apple (that
needs a paid Apple Developer account), so macOS blocks it the first time you open it:

1. Open StatusCollapse. When macOS says it can't verify the app, click **Done**.
2. Open **System Settings › Privacy & Security** and click **Open Anyway** next to the message
   about StatusCollapse.
3. Confirm with **Open Anyway** and your password. This is only needed once.

### Upgrading from 1.0.0

1.0.0 used a placeholder bundle identifier; later versions use `dev.andybolton.StatusCollapse`.
The first launch keeps your icon style and auto-hide delay, but runs setup again, since macOS may
not remember the button's position under the new identifier. Turn **Open at login** back on if
you use it, and remove any old StatusCollapse entry left in System Settings › General › Login Items.

## Build and run

```bash
./build.sh
open build/universal/StatusCollapse.app
```

`build.sh` builds a universal release binary and wraps it, and its Apple silicon and Intel slices,
in ad-hoc signed apps with the hardened runtime enabled: `build/universal/`, `build/apple-silicon/`
and `build/intel/`. `./tools/make-dmg.sh` packages each as a drag-to-Applications DMG in `build/`.

Quit any installed copy before opening a build, so the two don't both add a button.

## Usage

1. Hold **⌘** and drag the button (or other icons) so the icons you want to hide sit to its left.
2. Click the button to collapse or expand.
3. If the button goes missing, use **Reset Layout** in Settings.

## How it works

macOS lays status items out right to left. Collapsing adds a second, invisible item that shares
the button's autosave name, which makes macOS place it immediately left of the button (and keep it
there if the button is ⌘-dragged). That item is then made so wide (just under half the narrowest
display) that macOS cannot fit it, so it hides that item and every item to its left. The button
never changes size, so it can't be pushed out of view. Expanding removes the invisible item again.

This relies on observed menu bar behavior rather than documented API, so it may need adjusting
after system updates.

## Compatibility

- **macOS 26 and 27.** The app is built for macOS 26 and later, and the compiler checks that every
  API it uses exists on macOS 26. The hiding technique, however, was worked out and tested on
  macOS 27 only; it has not been tested on macOS 26 yet.
- **Displays.** The invisible item's width is worked out in points from the narrowest display, so
  it adapts to any resolution or scaling, and it is recalculated whenever displays change. Only a
  notched MacBook display has been tested. Displays without a notch, external displays, and
  setups mixing displays of different widths have not.

## Project layout

- `Sources/StatusCollapse/Controller.swift`: status items, collapse logic, auto-hide
- `Sources/StatusCollapse/Views.swift`, `AppDelegate.swift`, `main.swift`: settings UI and app setup
- `Resources/Info.plist`: app bundle metadata (menu bar only, no Dock icon)
- `build.sh`: builds the universal, Apple silicon and Intel apps
- `tools/`: DMG packaging (`make-dmg.sh`, `make-dmg-background.swift`) and the icon renderer (`make-icon.swift`)
- `.github/workflows/release.yml`: builds the DMGs and publishes a GitHub release for `v*` tags
- `.github/dependabot.yml`: weekly pull requests that update the pinned GitHub Actions
