"""R57 HOLD: verify true public GitHub raw bytes of final R54/R55
serialized manual-maintenance + SpotifyExit update candidate.

Reuse unchanged original R40 GitHub HTTP full-file SHA + 20 immutable
chunk validator; source/manifest/payload hashes are pinned to exact R55
review commits. No Git write, user action, publication or live Spotify.
"""
from __future__ import annotations
from importlib import util
from pathlib import Path
import sys

HERE=Path(__file__).resolve().parent
REVIEW="hold/spotify-v0630-shared-maintenance-review-only"
SOURCE="1a232ebfec37f1feff3d7bd6a7f84ee2a7fbdf6c"
MANIFEST_SHA="6bb1ce5b933774c9b143fae256533c1d34b98150b1f9f253b79258cb4cdfa7eb"
MAIN_SHA="b2b2fbf1afb60b58d501312160f7e2437c2452e90cb61ca8c2be0d877f92232d"
VBS_SHA="1c1563bff9b9a87ae851b4ca555429b5451ce67c6d225a148b5252256d71cdf7"
PAYLOAD_SHA="cf44e0fef3e1f3a12824be770d8b42b1c41c3c6c4eaacf786c9ab5efd8544aa1"

def main():
    path=HERE/"verify-integrated-public-transport-R40-HOLD.py"
    spec=util.spec_from_file_location("spotify_r57_original_real_remote_R40",path)
    if spec is None or spec.loader is None:
        raise RuntimeError("R57_R40_OFFICIAL_REMOTE_TRANSPORT_NOT_LOADABLE")
    old=util.module_from_spec(spec)
    spec.loader.exec_module(old)
    old.BRANCH=REVIEW
    old.SOURCE=SOURCE
    old.MANIFEST_SHA=MANIFEST_SHA
    old.TARGET_MAIN=MAIN_SHA
    old.TARGET_AGENT=VBS_SHA
    old.TARGET_SET=PAYLOAD_SHA
    old.main()
    print("R57_FINAL_SHARED_MUTEX_REAL_GITHUB_MANIFEST_SHA256=PASS")
    print("R57_FINAL_FULL_MAIN_AND_FAST_WMI_RESIDENT_20_CHUNKS_RECONSTRUCTED=PASS")
    print("R57_STABLE_V0628_AND_OWNER_PC_UNMODIFIED_RELEASE_NOT_APPROVED=YES")

if __name__=="__main__":
    if sys.argv[1:]:
        raise SystemExit("R57 no parameters")
    main()
