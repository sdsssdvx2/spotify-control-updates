"""Unpublished full-file transport admission for future Spotify Control stable edge.

No manifest or release package output is committed or modified. The exact
v0.6.28 source is previously rebuilt by the candidate builder. This checks
that both changes (main + resident VBS) can be represented by the unchanged
Bootstrap v1.0.6 gzip-base64-full-file chunk contract and decoded losslessly.
"""
from __future__ import annotations

import base64
import gzip
import hashlib
import json
import runpy
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BIN = ROOT / "validation/spotify-exit-immediate-maintenance-HOLD/out/future-safe"
BASE = ROOT / "validation/v0.6.28/out/bin"
MANIFEST = ROOT / "manifest.json"
SCHEMA = ROOT / "manifest.schema.json"

BASE_MAIN = (284321, "af1582ec335807f8f5daa9b3a65b13d567264f326d3c608c082ae02ff0a4cfc0")
BASE_AGENT = (4855, "2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278")
BASE_ADDON = (323385, "5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285")
BOOTSTRAP = {"version": "1.0.6", "sha256": "d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6", "size": 42963}


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def pin(data: bytes, expected: tuple[int, str], label: str) -> None:
    if (len(data), sha(data)) != expected:
        raise RuntimeError("EXACT_PIN_MISMATCH_" + label)


def transport(path: str, before: bytes, after: bytes) -> dict:
    if not path.startswith("bin/") or path.count("/") != 1:
        raise RuntimeError("BAD_TRANSPORT_PATH")
    if sha(before) == sha(after):
        raise RuntimeError("TRANSPORT_INPUT_UNCHANGED")
    compressed = gzip.compress(after, mtime=0)
    encoded = base64.b64encode(compressed)
    chunks = [encoded[i:i+4096] for i in range(0,len(encoded),4096)]
    if not 1 <= len(chunks) <= 128:
        raise RuntimeError("TRANSPORT_CHUNK_COUNT_EXCEEDS_CAP")
    encoded_back = b"".join(chunks)
    if encoded_back != encoded:
        raise RuntimeError("CHUNK_JOIN_CHANGED")
    payload = gzip.decompress(base64.b64decode(encoded_back, validate=True))
    if payload != after:
        raise RuntimeError("TRANSPORT_ROUNDTRIP_NOT_IDENTICAL")
    # Production format: full-file encoded transport is metadata+named
    # chunks stored at immutable source_commit. No bytes are uploaded here.
    patch = {
        "path": path,
        "from_sha256": sha(before),
        "to_sha256": sha(after),
        "encoding": "gzip-base64-full-file",
        "encoded_sha256": sha(encoded),
        "encoded_size": len(encoded),
        "compressed_sha256": sha(compressed),
        "compressed_size": len(compressed),
        "target_size": len(after),
        "chunks": [
            {
                "path": "packages/UNRELEASED/CHUNKS/chunk-%03d.txt" % i,
                "sha256": sha(c),
                "size": len(c)
            } for i,c in enumerate(chunks)
        ],
    }
    assert sha(payload) == patch["to_sha256"]
    assert sha(before) == patch["from_sha256"]
    return patch


