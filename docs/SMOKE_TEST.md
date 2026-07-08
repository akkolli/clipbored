# Manual Smoke Test Checklist

Use this checklist before a release or after changes to panel, pasteboard, settings, permissions, storage, launch-at-login, or packaging behavior.

## Setup

1. Build the app:

   ```bash
   ./scripts/check.sh
   ```

2. Quit any running ClipBored copy.
3. Open `build/ClipBored.app`.
4. With a fresh preferences profile, confirm the setup assistant appears before the clipboard panel; choose the open shortcut, Keep History retention, menu-bar/Dock presence, launch-at-login, iCloud sync, and Accessibility option, then finish setup.
5. Reopen ClipBored and confirm the setup assistant does not reappear.
6. Confirm ClipBored appears in the menu bar when `Show ClipBored in the menu bar` is enabled.

## Capture

1. Copy plain text from TextEdit, Notes, or a browser.
2. Open the panel with the configured open shortcut.
3. Confirm the copied text appears in Most Recent.
4. Copy a URL and confirm it appears as a Link with a browser-style site preview; if the source provides a local preview image, confirm the Link card uses that image preview instead and that tall shelves give the preview more room.
5. Copy an image and confirm it appears as an Image with a thumbnail and a centered dimension overlay.
6. Enable `Search in image labels`, copy an image containing readable text, and confirm searching for that text finds the Image.
7. Copy a sound clip and confirm it appears as Audio with an album-style artwork tile.
8. Copy a movie or video clip and confirm it appears as Video with a player-style preview and centered format pill.
9. Copy a PDF or PDF selection and confirm it appears as a PDF.
10. Copy one Finder file and confirm it appears as a File.
11. Copy multiple Finder files at once and confirm they appear as one grouped File item with the file count.
12. Copy formatted text from a browser or Mail message and confirm it appears as Rich Text rather than flattened plain text.
13. Disable Images, Audio, Video, Rich Text, PDFs, or Files in Settings > Capture, copy that type again, and confirm it is not captured.

## Panel

