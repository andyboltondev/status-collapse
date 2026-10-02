#!/bin/zsh
# Builds the app, then packages it as build/StatusCollapse-<version>.dmg with a drag-to-Applications layout.
# Positioning icons drives Finder via AppleScript, so macOS may ask to allow automation the first time.
set -euo pipefail
cd "$(dirname "$0")/.."
./build.sh
APP=build/StatusCollapse.app
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG=build/StatusCollapse-$VERSION.dmg
VOL=StatusCollapse
STAGE=build/dmg-stage
RW=build/rw.dmg

hdiutil detach "/Volumes/$VOL" >/dev/null 2>&1 || true
rm -rf "$STAGE" "$RW" "$DMG"
mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
swift tools/make-dmg-background.swift "$STAGE/.background/background.tiff"

hdiutil create -srcfolder "$STAGE" -volname "$VOL" -fs HFS+ -format UDRW -size 20m "$RW" >/dev/null
hdiutil attach "$RW" -noverify -noautoopen >/dev/null

osascript <<OSA
tell application "Finder"
  tell disk "$VOL"
    open
    delay 1
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 520}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set text size of opts to 13
    set background picture of opts to file ".background:background.tiff"
    set position of item "StatusCollapse.app" of container window to {180, 190}
    set position of item "Applications" of container window to {480, 190}
    delay 1
    set the bounds of container window to {200, 120, 860, 520}
    update without registering applications
    delay 2
    close
  end tell
end tell
OSA

sync
hdiutil detach "/Volumes/$VOL" >/dev/null
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -rf "$RW" "$STAGE"
echo "Built $DMG"