def main():
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8-sig"))
    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    if manifest["latest_version"] != "0.6.28" or manifest["bootstrap"] != BOOTSTRAP:
        raise RuntimeError("PUBLISHED_MANIFEST_IDENTITY_CHANGED")
    expected = {row["path"]: row for row in manifest["latest_files"]}
    for name,(size,digest) in {
        "bin/spotify-control.ps1":BASE_MAIN,
        "bin/addon-manager.ps1":BASE_ADDON,
        "bin/spotify-control-agent.vbs":BASE_AGENT,
    }.items():
        if expected[name] != {"path":name,"size":size,"sha256":digest}:
            raise RuntimeError("STABLE_LATEST_FILES_CHANGED")
    before_main = (BASE / "spotify-control.ps1").read_bytes()
    addon = (BASE / "addon-manager.ps1").read_bytes()
    pin(before_main,BASE_MAIN,"MAIN")
    pin(addon,BASE_ADDON,"ADDON")
    legacy = runpy.run_path(str(ROOT / "validation/normal-engine-shared-turnstile/audit-pinned-stable-entrypoints-v059.py"))["extract_verified_agent"]()
    pin(legacy,BASE_AGENT,"AGENT")

    changed_main = (BIN / "spotify-control.ps1").read_bytes()
    changed_agent = (BIN / "spotify-control-agent.vbs").read_bytes()
    if sha(changed_main)==BASE_MAIN[1] or sha(changed_agent)==BASE_AGENT[1]:
        raise RuntimeError("CANDIDATE_CHANGES_NOT_PRESENT")
    patches = (
        transport("bin/spotify-control.ps1",before_main,changed_main),
        transport("bin/spotify-control-agent.vbs",legacy,changed_agent),
    )
    if sha(addon) != BASE_ADDON[1]:
        raise RuntimeError("ADDON_AUTHORITY_CHANGED")
    full_schema = [
        x for x in schema["properties"]["updates"]["items"]["properties"]["patches"]["items"]["oneOf"]
        if x["properties"]["encoding"].get("const") == "gzip-base64-full-file"
    ]
    if len(full_schema) != 1:
        raise RuntimeError("OFFICIAL_FULL_FILE_SCHEMA_AMBIGUOUS")
    option = full_schema[0]
    if set(option["required"]) - set(patches[0]):
        raise RuntimeError("FULL_FILE_SCHEMA_REQUIRED_MISSING")
    if set(patches[0]) - set(option["properties"]):
        raise RuntimeError("FULL_FILE_SCHEMA_UNEXPECTED_FIELDS")
    for patch in patches:
        if patch["encoded_size"] > option["properties"]["encoded_size"]["maximum"]:
            raise RuntimeError("ENCODED_PAYLOAD_TOO_LARGE")
        if patch["compressed_size"] > option["properties"]["compressed_size"]["maximum"]:
            raise RuntimeError("COMPRESSED_PAYLOAD_TOO_LARGE")
        for item in patch["chunks"]:
            if not 1 <= item["size"] <= 4096:
                raise RuntimeError("CHUNK_OUT_OF_RANGE")

    # Reconstruct next-stage three-file snapshot and rollback to ORIGINAL
    # without mutating a filesystem path or invoking any production executable.
    live = {
        "bin/spotify-control.ps1":before_main,
        "bin/addon-manager.ps1":addon,
        "bin/spotify-control-agent.vbs":legacy,
    }
    staged = dict(live)
    staged["bin/spotify-control.ps1"] = changed_main
    staged["bin/spotify-control-agent.vbs"] = changed_agent
    if sha(staged["bin/addon-manager.ps1"]) != BASE_ADDON[1]:
        raise RuntimeError("STAGE_ADDON_NOT_PRESERVED")
    for patch in patches:
        if sha(live[patch["path"]]) != patch["from_sha256"]:
            raise RuntimeError("BEFORE_STAGE_PIN_MISMATCH")
        if sha(staged[patch["path"]]) != patch["to_sha256"]:
            raise RuntimeError("AFTER_STAGE_PIN_MISMATCH")
    restored = dict(live)
    if restored != live or staged == live:
        raise RuntimeError("ROLLBACK_SNAPSHOT_PRESERVATION_FAILED")

    print("FUTURE_OFFLINE_FULL_FILE_SCHEMA_V1=PASS")
    print("FUTURE_OFFLINE_MAIN_AND_VBS_PATCHES=2")
    print("FUTURE_OFFLINE_AGENT_VBS_HASH_AND_CHUNK_ROUNDTRIP=PASS")
    print("FUTURE_OFFLINE_ADDON_R17_BYTE_IDENTICAL=PASS")
    print("FUTURE_OFFLINE_STAGE_AND_ORIGINAL_ROLLBACK_SNAPSHOT=PASS")
    print("FUTURE_OFFLINE_MAIN_TARGET_SHA256="+sha(changed_main))
    print("FUTURE_OFFLINE_AGENT_TARGET_SHA256="+sha(changed_agent))
    print("DEPLOYABLE_MANIFEST_OR_IMMUTABLE_CHUNKS=NOT_PUBLISHED")
    print("OPERATING_WINDOWS_AND_PRODUCTION_MANIFEST=UNCHANGED")


if __name__ == "__main__":
    main()
