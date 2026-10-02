# StatusCollapse

A tiny macOS menu bar utility that hides and shows your menu bar icons with one click.

It adds a single **button** (a chevron) to the menu bar. Click it to collapse, and every icon to
its left disappears. Click it again to bring them back. Everything to the right of the button
(Control Center, the clock, ...) is never touched.

## Features

- One-click collapse/expand with an animated chevron
- Auto-hide after 5, 10, 30 or 60 seconds once the pointer leaves the menu bar
- Four icon styles: native double chevron, chevron, arrow, eye
- Icons stay visible while Settings is open so they are easy to rearrange
- Launch at login
- Right-click (or Control-click) either item for Settings and Quit

## Requirements

- macOS 26 or later (built and tested on macOS 27)
- Swift 6.2 toolchain (Xcode 26 or later)

## Build and run

```bash
./build.sh
open build/StatusCollapse.app
```

The script builds a release binary and wraps it in an ad-hoc signed `StatusCollapse.app`.

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

This relies on observed macOS 27 menu bar behavior rather than documented API, so it may need
adjusting after system updates. Only a notched MacBook display has been tested; external and
non-notched displays have not.

## Project layout

- `Sources/StatusCollapse/Controller.swift`: status items, collapse logic, auto-hide
- `Sources/StatusCollapse/Views.swift`, `AppDelegate.swift`, `main.swift`: settings UI and app setup
- `Resources/Info.plist`: app bundle metadata (menu bar only, no Dock icon)
- `build.sh`: builds and packages the app
