# ClipBored

ClipBored is a small native macOS clipboard manager. It captures local clipboard history and opens a keyboard-first side panel for search, sorting, copy, paste, pinning, and deletion. It runs as a dockless menu-bar utility by default, with an optional Dock icon mode.

The project is intentionally dependency-light: Swift Package Manager, AppKit, Carbon hotkeys, SQLite, and system frameworks only.

## Features

- Dockless menu-bar utility by default (`LSUIElement=true`), with a Settings toggle for normal Dock presence
- First-run setup assistant for the open shortcut, Keep History retention, menu-bar/Dock presence, launch-at-login, iCloud sync, and Accessibility permission
- Right-click menu-bar status menu with capture state, history count, settings, manual or timed pause/resume, and quit
- Global shortcuts:
  - `Shift + Command + V` or the configured open shortcut toggles the clipboard panel
  - `Command + ,` opens settings
  - `Command + F` focuses search; press it again while search is active to show filters
  - `Command + 1` through `Command + 9` paste the numbered visible card; add `Shift` to paste that card as plain text
  - `Return` pastes the selected clip; `Shift + Return` or `Command + Shift + V` pastes it as plain text
  - `Command + C` copies the selected clip or selected clips
  - `Command + E` edits the selected text or code clip
  - `Command + R` renames the selected clip
  - `Delete` removes selected clips, and `Command + Z` restores the last deleted batch
  - `Command + G` shows a filtered result back in the full clipboard history
  - `Command + O` opens the selected link, file, or media clip when possible
  - `Command + N` creates a new text clip
  - `Shift + Command + N` creates a new collection
  - `Shift + Command + C` toggles Stack capture mode for queued multi-paste workflows
  - `Command + Left` and `Command + Right` move between collections
  - `Command + Up` and `Command + Down` jump to the first or last visible clip
  - `Command + T` pauses or resumes clipboard capture
  - `Command + A` selects the visible shelf from a focused card; `Shift` + shelf navigation extends the selected range
  - `Space` or `Command + Y` previews the selected card when the focused search field is empty
- Clipboard history for text, URLs with local preview thumbnails when available, images, audio, video with movie thumbnails when available, RTF/HTML rich text, PDFs, and file references
- Keyboard-focusable compact rows and collection chips with type-to-search, Return-to-paste/select, Space-to-preview for text, built-in browser previews for links, Quick Look for files and media, remote copied-on device metadata, image rotation and text extraction quick actions, vertical wheel/trackpad panning, visible focus chrome, and VoiceOver action hints
- Shelf navigation keys for focused cards: Left/Right, Page Up/Page Down, Home, and End; add `Shift` to extend the selected range
- Shelf navigation keys for focused collection chips: Left/Right, Home, and End
- SQLite persistence with bounded history, time-based retention, pinned-item and Pinboard retention, and encrypted app-managed payloads
- Search with independent token matching, a Paste-style filter menu, structured filters such as `app:Safari`, `type:image,pdf`, `device:MacBook`, `pinboard:"Client Work","Read Later"`, `date:2026-06-30`, result jump-back to full history, optional local OCR for copied images, and on-demand OCR from image cards
- Sort modes for recent, most used, images, links, text, files, audio, and pinned items
- Custom named collections that behave as durable Pinboards, including empty color-coded collections, for organizing clips from the card Collect control, context menu, keyboard-focusable collection rail, direct text-clip creation, or by dragging cards onto collection chips; collection chips can be edited or deleted from their context menu
- Pinboard-level archive export from a collection chip for sharing one Pinboard, including empty Pinboards and color metadata
- Plain-text clip creation and editing with native macOS Writing Tools support when available
- Searchable custom titles for clips, so media, files, links, PDFs, audio, and text can be renamed without changing the copied payload
- Copy and paste actions with Accessibility permission fallback, including Command/Shift multi-select original-format or plain-text batching, Stack capture mode, Stack next-item actions, and Stack-as-text batch copy/paste
- Image thumbnail cache with byte and file-count pruning
- Portable local archive export/import for moving history, Pinboards, and app-managed image/audio/video/rich-text/PDF attachments between Macs; external file references stay path-based
- Optional iCloud archive sync for signed builds with an iCloud entitlement, using ClipBored's app-private ubiquity container and the same portable archive format
- Configurable left or right shelf side, Keep History retention, history length, cache limit, polling profile, ignored apps, content kinds, launch-at-login, Dock/menu-bar presence, screen-capture privacy, temporary capture pause, and clear-on-quit behavior, with card-level capture rules for ignoring a source app or content type
- Local-first storage, with optional sensitive-content exclusion for common secrets and iCloud sync disabled by default

## Requirements

- macOS 13 or newer
- Xcode command line tools with Swift 5.9 or newer

## Build

```bash
swift test
./scripts/build-macos-app.sh
open build/ClipBored.app
```

The build script packages `build/ClipBored.app`, strips the executable, applies an ad-hoc hardened-runtime signature, and enforces 2 MiB gates for both the executable and app bundle.

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

ClipBored does not use telemetry or background networking. Clipboard history is stored locally under Application Support unless iCloud Sync is explicitly enabled in a signed build with an iCloud entitlement. User-triggered link previews load the selected web page in an ephemeral built-in WebKit view.

Textual SQLite fields, image cache files, audio clips, video clips, rich text sidecars, and PDF attachments are encrypted with AES-GCM using a Keychain-held key when Keychain access is available. If Keychain access blocks or fails, ClipBored uses an owner-only app-local fallback key so capture does not stall. Full history clears remove the local fallback key when present and reset cached key state for future captures. Portable archive exports and iCloud sync archives are not encrypted by ClipBored, so treat them like sensitive backups. Temporary decrypted preview files may be created when thumbnailing, opening, or revealing encrypted media; stale previews are cleared on launch, cache/history clear, and quit. Use sensitive-content exclusion, ignored app settings, and the screen-sharing privacy toggle for high-risk sources or calls. See [docs/SECURITY.md](docs/SECURITY.md) for details and responsible disclosure.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). The current roadmap is in [docs/ROADMAP.md](docs/ROADMAP.md).

## License

GPL-2.0-only. See [LICENSE](LICENSE).
