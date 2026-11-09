"""R38 HOLD: encode the integrated R37 *actual* AgentTick + safe shortcuts as
one future stable 0.6.30 full-file Bootstrap update. Do not publish.

Reuse the existing official schema / deterministic gzip+base64 chunk producer,
but redirect its source and output to an isolated, unpublishable combined path.
All historical stable edges and Addon Manager r17 are byte preserved.
"""
from __future__ import annotations

import base64
import gzip
import hashlib
from importlib import util
import json
import os
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
OUTPUT=HERE/"out"/"release-staging-combined"
INTEGRATED=HERE/"out"/"integrated"
APPROVED_BASE="d38e88d9ae99f6a4983e2ad64f74f6fce7e6cde2"
PIN_R37_COMBINED="48714938d5ca1b40db0b1caf2fbc1e13afb69c46226e89949cfde129d643222a"
PIN_R37_AGENT="da054351cae6927504e735426d35f6d5e7edafcac7e06881f1adf1c20cecab9d"
PIN_R17_ADDON="5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285"

def sha(raw:bytes)->str:
    return hashlib.sha256(raw).hexdigest()

def die(reason:str):
    raise RuntimeError(reason)

def load(name:str,path:Path):
    spec=util.spec_from_file_location(name,path)
    if spec is None or spec.loader is None:
        die("INTEGRATED_STAGING_MODULE_UNAVAILABLE")
    mod=util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

def main():
    if (os.getenv("GITHUB_ACTIONS")!="true" or
        os.getenv("RUNNER_OS")!="Windows" or
        os.getenv("RUNNER_ENVIRONMENT")!="github-hosted"):
        die("GITHUB_HOSTED_WINDOWS_BUILD_ONLY")
    if OUTPUT.exists():
        die("COMBINED_STAGE_ALREADY_EXISTS_NO_OVERWRITE")
    new_main=(INTEGRATED/"spotify-control.ps1").read_bytes()
    new_agent=(INTEGRATED/"spotify-control-agent.vbs").read_bytes()
    addon=(INTEGRATED/"addon-manager.ps1").read_bytes()
    if (sha(new_main)!=PIN_R37_COMBINED or
        sha(new_agent)!=PIN_R37_AGENT or sha(addon)!=PIN_R17_ADDON):
        die("R37_COMBINED_SOURCE_BYTES_DRIFT")
    stage=load("spotify_original_stable_transport_R38",
        HERE/"stage-future-official-release-HOLD.py")
    # The canonical full-file packer and schema validation are unchanged.
    stage.SOURCE=INTEGRATED
    stage.STAGE=OUTPUT
    stage.build()
    future=json.loads((OUTPUT/"manifest-UNPUBLISHABLE.json").read_text("ascii"))
    receipt=json.loads((OUTPUT/"stage-receipt.json").read_text("ascii"))
    original=json.loads((ROOT/"manifest.json").read_text("utf-8-sig"))
    if (original["latest_version"]!="0.6.28" or
        future["source_commit"]!="f"*40 or
        future["latest_version"]!="0.6.30" or
        future["updates"][:-1]!=original["updates"] or
        len(future["updates"])!=19 or
        receipt["publishable"] is not False):
        die("FUTURE_HISTORY_OR_PUBLICATION_BOUNDARY_CHANGED")
    expected=new_main.replace(b'$ScriptVersion = "0.6.28"',
        b'$ScriptVersion = "0.6.30"',1)
    if (new_main.count(b'$ScriptVersion = "0.6.28"')!=1 or
        expected.count(b'$ScriptVersion = "0.6.30"')!=1):
        die("EXACT_MAIN_VERSION_MARKER_DRIFT")
    main_bytes=(OUTPUT/"bin"/"spotify-control.ps1").read_bytes()
    agent_bytes=(OUTPUT/"bin"/"spotify-control-agent.vbs").read_bytes()
    addon_bytes=(OUTPUT/"bin"/"addon-manager.ps1").read_bytes()
    if (main_bytes!=expected or agent_bytes!=new_agent or addon_bytes!=addon):
        die("FULL_FILE_STAGE_LOST_AN_INTEGRATED_FEATURE")
    patches=future["updates"][-1]["patches"]
    if [p["path"] for p in patches]!=[
        "bin/spotify-control.ps1","bin/spotify-control-agent.vbs"]:
        die("TWO_EXACT_OFFICIAL_PATCH_PATHS_REQUIRED")
    restored={}
    for patch in patches:
        b=[]
        for c in patch["chunks"]:
            part=(OUTPUT/c["path"]).read_bytes()
            if len(part)!=c["size"] or sha(part)!=c["sha256"]:
                die("COMPRESSED_IMMUTABLE_CHUNK_BYTES_CHANGED")
            b.append(part)
        encoded=b"".join(b)
        compressed=base64.b64decode(encoded,validate=True)
        decoded=gzip.decompress(compressed)
        if (len(encoded)!=patch["encoded_size"] or
            sha(encoded)!=patch["encoded_sha256"] or
            len(compressed)!=patch["compressed_size"] or
            sha(compressed)!=patch["compressed_sha256"] or
            len(decoded)!=patch["target_size"] or
            sha(decoded)!=patch["to_sha256"]):
            die("INTEGRATED_FULL_FILE_TRANSPORT_INCOMPLETE")
        restored[patch["path"]]=decoded
    if restored!={"bin/spotify-control.ps1":expected,
                  "bin/spotify-control-agent.vbs":new_agent}:
        die("BOTH_INTEGRATED_TARGETS_NOT_RESTORED")
    manifest_map={e["path"]:(e["size"],e["sha256"])
                  for e in future["latest_files"]}
    if manifest_map!={
        "bin/spotify-control.ps1":(len(expected),sha(expected)),
        "bin/addon-manager.ps1":(len(addon),sha(addon)),
        "bin/spotify-control-agent.vbs":(len(new_agent),sha(new_agent))}:
        die("FULL_PAYLOAD_LATEST_SET_DRIFT")
    print("R38_INTEGRATED_PUBLISHED_VERSION_CANDIDATE_MAIN_SHA256="+sha(expected))
    print("R38_INTEGRATED_PUBLISHED_VERSION_CANDIDATE_MANIFEST_SHA256="+sha(
        (OUTPUT/"manifest-UNPUBLISHABLE.json").read_bytes()))
    print("R38_INTEGRATED_NEW_SOURCE_CHUNKS="+str(
        sum(len(p["chunks"]) for p in patches)))
    print("R38_FULL_FILE_BOOTSTRAP_V106_TWO_PATCHES_REASSEMBLED=PASS")
    print("R38_R37_REAL_EXIT_AGENTTICK_AND_SAFE_SHORTCUTS_IN_ONE_BIN=PASS")
    print("R38_ORIGINAL_ADDON_R17_AND_HISTORY_EXACT=PASS")
    print("R38_PUBLIC_MAIN_OR_WINDOWS_CHANGES=NONE;RELEASE=HOLD")

if __name__=="__main__":
    if sys.argv[1:]:
        die("R38_NO_RUNTIME_OVERRIDES")
    main()
