# Roadmap

This roadmap keeps future work aligned with the project's constraints: small executable, low idle power, local-first storage, native macOS UI, and no feature regressions.

## Near Term

- Add an idle power measurement note using Instruments or Activity Monitor alongside `scripts/idle-soak-report.sh`.
- Add tagged release notes once a first public version is cut.

## Privacy And Security

- Keep improving secure cleanup semantics for cleared cache/history/key material where macOS storage behavior allows it.
- Keep the current no-telemetry posture. Keep remote movement limited to explicit user-controlled sync/export paths.
- Add encrypted archive and iCloud-sync payload options before treating sync archives as safe for high-risk clipboard history.

## Product Polish

- Improve keyboard focus states and VoiceOver labels.
- Consider optional password-protected archive exports if migration needs outgrow owner-only local archive files.
- Design true shared Pinboard collaboration separately from private iCloud archive sync.

## Performance

- Keep measuring binary size after each feature.
- Avoid continuous background file scans.
- Revisit polling intervals only with measured idle wakeup evidence.
- Keep image decoding lazy and cache bounded.
