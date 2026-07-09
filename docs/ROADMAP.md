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

- Keep keyboard focus, VoiceOver descriptions, Command-click category unions, and context-menu parity covered as the side-rail shelf evolves.
- Validate motion, cross-display placement, and card expansion on each supported macOS release, including the system Reduce Motion path.
- Consider optional password-protected archive exports if migration needs outgrow owner-only local archive files.
- Design true shared Pinboard collaboration separately from private iCloud archive sync.

## Performance

- Keep measuring binary size after each feature.
- Avoid continuous background file scans.
- Revisit polling intervals only with measured idle wakeup evidence.
- Track asynchronous preview latency and viewport materialization under large histories.
- Keep card-thumbnail decoding and user-triggered image transforms off the main thread, with bounded queues and caches.
