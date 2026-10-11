# Welcome to Goldfish

Goldfish is a local-first clipboard shelf for macOS 13 or later. The universal
build supports Apple Silicon and Intel Macs. Move the app to Applications before
enabling launch at login or granting Accessibility permission.

## Get started

1. Open Goldfish, choose a shortcut, and click Start using Goldfish. Paste permission
   is optional; all other preferences are in Settings. Only Start enables capture.
   Closing welcome defers setup; the menu bar or shortcut reopens it. Earlier copies are not backfilled.
2. Copy a few things in your usual apps.
3. Click the menu-bar icon or press your chosen shortcut. First-run setup offers
   Shift-Command-V; the alternate shortcut is Command-Option-V.
4. Type to search, use Up/Down to select, then Return to paste. Without Accessibility
   permission, Goldfish copies the clip instead; switch back to your app and press Command-V.
   Down Arrow from search enters the selected result. Escape clears a search first, then closes the shelf.

## Useful shortcuts

| Action | Shortcut |
| --- | --- |
| Search | Type, or Command-F |
| Preview | Space |
| Paste plain text | Shift-Return |
| Copy selected clips | Command-C |
| Quick paste | Command-1 through Command-9 |
| New text clip | Command-N |
| Edit / rename | Command-E / Command-R |
| Pin / new Pinboard | Command-P / Shift-Command-N |
| Select several | Command-click or Shift-click |
| Undo deletion | Command-Z |
| Settings | Command-comma |

The destination row above the vertical list opens Pinned and your Pinboards.
Choose New Pinboard in that menu, or press Shift-Command-N. Use Add to Pinboard
in a clip's context menu to organize it. The destination menu also offers editing,
exporting, and deleting the selected Pinboard. Pinboards retain their contents when
ordinary history expires. The top pencil button creates a text clip; More Actions
includes Settings, a shortcut/search guide, and confirmed history cleanup that keeps saved clips.

Search supports `app:Safari`, `type:image,pdf`, `pinboard:"Work"`, and
`date:2026-09-21`, combined with ordinary search words.

The destination menu, Content type, and sorting work independently. The filter button
offers sorting, source-app, and date choices. Clear filters resets the search and scope. The bottom of the shelf
shows the effective Copy/Paste action, its outcome, Undo after deletion, and capture
pause/resume. Settings > General offers three shelf widths, larger text, and left/right placement. The vertical shelf is the default; horizontal browsing remains an optional layout.

If a copy seems missing, check the result count: a filtered view shows how many clips
are visible out of the full history. New copies hidden by search, content type, or
destination show a **Show new** button that clears filters and selects the latest
copy. Hover over Listening for the latest capture detail. Paused capture and errors appear in the footer.

Text clips open in an attached editor. Command-Return saves; Escape cancels.
An unsuccessful save keeps your draft in the editor. Preview with Space; Escape or the
preview’s close button returns to the shelf. Clicking outside dismisses the shelf and
its preview. The shelf stays clear of the Dock and remembers your paste destination.

## Privacy and limitations

- History is local. There is no telemetry. Confidential/temporary clipboard markers
  are always excluded; likely-secret filtering is also enabled by default.
- Secret detection is best effort. Pause capture before copying sensitive content.
- History and managed attachments are encrypted with a stable local key. If the
  key is unavailable, capture pauses instead of writing new plaintext history.
- Archive exports are unencrypted: store and share them carefully.
- iCloud is optional whole-history backup in appropriately entitled builds, not live
  multi-device sync. This preview does not include iPhone/iPad or shared Pinboards.
- This is an early preview. A local-preview ZIP is not notarized and may be blocked
  by macOS. Do not disable Gatekeeper; use a Developer ID-signed, notarized release
  for ordinary distribution.

Settings > Data can export/import history and Pinboards. The explicit full-data
reset there removes saved clips too, after confirmation. The current system
clipboard is never cleared as part of history cleanup.
