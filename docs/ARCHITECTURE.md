# Architecture

ClipBored is a single-process AppKit utility built with Swift Package Manager.

## Runtime Shape

- `ClipBoredApp` creates `NSApplication`, sets accessory activation, installs `AppDelegate`, and starts the run loop.
- `AppDelegate` wires shared services, status menu items, settings observers, and global shortcuts.
- `ClipboardMonitorService` polls `NSPasteboard.changeCount` on a utility queue with adaptive active/idle intervals.
- `ClipboardStore` keeps the in-memory item list and persists rows to SQLite on a serial queue.
- `ClipboardCacheService` stores bounded image previews under Application Support and keeps a small `NSCache`.
- `ClipboardCloudSyncService` resolves the app-private iCloud ubiquity container when sync is enabled and pushes or pulls the portable archive file.
- `ShortcutManager` registers Carbon hotkeys for app-wide commands.
- `ClipboardPanelController` owns the side panel lifecycle, Dock-aware frame planning, configured left/right placement, and target-app tracking.
- `ClipboardPanelViewModel` filters, sorts, selects, copies, pastes, pins, organizes, deletes, opens, and reveals items.
- `LinkPreviewWindowController` opens selected HTTP(S) links in an ephemeral WebKit preview window instead of handing them to another browser.
- `OnboardingWindowController` shows the first-run setup assistant for shortcut, retention, system entry points, launch-at-login, iCloud sync, and Accessibility permission choices.
- `SettingsWindowController` exposes native controls for capture, privacy, performance, shortcuts, and data management.

## Data Flow

1. The monitor notices a pasteboard change.
2. Source app metadata is checked against ignored apps.
3. Pasteboard content is normalized into a `ClipboardItem`.
4. Sensitive text is skipped when exclusion is enabled.
5. Copied images run local Vision OCR only when `Search in image labels` is enabled; image cards can also run the same local OCR on demand from their quick actions.
6. The store deduplicates, preserves pinned and collection-assigned items, enforces limits, and persists the mutation.
7. The panel view model receives store updates and recomputes the visible list.

## Persistence

History is stored in SQLite at:

```text
~/Library/Application Support/ClipBored/history.sqlite
```

Images are stored under:

```text
~/Library/Application Support/ClipBored/images/
```

Restorable non-image payloads such as audio clips, rich text, and PDFs are stored under:

```text
~/Library/Application Support/ClipBored/attachments/
```

Legacy JSON import still exists for migration from early builds.

Portable `.clipboredarchive` files are JSON exports created by `ClipboardArchiveService`. They preserve item metadata and include decrypted bytes for app-managed image, URL-thumbnail, audio, video, rich-text, and PDF sidecars so a different Mac can re-cache them under its own storage directory and encryption key. External file references remain path-based and are not copied into the archive.

Optional iCloud Sync uses that same archive format at `Documents/ClipBored/ClipBored.clipboredarchive` inside the app-private ubiquity container. It is disabled by default, requires a signed build with iCloud entitlement access, pulls once when enabled at launch, and debounces pushes after local store changes. Shared Pinboard collaboration is not implemented.

Textual SQLite fields, including optional collection names and image OCR text, are encrypted and decrypted at the `ClipboardStore` boundary. App-managed image cache files, URL preview thumbnails, audio clips, rich text sidecars, and PDF attachments are encrypted and decrypted at the `ClipboardCacheService` boundary. The encryption key is stored in Keychain when available, with an owner-only app-local fallback key if Keychain access blocks or fails. Full history clears remove the local fallback key when present and reset cached key state after SQLite deletion succeeds. Runtime `ClipboardItem` values remain plaintext in memory so search, duplicate detection, copy, paste, organization, archive export/import, and cache cleanup operate normally. Opening or revealing encrypted media creates a temporary decrypted copy for macOS handoff; stale temporary previews are cleared on launch, cache/history clear, and quit. Link previews are user-triggered and use a non-persistent WebKit data store.

## Size And Power Constraints

The release build intentionally avoids SwiftUI, Combine, Swift Concurrency, third-party packages, bundled media, and app resources beyond `Info.plist`.

The side shelf is anchored to the current screen's visible frame and can be placed on the left or right edge. It uses compact horizontal rows in a vertical list; the active or hovered row expands in place while the panel stays clear of side Docks and reserves bottom Dock space for content padding.

The build script uses `-Osize`, whole-module optimization, disabled reflection metadata, linker dead stripping, symbol stripping, and hardened-runtime signing. The current public targets, enforced by `scripts/build-macos-app.sh`, are 2 MiB gates for both the executable and app bundle.
