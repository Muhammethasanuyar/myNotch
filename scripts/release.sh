#!/usr/bin/env bash
# Builds, signs, packages and publishes a release. The whole procedure: docs/RELEASE.md.
#
#   scripts/release.sh <version> [--dry-run]
#
# Environment (all optional):
#   MYNOTCH_SIGN_IDENTITY   "Developer ID Application: …"; empty = ad-hoc signing (today's default)
#   MYNOTCH_TEAM            the team id that goes with the identity
#   MYNOTCH_NOTARY_PROFILE  notarytool keychain profile (default: mynotch-notary), Developer ID mode only
#   MYNOTCH_BUILD_DIR       derived data (default: ~/Library/Developer/Xcode/DerivedData/MyNotch)
#
# --dry-run archives, signs, verifies and packages, prints the appcast item, and stops before
# touching appcast.xml, git or GitHub. Products stay in build/release/.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/release.sh <version> [--dry-run]}"
shift || true
DRY_RUN=0
for arg in "$@"; do [[ "$arg" == "--dry-run" ]] && DRY_RUN=1; done

IDENTITY="${MYNOTCH_SIGN_IDENTITY:-}"
TEAM="${MYNOTCH_TEAM:-}"
PROFILE="${MYNOTCH_NOTARY_PROFILE:-mynotch-notary}"
BUILD_DIR="${MYNOTCH_BUILD_DIR:-$HOME/Library/Developer/Xcode/DerivedData/MyNotch}"
REPO="Muhammethasanuyar/myNotch"
OUT="build/release"
ARCHIVE="$OUT/MyNotch.xcarchive"
APP="$ARCHIVE/Products/Applications/MyNotch.app"
ZIP="$OUT/MyNotch-$VERSION.zip"
DMG="$OUT/MyNotch-$VERSION.dmg"

log() { printf '\n==> %s\n' "$*"; }
require() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1 — $2" >&2; exit 1; }; }
require xcodegen "brew install xcodegen"
require create-dmg "brew install create-dmg"
require gh "brew install gh && gh auth login"

# --- 0. Preflight -------------------------------------------------------------------------------
log "Preflight"
[[ -z "$(git status --porcelain)" ]] || { echo "working tree is not clean" >&2; exit 1; }
[[ "$(git branch --show-current)" == "main" ]] || { echo "not on main" >&2; exit 1; }
MARKETING=$(sed -nE 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"([^"]+)".*/\1/p' project.yml | head -1)
BUILD_NO=$(sed -nE 's/^[[:space:]]*CURRENT_PROJECT_VERSION:[[:space:]]*"([^"]+)".*/\1/p' project.yml | head -1)
[[ "$MARKETING" == "$VERSION" ]] || { echo "project.yml MARKETING_VERSION is $MARKETING, not $VERSION" >&2; exit 1; }
[[ "$BUILD_NO" =~ ^[0-9]+$ ]] || { echo "CURRENT_PROJECT_VERSION must be an integer, got '$BUILD_NO'" >&2; exit 1; }
LAST_BUILD=$(grep -o 'sparkle:version="[0-9]*"' appcast.xml | head -1 | grep -o '[0-9]*' || true)
if [[ -n "$LAST_BUILD" && "$BUILD_NO" -le "$LAST_BUILD" ]]; then
  echo "CURRENT_PROJECT_VERSION $BUILD_NO must exceed the last published build $LAST_BUILD" >&2; exit 1
fi
grep -q "^## \[$VERSION\]" CHANGELOG.md || { echo "CHANGELOG.md has no '## [$VERSION]' section" >&2; exit 1; }
if [[ $DRY_RUN -eq 0 ]] && gh release view "v$VERSION" --repo "$REPO" >/dev/null 2>&1; then
  echo "release v$VERSION already exists on GitHub" >&2; exit 1
fi
if [[ -n "$IDENTITY" ]]; then
  [[ -n "$TEAM" ]] || { echo "MYNOTCH_TEAM is required with a signing identity" >&2; exit 1; }
  echo "mode: Developer ID ($IDENTITY), hardened runtime, notarization profile '$PROFILE'"