1. Open the panel and confirm the search field is focused.
2. Type a query and confirm results filter immediately.
3. Press `Command + F` to focus search, press it again to show filters, then add Type, Device, and Pinboard filters and confirm they appear as structured tokens. Type a structured query such as `pinboard:"Client Work","Read Later" type:image,pdf device:<part of this Mac's name>` and confirm only clips from those collections, content types, and the copied-on Mac remain.
4. Clear the search field, press `Space`, and confirm a selected web link opens in ClipBored's built-in browser preview while non-link previewable clips open in Quick Look instead of inserting a blank query.
5. Use arrow keys to move selection while the search field is focused.
6. Tab to the search controls, collection `+`, toolbar buttons, and collection chips; confirm VoiceOver help explains the matching actions and shortcuts. Press `Space` or `Return` on a focused chip and confirm it is selected and the visible focus state is clear. Use Left/Right, Home, and End to move through the chip rail, including custom collections and Stack when present, and confirm VoiceOver help mentions those keys plus Pinboard/Stack context actions where available.
7. Tab to cards; confirm the focused card gets a clear focus border, `Return` pastes or copies it, `Command + C` copies it, `Shift + Return` and `Command + Shift + V` paste or copy it as plain text, and `Space` or `Command + Y` opens the built-in browser for web links or Quick Look for text, files, and media.
8. With a card focused, press `Command + F` and confirm focus returns to search; press `Command + E` on a text/code clip and confirm the edit dialog opens. On a Mac with Writing Tools available, confirm the dialog offers Writing Tools and keeps the saved clip as plain text. Press `Command + R` and confirm the rename dialog opens.
9. With a card focused, use Left/Right, Page Up/Page Down, Home, End, `Command + Up`, and `Command + Down`; confirm selection and focus move together across the shelf. Select two clips, press `Delete`, confirm both disappear, then press `Command + Z` and confirm both return selected.
10. With a card or collection chip focused, type a normal character and confirm focus returns to search with that character inserted and results filtered.
11. Use a mouse wheel or two-finger vertical scroll over the card shelf and a crowded collection rail; confirm each pans horizontally, clamps at both ends, and shows subtle edge fades only where more content is hidden, with collection-chip labels fading cleanly instead of hard-clipping at the utility buttons.
12. Right-click a filtered result and choose Show in Clipboard, or press `Command + G` with the result card focused, and confirm search clears while the same card stays selected in Most Recent. Press `Command + O` on a focused link, file, or media card and confirm it opens.
13. Press `Esc` once with a non-empty search while the search field, a card, or a collection chip is focused and confirm search clears without closing the panel.
14. Press `Esc` again and confirm the panel closes.
15. Reopen the panel, change sort segments, and confirm each segment updates results.
16. Press `Shift + Command + N` or the collection rail `+`, enter `Client Work`, choose a color, and confirm a Client Work chip appears with 0 clips and an empty collection view.
17. Press `Command + N` or the shelf pencil button, enter text, and confirm a new text clip appears selected in the active shelf; on a Mac with Writing Tools available, confirm the new-text dialog offers Writing Tools. Repeat while Client Work is selected and confirm the clip is created in that collection.
18. Return to Clipboard, select a card, use its Collect button to choose Client Work, and confirm the Client Work chip count increases.
19. Select the Client Work chip and confirm the rail filters to assigned items, cards use the Client Work name/color in their headers, and the collection/color/assignment persists after quitting and reopening ClipBored. Confirm collection-assigned clips stay in Client Work even as normal clipboard history rolls over.
20. Create a second collection, then press `Command + Right` and `Command + Left`; confirm selection moves between collections and wraps around.
21. Right-click the Client Work chip, choose Edit Collection..., rename it, change its color, and confirm the chip and assigned card headers update.
22. Right-click a custom Pinboard chip, choose Export Pinboard..., save a `.clipboredarchive`, import it into a fresh test profile from Settings > Data, and confirm only that Pinboard's clips, empty Pinboard state, and color are restored.
23. Confirm collection chips with 0 clips do not show a visible count pill, while chips with clips still show their counts.
24. Right-click a media, file, link, PDF, audio, or text card, choose Rename..., give it a title, and confirm the card title and search results use the custom title while paste/copy still uses the original payload.
25. Right-click an image card or focus its action rail, choose `Rotate Image`, and confirm the preview updates while the title, Pinboard, source app, and searchable image text remain. Then choose `Extract Text` on an image containing text and confirm the card shows the extracted text and `Copy Plain Text` can copy it.
26. Double-click an item and confirm it attempts to paste or falls back to copy without creating a duplicate history entry.
27. Right-click a card, use Capture Rules to ignore its source app, copy from that app again, and confirm the new item is skipped.
28. Drag an unassigned card onto the renamed collection chip and confirm the chip count increases and the card appears when that collection is selected.
29. Open the panel and confirm it appears as a vertical side shelf with compact horizontal rows; hover a row and confirm it expands in place. On a multi-display setup, open from the global shortcut with the pointer on each display and confirm the shelf opens on that display; click the menu-bar icon and confirm it opens on the menu-bar icon's display. Switch Spaces or use a full-screen app and confirm the shelf opens on the active Space instead of following every desktop.
30. Switch Settings > General > Panel > Shelf side between Left and Right. Reopen the panel after each change and confirm it slides from the configured side and keeps the category row centered.
31. Select a file, rich text, or URL card, then hover or keyboard-focus it and confirm the action rail exposes `Paste Plain Text`, the corner source/kind badge remains visible, and on a narrow shelf secondary actions collapse behind `More` instead of overflowing the card.
32. Confirm card footers do not show `Unknown` for clips without a source app, confirm used clips show their usage count beside the source app, and confirm clips synced or imported from another Mac show that copied-on device in the footer.
33. Confirm card headers use readable relative ages such as `3 minutes ago` or `2 hours ago`, including when viewing a named collection.
34. Confirm the selected card shows a green corner Stack control, the hover/focus action rail does not duplicate Stack, and clips added to Stack keep a visible corner indicator when selection moves away.
35. Confirm text cards use a quiet paper-style body, single-line text cards do not repeat the same text in both title and body, and multi-line text cards show the remaining lines below the first line with a subtle bottom fade.
36. Confirm the Pinned empty state points to the Pin action instead of a plain-key shortcut.
37. Confirm each card's source or type badge reads as an attached header-corner tile instead of a small floating icon.
38. Confirm built-in collection chips use recognizable glyphs, while custom collection chips keep color-dot swatches.
39. Confirm cards from known apps show app identity in the header tile, falling back to source initials when an app icon is unavailable.
40. Confirm single-file and PDF cards show a centered document-cover preview with a file-type pill, while multi-file cards show a stacked file preview.
41. Confirm the shelf chrome uses one row with compact search, collection chips, and separate soft utility icon buttons instead of a heavy grouped block; typing a search expands the search field without pushing cards out of view.
42. Confirm the top collection rail reads as a quiet translucent strip, the selected collection is a subtle pill, and the active card visibly floats above neighboring cards while the rest stay docked in the shelf.
43. Copy a color swatch from a design tool and confirm it appears as a centered paint-chip Color card, can be filtered with the Colors chip, and copies back as both a color and hex text.
44. Copy a code snippet from an editor and confirm it appears as a Code card, remains visible in the Text chip, can be isolated with the Code chip or `type:code`, and copies back as plain text.
45. Copy a video/movie clip and confirm it appears as a Video card, uses a movie-frame thumbnail when available, filters with the Videos chip or `type:video`, `type:movie`, and `mp4`, previews/opens as a temp movie, and copies back as movie data.
46. Press `Shift + Command + C`, confirm the Stack chip appears active with 0 clips, copy two text snippets, and confirm Stack count increments and the Stack view shows them in copy order. Press `Shift + Command + C` again and confirm capture stops.
47. Filter to a few clips, right-click a card or the Stack chip, choose Add Visible Clips to Stack, and confirm only the visible clips are queued once in shelf order.
48. With multiple text-like clips in Stack, choose Copy Stack as Text or Paste Stack as Text and confirm the queued text is written in stack order with blank lines between clips and consumed from Stack.
49. Command-click non-adjacent cards and Shift-click a range; confirm the status count changes to selected clips, selected cards remain highlighted while hovering, and the card menu offers Paste Selection, Copy Selection, Paste Selection as Text, Copy Selection as Text, and Add Selection to Stack.
50. With a card focused, press `Shift` with Left/Right, Page Up/Page Down, Home, or End to extend the range, then press `Command + A` and confirm every visible card is selected without changing the active card.

