#!/bin/zsh
# Builds Reel.app into ./build
set -euo pipefail
cd "$(dirname "$0")"

tools/fetch-sparkle.sh
swift build -c release --arch arm64

APP="build/Reel.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$(swift build -c release --arch arm64 --show-bin-path)/Reel" "$APP/Contents/MacOS/Reel"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Version comes from the VERSION file (see release.sh); the build number counts commits.
if [[ -f VERSION ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(cat VERSION)" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(git rev-list --count HEAD 2>/dev/null || echo 1)" "$APP/Contents/Info.plist"
fi

if [[ ! -f build/AppIcon.icns ]]; then
  swift tools/MakeIcon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
if [[ -f Resources/Assets.car ]]; then cp Resources/Assets.car "$APP/Contents/Resources/"; fi

# Sparkle. Reel isn't sandboxed, so Sparkle's XPC services aren't needed.
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
ditto Vendor/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework "$FRAMEWORK"
rm -rf "$FRAMEWORK/Versions/B/XPCServices" "$FRAMEWORK/XPCServices"

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
if [[ -z "$IDENTITY" ]]; then
  echo "No signing certificate found; signing ad hoc."
  IDENTITY="-"
fi
# Inside out: Sparkle's helpers, the framework, then the app.
sign() { codesign --force --timestamp=none --sign "$IDENTITY" "$@"; }
sign "$FRAMEWORK/Versions/B/Autoupdate"
sign "$FRAMEWORK/Versions/B/Updater.app"
sign "$FRAMEWORK"
sign "$APP"
codesign --verify --strict --deep "$APP"
echo "Built $APP"
