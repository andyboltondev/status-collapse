#!/bin/zsh
# The one command for testing, building, verifying and packaging StatusCollapse.
#
#   ./build.sh                  run the tests, build build/StatusCollapse.app, then verify it
#   ./build.sh --dmg            ... and package it as build/StatusCollapse-<version>.dmg
#   ./build.sh --tests-only     only run the tests
#   ./build.sh --skip-tests     skip the tests
#   ./build.sh --skip-build     skip building (verify or package the existing app)
#   ./build.sh --skip-verify    skip verifying the built app
#
# The app is an Apple silicon, ad-hoc signed build; macOS 27 runs on Apple silicon only.
set -euo pipefail
cd "$(dirname "$0")"

run_tests=1 run_build=1 run_verify=1 run_dmg=0
for arg in "$@"; do
  case $arg in
    --tests-only) run_build=0 run_verify=0 run_dmg=0 ;;
    --skip-tests) run_tests=0 ;;
    --skip-build) run_build=0 ;;
    --skip-verify) run_verify=0 ;;
    --dmg) run_dmg=1 ;;
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg (try --help)" >&2; exit 2 ;;
  esac
done

if (( run_tests )); then
  echo "==> Testing"
  swift test
fi

if (( run_build )); then
  echo "==> Building"
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
fi

if (( run_verify )); then
  echo "==> Verifying"
  ./tools/verify-build.sh
fi

if (( run_dmg )); then
  echo "==> Packaging"
  ./tools/make-dmg.sh
fi
