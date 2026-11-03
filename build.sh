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

# macOS 26 icon with light, dark (black arrow) and tinted variants. Resources/AppIcon.icon
# is an Icon Composer document (open it in Icon Composer to tweak); actool compiles it into
# Assets.car. The .icns above stays as the fallback for Finder previews and older tools.
if [[ ! -d Resources/AppIcon.icon ]]; then
  swift tools/MakeIcon.swift --icon-composer Resources/AppIcon.icon
fi
if xcrun --find actool >/dev/null 2>&1; then
  rm -rf build/assets && mkdir -p build/assets
  xcrun actool Resources/AppIcon.icon --compile build/assets --platform macosx \
    --minimum-deployment-target 26.0 --app-icon AppIcon \
    --output-partial-info-plist build/assets/partial.plist >/dev/null
  cp build/assets/Assets.car "$APP/Contents/Resources/Assets.car"
  [[ -f build/assets/AppIcon.icns ]] && cp build/assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconName string AppIcon" "$APP/Contents/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Set :CFBundleIconName AppIcon" "$APP/Contents/Info.plist"
fi

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
# App extensions (Share menu, Safari button, Shortcuts actions) need Xcode and a real signing
# certificate, because macOS only loads signed, sandboxed extensions. Skipped otherwise.
if [[ "$IDENTITY" != "-" ]] && command -v xcodebuild >/dev/null; then
  VERSION_STRING=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
  BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")
  if command -v xcodegen >/dev/null; then xcodegen generate --quiet --spec Extensions/project.yml; fi
  xcodebuild -quiet -project Extensions/ReelExtensions.xcodeproj -alltargets -configuration Release \
    -allowProvisioningUpdates SYMROOT="$PWD/build/ext" \
    MARKETING_VERSION="$VERSION_STRING" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" build
  mkdir -p "$APP/Contents/PlugIns" "$APP/Contents/Extensions"
  ditto build/ext/Release/ReelShare.appex "$APP/Contents/PlugIns/ReelShare.appex"
  ditto build/ext/Release/ReelSafari.appex "$APP/Contents/PlugIns/ReelSafari.appex"
  ditto build/ext/Release/ReelIntents.appex "$APP/Contents/Extensions/ReelIntents.appex"
else
  echo "Skipping app extensions (needs Xcode and a signing certificate)."
fi

# Developer ID builds get the hardened runtime and a secure timestamp, which Apple's
# notarization requires (make-dmg.sh then notarizes). Other builds skip both.
if [[ "$IDENTITY" != "-" ]] && security find-identity -v -p codesigning | grep "$IDENTITY" | grep -q "Developer ID Application"; then
  SIGN_FLAGS=(--options runtime --timestamp)
  for appex in "$APP"/Contents/PlugIns/*.appex(N) "$APP"/Contents/Extensions/*.appex(N); do
    codesign --force "${SIGN_FLAGS[@]}" --preserve-metadata=entitlements --sign "$IDENTITY" "$appex"
  done
else
  SIGN_FLAGS=(--timestamp=none)
fi

# Inside out: Sparkle's helpers, the framework, then the app. Extensions keep the
# sandbox entitlements Xcode gave them.
sign() { codesign --force "${SIGN_FLAGS[@]}" --sign "$IDENTITY" "$@"; }
sign "$FRAMEWORK/Versions/B/Autoupdate"
sign "$FRAMEWORK/Versions/B/Updater.app"
sign "$FRAMEWORK"
sign "$APP"
codesign --verify --strict --deep "$APP"
echo "Built $APP"
