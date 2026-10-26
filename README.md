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

The current stable release is Spotify Control v0.6.21 with Addon Manager v0.6.5-r10. Real-PC Windows runtime acceptance completed successfully on 2026-10-26 with acceptance harness v2.0.3 against exact release head `5eac4f39920b84f22e2a5ee07422f6080bfc7ef7`.

The accepted v0.6.21 evidence covered exact Bootstrap 1.0.6 `Check -> RollbackTest -> Update -> post-Check`, a real v0.6.20 -> v0.6.21 one-edge transaction, exact rollback to the prior v0.6.20/r9 tree, a fresh committed v0.6.21/r10 update, and an already-current final check with zero remaining edges. Addon Manager r10 exposed exactly nine registry entries and automatic mutation authority remained limited to the already-approved installed-only set: `better-local-files`, `eternal-jukebox`, `ivLyrics`, and `playlist-maker`. Tagify, Splitify, Star Ratings, SC Cover Ambience, Spotify/Spicetify persistence, Marketplace data, and other protected surfaces remained unchanged. The acceptance harness restored the exact pre-test production tree and exactly one resident process before exit.

The current stable transport source commit is `9a90d5f13eb63023d8f965a004be14d309d99429` with payload set SHA-256 `7bd1bd7559eee615f4e0aa049b3ec1574f6b215dbdf7417a0a57ea99b20b6c55`. Stable payload identities are:

- Spotify Control v0.6.21: 281,579 bytes / SHA-256 `f97c78c905b83e90e58a24035febcaccc27cb12113ae9cbc64acdc79f5853828`
- Addon Manager v0.6.5-r10: 250,616 bytes / SHA-256 `7991b8eaa5a943957aebb9d3dd84d455ed6266430da442a672c05c145fe497a2`
- resident agent 0.1.1: 4,855 bytes / SHA-256 `2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278`
- Bootstrap 1.0.6: 42,963 bytes / SHA-256 `d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6`

The earlier Stage14 hands-off acceptance remains historical evidence for the v0.6.15 -> v0.6.17 chain and its failure-injection coverage; the v0.6.21 acceptance above is the current stable release gate.

## Version-pinned validator lifecycle

Version-pinned release validators are automatic only while their release branch is active. After a version is promoted to stable, its historical release/E2E workflows are retained on that release branch and, where useful, through `workflow_dispatch`, but they must not continue attaching to future `main` pull requests. One-time exact-main post-release validators are retired after their release has been superseded. This prevents a correct future manifest version bump from creating false-red CI while preserving historical validation evidence.

Machine-specific runtime reports and backups are intentionally not committed to this public repository.
