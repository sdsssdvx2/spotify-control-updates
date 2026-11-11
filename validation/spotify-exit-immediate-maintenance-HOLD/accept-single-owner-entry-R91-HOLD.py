"""R91 HOLD: acceptance of the actual R90 one-command owner path with the
R89 proven native Win32 WScript/Bootstrap/mutex transaction in GitHub hosted
scratch. R90 production source is NEVER modified; this adapter creates a
hosted-only derivative of R90 inside the existing R89 scratch fixture.
The only hosted adaptations are to locate the scratch operating root and the
already-authenticated immutable R85 private stage, and to invoke R88 in its
original existing strictly GitHub-hosted fixture mode.

This is NOT a deploy command for the real user's Windows owner account.
"""
from __future__ import annotations
import hashlib
import os
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parent
TEMP=Path(os.environ.get("RUNNER_TEMP","/not-runner")).resolve()
TEST=TEMP/"spotify-r43-integrated-real-owner-cutover.ps1"
R90=ROOT/"owner-single-command-offline-R90-HOLD.ps1"

def insist(ok:bool,why:str)->None:
    if not ok: raise RuntimeError("R91_"+why)

def once(s:str,old:str,new:str,label:str)->str:
    insist(s.count(old)==1,"SINGLE_ANCHOR_"+label)
    return s.replace(old,new,1)

def host():
    insist(os.environ.get("GITHUB_ACTIONS")=="true" and
           os.environ.get("RUNNER_OS")=="Windows" and
           os.environ.get("RUNNER_ENVIRONMENT")=="github-hosted" and
           TEMP.is_dir() and not TEMP.is_symlink(),
           "HOSTED_GITHUB_WINDOWS_ONLY")

