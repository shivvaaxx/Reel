#!/bin/zsh
# Packages build/Reel.app into build/Reel-<version>.dmg with an Applications shortcut.
#
# With a Developer ID certificate and a stored notarytool profile, the DMG is also signed,
# notarized by Apple and stapled, so it opens without the "cannot verify" warning.
# One-time setup (needs an app-specific password from appleid.apple.com):
#   xcrun notarytool store-credentials reel-notary --apple-id <email> --team-id <TEAM>
# Set REEL_NOTARY_PROFILE to use a different profile name.
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

PROFILE="${REEL_NOTARY_PROFILE:-reel-notary}"
DEVID=$(security find-identity -v -p codesigning | grep '"Developer ID Application' | head -1 | awk '{print $2}' || true)
if [[ -n "$DEVID" ]] && xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  codesign --force --timestamp --sign "$DEVID" "$DMG"
  echo "Notarizing $DMG (usually a few minutes)…"
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature -v "$DMG"
elif [[ -n "$DEVID" ]]; then
  echo "Note: not notarized. Run: xcrun notarytool store-credentials $PROFILE --apple-id <email> --team-id <TEAM>"
else
  echo "Note: not notarized (needs a Developer ID Application certificate), so macOS will warn on first open."
fi
echo "$DMG"