## Copy And Paste

1. Select a text item and press the Copy button. Confirm the system clipboard contains that text.
2. Select a URL item and confirm the system clipboard contains both string and URL data by pasting into a browser address bar.
3. Select one-file and multi-file File items and paste into Finder or an app that accepts file references. Confirm all files are preserved for the multi-file item.
4. Select an audio item and paste into an app that accepts sound pasteboard data.
5. Select a Video item and paste into an app that accepts movie pasteboard data.
6. Select a PDF item and paste into Preview, Finder, or an app that accepts PDF pasteboard data.
7. Select a rich text item and paste into TextEdit rich text mode or Mail. Confirm basic formatting is preserved and plain-text paste still works in a text-only field.
8. Press `Command + 1` through `Command + 9` on visible numbered cards and confirm the matching card is pasted or copied; add `Shift` and confirm URL/rich items paste as plain text only.
9. Without Accessibility permission, confirm paste actions copy and show the permission fallback status.
10. With Accessibility permission granted, confirm paste returns focus to the previous app and inserts the selected item.

## Settings

1. Open Settings with `Command + ,`.
2. Change Shelf side, Keep History, history length, default sort, polling profile, cache limit, ignored apps, and allowed content types; quit and reopen the app; confirm settings persist.
3. Change the open-panel shortcut and confirm the old shortcut no longer opens the panel and the new shortcut does.
4. Toggle `Pause clipboard capture` or press `Command + T`, copy text, and confirm paused capture does not record it; press `Command + T` again and confirm capture resumes.
5. Toggle `Exclude likely secrets`, copy a representative token, and confirm it is not recorded.
6. Toggle `Hide panel from screen sharing and recordings`, open the clipboard panel, and confirm it is omitted from a macOS screenshot or screen recording; disable it and confirm capture works normally again.
7. Use `Open Accessibility Settings` and confirm System Settings opens to the permission area or fallback settings app.
8. Use Settings > Data > `Export Archive...`, save a `.clipboredarchive`, then import it into a fresh or cleared test profile and confirm text, Pinboard assignments, image previews, and PDF/audio/video/rich-text clips reappear; confirm external file-reference clips still point at their original paths.
9. In an ad-hoc local build, turn on Settings > Data > `Sync history with iCloud` and confirm the status reports iCloud Sync unavailable. In a signed build with an iCloud entitlement, use `Sync Now`, then restore into a fresh test profile and confirm text, Pinboard assignments, and app-managed attachments reappear.
10. Use `Clear Clipboard History` and `Clear Thumbnail Cache`; confirm each shows a warning confirmation before deleting data.

