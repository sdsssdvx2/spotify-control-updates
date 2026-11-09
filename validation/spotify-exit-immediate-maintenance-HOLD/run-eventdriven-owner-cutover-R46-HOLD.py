"""R46 HOLD: reuse the full native-Windows R43 original R28 approved
resident cutover with the now event-driven WScript VBS candidate.

Only the immutable staged package path and expected resident SHA differ.
"""
from __future__ import annotations
from importlib import util
from pathlib import Path
import json
import os
import sys

HERE=Path(__file__).resolve().parent
STAGE=HERE/"out"/"release-staging-eventdriven-R46"
EXPECTED="1c1563bff9b9a87ae851b4ca555429b5451ce67c6d225a148b5252256d71cdf7"

def main():
    receipt=json.loads((STAGE/"stage-receipt.json").read_text("ascii"))
    if (receipt.get("resident_sha256")!=EXPECTED or
        receipt.get("future_scratch_version")!="0.6.30" or
        receipt.get("status")!="STAGED_HOLD_NOT_PUBLISHABLE" or
        receipt.get("publishable") is not False):
        raise RuntimeError("R46_FULL_FILE_PREVIOUS_VBS_OR_PUBLISHABLE_STAGE")
    script=HERE/"reuse-integrated-owner-cutover-R43-HOLD.py"
    spec=util.spec_from_file_location("spotify_r46_original_cutover_R43",script)
    if spec is None or spec.loader is None:
        raise RuntimeError("R46_PREVIOUS_R43_CUTOVER_UNAVAILABLE")
    r43=util.module_from_spec(spec)
    spec.loader.exec_module(r43)
    r43.COMBINED=STAGE.relative_to(HERE.parents[1]).as_posix()
    r43.AGENT_SHA=EXPECTED
    r43.run()
    print("R46_REUSED_EXACT_R43_NATIVE_OWNER_CUTOVER_FOR_FAST_WMI_RESIDENT=PASS")

if __name__=="__main__":
    if sys.argv[1:]:
        raise SystemExit("No arguments.")
    main()
