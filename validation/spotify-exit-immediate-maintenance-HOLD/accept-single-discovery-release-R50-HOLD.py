"""R50 HOLD: accept and preserve final single-discovery agent v0.6.30
without disturbing prior v0.6.30 historical reviews or main.

Modes:
 prepare-win: reuse original R43 owner-cutover test with new R49 main,
    same SHA-pinned R45 event VBS, exact R28 historical hosted process test
    protected against unrelated later workflow edits by comparing its block.
 prepare-bundle: reuse original R39 real-main-parent two-Git-commit author.
 custody-linux: reuse original R35 full source/manifest immutable proof to
    create only a NEW hold/spotify-v0630-singlecheck-review-only ref.

No production manifest update, no release, no user PC access.
"""
from __future__ import annotations
import hashlib
from importlib import util
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
STAGE=HERE/"out"/"release-staging-single-discovery-R49"
REVIEW=HERE/"out"/"promotion-review-single-discovery-R50"
MAIN="4ec5bc6c6612ab15fc297d474b193d228b9dab8eb5b79cd7b14042af5b72c93c"
AGENT="1c1563bff9b9a87ae851b4ca555429b5451ce67c6d225a148b5252256d71cdf7"
ADDON="5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285"
OLD_R28_WORKFLOW_BLOB="ab0488b61120431a9a9a3ee68a7228448c29d126"
EXPECTED_CHUNKS=20
REF="refs/heads/hold/spotify-v0630-singlecheck-review-only"

def sha(b:bytes)->str:
    return hashlib.sha256(b).hexdigest()

def module(name:str,filename:str):
    spec=util.spec_from_file_location(name,HERE/filename)
    if spec is None or spec.loader is None:
        raise RuntimeError("R50_PREVIOUS_VERIFIED_MODULE_UNAVAILABLE")
    m=util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m

def inspect_stage():
    manifest=json.loads((STAGE/"manifest-UNPUBLISHABLE.json").read_text("ascii"))
    files={r["path"]:r["sha256"] for r in manifest["latest_files"]}
    if (files!={"bin/spotify-control.ps1":MAIN,
                 "bin/spotify-control-agent.vbs":AGENT,
                 "bin/addon-manager.ps1":ADDON} or
        manifest.get("latest_version")!="0.6.30" or
        manifest.get("source_commit")!="f"*40 or
        len(manifest.get("updates",[]))!=19 or
        sum(len(p["chunks"]) for p in manifest["updates"][-1]["patches"])!=EXPECTED_CHUNKS):
        raise RuntimeError("R50_R49_FULLFILE_INTEGRATION_SHA_OR_SCOPE_DRIFT")
    return manifest

def git(*args):
    return subprocess.run(["git",*args],cwd=ROOT,capture_output=True,check=True).stdout

def prepare_win():
    if (os.getenv("GITHUB_ACTIONS")!="true" or
        os.getenv("RUNNER_OS")!="Windows" or
        os.getenv("RUNNER_ENVIRONMENT")!="github-hosted"):
        raise RuntimeError("R50_HOSTED_WINDOWS_ONLY")
    inspect_stage()
    r43=module("spotify_r50_exact_r43_hosted_owner_cutover",
               "reuse-integrated-owner-cutover-R43-HOLD.py")
    # The workflow evolved in R41/R47 but the R28 owner-process exercise
    # MUST be bitwise identical to the previously accepted R43 source.
    original=git("cat-file","blob",OLD_R28_WORKFLOW_BLOB).decode("utf-8")
    current=r43.TARGET.read_text("utf-8")
    for token in (r43.BEGIN,r43.END):
        if original.count(token)!=1 or current.count(token)!=1:
            raise RuntimeError("R50_R28_EXACT_HOSTED_SOURCE_REGION_NOT_UNIQUE")
    old_run=original.split(r43.BEGIN,1)[1].split(r43.END,1)[0]
    new_run=current.split(r43.BEGIN,1)[1].split(r43.END,1)[0]
    if old_run!=new_run:
        raise RuntimeError("R50_R28_ACCEPTED_REAL_OWNER_PROCESS_CODE_CHANGED")
    current_blob=git("rev-parse",":"+r43.TARGET.relative_to(ROOT).as_posix()).decode().strip()
    r43.SOURCE_BLOB=current_blob
    r43.COMBINED=STAGE.relative_to(ROOT).as_posix()
    r43.MAIN_SHA=MAIN
    r43.AGENT_SHA=AGENT
    r43.run()
    prepare=Path(os.environ["RUNNER_TEMP"]).resolve()/"spotify-r43-integrated-prepare.py"
    raw=prepare.read_text("utf-8")
    old_path="out/release-staging-combined"
    new_path="out/release-staging-single-discovery-R49"
    if raw.count(old_path)!=1 or new_path in raw:
        raise RuntimeError("R50_R43_PREPARER_PATH_DRIFT")
    prepare.write_text(raw.replace(old_path,new_path,1),encoding="utf-8")
    if old_path in prepare.read_text("utf-8"):
        raise RuntimeError("R50_PRIOR_STAGED_PAYLOAD_STILL_SELECTED")
    print("R50_OWNER_CUTOVER_ORIGINAL_R28_EXACT_BLOCK=BYTE_IDENTICAL")
    print("R50_REAL_INSTALLER_PREPARED_FOR_SINGLE_DISCOVERY_MAIN_SHA256="+MAIN)
    print("R50_NATIVE_R43_ROLLBACK_AND_SHORTCUT_PRESERVATION=NOT_CHANGED")

