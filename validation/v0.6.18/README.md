# Spotify Control v0.6.18 validation

This validation fixes a Spicetify backup-provenance bug exposed by Performance Phase 2 v0.3.0.

The trusted Spotify update transaction installs Spotify with `/skip-app-launch`, so Spicetify can copy the newly installed stock `Apps` payload while stamping `[Backup] version` from the still-old `prefs` value `app.last-launched-version`. Later Spotify launch updates `prefs`, causing a metadata-only version mismatch even though the backup bytes came from the new install.

v0.6.18 requirements:

- Never bless an arbitrary stale Spicetify backup by changing its version string alone.
- Existing stale-backup repair is allowed only when the committed Spotify transaction provenance, before/after versions, full version, and `.spa` write-time window prove that the backup was created by that transaction.
- Existing repair changes only `[Backup] version`; it does not run `spicetify apply`, edit Spotify `Apps`, or touch user data.
- Future trusted Spotify updates temporarily pin only `prefs` `app.last-launched-version` to the already-verified candidate full version while `spicetify backup apply --no-restart` runs, then restore the original `prefs` bytes exactly in `finally`.
- All provenance ambiguity remains fail-closed.
- Bootstrap 1.0.6 must prove exact `0.6.17 -> 0.6.18 -> rollback -> 0.6.18` behavior on Windows PowerShell 5.1.

This branch must not be merged until the Windows validation workflow succeeds.