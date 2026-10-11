# macOS design implementation · 21 September 2026

This pass implements the macOS changes from the [design review](DESIGN_REVIEW_2026-27.md). iPhone and iPad work is deferred at the user's request. The native AppKit shelf, keyboard workflows, local history, Pinboards, and Stack remain the product foundation.

The shelf now has persistent search, named destinations, independent type and sort controls, neutral content rows, and a visible action/status area. Selection opens a preview; hovering does not move neighboring rows. Standard width increases from 336 to 420 pt, with Compact and Wide preferences and a larger clip-text option.

| Review finding | Implemented behavior | Evidence |
| --- | --- | --- |
| 1. Setup consent | Closing welcome leaves setup incomplete and capture off. Shelf/menu/shortcut entry points reopen setup. Only Start enables monitoring; the welcome footer explains this. | Onboarding and app-delegate tests; guarded startup and polling paths. |
| 2. Missing feedback | The shelf shows action outcomes, selection count, deletion Undo, and capture Pause/Resume. Capture activity does not erase the last action. Key-storage errors remain visible. Copy fallback explains Command-V and keeps the shelf open. | Model tests and visible-feedback regression test. |
| 3. Unstable navigation | All clips, Pinned, Stack, and named Pinboards stay available during searches. Content type and ordering are separate controls; source/date filters insert readable query tokens. Stack retains queue order. | Destination/type/sort intersection regression test, including zero results. |
| 4. Clip recognition | Neutral rows use 14 pt titles, 12 pt excerpts, and 11 pt metadata. Code uses its first meaningful line; text excerpts avoid repeating the title; image thumbnails are used when available. Content gets the shelf's full width. Width and 1.2× text preferences persist. | Layout/geometry tests, formatter checks, and rendered fixtures. |
| 5. Hidden reuse action | A visible button says Copy or Paste into the available target app. More exposes the selected clip's contextual actions. Existing shortcuts and menus remain available. Automatic paste permission is optional. | Paste-service/model coverage and action-bar inspection. |
| 6. Accessibility gaps | Stronger adaptive secondary text, selection/focus boundaries, larger clip text, live Reduce Transparency/Increase Contrast handling, named native controls, and outcome announcements. Cards expose a single item with select/preview, copy, pin, and Quick Look actions instead of hidden preview children. | Light/dark secondary-text contrast tests (at least 4.5:1 on card and shelf surfaces), geometry/layout and accessibility-structure assertions, and live accessibility-tree inspection. Manual release checklist remains required. |
| 7. Moving hover targets | Hover only changes emphasis. Preview expansion follows explicit selection, with Reduce Motion support and coordinated layout. | Regression test asserts unchanged row frames during hover at both text sizes. |
| 8. Search discovery/recovery | Search is always visible with a Command-F hint. Result count, source/date filter menu, Reset, and actionable empty states sit near the search context. Type controls remain readable at compact/standard widths. | Search visibility, filtering, and narrow-layout coverage; rendered empty state. |
| 9. Current platform materials | The utility control group uses `NSGlassEffectView` on macOS 26+. Content remains opaque; reduced effects replace glass with an ordinary surface. Display-setting changes refresh the material and custom layers. Older systems use the fallback. | Current-SDK compilation and appearance/layout checks. Older-OS execution is still a release-matrix task. |
| 10. Brand/icon consistency | A purple layered clipboard/paper mark, full-resolution `.icns` fallback, and a template SF Symbol in the menu bar. Xcode 26+ builds compile the `.icon` source into appearance-aware `Assets.car`. | Asset compiler output, rendered icon inspection, bundle metadata and signing verification. |
| 11. Settings friction | Real shortcut recording with Escape cancellation and conflict checks; global shortcuts suspend while recording. Ignored apps have a native app picker, removable named rows, and an explicit advanced-rules editor. Sorting is separate from type, cache values no longer snap to mismatched ticks, and responsiveness/storage/duplicate-image copy explains the result. | Recorder, settings presentation/layout, persistence, and rule-normalization tests. |
| 12. Fragmented editing/recovery | Text editing uses an attached sheet with explicit Command-Return save, Escape cancel, empty-draft validation, and failed-save draft preservation. Edits/renames retain the original clip ID. Pinboard management, export, rename, help, and destructive confirmations also use attached sheets; duplicate Pinboard names are rejected. Delete confirmations explain permanent scope and default to Cancel. | Editor and Pinboard sheet integration tests; stable-target model regression. |

Implementation lives primarily in `ClipboardShelfControls`, `ClipboardPanelView`, `ClipboardItemCardView`, `ClipboardPanelViewModel`, `ClipTextEditorController`, `ShortcutRecorderButton`, and `IgnoredAppsEditor`. The app delegate enforces setup completion, and the panel controller manages width and sheet lifetimes. Existing working-tree changes were preserved.

**Verification and limits**

`./scripts/check.sh` passed all **310 tests with zero failures**, built the release app, passed the size gates, and verified its ad-hoc signature. The Apple Silicon executable is **1,169,008 bytes** and the bundle is **2.7 MiB**, including the modern icon assets. The capture test that previously timed out now explicitly retains its monitor through asynchronous delivery; the full suite passed after that correction.

