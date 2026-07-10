# ClipBored

ClipBored is a native macOS clipboard manager with a keyboard-first side shelf. It captures local clipboard history and makes clips easy to find, preview, organize, copy, paste, pin, and delete. It runs as a dockless menu-bar utility by default, with an optional Dock icon.

The project is intentionally dependency-light: Swift Package Manager, AppKit, Carbon hotkeys, SQLite, and system frameworks only.

## Features

- A compact toolbar with an expanding search control, clear-history and settings actions, plus a vertically scrollable category icon rail beside the cards
- Category filtering without a separate filter panel: click a chip to select it, or Command-click chips to show their union; unused empty built-in categories stay hidden while named Pinboards remain available even when empty
- A vertically scrolling list of cards with full-color kind or Pinboard headers that fills the space beside the category rail. Hover expands a card's preview without changing keyboard selection or filtering; commands live in card context menus and keyboard shortcuts
- Search that collapses to a magnifying-glass button when it is empty and unfocused, expands on click, typing, or `Command + F`, and stays expanded while a query is active
- Fast, short panel, search, category, and card transitions that honor the macOS Reduce Motion accessibility setting
- First-run setup for the open shortcut, Keep History retention, menu-bar/Dock presence, launch at login, iCloud sync, and Accessibility permission
- A menu-bar status menu with capture state, history count, settings, manual or timed pause/resume, and quit
- Global and panel shortcuts:
  - The configured open shortcut toggles the clipboard shelf
  - `Command + ,` opens settings
  - `Command + F` focuses search
  - `Command + 1` through `Command + 9` pastes the numbered visible card; add `Shift` to use plain text
  - `Return` pastes the selected clip; `Shift + Return` or `Command + Shift + V` uses plain text
  - `Command + C` copies the selected clip or selected clips
  - `Command + E` edits the selected text or code clip, and `Command + R` renames it
  - `Delete` removes selected clips, and `Command + Z` restores the last deleted batch
  - `Command + G` shows a filtered result in the full clipboard history
  - `Command + O` opens the selected link, file, or media clip when possible
  - `Shift + Command + N` creates a Pinboard collection
  - `Shift + Command + C` toggles Stack capture for queued multi-paste workflows
  - `Command + Left` and `Command + Right` move between collections
  - `Command + Up` and `Command + Down` jump to the first or last visible clip
  - `Command + T` pauses or resumes clipboard capture
  - `Command + A` selects the visible list from a focused card; Shift-modified navigation extends a range
  - `Space` or `Command + Y` previews the selected card when the focused search field is empty
- Keyboard-focusable cards and category chips with type-to-search, visible focus chrome, VoiceOver descriptions, context menus, Up/Down card navigation, and direct category navigation
- Clipboard history for text, code, colors, URLs, images, audio, video, RTF/HTML rich text, PDFs, and file references
- Immediate cards with previews loaded asynchronously. Image, link, document, and movie thumbnails fill in without blocking search, selection, or scrolling
- Built-in browser previews for links, Quick Look for files and media, image rotation, and local text extraction for images
- Independent-token and structured search, including `app:Safari`, `type:image,pdf`, `device:MacBook`, `pinboard:"Client Work","Read Later"`, and `date:2026-06-30`
- Custom color-coded Pinboards, including empty Pinboards, with drag-and-drop collection assignment, context-menu editing and export, and durable retention
- Searchable custom clip titles that do not alter the copied payload
- Multi-selection, original-format or plain-text batch copy/paste, Stack capture, next-item Stack actions, and Stack-as-text workflows
- SQLite persistence with bounded history, time-based retention, pinned-item and Pinboard retention, and encrypted app-managed payloads
- A bounded thumbnail cache with asynchronous loading and byte/file-count pruning
- Portable local archive export/import for history, Pinboards, and managed attachments; external file references stay path-based
- Optional iCloud archive sync for signed builds with an iCloud entitlement
- A redesigned, resizable Settings window with top-level `General`, `Shortcuts`, `Capture`, `Privacy`, `Performance`, and `Data` tabs. Each page is vertically scrollable and keeps controls aligned at narrow window sizes
- Settings for shelf side, retention, history length, default sort, cache limit, adaptive polling profile, ignored apps, content kinds, shortcuts, launch at login, Dock/menu-bar presence, screen-capture privacy, capture pause, and clear-on-quit behavior
- Local-first storage, with optional sensitive-content exclusion and iCloud sync disabled by default

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

For app-level behavior that cannot be fully covered by unit tests, run [docs/SMOKE_TEST.md](docs/SMOKE_TEST.md). For distribution builds, see [docs/RELEASE.md](docs/RELEASE.md).

Project layout:

- `sources/clipbored/app` - app entry point and service wiring
- `sources/clipbored/config` - defaults and power/size guardrails
- `sources/clipbored/extensions` - small AppKit/Foundation helpers
- `sources/clipbored/models` - clipboard item and settings models
- `sources/clipbored/resources` - app bundle metadata and icon assets
- `sources/clipbored/services` - capture, persistence, cache, shortcuts, paste, diagnostics, and privacy filters
- `sources/clipbored/views` - panel, onboarding, preview, and settings UI
- `tests/clipboredtests` - focused behavior tests for capture, persistence, search, paste, and settings decisions
- `docs` - architecture, security, release, smoke-test, and roadmap notes

## Privacy And Security

ClipBored does not use telemetry or background networking. Clipboard history is stored locally under Application Support unless iCloud Sync is explicitly enabled in a signed build with an iCloud entitlement. User-triggered link previews load the selected web page in an ephemeral built-in WebKit view.

Textual SQLite fields, image cache files, audio clips, video clips, rich text sidecars, and PDF attachments are encrypted with AES-GCM using a Keychain-held key when Keychain access is available. If Keychain access blocks or fails, ClipBored uses an owner-only app-local fallback key so capture does not stall. Portable archive exports and iCloud sync archives are not encrypted by ClipBored, so treat them as sensitive backups. Temporary decrypted preview files are cleared on launch, cache/history clear, and quit. See [docs/SECURITY.md](docs/SECURITY.md) for details and responsible disclosure.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). The current roadmap is in [docs/ROADMAP.md](docs/ROADMAP.md).

## License

GPL-2.0-only. See [LICENSE](LICENSE).
