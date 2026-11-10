"""R59 HOLD: combine unchanged fully-verified R54 shared-maintenance main,
unchanged r17 Addon Manager and R58 rapid-start/stop WMI resident into
one exact v0.6.30 official full-file update candidate.

Use existing R38 deterministic encoder unchanged; all remote release
artifacts are review-only and user Windows is untouched.
"""
from __future__ import annotations
from importlib import util
import hashlib
import json
import os
from pathlib import Path
import sys

HERE=Path(__file__).resolve().parent
BASE=HERE/"out"/"shared-maintenance-R54"
FAST=HERE/"out"/"rapid-restart-r58"
OUT=HERE/"out"/"rapid-restart-release-R59"
STAGE=HERE/"out"/"release-staging-rapid-restart-R59"
EXPECTED_MAIN="b2b2fbf1afb60b58d501312160f7e2437c2452e90cb61ca8c2be0d877f92232d"
EXPECTED_AGENT="925542aa4eeff3a566d527bdd2439f5864a8dce0e524c59b402ec2ef7afc9e0f"
EXPECTED_ADDON="5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285"

def sha(x):return hashlib.sha256(x).hexdigest()

def main():
    if (os.getenv("GITHUB_ACTIONS")!="true" or
        os.getenv("RUNNER_OS")!="Windows" or
        os.getenv("RUNNER_ENVIRONMENT")!="github-hosted"):
        raise RuntimeError("R59_HOSTED_WINDOWS_ONLY")
    if OUT.exists() or STAGE.exists():
        raise RuntimeError("R59_PREEXISTING_STAGING_NO_CLOBBER")
    record=json.loads((BASE/"attestation.json").read_text("utf-8"))
    fast=json.loads((FAST/"receipt.json").read_text("utf-8"))
    original=(BASE/"spotify-control.ps1").read_bytes()
    agent=(FAST/"spotify-control-agent.vbs").read_bytes()
    addon=(BASE/"addon-manager.ps1").read_bytes()
    versioned=original.replace(b'$ScriptVersion = "0.6.28"',
                               b'$ScriptVersion = "0.6.30"',1)
    if (sha(versioned)!=EXPECTED_MAIN or
        sha(original)!=record["main_plain_sha256"] or
        sha(agent)!=EXPECTED_AGENT or
        fast.get("new_sha256")!=EXPECTED_AGENT or
        fast.get("mode")!="R58_RAPID_RESTART_DISTINCT_WMI_SESSION_HOLD" or
        fast.get("r45_parent_sha256")!="1c1563bff9b9a87ae851b4ca555429b5451ce67c6d225a148b5252256d71cdf7" or
        sha(addon)!=EXPECTED_ADDON or
        record.get("mode")!="R54_SERIALIZED_AGENT_AND_MANUAL_MAINTENANCE_HOLD"):
        raise RuntimeError("R59_EXACT_R54_MAIN_R58_AGENT_R17_ADDON_PIN_FAILED")
    OUT.mkdir(parents=True,exist_ok=False)
    for name,data in {"spotify-control.ps1":original,
                      "spotify-control-agent.vbs":agent,
                      "addon-manager.ps1":addon}.items():
        with (OUT/name).open("xb") as f:f.write(data)
    spec=util.spec_from_file_location("spotify_r59_original_fullfile_encoder_R38",
                                    HERE/"stage-combined-official-transport-R38-HOLD.py")
    if spec is None or spec.loader is None:
        raise RuntimeError("R59_OFFICIAL_ENCODER_NOT_FOUND")
    r38=util.module_from_spec(spec)
    spec.loader.exec_module(r38)
    r38.INTEGRATED=OUT
    r38.OUTPUT=STAGE
    r38.PIN_R37_COMBINED=sha(original)
    r38.PIN_R37_AGENT=EXPECTED_AGENT
    r38.main()
    doc=json.loads((STAGE/"manifest-UNPUBLISHABLE.json").read_text("ascii"))
    release=(STAGE/"bin"/"spotify-control.ps1").read_bytes()
    release_agent=(STAGE/"bin"/"spotify-control-agent.vbs").read_bytes()
    versions={x["path"]:x["sha256"] for x in doc["latest_files"]}
    if (release!=versioned or release_agent!=agent or
        versions!={"bin/spotify-control.ps1":EXPECTED_MAIN,
                  "bin/spotify-control-agent.vbs":EXPECTED_AGENT,
                  "bin/addon-manager.ps1":EXPECTED_ADDON} or
        doc["source_commit"]!="f"*40 or doc["latest_version"]!="0.6.30" or
        sum(len(p["chunks"]) for p in doc["updates"][-1]["patches"])!=20):
        raise RuntimeError("R59_FULL_FILE_UPDATE_OR_HISTORY_NOT_EXACTLY_PINNED")
    print("R59_SINGLE_REVIEW_MAIN_SHARED_MUTEX_SHA256="+EXPECTED_MAIN)
    print("R59_RAPID_START_STOP_WMI_RESIDENT_SHA256="+EXPECTED_AGENT)
    print("R59_ADDON_R17_UNCHANGED_SHA256="+EXPECTED_ADDON)
    print("R59_OFFICIAL_BOOTSTRAP_TWO_FULL_FILE_PATCHES_20_CHUNKS=VERIFIED")
    print("R59_MAIN_CODE_EXACT_R55_BYTES;ONLY_VBS_SESSION_BEHAVIOR_CHANGED=PASS")
    print("R59_PUBLICATION_AND_USER_PC=UNCHANGED_HOLD")

if __name__=="__main__":
    if sys.argv[1:]:raise SystemExit("R59 no arguments")
    main()
