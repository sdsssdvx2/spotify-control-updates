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

The current stable release is Spotify Control v0.6.23 with Addon Manager v0.6.5-r12. The production merge commit is `9ac7a5722b606e1cbda11905747b60bfa751e6f4`.

v0.6.23 is a non-mutating Splitify source-monitor release. It identifies the verified public upstream `alexander-rebello/splitify` and its pinned stable `v1.1.0` release asset (`splitify.zip`, 7,822 bytes, GitHub-published SHA-256 `5de51a885815f78067b8d6f7f3ebe40c93b5a7c7e3c8c841fcd26147a13010ca`) while deliberately treating the installed Splitify release provenance as unproven because the upstream v1.1.0 manifest still declares version 1.0.0. Splitify therefore remains `monitor-only`, `mutation_mode=deny`, and `never-auto-install`; it has no archive extraction, file mutation, process launch, Spicetify command, update, or reinstall route.

The v0.6.23 release gate was completed on Windows CI at the exact production PR head. Independent release validation, the version-agnostic current-stable validator, and the exact Bootstrap 1.0.6 E2E all passed. The Bootstrap E2E started from an exact v0.6.22/r11 installed fixture and executed `Check -> RollbackTest -> Update -> post-Check`: Check resolved exactly one forward edge, RollbackTest restored the exact v0.6.22/r11 tree, Update committed exact v0.6.23/r12, full Spotify Control and Addon Manager SelfTests passed in the complete installed fixture, and the final Check reported `already_current=true` with zero remaining edges. Because the new Splitify behavior itself has no mutation/install authority and the production self-update transaction was fully exercised in that Windows fixture, no additional user-PC mutation acceptance was required for this release.

Automatic mutation authority remains limited to the already-approved installed-only set: `better-local-files`, `eternal-jukebox`, `ivLyrics`, and `playlist-maker`. Tagify remains protected monitor-only, Star Ratings remains source-watch-only with playlist-backed ratings preserved, and SC Cover Ambience remains deny / `never-disable-or-optimize`. The r12 registry change also preserves already-prepared r11 managed transactions only for the exact prior registry fingerprint, with every change reauthorized against the current registry/source adapter; tampered sources and arbitrary historical fingerprints remain fail-closed.

The current stable transport source commit is `ac895090c6db586e16089f143e6d494f74cab124` with payload set SHA-256 `a0c61cec440b9a2143cf2b564f4d6907453f52acbcd2bc145010b32078e83326`. Stable payload identities are:

- Spotify Control v0.6.23: 281,588 bytes / SHA-256 `bc9861bdd64ff8af94f68f0f065739f82b235271dcd18ad6325b819205528a08`
- Addon Manager v0.6.5-r12: 272,494 bytes / SHA-256 `23ad2210aea4352f535d1cf0b3ebb827a82200dcba2b70bf1ebae96499d82687`
- resident agent 0.1.1: 4,855 bytes / SHA-256 `2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278`
- Bootstrap 1.0.6: 42,963 bytes / SHA-256 `d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6`

The v0.6.22/r11 adaptive real-PC acceptance v1.0.2 remains historical predecessor evidence. It successfully exercised exact Bootstrap 1.0.6 from the user's then-installed v0.6.20/r9 production baseline through two forward edges (`v0.6.20 -> v0.6.21 -> v0.6.22`), including rollback, commit, protected-surface preservation, and exact restoration of the pre-test tree. The earlier v0.6.21/r10 v2.0.3 acceptance and Stage14 hands-off acceptance remain older historical evidence for their respective release chains.

## Version-pinned validator lifecycle

Version-pinned release validators are automatic only while their release branch is active. After a version is promoted to stable, its historical release/E2E workflows are retained on that release branch and, where useful, through `workflow_dispatch`, but they must not continue attaching to future `main` pull requests. One-time exact-main post-release validators are retired after their release has been superseded. This prevents a correct future manifest version bump from creating false-red CI while preserving historical validation evidence.

Machine-specific runtime reports and backups are intentionally not committed to this public repository.
