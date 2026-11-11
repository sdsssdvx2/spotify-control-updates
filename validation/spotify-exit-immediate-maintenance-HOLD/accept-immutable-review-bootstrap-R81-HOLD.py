"""R81 HOLD: exact immutable GitHub review -> pinned original v1.0.6
Bootstrap source, hosted loopback-only transaction. Never an owner installer.

Prior R42/R70 hosted Bootstrap demonstrations used correctly pinned synthetic
unpublished stage with fake 'f'*40 source. R81 uses the ACTUAL 21 review
chunks, pinned immutable real Git SHA and manifest verified by the EXISTING
R29 verifier before putting any bytes in an isolated Windows fixture.

Allowed: GITHUB_ACTIONS=true RUNNER_OS=Windows, github-hosted runner only.
No publishing, no network calls at all by production/user Spotify.
"""
from __future__ import annotations
import hashlib, importlib.util, json, os, subprocess, sys
from pathlib import Path

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
TMP=Path(os.environ.get("RUNNER_TEMP", "/nonexistent")).resolve()
STAGE=TMP/"spotify-r81-immutable-github-review-stage"
REHEARSAL=HERE/"rehearse-localhost-bootstrap-future.py"
R80=HERE/"verify-prepublication-owner-first-R80-HOLD.py"
EXPECTED_MANIFEST_SHA="71395858fcce58500bb42070bf4b248e2ab14613e148e7d74e616c252d6c3332"
EXPECTED_MAIN="b2b2fbf1afb60b58d501312160f7e2437c2452e90cb61ca8c2be0d877f92232d"
EXPECTED_AGENT="e56609ed8927512595f55c01ea50dbb9c8c59e4a2c86dcb3d16195a565c604d5"
EXPECTED_ADDON="5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285"

def sha(data:bytes):return hashlib.sha256(data).hexdigest()
def exact_write(p:Path,b:bytes):
    path=p.absolute()
    if not path.is_relative_to(STAGE) or path.is_symlink():
        raise RuntimeError("R81_STAGED_FILE_PATH_NOT_ISOLATED")
    path.parent.mkdir(parents=True,exist_ok=True)
    with path.open("xb") as f:
        f.write(b); f.flush(); os.fsync(f.fileno())
def load(path:Path,name:str):
    spec=importlib.util.spec_from_file_location(name,path)
    if not spec or not spec.loader:raise RuntimeError("R81_PINNED_MODULE_MISSING_"+name)
    mod=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod
def only_host():
    if (os.environ.get("GITHUB_ACTIONS")!="true" or
        os.environ.get("RUNNER_OS")!="Windows" or
        os.environ.get("RUNNER_ENVIRONMENT")!="github-hosted" or
        not str(TMP).lower().endswith(("temp","_temp","\\_temp"))):
        raise RuntimeError("R81_HOSTED_WINDOWS_GUARD")
