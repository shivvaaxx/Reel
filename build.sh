#!/bin/zsh
# Builds Reel.app into ./build
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release --arch arm64

APP="build/Reel.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --arch arm64 --show-bin-path)/Reel" "$APP/Contents/MacOS/Reel"
cp Resources/Info.plist "$APP/Contents/Info.plist"

if [[ ! -f build/AppIcon.icns ]]; then
  swift tools/MakeIcon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP"
echo "Built $APP"
