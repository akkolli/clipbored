# ClipBored design review · 21 September 2026

**Historical assessment:** this records the interface before the fixes. See the [macOS implementation report](DESIGN_UPDATE_2026-27.md) for the subsequent changes and verification. iOS implementation is deferred at the user's request.

**ClipBored has a strong native Mac foundation, but its main shelf does not yet match the clarity, finish, and accessibility assurance of leading 2026–27 Apple-platform apps.** Onboarding and Settings are considerably closer. The most valuable next work is to improve recognition, navigation, feedback, and consistency. A visual refresh alone would leave several important interaction problems unresolved.

This repository contains a macOS AppKit executable targeting macOS 13 and later. It contains no iOS target or iPhone/iPad interface. Accordingly, the Mac assessment below concerns an implemented product; the iOS assessment is a readiness review and proposed direction, not a review of an existing iOS app. See [Package.swift](/Users/proflepton/projects/clipbored/Package.swift:6).

The review covers the current working tree, including existing uncommitted changes. I inspected the source, documentation, app icon, accessibility tree, and a running review build compiled from the current application sources. The review build used isolated preferences and synthetic clips without starting the clipboard monitor. I examined the shelf, search, representative content and attachment fallback cards, onboarding, and all six Settings pages. Light and dark appearances were inspected on macOS 27.0, build 26A428, with the installed Xcode beta/Swift 6.4 toolchain.

The calendar year 2027 is still ahead. This review uses published Apple guidance and current 26/27 platform direction available on the review date; it does not claim to predict all of next year's design changes.

| Area | Assessment | Reason |
| --- | --- | --- |
| Native Mac behavior | Strong foundation | AppKit, system controls, keyboard navigation, Quick Look, contextual actions, and drag-and-drop fit the platform. |
| Shelf hierarchy and readability | Needs substantial refinement | Saturated headers dominate; narrow titles and 10 pt metadata reduce recognition. |
| Discoverability and navigation | Below the competitive bar | Icon-only filters, unnamed color dots for Pinboards, concealed actions, and changing rail positions require learning. |
| Feedback and recovery | High-priority gap | Action/status messages exist in the model but have no shelf presentation. |
| Onboarding | Visually strong; one trust issue | Clear hierarchy and optional paste permission, but closing the welcome window completes setup and starts capture. |
| Settings | Solid, with specific weaknesses | Good grouping and resizing; shortcut editing, ignored-app entry, and technical labels need improvement. |
| Accessibility | Meaningful groundwork; incomplete assurance | Labels, focus states, and Reduce Motion are present. Larger text, contrast, and complete assistive workflows need validation. |
| Branding and icon | Behind the interface | The blocky clipboard icon and full-color menu-bar miniature do not match the newer onboarding. |
| Contemporary platform materials | Partial adoption | Native controls can adapt, but the custom shelf largely retains a legacy visual-effect treatment. |
| iOS/iPadOS | Not implemented here | Needs its own capture model, navigation, touch interactions, and device data strategy. |

The relevant competitive set is broader than another colorful clipboard shelf:

