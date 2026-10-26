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

The current stable release is Spotify Control v0.6.24 with Addon Manager v0.6.5-r13. The production merge commit is `bfb733afce2400dd6e484d3dfeba223fe7cd1bfd`.

v0.6.24 is a narrowly scoped archive-resource-hardening release. It adds fail-closed ZIP validation before Marketplace extraction, strengthens the existing ivLyrics ZIP validator, and adds equivalent pre-extraction validation to pinned Pithaya staging. Marketplace archives are capped at 16,384 entries, 128 MiB per entry, and 512 MiB total expanded bytes. ivLyrics remains capped at 4,096 entries and 512 MiB total, now also enforcing a 128 MiB per-entry cap and rejecting symlinks; the historical official-tag zipball self-test now passes through the same validator before extraction. Pithaya archives are capped at 8,192 entries, 128 MiB per entry, and 512 MiB total. All three paths reject unsafe absolute/device/traversal paths, duplicate or case-colliding paths, and Unix symlink entries before `Expand-Archive` runs.

The existing Spicetify archive path was deliberately not rewritten: its manual `ZipFile` extractor already rejects unsafe paths, duplicate/case-colliding names and symlinks, applies a 128 MiB per-entry cap and a 256 MiB total expanded-byte cap, and extracts entries individually only after those checks. The exact Spicetify extractor block was held byte-identical by the v0.6.24 candidate builder.

The release gate was exercised repeatedly on Windows CI. Validation-only PR #74 was closed unmerged after independent push and PR-event validation. The exact production PR #75 head `d1f0e1f1a1be0f913f6fcd051463e49c59e1060b` then passed the release validator (`40378874769`), the exact Bootstrap 1.0.6 transaction E2E (`40378875106`), and the version-agnostic current-stable validator (`40378874923`). The Bootstrap cycle started from exact v0.6.23/r12, resolved one forward edge, rolled back to exact v0.6.23/r12, committed exact v0.6.24/r13, passed managed-script parsing and SelfTests, and finished with `already_current=true` and zero remaining edges. After production merge, the generic stable validator ran again on merge commit `bfb733afce2400dd6e484d3dfeba223fe7cd1bfd` as run `40379160939` and passed every stage.

Malicious ZIP fixtures covered traversal, absolute paths, Windows drive/device-style paths, duplicate/case collisions, Unix symlinks, entry-count bombs, a 129 MiB single entry, and more than 512 MiB total expanded data. Benign fixtures remained accepted. These tests use the exact candidate helper functions rather than a separately reimplemented validator.

Automatic mutation authority remains limited to the already-approved installed-only set: `better-local-files`, `eternal-jukebox`, `ivLyrics`, and `playlist-maker`. No v0.6.24 change expands install/update authority. Tagify remains protected monitor-only with `protect-ratings-tags-notes`, Star Ratings remains source-watch-only with `playlist-backed-ratings-preserve`, Splitify remains monitor-only / mutation-denied with installed content preserved, unknown sources remain fail-closed for mutation, and SC Cover Ambience remains deny / `never-disable-or-optimize`.

The current stable transport source commit is `5597598026c788e32645f31232f40f487f10a2f2` with payload set SHA-256 `07e8519a5e2b0ffd3888e6d9c119e70d5754a7adb81ebdc355ad20ae8260e659`. Stable payload identities are:

- Spotify Control v0.6.24: 284,312 bytes / SHA-256 `dc5d7ec17f18f7546786c81f3172c08f6fb1692842c2e6c0a69a86171e6b1151`
- Addon Manager v0.6.5-r13: 275,414 bytes / SHA-256 `81343687c475f7f48f1311b09c98205a021776f26e8d55082e0ec47f8ebfb470`
- resident agent 0.1.1: 4,855 bytes / SHA-256 `2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278`
- Bootstrap 1.0.6: 42,963 bytes / SHA-256 `d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6`

The v0.6.23/r12 Splitify source-monitor release remains historical predecessor evidence: it identified `alexander-rebello/splitify` while keeping Splitify monitor-only and mutation-denied because installed release provenance could not be proven from the upstream manifest. The v0.6.22/r11 adaptive real-PC acceptance v1.0.2 remains earlier predecessor evidence; it exercised exact Bootstrap 1.0.6 from the user's then-installed v0.6.20/r9 baseline through `v0.6.20 -> v0.6.21 -> v0.6.22`, including rollback, commit, protected-surface preservation, and exact restoration of the pre-test tree. The earlier v0.6.21/r10 v2.0.3 acceptance and Stage14 hands-off acceptance remain older historical evidence for their respective release chains.

## Version-pinned validator lifecycle

Version-pinned release validators are automatic only while their release branch is active. After a version is promoted to stable, its historical release/E2E workflows are retained on that release branch and, where useful, through `workflow_dispatch`, but they must not continue attaching to future `main` pull requests. One-time exact-main post-release validators are retired after their release has been superseded. This prevents a correct future manifest version bump from creating false-red CI while preserving historical validation evidence.

Machine-specific runtime reports and backups are intentionally not committed to this public repository.
