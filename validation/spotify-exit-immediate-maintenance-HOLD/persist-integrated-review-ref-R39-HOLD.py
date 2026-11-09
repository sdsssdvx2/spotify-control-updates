"""R39 HOLD: create/check only a new, separate non-main review branch for
the already Windows-accepted R37/R38 integrated v0.6.30 candidate.

Uses R35's existing Git bundle source/manifest/payload proof unchanged, with
the integrated main hash and a distinct owner-review ref.
"""
from __future__ import annotations
from importlib import util
from pathlib import Path
import sys

HERE=Path(__file__).resolve().parent
SRC=HERE/"persist-review-ref-HOLD.py"

def main():
    spec=util.spec_from_file_location("spotify_r35_immutable_custody_integrated",SRC)
    if spec is None or spec.loader is None:
        raise RuntimeError("R39_REVIEW_CUSTODY_MODULE_MISSING")
    c=util.module_from_spec(spec)
    spec.loader.exec_module(c)
    c.REVIEW_REF="refs/heads/hold/spotify-v0630-integrated-review-only"
    # All other expected paths, source chunk SHA validation, public parent,
    # manifest history and protected surfaces are the exact R35 code.
    c.PREVIEW_TARGETS=dict(c.PREVIEW_TARGETS)
    c.PREVIEW_TARGETS["bin/spotify-control.ps1"]=(
        "7caf4afe19c283aef3b5bebb30e0e598b10de147d3ab1ddd9724bf90594c59fe")
    c.main()
    print("R39_PERMANENT_INTEGRATED_REVIEW_REF_ONLY=VERIFIED")
    print("R39_OLD_SHORTCUT_ONLY_REVIEW_AND_PUBLIC_MAIN=UNCHANGED")

if __name__=="__main__":
    if sys.argv[1:]:
        raise SystemExit("No parameters accepted")
    main()
