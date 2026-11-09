"""R40 HOLD: real remote GitHub readback for the *combined functional*
v0.6.30 review candidate. Never publish or authorize a release.

Runs the unchanged official R29 network+digest verifier on the actual
long-lived R39 review branch, with a review-scoped expected main payload
SHA bound to the R37/R38 independently accepted combination.
"""
from __future__ import annotations
from importlib import util
import os
from pathlib import Path
import sys

HERE=Path(__file__).resolve().parent
BRANCH="hold/spotify-v0630-integrated-review-only"
SOURCE="94dbf3b5f4149fb3d82fffa3f58af16cbb4ec58a"
MANIFEST_SHA="453f25e62d25ecffd1bbf52fdb7d5ce5a2fadfe99f4f23b057dac5bda7257a2c"
TARGET_MAIN="7caf4afe19c283aef3b5bebb30e0e598b10de147d3ab1ddd9724bf90594c59fe"
TARGET_AGENT="da054351cae6927504e735426d35f6d5e7edafcac7e06881f1adf1c20cecab9d"
TARGET_SET="1aa7873a4e575d11c0312f13d3c2ebcf30753d391a0d08f012f4f5e2b80fc039"

def main():
    if (os.getenv("GITHUB_ACTIONS")!="true" or
        os.getenv("GITHUB_EVENT_NAME")!="push" or
        os.getenv("GITHUB_REPOSITORY")!="sdsssdvx2/spotify-control-updates" or
        os.getenv("GITHUB_REF")!="refs/heads/validate/spotify-exit-immediate-maintenance-HOLD"):
        raise RuntimeError("R40_GITHUB_HOLD_READONLY_ENV_REQUIRED")
    spec=util.spec_from_file_location("spotify_r29_exact_readonly_implementation",
        HERE/"verify-public-release-transport-R29-HOLD.py")
    if spec is None or spec.loader is None:
        raise RuntimeError("R40_R29_SOURCE_NOT_LOADABLE")
    auditor=util.module_from_spec(spec)
    spec.loader.exec_module(auditor)
    baseline_raw=auditor.download(
        auditor.RAW+auditor.BASE_MAIN_COMMIT+"/manifest.json",200_000)
    live_main=auditor.download(
        auditor.RAW+"main/manifest.json",200_000)
    if live_main!=baseline_raw:
        raise RuntimeError("R40_PUBLIC_MAIN_PROVENANCE_DRIFT")
    baseline=auditor.parse_manifest(baseline_raw,"ORIGINAL")
    auditor.validate_latest(baseline,auditor.ORIGINAL)
    if (baseline["latest_version"]!="0.6.28" or
        baseline["source_commit"]!=auditor.BASE_PAYLOAD_COMMIT or
        len(baseline["updates"])!=18):
        raise RuntimeError("R40_PUBLIC_HISTORY_DRIFT")

    # The old R29 release constants deliberately describe R34's historical
    # shortcut-only candidate. Override its *in-memory*, not on-disk,
    # target for the distinct R39 review. This is NOT approval to replace
    # the real public release's expected SHA in R28.
    auditor.FUTURE=dict(auditor.FUTURE)
    auditor.FUTURE["bin/spotify-control.ps1"]=TARGET_MAIN
    review_raw=auditor.download(auditor.RAW+BRANCH+"/manifest.json",200_000)
    if auditor.hash_bytes(review_raw)!=MANIFEST_SHA:
        raise RuntimeError("R40_IMMUTABLE_REVIEW_MANIFEST_SHA_CHANGED")
    review=auditor.parse_manifest(review_raw,"REVIEW")
    if review.get("source_commit")!=SOURCE:
        raise RuntimeError("R40_INTEGRATED_SOURCE_REF_NOT_PINNED")
    facts=auditor.attest_future_release(
        review_raw,baseline,MANIFEST_SHA,SOURCE)
    if (facts["status"]!="PUBLIC_SOURCE_AND_PAYLOAD_READONLY_VERIFIED_NOT_OWNER_AUTHORIZED" or
        facts["source_commit"]!=SOURCE or
        facts["manifest_sha256"]!=MANIFEST_SHA or
        facts["payload_set_sha256"]!=TARGET_SET or
        facts["main_sha256"]!=TARGET_MAIN or
        facts["agent_sha256"]!=TARGET_AGENT or
        facts["chunk_count"]!=20 or
        facts["to_version"]!="0.6.30"):
        raise RuntimeError("R40_INTEGRATED_R29_FACTUAL_RECEIPT_MISMATCH")
    print("R40_REAL_GITHUB_REVIEW_MANIFEST_SHA_AND_PUBLIC_MAIN_STABLE=PASS")
    print("R40_REAL_IMMUTABLE_20_CHUNKS_AND_FULL_MAIN_VBS_SHA=PASS")
    print("R40_FUTURE_EXIT_DISCOVERY_AND_SAFE_SHORTCUT_COMBINED_BYTES=PINNED")
    print("R40_OFFICIAL_MAIN_RELEASE=UNCHANGED;OWNER_APPROVAL=NOT_GRANTED")
    print("R40_PUBLIC_READONLY_TRANSPORT=VERIFIED_HOLD_NO_DEPLOY")

if __name__=="__main__":
    try:
        if sys.argv[1:]:
            raise RuntimeError("R40_NO_RUNTIME_OVERRIDES")
        main()
    except Exception as exc:
        print("R40_RESULT=HOLD_"+type(exc).__name__.upper())
        raise SystemExit(1)
