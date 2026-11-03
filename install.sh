#!/bin/zsh
# Builds Reel and installs it into /Applications for testing on this Mac.
# A locally built copy isn't marked as downloaded, so macOS opens it without the
# "cannot verify" warning that a downloaded, un-notarized DMG triggers.
set -euo pipefail
cd "$(dirname "$0")"

./build.sh
osascript -e 'tell application id "com.shiva.reel" to quit' 2>/dev/null || true
sleep 1
ditto build/Reel.app /Applications/Reel.app
xattr -dr com.apple.quarantine /Applications/Reel.app 2>/dev/null || true
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Reel.app
open /Applications/Reel.app
echo "Installed /Applications/Reel.app"
