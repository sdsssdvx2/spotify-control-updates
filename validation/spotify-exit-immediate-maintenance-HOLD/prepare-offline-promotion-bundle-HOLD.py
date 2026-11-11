"""Build one offline reviewable v0.6.30 Git promotion bundle; NEVER publish.

Only runs on an ephemeral GitHub-hosted Windows CI runner after existing
source, official Bootstrap, and owner preservation acceptance. Copies exactly
the already attested 20 immutable package chunks into a detached worktree
at the pinned *actual public main*, creates two sequential commits:
  1) immutable package objects, 2) manifest referencing commit 1.
Exports one incremental Git bundle + SHA-pinned receipt for review.

Never pushes, changes a repo ref, merges, updates a release, runs Bootstrap,
or touches a user's PC. The bundle REQUIRES pinned main as prerequisite.
"""
from __future__ import annotations

import copy
import hashlib
import json
import os
import re
from pathlib import Path
from importlib import util as importlib_util
import shutil
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
STAGE=HERE/"out"/"release-staging"
BASE_MAIN="d38e88d9ae99f6a4983e2ad64f74f6fce7e6cde2"
SCRATCH=Path(os.environ.get("RUNNER_TEMP","/invalid")).resolve()/"spotify-v0630-main-parent-promotion-review"
OUTPUT=HERE/"out"/"promotion-review-HOLD"
CHUNKS=20
BRANCH="hold-v0630-promotion"

def fail(reason: str):
    raise RuntimeError(reason)

def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def git(*args: str, cwd: Path=ROOT) -> str:
    p=subprocess.run(["git",*args],cwd=cwd,stdout=subprocess.PIPE,
                     stderr=subprocess.PIPE,check=False)
    if p.returncode:
        fail("OFFLINE_GIT_"+args[0].replace("-","_")+"_FAILED")
    return p.stdout.decode("utf-8").strip()

def canonical_file(path: Path, expected: int|None=None) -> bytes:
    if path.is_symlink() or not path.is_file():
        fail("EXPECTED_REGULAR_FILE_MISSING")
    data=path.read_bytes()
    if expected is not None and len(data)!=expected:
        fail("EXACT_FILE_SIZE_CHANGED")
    return data

