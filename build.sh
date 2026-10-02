#!/bin/zsh
# Builds a release binary and wraps it in StatusCollapse.app (ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP=build/StatusCollapse.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/StatusCollapse" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
codesign --force --sign - "$APP"
echo "Built $APP"
