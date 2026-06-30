# Roadmap

This roadmap keeps future work aligned with the project's constraints: small executable, low idle power, local-only storage, native macOS UI, and no feature regressions.

## Near Term

- Add an idle power measurement note using Instruments or Activity Monitor alongside `scripts/idle-soak-report.sh`.
- Add tagged release notes once a first public version is cut.

## Privacy And Security

- Keep improving secure cleanup semantics for cleared cache/history/key material where macOS storage behavior allows it.
- Keep the current no-network/no-telemetry posture unless the project explicitly changes direction.

## Product Polish

- Improve keyboard focus states and VoiceOver labels.
- Add a compact mode for narrower displays.
- Add import/export only if the storage and privacy story remains clear.

## Performance

- Keep measuring binary size after each feature.
- Avoid continuous background file scans.
- Revisit polling intervals only with measured idle wakeup evidence.
- Keep image decoding lazy and cache bounded.