def run():
    if (os.environ.get("GITHUB_ACTIONS")!="true" or
        os.environ.get("RUNNER_OS")!="Windows" or
        os.environ.get("RUNNER_ENVIRONMENT")!="github-hosted"):
        fail("CI_GITHUB_HOSTED_WINDOWS_REQUIRED")
    if git("rev-parse","origin/main")!=BASE_MAIN:
        fail("PUBLIC_MAIN_SHA_CHANGED")
    if git("rev-parse","HEAD")==BASE_MAIN:
        fail("HOLD_DEVELOPMENT_BRANCH_REQUIRED")
    if git("status","--porcelain","--","manifest.json","packages/"):
        fail("PUBLIC_TRACKED_OR_PACKAGE_PATHS_MODIFIED")
    if SCRATCH.exists():
        fail("PROMOTION_SCRATCH_ALREADY_EXISTS_NO_OVERWRITE")
    if OUTPUT.exists():
        fail("PROMOTION_OUTPUT_ALREADY_EXISTS_NO_OVERWRITE")
    old_raw=canonical_file(ROOT/"manifest.json")
    old=json.loads(old_raw.decode("utf-8-sig"))
    stage=json.loads(canonical_file(STAGE/"manifest-UNPUBLISHABLE.json").decode("ascii"))
    if (old.get("channel")!="stable" or old.get("latest_version")!="0.6.28" or
        len(old.get("updates",[]))!=18 or old.get("source_commit")!=
        "bb6d90146f20b73d36fbf8cb813f1b190f403c48"):
        fail("PUBLIC_BASELINE_UNEXPECTED")
    if (stage.get("source_commit")!="f"*40 or stage.get("channel")!="stable" or
        stage.get("latest_version")!="0.6.30" or
        len(stage.get("updates",[]))!=19 or
        stage["updates"][:18]!=old["updates"] or
        stage.get("bootstrap")!=old["bootstrap"]):
        fail("STAGED_UNPUBLISHABLE_HISTORY_INVALID")
    edge=stage["updates"][-1]
    if (edge.get("from_version")!="0.6.28" or edge.get("to_version")!="0.6.30"
        or [p.get("path") for p in edge.get("patches",[])]!=[
            "bin/spotify-control.ps1","bin/spotify-control-agent.vbs"]):
        fail("STAGED_RELEASE_EDGE_DRIFT")
    chunks=[c for p in edge["patches"] for c in p.get("chunks",[])]
    paths=[c["path"] for c in chunks]
    if (len(paths)!=CHUNKS or len(set(paths))!=CHUNKS or
        any(not p.startswith("packages/v0.6.30/") or
            "/../" in p or "\\" in p or p.startswith("/") for p in paths)):
        fail("STAGED_CHUNK_PATHS_NOT_EXACT")
    for c in chunks:
        raw=canonical_file(STAGE/c["path"],int(c["size"]))
        if sha(raw)!=c["sha256"]:
            fail("STAGED_CHUNK_CONTENT_MISMATCH")

    # Use a temporary worktree directly on the *actual* production main
    # commit. That way the bundle is strictly two fast-forward commits on
    # top of the current public baseline, NOT a detached synthetic root repo.
    SCRATCH.parent.mkdir(parents=True,exist_ok=True)
    git("worktree","add","--detach",str(SCRATCH),BASE_MAIN)
    output_created=False
    try:
        git("config","user.name","SpotifyControl HOLD Review Builder",cwd=SCRATCH)
        git("config","user.email","hold-review@users.noreply.github.com",cwd=SCRATCH)
        for c in chunks:
            src=STAGE/c["path"]
            dest=SCRATCH/c["path"]
            dest.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(src,dest)
        git("add","--","packages/v0.6.30",cwd=SCRATCH)
        source_changes=git("diff","--cached","--name-only",cwd=SCRATCH).splitlines()
        if sorted(source_changes)!=sorted(paths):
            fail("SOURCE_COMMIT_FILES_NOT_EXACT_EXPECTED")
        git("commit","-m","HOLD immutable v0.6.30 candidate payload (no public manifest)",cwd=SCRATCH)
        source_commit=git("rev-parse","HEAD",cwd=SCRATCH)
        if git("rev-parse","HEAD^",cwd=SCRATCH)!=BASE_MAIN:
            fail("PAYLOAD_COMMIT_NOT_DIRECT_CHILD_OF_PUBLIC_MAIN")
        candidate=copy.deepcopy(stage)
        candidate["source_commit"]=source_commit
        manifest_raw=(json.dumps(candidate,ensure_ascii=True,indent=2)+"\n").encode("ascii")
        (SCRATCH/"manifest.json").write_bytes(manifest_raw)
        git("add","--","manifest.json",cwd=SCRATCH)
        if git("diff","--cached","--name-only",cwd=SCRATCH).splitlines()!=["manifest.json"]:
            fail("MANIFEST_COMMIT_SCOPE_NOT_EXACT")
        git("commit","-m","HOLD candidate manifest referencing earlier source commit",cwd=SCRATCH)
        final_commit=git("rev-parse","HEAD",cwd=SCRATCH)
        if git("rev-parse","HEAD^",cwd=SCRATCH)!=source_commit:
            fail("MANIFEST_COMMIT_NOT_DIRECT_CHILD_OF_SOURCE")
        if git("rev-list","--count",BASE_MAIN+".."+final_commit,cwd=SCRATCH)!="2":
            fail("EXPECTED_EXACT_TWO_COMMIT_FAST_FORWARD_DELTA")

        # Reuse the existing real git SHA + compressed bytes proof, rather
        # than implementing a parallel transport checker.
        # Load as a persistent module, NOT runpy.run_path: CPython may
        # clear run_path function-global namespaces after returning, leaving
        # the verifier's imported Git helpers with stale/None globals.
        script=HERE/"verify-two-commit-future-release-HOLD.py"
        spec=importlib_util.spec_from_file_location("spotify_git_promotion_attest_hold",script)
        if spec is None or spec.loader is None:
            fail("SOURCE_ATTEST_MODULE_NOT_LOADABLE")
        checker=importlib_util.module_from_spec(spec)
        spec.loader.exec_module(checker)
        # Reuse exact verified attestation against this isolated worktree.
        # git() binds its default cwd at function definition, so update both.
        checker.SCRATCH=SCRATCH
        checker.STAGED=STAGE
        checker.EXPECTED_CHUNKS=CHUNKS
        # git(*args, cwd=...) declares cwd as KEYWORD-only. Updating
        # __defaults__ has no effect; use __kwdefaults__ for the real cwd.
        checker.git.__kwdefaults__["cwd"]=SCRATCH
        checker.attest(candidate,source_commit,final_commit)
        manifest_sha=sha(manifest_raw)
        OUTPUT.mkdir(parents=True,exist_ok=False)
        output_created=True
        bundle=OUTPUT/"v0630-two-commit-publication-NOT-AUTHORIZED.bundle"
        git("branch",BRANCH,final_commit,cwd=SCRATCH)
        git("bundle","create",str(bundle),"refs/heads/"+BRANCH,"^"+BASE_MAIN,cwd=SCRATCH)
        git("bundle","verify",str(bundle),cwd=ROOT)
        heads=git("bundle","list-heads",str(bundle),cwd=ROOT).splitlines()
        if heads!=[final_commit+" refs/heads/"+BRANCH]:
            fail("OFFLINE_BUNDLE_TIP_NOT_EXPECTED_MANIFEST_COMMIT")
        if not (500<len(bundle.read_bytes())<1_000_000):
            fail("BOUNDED_BUNDLE_CONTENT_INVALID")
        report={
            "schema":"SPOTIFY_V0630_OFFLINE_PROMOTION_BUNDLE_HOLD_V1",
            "status":"REVIEW_CANDIDATE_ONLY_NOT_AUTHORIZED_NOT_PUBLISHED",
            "base_public_main_commit":BASE_MAIN,
            "source_payload_commit":source_commit,
            "manifest_candidate_commit":final_commit,
            "manifest_sha256":manifest_sha,
            "payload_set_sha256":candidate["payload_set_sha256"],
            "source_package_chunks":CHUNKS,
            "git_commits_to_fast_forward":2,
            "bundle_name":bundle.name,
            "bundle_sha256":sha(bundle.read_bytes()),
            "bundle_size":bundle.stat().st_size,
            "public_manifest_changed":False,
            "github_ref_updated":False,
            "release_published":False,
            "operating_windows_modified":False,
            "owner_approval_granted":False
        }
        (OUTPUT/"promotion-receipt-HOLD.json").write_text(
            json.dumps(report,indent=2,sort_keys=True)+"\n",
            encoding="utf-8",newline="\n")
        if (ROOT/"manifest.json").read_bytes()!=old_raw:
            fail("PUBLIC_MAIN_MANIFEST_CHANGED_DURING_BUILD")
        if git("status","--porcelain","--","manifest.json","packages/"):
            fail("PUBLIC_PACKAGE_OR_MANIFEST_WORKTREE_CHANGED")
        print("PROMOTION_HOLD_SOURCE_COMMIT="+source_commit)
        print("PROMOTION_HOLD_MANIFEST_COMMIT="+final_commit)
        print("PROMOTION_HOLD_MANIFEST_SHA256="+manifest_sha)
        print("PROMOTION_HOLD_BUNDLE_SHA256="+report["bundle_sha256"])
        print("PROMOTION_HOLD_TWO_COMMIT_REAL_MAIN_ANCESTRY=PASS")
        print("PROMOTION_HOLD_IMMUTABLE_"+str(CHUNKS)+"_CHUNKS_AT_SOURCE_COMMIT=PASS")
        print("RELEASE_PUBLISHED=NO;REPOSITORY_REF_UPDATED=NO;USER_PC_CHANGES=NO")
    except:
        if output_created:
            shutil.rmtree(OUTPUT,ignore_errors=True)
        raise
    finally:
        git("worktree","remove","--force",str(SCRATCH))
        if SCRATCH.exists():
            fail("TEMP_PROMOTION_WORKTREE_NOT_CLEANED")

if __name__=="__main__":
    if sys.argv[1:]:
        raise SystemExit("No parameters: GitHub-hosted HOLD only.")
    try:
        run()
    except Exception as exc:
        # These are internal fixed failure labels; never emit Git stderr,
        # runner paths, environment, user data, or arbitrary exception text.
        reason=str(exc)
        if type(exc) is RuntimeError and re.fullmatch(r"[A-Za-z0-9_]{1,96}",reason):
            print("PROMOTION_BUNDLE_HOLD_REASON="+reason.upper())
        else:
            print("PROMOTION_BUNDLE_HOLD_REASON=UNVERIFIED_INTERNAL_ERROR")
        print("PROMOTION_BUNDLE_RESULT=HOLD_"+type(exc).__name__.upper())
        raise SystemExit(1)
