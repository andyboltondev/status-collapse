# StatusCollapse

A tiny macOS menu bar utility that hides and shows your menu bar icons with one click.

It adds two items to the menu bar: a **button** (a chevron) and a slim **divider** to its left.
Click the button to collapse, and every icon to the left of the divider disappears. Click it again
to bring them back. Everything to the right of the button (Control Center, the clock, ...) is never touched.

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

1. Hold **⌘** and drag the divider so the icons you want to hide sit to its left.
2. Click the button to collapse or expand.
3. If the layout gets into a bad state, use **Reset Layout** in Settings.

## How it works

macOS lays status items out right to left. When collapsed, the divider is made so wide
(just under half the narrowest display) that macOS cannot fit it, so it hides the divider and
every item to its left. The button never changes size, so it can't be pushed out of view. If you
drag the button left of the divider, the two swap roles automatically.

This relies on observed macOS 27 menu bar behavior rather than documented API, so it may need
adjusting after system updates. Only a notched MacBook display has been tested; external and
non-notched displays have not.

## Project layout

- `Sources/StatusCollapse/Controller.swift`: status items, collapse logic, auto-hide
- `Sources/StatusCollapse/Views.swift`, `AppDelegate.swift`, `main.swift`: settings UI and app setup
- `Resources/Info.plist`: app bundle metadata (menu bar only, no Dock icon)
- `build.sh`: builds and packages the app
