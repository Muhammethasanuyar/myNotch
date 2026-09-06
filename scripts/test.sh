#!/usr/bin/env bash
# Runs the unit tests (the app is the test host, so the notch panel appears briefly).
set -euo pipefail
cd "$(dirname "$0")/.."
# Build products live outside ~/Documents: the app is its own test host, and an app that reads
# its test bundle from Documents trips the Documents-folder permission prompt on every re-sign.
BUILD_DIR="${MYNOTCH_BUILD_DIR:-$HOME/Library/Developer/Xcode/DerivedData/MyNotch}"

xcodegen generate --quiet
xcodebuild \
  -project MyNotch.xcodeproj \
  -scheme MyNotch \
  -configuration Debug \
  -derivedDataPath "$BUILD_DIR" \
  -destination 'platform=macOS,arch=arm64' \
  -quiet \
  test "$@"
