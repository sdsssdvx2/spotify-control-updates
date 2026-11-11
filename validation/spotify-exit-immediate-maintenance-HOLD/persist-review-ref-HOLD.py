"""Custody only: preserve R34's exact accepted Git bundle on an isolated review ref.

No release creation, no main ref movement, no user PC access, and no fallback
ref. Run ONLY in a separate post-acceptance GitHub Actions job with scoped
contents:write, after native Windows admission and immutable bundle SHA proof.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
ARTEFACT=ROOT/"review-artifact"
BUNDLE=ARTEFACT/"v0630-two-commit-publication-NOT-AUTHORIZED.bundle"
RECEIPT=ARTEFACT/"promotion-receipt-HOLD.json"
BASE="d38e88d9ae99f6a4983e2ad64f74f6fce7e6cde2"
SOURCE_REF="refs/heads/hold-v0630-promotion"
REVIEW_REF="refs/heads/hold/spotify-v0630-review-only"
REPO="sdsssdvx2/spotify-control-updates"
CI_REF="refs/heads/validate/spotify-exit-immediate-maintenance-HOLD"
EXPECTED_CHUNKS=20
PREVIEW_TARGETS={
 "bin/spotify-control.ps1":"37eda0638c428ed3474a06812c067ca10f5771216ae509d3cd4ce10fdafbd3ec",
 "bin/spotify-control-agent.vbs":"da054351cae6927504e735426d35f6d5e7edafcac7e06881f1adf1c20cecab9d",
 "bin/addon-manager.ps1":"5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285"
}
HEX40=re.compile(r"^[0-9a-f]{40}$")
HEX64=re.compile(r"^[0-9a-f]{64}$")

def deny(label):
    raise RuntimeError(label)

def sha(raw:bytes)->str:
    return hashlib.sha256(raw).hexdigest()

def git(*args:str)->str:
    proc=subprocess.run(["git",*args],cwd=ROOT,stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,check=False,timeout=90)
    if proc.returncode!=0:
        deny("GIT_"+re.sub("[^A-Z0-9]","_",args[0].upper())+"_FAILED")
    return proc.stdout.decode("utf-8",errors="replace").strip()

def object_at(commit:str,path:str)->bytes:
    if not HEX40.fullmatch(commit) or path.startswith("/") or ".." in path or "\\" in path:
        deny("UNSAFE_GIT_OBJECT_SELECTOR")
    proc=subprocess.run(["git","show",commit+":"+path],cwd=ROOT,
        stdout=subprocess.PIPE,stderr=subprocess.PIPE,check=False,timeout=45)
    if proc.returncode:
        deny("IMMUTABLE_GIT_BLOB_UNAVAILABLE")
    return proc.stdout

def metadata(raw:bytes)->dict:
    obj=json.loads(raw.decode("utf-8"))
    if not isinstance(obj,dict):
        deny("INVALID_MANIFEST_SHAPE")
    return obj

def inspect_commit(source_sha:str,manifest_sha:str,expected_manifest:dict,
                   current_public:dict)->None:
    if source_sha==manifest_sha or not HEX40.fullmatch(source_sha) or not HEX40.fullmatch(manifest_sha):
        deny("WRONG_SOURCE_COMMIT_ID")
    if git("rev-parse",source_sha+"^")!=BASE:
        deny("SOURCE_COMMIT_NOT_DIRECT_PUBLIC_MAIN_CHILD")
    if git("rev-parse",manifest_sha+"^")!=source_sha:
        deny("MANIFEST_COMMIT_NOT_DIRECT_SOURCE_CHILD")
    if git("rev-list","--count",BASE+".."+manifest_sha)!="2":
        deny("REVIEW_NOT_EXACT_TWO_FAST_FORWARD_COMMITS")
    manifest_changes=git("diff","--name-only",source_sha,manifest_sha).splitlines()
    if manifest_changes!=["manifest.json"]:
        deny("REVIEW_MANIFEST_COMMIT_CHANGED_UNRELATED_FILES")
    raw=object_at(manifest_sha,"manifest.json")
    got=metadata(raw)
    if got.get("source_commit")!=source_sha:
        deny("MANIFEST_SOURCE_COMMIT_REFERENCE_NOT_IMMUTABLE")
    # Exact candidate semantics, allowing only the Git source SHA to differ
    # between two time-stamped builds of identical v0.6.30 content.
    x=dict(got); x.pop("source_commit",None)
    y=dict(expected_manifest); y.pop("source_commit",None)
    if x!=y or got.get("latest_version")!="0.6.30":
        deny("REVIEW_MANIFEST_CONTENT_DIFFERS_FROM_R34_CANDIDATE")
    if got.get("updates",[])[:18]!=current_public.get("updates",[]):
        deny("REVIEW_HISTORY_CHANGED")
    latest=got.get("latest_files",[])
    if not isinstance(latest,list) or len(latest)!=3 or {
         p.get("path"):p.get("sha256") for p in latest}!=PREVIEW_TARGETS:
        deny("REVIEW_LATEST_FILE_TARGET_DIGEST_DRIFT")
    rows="".join(
        f"{p['path']}|{p['size']}|{p['sha256']}\n" for p in sorted(latest,key=lambda q:q["path"])
    )
    if got.get("payload_set_sha256")!=sha(rows.encode("ascii")):
        deny("REVIEW_CANONICAL_PAYLOAD_SET_MISMATCH")
    edge=got.get("updates",[])[-1]
    if edge.get("from_version")!="0.6.28" or edge.get("to_version")!="0.6.30":
        deny("REVIEW_NOT_EXACT_FORWARD_EDGE")
    patches=edge.get("patches",[])
    if [x.get("path") for x in patches]!=[
        "bin/spotify-control.ps1","bin/spotify-control-agent.vbs"]:
        deny("REVIEW_RELEASE_PATCH_SET_CHANGED")
    chunks=[c for p in patches for c in p.get("chunks",[])]
    paths=[x.get("path") for x in chunks]
    changed=git("diff","--name-only",BASE,source_sha).splitlines()
    if (len(paths)!=EXPECTED_CHUNKS or len(set(paths))!=EXPECTED_CHUNKS or
        sorted(changed)!=sorted(paths) or
        any(not isinstance(p,str) or not p.startswith("packages/v0.6.30/")
            or p.endswith("/") or ".." in p for p in paths)):
        deny("REVIEW_SOURCE_COMMIT_EXACT_20_CHUNK_SCOPE_FAILED")
    for row in chunks:
        raw=object_at(source_sha,row["path"])
        if len(raw)!=row["size"] or sha(raw)!=row["sha256"]:
            deny("REVIEW_COMMITTED_CHUNK_BYTES_MISMATCH")
    print("REVIEW_REF_2_COMMITS_"+str(EXPECTED_CHUNKS)+"_CHUNKS_AND_MANIFEST=VERIFIED")

def main():
    if (os.getenv("GITHUB_ACTIONS")!="true" or
        os.getenv("RUNNER_ENVIRONMENT")!="github-hosted" or
        os.getenv("GITHUB_EVENT_NAME")!="push" or
        os.getenv("GITHUB_REF")!=CI_REF or
        os.getenv("GITHUB_REPOSITORY")!=REPO):
        deny("POST_WINDOWS_GITHUB_REVIEW_ONLY")
    if RECEIPT.is_symlink() or BUNDLE.is_symlink() or not RECEIPT.is_file() or not BUNDLE.is_file():
        deny("R34_ARTIFACT_REGULAR_FILES_REQUIRED")
    rec=metadata(RECEIPT.read_bytes())
    if (rec.get("schema")!="SPOTIFY_V0630_OFFLINE_PROMOTION_BUNDLE_HOLD_V1" or
        rec.get("status")!="REVIEW_CANDIDATE_ONLY_NOT_AUTHORIZED_NOT_PUBLISHED" or
        rec.get("base_public_main_commit")!=BASE or
        rec.get("bundle_name")!=BUNDLE.name or
        rec.get("source_package_chunks")!=EXPECTED_CHUNKS or
        rec.get("git_commits_to_fast_forward")!=2 or
        any(rec.get(k) is not False for k in (
          "github_ref_updated","release_published","owner_approval_granted",
          "operating_windows_modified","public_manifest_changed"))):
        deny("R34_REVIEW_RECEIPT_PROHIBITED_OR_INCOHERENT")
    bundle_bytes=BUNDLE.read_bytes()
    if (len(bundle_bytes)!=rec.get("bundle_size") or
        not 500<len(bundle_bytes)<1_000_000 or
        not HEX64.fullmatch(rec.get("bundle_sha256","")) or
        sha(bundle_bytes)!=rec["bundle_sha256"]):
        deny("R34_ORIGINAL_GIT_BUNDLE_SHA256_CHANGED")
    if (git("rev-parse","origin/main")!=BASE or
        git("rev-parse","HEAD")==BASE):
        deny("PUBLIC_MAIN_PROVENANCE_CHANGED")
    public=metadata(object_at(BASE,"manifest.json"))
    if public.get("latest_version")!="0.6.28":
        deny("CURRENT_PUBLIC_VERSION_NOT_BASELINE")
    source_sha=rec.get("source_payload_commit")
    manifest_sha=rec.get("manifest_candidate_commit")
    if not isinstance(source_sha,str) or not isinstance(manifest_sha,str):
        deny("RECEIPT_COMMIT_IDS_INVALID")
    # The local source commit is present only in the audited Git bundle,
    # which must have the exact expected Git ref as its sole listed head.
    heads=git("bundle","list-heads",str(BUNDLE)).splitlines()
    if heads!=[manifest_sha+" "+SOURCE_REF]:
        deny("REVIEW_BUNDLE_CONTAINS_UNKNOWN_REF")
    git("bundle","verify",str(BUNDLE))
    git("fetch","--no-tags","--no-write-fetch-head",str(BUNDLE),SOURCE_REF)
    expected_manifest=metadata(object_at(manifest_sha,"manifest.json"))
    if (sha(object_at(manifest_sha,"manifest.json"))!=rec.get("manifest_sha256") or
        expected_manifest.get("source_commit")!=source_sha or
        expected_manifest.get("payload_set_sha256")!=rec.get("payload_set_sha256")):
        deny("R34_MANIFEST_SHA_OR_CANDIDATE_CONTENT_DRIFT")
    inspect_commit(source_sha,manifest_sha,expected_manifest,public)

    # Do not push blindly over an existing owner review. If one already
    # exists, require its *content* to equal this build before returning.
    remote=git("ls-remote","--heads","origin",REVIEW_REF).splitlines()
    if len(remote)>1:
        deny("REVIEW_REF_NOT_UNIQUE")
    if remote:
        parts=remote[0].split()
        if len(parts)!=2 or parts[1]!=REVIEW_REF or not HEX40.fullmatch(parts[0]):
            deny("REVIEW_REF_UNRECOGNIZED")
        git("fetch","--no-tags","--no-write-fetch-head","origin",REVIEW_REF)
        prior_commit=parts[0]
        prior_source=git("rev-parse",prior_commit+"^")
        inspect_commit(prior_source,prior_commit,expected_manifest,public)
        print("REVIEW_REF=ALREADY_PRESERVED_SAME_CONTENT_NO_NEW_PUSH")
        print("REVIEW_REF_SHA="+prior_commit)
    else:
        # Single allowed write: one new, non-main review ref with no force.
        git("push","--porcelain","origin",manifest_sha+":"+REVIEW_REF)
        check=git("ls-remote","--heads","origin",REVIEW_REF).splitlines()
        if check!=[manifest_sha+"\t"+REVIEW_REF]:
            deny("REVIEW_REF_POST_PUSH_SHA_NOT_ATTESTED")
        print("REVIEW_REF=NEW_IMMUTABLE_HOLD_CANDIDATE_ONLY")
        print("REVIEW_REF_SHA="+manifest_sha)
    print("PRODUCTION_MAIN_WRITE=NO;RELEASE_CREATION=NO;USER_PC_WRITE=NO")
    print("R35_REVIEW_BRANCH_CONTENT_CUSTODY=PASS")

if __name__=="__main__":
    try:
        if sys.argv[1:]:
            deny("NO_UNCONTROLLED_ARGUMENTS_ALLOWED")
        main()
    except Exception as exc:
        reason=str(exc)
        if not re.fullmatch(r"[A-Z0-9_]{1,100}",reason):
            reason="UNVERIFIED_CUSTODY_ERROR"
        print("R35_REVIEW_BRANCH_CUSTODY=HOLD_"+reason)
        raise SystemExit(1)
