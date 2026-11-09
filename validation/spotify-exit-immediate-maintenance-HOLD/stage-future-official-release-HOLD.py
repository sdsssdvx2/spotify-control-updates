"""Offline next-stable release staging, NOT an authorized publication.

Assembles the real Bootstrap v1.0.6 full-file transport and entire stable
manifest under an ignored validation/out directory with an INVALID sentinel
source_commit, so no user or official updater can consume it as a release.

Publication would require separately committing chunk files, then setting
source_commit to that exact immutable commit in a distinct reviewed manifest
commit. This module intentionally does NOT offer a publish/activate mode.
"""
from __future__ import annotations

import base64
import copy
import gzip
import hashlib
import json
import os
from pathlib import Path
import runpy
import shutil

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "validation/spotify-exit-immediate-maintenance-HOLD/out/future-safe"
ORIGINAL = ROOT / "validation/v0.6.28/out/bin"
STAGE = ROOT / "validation/spotify-exit-immediate-maintenance-HOLD/out/release-staging"
LIVE_MANIFEST = ROOT / "manifest.json"
SCHEMA = ROOT / "manifest.schema.json"
VERSION = "0.6.30"  # FUTURE STAGING ONLY; v0.6.29 is an unrelated preview
INVALID_COMMIT = "f" * 40
BASE_SHA = {
    "bin/spotify-control.ps1": (284321,"af1582ec335807f8f5daa9b3a65b13d567264f326d3c608c082ae02ff0a4cfc0"),
    "bin/addon-manager.ps1": (323385,"5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285"),
    "bin/spotify-control-agent.vbs": (4855,"2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278"),
}
BOOTSTRAP = {"version":"1.0.6","sha256":"d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6","size":42963}
PATH_NAMES = {
    "bin/spotify-control.ps1":"main-v0628-to-v0630",
    "bin/spotify-control-agent.vbs":"resident-v011-to-v012",
}