## Storage And Privacy

1. Open the data folder from Settings > Data.
2. Confirm `history.sqlite` exists after capture.
3. Copy unique text and confirm `strings ~/Library/Application\ Support/ClipBored/history.sqlite | grep "unique text"` does not find it.
4. Copy uniquely identifiable rich text/audio/video/PDF data and confirm `strings ~/Library/Application\ Support/ClipBored/attachments/* | grep "unique text"` does not find it.
5. Export an archive with unique test content and confirm the archive file is treated as sensitive backup material because it is portable and not encrypted by ClipBored.
6. If iCloud Sync is enabled in a signed build, confirm `ClipBored.clipboredarchive` in the app-private iCloud container is treated as sensitive backup material because it is portable and not encrypted by ClipBored.
7. If `history-encryption.key` exists, confirm it is readable only by the current user.
8. Confirm image files are under `images/` and rich text/audio/video/PDF attachments are under `attachments/`.
9. Confirm app storage is local to `~/Library/Application Support/ClipBored` when iCloud Sync is off.
10. Open or reveal an encrypted image/audio/video/PDF, then quit ClipBored and confirm `/tmp/ClipBored/Previews` is removed.
11. Use `Clear Clipboard History` and confirm saved history, app-managed attachments, temporary previews, and `history-encryption.key` are removed when that fallback key exists.
12. Confirm quitting with `Clear history on quit` enabled removes history and app-managed cache/attachment files.

## Launch And Lifecycle

1. Enable Launch at Login, log out and back in, and confirm ClipBored starts.
2. Disable Launch at Login and confirm it no longer starts after the next login.
3. Right-click the menu-bar icon and confirm the status menu opens with capture state, clip count, Show Clipboard, Settings, Pause/Resume Capture, Pause for 5 Minutes, Pause for 30 Minutes, Pause for 1 Hour, and Quit.
4. Control-click the menu-bar icon and confirm the same status menu opens without toggling the panel.
5. Choose `Pause for 5 Minutes`, confirm the status detail shows a timed pause and copied text is not recorded, then choose `Resume Capture`.
6. Toggle manual Pause/Resume Capture from the status menu and confirm the status row changes.
7. Quit ClipBored from the menu bar and confirm no `ClipBored` process remains.
