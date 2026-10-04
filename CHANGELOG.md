# Changelog

## 1.0.1 - 2026-10-04

Better support for more than one display, and a proper What's New window.

**Displays**
- Hiding now works on wide displays without a notch: StatusCollapse spans the widest display, so icons can no longer stay visible beside the button
- Icons no longer jump left before fading out when collapsing with an external display connected
- The button's copy on other displays now updates when the icons are hidden or shown
- Pressing the empty menu bar beside the button no longer shows a long highlight on a display without a notch
- New **Prevent click highlights** setting (Behaviour tab, off by default): with more than one display, also stops that highlight on a display you aren't using. It needs the Device Control and Data Access permission, and Settings shows whether it's allowed and opens Privacy & Security for you

**Settings**
- The Settings window now resizes to fit each tab as you switch, keeping its top edge in place, with the same margins on every tab
- What's New opens in its own window, with the version, its release date in your language and the notes grouped by topic
- The setup walkthrough now shows the button as it looks in the menu bar

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
