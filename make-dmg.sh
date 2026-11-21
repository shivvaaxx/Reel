#!/bin/zsh
# Packages build/Reel.app into build/Reel-<version>.dmg with an Applications shortcut.
#
# With a stored notarytool profile, the app is signed with Developer ID, the DMG is
# notarized by Apple and stapled, so it opens without the "cannot verify" warning.
# The Developer ID signature comes from a local "Developer ID Application" certificate
# if there is one, otherwise from Xcode's cloud signing (needs Xcode signed in to an
# account on the team; no certificate on this Mac). Only a local certificate can sign
# the DMG itself, which notarization doesn't require.
# One-time setup (needs an app-specific password from appleid.apple.com):
#   xcrun notarytool store-credentials reel-notary --apple-id <email> --team-id <TEAM>
# Set REEL_NOTARY_PROFILE to use a different profile name.
set -euo pipefail
cd "$(dirname "$0")"

[[ -d build/Reel.app ]] || ./build.sh

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" build/Reel.app/Contents/Info.plist)
DMG="build/Reel-$VERSION.dmg"
PROFILE="${REEL_NOTARY_PROFILE:-reel-notary}"
DEVID=$(security find-identity -v -p codesigning | grep '"Developer ID Application' | head -1 | awk '{print $2}' || true)
NOTARIZE=false
xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 && NOTARIZE=true

# No local Developer ID certificate: re-sign through Xcode's cloud signing, the way an
# Xcode "Developer ID" export does. The app is wrapped in a minimal archive for it.
if $NOTARIZE && [[ -z "$DEVID" ]]; then
  TEAM=$(codesign -dv build/Reel.app 2>&1 | sed -n 's/^TeamIdentifier=//p')
  [[ -n "$TEAM" && "$TEAM" != "not set" ]] || { echo "build/Reel.app isn't signed by a team; can't use cloud signing." >&2; exit 1; }
  ARCHIVE="build/Reel.xcarchive"
  rm -rf "$ARCHIVE" build/export build/ExportOptions.plist
  mkdir -p "$ARCHIVE/Products/Applications"
  ditto build/Reel.app "$ARCHIVE/Products/Applications/Reel.app"
  plist() { /usr/libexec/PlistBuddy -c "$1" "$2" >/dev/null; }
  plist "Add :ArchiveVersion integer 2" "$ARCHIVE/Info.plist"
  plist "Add :Name string Reel" "$ARCHIVE/Info.plist"
  plist "Add :ApplicationProperties dict" "$ARCHIVE/Info.plist"
  plist "Add :ApplicationProperties:ApplicationPath string Applications/Reel.app" "$ARCHIVE/Info.plist"
  plist "Add :ApplicationProperties:CFBundleIdentifier string $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' build/Reel.app/Contents/Info.plist)" "$ARCHIVE/Info.plist"
  plist "Add :ApplicationProperties:CFBundleShortVersionString string $VERSION" "$ARCHIVE/Info.plist"
  plist "Add :ApplicationProperties:Team string $TEAM" "$ARCHIVE/Info.plist"
  plist "Add :method string developer-id" build/ExportOptions.plist
  plist "Add :signingStyle string automatic" build/ExportOptions.plist
  plist "Add :teamID string $TEAM" build/ExportOptions.plist
  echo "Signing with Developer ID through Xcode cloud signing…"
  xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath build/export \
    -exportOptionsPlist build/ExportOptions.plist -allowProvisioningUpdates >/dev/null
  rm -rf build/Reel.app "$ARCHIVE" build/ExportOptions.plist
  ditto build/export/Reel.app build/Reel.app
  rm -rf build/export
fi
STAGE="build/dmg-stage"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R build/Reel.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "Reel" -srcfolder "$STAGE" -ov -format UDZO -fs APFS "$DMG" >/dev/null
rm -rf "$STAGE"

if $NOTARIZE; then
  [[ -n "$DEVID" ]] && codesign --force --timestamp --sign "$DEVID" "$DMG"
  echo "Notarizing $DMG (usually a few minutes)…"
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait | tee build/notarize.log
  grep -q "status: Accepted" build/notarize.log || { echo "Notarization failed; see build/notarize.log" >&2; exit 1; }
  rm -f build/notarize.log
  xcrun stapler staple "$DMG"
else
  echo "Note: not notarized. Run: xcrun notarytool store-credentials $PROFILE --apple-id <email> --team-id <TEAM>"
fi
echo "$DMG"
