#!/usr/bin/env bash
# Regenerates the Xcode project when project.yml changed, then builds Debug into ./build.
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate --quiet
xcodebuild \
  -project MyNotch.xcodeproj \
  -scheme MyNotch \
  -configuration Debug \
  -derivedDataPath build \
  -destination 'platform=macOS,arch=arm64' \
  -quiet \
  build "$@"
