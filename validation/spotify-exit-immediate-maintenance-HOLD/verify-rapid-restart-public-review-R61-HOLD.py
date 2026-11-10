"""R61 HOLD: actual read-only GitHub public raw transport verification for
the R59 two-rapid-session WMI SpotifyExit full-file update candidate.
Reuses original R40 authentic R29 immutable 20-chunk downloader+SHA checker.
Never publishes, approves, installs or changes any real user software.
"""
from __future__ import annotations
from importlib import util
from pathlib import Path
import sys

HERE=Path(__file__).resolve().parent
BRANCH="hold/spotify-v0630-rapid-restart-review-only"
SOURCE="f972421ef2d8070bd25a54fde0b266dfe180b5e0"
MANIFEST_SHA="dba1889da45f6d08620a018493ff9ccdb6f2c03cfdc7a74883777535a896ba3c"
MAIN_SHA="b2b2fbf1afb60b58d501312160f7e2437c2452e90cb61ca8c2be0d877f92232d"
VBS_SHA="8eb76416848a7da3e3ce02a7d169655f676ea109f9f9a050d94e364e48182874"
PAYLOAD_SHA="c42eaa24faef6b53d101e677aa2923255d93cfedd8bd7dbf77784b2aef7c8a72"

def main():
    path=HERE/"verify-integrated-public-transport-R40-HOLD.py"
    spec=util.spec_from_file_location("spotify_r61_pinned_real_github_r40",path)
    if spec is None or spec.loader is None:
        raise RuntimeError("R61_VERIFIED_TRANSPORT_IMPLEMENTATION_MISSING")
    transport=util.module_from_spec(spec)
    spec.loader.exec_module(transport)
    transport.BRANCH=BRANCH
    transport.SOURCE=SOURCE
    transport.MANIFEST_SHA=MANIFEST_SHA
    transport.TARGET_MAIN=MAIN_SHA
    transport.TARGET_AGENT=VBS_SHA
    transport.TARGET_SET=PAYLOAD_SHA
    transport.main()
    print("R61_TWO_RAPID_RESTART_EVENT_REVIEW_REAL_GITHUB_MANIFEST=PASS")
    print("R61_COMPLETE_R59_MAIN_AND_VBS_20_REMOTE_CHUNKS=SHA256_VERIFIED")
    print("R61_PUBLIC_MAIN_V0628_PRESERVED_AND_OWNER_APPROVAL=NOT_GRANTED")

if __name__=="__main__":
    if sys.argv[1:]:
        raise SystemExit("R61 accepts no external arguments")
    main()
