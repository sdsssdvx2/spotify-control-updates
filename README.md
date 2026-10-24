# Spotify Control Updates

Trusted public update metadata for Spotify Control.

This repository must never contain Spotify account/profile data, cookies, tokens, PATs, private logs, or machine-specific secrets.

## Trust model

The Windows bootstrap is installed out-of-band and is intentionally separate from the managed `bin` directory. It reads only `manifest.json` from this repository. The manifest pins an immutable full Git commit SHA and describes strictly forward version edges.

For each edge the bootstrap requires the currently installed file SHA-256 to match the edge's `from_sha256`. Patch transport is split into small commit-pinned ASCII chunks. Before applying a patch the bootstrap verifies every chunk SHA-256 and size, then verifies the reassembled Base64 and decoded gzip. `gzip-base64-chunks` applies a hashed JSON line-patch to supported text files; `gzip-base64-full-file` expands directly to a staging file and verifies its exact target size and SHA-256, allowing CRLF/non-ASCII managed files without passing binary bytes through the PowerShell pipeline. The staged result must match the edge's exact `to_sha256`.

Before activation the complete staged managed payload must match `latest_files` and the canonical `payload_set_sha256`, and both Spotify Control and Addon Manager must pass Windows PowerShell parsing plus read-only SelfTest. Activation uses a same-volume full-`bin` directory swap. A persistent exact backup and the same-volume old root remain available until post-activation verification succeeds. Any failed activation restores and verifies the exact previous tree.

The bootstrap does not update itself while running. A release that requires a newer bootstrap is rejected by `min_bootstrap_version` and requires an out-of-band bootstrap update.

## Stable channel

- `manifest.json` - live stable manifest
- `manifest.schema.json` - manifest contract
- `packages/vX.Y.Z/...` - immutable patch chunks referenced through `source_commit`

Unreferenced experimental or superseded transport files are not trusted. Only paths and hashes explicitly listed by the current manifest are accepted.

## Runtime acceptance

Stage14 hands-off Windows runtime acceptance completed successfully on 2026-10-25 with acceptance package v1.4.1 against the stable v0.6.17 / Addon Manager v0.6.5-r7 payload.

The accepted runtime evidence covered the chained v0.6.15 -> v0.6.16 -> v0.6.17 self-update rollback test and fresh commit, exact target hashes, Windows-native Marketplace/Pithaya/installed-only-ivLyrics failure-injection rollback sandboxes, running-state check-only behavior, SpotifyExit unattended maintenance, actionable-pending drain to zero, protected Spotify/Spicetify data preservation, native Spotify updater blocking, resident mutation arming, single-instance persistence, and console-free managed launch.

The production bootstrap remains v1.0.6. The stable source anchor for the repaired v0.6.15 -> v0.6.17 transport is `36b15a2ed2f9a23fffbeaf91de78b7854f6108b2`, with payload set SHA-256 `0f7fe384630e027466aa734ac669b410774b4569db231982212b7fa565b691a0`.

Machine-specific runtime reports and backups are intentionally not committed to this public repository.
