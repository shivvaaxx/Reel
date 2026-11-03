#!/bin/zsh
# Packages build/Reel.app into build/Reel.dmg with an Applications shortcut.
set -euo pipefail
cd "$(dirname "$0")"

[[ -d build/Reel.app ]] || ./build.sh

STAGE="build/dmg-stage"
rm -rf "$STAGE" build/Reel.dmg
mkdir -p "$STAGE"
cp -R build/Reel.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "Reel" -srcfolder "$STAGE" -ov -format UDZO -fs APFS build/Reel.dmg >/dev/null
rm -rf "$STAGE"
echo "Built build/Reel.dmg"
