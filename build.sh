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

# Sign with a stable identity so macOS remembers Reel's permissions (Downloads, Full Disk
# Access…) across rebuilds and updates. Set REEL_SIGN_IDENTITY to choose one; otherwise the
# first "Developer ID Application" or "Apple Development" certificate is used, falling back
# to ad-hoc signing (fine for building it yourself, but macOS will re-ask for permissions).
IDENTITY="${REEL_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  for kind in "Developer ID Application" "Apple Development"; do
    IDENTITY=$(security find-identity -v -p codesigning | grep "\"$kind" | head -1 | awk '{print $2}' || true)
    [[ -n "$IDENTITY" ]] && break
  done
fi
if [[ -n "$IDENTITY" ]]; then
  codesign --force --timestamp=none --sign "$IDENTITY" "$APP"
else
  echo "No signing certificate found; signing ad hoc."
  codesign --force --sign - "$APP"
fi
echo "Built $APP"
