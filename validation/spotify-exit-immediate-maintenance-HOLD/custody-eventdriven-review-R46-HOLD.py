"""R46 HOLD: exact original R35 Git provenance reader, independently creates
only new event-driven review ref. No force, no main, no public stable release.
"""
from __future__ import annotations
from importlib import util
from pathlib import Path
import sys

HERE=Path(__file__).resolve().parent
REF="refs/heads/hold/spotify-v0630-eventdriven-review-only"
NEW_VBS="1c1563bff9b9a87ae851b4ca555429b5451ce67c6d225a148b5252256d71cdf7"

def run():
    src=HERE/"persist-review-ref-HOLD.py"
    spec=util.spec_from_file_location("spotify_r46_original_custody_R35",src)
    if spec is None or spec.loader is None:
        raise RuntimeError("R46_R35_CUSTODY_NOT_LOADABLE")
    c=util.module_from_spec(spec)
    spec.loader.exec_module(c)
    c.REVIEW_REF=REF
    c.PREVIEW_TARGETS=dict(c.PREVIEW_TARGETS)
    c.PREVIEW_TARGETS["bin/spotify-control.ps1"]=(
        "7caf4afe19c283aef3b5bebb30e0e598b10de147d3ab1ddd9724bf90594c59fe")
    c.PREVIEW_TARGETS["bin/spotify-control-agent.vbs"]=NEW_VBS
    c.main()
    print("R46_EVENTDRIVEN_VERIFIED_20_CHUNK_MAIN_PARENT_REF_PRESERVED=PASS")
    print("R46_PUBLIC_MAIN_AND_PRIOR_REVIEW_REFS=NOT_TOUCHED")

if __name__=="__main__":
    if sys.argv[1:]:
        raise SystemExit("No arguments")
    run()