def bundle_win():
    if (os.getenv("GITHUB_ACTIONS")!="true" or
        os.getenv("RUNNER_OS")!="Windows" or
        os.getenv("RUNNER_ENVIRONMENT")!="github-hosted"):
        raise RuntimeError("R50_HOSTED_WINDOWS_ONLY")
    manifest=inspect_stage()
    m=module("spotify_r50_exact_r39_main_parent_bundle",
             "build-integrated-review-git-bundle-R39-HOLD.py")
    m.STAGE=STAGE
    m.REVIEW=REVIEW
    m.PIN_NEW_MAIN=MAIN
    m.PIN_AGENT=AGENT
    m.EXPECTED_CHUNKS=EXPECTED_CHUNKS
    m.main()
    record=json.loads((REVIEW/"promotion-receipt-HOLD.json").read_text("utf-8"))
    if (record.get("status")!="REVIEW_CANDIDATE_ONLY_NOT_AUTHORIZED_NOT_PUBLISHED" or
        record.get("source_package_chunks")!=EXPECTED_CHUNKS or
        record.get("payload_set_sha256")!=manifest["payload_set_sha256"] or
        record.get("git_commits_to_fast_forward")!=2 or
        record.get("release_published") is not False or
        record.get("github_ref_updated") is not False or
        record.get("owner_approval_granted") is not False):
        raise RuntimeError("R50_VERIFIED_REVIEW_BUNDLE_RECEIPT_DRIFT")
    print("R50_FULL_INTEGRATED_FUNCTIONAL_REVIEW_GIT_BUNDLE=SHA256_PASS")
    print("R50_PUBLIC_MAIN_CHANGED=NO;USER_PC_CHANGED=NO")

def custody_linux():
    if (os.getenv("GITHUB_ACTIONS")!="true" or
        os.getenv("RUNNER_OS")!="Linux" or
        os.getenv("GITHUB_REF")!="refs/heads/validate/spotify-exit-immediate-maintenance-HOLD"):
        raise RuntimeError("R50_RESTRICTED_LINUX_HOLD_CUSTODY_ONLY")
    c=module("spotify_r50_reuse_r35_real_git_custody",
             "persist-review-ref-HOLD.py")
    c.REVIEW_REF=REF
    c.EXPECTED_CHUNKS=EXPECTED_CHUNKS
    c.PREVIEW_TARGETS=dict(c.PREVIEW_TARGETS)
    c.PREVIEW_TARGETS["bin/spotify-control.ps1"]=MAIN
    c.PREVIEW_TARGETS["bin/spotify-control-agent.vbs"]=AGENT
    c.main()
    print("R50_NEW_SINGLE_DISCOVERY_REVIEW_BRANCH_IMMUTABLE_PROVEN=PASS")
    print("R50_PRIOR_REVIEW_REFS_AND_PUBLIC_MAIN_UNMODIFIED=PASS")

if __name__=="__main__":
    if len(sys.argv)!=2 or sys.argv[1] not in ("prepare-win","bundle-win","custody-linux"):
        raise SystemExit("Usage: R50 prepare-win|bundle-win|custody-linux")
    {"prepare-win":prepare_win,"bundle-win":bundle_win,
     "custody-linux":custody_linux}[sys.argv[1]]()
