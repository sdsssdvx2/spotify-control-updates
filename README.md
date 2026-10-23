# Spotify Control Updates

Trusted public update source for the user's Spotify Control installation.

This repository intentionally contains only update metadata and distributable Spotify Control code. It must never contain Spotify account data, browser/profile data, cookies, tokens, PATs, private logs, machine-specific paths, or other secrets.

## Trust model

The installed bootstrap updater accepts only manifests from this repository. Update packages are pinned to an immutable Git commit URL and must match the manifest's SHA-256, byte size, protocol version, and per-file SHA-256 values before staging. The staged candidate must pass Windows PowerShell parsing and Spotify Control read-only self-tests before atomic activation. A failed activation restores the previous exact code snapshot and verifies rollback.

Native Spotify updates, Spicetify updates, add-on transactions, and user data remain governed by Spotify Control's separate fail-closed transaction policies.

## Layout

- `manifest.json` - current stable channel manifest
- `manifest.schema.json` - manifest schema
- `packages/` - immutable versioned update payloads referenced by commit-pinned raw URLs

The bootstrap updater is deliberately small and versioned separately from Spotify Control. A release that requires a newer bootstrap is blocked by `min_bootstrap_version` instead of replacing the bootstrap while it is executing.
