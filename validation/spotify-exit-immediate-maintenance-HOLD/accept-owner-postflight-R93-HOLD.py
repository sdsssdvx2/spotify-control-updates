"""R93 HOLD: run the unchanged R90 -Status in fresh native PowerShell
processes against exact pinned, independent Windows owner scratch *before*
the real R92 update, after real R90->R88 commit, after official rollback,
and after a temporary synthetic mixed-version interruption. Every mutation
of the mixed test is confined to RUNNER_TEMP and restored in finally.
Never pass a hosted override to an actual owner's installer.
"""
from __future__ import annotations
import hashlib
import os
from pathlib import Path
import sys

DIR=Path(__file__).resolve().parent
TEMP=Path(os.environ.get("RUNNER_TEMP","/not-runner")).resolve()
DRIVER=TEMP/"spotify-r43-integrated-real-owner-cutover.ps1"
STATUS=DIR/"owner-single-command-offline-R90-HOLD.ps1"

def insist(ok,why):
    if not ok:raise RuntimeError("R93_"+why)

def once(s,a,b,tag):
    insist(s.count(a)==1,"UNIQUE_NATIVE_TEST_INSERT_"+tag)
    return s.replace(a,b,1)

def main():
    insist(os.environ.get("GITHUB_ACTIONS")=="true" and
           os.environ.get("RUNNER_OS")=="Windows" and
           os.environ.get("RUNNER_ENVIRONMENT")=="github-hosted" and
           TEMP.is_dir() and not TEMP.is_symlink(),
           "ISOLATED_GITHUB_WINDOWS_ONLY")
    insist(DRIVER.is_file() and STATUS.is_file(),"GENERATED_R92_NATIVE_DRIVER_REQUIRED")
    d=DRIVER.read_text("utf-8")
    orig=hashlib.sha256(d.encode()).hexdigest()
    insist("R92_REAL_R86_R84_R85_FIRST_STAGE_TO_R90_R88_OWNER_WSCRIPT_COMMIT=PASS" in d and
           "R91_ACTUAL_R90_NATIVE_SINGLE_OWNER_ENTRY_WAS_INVOKED=PASS" in d and
           "FUTURE_OFFICIAL_BOOTSTRAP_CORRUPT_CHUNK_REJECTED_ORIGINAL_AND_OWNER_DATA_UNCHANGED_PASS" in d,
           "SOURCE_IS_NOT_FINAL_R92_NATIVE_WIN32_OWNER_TEST")
    helper=r"""function R93FreshSnapshot([string]$label,[string]$mainState,[string]$agentState,[string]$expectedClass){
      if($label -cnotmatch '^(BASELINE|CANDIDATE|ROLLBACK|MIXED)$'){throw 'R93_LABEL_NOT_PINNED'}
      $statusFile=(Resolve-Path 'validation/spotify-exit-immediate-maintenance-HOLD/owner-single-command-offline-R90-HOLD.ps1').Path
      $rows=@(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $statusFile -Status -HostedReadOnlyRoot $app 2>&1)
      $rc=$LASTEXITCODE
      if($rc -ne 0 -or
         $rows -cnotcontains 'RESULT=R93_READONLY_POSTFLIGHT_COLLECTED' -or
         $rows -cnotcontains 'R93_OBSERVATION_SCOPE=HOSTED_SCRATCH_ONLY' -or
         $rows -cnotcontains 'R93_NETWORK=NO;FILE_WRITE=NO;PROCESS_CHANGE=NO;RETRY=NO' -or
         $rows -cnotcontains ('R93_MAIN_HASH_CLASS='+$mainState) -or
         $rows -cnotcontains ('R93_AGENT_HASH_CLASS='+$agentState) -or
         $rows -cnotcontains 'R93_ADDON_HASH_CLASS=BASELINE' -or
         $rows -cnotcontains 'R93_OFFICIAL_BOOTSTRAP_HASH_CLASS=BASELINE' -or
         $rows -cnotcontains 'R93_AGENT_IN_MEMORY_VERSION=NOT_PROVEN'){
        $safe=@($rows|Where-Object {([string]$_) -match '^R93_[A-Z0-9_]{2,40}=[A-Z0-9_;-]{1,110}$'})
        throw ('R93_FRESH_STATUS_SOURCE_OR_FILE_PINS_UNCERTAIN_'+$label+'_'+($safe -join ';'))
      }
      if($expectedClass -ceq 'CANDIDATE'){
        if($rows -cnotcontains 'R93_TRANSACTION=COMMITTED_REPORTED_ONLY' -or
           $rows -cnotcontains 'R93_CLASSIFICATION=CANDIDATE_FILES_COMMITTED_RESIDENT_CODE_UNATTESTED' -and
           $rows -cnotcontains 'R93_CLASSIFICATION=HOLD_CANDIDATE_FILES_JOURNAL_OR_RESIDENT_UNVERIFIED'){
          throw 'R93_CANDIDATE_TRANSACTION_OR_RESIDENT_STATUS_NOT_RECOGNIZED'
        }
      }elseif($rows -cnotcontains ('R93_CLASSIFICATION='+$expectedClass)){
        throw ('R93_EXPECTED_CLASSIFICATION_NOT_FOUND_'+$label)
      }
      Write-Host ('R93_FRESH_POWERSHELL_'+$label+'_SOURCE_SNAPSHOT=PASS')
    }"""
    # No program-file changes before the real commit, only status lookups.
    commit="$receipt=@(& $r90 -Commit -ApprovalPhrase 'APPROVE_EXACT_PRIVATE_V0630_OWNER_CUTOVER_ONCE')"
    d=once(d,commit,
      helper+"\n    R93FreshSnapshot 'BASELINE' 'BASELINE' 'BASELINE' 'BASELINE_FILES_EXACT_RESIDENT_UNATTESTED'\n    "+commit,
      "PRECOMMIT_EXACT_BASELINE_AND_DEFINE_HELPER")
    marker="Write-Host 'R92_REAL_R86_R84_R85_FIRST_STAGE_TO_R90_R88_OWNER_WSCRIPT_COMMIT=PASS'"
    d=once(d,marker,
      marker+"\n    R93FreshSnapshot 'CANDIDATE' 'CANDIDATE' 'CANDIDATE' 'CANDIDATE'",
      "AFTER_REAL_OWNER_R90_COMMIT")
    rolled="Write-Host 'FUTURE_OFFICIAL_BOOTSTRAP_LOCALHOST_EXACT_ROLLBACK_AND_USER_DATA_PRESERVATION_PASS'"
    d=once(d,rolled,
      rolled+"\n    R93FreshSnapshot 'ROLLBACK' 'BASELINE' 'BASELINE' 'BASELINE_FILES_EXACT_RESIDENT_UNATTESTED'",
      "AFTER_BOOTSTRAP_ROLLBACK_FRESH_PROCESS")
    corrupt="Write-Host 'FUTURE_OFFICIAL_BOOTSTRAP_CORRUPT_CHUNK_REJECTED_ORIGINAL_AND_OWNER_DATA_UNCHANGED_PASS'"
    interruption=r"""$mixedReceipt=Get-Content -LiteralPath (Join-Path $env:R87_OFFLINE_STAGE 'offline-receipt.json') -Raw | ConvertFrom-Json
    $r84Source=Join-Path (Join-Path (Split-Path $env:R87_OFFLINE_STAGE -Parent) ([string]$mixedReceipt.source_stage_id)) 'spotify-control-agent.vbs'
    if((Get-FileHash -LiteralPath $r84Source -Algorithm SHA256).Hash.ToLowerInvariant() -cne
       'e56609ed8927512595f55c01ea50dbb9c8c59e4a2c86dcb3d16195a565c604d5'){
      throw 'R93_MIXED_TEST_CANDIDATE_AGENT_SOURCE_NOT_PINNED'
    }
    $agentTarget=Join-Path $app 'bin/spotify-control-agent.vbs'
    $beforeBytes=[IO.File]::ReadAllBytes($agentTarget)
    if((Get-FileHash -LiteralPath $agentTarget -Algorithm SHA256).Hash.ToLowerInvariant() -cne
      '2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278'){
      throw 'R93_MIXED_TEST_ROLLED_BACK_AGENT_NOT_BASELINE'
    }
    try{
      # This simulated interruption mutates ONLY the disposable hosted
      # scratch VBS after all real Bootstrap/WScript owner tests completed.
      [IO.File]::WriteAllBytes($agentTarget,[IO.File]::ReadAllBytes($r84Source))
      R93FreshSnapshot 'MIXED' 'BASELINE' 'CANDIDATE' 'HOLD_MIXED_VERSIONS_NO_RETRY'
    }finally{
      [IO.File]::WriteAllBytes($agentTarget,$beforeBytes)
    }
    if((Get-FileHash -LiteralPath $agentTarget -Algorithm SHA256).Hash.ToLowerInvariant() -cne
      '2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278'){
      throw 'R93_MIXED_TEST_SCRATCH_NOT_RESTORED'
    }
    Write-Host 'R93_MIXED_SCRATCH_INTERRUPTION_REJECTED_AND_CLEANED=PASS'"""
    d=once(d,corrupt,corrupt+"\n    "+interruption,"HOSTED_MIXED_VERSION_INTRUSION_AND_FINALLY_RESTORE")
    DRIVER.write_text(d,encoding="utf-8",newline="\n")
    print("R93_PINNED_ORIGINAL_NATIVE_R92_DRIVER_SHA256="+orig)
    print("R93_READONLY_OBSERVER_SOURCE_SHA256="+hashlib.sha256(STATUS.read_bytes()).hexdigest())
    print("R93_STANDALONE_FRESH_POWERSHELL_BASELINE_NEW_ROLLBACK_MIXED=PREPARED")
    print("R93_GITHUB_HOSTED_ONLY_OWNER_PC_AND_PUBLIC_MAIN=UNCHANGED")

if __name__=="__main__":
    if len(sys.argv)!=1:raise SystemExit("No args")
    main()
