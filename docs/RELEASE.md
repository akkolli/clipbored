# Release Guide

This guide covers the local release build, optional Developer ID signing, and optional notarization flow.

## Local Validation

Run:

```bash
./scripts/check.sh
```

This runs the unit test suite, builds `build/ClipBored.app`, applies an ad-hoc hardened-runtime signature, enforces size gates, and verifies the app signature.

## Local Archive

Run:

```bash
./scripts/release-macos-app.sh
```

Without signing credentials, this creates:

```text
build/ClipBored.app
build/ClipBored.zip
```

The app remains ad-hoc signed and is suitable for local validation only.

## Developer ID Signing

Set a Developer ID Application identity:

```bash
export DEVELOPER_ID_APPLICATION="Developer ID Application: Example, Inc. (TEAMID)"
./scripts/release-macos-app.sh
```

The script rebuilds the app, re-signs it with hardened runtime and timestamping, verifies the signature, and writes `build/ClipBored.zip`.

## Notarization

Preferred: configure a notarytool keychain profile once:

```bash
xcrun notarytool store-credentials "clipbored-notary" \
  --apple-id "developer@example.com" \
  --team-id "TEAMID" \
  --password "app-specific-password"
```

Then run:

```bash
export DEVELOPER_ID_APPLICATION="Developer ID Application: Example, Inc. (TEAMID)"
export NOTARYTOOL_PROFILE="clipbored-notary"
./scripts/release-macos-app.sh
```

Alternative environment-only notarization:

```bash
export DEVELOPER_ID_APPLICATION="Developer ID Application: Example, Inc. (TEAMID)"
export APPLE_ID="developer@example.com"
export APPLE_TEAM_ID="TEAMID"
export APPLE_APP_SPECIFIC_PASSWORD="app-specific-password"
./scripts/release-macos-app.sh
```

When notarization succeeds, the script staples the ticket to `build/ClipBored.app`, validates the staple, and recreates `build/ClipBored.zip`.

## Final Manual Checks

Before publishing, run the checklist in [SMOKE_TEST.md](SMOKE_TEST.md), then confirm:

```bash
codesign --verify --deep --strict --verbose=2 build/ClipBored.app
xcrun stapler validate build/ClipBored.app
spctl --assess --type execute --verbose=4 build/ClipBored.app
```
