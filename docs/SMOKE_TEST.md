# Manual Smoke Test Checklist

Use this checklist before a release or after changes to the shelf, pasteboard, settings, permissions, storage, launch-at-login, or packaging behavior.

## Setup

1. Run `./scripts/check.sh`, quit any running copy, and open `build/ClipBored.app`.
2. With fresh preferences, confirm the setup assistant appears before the shelf and covers the open shortcut, Keep History, menu-bar/Dock presence, launch at login, iCloud sync, and Accessibility.
3. Finish setup, relaunch, and confirm the assistant does not return.
4. Confirm the menu-bar icon appears when `Show ClipBored in the menu bar` is enabled.

## Capture And Preview Loading

1. Copy plain text, code, a URL, a color, an image, audio, video, rich text, a PDF, one Finder file, and multiple Finder files. Confirm each appears with the correct kind and grouped files remain one clip.
2. Confirm a new card appears immediately even when its preview is not cached. Keep searching and scrolling while the thumbnail loads, then confirm the card updates in place without changing selection or scroll position.
3. Confirm URL and video thumbnails appear when source data is available, and that a missing or failed thumbnail leaves a usable fallback card.
4. Enable `Search in image labels`, copy an image containing readable text, and confirm the OCR text is searchable after processing finishes.
5. Disable a content kind in Settings > Capture, copy that kind again, and confirm it is skipped. Re-enable it afterward.
6. Copy from an ignored source app and confirm the capture status reports that the item was skipped.

## Shelf Chrome, Search, And Categories

1. Open the shelf and confirm the collapsed search icon is at the toolbar's leading edge. Activate it and confirm the same liquid-glass pill expands smoothly to the right toward Clear History and Settings without moving its left edge or icon, with text and caret aligned after the icon.
2. With an empty query, confirm search is a circular magnifying-glass button. Click it or press `Command + F` and confirm it expands to an aligned search field without moving the card list.
3. Click a card or category while the empty search field is focused and confirm search collapses again. Enter a query and confirm it remains expanded after focus moves elsewhere; clearing the idle query collapses it.
4. Press `Command + F` repeatedly and confirm it keeps focus in the same search field.
5. Type a query and confirm results update immediately. Press `Esc` once to clear an active query and again to close the shelf.
6. Type a structured query such as `pinboard:"Client Work" type:image,pdf device:<part of this Mac's name>` and confirm the terms are combined with the text query.
7. Confirm the category icon rail scrolls vertically when its icons exceed the available height, while the card list scrolls independently beside it.
8. With sparse history, confirm built-in type/sort categories with zero matches are absent. Clipboard remains available, and empty custom Pinboards remain visible.
9. Click Text and confirm it replaces the current category filter. Command-click Links and confirm the list becomes the union of Text and Links; Command-click either selected chip again to remove it from the union.
10. Hover several category chips without clicking and confirm neither the active filters nor the visible clips change.
11. Tab to search, toolbar controls, chips, and cards. Confirm focus is visible and VoiceOver labels explain each action. Use Left/Right and Home/End on category icons, and Up/Down/Page/Home/End navigation on cards; Left/Right must not move card selection.

## Cards, Selection, And Actions

1. Confirm cards form one vertical list beside the category rail, with full-color kind or Pinboard headers and readable alignment at both left and right shelf positions.
2. Hover an unselected card and confirm only that card's preview expands. The selected/focused card, selected range, visible results, and keyboard navigation must not change, and the content must remain unobscured.
3. Move focus with the keyboard while another card is hovered. Confirm focus moves from the keyboard selection and stale hover expansion clears.
4. Confirm card and category transitions feel continuous rather than snapping. Enable macOS System Settings > Accessibility > Display > Reduce Motion and confirm panel, search, category, and card transitions become immediate; restore the original system setting afterward.
5. Right-click representative text, link, image, file, and media cards. Confirm applicable commands appear in the context menu: paste/copy, plain-text variants, preview/open, edit/rename, pin/collect, Stack, image rotate/extract text, capture rules, show in Clipboard, and delete.
6. With a card focused, confirm `Return` pastes, `Shift + Return` uses plain text, `Command + C` copies, `Space` or `Command + Y` previews, `Command + O` opens applicable clips, `Command + E` edits text/code, and `Command + R` renames without changing the payload.
7. Press `Command + 1` through `Command + 9` and confirm the matching numbered cards are used; add `Shift` and confirm plain-text output.
8. Command-click non-adjacent cards and Shift-click a range. Confirm context-menu batch actions use the selected set and `Command + A` selects all visible cards.
9. Delete multiple selected clips, press `Command + Z`, and confirm the batch returns selected.
10. From a filtered result, choose Show in Clipboard or press `Command + G`; confirm search clears and the same clip stays selected in Clipboard.
11. Double-click a card and confirm paste or copy fallback occurs without creating a duplicate history item.
12. Confirm text cards do not repeat a one-line title in the body, multi-line text shows the remaining lines, files/PDFs use document previews, and missing source apps do not display `Unknown`.
13. On multiple displays and Spaces, confirm the shortcut opens on the pointer's active display/Space and the menu-bar icon opens on its display. Switch Settings > General > Shelf side and verify both left and right placement.

