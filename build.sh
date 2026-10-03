#!/bin/zsh
# Builds an Apple silicon release binary and wraps it in an ad-hoc signed app at
# build/StatusCollapse.app. macOS 27 runs on Apple silicon only, so there is no Intel build.
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release --arch arm64
BIN_DIR=$(swift build -c release --arch arm64 --show-bin-path)
# Build number is the build time (YYYYMMDDHHMMSS); the plist value is just a fallback.
BUILD=$(date +%Y%m%d%H%M%S)

APP=build/StatusCollapse.app
rm -rf build/universal build/apple-silicon build/intel "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/StatusCollapse" "$APP/Contents/MacOS/StatusCollapse"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns CHANGELOG.md "$APP/Contents/Resources/"
cp -R Resources/Localization/*.lproj "$APP/Contents/Resources/"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"
# The hardened runtime blocks code injection (e.g. DYLD_INSERT_LIBRARIES) and libraries not
# signed by Apple. The app needs no exceptions, and notarization requires it.
codesign --force --sign - --options runtime "$APP"
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/StatusCollapse"))"