else
  echo "mode: ad-hoc signature (no Developer ID on this machine); Gatekeeper will ask the user to allow the app once"
fi

# --- 1. Tests -----------------------------------------------------------------------------------
log "Generate project and run the tests"
xcodegen generate --quiet
xcodebuild -project MyNotch.xcodeproj -scheme MyNotch -derivedDataPath "$BUILD_DIR" -resolvePackageDependencies -quiet
xcodebuild -project MyNotch.xcodeproj -scheme MyNotch -configuration Debug -derivedDataPath "$BUILD_DIR" \
  -destination 'platform=macOS,arch=arm64' -quiet test

# --- 2. Archive (universal) ---------------------------------------------------------------------
log "Archive Release $VERSION ($BUILD_NO)"
rm -rf "$OUT"
mkdir -p "$OUT"
SIGN_SETTINGS=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=${IDENTITY:--}")
if [[ -n "$IDENTITY" ]]; then
  SIGN_SETTINGS+=("DEVELOPMENT_TEAM=$TEAM" ENABLE_HARDENED_RUNTIME=YES CODE_SIGN_ENTITLEMENTS=Resources/MyNotch.entitlements "OTHER_CODE_SIGN_FLAGS=--timestamp")
fi
xcodebuild -project MyNotch.xcodeproj -scheme MyNotch -configuration Release -derivedDataPath "$BUILD_DIR" \
  -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" -quiet archive "${SIGN_SETTINGS[@]}"
[[ -d "$APP" ]] || { echo "archive produced no app at $APP" >&2; exit 1; }

