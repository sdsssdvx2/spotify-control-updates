"""R82 HOLD — combine previously accepted R70 real native R28 owner process
cutover / true Bootstrap / rollback / tamper detection with the *actual*
prepublication R81 immutable GitHub review (21 verified chunks).

Hosted scratch ONLY. This adapter derives an in-memory/test-only R28 source
that accepts the genuine review commit instead of R28's old test-only f*40;
no installed official R28/R27/Bootstrap or existing release source modified.
This is NOT an owner-PC prepublication installer.
"""
from __future__ import annotations

import hashlib
import os
from pathlib import Path
import subprocess
import sys

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
T=Path(os.environ.get("RUNNER_TEMP","/not-runner")).resolve()
POWER=T/"spotify-r43-integrated-real-owner-cutover.ps1"
PREP=T/"spotify-r43-integrated-prepare.py"
STAGE=T/"spotify-r81-immutable-github-review-stage"
R81=HERE/"accept-immutable-review-bootstrap-R81-HOLD.py"
REAL_COMMIT="27c3bbd2935c8568ee6d260085d8008aec5e173a"
MANIFEST_SHA="71395858fcce58500bb42070bf4b248e2ab14613e148e7d74e616c252d6c3332"
MAIN_SHA="b2b2fbf1afb60b58d501312160f7e2437c2452e90cb61ca8c2be0d877f92232d"
VBS_SHA="e56609ed8927512595f55c01ea50dbb9c8c59e4a2c86dcb3d16195a565c604d5"
BOOT_SHA="d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6"

def once(s:str,old:str,new:str,code:str)->str:
    if s.count(old)!=1:raise RuntimeError("R82_SOURCE_ANCHOR_"+code)
    return s.replace(old,new,1)

def host():
    if (os.environ.get("GITHUB_ACTIONS")!="true" or
        os.environ.get("RUNNER_OS")!="Windows" or
        os.environ.get("RUNNER_ENVIRONMENT")!="github-hosted" or
        not T.is_dir() or T.is_symlink()):
        raise RuntimeError("R82_HOSTED_WINDOWS_SCRATCH_ONLY")