## Pinboards And Stack

1. Press `Shift + Command + N` or use the category-row add button to create an empty color-coded Pinboard named `Client Work`; confirm its labeled chip remains visible with no count pill.
2. Assign an existing card through Collect or drag it onto the Pinboard. Confirm its count, color, and assignment survive relaunch and normal history pruning.
3. Right-click the Pinboard chip to edit its name/color, export it, and delete it. Import the archive into a fresh profile and confirm clips plus empty Pinboard metadata are restored.
4. Press `Shift + Command + C`, copy two clips, and confirm Stack capture records them in copy order. Toggle capture off again.
5. From a card or Stack context menu, test Add Visible Clips to Stack, next-item paste/copy, Stack-as-text, and Clear Stack. Confirm queue order and duplicate protection.

## Copy And Paste

1. Copy/paste text, URL, image, audio, video, PDF, rich text, and file clips into suitable apps. Confirm original pasteboard representations are preserved.
2. Paste a multi-file clip into Finder and confirm all file references are present.
3. Use plain-text paste on URL and rich-text clips and confirm formatting and non-text representations are omitted.
4. Without Accessibility permission, confirm paste falls back to copying and Settings > Privacy reports the permission requirement.
5. With Accessibility permission, confirm paste returns focus to the previous app and inserts the selected clip.

## Settings

1. With the ClipBored pane open, open Settings with `Command + ,` and confirm a resizable window with six clean selector tabs: `General`, `Shortcuts`, `Capture`, `Privacy`, `Performance`, and `Data`. Close the pane, switch to another app, and confirm `Command + ,` opens that app's settings instead of ClipBored.
2. Resize to the practical minimum. Visit every tab and confirm content stays anchored to the top-left, scrolls vertically when needed, and has no horizontal clipping, zero-sized controls, or duplicate selector labels.
3. In General, change shelf side, Keep History, history length, default sort, launch-at-login, and menu-bar/Dock presence. Relaunch and confirm persistence.
4. In Shortcuts, change the open shortcut, close Settings while a field is focused, and confirm the edited binding is committed and the old shortcut no longer opens the shelf.
5. In Capture, pause/resume capture, toggle likely-secret exclusion and image-label search, edit ignored apps, and toggle allowed content types. Confirm at least one content type must remain enabled and status feedback stays inside this tab.
6. In Privacy, test clear-on-quit, screen-capture hiding, Accessibility settings, permission refresh, and paste-status feedback.
7. In Performance, change the polling profile and image-cache cap. Confirm capture continues at the selected cadence, UI input remains responsive while polling, and the values persist.
8. In Data, export/import an archive, exercise available iCloud controls, open the history folder, and confirm destructive clear actions require confirmation and show success or error feedback in the Data page.
9. Change one control and confirm unrelated tabs do not jump, reset, or flash; long status messages should wrap instead of widening the window.

## Storage And Privacy

1. Open the data folder and confirm `history.sqlite`, `images/`, and `attachments/` appear as applicable.
2. Copy unique text and managed attachment data; confirm `strings` does not expose the test content from the SQLite database or encrypted sidecars.
3. Treat exported and iCloud `.clipboredarchive` files as sensitive because they are portable and not encrypted by ClipBored.
4. Open or reveal encrypted media, quit ClipBored, and confirm temporary preview files under `/tmp/ClipBored/Previews` are removed.
5. Clear history and confirm saved rows, managed attachments, temporary previews, and the fallback encryption key are removed when present. Clear the thumbnail cache separately and confirm history remains.
6. Enable `Clear history on quit`, relaunch, and confirm history and managed cache/attachment files were removed.

## Launch And Lifecycle

1. Enable and disable Launch at Login and verify the next login behavior each time.
2. Right-click or Control-click the menu-bar icon and confirm the menu includes capture state/count, Show Clipboard, New Collection, Stack Capture, Settings, pause/resume options, and Quit.
3. Test a timed pause, manual pause, and resume; confirm copied items are skipped only while capture is paused.
4. Quit from the menu-bar menu and confirm no `ClipBored` process remains.
