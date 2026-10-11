# Security

The main development branch is supported until tagged releases exist. Report vulnerabilities privately to the maintainer listed in the repository profile. Include the commit/version, macOS version, reproduction steps, expected/actual behavior, and affected clipboard/files/permissions. Do not publish exploit details or sensitive clipboard examples in an issue.

## Boundaries

History is local by default. There is no telemetry, shell/process execution, or Apple Events scripting. Explicit web previews load the selected HTTP(S) URL in a non-persistent WebKit view; sites receive normal request metadata. Optional iCloud moves portable archives through the app-private ubiquity container when enabled and entitled.

SQLite uses bound statements. Textual fields and managed image, rich-text, audio, video, and PDF bytes use AES-GCM. Keychain access is noninteractive and bounded; an owner-only local fallback key keeps capture working if Keychain is unavailable. Storage directories use mode 0700 and files/exports use 0600 where supported. Full history clear resets stored key state after the database clear succeeds. Local builds have ad-hoc hardened-runtime signatures; distribution requires Developer ID and notarization.

Identifiers, kinds, timestamps, pin state, and use counts are not encrypted. The fallback key does not protect data from a process that can read the whole Application Support directory. Unavailable encryption providers can leave plaintext; old plaintext rows/sidecars migrate when encryption becomes available. Snapshots, backups, filesystem remnants, and another process's copies are outside cleanup guarantees.

Preview/open/reveal may create decrypted temporary files under `/tmp/ClipBored/Previews`; stale files are removed at launch, cache/history clear, and quit. Cache cleanup removes disposable thumbnails and retains original copied images; deleting clips removes only references inside app-owned storage. Sufficient filesystem permissions can expose live previews and keys.

Exports and iCloud archives are **unencrypted sensitive backups**. They include metadata and recoverable managed attachment bytes. External file references remain path-based. Sync exchanges whole archives; it has no cross-device conflict resolution, end-to-end archive encryption, or shared Pinboard access control.

Sensitive exclusion is heuristic: private keys, bearer/API tokens (GitHub, Slack, AWS, Stripe, OpenAI, Google), JWTs, valid credit-card-like numbers, high-entropy secrets, common assignments, and source-aware OTPs. It can miss new formats or reject ordinary text. Common password managers/authenticators are ignored by default. OCR is local and opt-in, but recognized text can itself be sensitive.

Accessibility permits automatic paste simulation; capture works without it. Screen privacy covers the shelf window, not the system clipboard, other apps, or persisted history. Self-written pasteboard changes are marked to avoid recapture.

## Review priorities

Keep networking limited to explicit previews and private archive sync. Review new paths for ownership and encryption, and run [validation](docs/MAINTENANCE.md). Before expanding sync or advertising stronger security, address archive/capture concurrency and key rotation during in-flight captures. Add encrypted archives and measured conflict handling; never promise secure erasure on macOS storage.
