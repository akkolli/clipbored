# Goldfish visual review fixtures

These are native AppKit renders using synthetic clipboard contents and isolated preferences, not screenshots of customer history. Each view is rendered in light and dark appearance. Third-party reference imagery is not included.

- `shelf-light.png` / `shelf-dark.png`: standard 420 pt vertical shelf.
- `shelf-compact-*` / `shelf-wide-*`: 336 pt and 540 pt vertical widths.
- `shelf-large-text-*`: larger reading size.
- `shelf-focused-*` / `shelf-multiple-*`: focus and selection.
- `shelf-link-*`, `shelf-image-*`, `shelf-code-*`, `shelf-color-*`: selected content previews.
- `shelf-short-copy-*`: fully readable short text remains compact when selected.
- `side-shelf-*`: the compact vertical shelf, retained for earlier artifact links.
- `filtered-new-copy-*`, `capture-paused-*`, `search-empty-*`: state and recovery.
- `settings-0-*` through `settings-5-*`: General, Shortcuts, Capture, Privacy, Performance, Data.
- `welcome-*`: first-run introduction with vertical cards.
- `icon-*`: original Goldfish icon in default, dark, and monochrome treatments.

The vertical renders supersede the initial horizontal concept. Offscreen rendering does not establish runtime frame rate, VoiceOver usability, or behavior on other macOS versions. The live UI tool returned `cgWindowNotFound` during this pass, so physical interaction checks remain unverified.
