# Architecture

ClipBored is a single-process AppKit utility built with Swift Package Manager.

## Runtime Shape

- `ClipBoredApp` creates `NSApplication`, sets accessory activation, installs `AppDelegate`, and starts the run loop.
- `AppDelegate` wires shared services, status menu items, settings observers, and global shortcuts.
- `ClipboardMonitorService` polls `NSPasteboard.changeCount` on a utility queue with adaptive active/idle intervals.
- `ClipboardStore` keeps the in-memory item list and persists rows to SQLite on a serial queue.
- `ClipboardCacheService` stores bounded image previews under Application Support and keeps a small `NSCache`.
- `ShortcutManager` registers Carbon hotkeys for app-wide commands.
- `ClipboardPanelController` owns the bottom panel lifecycle and target-app tracking.
- `ClipboardPanelViewModel` filters, sorts, selects, copies, pastes, pins, organizes, deletes, opens, and reveals items.
- `SettingsWindowController` exposes native controls for capture, privacy, performance, shortcuts, and data management.

## Data Flow

1. The monitor notices a pasteboard change.
2. Source app metadata is checked against ignored apps.
3. Pasteboard content is normalized into a `ClipboardItem`.
4. Sensitive text is skipped when exclusion is enabled.
5. Copied images run local Vision OCR only when `Search in image labels` is enabled.
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

Textual SQLite fields, including optional collection names and image OCR text, are encrypted and decrypted at the `ClipboardStore` boundary. App-managed image cache files, URL preview thumbnails, audio clips, rich text sidecars, and PDF attachments are encrypted and decrypted at the `ClipboardCacheService` boundary. The encryption key is stored in Keychain when available, with an owner-only app-local fallback key if Keychain access blocks or fails. Full history clears remove the local fallback key when present and reset cached key state after SQLite deletion succeeds. Runtime `ClipboardItem` values remain plaintext in memory so search, duplicate detection, copy, paste, organization, and cache cleanup operate normally. Opening or revealing encrypted media creates a temporary decrypted copy for macOS handoff; stale temporary previews are cleared on launch, cache/history clear, and quit.

## Size And Power Constraints

The release build intentionally avoids SwiftUI, Combine, Swift Concurrency, third-party packages, bundled media, and app resources beyond `Info.plist`.

The build script uses `-Osize`, whole-module optimization, disabled reflection metadata, linker dead stripping, symbol stripping, and hardened-runtime signing. The current public targets, enforced by `scripts/build-macos-app.sh`, are a 1 MiB executable and a 1.8 MB app bundle.
