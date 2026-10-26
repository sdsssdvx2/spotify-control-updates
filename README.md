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

## Current stable baseline

Production is Spotify Control **v0.6.21** with Addon Manager **v0.6.5-r10**. The resident agent and Bootstrap are unchanged from the previously accepted production baseline.

- release merge commit: `9391c6489d1af08337338bd1ad8b6c331a1097a8`
- immutable transport source: `9a90d5f13eb63023d8f965a004be14d309d99429`
- payload set SHA-256: `7bd1bd7559eee615f4e0aa049b3ec1574f6b215dbdf7417a0a57ea99b20b6c55`
- Spotify Control v0.6.21: `281579` bytes / SHA-256 `f97c78c905b83e90e58a24035febcaccc27cb12113ae9cbc64acdc79f5853828`
- Addon Manager v0.6.5-r10: `250616` bytes / SHA-256 `7991b8eaa5a943957aebb9d3dd84d455ed6266430da442a672c05c145fe497a2`
- resident agent: `4855` bytes / SHA-256 `2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278`
- Bootstrap v1.0.6: `42963` bytes / SHA-256 `d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6`

The live manifest contains the exact v0.6.20 -> v0.6.21 forward edge for the Spotify Control main script and Addon Manager only. Bootstrap and the resident agent are not replaced by this release.

## Addon mutation policy

Addon Manager r10 uses a declarative mutation-policy registry plus transaction provenance. Automatic mutation authority is intentionally limited to the already accepted installed-only set:

- `ivLyrics`
- `better-local-files`
- `eternal-jukebox`
- `playlist-maker`

Protected or non-authorized addons remain mutation-denied: Tagify preserves ratings/tags/notes, Splitify remains unknown-source, Star Ratings remains source-watch-only with playlist-backed ratings preserved, and SC Cover Ambience is explicitly never disabled or optimized. Unknown addons fail closed. New transactions bind the registry schema, registry identity, source, policy and handler so `CommitLast` rejects registry drift or revoked authorization; rollback remains independent so recovery cannot be blocked by a later policy change.

## Runtime acceptance

The v0.6.21 / r10 release passed hands-off Windows runtime acceptance on **2026-10-26** with acceptance package **v2.0.3**.

The accepted real-PC evidence covered the exact v0.6.20 -> v0.6.21 one-edge Bootstrap 1.0.6 path: initial `Check`, an actual `RollbackTest` ending `rolled-back`, a fresh `Update` ending `committed`, and a post-update `Check` reporting v0.6.21 already current with zero remaining edges. Candidate main and Addon Manager SelfTests passed, the r10 registry exposed exactly nine policy entries with automatic authority limited to the four names above, protected Spotify/Spicetify/addon surfaces remained unchanged, and the exact v0.6.20/r9 baseline plus one resident process was restored after acceptance.

The final acceptance harness avoided the localhost HTTP path that had exposed machine-specific PowerShell web-stack failures in earlier harness revisions. It retained the exact Bootstrap 1.0.6 bytes and supplied only the already validated pinned release manifest to the Bootstrap manifest-fetch call while leaving immutable GitHub HTTPS patch downloads and all Bootstrap size/SHA verification intact.

Machine-specific runtime reports and backups are intentionally not committed to this public repository.

## Version-pinned CI lifecycle

Version-pinned release validators are release evidence, not permanent validators for every future `main` version. After a release is promoted, historical validators must not keep automatic `pull_request -> main` or exact-main triggers that assert an older stable version. Historical release/E2E validators may remain available on their release branch or through `workflow_dispatch`; obsolete one-shot exact-main validators should be retired. This prevents a correct future release from producing false-red CI solely because an older workflow still expects the previous `latest_version`.
