#!/usr/bin/env bash
# Builds, replaces any running instance and launches the app.
# Usage: scripts/run.sh [--args -debugTintNotch YES -openDebugPreview YES]
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_DIR="${MYNOTCH_BUILD_DIR:-$HOME/Library/Developer/Xcode/DerivedData/MyNotch}"

scripts/build.sh

if pgrep -x MyNotch >/dev/null; then
  pkill -x MyNotch
  while pgrep -x MyNotch >/dev/null; do sleep 0.1; done
fi

open "$BUILD_DIR/Build/Products/Debug/MyNotch.app" "$@"
