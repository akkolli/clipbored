#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

if pgrep -x Goldfish >/dev/null; then echo "FAIL: quit Goldfish before clipboard tests"; exit 1; fi
for script in "$SCRIPT_DIR/"*.sh; do bash -n "$script"; done
python3 -m unittest discover -s Tests/BuildTools -p 'test_*.py'
swift test -q
"$SCRIPT_DIR/build-macos-app.sh" --allow-dirty
codesign --verify --deep --strict --verbose=2 "$REPO_ROOT/build/Goldfish.app"
