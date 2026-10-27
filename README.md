# Spotify Control Updates

Trusted public update metadata for Spotify Control.

This repository must never contain Spotify account/profile data, cookies, tokens, PATs, private logs, machine-specific secrets, or raw real-PC diagnostic reports.

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

The current stable release is **Spotify Control v0.6.28 with Addon Manager v0.6.5-r17**. The production merge commit is `41a361843e885919e316ec440d5066e6139675fb`.

v0.6.28 adds read-only exact official Git commit-snapshot provenance for SC Cover Ambience. It does **not** grant SC Cover Ambience install, update, cleanup, migration, disable, optimization, or other mutation authority. The authoritative upstream is `Theblockbuster1/spicetify-extensions`, source path `CoverAmbience/CoverAmbience.js`.

The frozen provenance catalog contains 35 unique official source snapshots. The catalog payload SHA-256 is `c12391e57a393d37d70ffd7a984bdbb6af9f4a83cf3c2b0a8c9bf040247c731f`. The current authenticated snapshot is commit `9454b55e454fb354ecedcf3f72c5a4f0a9671651`, 10,267 bytes, SHA-256 `0aea69246e14156b22a10261af07b84f3abc58bed4368e03f740ed76db329738`.

Local provenance is deliberately fail-closed. The resolver fingerprints only the supported local source/active SC Cover Ambience script paths. All present local files must match one and the same frozen official size+SHA-256 snapshot before a commit is proven. Unknown bytes, reparse points, conflicting official snapshots, ambiguous catalog matches, or a future upstream head outside the frozen catalog remain monitoring-only/unproven. The provenance helpers do not read Spotify Browser/Default IndexedDB or localStorage and do not modify Marketplace state, Spicetify config, Spotify user data, or any extension file.

A one-shot read-only real-PC collector established that Marketplace installed state and persistent `sc-cover-ambience.js` configuration coexist (`dual-owned-risk`). Both the local source copy and active xpui copy exactly matched the current official snapshot. The raw report is intentionally not committed; only its identity and non-sensitive conclusions are pinned in validation metadata: 16,730 bytes / SHA-256 `7349326c6567806f6c45bacb741d32649a6afc424b797d7249358cd9b8f5b38b`. This evidence explicitly keeps `safe_to_expand_mutation_authority=false`, `safe_to_auto_remove_direct_copy=false`, and `disable_or_optimize=false`.

SC Cover Ambience therefore remains exactly `inventory_policy=rescue-copy-cleanup-only`, `mutation_mode=deny`, `install_mode=recovery-owned`, `version_strategy=owner-cleanup-only`, `rollback_strategy=external-owner`, and `data_policy=never-disable-or-optimize`. The observed dual ownership is monitored, not automatically normalized.

Validation-only PR #93 was closed unmerged after exact head `f8ed342f0f414abba3d2a42f93720057ae8b55e5` passed the SC Cover Ambience candidate run `40503043002` and generic current-stable run `40503042928`. The validated builder is pinned by exact Git blob `a52961092730a3216ea2d4b4dceaaa814f33ce4e`. The source-history audit PR #91 and one-shot collector PR #92 were also closed unmerged after successful independent CI.

The production release branch then independently rebuilt the validated candidate and froze immutable transport. Preparation run `40503709545` succeeded. The immutable transport source commit is `bb6d90146f20b73d36fbf8cb813f1b190f403c48`, and the payload set SHA-256 is `4be96c5d41c2160ed9ac96001b469998595629232929b82c8b0f34b11fda3b43`.

Before the production PR, release-branch validator run `40504188398` and Bootstrap 1.0.6 E2E run `40504234635` succeeded. Production PR #94 exact head `7042a6274411da0f6279fcbbab5d6e5d18c3d82a` then independently passed all three merge gates: v0.6.28 release validator `40504482442`, v0.6.28 Bootstrap E2E `40504482434`, and generic current-stable validator `40504482544`. After merge, the generic stable validator ran again on production merge commit `41a361843e885919e316ec440d5066e6139675fb` as run `40504671754` and passed every stage.

