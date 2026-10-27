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

The current stable release is Spotify Control v0.6.26 with Addon Manager v0.6.5-r15. The production merge commit is `3bc27518cb2d44613a2343c52cefc6a36b70013a`.

v0.6.26 adds read-only exact installed-release provenance for Tagify without adding any Tagify install or mutation authority. The resolver fingerprints only the resolved Tagify install-source directory and accepts a local release only when that file tree exactly matches a frozen catalog entry derived from a cryptographically authenticated official `alexk218/tagify` release asset. Package or manifest version strings are not trusted to prove the local release. An unknown release, extra file, missing file, changed file, metadata-version-only edit, or ambiguous catalog match remains unproven and untouched.

The authenticated identity-marked Tagify provenance catalog contains seven official releases:

- Tagify v2.5.0: asset 494,087 bytes / SHA-256 `5a47106d50b08aa377a3402258dee94db63797360e21dccf59f81f0827fcaccc`; canonical tree SHA-256 `3b5ba1c33e4415fe530a029fd93af8f0fc84748eb2ac432422f31747a40c28dc`
- Tagify v3.0.0: asset 909,371 bytes / SHA-256 `ee04ec7eeb45054b798337ccd9e08f66a2cc881348f74b7a4d2adfbc93ef07b1`; canonical tree SHA-256 `ac6d7f7567d78cbfbb37df40dc3d76273df3dde80f0962efaea3a217dcba99d0`
- Tagify v3.1.0: asset 1,355,380 bytes / SHA-256 `a84b9c2aefd43035b16edf537b91652b934c09f1ef5037ed17b3738f1e4ecc91`; canonical tree SHA-256 `f896dc5f83acd8272315aa171ea7893d744dc029422b15574da9c60190750c4e`
- Tagify v3.2.0: asset 1,436,949 bytes / SHA-256 `346f0e746abf3e29aca754240da2e9d2c87e75d7e35fd27109575fed66629c31`; canonical tree SHA-256 `516f364e8519983ae1bd64158b552a3bb68ed54414402e4ab9523f3e6abe1559`
- Tagify v3.3.0: asset 1,470,208 bytes / SHA-256 `12f2efc0221014464eff2d5884a83bd05882138e87bcd0c208e734538c71604c`; canonical tree SHA-256 `108e8afba7bcab8cfe8657431041a0118140a774ba4996e60ce91cfa8a4cf2d9`
- Tagify v3.3.1: asset 1,471,676 bytes / SHA-256 `b7510e525297c297d6007305acef947c35bf2df34e0fae492c41a31f555db957`; canonical tree SHA-256 `8f8abd6f80f88321d6517c1496c985da146e313a949e80f4e4b41c34ad27178a`
- Tagify v3.3.2: asset 1,554,948 bytes / SHA-256 `5261538c8f596cf179b1f6efd20e0a0a60c73b4cd765115fc6bc25c6a6b3b76b`; canonical tree SHA-256 `e751c2692d0edb5d63ac359df0b81c024ddca4f02e9de46cd5e4d8f3266bbf71`

Older stable Tagify releases are deliberately not guessed. v1.0.0, v1.0.1, v1.0.2, v2.0.0, v2.1.0 and v2.1.1 expose no exact release ZIP suitable for this proof. v2.1.2, v2.2.0, v2.3.0 and v2.4.0 have authenticated ZIP bytes but their archived install trees lack an explicit Tagify identity marker, so they are also excluded from exact local provenance. The frozen catalog evidence JSON SHA-256 is `75d66f6e06ec76c8f96fbc7941617e7330844979a87d3297e8e4ff824c3b6a1a`.

Canonical local-tree ordering is explicit `StringComparer.OrdinalIgnoreCase`, not culture-dependent `Sort-Object`. Validation re-authenticated all seven accepted official assets, reproduced their exact file-tree fingerprints, proved identical results under `en-US`, `tr-TR` and `ko-KR`, and rejected added-file, missing-file, content-drift, package-version-only tampering and ambiguous-catalog fixtures. The provenance helpers themselves perform no network fetch, archive extraction, process launch, Spicetify mutation, file mutation, or Tagify localStorage/IndexedDB access.

