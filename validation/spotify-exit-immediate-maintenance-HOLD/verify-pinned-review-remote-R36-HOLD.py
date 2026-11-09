"""R36: independently read the actual public-GitHub HOLD review transport.

This is NOT a production release or an owner-approved installation.
It reuses R29's actual network/manifest/immutable-chunk attestor unmodified,
with the frozen R35 review branch instead of published main as the candidate.
No git writes, no settings access, and no PC, Spotify, or Bootstrap execution.
"""
from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
EXPECTED_REVIEW_BRANCH="hold/spotify-v0630-review-only"
EXPECTED_SOURCE="79b3654d5729fb7965c017809df34b6b4191b25c"
EXPECTED_MANIFEST_SHA="7bd98381349cbc99cf861860e0dc74120ba617c8b4aaa11c796b114abe5e85ab"
EXPECTED_PAYLOAD_SET="45f1614421042093ed0b2e49dc1a60edef4e6213d0c7d1a0642d8eb3eec33589"

def run():
    if (os.getenv("GITHUB_ACTIONS")!="true" or
        os.getenv("GITHUB_EVENT_NAME")!="push" or
        os.getenv("GITHUB_REPOSITORY")!="sdsssdvx2/spotify-control-updates" or
        os.getenv("GITHUB_REF")!="refs/heads/validate/spotify-exit-immediate-maintenance-HOLD"):
        raise RuntimeError("READ_ONLY_GITHUB_HOLD_CI_REQUIRED")
    path=HERE/"verify-public-release-transport-R29-HOLD.py"
    spec=importlib.util.spec_from_file_location("spotify_r29_original_readonly",path)
    if spec is None or spec.loader is None:
        raise RuntimeError("ORIGINAL_R29_AUDITOR_NOT_LOADABLE")
    r29=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(r29)
    # Historic shortcut-only review remains independently readable after R29
    # switches the real future release target to the integrated candidate.
    r29.FUTURE=dict(r29.FUTURE)
    r29.FUTURE["bin/spotify-control.ps1"]="37eda0638c428ed3474a06812c067ca10f5771216ae509d3cd4ce10fdafbd3ec"
    raw_baseline=r29.download(r29.RAW+r29.BASE_MAIN_COMMIT+"/manifest.json",200_000)
    checked_in=(ROOT/"manifest.json").read_bytes()
    if raw_baseline!=checked_in:
        raise RuntimeError("PUBLISHED_BASELINE_BYTES_CHANGED")
    original=r29.parse_manifest(raw_baseline,"ORIGINAL")
    if (original.get("latest_version")!="0.6.28" or
        original.get("source_commit")!=r29.BASE_PAYLOAD_COMMIT or
        len(original.get("updates",[]))!=18):
        raise RuntimeError("PUBLIC_STABLE_BASELINE_NOT_EXACT")
    r29.validate_latest(original,r29.ORIGINAL)
    current_public=r29.download(r29.RAW+"main/manifest.json",200_000)
    if current_public!=raw_baseline:
        raise RuntimeError("PUBLIC_MAIN_WAS_NOT_PRESERVED")
    remote=r29.download(
        r29.RAW+EXPECTED_REVIEW_BRANCH+"/manifest.json",200_000
    )
    if r29.hash_bytes(remote)!=EXPECTED_MANIFEST_SHA:
        raise RuntimeError("REMOTE_REVIEW_MANIFEST_SHA_NOT_PINNED")
    review=r29.parse_manifest(remote,"REVIEW")
    if review.get("source_commit")!=EXPECTED_SOURCE:
        raise RuntimeError("REVIEW_SOURCE_COMMIT_NOT_PINNED")
    facts=r29.attest_future_release(
        remote,original,EXPECTED_MANIFEST_SHA,EXPECTED_SOURCE
    )
    if (facts.get("status")!="PUBLIC_SOURCE_AND_PAYLOAD_READONLY_VERIFIED_NOT_OWNER_AUTHORIZED" or
        facts.get("source_commit")!=EXPECTED_SOURCE or
        facts.get("manifest_sha256")!=EXPECTED_MANIFEST_SHA or
        facts.get("payload_set_sha256")!=EXPECTED_PAYLOAD_SET or
        facts.get("chunk_count")!=20 or
        facts.get("to_version")!="0.6.30" or
        facts.get("main_sha256")!=r29.FUTURE["bin/spotify-control.ps1"] or
        facts.get("agent_sha256")!=r29.FUTURE["bin/spotify-control-agent.vbs"]):
        raise RuntimeError("ORIGINAL_R29_RECEIPT_NOT_EXACT_PINNED_REVIEW")
    print("R36_ACTUAL_PUBLIC_GITHUB_REVIEW_MANIFEST_SHA256=PASS")
    print("R36_ACTUAL_SOURCE_COMMIT_IMMUTABLE_20_CHUNKS=PASS")
    print("R36_R29_ACTUAL_RAW_DOWNLOAD_AND_TWO_PAYLOAD_BYTES=PASS")
    print("R36_PUBLISHED_MAIN_V0628=BYTE_IDENTICAL")
    print("R36_REVIEW_SHA_IS_NOT_OWNER_APPROVAL_AND_NOT_RELEASE=YES")
    print("R36_NETWORK=READONLY_PUBLIC_RAW_GITHUB_ONLY;GIT_WRITE=NO")
    print("R36_RESULT=PINNED_PUBLIC_REVIEW_TRANSPORT_VERIFIED_NO_DEPLOY")

if __name__=="__main__":
    try:
        if sys.argv[1:]:
            raise RuntimeError("R36_NO_RUNTIME_OVERRIDES")
        run()
    except Exception as exc:
        # R29 already bounds requests. Never log original URLs or response data.
        print("R36_RESULT=HOLD_"+type(exc).__name__.upper())
        raise SystemExit(1)
