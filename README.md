# Archived refactoring experiment

This branch preserves reductions made against the older ClipBored code. Current Goldfish development and installation use `main`; do not ship this branch.

# Goldfish

A native macOS clipboard manager with a keyboard-first side shelf. Captures text, code, colors, links, images, audio, video, rich text, PDFs, and file references. Requires macOS 13+ and Swift 5.9+; uses system frameworks and SQLite without package dependencies.

## Build and run

```sh
./scripts/dev.sh check
open build/Goldfish.app
```

The check runs tests, builds and signs the app, verifies its signature, and checks source and bundle size. `swift test --filter <suite>` runs a focused suite. Packaging, notarization, manual checks, and power measurement are in [Validation](docs/MAINTENANCE.md).

## Using the shelf

The configured global shortcut toggles the shelf; clicking the menu-bar icon opens it on that icon's display. The shelf follows the pointer's display otherwise. Select its left or right side in Settings. Right-click or Control-click the menu-bar icon for status, timed/manual capture pause, setup, and quit.

Click a category to filter; Command-click categories to show their union. Empty built-in categories hide automatically; empty Pinboards remain available. Create a Pinboard with the plus button, choose its color, and assign clips through Collect or drag-and-drop. Pinboard menus edit, export, or delete them. Pins and assigned Pinboards survive ordinary pruning.

Hover expands a preview without changing selection. Command-click clips for a batch or Shift-click a range. Context menus expose applicable copy/paste, edit, rename, open/reveal, Quick Look or web preview, pin/collect, Stack, rotate/OCR, capture rules, and delete commands. Dragging file clips retains every file reference. Renaming affects searchable metadata, not the copied payload. Writing Tools appear on supported systems.

Search expands on click, typing, or Command-F and collapses when empty and unfocused. Independent tokens match case-insensitively, including diacritics. Combine them with `app:Safari`, `type:image,pdf`, `device:MacBook`, `pinboard:"Client Work","Read Later"`, `date:2026-06-30`, before/after dates, or pin state. Quoted structured values match exactly. Local image OCR is opt-in and can also be requested explicitly.

Stack queues clips for repeated paste. Add selected or visible clips, or enable Stack capture to queue new captures in copy order. Its menu supports next-item copy/paste, the queue as plain text, and clearing the queue.

| Shortcut | Action |
| --- | --- |
| Configured open shortcut | Toggle shelf |
| Command-, / Command-F | Settings / search |
| Return / Shift-Return or Command-Shift-V | Paste / paste plain text |
| Command-1…9; add Shift | Paste numbered clip / plain text |
| Command-C / Command-E / Command-R | Copy selection / edit text or code / rename |
| Delete / Command-Z | Delete selection / undo last deleted batch |
| Command-A / Shift-navigation | Select visible clips / extend range |
| Up/Down, Home/End, Page Up/Down | Navigate clips |
| Command-Up/Down | First/last clip |
| Command-Left/Right | Previous/next collection |
| Command-G / Command-O | Show in full history / open |
| Space or Command-Y | Preview; Space requires empty search |
| Command-Shift-N / Command-Shift-C | New Pinboard / Stack capture |
| Command-T / Escape | Pause capture / clear search, then close |

Tab moves through controls, categories, and clips. Category navigation, context menus, VoiceOver labels, and Reduce Motion are supported. Automatic paste requires Accessibility permission; without it, the clip is copied for manual paste.

Settings has six tabs: General (retention, length, sorting, shelf side, login, menu-bar/Dock); Shortcuts; Capture (pause, types, ignored apps, sensitive exclusion, OCR); Privacy (clear on quit, screen sharing, Accessibility, paste status); Performance (adaptive polling and thumbnail cap); Data (archives, iCloud, storage, clears). Editors commit when Settings closes. First-run setup covers the main choices.

## Storage and maintenance

History keeps its existing `~/Library/Application Support/ClipBored` location: SQLite metadata/text, original images and thumbnails in `images/`, managed media in `attachments/`. Legacy JSON migrates automatically. Text and managed media use AES-GCM with a Keychain key or owner-only fallback key; metadata and live previews have different protection boundaries. [Security](SECURITY.md) explains them.

Local archives include history, Pinboards, and managed attachments; external files remain path references. Archives are unencrypted. Optional iCloud uses the same format, requires a signed ubiquity entitlement, and is off by default. Explicit link previews load the selected page in ephemeral WebKit. There is no telemetry.

For changes, start with the [code map](docs/MAINTENANCE.md). Licensed GPL-2.0-only; retain [LICENSE](LICENSE).
