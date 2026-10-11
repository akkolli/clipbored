# Maintenance

## Code map

Goldfish is one AppKit process. Start with the owner of the behavior below; related methods live together in the same subsystem. Tests use shared isolated fixtures and retain explicit scenario inputs and expected results.

| Source file | Responsibility |
| --- | --- |
| `Application.swift` | Startup, lifecycle, menus, hotkeys, configuration and service wiring |
| `Clips.swift` | Content-kind policy, representations, preferences and normalization |
| `Capture.swift` | Polling, ordered readers, rules, immutable provenance and OCR |
| `History.swift` | Deduplication, retention, SQL, migration and encryption |
| `Transfers.swift` | Media ownership/cache/previews, clipboard writers, archives and iCloud |
| `ShelfModel.swift`, `ShelfSearch.swift`, `ShelfActions.swift` | Indexed filters, search grammar, selection, Pinboards, Stack and media actions |
| `ShelfView.swift` | Native table/sidebar, rendering, context menus, dialogs and common controls |
| `ShelfWindow.swift` | Shelf lifecycle, displays, animations, keyboard routing and Quick Look |
| `SettingsWindow.swift`, `AuxiliaryWindows.swift` | Settings forms/data actions, setup and ephemeral web preview |

Two test files cover the interface (`InterfaceTests.swift`: settings, keyboard routing, shelf search/actions and native views) and data (`StorageTests.swift`: history, media, encryption, archives, capture and paste). Tests and shared fixtures count toward a 1,900-line suite budget. Group related scenarios into workflows and explicit case tables; preserve their inputs, assertions and fresh-fixture boundaries. Stop capture monitors before resetting, clear temporary previews between cache scenarios, and await pending UI callbacks before releasing their owners. Use the editor's symbol list to navigate classes; method count is descriptive, not a coverage target.

`GoldfishApp` starts NSApplication; AppDelegate wires services and only intentional global Carbon hotkeys (shelf and Stack capture). Settings uses a local shelf binding. The shelf controller tracks the target app and screen, positions the left/right panel, and respects Reduce Motion.

CaptureMonitor polls pasteboard change counts with adaptive active/idle profiles on a utility queue. An ordered reader table shares one immutable CaptureSource through classification, validation and caching. Rules run before caching each content kind; RTF and HTML share validation and caching, preserving original RTF bytes and hashes of the source data. Self-written changes are ignored. HistoryStore owns history, a single duplicate-update path (including Keep First Image), and prepared SQLite writes on its persistence queue. A shared mutation path prepares a complete clip value before notifying observers, so edits never expose mismatched titles, payloads or metadata. ClipRow defines the SQL column order, field types, defaults, encrypted strings and added columns once; typed key paths drive schema creation, loading and binding. Retention keeps pins/Pinboards; legacy JSON and plaintext rows/sidecars migrate. Runtime clips remain plaintext for search/paste. Storage and security boundaries are in [Security](../SECURITY.md).

ShelfModel owns selection and Stack. ShelfFilter is a value with exactly one scope: history, Stack, a Pinboard or a category union. Its pure reducer commits a complete transition and returns effects; ShelfModel then reloads and delivers callbacks. Extend this reducer for new filter behavior instead of adding flags or batching guards. Category and Pinboard indexes avoid full-history scans for empty queries. Search matches, normalized documents, filtered views, and count summaries are cached; invalidation follows item/preferences changes. Stable ties use original offsets. Stack preserves queued copy order. Visible selection and range anchors are restored by ID after filtering.

ShelfView uses NSTableView for row reuse and scrolling; hover presentation is independent of model selection. A small renderer handles kind/title/content/thumbnail/footer. UI owns native label styles, sizing, window hosting, alerts, archive panels and animation construction; views supply content and actions. Submenus share explicit enablement, and shelf transitions share cleanup. Range movement belongs to ShelfModel so table arrows and window shortcuts use the same selection rules. ClipKind defines display names, search labels, primary categories, icons and attachment capabilities together. Native controls handle search, the independent category rail, focus, and menus. ShelfKeyboard resolves keys, modifiers, search-editing state and the settings binding into a typed intent; the controller executes it. Numbered actions and settings keep their precedence, and navigation/range selection share movement rules. Preview work runs on a bounded operation queue, coalesces matching in-flight requests, returns on the main queue, and checks row identity before applying images.

