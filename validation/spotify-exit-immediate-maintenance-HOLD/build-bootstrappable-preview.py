"""Prepare a real Bootstrap-1.0.6-shaped single-file forward update, HOLD ONLY.

This uses the existing stable 0.6.28 source builder and official release
transport formatter. No separate updater, no edits to checked-in manifest.json,
no production user profile, no extra addon mutation authority.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import runpy
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
STAGE = HERE / "out"
PKG = ROOT / "packages/v0.6.29/main-v0628-to-v0629"
PREVIEW = STAGE / "preview"
OLD_MAIN = (284321, "af1582ec335807f8f5daa9b3a65b13d567264f326d3c608c082ae02ff0a4cfc0")
UNCHANGED_ADDON = (323385, "5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285")
UNCHANGED_AGENT = (4855, "2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278")
BOOTSTRAP = {"version": "1.0.6", "sha256": "d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6", "size": 42963}
OLD_MARKER = b'$ScriptVersion = "0.6.28"'
NEW_MARKER = b'$ScriptVersion = "0.6.29"'

def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def pair(data: bytes) -> tuple[int, str]:
    return len(data), sha(data)

def production_manifest() -> dict:
    manifest = json.loads((ROOT / "manifest.json").read_text(encoding="utf-8-sig"))
    if manifest.get("schema") != 1 or manifest.get("channel") != "stable":
        raise RuntimeError("CANNOT_REUSE_UNEXPECTED_STABLE_SCHEMA")
    if manifest.get("latest_version") != "0.6.28" or manifest.get("min_bootstrap_version") != "1.0.6" or manifest.get("bootstrap") != BOOTSTRAP:
        raise RuntimeError("STABLE_MANIFEST_BASE_OR_BOOTSTRAP_DRIFT")
    latest = {x["path"]: (int(x["size"]),x["sha256"]) for x in manifest["latest_files"]}
    if latest != {
        "bin/spotify-control.ps1": OLD_MAIN,
        "bin/addon-manager.ps1": UNCHANGED_ADDON,
        "bin/spotify-control-agent.vbs": UNCHANGED_AGENT,
    }:
        raise RuntimeError("STABLE_SOURCE_SET_DRIFT")
    return manifest

def release_engine() -> dict:
    # Reuse immutable production release helper for gzip-base64-full-file
    # encoding and canonical payload hash, rather than new patch syntax.
    engine = runpy.run_path(str(ROOT / "validation/v0.6.26/release_transport.py"))
    return engine

def package() -> dict:
    manifest = production_manifest()
    # Existing source-attested event guard + unchanged r17/agent.
    stage_module = runpy.run_path(str(HERE / "stage-candidate.py"))
    stage_module["construct"]()
    source = stage_module["source_from_stable"]()
    original, addon, agent = source
    staged = (STAGE / "bin/spotify-control.ps1").read_bytes()
    if pair(original) != OLD_MAIN or pair(addon) != UNCHANGED_ADDON or pair(agent) != UNCHANGED_AGENT:
        raise RuntimeError("CANONICAL_RELEASE_PARENT_MISMATCH")
    if staged.count(OLD_MARKER) != 1 or staged.count(NEW_MARKER) != 0:
        raise RuntimeError("AGENTTICK_CANDIDATE_VERSION_MARKER_DRIFT")
    updated = staged.replace(OLD_MARKER, NEW_MARKER, 1)
    if updated.replace(NEW_MARKER, OLD_MARKER, 1) != staged:
        raise RuntimeError("VERSION_INVERSE_MISMATCH")
    if pair(updated) == pair(original):
        raise RuntimeError("NO_FEATURE_DIFFERENCE")
    # Single forward edge: changed main only; full-bin invariant will still
    # validate exact unchanged addon + resident-agent bytes.
    engine = release_engine()
    transport = engine["build_full_file_patch"]("bin/spotify-control.ps1", original, updated, PKG)
    if transport.get("encoding") != "gzip-base64-full-file":
        raise RuntimeError("PRODUCTION_TRANSPORT_FORMAT_DRIFT")
    target = stage_module["function_span"](updated.decode("utf-8-sig"), "Invoke-ResidentAgentTick")
    if not all(isinstance(x, int) for x in target) or target[1] <= target[0]:
        raise RuntimeError("PREVIEW_AGENTTICK_NOT_PRESENT")
    (STAGE / "bin/spotify-control.ps1").write_bytes(updated)
    expected = {
        "schema": 1, "hold": True, "deployable": False,
        "old_version": "0.6.28", "new_version": "0.6.29",
        "old_main_sha256": OLD_MAIN[1],
        "new_main_sha256": sha(updated), "new_main_size": len(updated),
        "addon_sha256": UNCHANGED_ADDON[1], "agent_sha256": UNCHANGED_AGENT[1],
        "bootstrap": BOOTSTRAP, "patch": transport,
        "event": json.loads((STAGE / "source-attestation.json").read_text())["agent_vbs_exit_event"],
        "unchanged_app_auto_authority": ["better-local-files", "eternal-jukebox", "ivLyrics", "playlist-maker"],
        "production_mutation_authorized": False,
    }
    STAGE.mkdir(parents=True, exist_ok=True)
    (STAGE / "bootstrappable-preview-metadata.json").write_text(json.dumps(expected, indent=2, sort_keys=True)+"\n", encoding="utf-8", newline="\n")
    print("BOOTSTRAP_V106_SINGLE_MAIN_FORWARD_EDGE_BUILT_HOLD",len(updated),sha(updated),len(transport["chunks"]))
    return expected

def manifest_preview(source_commit: str) -> dict:
    if not re.fullmatch(r"[a-f0-9]{40}", source_commit):
        raise RuntimeError("PREVIEW_SOURCE_COMMIT_INVALID")
    metadata = package()
    # A manifest must point ONLY at immutable committed transport, never
    # uncommitted workspace files or a mutable branch ref.
    subprocess.check_call(["git","cat-file","-e",source_commit+"^{commit}"],cwd=ROOT)
    for chunk in metadata["patch"]["chunks"]:
        rel = chunk["path"]
        pinned = subprocess.check_output(["git","show",f"{source_commit}:{rel}"],cwd=ROOT)
        actual=(ROOT / rel).read_bytes()
        if pinned != actual or pair(pinned) != (int(chunk["size"]),chunk["sha256"]):
            raise RuntimeError("PREVIEW_SOURCE_COMMIT_MISSING_EXACT_PACKAGE_CHUNK")
    m=production_manifest()
    if any(x["from_version"]=="0.6.28" for x in m["updates"]):
        raise RuntimeError("SOURCE_EDGE_ALREADY_EXISTS")
    final = [
        {"path":"bin/spotify-control.ps1","sha256":metadata["new_main_sha256"],"size":metadata["new_main_size"]},
        {"path":"bin/addon-manager.ps1","sha256":UNCHANGED_ADDON[1],"size":UNCHANGED_ADDON[0]},
        {"path":"bin/spotify-control-agent.vbs","sha256":UNCHANGED_AGENT[1],"size":UNCHANGED_AGENT[0]},
    ]
    m["latest_version"]="0.6.29"
    m["source_commit"]=source_commit
    m["latest_files"]=final
    m["payload_set_sha256"]=release_engine()["canonical_payload"](final)
    m["updates"].append({"from_version":"0.6.28","to_version":"0.6.29","patches":[metadata["patch"]]})
    PREVIEW.mkdir(parents=True,exist_ok=True)
    out=PREVIEW/"manifest.json"
    out.write_text(json.dumps(m,separators=(",",":"))+"\n",encoding="utf-8",newline="\n")
    parsed=json.loads(out.read_text(encoding="utf-8"))
    if parsed["updates"][:-1] != production_manifest()["updates"]:
        raise RuntimeError("HISTORICAL_STABLE_EDGES_WERE_CHANGED")
    if parsed["updates"][-1]["patches"][0]["to_sha256"] != metadata["new_main_sha256"]:
        raise RuntimeError("SINGLE_PATCH_TARGET_DRIFT")
    print("BOOTSTRAP_PREVIEW_MANIFEST_ONE_EDGE_COMMITTED_SOURCE_PIN_PASS",source_commit,parsed["payload_set_sha256"])
    return parsed

def main():
    p=argparse.ArgumentParser()
    q=p.add_mutually_exclusive_group(required=True)
    q.add_argument("--build",action="store_true")
    q.add_argument("--source-commit")
    args=p.parse_args()
    if args.build:
        package()
    else:
        manifest_preview(args.source_commit)

if __name__=="__main__":
    main()
