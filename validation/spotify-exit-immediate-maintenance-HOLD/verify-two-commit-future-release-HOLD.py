"""Non-publishing two-commit promotion proof for a future stable release.

The actual Bootstrap v1.0.6 reads immutable patches from
source_commit and a *later* manifest.json on main. This script recreates
that exact topology with real git commits entirely under GitHub Windows
RUNNER_TEMP. No network, git push, changes to main or operating files.

It is NOT an authorization to release a new stable version.
"""
from __future__ import annotations

import base64
import copy
import gzip
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
STAGED = ROOT / "validation/spotify-exit-immediate-maintenance-HOLD/out/release-staging"
SCRATCH = Path(os.environ["RUNNER_TEMP"]).resolve() / "spotify-future-two-commit-provenance"
PUBLIC = ROOT / "manifest.json"
REQUIRED = (
    "bin/spotify-control.ps1",
    "bin/spotify-control-agent.vbs",
)


def digest(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def git(*args: str, cwd: Path = SCRATCH) -> str:
    proc = subprocess.run(("git", *args), cwd=cwd, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, check=False)
    if proc.returncode:
        raise RuntimeError("GIT_STAGE_ACTION_FAILED_"+args[0].replace("-","_"))
    return proc.stdout.decode("ascii").strip()


def git_raw(sha: str, path: str) -> bytes:
    if not (len(sha)==40 and all(x in "0123456789abcdef" for x in sha)):
        raise RuntimeError("INVALID_SOURCE_COMMIT_ID")
    if path.startswith("/") or ".." in path or "\\" in path or ":" in path:
        raise RuntimeError("UNSAFE_SOURCE_RELATIVE_PATH")
    proc = subprocess.run(("git", "show", sha+":"+path), cwd=SCRATCH,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          check=False)
    if proc.returncode:
        raise RuntimeError("IMMUTABLE_COMMIT_SOURCE_CHUNK_MISSING")
    return proc.stdout


def attest(manifest: dict, source: str, committed_manifest: str|None=None) -> None:
    previous=json.loads(PUBLIC.read_text(encoding="utf-8-sig"))
    if previous["latest_version"]!="0.6.28" or len(previous["updates"])!=18:
        raise RuntimeError("PUBLIC_STABLE_HISTORY_UNEXPECTED")
    if (manifest["source_commit"]!=source or
        manifest["latest_version"]!="0.6.30" or
        manifest["channel"]!="stable" or
        manifest["bootstrap"]!=previous["bootstrap"] or
        manifest["updates"][:18]!=previous["updates"]):
        raise RuntimeError("STABLE_HISTORY_OR_IMMUTABLE_PIN_MISMATCH")
    if len(manifest["updates"]) != 19:
        raise RuntimeError("ONE_NEW_STABLE_EDGE_REQUIRED")
    edge=manifest["updates"][-1]
    if (edge["from_version"],edge["to_version"])!=("0.6.28","0.6.30"):
        raise RuntimeError("STABLE_FORWARD_EDGE_NOT_EXACT")
    if [p["path"] for p in edge["patches"]]!=list(REQUIRED):
        raise RuntimeError("FULL_FILE_PATCH_TARGET_SET_DRIFT")
    expected_latest = {
        item["path"]:item for item in manifest["latest_files"]
    }
    rows=sorted(
        "%s|%d|%s"%(r["path"],r["size"],r["sha256"])
        for r in manifest["latest_files"]
    )
    if digest(("\n".join(rows)+"\n").encode("ascii"))!=manifest["payload_set_sha256"]:
        raise RuntimeError("PAYLOAD_SET_DIGEST_MISMATCH")
    source_paths=[]
    for patch in edge["patches"]:
        if patch["encoding"]!="gzip-base64-full-file":
            raise RuntimeError("UNSUPPORTED_PUBLISHED_PATCH_KIND")
        if (patch["to_sha256"]!=expected_latest[patch["path"]]["sha256"] or
            patch["target_size"]!=expected_latest[patch["path"]]["size"] or
            not 1<=len(patch["chunks"])<=32):
            raise RuntimeError("PUBLISHED_PATCH_TARGET_MISMATCH")
        parts=[]
        for i,ch in enumerate(patch["chunks"]):
            path=ch["path"]
            if (not path.startswith("packages/v0.6.30/") or
                not path.endswith("/chunk-%03d.txt"%i)):
                raise RuntimeError("PUBLISHED_CHUNK_NOT_VERSION_BOUND")
            if path in source_paths:
                raise RuntimeError("DUPLICATE_SOURCE_CHUNK_PATH")
            source_paths.append(path)
            b=git_raw(source,path)
            if (len(b),digest(b))!=(ch["size"],ch["sha256"]):
                raise RuntimeError("IMMUTABLE_SOURCE_CHUNK_NOT_HASH_MATCHED")
            parts.append(b)
        encoded=b"".join(parts)
        compressed=base64.b64decode(encoded,validate=True)
        if (len(encoded),digest(encoded))!=(patch["encoded_size"],patch["encoded_sha256"]) or (
            len(compressed),digest(compressed))!=(patch["compressed_size"],patch["compressed_sha256"]):
            raise RuntimeError("IMMUTABLE_TRANSPORT_ENVELOPE_MISMATCH")
        full=gzip.decompress(compressed)
        if (len(full),digest(full))!=(patch["target_size"],patch["to_sha256"]):
            raise RuntimeError("IMMUTABLE_SOURCE_CONTENT_NOT_TARGET_MATCH")
        if full!=(STAGED/patch["path"]).read_bytes():
            raise RuntimeError("SOURCE_COMMIT_DIFFERS_FROM_PREVIOUSLY_TESTED_RELEASE")
    if len(source_paths)!=20:
        raise RuntimeError("IMMUTABLE_PAYLOAD_CHUNK_COUNT_MISMATCH")
    if committed_manifest:
        # The manifest commit must be a DISTINCT successor; otherwise Git
        # would be trying to include its own SHA in its own content.
        if committed_manifest==source:
            raise RuntimeError("MANIFEST_SELF_REFERENCE_FORBIDDEN")
        parent=git("rev-parse",committed_manifest+"^")
        if parent!=source:
            raise RuntimeError("MANIFEST_NOT_DIRECT_CHILD_OF_SOURCE_COMMIT")
        changed=git("diff","--name-only",source,committed_manifest).splitlines()
        if changed!=["manifest.json"]:
            raise RuntimeError("MANIFEST_COMMIT_CHANGED_PAYLOAD_OR_OTHER_FILES")
        if git_raw(committed_manifest,"manifest.json")!=(
            SCRATCH/"manifest.json").read_bytes():
            raise RuntimeError("IMMUTABLE_MANIFEST_BYTES_DIFF")
    print("IMMUTABLE_GIT_SOURCE_CHUNKS_20_AND_PAYLOAD_SET=PASS")


def run():
    if os.environ.get("GITHUB_ACTIONS")!="true" or os.environ.get("RUNNER_OS")!="Windows":
        raise RuntimeError("GITHUB_WINDOWS_HOSTED_ONLY")
    if SCRATCH.exists():
        raise RuntimeError("SCRATCH_GIT_REPOSITORY_ALREADY_EXISTS")
    before_public=PUBLIC.read_bytes()
    stage=json.loads((STAGED/"manifest-UNPUBLISHABLE.json").read_text(encoding="ascii"))
    if (stage["source_commit"]!="f"*40 or
        len(stage["updates"])!=19 or
        stage["updates"][-1]["to_version"]!="0.6.30"):
        raise RuntimeError("UNPUBLISHABLE_STAGE_INVALID")
    SCRATCH.mkdir(parents=True,mode=0o700)
    try:
        git("init","--initial-branch=main")
        git("config","user.name","SpotifyControl Synthetic Release Tester")
        git("config","user.email","synthetic-release@example.invalid")
        chunks=[ch["path"] for p in stage["updates"][-1]["patches"] for ch in p["chunks"]]
        if len(chunks)!=20 or len(chunks)!=len(set(chunks)):
            raise RuntimeError("STAGED_CHUNKS_NOT_20_UNIQUE")
        for rel in chunks:
            src=STAGED/rel
            target=SCRATCH/rel
            target.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(src,target)
        git("add","packages/v0.6.30")
        git("commit","-m","SCRATCH ONLY immutable candidate payload files")
        payload_commit=git("rev-parse","HEAD")
        # Every chunk MUST already exist in payload commit before creating
        # the manifest.  No staged working-tree rewrite can alter that SHA.
        for rel in chunks:
            if git_raw(payload_commit,rel)!=(STAGED/rel).read_bytes():
                raise RuntimeError("SOURCE_COMMIT_CHUNK_NOT_STAGE_IDENTICAL")
        new_manifest=copy.deepcopy(stage)
        new_manifest["source_commit"]=payload_commit
        published=SCRATCH/"manifest.json"
        published.write_text(json.dumps(new_manifest,indent=2,ensure_ascii=True)+"\n",
                             encoding="ascii",newline="\n")
        attest(new_manifest,payload_commit)
        git("add","manifest.json")
        git("commit","-m","SCRATCH ONLY latest stable manifest referencing immutable earlier payload")
        manifest_commit=git("rev-parse","HEAD")
        attest(new_manifest,payload_commit,manifest_commit)
        # Negative control: wrong sentinel never resolves a real Git blob.
        bad=copy.deepcopy(new_manifest)
        bad["source_commit"]="f"*40
        try:
            attest(bad,"f"*40)
        except RuntimeError as exc:
            if "IMMUTABLE_COMMIT_SOURCE_CHUNK_MISSING" not in str(exc):
                raise
        else:
            raise RuntimeError("SENTINEL_PSEUDO_COMMIT_WAS_ACCEPTED")
        if PUBLIC.read_bytes()!=before_public:
            raise RuntimeError("ACTUAL_PUBLISHED_MANIFEST_MUTATED")
        print("FUTURE_REAL_GIT_TWO_COMMIT_PUBLICATION_PROTOCOL=PASS")
        print("FUTURE_REAL_GIT_SOURCE_COMMIT_PRECEDES_MANIFEST=PASS")
        print("FUTURE_REAL_GIT_SENTINEL_REF_REJECTED=PASS")
        print("REAL_GITHUB_PUBLICATION=NO")
        print("OPERATING_WINDOWS_AND_MAIN_UNCHANGED=YES")
    finally:
        shutil.rmtree(SCRATCH,ignore_errors=True)


if __name__=="__main__":
    if len(sys.argv)!=1:
        raise SystemExit("No arguments accepted: this is synthetic-only.")
    run()