Goldfish retains the `com.local.clipbored` bundle/Keychain identity and existing ClipBored storage, temporary-preview and iCloud paths. Preferences centralizes normalization, per-key persistence, and narrow change notifications. Settings and setup use native SwiftUI forms inside AppKit windows. SettingsFormState owns drafts and validation; refresh preserves active edits and caches cloud status. SetupDraft applies choices only on Finish. Archive/sync and user-requested media actions use bounded background queues with main-thread completion feedback. Web preview uses nonpersistent WKWebView only after explicit user action.

Use the validation checklist below for tests, signing, release and OS integration. Keep domain files below 1200 readable lines; consolidate duplication before splitting. Do not add density/layout variants, decorative preview hierarchies, continuous scans, unbounded work, or another owner for the same state.

Next work: resolve the concurrency/key-rotation and archive limitations listed in Security, measure idle wakeups and preview latency across large histories, validate OS/VoiceOver/motion behavior, and add tagged release notes. Shared Pinboard collaboration needs its own design.

## Contributions

Use the build command in [README](../README.md), the [code map](MAINTENANCE.md), and [release checks](MAINTENANCE.md).

Keep native UI, a small binary, bounded idle work, and local-first behavior. Prefer system frameworks. Explain any new dependency, networking, sensitive-data capture, or persistence format, and document its size and privacy effects.

Keep ownership clear: the history store owns persistence, the shelf model owns selection/filtering/Stack, and views render state. Consolidate repeated behavior before adding another abstraction. Keep Swift files below 1200 readable lines; avoid statement packing, generated source, or feature removal to meet budgets.

Add behavior tests for changed persistence, retention, security, clipboard representations, search, and shortcuts. Share fixture setup while keeping scenario inputs and expected outputs visible. Use the manual checklist for native UI and OS integration. Run `scripts/dev.sh check` before submitting a change, and report any checks that could not run.

A review should explain the problem, resulting behavior, validation, and material limitations. Update documentation when commands, settings, permissions, or storage change. Preserve the license and private vulnerability reporting policy.

## Validation and release

## Automated checks

```sh
./scripts/dev.sh check
./scripts/dev.sh idle 900
```

The check runs tests, packages `build/Goldfish.app`, applies an ad-hoc hardened-runtime signature, verifies it, and enforces 2 MiB executable/bundle gates and the source-size and test-suite budget guards. Review idle CPU/wakeups alongside Instruments or Activity Monitor; change polling intervals only with measured evidence. Keep thumbnails and media transforms off the main thread and queues/caches bounded.

## Distribution

`./scripts/release-macos-app.sh` rebuilds and creates `build/Goldfish.zip`. Without credentials it remains a local ad-hoc build. Set `DEVELOPER_ID_APPLICATION` to the Developer ID Application identity for distribution signing and timestamping.

Notarization uses `NOTARYTOOL_PROFILE`, or all three of `APPLE_ID`, `APPLE_TEAM_ID`, and `APPLE_APP_SPECIFIC_PASSWORD`. Create a profile once with `xcrun notarytool store-credentials <profile> --apple-id <id> --team-id <team> --password <app-specific-password>`. The release script submits, staples, validates, and recreates the zip after success. Do not store credentials in this repository.

Local/release scripts add no iCloud entitlement. Sync reports unavailable until the app is signed with its ubiquity container entitlement. Repeat signing, notarization, and sync checks for that build.

```sh
codesign --verify --deep --strict --verbose=2 build/Goldfish.app
codesign -d --verbose=4 build/Goldfish.app
xcrun stapler validate build/Goldfish.app
spctl --assess --type execute --verbose=4 build/Goldfish.app
```

