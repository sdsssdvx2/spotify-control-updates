"""R52 HOLD — actual public GitHub RAW readback of the final R50/R51
single-discovery SpotifyExit candidate; original R40 immutable 20-chunk
verifier runs unchanged against exactly pinned latest source and payload.

No production main modification, approval, release or installation.
"""
from __future__ import annotations

from importlib import util
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
BRANCH = "hold/spotify-v0630-singlecheck-review-only"
SOURCE = "8a001700d31de97d5fb0c746111094b4dd1c009c"
MANIFEST_SHA = "8f37e5c07310371ec8ff995d8c6f81aa9f2c7c9e0868d6f89dffac5feee913ef"
MAIN = "4ec5bc6c6612ab15fc297d474b193d228b9dab8eb5b79cd7b14042af5b72c93c"
AGENT = "1c1563bff9b9a87ae851b4ca555429b5451ce67c6d225a148b5252256d71cdf7"
PAYLOAD = "02bbcc70ad2bbb9f17228d9c4fd9fdbf0388b09d64fe0cd7090327507bdc98bc"

def main():
    spec = util.spec_from_file_location(
        "spotify_verified_r40_real_github_source_checker",
        HERE / "verify-integrated-public-transport-R40-HOLD.py")
    if spec is None or spec.loader is None:
        raise RuntimeError("R52_REAL_TRANSPORT_VERIFIER_UNAVAILABLE")
    m = util.module_from_spec(spec)
    spec.loader.exec_module(m)
    m.BRANCH = BRANCH
    m.SOURCE = SOURCE
    m.MANIFEST_SHA = MANIFEST_SHA
    m.TARGET_MAIN = MAIN
    m.TARGET_AGENT = AGENT
    m.TARGET_SET = PAYLOAD
    m.main()
    print("R52_REAL_GITHUB_FINAL_SINGLE_DISCOVERY_20_CHUNKS_SHA256=PASS")
    print("R52_FINAL_MAIN_AND_FAST_EVENT_AGENT_FULL_BYTES_RESTORED=PASS")
    print("R52_PUBLIC_MAIN_STABLE_REVIEW_ONLY_NO_OWNER_APPROVAL=YES")

if __name__ == "__main__":
    if sys.argv[1:]:
        raise SystemExit("R52 has no runtime parameters")
    main()