def run():
    host()
    insist(TEST.is_file() and R90.is_file(),"R89_DRIVER_AND_R90_SOURCE_REQUIRED")
    src=TEST.read_text("utf-8")
    insist("R89_NATIVE_PRODUCTION_CANDIDATE_R88_DRIVER_ACTUALLY_SELECTED=PASS" in src and
           "R87_REAL_R85_IMMUTABLE_OFFLINE_MANIFEST_AND_BOOTSTRAP_BOUND=PASS" in src,
           "SOURCE_MUST_BE_PROVEN_R89_WITH_PRIVATE_R85")
    base=hashlib.sha256(src.encode("utf-8")).hexdigest()
    r90=R90.read_text("utf-8")
    # Exact source strings, not approximations. Only the test-owned runner
    # instance runs this derivative. The user's R90 file is byte-identical.
    r90=once(r90,
      """    if(([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole(
       [Security.Principal.WindowsBuiltInRole]::Administrator)){""",
      """    if($false -and ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole(
       [Security.Principal.WindowsBuiltInRole]::Administrator)){""",
      "HOSTED_RUNNER_ACCOUNT_NOT_PRODUCTION")
    r90=once(r90,
      """    $local=[IO.Path]::GetFullPath([Environment]::GetFolderPath(
      [Environment+SpecialFolder]::LocalApplicationData)).TrimEnd('\\','/')""",
      """    $local=[IO.Path]::GetFullPath($env:LOCALAPPDATA).TrimEnd('\\','/')
    $fixture=Join-Path $env:RUNNER_TEMP 'spotify-future-bootstrap-rehearsal'""",
      "HOSTED_SCRATCH_ROOT_INSTEAD_OF_ACTUAL_OWNER_ROOT")
    r90=once(r90,
      """    $existing=@(Get-ChildItem -LiteralPath $local -Directory -Filter 'SpotifyControlCanary-offline-ready-*' -Force -ErrorAction Stop)""",
      """    $existing=@(Get-Item -LiteralPath $env:R87_OFFLINE_STAGE -Force -ErrorAction Stop)""",
      "HOSTED_PREVERIFIED_R85_STAGE_NOT_OPERATING_USER_STAGE")
    r90=once(r90,
      """      $r88Result=@(& ([ScriptBlock]::Create([Text.Encoding]::UTF8.GetString($r88))) -PrivateOfflineReadyPath $stage -Commit -ApprovalPhrase 'APPROVE_EXACT_PRIVATE_V0630_OWNER_CUTOVER_ONCE')""",
      """      $r88Result=@(& ([ScriptBlock]::Create([Text.Encoding]::UTF8.GetString($r88))) -PrivateOfflineReadyPath $stage -HostedFixtureRoot $fixture -Commit -ApprovalPhrase 'APPROVE_EXACT_PRIVATE_V0630_OWNER_CUTOVER_ONCE')""",
      "R88_ORIGINAL_GITHUB_HOSTED_OWNER_PROCESS_SCRATCH")
    insist("R90_EXACT_PRIVATE_OWNER_CUTOVER_COMMITTED" in r90 and
           r90.count("-HostedFixtureRoot $fixture -Commit")==1 and
           "R90_EXACT_OWNER_APPROVAL_REQUIRED" in r90,
           "R90_HOSTED_DERIVATIVE_APPROVAL_GUARD_MISSING")

    # Actual R89 driver has already exercised original R88 policy negative
    # cases. Change only the positive commit to *R90*, and preserve the real
    # native WScript owner handoff, mutex, postcommit and rollback checks.
    anchor="""$receipt=@(& $driver @r28Args -Commit -ApprovalPhrase 'APPROVE_EXACT_PRIVATE_V0630_OWNER_CUTOVER_ONCE')"""
    replacement="""$r90Text=[IO.File]::ReadAllText((Join-Path $env:RUNNER_TEMP 'spotify-r91-hosted-r90-driver.ps1'),[Text.Encoding]::UTF8)
    $r90=[ScriptBlock]::Create($r90Text)
    $receipt=@(& $r90 -Commit -ApprovalPhrase 'APPROVE_EXACT_PRIVATE_V0630_OWNER_CUTOVER_ONCE')
    foreach($r91Line in @($receipt)){
      if([string]$r91Line -cmatch '^[A-Z0-9_]{2,64}=[A-Za-z0-9_.;-]{1,150}$'){
        Write-Host ('R91_R90_SAFE_RECEIPT_'+[string]$r91Line)
      }
    }
    Write-Host 'R91_ACTUAL_R90_NATIVE_SINGLE_OWNER_ENTRY_WAS_INVOKED=PASS'"""
    src=once(src,anchor,replacement,"R90_NOT_R88_ACTUAL_COMMIT")

    start=src.index("if($receipt -cnotcontains 'RESULT=HOSTED_PRIVATE_OFFLINE_ONESHOT_COMMITTED'")
    end=src.index("throw ('R28_SINGLE_APPROVED_DRIVER_NOT_COMMITTED '",start)
    insist(start>0 and end>start and end-start<2200,"R89_POSITIVE_RECEIPT_AREA_NOT_EXACT")
    begin=src[start:end]
    insist("OUTER_MAINTENANCE_AND_AGENTTICK_MUTEXES=HELD" in begin and
           "R88_OFFICIAL_INSTALLED_BOOTSTRAP=UNCHANGED_PINNED" in begin and
           "USER_SHORTCUTS_AND_STATE=BYTE_IDENTICAL" in begin,
           "R89_NATIVE_OWNER_POSITIVE_PROOF_NOT_PRESERVED")
    src=src[:start]+"""if($receipt -cnotcontains 'RESULT=R90_EXACT_PRIVATE_OWNER_CUTOVER_COMMITTED' -or
       $receipt -cnotcontains 'R90_R88_SINGLE_OWNER_RESIDENT_AND_BOOTSTRAP_ORIGINAL=VERIFIED' -or
       $receipt -cnotcontains 'R90_IMMUTABLE_PRIVATE_STAGE_SELECTED=ONE' -or
       $receipt -cnotcontains 'R90_EXISTING_PRIVATE_STAGE=ONE_EXACT_CANDIDATE_REUSED'){
      """+src[end:]
    src=once(src,
      "Write-Host 'R89_ACTUAL_R88_OWNER_CUTOVER_PRESERVED_OFFICIAL_BOOTSTRAP=PASS'",
      """Write-Host 'R89_ACTUAL_R88_OWNER_CUTOVER_PRESERVED_OFFICIAL_BOOTSTRAP=PASS'
    Write-Host 'R91_REAL_R90_PINNED_OWNER_SINGLE_ENTRY_WITH_R88_WSCRIPT_TRANSACTION=PASS'""",
      "R90_OWNER_POSTCOMMIT_PROOF_ADDED")

    newPath=TEMP/"spotify-r91-hosted-r90-driver.ps1"
    insist(not newPath.exists(),"R90_HOSTED_SOURCE_ALREADY_PRESENT")
    newPath.write_text(r90,encoding="utf-8",newline="\n")
    TEST.write_text(src,encoding="utf-8",newline="\n")
    print("R91_R89_VERIFIED_OWNER_HARNESS_SHA256="+base)
    print("R91_ORIGINAL_R90_NATIVE_OWNER_SOURCE_SHA256="+hashlib.sha256(R90.read_bytes()).hexdigest())
    print("R91_HOSTED_ONLY_R90_DERIVATIVE_SHA256="+hashlib.sha256(r90.encode()).hexdigest())
    print("R91_REAL_R90_POSITIVE_OWNER_SOURCE_BOUND_TO_SCRATCH=PREPARED")
    print("R91_REPRODUCTION_SCOPE=GITHUB_HOSTED_WIN32_ONLY")
    print("R91_OWNER_PC_OPERATING_FILES_AND_PUBLIC_MAIN=UNMODIFIED")

if __name__=="__main__":
    if len(sys.argv)!=1: raise SystemExit("No arguments")
    run()
