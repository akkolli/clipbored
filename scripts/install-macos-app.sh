#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_BUNDLE="$REPO_ROOT/build/Goldfish.app"
DESTINATION="${1:-/Applications/Goldfish.app}"
[[ "$DESTINATION" == /*/Goldfish.app ]] || { echo "FAIL: use an absolute destination ending in Goldfish.app"; exit 1; }
if pgrep -x Goldfish >/dev/null; then echo "FAIL: quit Goldfish before installing"; exit 1; fi
"$SCRIPT_DIR/build-macos-app.sh"
python3 "$SCRIPT_DIR/build-state.py" installable "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"
INSTALL_STAGE="$(mktemp -d "$(dirname "$DESTINATION")/.goldfish-install.XXXXXX")"
BACKUP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/goldfish-install-backup.XXXXXX")"
trap 'rm -rf "$INSTALL_STAGE"' EXIT
ditto "$APP_BUNDLE" "$INSTALL_STAGE/Goldfish.app"
diff -qr "$APP_BUNDLE" "$INSTALL_STAGE/Goldfish.app"
codesign --verify --deep --strict "$INSTALL_STAGE/Goldfish.app"
if pgrep -x Goldfish >/dev/null; then echo "FAIL: Goldfish started during the build; quit and retry"; exit 1; fi
if [[ -e "$DESTINATION" ]]; then mv "$DESTINATION" "$BACKUP_ROOT/Goldfish.app"; fi
if ! mv "$INSTALL_STAGE/Goldfish.app" "$DESTINATION"; then
  [[ ! -e "$BACKUP_ROOT/Goldfish.app" ]] || mv "$BACKUP_ROOT/Goldfish.app" "$DESTINATION"
  exit 1
fi
if ! codesign --verify --deep --strict "$DESTINATION" || ! python3 "$SCRIPT_DIR/build-state.py" installable "$DESTINATION"; then
  mv "$DESTINATION" "$INSTALL_STAGE/Rejected.app"
  [[ ! -e "$BACKUP_ROOT/Goldfish.app" ]] || mv "$BACKUP_ROOT/Goldfish.app" "$DESTINATION"
  exit 1
fi
open "$DESTINATION"
INSTALLED_PID=""
for _ in {1..50}; do
  INSTALLED_PID="$(pgrep -x Goldfish | head -n 1 || true)"
  [[ -z "$INSTALLED_PID" ]] || break
  sleep 0.1
done
[[ -n "$INSTALLED_PID" ]] || { echo "FAIL: installed Goldfish did not launch"; exit 1; }
RUNNING_EXECUTABLE="$(ps -p "$INSTALLED_PID" -o comm= | sed 's/^[[:space:]]*//')"
[[ "$RUNNING_EXECUTABLE" == "$DESTINATION/Contents/MacOS/Goldfish" ]] || {
  echo "FAIL: another app was launched: $RUNNING_EXECUTABLE"; exit 1;
}
echo "Installed $DESTINATION; previous app preserved at $BACKUP_ROOT/Goldfish.app"
