#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

bash -n "$SCRIPT_DIR/release-macos-app.sh"
swift test -q
"$SCRIPT_DIR/build-macos-app.sh"
codesign --verify --deep --strict --verbose=2 "$REPO_ROOT/build/ClipBored.app"
