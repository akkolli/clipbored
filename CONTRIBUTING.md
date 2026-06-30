# Contributing

Thanks for working on ClipBored. The project is optimized for a small binary, low idle power, local-only behavior, and native macOS ergonomics. Changes should protect those constraints.

## Local Setup

```bash
swift test
./scripts/build-macos-app.sh
open build/ClipBored.app
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
- Keep UI native and compact. This is a utility, not a marketing surface.

## Pull Request Checklist

- `swift test -q` passes.
- `./scripts/build-macos-app.sh` passes.
- The release executable remains under the size gate printed by the build script.
- Security or privacy behavior is unchanged or documented.
- User-facing behavior is covered by tests or a manual verification note.
- Documentation is updated when commands, settings, storage, or permissions change.
