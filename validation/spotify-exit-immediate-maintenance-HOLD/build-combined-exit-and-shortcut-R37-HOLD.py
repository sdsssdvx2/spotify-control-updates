"""R37 HOLD: unite previously verified SpotifyExit AgentTick with safe shortcuts.

The existing R10 exit-discovery prototype and R34 reviewed neutral-shortcut
candidate BOTH descend from the exact public v0.6.28/r17 bytes. This module
does not invent a third rewrite. It transplants exactly the already-reviewed
AgentTick function slice into the independently built shortcut candidate,
proves both modifications commute without collision, and stages a single
new combined release candidate for targeted Windows native acceptance.

No official manifest change, push, release, user PC interaction, or install.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import runpy
import sys

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
OUT=HERE/"out"
BASE_MAIN=(284321,"af1582ec335807f8f5daa9b3a65b13d567264f326d3c608c082ae02ff0a4cfc0")
BASE_ADDON="5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285"
PIN_SAFE_MAIN="37eda0638c428ed3474a06812c067ca10f5771216ae509d3cd4ce10fdafbd3ec"
PIN_SAFE_AGENT="da054351cae6927504e735426d35f6d5e7edafcac7e06881f1adf1c20cecab9d"
REGRESSION_FN="Invoke-ResidentAgentTick"


def sha(raw:bytes)->str:
    return hashlib.sha256(raw).hexdigest()


def require(cond:bool,code:str)->None:
    if not cond:
        raise RuntimeError(code)


def main():
    stable_mod=runpy.run_path(str(HERE/"stage-candidate.py"))
    base,addon,base_agent=stable_mod["source_from_stable"]()
    require((len(base),sha(base))==BASE_MAIN,"PUBLIC_MAIN_BYTES_CHANGED")
    require(sha(addon)==BASE_ADDON,"PUBLIC_ADDON_R17_CHANGED")

    # Construct and pin each previously accepted change independently.
    exit_mod=runpy.run_path(str(HERE/"stage-candidate.py"))
    provenance=exit_mod["construct"]()
    fast=(OUT/"bin"/"spotify-control.ps1").read_bytes()
    require(provenance["base_main_sha256"]==BASE_MAIN[1] and
            provenance["candidate_main_sha256"]==sha(fast),
            "FAST_EXIT_PARENT_OR_CANDIDATE_ATTESTATION_CHANGED")
    event=provenance["agent_vbs_exit_event"]
    require(isinstance(event,str) and event.lower().endswith("exit"),
            "FAST_EXIT_VBS_EVENT_MISSING")

    safe_mod=runpy.run_path(str(HERE/"build-managed-shortcut-future-safe-candidate.py"))
    safe_mod["build"]()
    safe=(OUT/"future-safe"/"spotify-control.ps1").read_bytes()
    safe_agent=(OUT/"future-safe"/"spotify-control-agent.vbs").read_bytes()
    require(sha(safe)==PIN_SAFE_MAIN and sha(safe_agent)==PIN_SAFE_AGENT,
            "REVIEWED_SHORTCUT_AND_RESIDENT_BYTES_CHANGED")

    bom=b"\xef\xbb\xbf" if base.startswith(b"\xef\xbb\xbf") else b""
    require(all(x.startswith(bom) for x in (fast,safe)),"PARENT_ENCODING_DRIFT")
    def decode(x:bytes)->str:
        return x[len(bom):].decode("utf-8")

    before=decode(base)
    after_exit=decode(fast)
    after_shortcut=decode(safe)
    function_span=exit_mod["function_span"]
    a0,a1=function_span(before,REGRESSION_FN)
    e0,e1=function_span(after_exit,REGRESSION_FN)
    s0,s1=function_span(after_shortcut,REGRESSION_FN)
    old=before[a0:a1]
    new=after_exit[e0:e1]
    require(old==after_shortcut[s0:s1],"SHORTCUT_EDIT_OVERLAPS_EXIT_FUNCTION")
    require(before[:a0]+new+before[a1:]==after_exit,
            "FAST_EXIT_EDIT_NOT_EXACTLY_ONE_FUNCTION")
    require(old!=new and REGRESSION_FN in new,
            "FAST_EXIT_FUNCTION_NOT_IMPROVED")
    require(after_shortcut.count(old)==1,
            "EXACT_AGENTTICK_REPLACEMENT_ANCHOR_NOT_UNIQUE")
    combined_text=after_shortcut.replace(old,new,1)
    # The fast exit change can be removed losslessly from the final candidate.
    require(combined_text.replace(new,old,1)==after_shortcut,
            "COMBINED_EDIT_FAILED_INVERSE_REPLAY")
    require(combined_text!=after_exit and combined_text!=after_shortcut,
            "ONE_OF_TWO_REQUIRED_FEATURES_MISSING")
    merged=bom+combined_text.encode("utf-8")
    require(sha(merged)!=sha(base) and sha(merged)!=PIN_SAFE_MAIN,
            "NO_COMBINED_CANDIDATE_DIFFERENCE")

    # Existing R10 test executable must import the EXACT merged function, not
    # a stale standalone fixture built by the earlier stage-candidate step.
    c0,c1=function_span(combined_text,REGRESSION_FN)
    merged_func=combined_text[c0:c1]
    require(merged_func==new,"MERGED_RUNTIME_FUNCTION_NOT_EXACT_EXIT_FIX")
    integrated=OUT/"integrated"
    isolated=OUT/"integrated-proof"/"isolated"
    integrated.mkdir(parents=True,exist_ok=True)
    isolated.mkdir(parents=True,exist_ok=True)
    (integrated/"spotify-control.ps1").write_bytes(merged)
    (integrated/"addon-manager.ps1").write_bytes(addon)
    (integrated/"spotify-control-agent.vbs").write_bytes(safe_agent)
    (isolated/"actual-agenttick-function.ps1").write_text(
        merged_func,encoding="utf-8",newline="\n")
    metadata={
        "schema":1,
        "mode":"R37_COMBINED_HOLD_SCRATCH_NOT_RELEASED",
        "agent_vbs_exit_event":event,
        "merged_main_sha256":sha(merged),
        "merged_main_bytes":len(merged),
        "base_main_sha256":BASE_MAIN[1],
        "independent_exit_main_sha256":sha(fast),
        "independent_shortcut_main_sha256":sha(safe),
        "merged_vbs_sha256":sha(safe_agent),
        "unchanged_addon_r17_sha256":sha(addon),
        "main_changes":"ONLY_PREVIOUS_FAST_EXIT_FUNCTION_AND_PREVIOUS_SAFE_SHORTCUT_BLOCK",
        "existing_r10_exact_merged_function_proven":True,
        "previous_review_candidate_not_replaced":True,
        "public_main_changed":False,
        "user_pc_changed":False,
        "owner_approval_granted":False
    }
    (OUT/"integrated-proof"/"source-attestation.json").write_text(
        json.dumps(metadata,sort_keys=True,indent=2)+"\n",encoding="utf-8")
    print("R37_COMBINED_MAIN_SHA256="+sha(merged))
    print("R37_OLD_EXIT_FIX_AND_NEW_SAFE_SHORTCUTS_BOTH_PRESERVED=PASS")
    print("R37_ADDON_R17_AND_NEUTRAL_RESIDENT_BYTES_UNCHANGED=PASS")
    print("R37_MERGED_EXIT_FUNCTION_EXACT_FOR_WINDOWS_EXECUTION=PASS")
    print("R37_DEPLOYMENT=OFF;PUBLIC_MAIN=UNCHANGED;OWNER_DATA=UNTOUCHED")


if __name__=="__main__":
    if sys.argv[1:]:
        raise SystemExit("R37 takes no arguments.")
    main()
