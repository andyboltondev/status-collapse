# StatusCollapse

An easy to use, simple, lightweight and minimal menu bar icon collapsing tool for macOS. One
button hides and shows your menu bar icons with a single click, with no clutter and nothing else
to learn.

> **Requires macOS 27 or later, on Apple silicon.** macOS 27 is the only version it is built for and
> tested on (see [Compatibility](#compatibility)).

It adds a single **button** (a chevron) to the menu bar. Click it to collapse, and every icon to
its left disappears. Click it again to bring them back. Everything to the right of the button
(Control Center, the clock, ...) is never touched.

## Features

- One-click collapse/expand with an animated button
- 19 icon styles plus custom text, with adjustable size and weight
- Global keyboard shortcut (default ⌃⌥S), reveal on hover, and a right-click menu
- Auto-hide with a slider delay, optionally only on battery or mains power
- Hides when the Mac locks or sleeps, or when a display is mirrored
- Fade the button when icons are hidden, or show it only while icons are shown, revealing them with the shortcut
- Export and import settings
- Optional daily check for a newer release (it only links to it; nothing is downloaded)
- 36 languages, defaulting to British English and following macOS
- Icons stay visible while Settings is open so they are easy to rearrange
- Launch at login

## Requirements

- macOS 27 or later on a Mac with Apple silicon (macOS 27 does not run on Intel Macs)
- To build: Xcode 27 or later (Swift 6.4)

## Install

Download the DMG from the [releases page](https://github.com/andyboltondev/status-menu-collapse/releases),
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

`build.sh` builds an Apple silicon release binary and wraps it in an ad-hoc signed app with the
hardened runtime enabled: `build/StatusCollapse.app`. `./tools/make-dmg.sh` packages it as a
drag-to-Applications DMG in `build/`.

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

- **macOS 27 only.** The app requires macOS 27 and uses its menu bar behavior. The hiding technique
  was worked out and tested on macOS 27, and macOS 27 runs on Apple silicon only, so there is no
  Intel build.
- **Displays.** The invisible item's width is worked out in points from the narrowest display, so
  it adapts to any resolution or scaling, and it is recalculated whenever displays change. Only a
  notched MacBook display has been tested. Displays without a notch, external displays, and
  setups mixing displays of different widths have not.

## Tests

`swift test` runs the unit tests. The release workflow runs them, builds the apps, then runs
`tools/verify-build.sh`, which checks the architecture, signature, version, minimum macOS, changelog and languages.

## Changelog and license

See [CHANGELOG.md](CHANGELOG.md); the latest entry is also shown in Settings when you click the
version line. StatusCollapse is source-available under the
[PolyForm Noncommercial License 1.0.0](LICENSE). You may use, modify and share it for any
noncommercial purpose, free of charge, but you must keep the `Required Notice:` credit line and
a copy of the license (or its URL) with anything you share. Selling it or using it commercially
is not permitted. Strictly speaking this is not an OSI "open source" license, because it
restricts commercial use.

## Project layout

- `Sources/StatusCollapse/Controller.swift`: status items, collapse logic, auto-hide
- `Sources/StatusCollapse/Views.swift`, `AppDelegate.swift`, `main.swift`: settings UI and app setup
- `Resources/Info.plist`: app bundle metadata (menu bar only, no Dock icon)
- `build.sh`: builds the Apple silicon app
- `tools/`: DMG packaging (`make-dmg.sh`, `make-dmg-background.swift`) and the icon renderer (`make-icon.swift`)
- `.github/workflows/release.yml`: builds the DMG and publishes a GitHub release for `v*` tags
- `.github/dependabot.yml`: weekly pull requests that update the pinned GitHub Actions
