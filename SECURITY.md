# Security Policy

## Supported Versions

The main branch is the supported development line until tagged releases exist.

## Reporting A Vulnerability

Please do not open a public issue with exploit details or sensitive clipboard examples.

Report privately by contacting the maintainer listed in the repository profile. Include:

- affected version or commit
- macOS version
- reproduction steps
- expected and actual behavior
- whether clipboard payloads, files, permissions, or persistence are involved

## Current Security Model

ClipBored is local-only:

- no network APIs
- no telemetry
- no remote sync
- no shell/process execution
- no Apple Events scripting

The app stores history, image cache files, rich text sidecars, audio clips, and PDF attachments in the user's Application Support directory under the same app-owned area. Textual SQLite fields, optional local image OCR text, and app-managed image/rich text/audio/PDF sidecars are encrypted with a Keychain-held key when Keychain access is available, with an owner-only app-local fallback key if Keychain access blocks or fails. Full history clears remove the local fallback key when present and reset cached key state for future captures. SQLite metadata and short-lived temporary decrypted previews remain local files with owner-only filesystem permissions applied where supported. Users should enable sensitive-content exclusion and ignore high-risk source apps where appropriate.

See `docs/SECURITY.md` for design details and known limitations.
