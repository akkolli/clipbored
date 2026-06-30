# ClipBored

ClipBored is a small native macOS clipboard manager. It captures local clipboard history and opens a keyboard-first bottom panel for search, sorting, copy, paste, pinning, and deletion. It runs as a dockless menu-bar utility by default, with an optional Dock icon mode.

The project is intentionally dependency-light: Swift Package Manager, AppKit, Carbon hotkeys, SQLite, and system frameworks only.

## Features

- Dockless menu-bar utility by default (`LSUIElement=true`), with a Settings toggle for normal Dock presence
- Right-click menu-bar status menu with capture state, history count, settings, pause/resume, and quit
- Global shortcuts:
  - `Command + Option + V` toggles the clipboard panel
  - `Command + ,` opens settings
  - `Command + 1` through `Command + 9` paste the numbered visible card; add `Shift` to paste that card as plain text
- Clipboard history for text, URLs with local preview thumbnails when available, images, audio, RTF/HTML rich text, PDFs, and file references
- SQLite persistence with bounded history, pinned-item retention, and encrypted app-managed payloads
- Search with independent token matching, structured filters such as `app:Safari`, `type:image`, `date:2026-06-30`, and optional local OCR for copied images
- Sort modes for recent, most used, images, links, text, files, audio, and pinned items
- Custom named collections for organizing clips from the card context menu or by dragging cards onto collection chips
- Copy and paste actions with Accessibility permission fallback
- Image thumbnail cache with byte and file-count pruning
- Configurable history length, cache limit, polling profile, ignored apps, content kinds, launch-at-login, Dock/menu-bar presence, and clear-on-quit behavior, with card-level capture rules for ignoring a source app or content type
- Local-only storage, with optional sensitive-content exclusion for common secrets

## Requirements

- macOS 13 or newer
- Xcode command line tools with Swift 5.9 or newer

## Build

```bash
swift test
./scripts/build-macos-app.sh
open build/ClipBored.app
```

The build script packages `build/ClipBored.app`, strips the executable, applies an ad-hoc hardened-runtime signature, and enforces a 1 MiB executable gate plus a 1.8 MB bundle gate.

## Development

Run the full local validation:

```bash
./scripts/check.sh
```

Useful commands:

```bash
swift test -q
./scripts/build-macos-app.sh
./scripts/release-macos-app.sh
./scripts/idle-soak-report.sh 900
```

For app-level behavior that cannot be fully covered by unit tests, run the manual checklist in [docs/SMOKE_TEST.md](docs/SMOKE_TEST.md).
For distribution builds, see [docs/RELEASE.md](docs/RELEASE.md).

Project layout:

- `sources/clipbored/app` - app entry point and service wiring
- `sources/clipbored/config` - defaults and power/size guardrails
- `sources/clipbored/extensions` - small AppKit/Foundation helpers
- `sources/clipbored/models` - clipboard item and settings models
- `sources/clipbored/resources` - app bundle metadata and icon assets
- `sources/clipbored/services` - clipboard capture, persistence, cache, shortcuts, paste, diagnostics, privacy filters
- `sources/clipbored/views` - panel and settings UI
- `tests/clipboredtests` - unit tests for persistence, filtering, shortcuts, pasteboard writes, diagnostics, and sensitive-content detection
- `docs` - architecture, security notes, and roadmap

## Privacy And Security

ClipBored does not use network APIs or telemetry. Clipboard history is stored locally under Application Support.

Textual SQLite fields, image cache files, audio clips, rich text sidecars, and PDF attachments are encrypted with AES-GCM using a Keychain-held key when Keychain access is available. If Keychain access blocks or fails, ClipBored uses an owner-only app-local fallback key so capture does not stall. Full history clears remove the local fallback key when present and reset cached key state for future captures. Temporary decrypted preview files may be created when opening or revealing encrypted media; stale previews are cleared on launch, cache/history clear, and quit. Use sensitive-content exclusion and ignored app settings for high-risk sources. See [docs/SECURITY.md](docs/SECURITY.md) for details and responsible disclosure.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). The current roadmap is in [docs/ROADMAP.md](docs/ROADMAP.md).

## License

GPL-2.0-only. See [LICENSE](LICENSE).
