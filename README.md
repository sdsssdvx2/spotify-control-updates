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

The current stable release is Spotify Control v0.6.27 with Addon Manager v0.6.5-r16. The production merge commit is `ff9f46139dcc5c7d7a2380731b4907711d820bbf`.

v0.6.27 adds read-only exact installed-release provenance for Star Ratings without granting Star Ratings any install, update, or filesystem mutation authority. The authoritative upstream is `brimell/spicetify-star-ratings`. The frozen provenance catalog covers all 13 stable releases from v2.0.0 through v2.1.3; each accepted release has a unique exact `dist/star-ratings.js` byte size, SHA-256, and tag commit. The audit catalog evidence JSON SHA-256 is `2592f43a26c3c49b9d58b8244654d27448d801995465c7c8e4ba8d3159b9aa27`.

Local Star Ratings provenance is deliberately narrow. If the active xpui `sc-star-ratings.js` exactly matches a frozen official release dist identity, that release may be proven directly. If the active file is the already-validated performance-transformed SHA-256 `6e0d1c84408294a619d91191eec83a6d10794ef31093d31ccf1f1bd39ea8c8a3`, the release may be proven only through the existing performance `active-state.json` contract plus its exact bound `original.bin` backup. Missing or forged state, a tampered backup, unknown bytes, or an ambiguous catalog all fail closed to unproven. The Spicetify rescue copy is never used as release provenance.

Star Ratings ratings themselves remain Spotify playlists and are outside the provenance input surface. Browser/Default, IndexedDB, localStorage and other Spotify/Tagify user data are not read by the Star Ratings provenance helpers. The historical production performance trust anchor is release v2.1.3: 43,396 bytes / SHA-256 `198fd7c3307de8f2efc36f40df4e79846188cf35a1d5b550ed3d8ab85e8139b1`. The release audit proved this identity maps uniquely to v2.1.3.

The validation-only source was finalized at head `ac6a89298af835b65d4948ed0587341bb3cc7ff9` with builder blob `99efd34930aca9f463983f801fe91593539017f1`. Validation PR #85 was closed unmerged after push run `40462233405`, independent PR run `40462367886`, and generic stable run `40462367892` all succeeded. The audit run `40460929873` independently re-authenticated all 13 stable release dist files. Validation covered exact active-original provenance, performance-transformed plus exact-original-backup provenance, missing/forged-state and tampered-backup fail-closed behavior, rescue-copy exclusion, unknown/ambiguous fail-closed behavior, the existing immutable Star Ratings performance regression, PowerShell 5.1 parsing, full Addon Manager SelfTest, and no-production-change checks.

The production release branch then independently rebuilt the same candidate and published immutable transport. Preparation run `40462777360` succeeded. The immutable transport source commit is `1bead7959e27c7fff58116c43b8ca8e09a88203e` and the payload set SHA-256 is `d74d39b2f705a6e225e639038390d24027ff32d27cd390a1b82700739bb0f178`.

Before production merge, release-branch validator run `40463183637` and Bootstrap 1.0.6 E2E run `40463224727` both succeeded. Production PR #86 exact head `e339a2d52acff1e525675ff990f4f03183bf4afd` then independently passed all three merge gates: v0.6.27 release validator `40463481006`, v0.6.27 Bootstrap E2E `40463481106`, and generic current-stable validator `40463480998`. After merge, the generic stable validator ran again on production merge commit `ff9f46139dcc5c7d7a2380731b4907711d820bbf` as run `40463682120` and passed every stage.

The Bootstrap E2E used only a synthetic Windows fixture. It started from exact v0.6.26/r15, completed `Check -> RollbackTest -> Update -> main SelfTest -> Addon r16 SelfTest -> post-Check`, restored exact v0.6.26/r15 after RollbackTest, committed exact v0.6.27/r16 on Update, finished already-current with zero remaining edges, and preserved exact released Bootstrap 1.0.6 bytes. Because v0.6.27 changes only read-only provenance and the production update transaction is fully exercised in CI, no separate real-PC mutation acceptance was required.

Automatic mutation authority remains limited to the already-approved installed-only set: `better-local-files`, `eternal-jukebox`, `ivLyrics`, and `playlist-maker`. No v0.6.27 change expands install/update authority. Star Ratings remains `source-watch-only`, `mutation_mode=deny`, `install_mode=marketplace-owned`, and `playlist-backed-ratings-preserve`. Tagify remains monitor-only / mutation-denied / never-auto-install with `protect-ratings-tags-notes`. Splitify remains monitor-only / mutation-denied / never-auto-install. SC Cover Ambience remains mutation-denied with `never-disable-or-optimize`. RollbackLast remains source-adapter-independent. Unknown or new source states remain fail-closed for mutation.

Stable payload identities are:

- Spotify Control v0.6.27: 284,317 bytes / SHA-256 `9eb51ff9e001ebd84fd43532a2b3869f6d61f9b230a8008742119e8892202787`
- Addon Manager v0.6.5-r16: 303,745 bytes / SHA-256 `c8d52542faaf033c0ede8216f71fe2e40d73636bd343d3faf88eb926e5017152`
- resident agent 0.1.1: 4,855 bytes / SHA-256 `2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278`
- Bootstrap 1.0.6: 42,963 bytes / SHA-256 `d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6`

## Predecessor provenance and hardening evidence

v0.6.26/r15 added read-only exact installed-release provenance for Tagify without adding Tagify mutation authority. It accepts only exact file-tree matches from the authenticated identity-marked official release catalog (v2.5.0, v3.0.0, v3.1.0, v3.2.0, v3.3.0, v3.3.1 and v3.3.2), uses explicit `StringComparer.OrdinalIgnoreCase` canonical ordering, and rejects added/missing/changed files, metadata-only version edits and ambiguous matches. Its frozen catalog evidence JSON SHA-256 is `75d66f6e06ec76c8f96fbc7941617e7330844979a87d3297e8e4ff824c3b6a1a`.

v0.6.25/r14 added exact read-only installed-release provenance for authenticated Splitify v1.0.5, v1.0.8 and v1.1.0 trees while keeping Splitify mutation denied. v1.0.1 and v1.0.4 remain deliberately unproven for documented release-asset/layout reasons. Its frozen catalog evidence JSON SHA-256 is `60311e81ae11727528fd5e34879533e1cfacdaaf7b2b21dd1808fb20e3b32454`.

v0.6.24/r13 hardened Marketplace, ivLyrics and Pithaya archive processing with fail-closed pre-extraction validation. v0.6.23/r12 identified the Splitify upstream while intentionally leaving local release provenance unproven. v0.6.22/r11 introduced the generic source/version/rollback adapter layer and remains backed by the earlier real-PC adaptive acceptance that exercised exact Bootstrap 1.0.6 from the user's then-installed v0.6.20/r9 baseline through `v0.6.20 -> v0.6.21 -> v0.6.22`, including rollback, commit, protected-surface preservation and exact restoration of the pre-test tree.

## Version-pinned validator lifecycle

Version-pinned release validators are automatic only while their release branch is active. After a version is promoted to stable, its historical release/E2E workflows remain available on that release branch and through `workflow_dispatch`, but they must not continue attaching automatically to future `main` pull requests. The version-agnostic current-stable validator remains the production guard for the live manifest and transport. This prevents a correct future manifest version bump from creating false-red CI while preserving historical validation evidence.

Machine-specific runtime reports and backups are intentionally not committed to this public repository.
