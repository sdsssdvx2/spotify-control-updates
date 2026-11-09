"""R47 HOLD: authentic read-only GitHub raw transport of the final fast
WMI-event v0.6.30 candidate. Reuses successful R40 public HTTP verifier.

No release, no owner approval, no public main updates, no user PC, no writes.
"""
from __future__ import annotations
from importlib import util
from pathlib import Path
import sys

HERE=Path(__file__).resolve().parent

def main():
    src=HERE/"verify-integrated-public-transport-R40-HOLD.py"
    spec=util.spec_from_file_location("spotify_r47_exact_r40_remote_auditor",src)
    if spec is None or spec.loader is None:
        raise RuntimeError("R47_ORIGINAL_REMOTE_SOURCE_CHECK_UNAVAILABLE")
    m=util.module_from_spec(spec)
    spec.loader.exec_module(m)
    m.BRANCH="hold/spotify-v0630-eventdriven-review-only"
    m.SOURCE="991ceedfb4263d4242cb05f8666211f87fe1a150"
    m.MANIFEST_SHA="409a7f235192131381a85c151109ffc11f75cd658b4a7c3a979cf3a02d778ed1"
    m.TARGET_AGENT="1c1563bff9b9a87ae851b4ca555429b5451ce67c6d225a148b5252256d71cdf7"
    m.TARGET_SET="bd7dfdbdee7de01629b764825a7909d2e536e085eddeb7bca69db69cdb5bb5dc"
    m.main()
    print("R47_PUBLIC_GITHUB_FAST_WMI_REVIEW_SOURCE_20_CHUNKS_AND_FULL_AGENT=PASS")
    print("R47_LIVE_STABLE_MAIN_V0628_AND_OWNER_SETTINGS=UNMODIFIED")
    print("R47_AUTHORIZATION_TO_PUBLISH_OR_INSTALL=NO")

if __name__=="__main__":
    if sys.argv[1:]:
        raise SystemExit("No parameters.")
    main()
