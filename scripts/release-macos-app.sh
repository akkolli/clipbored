#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_NAME="Goldfish"
APP_BUNDLE="$REPO_ROOT/build/${APP_NAME}.app"
ZIP_PATH="$REPO_ROOT/build/${APP_NAME}.zip"
REQUIRE_NOTARIZATION=false

usage() {
  cat <<'USAGE'
Usage: scripts/release-macos-app.sh [--require-notarization]

Builds build/Goldfish.app, optionally re-signs it with a Developer ID
Application certificate, optionally notarizes it, staples the ticket, and
creates build/Goldfish.zip.

--require-notarization fails before building if distribution credentials are
missing, and validates Gatekeeper before reporting a public release is ready.
Without credentials the archive is named Goldfish-local-preview.zip.

Optional environment:
  DEVELOPER_ID_APPLICATION        codesign identity, e.g. "Developer ID Application: Example, Inc. (TEAMID)"
  APP_BUNDLE_IDENTIFIER           release bundle identifier to write into Info.plist
  ENTITLEMENTS_FILE               optional entitlements plist used for both signing passes
  ARCHITECTURES                  defaults to "arm64 x86_64" (universal)
  NOTARYTOOL_PROFILE             preferred notarytool keychain profile

Alternative notarization credentials when NOTARYTOOL_PROFILE is not set:
  APPLE_ID                       Apple ID email
  APPLE_TEAM_ID                  Apple Developer Team ID
  APPLE_APP_SPECIFIC_PASSWORD    app-specific password

Without DEVELOPER_ID_APPLICATION, this script performs a local ad-hoc signed
release build and zip only. Notarization is skipped.
USAGE
}

create_zip_archive() {
  rm -f "$ZIP_PATH"
  (
    cd "$REPO_ROOT/build"
    /usr/bin/zip -qry --symlinks "$ZIP_PATH" "${APP_NAME}.app"
  )
  local archive_list
  archive_list="$(/usr/bin/unzip -l "$ZIP_PATH")"
  if [[ "$archive_list" == *"__MACOSX"* || "$archive_list" == *"/._"* ]]; then
    echo "FAIL: release archive contains macOS metadata sidecar files."
    exit 1
  fi
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi
if [[ "${1:-}" == "--require-notarization" ]]; then
  REQUIRE_NOTARIZATION=true
elif [[ -n "${1:-}" ]]; then
  usage
  exit 1
fi

HAS_NOTARY_CREDENTIALS=false
if [[ -n "${NOTARYTOOL_PROFILE:-}" ]] ||
   [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
  HAS_NOTARY_CREDENTIALS=true
fi
if [[ "$REQUIRE_NOTARIZATION" == true ]] &&
   { [[ -z "${DEVELOPER_ID_APPLICATION:-}" ]] || [[ "$HAS_NOTARY_CREDENTIALS" != true ]]; }; then
  echo "FAIL: public distribution requires Developer ID Application signing and notarization credentials."
  exit 1
fi
if [[ -n "${DEVELOPER_ID_APPLICATION:-}" && "$DEVELOPER_ID_APPLICATION" != "Developer ID Application:"* ]]; then
  echo "FAIL: use a Developer ID Application identity, not an Apple Development or App Store certificate."
  exit 1
fi
if [[ -z "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  ZIP_PATH="$REPO_ROOT/build/${APP_NAME}-local-preview.zip"
elif [[ "$HAS_NOTARY_CREDENTIALS" != true ]]; then
  ZIP_PATH="$REPO_ROOT/build/${APP_NAME}-signed-unnotarized.zip"
fi

export ARCHITECTURES="${ARCHITECTURES:-arm64 x86_64}"

cd "$REPO_ROOT"

"$SCRIPT_DIR/build-macos-app.sh"

if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  echo "Signing with Developer ID identity: $DEVELOPER_ID_APPLICATION"
  CODESIGN_ARGUMENTS=(
    --deep
    --force
    --options runtime
    --timestamp
    --sign "$DEVELOPER_ID_APPLICATION"
  )
  if [[ -n "${ENTITLEMENTS_FILE:-}" ]]; then
    if [[ ! -f "$ENTITLEMENTS_FILE" ]]; then
      echo "FAIL: ENTITLEMENTS_FILE does not exist: $ENTITLEMENTS_FILE"
      exit 1
    fi
    CODESIGN_ARGUMENTS+=(--entitlements "$ENTITLEMENTS_FILE")
  fi
  codesign "${CODESIGN_ARGUMENTS[@]}" "$APP_BUNDLE"
else
  echo "DEVELOPER_ID_APPLICATION is not set; keeping local ad-hoc signature."
fi

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
SIGNATURE_DETAILS="$(codesign -d --verbose=4 "$APP_BUNDLE" 2>&1)"
if [[ "$SIGNATURE_DETAILS" != *"runtime"* ]]; then
  echo "FAIL: hardened runtime was not found in the code signature."
  exit 1
fi

create_zip_archive
echo "Created $ZIP_PATH"

if [[ -z "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  echo "Skipping notarization because Developer ID signing is not configured."
  echo "LOCAL PREVIEW ONLY: this archive is not ready for normal Gatekeeper-protected distribution."
  exit 0
fi

if [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
  echo "Submitting notarization with keychain profile: $NOTARYTOOL_PROFILE"
  xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARYTOOL_PROFILE" --wait
elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
  echo "Submitting notarization with Apple ID credentials for team: $APPLE_TEAM_ID"
  xcrun notarytool submit "$ZIP_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --wait
else
  echo "Notarization credentials are not configured; signed zip is ready but not notarized."
  exit 0
fi

xcrun stapler staple "$APP_BUNDLE"
xcrun stapler validate "$APP_BUNDLE"
spctl --assess --type execute --verbose=4 "$APP_BUNDLE"

create_zip_archive
echo "Created notarized release archive: $ZIP_PATH"
