# Contributing

Thanks for working on Goldfish. The project is optimized for a small binary, low idle power, local-only behavior, and native macOS ergonomics. Changes should protect those constraints.

## Local Setup

Quit Goldfish before running tests: the clipboard integration tests use the system pasteboard. This prevents the running app from saving test fixtures into your history.

```bash
swift test
./scripts/build-macos-app.sh
open build/Goldfish.app
```

Run the full local check before opening a pull request:

```bash
./scripts/check.sh
```

## Engineering Guidelines

- Prefer AppKit, Foundation, Carbon, SQLite, and system frameworks over third-party dependencies.
- Keep the release app small. If a dependency or framework is needed, document the feature value and size impact.
- Preserve local-only behavior. Do not add networking, telemetry, analytics, crash uploaders, or remote sync without an explicit design discussion.
- Avoid storing new classes of sensitive data. If capture behavior expands, add tests and update `docs/SECURITY.md`.
- Keep idle work bounded. Polling, timers, file scans, and cache purges should have clear caps or backoff behavior.
- Add tests for persistence, pruning, sensitive filtering, shortcut parsing, pasteboard behavior, and search/sort changes.
- Prefer behavior-level tests. Use the smoke checklist for visual layout instead of adding production debug accessors for private UI details.
- Extend `GoldfishWorkflowTests` when a user journey crosses capture, storage, search, transfer, shelf, or Settings. Keep focused tests for failure paths and formats that the workflow tests cannot safely exercise.
- Format application Swift consistently with `xcrun swift-format format --configuration .swift-format --in-place --recursive Sources/clipbored`.
- Put card actions in `ClipboardCardCommand` and its shared handler; keep ordinary settings reads/writes together in a typed binding.
- Keep geometry, appearance, and field-editor behavior in their named components. Remove obsolete paths when a design is retired.
- Report source and release size with `python3 scripts/project-metrics.py`; do not count cache removal as code reduction.
- Keep UI native and compact. This is a utility, not a marketing surface.

## Pull Request Checklist

- `swift test -q` passes.
- `./scripts/build-macos-app.sh` passes.
- The release executable remains under the size gate printed by the build script.
- Security or privacy behavior is unchanged or documented.
- User-facing behavior is covered by tests or a manual verification note.
- Documentation is updated when commands, settings, storage, or permissions change.
