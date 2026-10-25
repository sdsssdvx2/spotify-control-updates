# Performance Phase 2 v0.5.3 — validation only

DO NOT MERGE this validation branch into production.

Runtime failure fixed from v0.5.2:
- v0.5.2 waited for an existing Spotify CoreAudio session before issuing Play, but paused Spotify can have no render session yet.
- v0.5.3 arms Spotify-only IAudioSessionNotification before Play and immediately mutes newly created Spotify sessions, backed by 5 ms exact-session polling.
- exact original per-session mute and volume state is restored before shutdown.
- no global media key or global audio mute is used.

User-experience contract:
- Spotify startup is hidden.
- during measurement Spotify is deliberately not minimized/fully hidden because Electron/Chromium occlusion/background throttling can change renderer measurements.
- instead the normal Spotify window is shown without activation and placed at the bottom of the Z-order behind the user's foreground app.
- other apps/audio are not controlled or muted.

Final deterministic identity:
- package: 126,853 bytes
- package SHA-256: b7aea344cd9a67c0b46886b41118bc3a33c76d2a2d7d6c8facdfa284b5baea43
- integrated profiler PS1: 108,497 bytes
- PS1 SHA-256: 73793f14137b0eb8c2f008f5990e984f40650d4b566a974a30411cdfad94be84

Production main baseline remains 6e2dd5cec54ca795457935d6bee83f63d39722bf.
