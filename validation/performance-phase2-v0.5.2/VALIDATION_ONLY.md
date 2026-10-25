# Performance Phase 2 v0.5.2 validation only

This branch contains a validation-only silent, Spotify-targeted profiler. It must not be merged into production main.

Contract:
- no global media keys;
- target Spotify's Windows media session directly;
- mute only Spotify audio sessions during workload and restore their original mute/volume state;
- require every recorded NEXT event to be confirmed by Spotify media metadata/position change;
- short 3-transition workload per condition;
- preserve exact v0.5.1 production-alignment, patch eligibility, rollback, xpui/config, persistence, and resident safety contracts;
- production main remains unchanged until clean runtime evidence supports a release decision.
