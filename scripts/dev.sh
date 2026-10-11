#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

case "${1:-build}" in
  build|check) echo "FAIL: archived refactoring branch; build current Goldfish from main."; exit 1 ;;
esac

case "${1:-build}" in
  check)
    bash -n "$SCRIPT_DIR/release-macos-app.sh"
    find sources tests -type f -name '*.swift' -exec wc -l {} + | awk '
      $NF != "total" && $1 > 1200 { print "FAIL: " $2 " exceeds 1200 readable lines"; failed = 1 }
      END { exit failed }
    '
    python3 - <<'TEST_BUDGET'
from pathlib import Path
import re
files = [path for path in Path('tests').rglob('*') if path.is_file()]
lines = sum(len(path.read_text().splitlines()) for path in files)
methods = sum(len(re.findall(r'\bfunc test\w+\(\)', path.read_text())) for path in files if path.suffix == '.swift')
print(f"Test suite: {lines:,} lines in {len(files)} files; {methods} XCTest methods")
if lines > 1900:
    raise SystemExit("FAIL: tests and shared fixtures must stay within 1,900 total lines")
TEST_BUDGET
    swift test -q
    ;;
  inventory)
    python3 - <<'INVENTORY'
from pathlib import Path
counts = {"maintained": [0, 0, 0], "generated": [0, 0, 0]}
for path in Path('.').rglob('*'):
    if not path.is_file() or path.is_symlink():
        continue
    group = "generated" if path.parts[0] in {'.build', 'build'} else "maintained"
    data = path.read_bytes()
    counts[group][0] += 1
    counts[group][1] += len(data)
    try:
        text = data.decode('utf-8')
        if '\0' not in text:
            counts[group][2] += len(text.splitlines())
    except UnicodeDecodeError:
        pass
for group, (files, size, lines) in counts.items():
    print(f"{group}: {files} files, {size:,} bytes, {lines:,} UTF-8 text lines")
print("Binary assets count toward files and bytes, not text lines. Hidden files are included.")
INVENTORY
    exit 0
    ;;
  idle)
    PID="$(pgrep -x Goldfish | head -n 1 || true)"
    [[ -n "$PID" ]] || { echo "Launch build/Goldfish.app first."; exit 1; }
    ps -o pid,pcpu,pmem,time,command -p "$PID"
    sleep "${2:-900}"
    ps -o pid,pcpu,pmem,time,command -p "$PID"
    echo "Use Instruments or Activity Monitor Energy for wakeup/energy validation."
    exit 0
    ;;
  clean)
    for product in .build build; do
      if [[ -e "$product" ]] && ! git check-ignore -q "$product/"; then
        echo "Refusing to remove $product: it is not a Git-ignored build directory."
        exit 1
      fi
    done
    if [[ -n "$(git ls-files -- .build build)" ]]; then
      echo "Refusing to remove build directories containing tracked files."
      exit 1
    fi
    rm -rf "$REPO_ROOT/.build" "$REPO_ROOT/build"
    exit 0
    ;;
  build) ;;
  *) echo "Usage: scripts/dev.sh [build|check|inventory|idle [seconds]|clean]"; exit 1 ;;
esac

APP_NAME="Goldfish"
APP_BUNDLE="$REPO_ROOT/build/$APP_NAME.app"
BIN_PATH="$REPO_ROOT/.build/release/$APP_NAME"
INFO_PLIST="$REPO_ROOT/sources/clipbored/resources/Info.plist"
ICON_FILE="$REPO_ROOT/sources/clipbored/resources/AppIcon.icns"
SIZE_LIMIT_BYTES=$((2 * 1024 * 1024))
SIZE_LIMIT_LABEL="2 MiB"

swift build -c release --product "$APP_NAME" \
  -Xswiftc -Osize \
  -Xswiftc -whole-module-optimization \
  -Xswiftc -gnone \
  -Xswiftc -Xfrontend \
  -Xswiftc -disable-reflection-metadata \
  -Xlinker -dead_strip \
  -Xlinker -no_function_starts \
  -Xlinker -no_compact_unwind
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$INFO_PLIST" "$APP_BUNDLE/Contents/Info.plist"
cp "$ICON_FILE" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
strip "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
codesign --deep --force --options runtime --sign - "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
touch "$APP_BUNDLE"

APP_SIZE=$(stat -f%z "$APP_BUNDLE/Contents/MacOS/$APP_NAME")
HUMAN_SIZE=$(du -h "$APP_BUNDLE/Contents/MacOS/$APP_NAME" | cut -f1)
APP_BUNDLE_SIZE=$(du -sh "$APP_BUNDLE" | cut -f1)
APP_BUNDLE_BYTES=$(du -sk "$APP_BUNDLE" | awk '{print $1*1024}')
echo "Built $APP_BUNDLE"
echo "Binary size: $HUMAN_SIZE ($APP_SIZE bytes)"
echo "Bundle size: $APP_BUNDLE_SIZE"
if [ "$APP_SIZE" -gt "$SIZE_LIMIT_BYTES" ]; then
  echo "FAIL: executable exceeds $SIZE_LIMIT_LABEL target ($APP_SIZE bytes)"
  exit 1
fi
if [ "$APP_BUNDLE_BYTES" -gt "$SIZE_LIMIT_BYTES" ]; then
  echo "FAIL: bundle exceeds $SIZE_LIMIT_LABEL target ($APP_BUNDLE_BYTES bytes)"
  exit 1
fi
