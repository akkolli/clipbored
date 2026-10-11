# Goldfish release review — September 21, 2026

> Historical review. Use [current release procedures](../RELEASE.md) and the [documentation index](../README.md).

## Scope and benchmark

The benchmark is a useful, coherent **local Mac clipboard manager**, retaining
Goldfish's vertical shelf and collapsing previews. This is not a claim of full
Paste parity. Paste was reviewed through its current official website, help,
release notes, and product screenshots—not a hands-on installation.

| Area | Paste reference | Goldfish outcome |
| --- | --- | --- |
| Browsing | Horizontal visual shelf; compact mode and resizable previews | Vertical shelf retained; shared corner/inset/spacing rules, flush card joins, one expansion-animation owner, independent hover and selection, stable scrollbar gutter, adaptive header text contrast |
| Everyday actions | Keyboard navigation, quick paste, plain text, preview, edit, rename, new text | Core equivalents present; added Command-N note creation, corrected Command-P pinning so typing `p` searches, reorganized context menus and added a keyboard/search guide |
| Organization | Durable Pinboards and multi-selection | Saved boards/pins survive routine cleanup; batch collection assignment now acts on the selected set; clear-history confirmation defaults to Cancel |
| Search | App/type/date/device filters and suggestions | Text, structured filters, and optional image OCR available; no comparable visual filter-suggestion interface yet |
| Setup and preferences | Clear first-run purpose and restrained chrome | Welcome rebuilt around a shelf preview and two choices; advanced preferences moved out of setup. Six Settings pages size to their actual content instead of a fixed-height empty footer |
| Privacy | Rules/exclusions and private content handling | Standard confidential/transient/generated markers rejected; whitespace preserved; unavailable encryption key blocks new persistence; unreadable history blocks unsafe import; paused/setup copies are not backfilled |
| Distribution and ecosystem | Established Mac/iPhone/iPad product, sync and collaboration | Mac-only local preview. Optional whole-history iCloud backup is not live sync. Developer ID signing and notarization explicitly deferred |

Reference: [Paste on Mac](https://pasteapp.io/help/paste-on-mac),
[Pinboards](https://pasteapp.io/help/organize-with-pinboards),
[search and filters](https://pasteapp.io/help/search-and-filters), and
[current product](https://pasteapp.io/).

## Reliability fixes

- Capture preserves original text/code indentation and trailing newlines.
- Hex color literals become color clips and honor color exclusions.
- Capture/import cannot silently fall back to plaintext when the production key is unavailable.
- Import cannot rewrite the database while unreadable encrypted records exist.
- Delayed automatic paste verifies the target is still frontmost and the clipboard
  has not changed; otherwise it cancels delivery.
- Normal app launch/reopen reveals a usable window. Login/service launch remains quiet.
- First-run capture stays off, and values copied during setup or a pause are not
  retroactively captured when monitoring starts/resumes.
- Build scripts validate architecture, size, signatures, and bundle contents;
  local/unnotarized ZIP names cannot masquerade as a notarized public release.

Confidential clipboard markers follow the community interoperability conventions
documented at [nspasteboard.org](https://nspasteboard.org/). Secret detection remains
best effort, not a guarantee that all sensitive text is recognized.

## Verification and limits

The full suite passed: **297 tests, zero failures**. Automated coverage includes card geometry through expansion/reversal, appearance
changes, Settings fit at three widths, welcome layout/completion, exact text capture,
pause/start boundaries, marker exclusion, encrypted storage failures, safe archive
import, batch assignment, protected history cleanup, shortcut dispatch, and delayed
paste cancellation. Run `./scripts/check.sh` for the complete suite and local bundle.

The final universal bundle contains both arm64 and x86_64 slices (approximately
2.5 MiB). Strict code-signature verification and ZIP integrity checks passed.
The ZIP contains only the app, icon, license, quick-start guide, and signature
metadata—no clipboard database, encryption key, or demo-user history.

Manual visual review uses isolated sample data, with the real AppKit views in both
appearances. The real encrypted history was separately checked: 34 readable records,
no decryption warning after the previously authorized cleanup. The recovery backup
was retained. No user history is packaged into the app or ZIP.

Still requires a separate pre-distribution pass: a clean Mac install, Intel hardware
(a universal compile is not hardware testing), multi-display/Spaces behavior,
login-item registration, and granted Accessibility paste into representative apps.
The full manual checklist is in [SMOKE_TEST.md](../SMOKE_TEST.md); it is a checklist,
not a claim that every item has been manually exercised.

## Deliberately not claimed

- No iPhone/iPad clients, live cross-device sync, shared/team Pinboards, AI/MCP,
  automatic updater, or full Paste search/filter UX.
- Exported archives are portable but unencrypted; they must be handled as sensitive.
- The current package is a local preview, not a notarized public release. Signing
  remains deferred at the user's request; no credentials or permission grants
  were changed during this review.

Public-distribution requirements are separate from UI completion. See
[RELEASE.md](../RELEASE.md) and Apple's
[notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
