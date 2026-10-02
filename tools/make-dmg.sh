#!/bin/zsh
# Builds the apps, then packages each as build/StatusCollapse-<version>-<variant>.dmg with a
# drag-to-Applications layout. Images are made with `diskutil image` (macOS 26+), which replaces
# the hdiutil verbs deprecated in macOS 27.
# Positioning icons drives Finder via AppleScript, so macOS may ask to allow automation the first time.
set -euo pipefail
cd "$(dirname "$0")/.."
./build.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" build/universal/StatusCollapse.app/Contents/Info.plist)
VOL=StatusCollapse
RW=build/rw.dmg
BACKGROUND=build/dmg-background.tiff
DEVICE=

# However the script exits (e.g. automation was denied), eject the working image and remove
# scratch files rather than leaving the volume mounted. zsh skips EXIT traps when `set -e` fires
# because of a function, so a function here must call `exit` itself when something fails.
cleanup() {
  if [[ -n $DEVICE ]]; then
    diskutil unmountDisk force "$DEVICE" >/dev/null 2>&1 || true
    diskutil eject "$DEVICE" >/dev/null 2>&1 || true
  fi
  rm -f "$RW" "$BACKGROUND"
}
trap cleanup EXIT

# Runs a command without its progress output, printing what it said only if it fails.
quietly() {
  local output
  output=$("$@" 2>&1) || { echo "$output" >&2; exit 1; }
}

# Finder finds the volume by name, so first eject every volume already using it, such as an
# opened copy of the DMG ("StatusCollapse", "StatusCollapse 1", ...). Otherwise Finder could
# lay out the wrong one.
for mount in "/Volumes/$VOL" "/Volumes/$VOL "{1..9}; do
  [[ -e $mount ]] || continue
  if ! diskutil eject "$mount" >/dev/null 2>&1; then
    echo "Eject $mount first: Finder can't tell it apart from the new volume." >&2
    exit 1
  fi
done

swift tools/make-dmg-background.swift "$BACKGROUND"

for variant in universal apple-silicon intel; do
  DMG=build/StatusCollapse-$VERSION-$variant.dmg
  rm -f "$RW" "$DMG"

  # diskutil can't make a writable image from a folder, so fill a blank one, lay it out in Finder,
  # then compress it.
  quietly diskutil image create blank --format RAW --size 20m --volumeName "$VOL" --fs APFS "$RW"
  # attach prints the image's whole-disk device first, and ends the volume's line with its mount point.
  ATTACH=$(diskutil image attach "$RW")
  DEVICE=$(awk 'NR == 1 { print $1 }' <<< "$ATTACH")
  MOUNT=$(awk -F'\t' '$NF ~ "^/Volumes/" { print $NF }' <<< "$ATTACH")
  if [[ -z $DEVICE || -z $MOUNT ]]; then
    echo "Couldn't find where $RW was attached:" >&2
    echo "$ATTACH" >&2
    exit 1
  fi
  ditto "build/$variant/StatusCollapse.app" "$MOUNT/StatusCollapse.app"
  ln -s /Applications "$MOUNT/Applications"
  mkdir "$MOUNT/.background"
  cp "$BACKGROUND" "$MOUNT/.background/background.tiff"

  # Set up the Finder window: icon view, size, background and icon positions.
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
  diskutil eject "$DEVICE" >/dev/null
  DEVICE=
  quietly diskutil image create from --format ULFO "$RW" "$DMG"
  echo "Built $DMG"
done