def run():
    host()
    if not (POWER.is_file() and PREP.is_file() and STAGE.is_dir()):
        raise RuntimeError("R82_R70_AND_R81_SCRATCH_NOT_REBUILT")
    report=(STAGE/"stage-receipt.json").read_text("ascii")
    if MANIFEST_SHA not in report or REAL_COMMIT not in report or BOOT_SHA not in (
        HERE/"rehearse-localhost-bootstrap-future.py").read_text("utf-8"):
        raise RuntimeError("R82_REVIEW_SOURCE_OR_BOOTSTRAP_PIN_NOT_MATCHED")
    source=POWER.read_text("utf-8")
    baseline_hash=hashlib.sha256(source.encode("utf-8")).hexdigest()
    # The native R43 script still consumes the pinned R28 owner-lock, WScript
    # and official Bootstrap code. Only the HOSTED proof source commit and
    # fixture binding differ from the fake future-payload rehearsal.
    old_stage="'validation/spotify-exit-immediate-maintenance-HOLD/out/release-staging-boot-wmi-R70/stage-receipt.json'"
    new_stage="(Join-Path $env:RUNNER_TEMP 'spotify-r81-immutable-github-review-stage/stage-receipt.json')"
    source=once(source,old_stage,new_stage,"R81_NATIVE_STAGE_RECEIPT")
    source=once(source,"source_commit=('f'*40)",
                "source_commit='"+REAL_COMMIT+"'","GENUINE_SOURCE_COMMIT")
    source=once(source,"chunk_count=20","chunk_count=21","GENUINE_21_CHUNKS")
    source=once(source,"status='HOSTED_SYNTHETIC_SOURCE_ONLY_NOT_PUBLIC_VERIFIED'",
                "status='HOSTED_GENUINE_IMMUTABLE_REVIEW_NOT_PUBLIC_VERIFIED'",
                "FACT_STATUS_NOT_SYNTHETIC")
    # R28 old hosted mode accepts a fake source commit for synthetic release
    # only. The *original pinned* R28 bytes remain untouched on disk, but the
    # hosted native PowerShell fixture can invoke a DRY RUN derived driver
    # accepting the R81 actual authenticated immutable commit.
    src_line="$driver=[ScriptBlock]::Create([Text.Encoding]::ASCII.GetString($r28Bytes))"
    amended=r"""$r28Text=[Text.Encoding]::ASCII.GetString($r28Bytes)
  $expectedAnchor='$expectedSource=(''f''*40)'
  $reviewSourceAnchor='$expectedSource=''27c3bbd2935c8568ee6d260085d8008aec5e173a'''
  $factsAnchor="'HOSTED_SYNTHETIC_SOURCE_ONLY_NOT_PUBLIC_VERIFIED'"
  $factsReplacement="'HOSTED_GENUINE_IMMUTABLE_REVIEW_NOT_PUBLIC_VERIFIED'"
  if(([regex]::Matches($r28Text,[regex]::Escape($expectedAnchor))).Count -ne 1 -or
     ([regex]::Matches($r28Text,[regex]::Escape($factsAnchor))).Count -ne 1){
    throw 'R82_R28_HOSTED_ACCEPTANCE_LITERAL_PROVENANCE_CHANGED'
  }
  $r28Text=$r28Text.Replace($expectedAnchor,$reviewSourceAnchor)
  $r28Text=$r28Text.Replace($factsAnchor,$factsReplacement)
  $driver=[ScriptBlock]::Create($r28Text)"""
    source=once(source,src_line,amended,"HOSTED_DRIVER_REAL_REVIEW_SOURCE_ONLY")
    old_chunk="'loopback-source/sdsssdvx2/spotify-control-updates/'+('f'*40)"
    new_chunk="'loopback-source/sdsssdvx2/spotify-control-updates/"+REAL_COMMIT+"'"
    source=once(source,old_chunk,new_chunk,"CHUNK_TAMPER_ACTUAL_COMMIT_PATH")
    expected="R43_ACTUAL_R28_OWNER_CUTOVER_CONSUMES_INTEGRATED_PAYLOAD_SHA_PASS"
    source=once(source,expected,
        "R82_EXACT_REAL_REVIEW_SHA_INTEGRATED_OWNER_CUTOVER=PASS",
        "EXACT_REVIEW_PAYLOAD_ASSERTION")
    more="    if([string]$expect.future_main_sha256 -cne '"+MAIN_SHA+"' -or"
    if more not in source or VBS_SHA not in source or "R28_FINAL_NEW_AGENT_NOT_SINGLE" not in source:
        raise RuntimeError("R82_R70_FROZEN_REAL_OWNER_LIFECYCLE_NOT_PRESENT")
    # Preserve every prior lock/retry/rollback/shortcut check in the entire
    # R43 script. Only replace the single hosted preparer reference.
    prep=PREP.read_text("utf-8")
    if prep.count("module.prepare()")!=1:
        raise RuntimeError("R82_ORIGINAL_R43_PREPARE_UNRECOGNIZED")
    new_prep="""from importlib import util
from pathlib import Path
root=Path.cwd()
p=root/"validation/spotify-exit-immediate-maintenance-HOLD/accept-immutable-review-bootstrap-R81-HOLD.py"
spec=util.spec_from_file_location("r82_review_real_21_chunks",p)
if spec is None or spec.loader is None:
    raise RuntimeError("R82_PINNED_REVIEW_MIRROR_NOT_AVAILABLE")
module=util.module_from_spec(spec)
spec.loader.exec_module(module)
module.mirror()
"""
    # Only scratch test-owned files can be replaced, never the repo source
    # or the actual owner local application.
    POWER.write_text(source,encoding="utf-8",newline="\n")
    PREP.write_text(new_prep,encoding="utf-8",newline="\n")
    print("R82_ORIGINAL_PINNED_R70_SCRIPT_SHA256="+baseline_hash)
    print("R82_GENERATED_REAL_REVIEW_TEST_SHA256="+hashlib.sha256(source.encode()).hexdigest())
    print("R82_TEST_R28_REAL_SOURCE_COMMIT="+REAL_COMMIT)
    print("R82_GENUINE_21_REMOTE_CHUNKS_TO_OWNER_WSCRIPT_MUTEX_AND_ROLLBACK=PREPARED")
    print("R82_HOSTED_TEST_ONLY_AND_PRODUCT_SOURCE_UNCHANGED=YES")

if __name__=="__main__":
    if sys.argv[1:]:raise SystemExit("No args")
    run()
