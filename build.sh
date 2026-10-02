#!/bin/zsh
# Builds a release binary and wraps it in StatusCollapse.app (ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP=build/StatusCollapse.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/StatusCollapse" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
# Build number is the build time (YYYYMMDDHHMMSS); the plist value is just a fallback.
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(date +%Y%m%d%H%M%S)" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP"