The packaging toolchain initially wrote SDK 13 into the release binary's load command despite compiling against SDK 27. The build now passes the actual SDK version and the Info.plist deployment minimum explicitly to the linker. A subsequent build verified **minimum macOS 13.0 / SDK 27.0**, the modern icon's System/Aqua/Dark/tintable appearance metadata, and the app signature.

Live checks in the isolated native review app confirmed light/dark readability, persistent navigation through a zero-result search, successful inline reset, one accessible item per clip with custom actions, editor validation and cancellation, shortcut recorder cancellation, and a preview-storage slider whose accessible value and visible label both read **120 MB**. The final text-size check also covers expanded plain-text previews, not just row titles and metadata.

After the final preview-font adjustment, all **17 relevant geometry, layout, and design regression tests passed again**. The package was rebuilt after that change.

The review fixture uses synthetic content, isolated preferences, a temporary store, and a test encryption key. It does not start the clipboard monitor or inspect the user's real clipboard history. Layout tests cover compact/wide shelves, both text sizes, screen bounds, and Settings widths of 560/580/760 pt.

**Rendered examples**

These are rendered application views from the same sources, with synthetic clips. System focus rings, active controls, sheets, and appearance changes were also checked in the live app; offscreen renders do not capture all compositor effects.

| Shelf | Supporting flows |
| --- | --- |
| [Light](design-update-2026-09-21/shelf-light.png) · [Dark](design-update-2026-09-21/shelf-dark.png) | [Search recovery](design-update-2026-09-21/search-empty-dark.png) |
| [Compact](design-update-2026-09-21/shelf-compact-light.png) · [Wide](design-update-2026-09-21/shelf-wide-light.png) | [General](design-update-2026-09-21/settings-0-light.png) · [Shortcuts](design-update-2026-09-21/settings-1-light.png) |
| [Compiled modern icon](design-update-2026-09-21/icon-modern.png) | [Capture/app exclusions](design-update-2026-09-21/settings-2-light.png) · [Performance](design-update-2026-09-21/settings-4-dark.png) · [Welcome](design-update-2026-09-21/welcome-light.png) |

The separate `icon-default`, `icon-dark`, and `icon-monochrome` images are fallback artwork studies from the icon-generation script. The shipped modern appearances are generated by Apple's asset compiler from `AppIcon.icon`.

Full VoiceOver/Voice Control task completion, exhaustive measured contrast, localization, real-world competitor timing, Intel runtime behavior, and older macOS execution are not established by automated layout tests. The concrete release checks are in [SMOKE_TEST.md](SMOKE_TEST.md). These are remaining validation tasks, not claims that those workflows fail. The changes follow current published platform direction; they do not certify compliance with future 2027 guidance.

The executable budget remains 2 MiB per architecture. The bundle gets a fixed additional 1 MiB allowance because compiled modern icon appearances add approximately 1.4 MiB. This yields a 3 MiB single-architecture / 5 MiB universal bundle gate. The build remains an ad-hoc signed local preview until the separate distribution signing/notarization process is completed.

**Follow-up: Goldfish and the menu-bar toggle**

The app is now named Goldfish throughout its visible interface, executable, bundle metadata, build/release scripts, and active documentation. Existing storage, preferences, Keychain, and archive identities are retained so the rename preserves access to saved data. The screenshots above predate the rename.

Primary menu-bar clicks now toggle on mouse-down. The panel's focus-loss and outside-click handlers defer dismissal for that same status-button click, preventing the shelf from closing before the toggle and immediately reopening. Control/right-click status menus and ordinary outside-click dismissal retain their separate behavior. Regression coverage includes the status-button hit region, a display with negative coordinates, modifier keys, and unrelated events.

After these changes, `./scripts/check.sh` passed **311 tests with zero failures**, built `build/Goldfish.app`, and verified the size gates and ad-hoc signature. An isolated live fixture confirmed launch and the renamed application menu. The automation could not access its menu-bar status item, so repeated physical icon clicks remain a manual check in [SMOKE_TEST.md](SMOKE_TEST.md).

**Follow-up: copies hidden by filters**

The running app was capturing successfully while the shelf remained filtered to Links. Clearing that filter exposed the recent text copies. Filtered result counts now include the total history count, captures outside the current view produce a separate Show new action, and routine capture/skipped messages are visible in the footer. Show new clears search, content type, and destination filters, uses newest-first ordering, and selects the latest hidden copy. The notice does not overwrite Undo or other action feedback and disappears when its clips become visible or are removed.

The targeted validation passed **58 tests**: 15 design regression tests, including three new capture/filter recovery cases, plus 43 app-delegate, panel-controller, geometry, and layout tests. Compact-width recovery, search/Pinboard/Pinned scopes, duplicate notice counts, removed clips, preserved Undo, and Stack capture are covered. These tests use isolated stores without changing the system clipboard. The release smoke-test instructions now require quitting running app copies before the broader clipboard/paste suite.

See [Apple's Icon Composer workflow](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer), [AppKit design guidance](https://developer.apple.com/videos/play/wwdc2025/310/), and the original review for platform references and the competitive context.