| Benchmark | What it establishes | Implication for ClipBored |
| --- | --- | --- |
| [Apple Spotlight clipboard history](https://support.apple.com/en-asia/guide/mac-help/mchl40d5b86b/26/mac/26) | macOS already offers searchable clipboard history. | Basic history and search are baseline utility. The shelf, retained collections, richer content, and Stack need a visibly better workflow. |
| [Paste](https://pasteapp.io/help/explore-paste) | Visual history, structured filters, Pinboards, and a device-spanning experience. | ClipBored has useful local organizing capabilities, but its interface conceals much of that value. Whole-archive backup does not supply the same device experience. |
| [Raycast Clipboard History](https://www.raycast.com/core-features/clipboard-history) | Search alongside a separate detailed preview and fast keyboard reuse. | Compare time to identify and reuse a clip, particularly when several entries have similar titles. |
| [Maccy](https://maccy.app/) | A focused native utility centered on quick search and reuse. | Extra visual structure needs to earn its screen space and learning cost. |
| [PastePal](https://indiegoodies.com/pastepal) | An edge shelf, larger organizing view, collections, Stack, and Mac/iPhone/iPad support. | A vertical shelf is a credible direction, but is not sufficient differentiation by itself. |

These comparisons use the vendors' published product descriptions and imagery, not timed testing of competing installations. Vendor marketing claims about speed or privacy are not independent measurements. In particular, older claims that macOS has no clipboard history are no longer a useful benchmark.

Apple's current direction emphasizes readable content, distinct controls/navigation, adaptive system materials, and respect for platform conventions. Its WWDC26 design update specifically discusses improved legibility, stronger toolbar structure, edge-aligned Mac sidebars, and refined icon rendering. This supports refining ClipBored's hierarchy rather than simply adding more translucent surfaces. [Apple WWDC26 keynote](https://developer.apple.com/videos/play/wwdc2026/101/)

**The following findings are ordered by practical priority.** P1 means address before presenting the app as a polished public product; P2 means a substantial quality improvement; P3 means later optimization. These are design-review priorities, not claims of a security exploit or a formal compliance rating.

1. **P1 · Closing onboarding starts capture despite the explicit “Start” action.**

   The welcome window says capture starts when the user is ready and provides “Start using ClipBored.” However, its close delegate calls the same completion path, marks onboarding complete, and invokes the app's completion callback, which starts the monitor. A person closing the introduction may reasonably believe they have deferred setup. This is especially consequential for a clipboard product.

   Keep the current compact introduction, but distinguish dismissal from starting capture. Closing should leave setup incomplete and capture inactive, with an easy route back from the menu bar. Explain the capture behavior immediately next to the start action. The existing statement that Accessibility is optional for copying is good and should remain.

   Evidence: [welcome close behavior](/Users/proflepton/projects/clipbored/Sources/Goldfish/views/OnboardingWindowController.swift:78), [completion path](/Users/proflepton/projects/clipbored/Sources/Goldfish/views/OnboardingWindowController.swift:246), [monitor start](/Users/proflepton/projects/clipbored/Sources/Goldfish/app/AppDelegate.swift:926). This finding is source-confirmed; the review fixture did not run capture.

2. **P1 · Important action feedback never reaches the shelf.**

   The view model produces messages for copy/paste outcomes, deletion/undo, Stack actions, unavailable content, and capture-rule changes. It exposes `onStatusMessageChanged` and `onCaptureStatusChanged`, but the shelf's binding method subscribes to neither. Some state is available elsewhere in Settings or the menu-bar menu, and card changes can be visible, but there is no general in-context outcome or persistent capture-state presentation in the shelf.

   Add a compact feedback region with messages such as “Copied — press ⌘V to paste,” “Deleted 3 clips · Undo,” and “Capture paused · Resume.” Expose the current selection count and the intended destination when reliable. Announce consequential outcomes to assistive technology. Ensure copy fallback remains understandable after an attempted paste dismisses the shelf.

   Evidence: [model status](/Users/proflepton/projects/clipbored/Sources/Goldfish/views/ClipboardPanelViewModel.swift:175), [callbacks](/Users/proflepton/projects/clipbored/Sources/Goldfish/views/ClipboardPanelViewModel.swift:268), [shelf bindings](/Users/proflepton/projects/clipbored/Sources/Goldfish/views/ClipboardPanelView.swift:434). This is a concrete implementation gap, not just a visual preference.

3. **P1 · Navigation is difficult to recognize and changes while searching.**

   The rail combines history, frequency ordering, content types, pinned content, custom Pinboards, and potentially Stack in one icon column. Custom Pinboards become colored dots with their names hidden. Their names and counts are available through accessibility labels and tooltips, but the resting screen offers little help distinguishing them. Color alone is insufficient for recognizing multiple named destinations.

   The live no-results search also removed nearly every built-in category. Counts are calculated against the search query, and categories with no matching entries disappear. This changes navigation positions exactly when the user may need to broaden their search; the empty-state advice to “switch filters” is weakened by the missing filters.

   Preserve stable navigation during a query. Show an active destination label and explicit filter summary. Give Pinboards visible names in an expandable rail or named collection picker. Separate the concepts of destination, content filter, and sort order. Command-click unions can remain an expert shortcut alongside a visible filter interface.

   Evidence: [icon-only rail](/Users/proflepton/projects/clipbored/Sources/Goldfish/views/ClipboardPanelView.swift:580), [Pinboard dots](/Users/proflepton/projects/clipbored/Sources/Goldfish/views/ClipboardPanelView.swift:599), [query-dependent counts](/Users/proflepton/projects/clipbored/Sources/Goldfish/views/ClipboardPanelViewModel.swift:401), [category visibility](/Users/proflepton/projects/clipbored/Sources/Goldfish/views/ClipboardPanelViewModel.swift:435).

4. **P1 · The card list spends too much visual emphasis on classification and too little on the clip itself.**

   At the preferred 336 pt shelf width, the rail, gutters, quick-paste number, source badge, and occasional pin leave a narrow title area. In the review fixture, “Launch notes for the autumn release” and longer filenames were visibly truncated. Every collapsed row is effectively a full-color header. The result is a strong rainbow of content categories with limited text for distinguishing actual items.

   The compact title is 13 pt and its type/app/time subtitle is 10 pt. That small subtitle is doing substantial work. Code titles commonly reduce to a language label such as “Swift Snippet,” so several code clips can look alike before expansion. This is a recognition problem even though the black/white header-ink selection is deliberately contrast-aware.

   Give the title and a useful content excerpt more room. Prototype a neutral row surface with a smaller type accent, a modest source icon, and readable metadata. Start around 13–14 pt for Mac primary text and 11–12 pt for secondary text, then validate density and accessibility. Show a code excerpt or identifying first line, the domain for a link, and a recognizable thumbnail for an image when available. Offer a wider shelf or detail view for content that cannot be judged at the compact width.

   Evidence: [shelf dimensions](/Users/proflepton/projects/clipbored/Sources/Goldfish/views/ClipboardPanelController.swift:62), [card header and fonts](/Users/proflepton/projects/clipbored/Sources/Goldfish/views/ClipboardItemCardView.swift:886), [title formatting](/Users/proflepton/projects/clipbored/Sources/Goldfish/views/ClipboardItemCardContentFormatter.swift:4). Neutral rows are a design recommendation, not an Apple rule banning color.

5. **P1 · Make the primary reuse action discoverable.**

   Single-click selects; double-click pastes; Return pastes; most alternatives live in context menus and shortcuts. These are useful Mac behaviors, but a new user looking at the shelf sees search, ellipsis, settings, filters, and colored cards without an obvious Copy/Paste action or destination. Accessibility access also changes whether a paste action can directly insert content or must fall back to copying.

   Show a small selected-item action bar with the effective action and shortcut: for example, “Paste into Notes ↵” when the target and permission are available, or “Copy ↵” when that is the effective behavior. Make plain-text paste and additional actions reachable through a visible, consistently placed menu. Preserve the existing shortcut and contextual-menu paths.

   Evidence: [click behavior](/Users/proflepton/projects/clipbored/Sources/Goldfish/views/ClipboardItemCardView.swift:430), [contextual actions](/Users/proflepton/projects/clipbored/Sources/Goldfish/views/ClipboardItemCardView.swift:503), [welcome permission explanation](/Users/proflepton/projects/clipbored/Sources/Goldfish/views/OnboardingWindowController.swift:70).

6. **P1 · Accessibility needs an explicit release standard.**

   There is substantial useful work here: system fonts, semantic colors in many places, calculated header ink, keyboard-focusable cards and categories, selection descriptions, custom category-combination actions, and Reduce Motion handling. The live accessibility tree exposed meaningful labels.

   Remaining concerns are small fixed typography, subdued footer metadata and inactive rail symbols, color-only Pinboard identities, and outcome messages without presentation/announcements. Source inspection found no explicit custom-view handling for Increase Contrast, Reduce Transparency, or a larger reading-size preference. Native components may already adapt to some settings; absence of custom handling does not prove that every control fails.

   Validate full find/preview/copy/pin/delete/undo workflows using VoiceOver, Voice Control, and keyboard-only input. Check focus and selection independently, including selection after filtering and list reflow. Measure both appearances and custom Pinboard colors; Apple uses approximately 4.5:1 for most text and 3:1 for non-text contrast in its evaluation guidance. No comprehensive contrast measurement or accessibility certification was performed in this review. [Apple contrast evaluation](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/sufficient-contrast-evaluation-criteria)

   The Mac's 32 pt toolbar controls are not automatically an iOS-sized-target violation. An iPhone implementation should use comfortably tappable targets, with 44 × 44 pt as the usual design target, and support Dynamic Type. [Apple UI design guidance](https://developer.apple.com/design/tips/)

7. **P2 · Keep preview expansion from undermining spatial stability.**

   A compact row grows from 56 pt to 220 pt, moving subsequent rows by 164 pt. Expansion is short and deliberately coordinated, and the code handles stationary-pointer feedback and Reduce Motion. Those are strengths. Nevertheless, moving neighboring targets during pointer exploration remains a usability risk, particularly in a long list or near its bottom. This review did not establish a reproducible animation-jitter defect.

   Compare the current interaction with a stable list plus a side preview, or with expansion tied to explicit selection. If hover expansion stays, test deliberate dwell and scroll anchoring with real tasks. Keep the vertical shelf identity while allowing users to inspect content without repeatedly losing their place.

   Evidence: [row and expanded sizes](/Users/proflepton/projects/clipbored/Sources/Goldfish/views/ClipboardPanelViewSupport.swift:44), [presentation heights](/Users/proflepton/projects/clipbored/Sources/Goldfish/views/ClipboardPanelViewSupport.swift:280), [expansion coordination](/Users/proflepton/projects/clipbored/Sources/Goldfish/views/ClipboardPanelView.swift:1769).

8. **P2 · Search should advertise its capabilities and make recovery easier.**

   Type-to-search and ⌘F work, and structured search is unusually capable. However, the initial field collapses to a magnifying glass, and query syntax is explained in a modal guide behind the ellipsis. An empty search field does not visibly teach the primary task. The no-results state gives advice but no inline reset actions.

   Prototype a persistent “Search clips…” field with an optional compact mode. Offer filter suggestions or chips for app, content type, date, and Pinboard; retain typed syntax for expert users. Show active filters and result counts, with “Clear search” and “Reset filters” where they resolve an empty result. Keep those controls near the search context on very tall displays.

   Evidence: [search setup](/Users/proflepton/projects/clipbored/Sources/Goldfish/views/ClipboardPanelView.swift:239), [search guide](/Users/proflepton/projects/clipbored/Sources/Goldfish/views/ClipboardPanelView.swift:1687), [empty-state copy](/Users/proflepton/projects/clipbored/Sources/Goldfish/views/ClipboardPanelView.swift:1815).

9. **P2 · The custom shelf needs a deliberate current-platform material treatment.**

   The shelf uses `NSVisualEffectView` with `.hudWindow`, an approximately 96%-opaque tint, custom borders, and custom search/chrome containers. This is not equivalent to adopting the current Liquid Glass custom-control APIs. Conversely, the app's standard controls already benefit from being AppKit components; an AppKit-to-SwiftUI rewrite is unnecessary for this purpose.

   On supported systems, evaluate standard AppKit toolbar/search components or a restrained `NSGlassEffectView` treatment for the control layer. Retain stable, readable content surfaces and an appropriate macOS 13–15 fallback. Review custom backgrounds and corner geometry against the actual current OS, including user material preferences. The objective is coherent structure and legibility, with glass limited to useful navigation/control surfaces. [Apple adoption guidance](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass), [AppKit design session](https://developer.apple.com/videos/play/wwdc2025/310/)

   Evidence: [panel tint](/Users/proflepton/projects/clipbored/Sources/Goldfish/views/ClipboardPanelView.swift:100), [shelf material](/Users/proflepton/projects/clipbored/Sources/Goldfish/views/ClipboardPanelView.swift:211), [custom search material](/Users/proflepton/projects/clipbored/Sources/Goldfish/views/ClipboardPanelView.swift:512).

10. **P2 · Bring iconography and the shelf into the onboarding's visual family.**

    The welcome screen's typography, generous spacing, muted preview, neutral groups, and purple primary action form a coherent identity. The shelf's many saturated category fills feel like a separate product, and the bundled app icon is a coarse, hard-edged brown clipboard. The production menu bar also scales that full-color app icon to 18 pt and explicitly disables template rendering.

    Retain the welcoming tone and translate its restraint into the shelf. Create a recognizable app mark at small sizes, with appropriate contemporary icon appearances and a fallback asset for older systems. Use a separate template symbol for the menu bar so it can respond to system contrast and appearance. Apple's current Icon Composer workflow supports layered artwork and appearance variants; it is a useful production path, not a reason to overdecorate the icon. [Icon Composer](https://developer.apple.com/icon-composer/)

    Evidence: [app icon](design-review-2026-09-21/app-icon.png), [menu-bar image treatment](/Users/proflepton/projects/clipbored/Sources/Goldfish/app/AppDelegate.swift:957), [welcome](design-review-2026-09-21/welcome-light.png).

11. **P2 · Improve a few Settings controls rather than replacing the entire window.**

    The six pages are logically grouped, use native controls, fit their contents, and handle constrained widths. Keep that foundation. The shortcut editor, however, requires editing a key and four separate modifier checkboxes; a shortcut recorder would be more direct and easier to verify. The ignored-app list is a raw text box containing names; provide an app picker and removable named entries, with advanced text rules only where useful.

    “Polling profile,” “Thumbnail cap (MB),” and “Keep first image copy” need outcome-oriented explanations. Consider “Capture responsiveness” with a short battery/speed explanation, and clarify what the duplicate-image option actually changes. Keep detailed storage information available without making it the primary language of everyday settings. “Default sort” also includes content categories, so it should distinguish sort order from the initial view.

    A concrete consistency issue appeared in the live accessibility tree: the cache slider reported 129.5 while the visible label said 120 MB. The slider is restricted to evenly spaced ticks while the label reflects the stored setting. Align the allowed values, stored value, and accessible value. Also validate translations: the fixed label widths, horizontal six-part selector, and non-resizable welcome layout currently have no localization evidence.

    Evidence: [shortcut editor](/Users/proflepton/projects/clipbored/Sources/Goldfish/views/SettingsWindowController.swift:652), [ignored-app editor](/Users/proflepton/projects/clipbored/Sources/Goldfish/views/SettingsWindowController.swift:360), [cache ticks](/Users/proflepton/projects/clipbored/Sources/Goldfish/views/SettingsWindowController.swift:449), [cache displayed value](/Users/proflepton/projects/clipbored/Sources/Goldfish/views/SettingsWindowController.swift:968).

12. **P2 · Make editing, empty states, and data operations feel like parts of one workflow.**

    Creating and editing text uses modal `NSAlert` accessories, while previews have their own windows and most management lives in contextual menus. This is functional but fragmented for frequent snippet work. Consider an attached editor sheet or stable detail view that keeps the selected clip and its destination visible. Preserve keyboard cancellation and explicit save behavior.

    Empty-state copy is usefully specific to search, Pinboards, Stack, and content types. Add the relevant action: new text clip, reset filters, resume capture, or guidance for adding to a Pinboard. For destructive operations, keep clear scope and a reachable undo where supported. Archive export/import already has explicit encryption limitations and confirmation/progress handling; preserve that honesty while simplifying technical language.

    Evidence: [edit/new-clip flow](/Users/proflepton/projects/clipbored/Sources/Goldfish/views/ClipboardPanelView.swift:1645), [empty states](/Users/proflepton/projects/clipbored/Sources/Goldfish/views/ClipboardPanelView.swift:1815), [data controls](/Users/proflepton/projects/clipbored/Sources/Goldfish/views/SettingsWindowController.swift:474).

**For iPhone and iPad, the work is a product design project of its own.** The current Mac implementation cannot be evaluated as an iOS interface, and a narrow Mac shelf should not be treated as an already-completed phone design.

| Concern | Recommended iPhone approach | Recommended iPad approach |
| --- | --- | --- |
| Navigation | A small set of named destinations, such as History and Pinboards, with an obvious search entry and Settings access. | A sidebar or adaptive split view, with detail beside the list when space permits. |
| Clip recognition | A readable list with useful excerpts/thumbnails; open details on tap and make Copy explicit. | Reuse the same content hierarchy, with more preview space and optional denser layouts. |
| Actions | Visible Copy/Share/Pin actions; long press and swipe actions as additional routes. | Touch actions plus pointer menus, keyboard commands, drag-and-drop, and multi-selection. |
| Capture | A user-invoked “Save from Clipboard” action and Share extension. Explain when a clip is saved. | The same explicit capture model, including sharing and drag-and-drop across apps. |
| Search | Filters with visible names and reset actions; no dependence on keyboard-only syntax. | Search and filters that adapt to the available pane width. |
| Accessibility | Dynamic Type, useful VoiceOver actions, comfortable touch targets, and color-independent states. | The same, plus keyboard focus and layout testing across multitasking sizes. |
| Device continuity | Explicit sync state and a deliberate data model, if cross-device use is part of the product promise. | The same model, including offline behavior, conflicts, deletion, and attachment availability. |

The capture model is a material difference. Apple documents the foreground/background suspension lifecycle and user-intent requirements around pasteboard access; `UIPasteControl` supplies a system-mediated paste action. Design around explicit capture and sharing rather than promising the Mac's continuous polling behavior on a phone. Paste's own iPhone guide describes this limitation and its extension-based workflow. [Apple background lifecycle](https://developer.apple.com/documentation/uikit/preparing-your-ui-to-run-in-the-background), [UIPasteControl](https://developer.apple.com/documentation/uikit/uipastecontrol), [Paste's iPhone workflow](https://pasteapp.io/help/paste-on-iphone)

ClipBored currently offers optional whole-history iCloud backup/restore and correctly labels it as such. A synchronized history across devices needs additional product decisions: identity and merge behavior, per-item changes, attachment transfer, offline progress, conflicts, deletion propagation, and what data is protected. Do not present the existing backup toggle as a completed sync experience. See [data screen](/Users/proflepton/projects/clipbored/Sources/Goldfish/views/SettingsWindowController.swift:474) and [roadmap](/Users/proflepton/projects/clipbored/docs/ROADMAP.md).

**A focused implementation sequence would be:**

| Order | Work | Definition of a useful outcome |
| --- | --- | --- |
| 1 | Onboarding dismissal, action feedback, persistent capture state | Closing setup leaves capture off; copy fallback, failures, pause, and deletion/undo are understandable where they happen. |
| 2 | Stable named navigation, visible search/filter state, primary action | A new user can locate a clip, identify the current filter, and reuse it without consulting a guide. |
| 3 | Row hierarchy, readable metadata, preview stability, width options | Similar clips are distinguishable, filenames/excerpts have room, and previewing preserves orientation. |
| 4 | Current-platform control styling, app/menu-bar icons, Settings refinements | Shelf, onboarding, and Settings share a visual identity and respect system appearance preferences. |
| 5 | Accessibility and device-matrix validation | Common tasks work with assistive technology, larger text, both appearances, reduced effects, and supported display sizes. |
| 6 | iOS/iPadOS prototype and continuity specification | Realistic capture, share, retrieval, and offline/device workflows are agreed before building parity features. |

The first prototype should preserve the vertical shelf, native Mac behaviors, rich formats, local-first operation, shortcuts, Pinboards, and Stack. Explore a visible search field, a named collection/filter control, quieter rows with useful excerpts, and a selected-item action/status area. Treat exact widths, preview behavior, and color restraint as hypotheses to validate with representative users.

Suggested validation tasks are: find one of several similar text clips; distinguish two code snippets; reuse an image; paste as plain text; recover from a zero-result search; create and revisit a named Pinboard; identify whether capture is paused; understand the outcome without Accessibility permission; delete and undo a selection; and complete or defer first-run setup. Use representative data and record completion, mistakes, and hesitation rather than relying on aesthetic preference alone.

**Verification completed:** 43 existing tests passed with zero failures across `ClipboardCardGeometryTests`, `ClipboardPanelControllerTests`, `ClipboardPanelLayoutTests`, `OnboardingWindowControllerTests`, `SettingsLayoutTests`, and `SettingsPresentationTests`. These exercise card geometry, appearance changes, shortcut mapping, display placement, and Settings widths of 560/580/760 pt, among other behaviors. They do not establish full usability or accessibility quality. No application source files were changed for this review.

**Limits of this review:** I did not run a formal VoiceOver/Voice Control session, measure every contrast pair, benchmark large histories, validate every supported macOS version, test a signed cloud backup deployment, or exercise rich-media capture/playback end to end. The sample attachment cards included unavailable-media fallback states. A later attempt to reconnect to the live review app timed out, so remaining findings were checked against source and render fixtures. The isolated app was stopped afterward. These limits are why the review distinguishes confirmed behavior, design judgment, and proposed validation.

Selected visual evidence is available as [collapsed shelf](design-review-2026-09-21/shelf-light.png), [expanded shelf](design-review-2026-09-21/shelf-expanded-light.png), [welcome](design-review-2026-09-21/welcome-light.png), [General settings](design-review-2026-09-21/settings-0-light.png), [Shortcuts](design-review-2026-09-21/settings-1-dark.png), [Capture](design-review-2026-09-21/settings-2-dark.png), [Data](design-review-2026-09-21/settings-5-dark.png), and [empty search](design-review-2026-09-21/search-empty-dark.png). These are sample-data AppKit renders with window chrome omitted, not redesign proposals. Native compositing and focus can differ from offscreen rendering; the material and dark-shelf assessment also used the live UI. Unreliable offscreen dark-shelf and dark-welcome exports were excluded.
