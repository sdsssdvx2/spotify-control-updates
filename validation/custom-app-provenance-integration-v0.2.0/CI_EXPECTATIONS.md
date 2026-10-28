Expected CI behavior:
- Any mismatch in pinned function names, builder anchors, provenance/native-refresh blobs, or parent bytes MUST fail.
- No fallback to guessed source identity is permitted.
- No generic authority marker may be introduced to make tests pass.
- Fixes must preserve exact production main and source-topology parent identity.