def stage():
    only_host()
    if STAGE.exists():raise RuntimeError("R81_STAGE_PREEXISTED")
    mod=load(R80,"r81_exact_remote_r80")
    verifier=mod.load_verifier()
    raw=verifier.download(verifier.RAW+mod.REVIEW_COMMIT+"/manifest.json",200000)
    doc,patches=mod.preflight(raw,verifier)
    if sha(raw)!=EXPECTED_MANIFEST_SHA:
        raise RuntimeError("R81_SOURCE_REVIEW_MANIFEST_SHA_INVALID")
    base_raw=verifier.download(verifier.RAW+verifier.BASE_MAIN_COMMIT+"/manifest.json",200000)
    base=verifier.parse_manifest(base_raw,"BASE")
    if (base.get("latest_version")!=verifier.BASE_LATEST or
        doc["updates"][:-1]!=base["updates"] or
        doc["bootstrap"]!=base["bootstrap"]):
        raise RuntimeError("R81_STABLE_BASELINE_DIFFERENT")
    verifier.validate_latest(base,verifier.ORIGINAL)
    originals={p:verifier.ORIGINAL[p][1] for p in
               ("bin/spotify-control.ps1","bin/spotify-control-agent.vbs")}
    count,decoded=verifier.attest_downloaded(
        doc,verifier.FUTURE,originals,"0.6.30",patches,mod.IMMUTABLE_SOURCE_COMMIT)
    if count!=21 or {p:sha(b) for p,b in decoded.items()}!={
        "bin/spotify-control.ps1":EXPECTED_MAIN,
        "bin/spotify-control-agent.vbs":EXPECTED_AGENT}:
        raise RuntimeError("R81_REAL_REMOTE_SOURCE_OUTPUTS_MISMATCH")
    # All bytes were already independently fetched and checked by the frozen
    # R29 verifier; now get exact corresponding local Git objects, bound by
    # the same manifest SHA/size (never accept local source without remote
    # admission).
    for patch in patches:
        for ch in patch["chunks"]:
            rel=ch["path"]
            if (not rel.startswith("packages/v0.6.30/") or
                ".." in rel or "\\" in rel or ":" in rel):
                raise RuntimeError("R81_UNSAFE_CHUNK_PATH")
            get=subprocess.run(["git","show",mod.IMMUTABLE_SOURCE_COMMIT+":"+rel],
                               cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,
                               timeout=20,check=True)
            data=get.stdout
            if (len(data),sha(data))!=(ch["size"],ch["sha256"]):
                raise RuntimeError("R81_LOCAL_GIT_OBJECT_NOT_MATCHING_VERIFIED_REMOTE")
            exact_write(STAGE/rel,data)
    original_addon=(ROOT/"validation/v0.6.28/out/bin/addon-manager.ps1").read_bytes()
    if sha(original_addon)!=EXPECTED_ADDON:
        raise RuntimeError("R81_ORIGINAL_ADDON_R17_NOT_EXACT")
    exact_write(STAGE/"bin/spotify-control.ps1",decoded["bin/spotify-control.ps1"])
    exact_write(STAGE/"bin/spotify-control-agent.vbs",decoded["bin/spotify-control-agent.vbs"])
    exact_write(STAGE/"bin/addon-manager.ps1",original_addon)
    exact_write(STAGE/"manifest-UNPUBLISHABLE.json",raw)
    receipt={
        "status":"STAGED_HOLD_NOT_PUBLISHABLE",
        "publishable":False,
        "source_commit":mod.IMMUTABLE_SOURCE_COMMIT,
        "manifest_sha256":sha(raw),
        "payload_sha256":doc["payload_set_sha256"],
        "source_kind":"EXACT_REMOTE_HELD_REVIEW_NOT_OFFICIAL_STABLE",
    }
    exact_write(STAGE/"stage-receipt.json",
        json.dumps(receipt,sort_keys=True,separators=(",",":")).encode("ascii"))
    print("R81_REMOTE_REVIEW_MANIFEST_GIT_BLOB_AND_SHA=PASS")
    print("R81_REAL_REVIEW_GIT_CHUNKS_21_OVER_REMOTE_AND_LOCAL=PASS")
    print("R81_MAIN_AND_VBS_SHA_AND_ADDON_R17=PASS")
    print("R81_STAGE=ISOLATED_HOSTED_SCRATCH_ONLY_NOT_INSTALLER")
def mirror():
    only_host()
    if not STAGE.is_dir():raise RuntimeError("R81_REVIEW_STAGE_MISSING")
    mod80=load(R80,"r81_exact_r80_mirror")
    frozen=(STAGE/"manifest-UNPUBLISHABLE.json").read_bytes()
    if (sha(frozen)!=EXPECTED_MANIFEST_SHA or
        mod80.gitblob(frozen)!=mod80.REVIEW_MANIFEST_GIT_BLOB):
        raise RuntimeError("R81_REVIEW_MANIFEST_STAGING_CHANGED")
    # Reuse original hosted Bootstrap mirror. Exact ONLY stage locator and
    # immutable real source commit change; all original transaction logic
    # and only the two Bootstrap URL literals are reused from R42.
    mod=load(REHEARSAL,"r81_original_r42_mirror")
    mod.STAGED=STAGE
    mod.COMMIT=mod80.IMMUTABLE_SOURCE_COMMIT
    mod.prepare()
    if not (mod.REHEARSAL/"rehearsal-report.json").is_file():
        raise RuntimeError("R81_BOOTSTRAP_MIRROR_NO_RECEIPT")
    receipt=json.loads((mod.REHEARSAL/"rehearsal-report.json").read_text("ascii"))
    if (receipt["fake_unpublished_source_commit"]!=mod.COMMIT or
        receipt["future_main_sha256"]!=EXPECTED_MAIN or
        receipt["future_agent_sha256"]!=EXPECTED_AGENT or
        receipt["staged_manifest_sha256"]!=EXPECTED_MANIFEST_SHA):
        raise RuntimeError("R81_BOOTSTRAP_MIRROR_NOT_EXACT_REVIEW")
    print("R81_VERIFIED_REVIEW_TO_ORIGINAL_BOOTSTRAP_HOSTED_MIRROR=PASS")
    print("R81_BOOTSTRAP_DERIVATIVE=ONLY_TWO_NETWORK_LOCATORS_CHANGED")
    print("R81_OWNER_PC_BOOTSTRAP_UNCHANGED=YES")
if __name__=="__main__":
    if sys.argv[1:]==["stage"]:stage()
    elif sys.argv[1:]==["mirror"]:mirror()
    else:raise SystemExit("Only stage or mirror; hosted Windows runner only")
