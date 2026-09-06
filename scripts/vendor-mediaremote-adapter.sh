#!/usr/bin/env bash
# Builds the mediaremote-adapter artefacts (BSD-3-Clause, https://github.com/ungive/mediaremote-adapter)
# from the pinned reference clone with clang — no CMake needed — and places them under
# Vendor/mediaremote-adapter/ for the app to bundle:
#   MediaRemoteAdapter.framework   loaded by /usr/bin/perl, never linked by the app
#   MediaRemoteAdapterTestClient   used only by the `test` health check
#   mediaremote-adapter.pl         the launcher script
# Nothing under references/ is copied into the source tree; only these build products are.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC=references/mediaremote-adapter
EXPECTED_COMMIT=3ac3d4b
OUT=Vendor/mediaremote-adapter
FRAMEWORK="$OUT/MediaRemoteAdapter.framework"
ARCHS=(arm64 x86_64)

[ -d "$SRC/.git" ] || { echo "reference clone missing at $SRC (see docs/harvest/mediaremote-adapter.md)" >&2; exit 1; }
HEAD=$(git -C "$SRC" rev-parse --short=7 HEAD)
[ "$HEAD" = "$EXPECTED_COMMIT" ] || { echo "expected commit $EXPECTED_COMMIT, clone is at $HEAD — review the diff before bumping" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
rm -rf "$OUT"
mkdir -p "$FRAMEWORK/Versions/A/Resources" "$FRAMEWORK/Versions/A/Headers"

ADAPTER_SOURCES=(
  src/adapter/env.m src/adapter/get.m src/adapter/globals.m src/adapter/keys.m src/adapter/now_playing.m
  src/adapter/repeat.m src/adapter/seek.m src/adapter/send.m src/adapter/shuffle.m src/adapter/speed.m
  src/adapter/stream.m src/adapter/test.m src/private/MediaRemote.m src/utility/Debounce.m src/utility/helpers.m
)
for arch in "${ARCHS[@]}"; do
  xcrun clang -arch "$arch" -dynamiclib -fobjc-arc -fvisibility=default -mmacosx-version-min=14.0 -O2 \
    -I"$SRC/include" -I"$SRC/src" \
    -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
    -install_name @rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter \
    -o "$TMP/adapter-$arch" "${ADAPTER_SOURCES[@]/#/$SRC/}"
  xcrun clang -arch "$arch" -fobjc-arc -mmacosx-version-min=14.0 -O2 -I"$SRC/src/test" \
    -framework Foundation -framework MediaPlayer \
    -o "$TMP/client-$arch" "$SRC/src/test/main.m" "$SRC/src/test/NowPlayingTest.m"
done
lipo -create -output "$FRAMEWORK/Versions/A/MediaRemoteAdapter" "${ARCHS[@]/#/$TMP/adapter-}"
lipo -create -output "$OUT/MediaRemoteAdapterTestClient" "${ARCHS[@]/#/$TMP/client-}"
chmod 0755 "$OUT/MediaRemoteAdapterTestClient"

cp "$SRC/include/MediaRemoteAdapter.h" "$FRAMEWORK/Versions/A/Headers/"
cat > "$FRAMEWORK/Versions/A/Resources/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key><string>en</string>
	<key>CFBundleExecutable</key><string>MediaRemoteAdapter</string>
	<key>CFBundleIdentifier</key><string>com.vandenbe.MediaRemoteAdapter</string>
	<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
	<key>CFBundleName</key><string>MediaRemoteAdapter</string>
	<key>CFBundlePackageType</key><string>FMWK</string>
	<key>CFBundleShortVersionString</key><string>0.1</string>
	<key>CFBundleVersion</key><string>0.1.0</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
</dict>
</plist>
PLIST
ln -s A "$FRAMEWORK/Versions/Current"
ln -s Versions/Current/MediaRemoteAdapter "$FRAMEWORK/MediaRemoteAdapter"
ln -s Versions/Current/Resources "$FRAMEWORK/Resources"
ln -s Versions/Current/Headers "$FRAMEWORK/Headers"

cp "$SRC/bin/mediaremote-adapter.pl" "$OUT/mediaremote-adapter.pl"
chmod 0644 "$OUT/mediaremote-adapter.pl"
cp "$SRC/LICENSE" "$OUT/LICENSE"

# Ad-hoc for local builds; a release re-signs inside-out with the Developer ID.
codesign --force --deep --sign - "$FRAMEWORK"
codesign --force --sign - "$OUT/MediaRemoteAdapterTestClient"

{
  echo "source: https://github.com/ungive/mediaremote-adapter"
  echo "commit: $(git -C "$SRC" rev-parse HEAD)"
  echo "built: $(date -u +%Y-%m-%dT%H:%M:%SZ) with $(xcrun clang --version | head -1) on macOS $(sw_vers -productVersion)"
  echo "archs: ${ARCHS[*]}"
  shasum -a 256 "$FRAMEWORK/Versions/A/MediaRemoteAdapter" "$OUT/MediaRemoteAdapterTestClient" "$OUT/mediaremote-adapter.pl"
} > "$OUT/MANIFEST.txt"
echo "vendored into $OUT"
cat "$OUT/MANIFEST.txt"
