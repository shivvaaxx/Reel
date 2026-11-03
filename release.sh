#!/bin/zsh
# Publishes a Reel release: ./release.sh 1.1.0   (add --dry-run to try it without publishing)
#
#  1. Moves CHANGELOG's [Unreleased] notes under the new version
#  2. Builds, signs and packages Reel-<version>.dmg
#  3. Signs the DMG for Sparkle (with the private key in your Keychain) and adds it to appcast.xml
#  4. Commits, tags v<version>, pushes, and creates the GitHub release with the DMG
# Existing users get the update within a day, via Sparkle.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:-}"
DRY_RUN=false
[[ "${2:-}" == "--dry-run" || "${1:-}" == "--dry-run" ]] && DRY_RUN=true
if [[ ! "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
  echo "Usage: ./release.sh <major.minor.patch> [--dry-run]   e.g. ./release.sh 1.1.0" >&2
  exit 1
fi
if ! $DRY_RUN; then
  [[ -z "$(git status --porcelain)" ]] || { echo "Commit or stash your changes first." >&2; exit 1; }
  [[ "$(git branch --show-current)" == "main" ]] || { echo "Release from main." >&2; exit 1; }
  if git rev-parse "v$VERSION" >/dev/null 2>&1; then
    # A previous run tagged this version but stopped before publishing: finish it.
    if ! gh release view "v$VERSION" >/dev/null 2>&1 && [[ -f "build/Reel-$VERSION.dmg" ]]; then
      echo "v$VERSION is tagged but not published yet; finishing that release."
      NOTES=$(git show "v$VERSION:CHANGELOG.md" | awk -v v="$VERSION" 'index($0, "## [" v "]") == 1 {p=1; next} /^## \[/ {if (p) exit} p')
      git push origin "v$VERSION"
      gh release create "v$VERSION" "build/Reel-$VERSION.dmg" --title "Reel $VERSION" --notes "$NOTES"
      git push origin main
      echo "Released Reel $VERSION. Sparkle users will be offered it within a day."
      exit 0
    fi
    echo "v$VERSION already exists. Use the next version number (see CHANGELOG.md)." >&2
    exit 1
  fi
fi

# 1. Changelog: the [Unreleased] section becomes this version's notes.
NOTES=$(/usr/bin/python3 - "$VERSION" "$DRY_RUN" <<'PY'
import re, sys, datetime
version, dry = sys.argv[1], sys.argv[2] == "true"
text = open("CHANGELOG.md").read()
m = re.search(r"## \[Unreleased\]\n(.*?)(?=\n## \[)", text, re.S)
notes = m.group(1).strip() if m else ""
if not notes:
    sys.exit("CHANGELOG.md has nothing under [Unreleased].")
if not dry:
    today = datetime.date.today().isoformat()
    text = text.replace(m.group(0), f"## [Unreleased]\n\n## [{version}] - {today}\n\n{notes}\n", 1)
    open("CHANGELOG.md", "w").write(text)
print(notes)
PY
)

# 2. Build and package.
echo "$VERSION" > VERSION
./build.sh
DMG=$(./make-dmg.sh | tail -1)
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" build/Reel.app/Contents/Info.plist)

# 3. Sparkle signature and appcast entry.
SIGNATURE=$(Vendor/Sparkle/bin/sign_update --account reel "$DMG")   # sparkle:edSignature="…" length="…"
URL="https://github.com/shivvaaxx/Reel/releases/download/v$VERSION/$(basename "$DMG")"
NOTES="$NOTES" /usr/bin/python3 - "$VERSION" "$BUILD" "$URL" "$SIGNATURE" "$DRY_RUN" <<'PY'
import html, os, re, sys, email.utils
version, build, url, signature, dry = sys.argv[1:6]
lines, out, in_list = os.environ["NOTES"].splitlines(), [], False
for line in lines:
    line = line.rstrip()
    if line.startswith("### "):
        if in_list: out.append("</ul>"); in_list = False
        out.append(f"<h3>{html.escape(line[4:])}</h3>")
    elif line.startswith("- "):
        if not in_list: out.append("<ul>"); in_list = True
        item = html.escape(line[2:])
        item = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", item)
        item = re.sub(r"`(.+?)`", r"<code>\1</code>", item)
        out.append(f"<li>{item}</li>")
if in_list: out.append("</ul>")
item = f"""    <item>
      <title>Reel {version}</title>
      <pubDate>{email.utils.formatdate(localtime=True)}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <description><![CDATA[{''.join(out)}]]></description>
      <enclosure url="{url}" {signature} type="application/octet-stream"/>
    </item>"""
marker = "<!-- release.sh adds new versions below this line -->"
appcast = open("appcast.xml").read().replace(marker, marker + "\n" + item, 1)
if dry == "true":
    print(item)
else:
    open("appcast.xml", "w").write(appcast)
PY

if $DRY_RUN; then
  git checkout -- VERSION 2>/dev/null || true
  echo "\nDry run OK: built $DMG, signed it for Sparkle, and generated the appcast entry above. Nothing was published."
  exit 0
fi

# 4. Publish.
git add VERSION CHANGELOG.md appcast.xml
git commit -m "Release $VERSION"
git tag "v$VERSION"
# Publish the download before pushing the appcast that points to it, so Sparkle never
# offers an update whose file isn't there yet.
git push origin "v$VERSION"
gh release create "v$VERSION" "$DMG" --title "Reel $VERSION" --notes "$NOTES"
git push origin main
echo "Released Reel $VERSION. Sparkle users will be offered it within a day."
