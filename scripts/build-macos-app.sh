#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Goldfish"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_ROOT="$REPO_ROOT/build"
APP_BUNDLE="$OUTPUT_ROOT/${APP_NAME}.app"
BIN_NAME="$APP_NAME"
INFO_PLIST="$REPO_ROOT/sources/clipbored/resources/Info.plist"
ICON_FILE="$REPO_ROOT/sources/clipbored/resources/AppIcon.icns"
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
MINIMUM_SYSTEM_VERSION="$(plutil -extract LSMinimumSystemVersion raw -o - "$INFO_PLIST")"
read -r -a BUILD_ARCHITECTURES <<< "${ARCHITECTURES:-$(uname -m)}"
ARCH_ARGUMENTS=()
for architecture in "${BUILD_ARCHITECTURES[@]}"; do
  case "$architecture" in
    arm64|x86_64) ARCH_ARGUMENTS+=(--arch "$architecture") ;;
    *) echo "FAIL: unsupported architecture: $architecture"; exit 1 ;;
  esac
done
SIZE_LIMIT_BYTES=$((2 * 1024 * 1024 * ${#BUILD_ARCHITECTURES[@]}))
SIZE_LIMIT_LABEL="$((2 * ${#BUILD_ARCHITECTURES[@]})) MiB"
BUNDLE_SIZE_LIMIT_BYTES=$((SIZE_LIMIT_BYTES + 1024 * 1024))
BUNDLE_SIZE_LIMIT_LABEL="$((2 * ${#BUILD_ARCHITECTURES[@]} + 1)) MiB"

cd "$REPO_ROOT"

swift build -c release --product "$APP_NAME" \
  "${ARCH_ARGUMENTS[@]}" \
  -Xswiftc -Osize \
  -Xswiftc -whole-module-optimization \
  -Xswiftc -gnone \
  -Xswiftc -Xfrontend \
  -Xswiftc -disable-reflection-metadata \
  -Xlinker -dead_strip \
  -Xlinker -platform_version -Xlinker macos \
  -Xlinker "$MINIMUM_SYSTEM_VERSION" -Xlinker "$SDK_VERSION" \
  -Xlinker -no_function_starts \
  -Xlinker -no_compact_unwind
BIN_DIRECTORY="$(swift build -c release "${ARCH_ARGUMENTS[@]}" --show-bin-path)"
BIN_PATH="$BIN_DIRECTORY/$BIN_NAME"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$INFO_PLIST" "$APP_BUNDLE/Contents/Info.plist"
if [[ -n "${APP_BUNDLE_IDENTIFIER:-}" ]]; then
  plutil -replace CFBundleIdentifier -string "$APP_BUNDLE_IDENTIFIER" "$APP_BUNDLE/Contents/Info.plist"
fi
cp "$ICON_FILE" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
# Xcode 26+ compiles the layered Mac icon and its appearance renditions. Keep
# the full-resolution .icns fallback for older SDKs and macOS releases.
if [[ "${SDK_VERSION%%.*}" -ge 26 ]]; then
  ICON_BUILD_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/goldfish-icons.XXXXXX")"
  trap 'rm -rf "$ICON_BUILD_DIRECTORY"' EXIT
  xcrun actool "$REPO_ROOT/sources/clipbored/resources/AppIcon.icon" \
    --compile "$ICON_BUILD_DIRECTORY" --app-icon AppIcon --platform macosx \
    --minimum-deployment-target 13.0 --target-device mac --optimization space \
    --output-partial-info-plist "$ICON_BUILD_DIRECTORY/Icon.plist" \
    --output-format human-readable-text
  cp "$ICON_BUILD_DIRECTORY/Assets.car" "$APP_BUNDLE/Contents/Resources/Assets.car"
  plutil -insert CFBundleIconName -string AppIcon "$APP_BUNDLE/Contents/Info.plist"
fi
cp "$REPO_ROOT/LICENSE" "$APP_BUNDLE/Contents/Resources/LICENSE"
cp "$REPO_ROOT/docs/QUICK_START.md" "$APP_BUNDLE/Contents/Resources/Quick Start.md"
cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
strip "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
CODESIGN_ARGUMENTS=(--deep --force --options runtime --sign -)
if [[ -n "${ENTITLEMENTS_FILE:-}" ]]; then
  if [[ ! -f "$ENTITLEMENTS_FILE" ]]; then
    echo "FAIL: ENTITLEMENTS_FILE does not exist: $ENTITLEMENTS_FILE"
    exit 1
  fi
  CODESIGN_ARGUMENTS+=(--entitlements "$ENTITLEMENTS_FILE")
fi
codesign "${CODESIGN_ARGUMENTS[@]}" "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"
for architecture in "${BUILD_ARCHITECTURES[@]}"; do
  lipo "$APP_BUNDLE/Contents/MacOS/$APP_NAME" -verify_arch "$architecture"
done
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
if [ "$APP_BUNDLE_BYTES" -gt "$BUNDLE_SIZE_LIMIT_BYTES" ]; then
  echo "FAIL: bundle exceeds $BUNDLE_SIZE_LIMIT_LABEL target ($APP_BUNDLE_BYTES bytes)"
  exit 1
fi
