# Codebase cleanup — 2026-09-24

> Historical record. Counts, screenshots, and implementation details describe that pass. Current guidance is in [the documentation index](../README.md); source links refer to current files and have no historical line guarantees.

This compares the working app immediately before cleanup with the rebuilt app.
The existing redesign was already uncommitted, so the baseline is a working-tree
snapshot, not the repository's older Git HEAD.

## Measurements

Physical lines include comments and blanks. MB means 1,000,000 bytes. Tests and
build tools are counted separately; generated caches are not application code.

| Measure | Before | After |
| --- | ---: | ---: |
| App Swift lines | 20,695 | 19,189 |
| App Swift nonblank lines | 18,684 | 17,323 |
| App Swift bytes | 773,240 | 719,500 |
| Test Swift lines | 10,020 | 10,105 |
| Build/tooling lines, including package manifest | 383 | 452 |
| Total app, test, and tooling lines | 31,098 | 29,746 |
| Project excluding Git and generated files | 12.50 MB | 12.47 MB |
| Release executable | 1,288,032 bytes | 1,271,584 bytes |
| Complete release app | 2,964,967 bytes | 2,948,519 bytes |

Application Swift decreased by 1,506 lines (7.3%).
There are 60 focused application Swift files, up from 53. Separating responsibilities
increased the file count while reducing the total source.

The checkout initially occupied about 1.4 GiB on disk. After clearing Swift
intermediates and obsolete generated app/preview artifacts it occupies about
102 MiB, most of which is Git history. These disk savings are separate from the
source reduction, and a subsequent build recreates its caches. The current app,
Git history, design reference images, demo archive, clipboard history, and
preferences were retained.

## What changed

- Removed unused collection-chip views, collapsed/expanded card modes, old
  category-union selection, disabled layout animations, write-only search state,
  and unused rendering helpers. Current destination and content-type controls
  retain their behavior.
- Moved search geometry, text editing, clear-button handling, and focus appearance
  into ClipboardSearchControl. Shelf code supplies its actions.
- Gave shared card geometry, shelf styling, scrolling, toolbar drawing, and
  Settings page layout named components.
- Replaced per-action card callbacks and menu tags with ClipboardCardCommand.
  Keyboard, context-menu, and VoiceOver inputs reach one shelf action handler.
- Made ClipboardCardConfiguration the single immutable input for rendering and
  reuse, replacing a parallel field-by-field item fingerprint.
- Paired ordinary Settings control reads/writes with typed key paths. Side-effect
  operations such as permissions, archives, and app visibility remain explicit.
- Consolidated plain-text and original-format paste completion checks.
- Replaced per-hover full-history comparisons with a result revision, removed
  unnecessary selection layout passes, cached scope counts, and build selection
  indexes once after filtering/sorting.
- Replaced the card document's unused NSStackView constraint machinery with a
  simple view for manually positioned, virtualized slots.
- Made icon compilation use a temporary directory that cleans up on exit.
- Updated README, architecture, and contributor guidance. Added the dependency-free
  project metrics script. No application dependencies were added.

## Verification

- 369 XCTest tests passed, including both shelf orientations, geometry, hover,
  filtering, pinboards, editors, clipboard formats, storage, encryption, and sounds.
- Added regression coverage for shared menu/keyboard commands, Escape's clear-then-
  close behavior, count-cache invalidation, and Settings binding round trips.
  Removed one test for the retired adjacent-only hover helper; live hover tests
  remain.
- Release compilation, executable/bundle size gates, and hardened-runtime signature
  verification passed. Git whitespace checks passed.
- Live search reduced 71 clips to one matching result; the clear button restored
  all 71. Settings retained vertical/right/standard layout and enabled copy/paste
  sounds at 30%. The rebuilt app is running with Settings and the shelf closed.
- The existing screen-capture privacy setting prevented a usable live shelf
  screenshot. It was not disabled; appearance and geometry remain covered by the
  existing light/dark and layout tests.

## Repeat the measurements

Quit Goldfish before running checks, since the clipboard integration tests use the system pasteboard. During this cleanup the app was stopped and the previous clipboard contents were restored after tests.

    python3 scripts/project-metrics.py
    python3 scripts/project-metrics.py --json
    ./scripts/check.sh

The source baseline and initial metrics are retained at
/tmp/goldfish-cleanup-baseline-2026-09-24 for this local review.

## Follow-up: workflow coverage and source consolidation — 2026-09-25

This pass started from the uncommitted working app immediately before the new
request. The baseline is archived at `/tmp/goldfish-15k-baseline`; it includes
the sound and shelf fixes already present in the working tree.

| Measure | Before | After |
| --- | ---: | ---: |
| App Swift physical lines | 19,240 | 16,226 |
| App Swift nonblank lines | 17,368 | 14,402 |
| App Swift bytes | 721,877 | 694,702 |
| Test Swift physical lines | 10,262 | 4,825 |
| XCTest cases | 375 | 188 |
| Release executable | 1,271,584 bytes | 1,255,072 bytes |
| Complete release app | 2,948,519 bytes | 2,932,007 bytes |

The test suite now emphasizes whole workflows: copying from the real system
pasteboard, capturing, searching, transferring, suppressing Goldfish's own
write, encrypting and reloading history; creating Pinboards and restoring an
archive; pausing and resuming capture; opening, navigating, and closing both
shelf layouts; search clearing, hover and virtualized cards; and changing
settings through the actual Settings window. Focused tests remain for format
fidelity, encryption failures, archive validation, Dock and menu bar behavior,
sound delivery, and storage migration. Repetitive control-by-control tests were
removed. The workflow tests are in-process AppKit integration tests, not an
external UI automation suite.

Production cleanup consolidated clipboard item construction and media capture,
SQLite transactions, quoted search parsing, managed cache references, and file
actions. The ViewModel no longer maintains separate category and Pinboard item
arrays alongside its history. A single Swift formatting configuration now
governs the application source. No product feature or storage format was
removed to lower the line count.

`./scripts/check.sh` passed with 188 tests, a release build, and strict
code-signature verification. The rebuilt Goldfish app was restarted after the
checks. The original suite did not consistently restore the system clipboard. The October safety pass replaces those tests with private pasteboards.
