#!/usr/bin/env bash
# Runs the unit tests (the app is the test host, so the notch panel appears briefly).
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate --use-cache --quiet
xcodebuild \
  -project MyNotch.xcodeproj \
  -scheme MyNotch \
  -configuration Debug \
  -derivedDataPath build \
  -destination 'platform=macOS,arch=arm64' \
  -quiet \
  test "$@"
