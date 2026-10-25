# Optimization targets

Targets are added only after source-level analysis and must include exact upstream provenance, structural guards, idempotent transforms, rollback metadata, and a no-op path for unknown upstream revisions.

Current isolation evidence prioritizes user.css, Better Local Files, and Playlist Maker. SC Cover Ambience is explicitly excluded from optimization because disabling it materially worsened transition cost in v0.4.1.
