# Addon source adapter registry validation v0.1.0

Validation-only follow-up to production Spotify Control v0.6.21 / Addon Manager v0.6.5-r10.

This candidate does **not** change production files and does **not** grant any new automatic-update authority. It models the next generic source/version/rollback layer on top of the r10 policy registry while keeping mutation authorization exclusively in `Get-AddonMutationAuthorization`.

Validated adapter classes:

- Pithaya `git-commit-tree` -> existing `pithaya` handler only.
- ivLyrics `semver-release-exact-tree` -> existing `ivlyrics` handler only.
- Tagify `semver-release-monitor` -> metadata monitoring only; mutation denied.
- Star Ratings `upstream-head-watch` -> metadata monitoring only; mutation denied.
- Splitify `unresolved-source` -> no source resolution or mutation.
- rescue-copy extensions `owner-cleanup-only` -> external owner only; mutation denied.

Safety invariants:

- automatic mutation authority remains exactly `better-local-files`, `eternal-jukebox`, `ivLyrics`, and `playlist-maker`;
- absent installed-only apps are never auto-installed;
- Tagify ratings/tags/notes remain protected;
- playlist-backed Star Ratings remain protected;
- SC Cover Ambience remains `never-disable-or-optimize`;
- unknown or source/kind/policy-mismatched addons fail closed;
- the generic adapter layer performs no network fetch, archive extraction, filesystem mutation, Spotify launch, or Spicetify command;
- mutation-capable plans delegate network/archive work to the already-existing validated handlers rather than introducing a second extraction path;
- adapter transaction provenance is accepted only for a registry-authorized mutation plan and binds registry fingerprint, adapter id/strategy/source, rollback strategy, and existing mutation handler.

This branch is intended to be closed unmerged after Windows PowerShell 5.1 validation. A future production candidate may integrate the generic routing only after its behavior is independently proven and must still grant no new source automatic authority without a separate release decision.
