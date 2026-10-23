# Spotify Control Updates

Trusted public update source for the user's Spotify Control installation.

This repository intentionally contains only update metadata and distributable Spotify Control code. It must never contain Spotify account data, browser/profile data, cookies, tokens, PATs, private logs, machine-specific paths, or other secrets.

## Trust model

The installed bootstrap accepts only the `stable` manifest from this repository. The manifest pins an immutable full Git commit SHA. The core payload is stored as a Base64-encoded ZIP text file under that commit so it can be published without a GitHub token or binary release uploader.

Before activation the bootstrap verifies:

1. repository, manifest schema, channel, semantic version and minimum bootstrap version;
2. its own pinned bootstrap SHA-256 and byte size;
3. commit-pinned raw GitHub URLs for the bootstrap and package;
4. encoded package SHA-256 and size;
5. decoded ZIP SHA-256 and size;
6. an exact allowlist of ZIP entries plus every extracted file's SHA-256 and size;
7. a canonical payload-set SHA-256;
8. Windows PowerShell parsing and read-only SelfTest for the staged Spotify Control main and Addon Manager.

Activation uses a same-volume full `bin` directory swap. The previous exact `bin` tree is preserved in both a same-directory old root and a persistent backup until post-activation SelfTest succeeds. Any failed activation restores and verifies the previous exact tree.

Native Spotify updates, Spicetify updates, add-on transactions, and user data remain governed by Spotify Control's separate fail-closed transaction policies.

## Layout

- `manifest.json` - current stable channel manifest
- `manifest.schema.json` - manifest schema
- `bootstrap/spotify-control-self-updater.ps1` - minimal trust/rollback bootstrap
- `packages/vX.Y.Z/spotify-control-core-vX.Y.Z.zip.b64` - versioned Base64 transport containing the managed core files

The bootstrap is versioned separately from Spotify Control. A release that requires a newer bootstrap is blocked by `min_bootstrap_version` rather than replacing the trust bootstrap while it is executing.
