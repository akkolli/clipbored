# Manual Smoke Test Checklist

Use this checklist before a release or after changes to panel, pasteboard, settings, permissions, storage, launch-at-login, or packaging behavior.

## Setup

1. Build the app:

   ```bash
   ./scripts/check.sh
   ```

2. Quit any running ClipBored copy.
3. Open `build/ClipBored.app`.
4. Confirm ClipBored appears in the menu bar when `Show ClipBored in the menu bar` is enabled.

## Capture

1. Copy plain text from TextEdit, Notes, or a browser.
2. Open the panel with `Command + Option + V`.
3. Confirm the copied text appears in Most Recent.
4. Copy a URL and confirm it appears as a Link; if the source provides a local preview image, confirm the Link card uses that preview.
5. Copy an image and confirm it appears as an Image with a thumbnail.
6. Enable `Search in image labels`, copy an image containing readable text, and confirm searching for that text finds the Image.
7. Copy a sound clip and confirm it appears as Audio.
8. Copy a PDF or PDF selection and confirm it appears as a PDF.
9. Copy one Finder file and confirm it appears as a File.
10. Copy multiple Finder files at once and confirm they appear as one grouped File item with the file count.
11. Copy formatted text from a browser or Mail message and confirm it appears as Rich Text rather than flattened plain text.
12. Disable Images, Audio, Rich Text, PDFs, or Files in Settings > Capture, copy that type again, and confirm it is not captured.

## Panel

1. Open the panel and confirm the search field is focused.
2. Type a query and confirm results filter immediately.
3. Type a structured query such as `pinboard:"Client Work","Read Later" type:image,pdf` and confirm only clips from those collections and content types remain.
4. Clear the search field, press `Space`, and confirm the selected previewable clip opens in Quick Look instead of inserting a blank query.
5. Use arrow keys to move selection while the search field is focused.
6. Tab to collection chips and press `Space` or `Return`; confirm the focused chip is selected and the visible focus state is clear. Use Left/Right, Home, and End to move through the chip rail, including custom collections and Stack when present.
7. Tab to cards; confirm the focused card gets a clear focus border, `Return` pastes or copies it, and `Space` opens Quick Look for text, links, files, and media.
8. With a card focused, use Left/Right, Page Up/Page Down, Home, and End; confirm selection and focus move together across the shelf.
9. With a card or collection chip focused, type a normal character and confirm focus returns to search with that character inserted and results filtered.
10. Use a mouse wheel or two-finger vertical scroll over the card shelf and a crowded collection rail; confirm each pans horizontally, clamps at both ends, and shows subtle edge fades only where more content is hidden.
11. Right-click a filtered result and choose Show in Clipboard, or press `Command + G`, and confirm search clears while the same card stays selected in Most Recent.
12. Press `Esc` once with a non-empty search while the search field, a card, or a collection chip is focused and confirm search clears without closing the panel.
13. Press `Esc` again and confirm the panel closes.
14. Reopen the panel, change sort segments, and confirm each segment updates results.
15. Press `Shift + Command + N` or the collection rail `+`, enter `Client Work`, choose a color, and confirm a Client Work chip appears with 0 clips and an empty collection view.
16. Return to Clipboard, select a card, use its Collect button to choose Client Work, and confirm the Client Work chip count increases.
17. Select the Client Work chip and confirm the rail filters to assigned items, cards use the Client Work name/color in their headers, and the collection/color/assignment persists after quitting and reopening ClipBored.
18. Right-click the Client Work chip, choose Edit Collection..., rename it, change its color, and confirm the chip and assigned card headers update.
19. Right-click a media, file, link, PDF, audio, or text card, choose Rename..., give it a title, and confirm the card title and search results use the custom title while paste/copy still uses the original payload.
20. Double-click an item and confirm it attempts to paste or falls back to copy without creating a duplicate history entry.
21. Right-click a card, use Capture Rules to ignore its source app, copy from that app again, and confirm the new item is skipped.
22. Drag an unassigned card onto the renamed collection chip and confirm the chip count increases and the card appears when that collection is selected.
23. Resize or test on a narrow display and confirm the bottom shelf switches to compact cards that still show two recent clips cleanly.
24. Select a file, rich text, or URL card and confirm the selected-card rail exposes `Paste Plain Text`, the corner source/kind badge remains visible, and on a narrow shelf secondary actions collapse behind `More` instead of overflowing the card.
25. Confirm card footers do not show `Unknown` for clips without a source app, and confirm used clips show their usage count beside the source app.
26. Confirm card headers use readable relative ages such as `3 minutes ago` or `2 hours ago`, including when viewing a named collection.
27. Confirm the selected card shows a green corner Stack control, and that clips added to Stack keep a visible corner indicator when selection moves away.

