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

The current stable release is Spotify Control v0.6.22 with Addon Manager v0.6.5-r11. Real-PC Windows runtime acceptance completed successfully on 2026-10-27 with adaptive acceptance harness v1.0.2 against exact release head `9c1cabcaaed6c7a1465f5baea12d046a5d51c8dc`; the production merge commit is `0538f4e9adef922b635c654a9e259f5e83400634`.

The accepted v0.6.22 evidence covered exact Bootstrap 1.0.6 `Check -> RollbackTest -> Update -> post-Check` from the user's exact v0.6.20/r9 production baseline. The initial Check resolved exactly two forward edges (`v0.6.20 -> v0.6.21 -> v0.6.22`), RollbackTest restored the exact v0.6.20/r9 tree, Update committed exact v0.6.22/r11, and the final Check reported `already_current=true` with zero remaining edges. Addon Manager r11 exposed exactly nine registry entries and automatic mutation authority remained limited to the already-approved installed-only set: `better-local-files`, `eternal-jukebox`, `ivLyrics`, and `playlist-maker`. Tagify, Splitify, Star Ratings, SC Cover Ambience, Spotify/Spicetify persistence, Marketplace data, and other protected surfaces remained unchanged. The acceptance harness restored the exact pre-test v0.6.20/r9 production tree and exactly one resident process before exit.

The current stable transport source commit is `db4dd0e4357cbf03ea95dd8773c0be173b2c91fc` with payload set SHA-256 `cb396442ac874504a04d4acb0034d3cb9fa11acce290da18e639c2dbe8e5a091`. Stable payload identities are:

- Spotify Control v0.6.22: 281,586 bytes / SHA-256 `b5ba4dc98b10ea922ce30401b5cddf5a1ab01171366e09b3546ce3cc6fcd80fe`
- Addon Manager v0.6.5-r11: 268,670 bytes / SHA-256 `0ee8d30bf7c2fda9d0d8d112b7191b0d0439a1071d284d0cc04a87fe8937c7bc`
- resident agent 0.1.1: 4,855 bytes / SHA-256 `2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278`
- Bootstrap 1.0.6: 42,963 bytes / SHA-256 `d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6`

The v0.6.21/r10 v2.0.3 acceptance remains historical predecessor evidence for the one-edge v0.6.20 -> v0.6.21 release. The earlier Stage14 hands-off acceptance remains historical evidence for the v0.6.15 -> v0.6.17 chain and its failure-injection coverage; the v0.6.22 acceptance above is the current stable release gate.

## Version-pinned validator lifecycle

Version-pinned release validators are automatic only while their release branch is active. After a version is promoted to stable, its historical release/E2E workflows are retained on that release branch and, where useful, through `workflow_dispatch`, but they must not continue attaching to future `main` pull requests. One-time exact-main post-release validators are retired after their release has been superseded. This prevents a correct future manifest version bump from creating false-red CI while preserving historical validation evidence.

Machine-specific runtime reports and backups are intentionally not committed to this public repository.
