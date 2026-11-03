#!/bin/zsh
# Downloads Sparkle (Reel's updater) into Vendor/, verifying the official release checksum.
# Run once before building from source; build.sh calls it automatically.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="2.10.1"
SHA256="4c2e48a3e50ebcc2c88a58a4c7264a1a99c3c31857ce754357afb9cdb323022a"
DEST="Vendor/Sparkle"

if [[ -f "$DEST/.version" && "$(cat "$DEST/.version")" == "$VERSION" ]]; then
  exit 0
fi

ZIP=$(mktemp -t sparkle).zip
curl -fsSL -o "$ZIP" "https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/Sparkle-for-Swift-Package-Manager.zip"
ACTUAL=$(shasum -a 256 "$ZIP" | awk '{print $1}')
if [[ "$ACTUAL" != "$SHA256" ]]; then
  echo "Sparkle download checksum mismatch ($ACTUAL); refusing to use it." >&2
  rm -f "$ZIP"
  exit 1
fi
rm -rf "$DEST"
mkdir -p "$DEST"
ditto -x -k "$ZIP" "$DEST"
rm -f "$ZIP"
echo "$VERSION" > "$DEST/.version"
echo "Sparkle $VERSION ready in $DEST"