Confirm hardened runtime, then complete the checklist below before publishing. Record the tested macOS version, signing configuration, and any untested integration. Add release notes when cutting tags.

## Manual checks

| Area | Verify |
| --- | --- |
| Setup/lifecycle | Fresh preferences show setup before the shelf; shortcut, retention, menu-bar/Dock, login, sync, and Accessibility choices persist. Relaunch hides completed setup. Test login on/off, both launch surfaces, timed/manual pause/resume, and quit with no process remaining. |
| Capture | Copy text, code, URL, color, image, audio, video, rich text, PDF, single/multiple Finder files. Check kind, grouped files, payload, ignored apps/types, sensitive exclusion, and capture status. Enable/disable OCR and search recognized text. |
| Responsiveness | With large history, scroll/search/select during thumbnail loads. New clips appear immediately; previews update in place without changing selection/scroll. Failed/missing previews keep usable fallbacks; URL/video previews work with available sources. |
| Shelf/display | Check left/right position, pointer display, menu-bar display, multiple displays, Spaces, and fullscreen. Hover expands only that row without affecting keyboard/batch selection or filters. Keyboard movement clears stale hover. Reduce Motion makes transitions immediate. |
| Search/categories | Icon opens search by click, typing, or repeated Command-F. Empty idle search collapses on another click; active queries persist. Escape clears, then closes. Test independent tokens and combined app/type/device/Pinboard/date/pin filters, quoting and diacritics. Empty built-ins hide; empty Pinboards remain. Command-click unions categories; hover changes no filters. Both scroll areas work independently. |
| Accessibility | Tab through search, toolbar, categories, and rows. Check visible focus, VoiceOver names/actions, category Up/Down/Home/End, clip Up/Down/Page/Home/End, and range extension. Left/Right must follow the documented shortcut routing. |
| Clip actions | Context menus expose applicable commands for every kind. Test keyboard shortcuts in README, numbered quick paste and plain-text variants, edit code/text, rename without payload changes, pin, collect, open/reveal, previews, image rotate/OCR, capture rules, and Show in Clipboard retaining the same clip. Double-click paste does not recapture. |
| Selection/Stack | Command-click nonadjacent clips, Shift-select a range, select all, batch original/plain-text copy/paste, delete and undo. Stack captures copy order; test add selected/visible, duplicate protection, next copy/paste, queue as text, and clear. |
| Pinboards | Create an empty colored board, assign by menu and drag, rename/recolor, export, delete, import into fresh preferences, and relaunch. Check counts, empty-board metadata, colors, durable retention, and all files when dragging a multi-file clip out. |
| Presentation | Titles are not repeated in text bodies; multiline text shows remaining content, code is monospaced, colors show swatches, documents show name/location, missing sources omit “Unknown.” Previews and controls fit narrow shelves. |
| Settings | Visit all six tabs at minimum size: top alignment, vertical scroll, no clipping/duplicate selectors/zero-size controls. Change every setting and relaunch. Close while editing shortcut/ignored-app drafts; check commit, validation, at least one capture kind, and no resetting unrelated edits. Status messages wrap. Settings shortcut remains local to the shelf. |
| Paste/permissions | Test every original representation in a suitable app, including multi-file Finder paste, URL titles and rich text. Plain text omits other formats. Without Accessibility, check copy fallback/status; with permission, check target activation and insertion. |
| Data/privacy | Export/import attachments and Pinboards; test entitled and unavailable iCloud. Check destructive confirmations, errors and success. Inspect encrypted SQLite text/sidecars using unique test content. Check temporary preview cleanup at quit. Clear thumbnails while retaining original images/history; clear history and clear-on-quit remove owned media and fallback key. Screen privacy hides only the shelf. Treat archives as sensitive. |

## Measuring the folder

`./scripts/dev.sh inventory` counts every regular file, including hidden files, docs, scripts, license and assets. It reports maintained files separately from `.build` and `build`; binary files contribute to bytes and file counts. `./scripts/dev.sh clean` removes only regenerable build products. Keep both figures when reporting reductions.