def sha(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def exact_file(path: Path, expected: tuple[int,str], label: str) -> bytes:
    b = path.read_bytes()
    if (len(b),sha(b)) != expected:
        raise RuntimeError("SOURCE_PIN_DRIFT_"+label)
    return b


def encode_chunks(path: str, before: bytes, after: bytes, root: Path):
    if path not in PATH_NAMES or before == after:
        raise RuntimeError("INVALID_OR_UNCHANGED_PATCH_TARGET")
    payload = bytearray(gzip.compress(after,mtime=0))
    if payload[:3] != bytes((31,139,8)) or len(payload) < 20:
        raise RuntimeError("GZIP_FORMAT_UNEXPECTED")
    # Standardize RFC1952 OS byte for deterministic Windows/Linux output.
    payload[9] = 255
    compressed = bytes(payload)
    encoded = base64.b64encode(compressed)
    chunks = [encoded[i:i+4096] for i in range(0,len(encoded),4096)]
    if not (1 <= len(chunks) <= 32):
        raise RuntimeError("BOOTSTRAP_CHUNK_BOUND_EXCEEDED")
    parts = []
    for i,b in enumerate(chunks):
        rel = "packages/v%s/%s/chunk-%03d.txt" % (VERSION,PATH_NAMES[path],i)
        dest = root / rel
        dest.parent.mkdir(parents=True,exist_ok=True)
        with dest.open("xb") as f:
            f.write(b)
        parts.append({"path":rel,"sha256":sha(b),"size":len(b)})
    if gzip.decompress(base64.b64decode(b"".join(chunks),validate=True)) != after:
        raise RuntimeError("NON_REPRODUCIBLE_FULL_FILE_PAYLOAD")
    return {
        "path":path,"from_sha256":sha(before),"to_sha256":sha(after),
        "encoding":"gzip-base64-full-file",
        "encoded_sha256":sha(encoded),"encoded_size":len(encoded),
        "compressed_sha256":sha(compressed),"compressed_size":len(compressed),
        "target_size":len(after),"chunks":parts,
    }


def build():
    if not (ROOT / ".git").exists():
        raise RuntimeError("GIT_WORKTREE_REQUIRED")
    if STAGE.exists():
        raise RuntimeError("STAGE_MUST_BE_NEW_NO_OVERWRITE")
    published = json.loads(LIVE_MANIFEST.read_text(encoding="utf-8-sig"))
    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    if (published.get("latest_version") != "0.6.28" or
        published.get("bootstrap") != BOOTSTRAP or
        published.get("source_commit") != "bb6d90146f20b73d36fbf8cb813f1b190f403c48" or
        len(published.get("updates",[])) != 18 or
        published.get("channel") != "stable"):
        raise RuntimeError("PUBLISHED_STABLE_BASELINE_DRIFT")
    if [(e.get("from_version"),e.get("to_version")) for e in published["updates"]][-1] != ("0.6.27","0.6.28"):
        raise RuntimeError("HISTORIC_EDGE_TIP_DRIFT")
    if set(row["path"] for row in published["latest_files"]) != set(BASE_SHA):
        raise RuntimeError("PUBLISHED_LATEST_FILES_SET_DRIFT")
    official = {p:exact_file((ORIGINAL/p.split("/")[-1]) if p.endswith(".ps1") else
                         ROOT / "validation/spotify-exit-immediate-maintenance-HOLD/out/_missing",
                         BASE_SHA[p],"OFFICIAL_"+p) for p in BASE_SHA if p.endswith(".ps1")}
    original_agent = runpy.run_path(
        str(ROOT/"validation/normal-engine-shared-turnstile/audit-pinned-stable-entrypoints-v059.py")
    )["extract_verified_agent"]()
    if (len(original_agent),sha(original_agent)) != BASE_SHA["bin/spotify-control-agent.vbs"]:
        raise RuntimeError("ORIGINAL_AGENT_PIN_DRIFT")
    official["bin/spotify-control-agent.vbs"] = original_agent
    for row in published["latest_files"]:
        if (row["size"],row["sha256"]) != BASE_SHA[row["path"]]:
            raise RuntimeError("MANIFEST_LATEST_FILE_HASH_DRIFT")
    new_main = (SOURCE/"spotify-control.ps1").read_bytes()
    new_agent = (SOURCE/"spotify-control-agent.vbs").read_bytes()
    marker = b'$ScriptVersion = "0.6.28"'
    if new_main.count(marker) != 1:
        raise RuntimeError("CANDIDATE_VERSION_MARKER_MISSING")
    new_main = new_main.replace(marker,b'$ScriptVersion = "0.6.30"',1)
    if new_main.count(b'$ScriptVersion = "0.6.30"') != 1:
        raise RuntimeError("FUTURE_VERSION_NOT_UNIQUE")
    latest = dict(official)
    latest.update({
        "bin/spotify-control.ps1":new_main,
        "bin/spotify-control-agent.vbs":new_agent,
    })
    if latest["bin/addon-manager.ps1"] != official["bin/addon-manager.ps1"]:
        raise RuntimeError("ADDON_R17_MUST_NOT_CHANGE")
    stage_parent = STAGE.parent
    stage_parent.mkdir(parents=True,exist_ok=True)
    temp = stage_parent / ".release-staging-incomplete"
    if temp.exists():
        raise RuntimeError("INCOMPLETE_STAGE_ALREADY_EXISTS")
    temp.mkdir(mode=0o700)
    try:
        patches = [
            encode_chunks(p,official[p],latest[p],temp)
            for p in ("bin/spotify-control.ps1","bin/spotify-control-agent.vbs")
        ]
        official_format = [
            o for o in schema["properties"]["updates"]["items"]["properties"]["patches"]["items"]["oneOf"]
            if o["properties"]["encoding"].get("const") == "gzip-base64-full-file"
        ]
        if len(official_format) != 1:
            raise RuntimeError("PATCH_SCHEMA_AMBIGUOUS")
        fmt = official_format[0]
        for p in patches:
            if set(p) != set(fmt["required"]):
                raise RuntimeError("PATCH_SCHEMA_KEYS_DRIFT")
            for ch in p["chunks"]:
                b=(temp/ch["path"]).read_bytes()
                if (len(b),sha(b)) != (ch["size"],ch["sha256"]):
                    raise RuntimeError("STAGED_CHUNK_BYTES_DIFFER")
        candidate = copy.deepcopy(published)
        candidate["source_commit"] = INVALID_COMMIT
        candidate["latest_version"] = VERSION
        candidate["latest_files"] = [
            {"path":p,"sha256":sha(b),"size":len(b)}
            for p,b in sorted(latest.items())
        ]
        canonical = "\n".join(
            "%s|%d|%s"%(p,len(b),sha(b)) for p,b in sorted(latest.items())
        )+"\n"
        candidate["payload_set_sha256"] = sha(canonical.encode("ascii"))
        candidate["updates"].append({
            "from_version":"0.6.28","to_version":VERSION,"patches":patches
        })
        if candidate["updates"][:-1] != published["updates"]:
            raise RuntimeError("HISTORICAL_STABLE_EDGES_CHANGED")
        for p,b in latest.items():
            dest=temp/p
            dest.parent.mkdir(parents=True,exist_ok=True)
            dest.write_bytes(b)
        (temp/"manifest-UNPUBLISHABLE.json").write_text(
            json.dumps(candidate,ensure_ascii=True,indent=2)+"\n",encoding="ascii",newline="\n"
        )
        receipt={
            "schema":1,
            "status":"STAGED_HOLD_NOT_PUBLISHABLE",
            "source_commit":INVALID_COMMIT,
            "bootstrap":BOOTSTRAP,
            "previous_version":"0.6.28","future_scratch_version":VERSION,
            "historic_edge_count":18,"new_edge_count":1,
            "patch_paths":[p["path"] for p in patches],
            "chunk_counts":[len(p["chunks"]) for p in patches],
            "payload_sha256":candidate["payload_set_sha256"],
            "manifest_sha256":sha((temp/"manifest-UNPUBLISHABLE.json").read_bytes()),
            "main_sha256":sha(new_main),
            "resident_sha256":sha(new_agent),
            "addon_r17_sha256":sha(latest["bin/addon-manager.ps1"]),
            "production_manifest_write":False,
            "publishable":False,
        }
        (temp/"stage-receipt.json").write_text(
            json.dumps(receipt,indent=2,sort_keys=True)+"\n",encoding="ascii",newline="\n"
        )
        # Atomic published-to-local-staging directory only: never modify
        # public packages/ or manifest.json, nor replace a previous stage.
        temp.rename(STAGE)
    finally:
        if temp.exists():
            shutil.rmtree(temp)
    print("FUTURE_STABLE_STAGE=COMPLETED_UNPUBLISHABLE")
    print("FUTURE_STABLE_STAGE_CHUNKS=%d"%(sum(len(p["chunks"]) for p in patches)))
    print("FUTURE_STABLE_STAGE_MANIFEST_SHA256="+receipt["manifest_sha256"])
    print("FUTURE_STABLE_STAGE_PAYLOAD_SHA256="+receipt["payload_sha256"])
    print("FUTURE_STABLE_STAGE_ADDON_R17=BYTE_IDENTICAL")
    print("PUBLIC_MANIFEST_AND_PACKAGES_UNCHANGED=YES")


if __name__=="__main__":
    build()