## Copy And Paste

1. Select a text item and press the Copy button. Confirm the system clipboard contains that text.
2. Select a URL item and confirm the system clipboard contains both string and URL data by pasting into a browser address bar.
3. Select one-file and multi-file File items and paste into Finder or an app that accepts file references. Confirm all files are preserved for the multi-file item.
4. Select an audio item and paste into an app that accepts sound pasteboard data.
5. Select a PDF item and paste into Preview, Finder, or an app that accepts PDF pasteboard data.
6. Select a rich text item and paste into TextEdit rich text mode or Mail. Confirm basic formatting is preserved and plain-text paste still works in a text-only field.
7. Press `Command + 1` through `Command + 9` on visible numbered cards and confirm the matching card is pasted or copied; add `Shift` and confirm URL/rich items paste as plain text only.
8. Without Accessibility permission, confirm paste actions copy and show the permission fallback status.
9. With Accessibility permission granted, confirm paste returns focus to the previous app and inserts the selected item.

## Settings

1. Open Settings with `Command + ,`.
2. Change history length, default sort, polling profile, cache limit, ignored apps, and allowed content types; quit and reopen the app; confirm settings persist.
3. Change the open-panel shortcut and confirm the old shortcut no longer opens the panel and the new shortcut does.
4. Toggle `Pause clipboard capture`, copy text, and confirm paused capture does not record it.
5. Toggle `Exclude likely secrets`, copy a representative token, and confirm it is not recorded.
6. Use `Open Accessibility Settings` and confirm System Settings opens to the permission area or fallback settings app.
7. Use `Clear Clipboard History` and `Clear Thumbnail Cache`; confirm each shows a warning confirmation before deleting data.

## Storage And Privacy

1. Open the data folder from Settings > Data.
2. Confirm `history.sqlite` exists after capture.
3. Copy unique text and confirm `strings ~/Library/Application\ Support/ClipBored/history.sqlite | grep "unique text"` does not find it.
4. Copy uniquely identifiable rich text/audio/PDF data and confirm `strings ~/Library/Application\ Support/ClipBored/attachments/* | grep "unique text"` does not find it.
5. If `history-encryption.key` exists, confirm it is readable only by the current user.
6. Confirm image files are under `images/` and rich text/audio/PDF attachments are under `attachments/`.
7. Confirm app storage is local to `~/Library/Application Support/ClipBored`.
8. Open or reveal an encrypted image/audio/PDF, then quit ClipBored and confirm `/tmp/ClipBored/Previews` is removed.
9. Use `Clear Clipboard History` and confirm saved history, app-managed attachments, temporary previews, and `history-encryption.key` are removed when that fallback key exists.
10. Confirm quitting with `Clear history on quit` enabled removes history and app-managed cache/attachment files.

## Launch And Lifecycle

1. Enable Launch at Login, log out and back in, and confirm ClipBored starts.
2. Disable Launch at Login and confirm it no longer starts after the next login.
3. Right-click the menu-bar icon and confirm the status menu opens with capture state, clip count, Show Clipboard, Settings, Pause/Resume Capture, and Quit.
4. Control-click the menu-bar icon and confirm the same status menu opens without toggling the panel.
5. Toggle Pause/Resume Capture from the status menu and confirm the status row changes.
6. Quit ClipBored from the menu bar and confirm no `ClipBored` process remains.