Validation-only PR #82 was closed unmerged after exact head `91980963f1bd7cca987a3fc15c0a70074ea72c08` independently passed push validation (`40453161373`), pull-request validation (`40453275598`) and the generic current-stable validator (`40453275661`). The validated Tagify candidate builder is pinned by exact Git blob `6988eff6b99266ed4601db31c8984d83bc11c44e`; the earlier release-asset audit run `40388895760` also passed independently.

The exact production PR #83 head `b85c8705597706baa61d14dbf9685336644f27ca` then passed the v0.6.26 release validator (`40454611099`), the exact Bootstrap 1.0.6 transaction E2E (`40454611100`), and the version-agnostic current-stable validator (`40454611111`). The Bootstrap cycle started from exact v0.6.25/r14, resolved the single forward edge, completed RollbackTest back to exact v0.6.25/r14, committed exact v0.6.26/r15, passed managed-script parsing and SelfTests, and finished with an already-current post-Check and zero remaining edges while preserving exact Bootstrap bytes. After production merge, the generic stable validator ran again on merge commit `3bc27518cb2d44613a2343c52cefc6a36b70013a` as run `40454801578` and passed every stage.

Automatic mutation authority remains limited to the already-approved installed-only set: `better-local-files`, `eternal-jukebox`, `ivLyrics`, and `playlist-maker`. No v0.6.26 change expands install/update authority. Tagify remains protected monitor-only with `mutation_mode=deny`, `install_mode=never-auto-install` and `protect-ratings-tags-notes`. Splitify remains monitor-only / mutation-denied / never-auto-install with exact release provenance retained from v0.6.25. Star Ratings remains source-watch-only with `playlist-backed-ratings-preserve`; unknown sources remain fail-closed for mutation; SC Cover Ambience remains deny / `never-disable-or-optimize`; RollbackLast remains source-adapter-independent.

The current stable transport source commit is `1dcaf6ea9a32d2f9b3116993f9d08374b612f1e2` with payload set SHA-256 `172321533fc3147835b8ec79c8869d7c5e0f56dec6fb6bd5a8af963f412e5131`. Stable payload identities are:

- Spotify Control v0.6.26: 284,311 bytes / SHA-256 `d7b484a2a7b10a27db0f182d71fe36f590784171db7208189540045bcf4f54d1`
- Addon Manager v0.6.5-r15: 291,294 bytes / SHA-256 `4aa56dd5d4ef07da21d3bdf5c76227fabb49c64767a281b1e11ee48e7211a09f`
- resident agent 0.1.1: 4,855 bytes / SHA-256 `2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278`
- Bootstrap 1.0.6: 42,963 bytes / SHA-256 `d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6`

The v0.6.25/r14 Splitify provenance release remains direct predecessor evidence. It introduced exact read-only installed-release provenance for authenticated Splitify v1.0.5, v1.0.8 and v1.1.0 trees while keeping Splitify mutation denied; v1.0.1 and v1.0.4 remain deliberately unproven for the documented asset-layout reasons. The v0.6.24/r13 archive-resource-hardening release remains earlier predecessor evidence for fail-closed Marketplace, ivLyrics and Pithaya archive validation. The v0.6.23/r12 release identified the Splitify upstream while intentionally leaving installed release provenance unresolved. The v0.6.22/r11 adaptive real-PC acceptance v1.0.2 remains earlier predecessor evidence; it exercised exact Bootstrap 1.0.6 from the user's then-installed v0.6.20/r9 baseline through `v0.6.20 -> v0.6.21 -> v0.6.22`, including rollback, commit, protected-surface preservation, and exact restoration of the pre-test tree.

## Version-pinned validator lifecycle

Version-pinned release validators are automatic only while their release branch is active. After a version is promoted to stable, its historical release/E2E workflows are retained on that release branch and, where useful, through `workflow_dispatch`, but they must not continue attaching to future `main` pull requests. One-time exact-main post-release validators are retired after their release has been superseded. This prevents a correct future manifest version bump from creating false-red CI while preserving historical validation evidence.

Machine-specific runtime reports and backups are intentionally not committed to this public repository.
