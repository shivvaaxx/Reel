#!/bin/zsh
# Packages build/Reel.app into build/Reel-<version>.dmg with an Applications shortcut.
set -euo pipefail
cd "$(dirname "$0")"

[[ -d build/Reel.app ]] || ./build.sh

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" build/Reel.app/Contents/Info.plist)
DMG="build/Reel-$VERSION.dmg"
STAGE="build/dmg-stage"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R build/Reel.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "Reel" -srcfolder "$STAGE" -ov -format UDZO -fs APFS "$DMG" >/dev/null
rm -rf "$STAGE"
echo "$DMG"
