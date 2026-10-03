# Changelog

## 1.0.0 - 2026-10-03

First release. Requires macOS 27 on Apple silicon; tested on a MacBook Pro with an M5 Pro chip.

**Hiding**
- One-click collapse and expand of the menu bar icons to the left of a single button, with an animated glyph
- Icons to the right of the button (Control Center, the clock) are never touched
- Right-click (or Control-click) menu with Hide/Show, Settings and Quit, and a tooltip showing how many icons are hidden
- Global keyboard shortcut (default ⌃⌥S), which you can change or turn off
- Reveal on hover
- Auto-hide with a delay from 5 to 120 seconds, optionally only on battery or only on mains power
- Hides when the Mac locks or sleeps, and optionally when a display is mirrored
- Dims the button while nothing sits to its left

**Appearance**
- 19 icon styles plus custom text, with adjustable size and weight
- Fade the button while icons are hidden, or show it only while icons are shown and bring them back with the shortcut
- Translated into 36 languages, defaulting to British English and following macOS

**Settings**
- First-run setup walkthrough, which can be run again
- Settings in three tabs (Menu bar, Behaviour, General) in a resizable window that opens tall enough to show a tab without scrolling
- Icons stay shown while Settings is open so they are easy to arrange, and auto-hide pauses
- Launch at login
- Export and import of settings
- Optional update check, once a day, that links to a newer release and never downloads or installs anything
- What's new for the running version, shown by clicking the version line in Settings

**Under the hood**
- No permissions needed: the app only manages its own menu bar items
- Apple silicon build, ad-hoc signed with the hardened runtime (not notarized, so macOS asks you to allow it on first launch)
- Licensed under PolyForm Noncommercial 1.0.0: free to use and share with credit, no commercial use
