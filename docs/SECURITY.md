# Security Notes

ClipBored is designed as a local macOS utility. Its primary privacy promise is that clipboard data stays on the machine.

## Current Protections

- No networking or telemetry in production source.
- No shell/process execution.
- No Apple Events scripting.
- Hardened runtime is applied by the local build script, and the release script supports Developer ID signing plus notarization when credentials are configured.
- Clipboard persistence uses prepared SQLite statements and bound values.
- Textual SQLite fields, including optional local image OCR text, are encrypted with AES-GCM using a Keychain-held key when Keychain access is available.
- App-managed image cache files, audio clips, rich text sidecars, and PDF attachments are encrypted with the same encryption service.
- If Keychain access blocks or fails, ClipBored uses an owner-only app-local fallback key so clipboard capture and persistence continue without a Keychain UI stall.
- Full history clears remove the app-local fallback key when present and reset cached key state after the database clear succeeds.
- App-owned storage directories are restricted to the current user, and saved history/cache files are written with owner-only permissions where the filesystem supports POSIX modes.
- ClipBored marks its own pasteboard writes so copy/paste actions from history are not re-captured as new clipboard events.
- Sensitive-content exclusion can skip common high-risk values:
  - private key blocks
  - bearer tokens
  - GitHub tokens
  - Slack tokens
  - AWS access key IDs
  - Stripe keys
  - OpenAI-style API keys
  - Google API keys
  - JSON Web Tokens
  - Luhn-valid credit-card-like values
  - OTP-like values from known authenticator/password-manager sources
  - long high-entropy token-like strings
  - obvious password/secret keywords and common secret assignment forms
- Default ignored apps include common password managers and authenticators.

## Known Limitations

- SQLite item metadata such as identifiers, kinds, timestamps, pin state, and use counts is not encrypted.
- The app-local fallback key prevents plaintext app-managed history/media files, but it does not protect against a process or user account that can read the full ClipBored Application Support directory before history is cleared.
- Opening or revealing encrypted images, audio clips, or PDFs creates temporary decrypted preview files so macOS can hand them to other apps. ClipBored clears stale preview files on launch, cache/history clear, and quit.
- Existing plaintext SQLite rows and legacy sidecar files are migrated when encryption becomes available, but system snapshots, backups, live temporary previews, or filesystem remnants may retain older plaintext copies.
- The local development build is ad-hoc signed; use `scripts/release-macos-app.sh` with Developer ID credentials for notarized distribution builds.
- Accessibility permission is required for automatic paste simulation.
- Sensitive-content detection is heuristic and can miss novel formats or produce false positives.
- Local image OCR is opt-in through `Search in image labels`; recognized text stays local but can still contain sensitive clipboard-derived content.
- Local filesystem access by another process or user account with sufficient permissions can expose metadata, fallback keys, and live temporary decrypted previews.

## Release Hardening Checklist

- Run `swift test -q`.
- Run `./scripts/build-macos-app.sh` or `./scripts/release-macos-app.sh`.
- Verify `codesign --verify --deep --strict --verbose=2 build/ClipBored.app`.
- Verify hardened runtime appears in `codesign -d --verbose=4 build/ClipBored.app`.
- For distribution, verify `xcrun stapler validate build/ClipBored.app` and `spctl --assess --type execute --verbose=4 build/ClipBored.app`.
- Confirm no new `URLSession`, process execution, Apple Events, telemetry, or remote sync APIs were introduced.
- Review any new persistence paths for unencrypted sensitive data.
