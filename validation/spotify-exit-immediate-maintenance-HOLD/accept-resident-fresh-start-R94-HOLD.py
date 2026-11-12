"""R94 HOLD: one genuine native Win32 fresh WScript startup AFTER the exact
R90->R88 owner candidate commit, BEFORE the existing explicit rollback.

Reuses the proven R93 independent PowerShell process snapshots and the
original R92/R89 WScript owner test. The only live processes touched belong
to the GitHub-hosted disposable test fixture and are identity-checked before
termination. This is a process-level relaunch, NOT a physical Windows reboot,
Task Scheduler proof, or an actual user PC logon.
"""
from __future__ import annotations
import hashlib
import os
from pathlib import Path
import sys

TEMP=Path(os.environ.get("RUNNER_TEMP","/not-runner")).resolve()
TEST=TEMP/"spotify-r43-integrated-real-owner-cutover.ps1"

def ensure(ok:bool,why:str)->None:
    if not ok:raise RuntimeError("R94_"+why)

def once(s:str,old:str,new:str,label:str)->str:
    ensure(s.count(old)==1,"TEST_DRIVER_ANCHOR_"+label)
    return s.replace(old,new,1)

def run()->None:
    ensure(os.environ.get("GITHUB_ACTIONS")=="true" and
           os.environ.get("RUNNER_OS")=="Windows" and
           os.environ.get("RUNNER_ENVIRONMENT")=="github-hosted" and
           TEMP.is_dir() and not TEMP.is_symlink(),
           "GITHUB_HOSTED_WINDOWS_ONLY")
    ensure(TEST.is_file(),"R93_NATIVE_TEST_PREVIOUSLY_STAGED_REQUIRED")
    s=TEST.read_text("utf-8")
    ensure("R93_FRESH_POWERSHELL_CANDIDATE_SOURCE_SNAPSHOT=PASS" not in s or
           "R93FreshSnapshot 'CANDIDATE'" in s,"R93_FRESH_STATUS_DRIVER_INVALID")
    ensure("R93FreshSnapshot 'CANDIDATE'" in s and
           "R93FreshSnapshot 'ROLLBACK'" in s and
           "R93FreshSnapshot 'MIXED'" in s and
           "R92_REAL_R86_R84_R85_FIRST_STAGE_TO_R90_R88_OWNER_WSCRIPT_COMMIT=PASS" in s,
           "R93_NATIVE_WIN32_BASELINE_NOT_INTACT")
    marker="Write-Host 'R28_SUCCESSFUL_UPDATE_NO_SECOND_ATTEMPT_AND_RESIDENT_PRESERVED_PASS'"
    update=r"""Write-Host 'R28_SUCCESSFUL_UPDATE_NO_SECOND_ATTEMPT_AND_RESIDENT_PRESERVED_PASS'
    # Independent native process restart in a disposable Win32 hosted owner
    # fixture, after the REAL R90->R88 commit and single-resident assertion.
    $beforeMainHash=(Get-FileHash -LiteralPath $main -Algorithm SHA256).Hash.ToLowerInvariant()
    $beforeAgentHash=(Get-FileHash -LiteralPath $agent -Algorithm SHA256).Hash.ToLowerInvariant()
    $beforeInstalledBoot=(Get-FileHash -LiteralPath (Join-Path $app 'bootstrap/spotify-control-self-updater.ps1') -Algorithm SHA256).Hash.ToLowerInvariant()
    $beforeTxn=(Get-FileHash -LiteralPath (Join-Path $app 'self-update-last-transaction.json') -Algorithm SHA256).Hash
    if($beforeMainHash -cne 'b2b2fbf1afb60b58d501312160f7e2437c2452e90cb61ca8c2be0d877f92232d' -or
       $beforeAgentHash -cne 'e56609ed8927512595f55c01ea50dbb9c8c59e4a2c86dcb3d16195a565c604d5' -or
       $beforeInstalledBoot -cne 'd9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6'){
      throw 'R94_CANDIDATE_OWNER_BINARY_PINS_NOT_READY_FOR_RESTART'
    }
    $newResident.Refresh()
    if($newResident.HasExited){throw 'R94_EXACT_COMMITTED_OWNER_RESIDENT_ALREADY_STOPPED'}
    $beforeProcess=Get-CimInstance Win32_Process -Filter ("ProcessId="+[int]$newResident.Id) -ErrorAction Stop
    if($null -eq $beforeProcess -or
       -not [string]::Equals([string]$beforeProcess.ExecutablePath,$wscript,[StringComparison]::OrdinalIgnoreCase) -or
       -not ([string]$beforeProcess.CommandLine).Contains($agent)){
      throw 'R94_ORIGINAL_COMMITTED_RESIDENT_IDENTITY_NOT_PROVEN'
    }
    $ownerBefore=Invoke-CimMethod -InputObject $beforeProcess -MethodName GetOwnerSid -ErrorAction Stop
    if([int]$ownerBefore.ReturnValue -ne 0 -or
       [string]$ownerBefore.Sid -cne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value){
      throw 'R94_ORIGINAL_RESIDENT_OWNER_SID_NOT_EXACT'
    }
    $priorPid=[int]$newResident.Id
    $priorCreation=[datetime]$beforeProcess.CreationDate
    # Only the test-owned process returned by the original R28 fixture
    # is stopped, and only after exact binary/script/SID/PID checks.
    Stop-Process -Id $priorPid -Force -ErrorAction Stop
    if(-not $newResident.WaitForExit(5000)){throw 'R94_OWNED_RESIDENT_DID_NOT_EXIT'}
    if($priorCreation -eq [datetime]::MinValue){throw 'R94_OLD_PROCESS_CREATION_UNKNOWN'}
    if(@(Get-CimInstance Win32_Process -Filter ("ProcessId="+$priorPid) -ErrorAction Stop).Count -ne 0){
      throw 'R94_OLD_PROCESS_STILL_LIVE_AFTER_EXACT_TERMINATION'
    }
    # Simulate OS logon launch using the same fixed VBS path and neutral
    # working directory. This is NOT a Windows restart or startup registry
    # admission test; the launcher is explicitly controlled by the fixture.
    $newResident=Start-Process -FilePath $wscript -WorkingDirectory $app -ArgumentList ('//B //NoLogo "'+$agent+'"') -PassThru
    Start-Sleep -Seconds 3
    $newResident.Refresh()
    if($newResident.HasExited){throw 'R94_FRESH_WSCRIPT_STARTUP_EXITED'}
    $fresh=Get-CimInstance Win32_Process -Filter ("ProcessId="+[int]$newResident.Id) -ErrorAction Stop
    if($null -eq $fresh -or
       -not [string]::Equals([string]$fresh.ExecutablePath,$wscript,[StringComparison]::OrdinalIgnoreCase) -or
       -not ([string]$fresh.CommandLine).Contains($agent) -or
       [int]$fresh.ProcessId -eq $priorPid){
      throw 'R94_LOGON_STYLE_FRESH_WSCRIPT_IDENTITY_UNVERIFIED'
    }
    $ownerAfter=Invoke-CimMethod -InputObject $fresh -MethodName GetOwnerSid -ErrorAction Stop
    if([int]$ownerAfter.ReturnValue -ne 0 -or
       [string]$ownerAfter.Sid -cne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value){
      throw 'R94_FRESH_WSCRIPT_OWNER_SID_UNVERIFIED'
    }
    $matches=@(Get-CimInstance Win32_Process -Filter "Name='wscript.exe'" -ErrorAction Stop |
      Where-Object {([string]$_.CommandLine).Contains($agent)})
    if($matches.Count -ne 1 -or [int]$matches[0].ProcessId -ne [int]$newResident.Id){
      throw 'R94_FRESH_WSCRIPT_NOT_SINGLE_EXACT_SCRIPT'
    }
    foreach($check in @(
        @{path=$main;sha=$beforeMainHash},
        @{path=$agent;sha=$beforeAgentHash},
        @{path=(Join-Path $app 'bootstrap/spotify-control-self-updater.ps1');sha=$beforeInstalledBoot},
        @{path=(Join-Path $app 'self-update-last-transaction.json');sha=$beforeTxn.ToLowerInvariant()})){
      if((Get-FileHash -LiteralPath $check.path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $check.sha){
        throw 'R94_LOGON_STYLE_RESTART_CHANGED_PINNED_OWNER_BYTES'
      }
    }
    R93FreshSnapshot 'CANDIDATE' 'CANDIDATE' 'CANDIDATE' 'CANDIDATE'
    Write-Host 'R94_LOGON_STYLE_FRESH_WSCRIPT_ONE_OWNER_RESIDENT_AND_DATA_PRESERVED=PASS'
    Write-Host 'R94_REAL_WINDOWS_REBOOT=NO_PROCESS_RESTART_ONLY'"""
    s=once(s,marker,update,"RESTART_EXACT_AFTER_SINGLE_COMMITTED_RESIDENT")
    ensure(s.count("Write-Host 'R94_LOGON_STYLE_FRESH_WSCRIPT_ONE_OWNER_RESIDENT_AND_DATA_PRESERVED=PASS'")==1 and
           "R93FreshSnapshot 'ROLLBACK'" in s and
           "FUTURE_OFFICIAL_BOOTSTRAP_CORRUPT_CHUNK_REJECTED_ORIGINAL_AND_OWNER_DATA_UNCHANGED_PASS" in s,
           "UNINTENDED_NATIVE_ROLLBACK_CHANGE")
    TEST.write_text(s,encoding="utf-8",newline="\n")
    print("R94_FROZEN_R93_TEST_PARENT_SHA256="+hashlib.sha256(TEST.read_bytes()).hexdigest())
    print("R94_EXACT_COMMITTED_VBS_PROCESS_FRESH_OS_LAUNCH=PREPARED")
    print("R94_USER_WINDOWS_AND_PUBLIC_MAIN=UNMODIFIED")
    print("R94_PHYSICAL_REBOOT_AND_REAL_LOGON=NOT_TESTED")

if __name__=="__main__":
    if sys.argv[1:]:raise SystemExit("No arguments")
    run()
