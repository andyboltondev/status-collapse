#!/bin/zsh
# Checks the built app in build/ is what a release should contain: Apple silicon only, a valid
# hardened-runtime signature, a matching version, macOS 27 as the minimum, and the bundled
# changelog and languages.
set -euo pipefail
cd "$(dirname "$0")/.."

PLIST_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
fail() { echo "FAIL: $*" >&2; exit 1 }

APP=build/StatusCollapse.app
[[ -d $APP ]] || fail "$APP is missing"
have=$(lipo -archs "$APP/Contents/MacOS/StatusCollapse")
[[ $have == arm64 ]] || fail "architectures are '$have', expected 'arm64'"

codesign --verify --strict "$APP" || fail "signature is invalid"
details=$(codesign -dv "$APP" 2>&1)
[[ $details == *"flags="*runtime* ]] || fail "the hardened runtime is not enabled"

info=$APP/Contents/Info.plist
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$info")
[[ $version == $PLIST_VERSION ]] || fail "version $version != $PLIST_VERSION"
minimum=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$info")
[[ $minimum == 27.0 ]] || fail "minimum system version is $minimum, expected 27.0"
head -3 CHANGELOG.md | grep -q "## $version" || fail "CHANGELOG.md has no entry for $version at the top"
[[ -f $APP/Contents/Resources/CHANGELOG.md ]] || fail "the changelog is not bundled"
langs=$(ls -d "$APP"/Contents/Resources/*.lproj | wc -l | tr -d ' ')
(( langs >= 30 )) || fail "only $langs languages are bundled"
echo "OK  $have, $version, macOS $minimum+, $langs languages"
