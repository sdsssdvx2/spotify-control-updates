# Spotify Control CSS Provenance Collector v0.1.0

Validation-only tool for the next Performance Phase 2 step. It captures the exact active Spicetify CSS bytes needed to optimize `user.css` / `colors.css` without guessing or changing the user's visual setup.

The collector is validated under Windows PowerShell 5.1, matching the user's production scripting environment.

## What it reads

- `%APPDATA%\Spotify\Apps\xpui\user.css`
- `%APPDATA%\Spotify\Apps\xpui\colors.css`
- `%APPDATA%\Spotify\Apps\xpui\index.html` only to extract lines mentioning `user.css` / `colors.css`
- `%APPDATA%\spicetify\config-xpui.ini` only to extract `current_theme`, `color_scheme`, `inject_css`, `replace_colors`, `overwrite_assets`
- the selected theme's `user.css` and `color.ini`, when present
- hashes/sizes of Spotify Control production components, read-only

Spicetify 2.46.2 itself creates `user.css` and `colors.css` directly in active `xpui`; the collector treats those exact active bytes as authoritative.

## What it never reads or changes

- Spotify `Browser`, `Default`, `Users`, prefs, localStorage, IndexedDB
- Star Ratings playlist data
- ivLyrics, Tagify, Splitify, SC Cover Ambience, Marketplace, extensions/custom-app payloads
- Spotify process state
- Spicetify configuration or commands

It does not invoke `spicetify apply`, `backup`, `restore`, or `config`; does not stop/start Spotify; and does not mutate active/theme source files. Source files are hashed before and after capture and the run fails if any source identity changes.

## Output

Run `RUN_CSS_PROVENANCE_COLLECTOR.cmd` normally. Spotify may stay open.

Latest output is under:

`%LOCALAPPDATA%\SpotifyControl\reports\css-provenance-v010\`

Upload `SpotifyControl-CSS-Provenance-v0.1.0-latest.zip` after the run. The archive contains exact CSS/theme-source copies when present, sanitized theme settings, CSS-link excerpts, SHA-256 identities, encoding/line-ending metadata, and static counts for potentially expensive CSS constructs.