The Bootstrap E2E used only a synthetic Windows fixture. It started from exact v0.6.27/r16, completed `Check -> RollbackTest -> Update -> main SelfTest -> Addon r17 SelfTest -> post-Check`, restored exact v0.6.27/r16 after RollbackTest, committed exact v0.6.28/r17 on Update, finished already-current with zero remaining edges, and preserved exact released Bootstrap 1.0.6 bytes.

Automatic mutation authority remains limited to the already-approved installed-only set: `better-local-files`, `eternal-jukebox`, `ivLyrics`, and `playlist-maker`. v0.6.28 does not expand install/update authority. Star Ratings remains `source-watch-only`, `mutation_mode=deny`, `install_mode=marketplace-owned`, and `playlist-backed-ratings-preserve`; its existing `star-ratings-observer-debounce-v1` performance transform and rollback contract remain unchanged. Tagify remains monitor-only / mutation-denied / never-auto-install with `protect-ratings-tags-notes`. Splitify remains monitor-only / mutation-denied / never-auto-install. RollbackLast remains source-adapter-independent. Unknown or new source states remain fail-closed for mutation.

Stable payload identities are:

- Spotify Control v0.6.28: 284,321 bytes / SHA-256 `af1582ec335807f8f5daa9b3a65b13d567264f326d3c608c082ae02ff0a4cfc0`
- Addon Manager v0.6.5-r17: 323,385 bytes / SHA-256 `5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285`
- resident agent 0.1.1: 4,855 bytes / SHA-256 `2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278`
- Bootstrap 1.0.6: 42,963 bytes / SHA-256 `d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6`

## Predecessor provenance and hardening evidence

v0.6.27/r16 added read-only exact installed-release provenance for Star Ratings while preserving `playlist-backed-ratings-preserve` and the validated performance transform. Its frozen release catalog covers 13 stable releases from v2.0.0 through v2.1.3; catalog evidence SHA-256 `2592f43a26c3c49b9d58b8244654d27448d801995465c7c8e4ba8d3159b9aa27`.

v0.6.26/r15 added read-only exact installed-release provenance for Tagify without adding mutation authority. It accepts only exact authenticated identity-marked official release trees and keeps `protect-ratings-tags-notes`. Its frozen catalog evidence JSON SHA-256 is `75d66f6e06ec76c8f96fbc7941617e7330844979a87d3297e8e4ff824c3b6a1a`.

v0.6.25/r14 added exact read-only installed-release provenance for authenticated Splitify v1.0.5, v1.0.8 and v1.1.0 trees while keeping Splitify mutation denied. Its frozen catalog evidence JSON SHA-256 is `60311e81ae11727528fd5e34879533e1cfacdaaf7b2b21dd1808fb20e3b32454`.

v0.6.24/r13 hardened Marketplace, ivLyrics and Pithaya archive processing with fail-closed pre-extraction validation. v0.6.23/r12 identified the Splitify upstream while intentionally leaving local release provenance unproven. v0.6.22/r11 introduced the generic source/version/rollback adapter layer and remains backed by the earlier real-PC adaptive acceptance that exercised exact Bootstrap 1.0.6 through multiple update edges, rollback, commit, protected-surface preservation, and exact restoration of the pre-test tree.

## Version-pinned validator lifecycle

Version-pinned release validators are automatic only while their release branch is active. After a version is promoted to stable, its historical release/E2E workflows remain available on that release branch and through `workflow_dispatch`, but they must not continue attaching automatically to future `main` pull requests. The version-agnostic current-stable validator remains the production guard for the live manifest and transport. This prevents a correct future manifest version bump from creating false-red CI while preserving historical validation evidence.

Machine-specific runtime reports and backups are intentionally not committed to this public repository.
