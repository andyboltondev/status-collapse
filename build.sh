#!/bin/zsh
# Builds a universal (Apple silicon + Intel) release binary, then wraps it, and each of its two
# slices, in an ad-hoc signed app at build/<variant>/StatusCollapse.app, where <variant> is
# universal, apple-silicon or intel.
set -euo pipefail
cd "$(dirname "$0")"
# Xcode 27 warns that x86_64 is deprecated for macOS 27. The app targets macOS 26 (Package.swift),
# the last release for Intel Macs, so the warning doesn't apply.
swift build -c release --arch arm64 --arch x86_64
UNIVERSAL="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/StatusCollapse"
# Build number is the build time (YYYYMMDDHHMMSS), shared by all variants; the plist value is just
# a fallback.
BUILD=$(date +%Y%m%d%H%M%S)

for variant in universal apple-silicon intel; do
  APP=build/$variant/StatusCollapse.app
  BIN=$APP/Contents/MacOS/StatusCollapse
  rm -rf "$APP"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
  case $variant in
    universal) cp "$UNIVERSAL" "$BIN" ;;
    apple-silicon) lipo -thin arm64 "$UNIVERSAL" -output "$BIN" ;;
    intel) lipo -thin x86_64 "$UNIVERSAL" -output "$BIN" ;;
  esac
  cp Resources/Info.plist "$APP/Contents/"
  cp Resources/AppIcon.icns CHANGELOG.md "$APP/Contents/Resources/"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"
  # The hardened runtime blocks code injection (e.g. DYLD_INSERT_LIBRARIES) and libraries not
  # signed by Apple. The app needs no exceptions, and notarization requires it.
  codesign --force --sign - --options runtime "$APP"
  echo "Built $APP ($(lipo -archs "$BIN"))"
done
