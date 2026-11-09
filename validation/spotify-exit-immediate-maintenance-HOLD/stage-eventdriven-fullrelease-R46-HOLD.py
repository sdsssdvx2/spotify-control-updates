"""R46 HOLD: combine already-verified original R37 SpotifyExit AgentTick
and safe-shortcut main with the live-Windows-fast R45 event-driven WScript.

Reuses UNMODIFIED R38 verified full-file release staging implementation.
Never overwrite the earlier R39 integrated review or production v0.6.28.
"""
from __future__ import annotations
from importlib import util
import hashlib
import json
import os
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
SOURCE=HERE/"out"/"integrated"
FAST=HERE/"out"/"eventdriven-r45"/"spotify-control-agent.vbs"
MERGED=HERE/"out"/"eventdriven-integrated-R46"
STAGE=HERE/"out"/"release-staging-eventdriven-R46"
MAIN_PIN="48714938d5ca1b40db0b1caf2fbc1e13afb69c46226e89949cfde129d643222a"
FAST_PIN="1c1563bff9b9a87ae851b4ca555429b5451ce67c6d225a148b5252256d71cdf7"
ADDON_PIN="5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285"
VERSION_MAIN_PIN="7caf4afe19c283aef3b5bebb30e0e598b10de147d3ab1ddd9724bf90594c59fe"

def sha(b):
    return hashlib.sha256(b).hexdigest()

def imported(path,name):
    spec=util.spec_from_file_location(name,path)
    if spec is None or spec.loader is None:
        raise RuntimeError("R46_ORIGINAL_MODULE_NOT_LOADABLE")
    mod=util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

def run():
    if (os.getenv("GITHUB_ACTIONS")!="true" or
        os.getenv("RUNNER_OS")!="Windows" or
        os.getenv("RUNNER_ENVIRONMENT")!="github-hosted"):
        raise RuntimeError("R46_HOSTED_WINDOWS_ONLY")
    if MERGED.exists() or STAGE.exists():
        raise RuntimeError("R46_PREVIOUS_STAGING_EXISTS_NO_OVERWRITE")
    before={
        "spotify-control.ps1":(SOURCE/"spotify-control.ps1").read_bytes(),
        "addon-manager.ps1":(SOURCE/"addon-manager.ps1").read_bytes(),
        "spotify-control-agent.vbs":FAST.read_bytes()
    }
    if ({k:sha(v) for k,v in before.items()}!={
        "spotify-control.ps1":MAIN_PIN,
        "addon-manager.ps1":ADDON_PIN,
        "spotify-control-agent.vbs":FAST_PIN}):
        raise RuntimeError("R46_COMBINED_SOURCE_OR_EVENT_AGENT_SHA_DRIFT")
    source_receipt=json.loads((FAST.parent/"receipt.json").read_text("utf-8"))
    if (source_receipt.get("new_event_driven_vbs_sha256")!=FAST_PIN or
        source_receipt.get("mode")!="R45_WMI_STOP_EVENT_HOLD_NOT_PUBLISHED" or
        source_receipt.get("safety_fallback_poll_ms")!=60000 or
        source_receipt.get("event_settle_ms")!=2500):
        raise RuntimeError("R46_R45_EVENT_TRACING_NOT_THE_LIVE_ACCEPTED_VERSION")
    MERGED.mkdir(parents=True,exist_ok=False)
    for name,content in before.items():
        with (MERGED/name).open("xb") as f:
            f.write(content)
    # Previously verified source+schema+chunk producer remains byte-for-byte.
    r38=imported(HERE/"stage-combined-official-transport-R38-HOLD.py",
                 "spotify_r46_original_full_file_packer_R38")
    r38.INTEGRATED=MERGED
    r38.OUTPUT=STAGE
    r38.PIN_R37_AGENT=FAST_PIN
    r38.main()
    manifest=json.loads((STAGE/"manifest-UNPUBLISHABLE.json").read_text("ascii"))
    check={r["path"]:r["sha256"] for r in manifest["latest_files"]}
    if check!={"bin/spotify-control.ps1":VERSION_MAIN_PIN,
              "bin/spotify-control-agent.vbs":FAST_PIN,
              "bin/addon-manager.ps1":ADDON_PIN}:
        raise RuntimeError("R46_EVENT_AGENT_NOT_IN_OFFICIAL_TARGET_SET")
    if (manifest["source_commit"]!="f"*40 or
        manifest["latest_version"]!="0.6.30" or
        len(manifest["updates"])!=19 or
        manifest["updates"][-1]["to_version"]!="0.6.30"):
        raise RuntimeError("R46_STAGED_UNPUBLISHABLE_SCHEMA_DRIFT")
    if any((MERGED/k).read_bytes()!=v for k,v in before.items()):
        raise RuntimeError("R46_ORIGINAL_SOURCE_FILES_CHANGED")
    print("R46_EVENT_DRIVEN_AGENT_SHA256="+FAST_PIN)
    print("R46_FULL_RELEASE_MAIN_SHA256="+VERSION_MAIN_PIN)
    print("R46_FULL_RELEASE_PATCH_CHUNKS="+str(sum(
        len(p["chunks"]) for p in manifest["updates"][-1]["patches"])))
    print("R46_ORIGINAL_R37_AGENTTICK_MAIN_PLUS_R45_WMI_TRACE_AGENT=INTEGRATED")
    print("R46_OFFICIAL_BOOTSTRAP_FULL_FILE_ENCODER_VERIFIED=PASS")
    print("R46_NO_PRODUCTION_MANIFEST_OR_WINDOWS_CHANGE=YES")

if __name__=="__main__":
    if sys.argv[1:]:
        raise SystemExit("No arguments.")
    run()
