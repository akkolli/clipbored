#!/usr/bin/env bash
set -euo pipefail

APP_NAME="ClipBored"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_ROOT="$REPO_ROOT/build"
APP_BUNDLE="$OUTPUT_ROOT/${APP_NAME}.app"
BIN_NAME="$APP_NAME"
BIN_PATH="$REPO_ROOT/.build/release/$BIN_NAME"
INFO_PLIST="$REPO_ROOT/sources/clipbored/resources/Info.plist"
ICON_FILE="$REPO_ROOT/sources/clipbored/resources/AppIcon.icns"
SIZE_LIMIT_BYTES=$((2 * 1024 * 1024))
SIZE_LIMIT_LABEL="2 MiB"

cd "$REPO_ROOT"

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
codesign --deep --force --options runtime --sign - "$APP_BUNDLE" >/dev/null 2>&1 || true
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