# --- 3. Sign inside-out -------------------------------------------------------------------------
log "Sign (inside-out)"
sign() {
  if [[ -n "$IDENTITY" ]]; then
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$@"
  else
    codesign --force --sign - "$@"
  fi
}
FRAMEWORKS="$APP/Contents/Frameworks"
sign "$FRAMEWORKS/MediaRemoteAdapter.framework"
SPARKLE="$FRAMEWORKS/Sparkle.framework/Versions/B"
for service in "$SPARKLE"/XPCServices/*.xpc; do [[ -e "$service" ]] && sign "$service"; done
[[ -e "$SPARKLE/Autoupdate" ]] && sign "$SPARKLE/Autoupdate"
[[ -e "$SPARKLE/Updater.app" ]] && sign "$SPARKLE/Updater.app"
sign "$FRAMEWORKS/Sparkle.framework"
sign "$APP/Contents/Resources/MediaRemoteAdapterTestClient"
if [[ -n "$IDENTITY" ]]; then
  sign --entitlements Resources/MyNotch.entitlements "$APP"
else
  sign "$APP"
fi

# --- 4. Verify ----------------------------------------------------------------------------------
log "Verify signatures"
codesign --verify --deep --strict --verbose=2 "$APP"
for item in "$APP" "$FRAMEWORKS/MediaRemoteAdapter.framework" "$FRAMEWORKS/Sparkle.framework" "$APP/Contents/Resources/MediaRemoteAdapterTestClient"; do
  printf '%-60s %s\n' "$(basename "$item")" "$(codesign -dv "$item" 2>&1 | grep -E '^(Signature|TeamIdentifier)=' | tr '\n' ' ')"
done
if spctl -a -t exec -vv "$APP" 2>&1; then
  echo "Gatekeeper: accepted"
else
  echo "Gatekeeper: rejected — expected with an ad-hoc signature; the README explains Open Anyway"
fi

# --- 5. Notarize the app (Developer ID mode) ----------------------------------------------------
if [[ -n "$IDENTITY" ]]; then
  log "Notarize the app"
  ditto -c -k --keepParent "$APP" "$OUT/notarize.zip"
  xcrun notarytool submit "$OUT/notarize.zip" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$APP"
  rm -f "$OUT/notarize.zip"
fi

# --- 6. Package ---------------------------------------------------------------------------------
log "Package"
ditto -c -k --keepParent "$APP" "$ZIP"
STAGE="$OUT/dmg"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
create-dmg --volname "MyNotch" --volicon Resources/AppIcon.icns --window-pos 200 120 --window-size 600 400 \
  --icon-size 128 --icon "MyNotch.app" 150 190 --app-drop-link 450 190 --hide-extension "MyNotch.app" \
  --no-internet-enable "$DMG" "$STAGE" >/dev/null
rm -rf "$STAGE"
if [[ -n "$IDENTITY" ]]; then
  sign "$DMG"
  log "Notarize the disk image"
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$DMG"
fi
ls -la "$ZIP" "$DMG"

# --- 7. Sparkle signature and appcast item ------------------------------------------------------
log "Sparkle signature"
SIGN_UPDATE=$(find "$BUILD_DIR/SourcePackages/artifacts" -path "*parkle*/bin/sign_update" -type f 2>/dev/null | head -1)
[[ -n "$SIGN_UPDATE" ]] || { echo "sign_update not found under $BUILD_DIR/SourcePackages — build once first" >&2; exit 1; }
SIGNATURE=$("$SIGN_UPDATE" "$ZIP")   # sparkle:edSignature="…" length="…"
echo "$SIGNATURE"
NOTES=$(awk -v v="$VERSION" '$0 ~ "^## \\[" v "\\]" {f=1; next} /^## \[/ {f=0} f' CHANGELOG.md | sed -e '1{/^$/d;}')
PUBDATE=$(LC_ALL=C date "+%a, %d %b %Y %H:%M:%S %z")
# The changelog section as HTML for Sparkle's notes pane: headings, bullet lists, inline code.
NOTES_HTML=$(python3 - "$NOTES" <<'PY'
import html, re, sys
out, in_list = [], False
def inline(text):
    return re.sub(r"\x60([^\x60]+)\x60", r"<code>\1</code>", html.escape(text))  # \x60 = backtick, kept out of bash's way
for line in sys.argv[1].splitlines():
    if line.startswith("### "):
        if in_list: out.append("</ul>"); in_list = False
        out.append("<h3>" + html.escape(line[4:]) + "</h3>")
    elif line.startswith("- "):
        if not in_list: out.append("<ul>"); in_list = True
        out.append("<li>" + inline(line[2:]) + "</li>")
    elif line.strip():
        if in_list: out.append("</ul>"); in_list = False
        out.append("<p>" + inline(line) + "</p>")
if in_list: out.append("</ul>")
print("\n".join(out))
PY
)
ITEM=$(cat <<ITEM
    <item>
      <title>MyNotch $VERSION</title>
      <link>https://github.com/$REPO/releases/tag/v$VERSION</link>
      <sparkle:version>$BUILD_NO</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <pubDate>$PUBDATE</pubDate>
      <description><![CDATA[$NOTES_HTML]]></description>
      <enclosure url="https://github.com/$REPO/releases/download/v$VERSION/MyNotch-$VERSION.zip" type="application/octet-stream" $SIGNATURE/>
    </item>
ITEM
)
echo "$ITEM"

if [[ $DRY_RUN -eq 1 ]]; then
  log "Dry run: appcast.xml, git and GitHub untouched. Products in $OUT/"
  exit 0
fi

# --- 8. Publish ---------------------------------------------------------------------------------
log "Update appcast.xml"
python3 - "$ITEM" <<'PY'
import sys
item = sys.argv[1]
path = "appcast.xml"
text = open(path, encoding="utf-8").read()
marker = "    <language>en</language>\n"
assert text.count(marker) == 1, "appcast.xml lost its <language> line"
text = text.replace(marker, marker + item + "\n")
open(path, "w", encoding="utf-8").write(text)
PY
git add appcast.xml
git commit -q -m "chore(release): publish v$VERSION"
git push -q origin main

log "GitHub release"
gh release create "v$VERSION" "$DMG" "$ZIP" --repo "$REPO" --title "MyNotch $VERSION" --notes "$NOTES"
gh release view "v$VERSION" --repo "$REPO" --json url,assets --jq '.url, (.assets[].name)'
log "Done: v$VERSION"
