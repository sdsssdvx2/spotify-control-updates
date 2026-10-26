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

The current stable release is Spotify Control v0.6.25 with Addon Manager v0.6.5-r14. The production merge commit is `0bcd84e60b0f03468e37a3f186eabd9f9efda24e`.

v0.6.25 adds read-only exact installed-release provenance for Splitify without adding any Splitify install or mutation authority. The resolver compares the installed Splitify file tree only against a frozen catalog of cryptographically authenticated official `alexander-rebello/splitify` release assets. It never trusts `manifest.version` to infer the installed version. An exact catalog match may report the local release; any extra file, missing file, content drift, unknown tree, or ambiguous tree remains unproven and untouched.

The authenticated provenance catalog currently contains three provable official releases:

- Splitify v1.0.5: asset 7,301 bytes / SHA-256 `c2ecc5e9330035b5c1855f537ea42f85a49705519ccc57e10d121e8b4595fab2`; canonical tree SHA-256 `8c4525b41511fb5a32ad4921fbdbda5c59e0fb613ff0b2f223d0ee295030936a`
- Splitify v1.0.8: asset 8,801 bytes / SHA-256 `03158572d234c1aba14d7b9c53578886c885ffc568f5004dc03346eaa5dc4508`; canonical tree SHA-256 `571722765760ccb98697a50742cfc8e66fae5411f91716794359e483b4383c76`
- Splitify v1.1.0: asset 7,822 bytes / SHA-256 `5de51a885815f78067b8d6f7f3ebe40c93b5a7c7e3c8c841fcd26147a13010ca`; canonical tree SHA-256 `48bace1b6cef325dd1757bf4428e01fd42759a74da20a93fc16ab1ce49132777`

Splitify v1.0.1 remains deliberately unprovable because that stable release exposes no `splitify.zip` asset. Splitify v1.0.4 remains deliberately unprovable because its authenticated asset does not contain the expected install-root `manifest.json`. These releases are not guessed from tags or manifest metadata.

Canonical local-tree ordering is explicit `StringComparer.OrdinalIgnoreCase`, not culture-dependent `Sort-Object`. The exact resolver was validated against authenticated v1.0.5, v1.0.8 and v1.1.0 fixtures under `en-US`, `tr-TR` and `ko-KR`; it produced identical fingerprints in every culture and rejected extra-file, missing-file, content-drift and ambiguous-catalog fixtures. The frozen catalog evidence JSON SHA-256 is `60311e81ae11727528fd5e34879533e1cfacdaaf7b2b21dd1808fb20e3b32454`.

Validation-only PR #79 was closed unmerged after the exact validation head `c08ce018a8424ce39c4e5692443b78a71e010b26` independently passed both push and pull-request CI. The exact production PR #80 head `74d16bffb5fcba03adda1b8b848dca2c1436b406` then passed the v0.6.25 release validator (`40387603088`), the exact Bootstrap 1.0.6 transaction E2E (`40387603204`), and the version-agnostic current-stable validator (`40387603202`). The Bootstrap cycle started from exact v0.6.24/r13, resolved one forward edge, completed RollbackTest back to exact v0.6.24/r13, committed exact v0.6.25/r14, passed managed-script parsing and SelfTests, and finished with an already-current post-Check and zero remaining edges. After production merge, the generic stable validator ran again on merge commit `0bcd84e60b0f03468e37a3f186eabd9f9efda24e` as run `40387966287` and passed every stage.

Automatic mutation authority remains limited to the already-approved installed-only set: `better-local-files`, `eternal-jukebox`, `ivLyrics`, and `playlist-maker`. No v0.6.25 change expands install/update authority. Tagify remains protected monitor-only with `protect-ratings-tags-notes`, Star Ratings remains source-watch-only with `playlist-backed-ratings-preserve`, Splitify remains monitor-only / mutation-denied / `never-auto-install`, unknown sources remain fail-closed for mutation, and SC Cover Ambience remains deny / `never-disable-or-optimize`. RollbackLast remains source-adapter-independent.

The current stable transport source commit is `7c23a470ecf9c83dff5c42caeed03ff20f669072` with payload set SHA-256 `bb6c5f63d3b65fb61f3f03ca64d43060de4508a2b0bb72e77df868c64337079a`. Stable payload identities are:

- Spotify Control v0.6.25: 284,313 bytes / SHA-256 `896bb74e71385b5b6ada118af41cbe9d398dc662ce3719234104028e6eed197f`
- Addon Manager v0.6.5-r14: 282,718 bytes / SHA-256 `25ebd0a5d5158f7d3cb4b4ce2ecf89f05f4dad3ef6bc799599e7204ce103c29c`
- resident agent 0.1.1: 4,855 bytes / SHA-256 `2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278`
- Bootstrap 1.0.6: 42,963 bytes / SHA-256 `d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6`

The v0.6.24/r13 archive-resource-hardening release remains historical predecessor evidence. It introduced fail-closed pre-extraction ZIP validation for Marketplace and pinned Pithaya staging and strengthened ivLyrics archive checks while preserving the already-hardened Spicetify extractor. The v0.6.23/r12 Splitify source-monitor release is the earlier step that identified `alexander-rebello/splitify` while intentionally leaving installed release provenance unresolved. The v0.6.22/r11 adaptive real-PC acceptance v1.0.2 remains earlier predecessor evidence; it exercised exact Bootstrap 1.0.6 from the user's then-installed v0.6.20/r9 baseline through `v0.6.20 -> v0.6.21 -> v0.6.22`, including rollback, commit, protected-surface preservation, and exact restoration of the pre-test tree.

## Version-pinned validator lifecycle

Version-pinned release validators are automatic only while their release branch is active. After a version is promoted to stable, its historical release/E2E workflows are retained on that release branch and, where useful, through `workflow_dispatch`, but they must not continue attaching to future `main` pull requests. One-time exact-main post-release validators are retired after their release has been superseded. This prevents a correct future manifest version bump from creating false-red CI while preserving historical validation evidence.

Machine-specific runtime reports and backups are intentionally not committed to this public repository.
