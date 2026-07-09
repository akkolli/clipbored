# Architecture

ClipBored is a single-process AppKit utility built with Swift Package Manager. UI, capture, persistence, preview generation, and paste orchestration stay in-process. Capture persistence, card-thumbnail loading, archive and sync operations, image rotation, and OCR use bounded background queues; their UI state and completion feedback return to the main thread.

## Runtime Shape

- `ClipBoredApp` creates `NSApplication`, installs `AppDelegate`, and starts the run loop.
- `AppDelegate` wires services, menu-bar commands, settings observers, and global shortcuts.
- `ClipboardMonitorService` watches `NSPasteboard.changeCount` on a utility queue with adaptive active/idle polling intervals selected by the Performance setting.
- `ClipboardStore` owns the in-memory item list and SQLite persistence on a serial queue.
- `ClipboardCacheService` stores bounded encrypted preview sidecars under Application Support and maintains a small in-memory cache.
- `ClipboardCloudSyncService` resolves the private iCloud ubiquity container and pushes or pulls portable archives only when sync is enabled.
- `ShortcutManager` registers only intentional system-wide Carbon hotkeys (open shelf and Stack capture). The Settings binding is handled by the shelf's local key monitor and is never registered globally.
- `ClipboardPanelController` owns shelf lifecycle, current-screen placement, left/right frame planning, target-app tracking, and show/hide/reflow animation.
- `ClipboardPanelViewModel` owns query parsing, indexed category unions, sorting, selection, copy/paste, pinning, Pinboards, Stack, deletion, opening, and asynchronous thumbnail request coalescing.
- `ClipboardPanelView` renders the toolbar, vertical category icon rail, and viewport-aware card list beside it.
- `LinkPreviewWindowController` opens user-selected HTTP(S) links in an ephemeral WebKit preview window.
- `OnboardingWindowController` handles first-run shortcut, retention, lifecycle, sync, and Accessibility choices.
- `SettingsWindowController` presents six resizable, vertically scrollable settings pages and routes common settings changes through targeted control refreshes.

## Capture And Presentation Flow

1. The monitor notices a pasteboard change.
2. Capture rules check paused state, ignored source apps, allowed content kinds, and optional sensitive-text exclusion.
3. Pasteboard content is normalized into a `ClipboardItem`; local Vision OCR runs when image-label search is enabled.
4. The store deduplicates, preserves pinned and Pinboard-assigned items, enforces retention/length limits, and persists the mutation.
5. The panel view model maintains category/Pinboard indexes, applies the text query and selected category union, and caches parsed search matches across counts and category changes.
6. The view lays out card slots beside the category rail in one vertical document and materializes cards near the visible viewport.
7. Cards render immediately with a fallback presentation. Preview thumbnails load on a bounded operation queue; identical in-flight requests share work, and a still-relevant card is replaced in place on the main thread when its image arrives.

## Shelf Interaction Model

The shelf uses a fixed vertical layout on the configured left or right edge of the active screen.

- Header row one contains the collapsed/expanded search control plus clear-history and settings actions.
- Header row two is a labeled, horizontally scrollable category rail. Built-in categories without clips are omitted unless currently selected; custom Pinboards remain available when empty.
- A normal chip click replaces the active category filter. Command-click adds or removes chips from a union. Hover changes chrome only and never changes filtering.
- An empty, unfocused search field collapses to an icon. Click, typing, or `Command + F` expands and focuses it; clicking elsewhere collapses it only when the query is empty. Repeated `Command + F` keeps focus in the same field.
- Cards scroll vertically and fill the usable shelf width. Hover expansion changes visual presentation only: it does not mutate keyboard selection, the selected range, or query/category state.
- Card commands are discoverable through context menus, VoiceOver descriptions, and keyboard shortcuts. Hover-only action controls are not part of the interaction contract.
- Category changes and card/search expansion use short AppKit/Core Animation transitions. Both panel-controller and panel-view durations resolve to zero when macOS Reduce Motion is enabled.

The panel has no user-facing resize lip, alternate density/layout mode, close button, new-text action, or persistent status bar. It is dismissed with `Esc` or the configured global shortcut.

## Settings UI

Settings uses a custom segmented selector backed by a borderless `NSTabView`:

- `General` - history, sorting, shelf side, launch, and menu-bar/Dock presence
- `Shortcuts` - a system-wide open-shelf binding and a pane-local open-settings binding
- `Capture` - pause state, content kinds, image-label search, likely-secret exclusion, ignored apps, and capture status
- `Privacy` - local-data behavior, screen-capture hiding, Accessibility permission, and paste status
- `Performance` - adaptive polling profile and thumbnail-cache cap
- `Data` - iCloud archive sync, local archive import/export, storage location, and destructive clears

Each tab is a top-aligned document inside its own vertical scroll view. The window has a practical minimum size, no horizontal scrollers, and commits focused text/shortcut drafts when it closes. Common narrow settings changes update their bound controls without rebuilding the whole window; expensive cloud status checks are cached across unrelated refreshes.

## Persistence And Privacy Boundaries

History is stored in:

```text
~/Library/Application Support/ClipBored/history.sqlite
```

Image previews are stored under `images/`; restorable audio, video, rich-text, and PDF payloads are stored under `attachments/`. Legacy JSON import remains for migration from early builds.

Portable `.clipboredarchive` files preserve item metadata, Pinboards, and decrypted bytes for app-managed sidecars so another Mac can re-cache them with its own storage paths and encryption key. External file references remain path-based. Optional iCloud sync uses the same unencrypted archive format inside the app-private ubiquity container and is disabled by default.

Textual SQLite fields are encrypted and decrypted at the `ClipboardStore` boundary. Managed cache and attachment files are encrypted and decrypted at the `ClipboardCacheService` boundary. The key lives in Keychain when available, with an owner-only local fallback if Keychain access fails. Runtime `ClipboardItem` values remain plaintext in memory for search and clipboard operations. Opening encrypted media may create a temporary decrypted file; stale previews are cleared on launch, cache/history clear, and quit. Link previews are user-triggered and use a non-persistent WebKit data store.

## Size And Power Constraints

The release build intentionally avoids SwiftUI, Combine, Swift Concurrency, third-party packages, and bundled media. The shelf avoids continuous layout work, renders only cards near the viewport, coalesces preview requests, keeps card-thumbnail decoding off the main thread, and bounds both memory and disk caches. Clipboard monitoring uses change-count polling with selectable adaptive profiles rather than continuous file scans.

The build script uses `-Osize`, whole-module optimization, disabled reflection metadata, linker dead stripping, symbol stripping, and hardened-runtime signing. `scripts/build-macos-app.sh` enforces 2 MiB gates for both the executable and app bundle.
