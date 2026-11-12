"""R99 hosted native Windows: owner R90/R94/R98 candidate -> immutable
R98 guard registration with exact COM .lnk -> shell-run while the resident
already exists -> no second WScript -> owner-only receipt-bound revoke.
All link/guard/receipt files exist only in RUNNER_TEMP; no actual user
Startup/registry/scheduled task is changed; no real Windows logon claimed.
"""
from __future__ import annotations
import hashlib
import os
from pathlib import Path
import sys
TEMP=Path(os.environ.get("RUNNER_TEMP","/not-runner")).resolve()
DRIVER=TEMP/"spotify-r43-integrated-real-owner-cutover.ps1"

def require(x,why):
    if not x:raise RuntimeError("R99_"+why)

def main():
    require(os.environ.get("GITHUB_ACTIONS")=="true" and
            os.environ.get("RUNNER_OS")=="Windows" and
            os.environ.get("RUNNER_ENVIRONMENT")=="github-hosted" and
            TEMP.is_dir() and not TEMP.is_symlink(),
            "HOSTED_WINDOWS_ONLY")
    require(DRIVER.is_file(),"R98_NATIVE_DRIVER_REQUIRED")
    s=DRIVER.read_text("utf-8")
    mark="    Write-Host 'R98_NATIVE_FRESH_WMI_SUBSCRIPTION_AND_REPEATED_GUARD_SKIP=PASS'"
    require(s.count(mark)==1 and "R98_NATIVE_WSCRIPT_ABSENT_OWNER_STARTED_SINGLE_FRESH=PASS" in s and
            "R93FreshSnapshot 'ROLLBACK'" in s and
            "R94_FRESH_AGENT_NEW_WMI_START_SUBSCRIPTION=PASS" in s,
            "REAL_R98_WSCRIPT_MUST_HAVE_PASSED")
    inject=r"""    Write-Host 'R98_NATIVE_FRESH_WMI_SUBSCRIPTION_AND_REPEATED_GUARD_SKIP=PASS'
    & {
    $r99Source=(Resolve-Path 'validation/spotify-exit-immediate-maintenance-HOLD/owner-approved-guarded-logon-R99-HOLD.ps1').Path
    $ownerStartup=Join-Path (Split-Path $app -Parent) 'R99UserStartup'
    $commonStartup=Join-Path (Split-Path $app -Parent) 'R99CommonStartup'
    foreach($d in @($ownerStartup,$commonStartup)){
      if(Test-Path -LiteralPath $d){throw 'R99_TEST_STARTUP_DIRECTORY_PREEXISTS'}
      [void][IO.Directory]::CreateDirectory($d)
    }
    $ownerLink=Join-Path $ownerStartup 'Spotify Control Resident (R99 Guarded).lnk'
    $ownerGuard=Join-Path $app 'owner-guard-r99.ps1'
    $ownerReceipt=Join-Path $app 'startup-owner-r99.json'
    $mainFingerprint=(Get-FileHash -LiteralPath $main -Algorithm SHA256).Hash
    $agentFingerprint=(Get-FileHash -LiteralPath $agent -Algorithm SHA256).Hash
    $journal=Join-Path $app 'self-update-last-transaction.json'
    $journalFingerprint=(Get-FileHash -LiteralPath $journal -Algorithm SHA256).Hash
    function R99Once([string[]]$parms){
      $rows=@(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $r99Source -HostedFixtureRoot $app @parms 2>&1)
      if($LASTEXITCODE -ne 0){throw 'R99_EXACT_NATIVE_OWNER_RUN_EXIT_NONZERO'}
      foreach($line in @($rows)){
        $s=[string]$line
        if($s -cmatch '^R99_[A-Z0-9_]{2,50}=[A-Z0-9_;-]{1,150}$'){
          Write-Host ('R99_SAFE_HOSTED_RECEIPT_'+$s)
        }
      }
      return $rows
    }
    $plan=R99Once @()
    if($plan -cnotcontains 'RESULT=R99_READONLY_OWNER_LOGON_PLAN' -or
       $plan -cnotcontains 'R99_PLAN=READY_FOR_EXACT_OWNER_APPROVAL_NOT_EXECUTION_PROOF'){
      throw 'R99_BEFORE_FIRST_REGISTRATION_NOT_READONLY_READY'
    }
    $denied=R99Once @('-Commit')
    if($denied -cnotcontains 'HOLD_REASON=R99_CREATE_EXPLICIT_APPROVAL_REQUIRED' -or
       $denied -cnotcontains 'RESULT=R99_HOLD_NO_RETRY'){
      throw 'R99_MISSING_OWNER_APPROVAL_NOT_REJECTED'
    }
    $created=R99Once @('-Commit','-ApprovalPhrase','APPROVE_EXACT_ONE_OWNER_LOGON_SHORTCUT_ONCE')
    if($created -cnotcontains 'RESULT=R99_EXPLICIT_OWNER_LOGON_LINK_REGISTERED' -or
       $created -cnotcontains 'R99_COMMIT_RESULT=ONE_GUARDED_USER_STARTUP_LINK_CREATED_NOT_LAUNCHED' -or
       -not(Test-Path -LiteralPath $ownerLink -PathType Leaf) -or
       -not(Test-Path -LiteralPath $ownerGuard -PathType Leaf) -or
       -not(Test-Path -LiteralPath $ownerReceipt -PathType Leaf)){
      throw ('R99_VERIFIED_SOURCE_GUARDED_STARTUP_CREATION_FAILED '+(@($created|Where-Object{$_ -match '^(HOLD_REASON|R99_)='}) -join ';'))
    }
    $guardBytes=(Get-FileHash -LiteralPath $ownerGuard -Algorithm SHA256).Hash
    $receiptBytes=(Get-FileHash -LiteralPath $ownerReceipt -Algorithm SHA256).Hash
    $linkBytes=(Get-FileHash -LiteralPath $ownerLink -Algorithm SHA256).Hash
    $record=Get-Content -LiteralPath $ownerReceipt -Raw | ConvertFrom-Json
    if([string]$record.guard_sha256 -cne $guardBytes.ToLowerInvariant()){
      throw 'R99_RECEIPT_NOT_BOUND_TO_GUARD_SOURCE_HASH'
    }
    # The existing R90 single-command status must recognize an owned R99
    # guarded link instead of incorrectly reporting no auto-start route.
    $r90Status='validation/spotify-exit-immediate-maintenance-HOLD/owner-single-command-offline-R90-HOLD.ps1'
    $r100=@(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $r90Status -Status -HostedReadOnlyRoot $app 2>&1)
    if($LASTEXITCODE -ne 0 -or
       $r100 -cnotcontains 'RESULT=R93_READONLY_POSTFLIGHT_COLLECTED' -or
       $r100 -cnotcontains 'R100_R99_GUARDED_LOGON=ONE_OWNED_GUARDED_REGISTERED_NOT_LOGON_PROOF' -or
       $r100 -cnotcontains 'R100_LOGON_ASSESSMENT=HOSTED_GUARDED_COM_VERIFIED_REAL_LOGON_NOT_TESTED'){
      throw ('R100_EXACT_R99_GUARDED_OWNER_STATUS_NOT_RECOGNIZED '+(@($r100|Where-Object{$_ -match '^R100_'}) -join ';'))
    }
    Write-Host 'R100_SINGLE_COMMAND_OWNER_R99_GUARDED_STARTUP_READONLY_RECOGNITION=PASS'
    $noSecond=R99Once @()
    if($noSecond -cnotcontains 'R99_PLAN=OWNED_GUARDED_LOGON_LINK_PRESENT_EXECUTION_UNVERIFIED'){
      throw 'R99_OWNER_REGISTRATION_PLAN_AFTER_COMMIT_MISMATCH'
    }
    $duplicate=R99Once @('-Commit','-ApprovalPhrase','APPROVE_EXACT_ONE_OWNER_LOGON_SHORTCUT_ONCE')
    if($duplicate -cnotcontains 'HOLD_REASON=R99_NEVER_OVERWRITE_EXISTING_LINK_OR_RECEIPT' -or
       (Get-FileHash -LiteralPath $ownerLink -Algorithm SHA256).Hash -cne $linkBytes -or
       (Get-FileHash -LiteralPath $ownerGuard -Algorithm SHA256).Hash -cne $guardBytes){
      throw 'R99_REPEATED_OWNER_APPROVAL_DID_NOT_PRESERVE_ORIGINAL'
    }
    $linkCOM=(New-Object -ComObject WScript.Shell).CreateShortcut($ownerLink)
    $exe=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if(-not [string]::Equals([string]$linkCOM.TargetPath,$exe,[StringComparison]::OrdinalIgnoreCase) -or
       -not([string]$linkCOM.Arguments).Contains($ownerGuard) -or
       -not([string]$linkCOM.Arguments).Contains('-HostedFixtureRoot')){
      throw 'R99_REAL_WIN32_COM_LINK_GUARD_TARGET_NOT_EXACT'
    }
    $newResident.Refresh()
    if($newResident.HasExited){throw 'R99_EXISTING_R98_RESIDENT_NOT_RUNNING'}
    $residentPID=[int]$newResident.Id
    # Launch the actual installed COM .lnk using native Windows Shell. The
    # resident is already running, so the guarded link MUST skip a duplicate.
    [void](Start-Process -FilePath $ownerLink -ErrorAction Stop)
    Start-Sleep -Seconds 4
    $active=@(Get-CimInstance Win32_Process -Filter "Name='wscript.exe'" -ErrorAction Stop |
      Where-Object {([string]$_.CommandLine).Contains($agent)})
    if($active.Count -ne 1 -or [int]$active[0].ProcessId -ne $residentPID){
      throw 'R99_REAL_COM_STARTUP_LINK_CREATED_SECOND_WSCRIPT'
    }
    $removed=R99Once @('-Remove','-ApprovalPhrase','APPROVE_REMOVE_ONLY_R99_OWNED_LOGON_SHORTCUT_ONCE')
    if($removed -cnotcontains 'RESULT=R99_EXPLICIT_OWNED_LOGON_LINK_REVOKED' -or
       (Test-Path -LiteralPath $ownerLink) -or
       (Test-Path -LiteralPath $ownerGuard) -or
       (Test-Path -LiteralPath $ownerReceipt)){
      throw ('R99_EXACT_GUARD_LINK_RECEIPT_REVOKE_INCOMPLETE '+(@($removed|Where-Object {$_ -match '^(HOLD_REASON|R99_)='}) -join ';'))
    }
    $r100Gone=@(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $r90Status -Status -HostedReadOnlyRoot $app 2>&1)
    if($LASTEXITCODE -ne 0 -or
       $r100Gone -cnotcontains 'R100_R99_GUARDED_LOGON=NONE' -or
       $r100Gone -cnotcontains 'R100_LOGON_ASSESSMENT=NO_GUARDED_R99_REGISTRATION'){
      throw 'R100_OWNER_GUARDED_REGISTRATION_NOT_REMOVED_IN_STATUS'
    }
    Write-Host 'R100_SINGLE_COMMAND_OWNER_GUARDED_LINK_REVOKE_REFLECTED=PASS'
    foreach($item in @(@{path=$main;sha=$mainFingerprint},
        @{path=$agent;sha=$agentFingerprint},
        @{path=$journal;sha=$journalFingerprint})){
      if((Get-FileHash -LiteralPath $item.path -Algorithm SHA256).Hash -cne $item.sha){
        throw 'R99_UNRELATED_OWNER_DATA_OR_RELEASE_CHANGED'
      }
    }
    foreach($folder in @($ownerStartup,$commonStartup)){
      if(@(Get-ChildItem -LiteralPath $folder -Force -ErrorAction Stop).Count -ne 0){
        throw 'R99_STARTUP_FIXTURE_NOT_EMPTY_AFTER_REMOVE'
      }
      [IO.Directory]::Delete($folder)
    }
    Write-Host 'R99_EXACT_WIN32_COM_GUARDED_LOGON_LINK_NO_DUPLICATE=PASS'
    Write-Host 'R99_IMMUTABLE_R98_GUARD_OWNER_RECEIPT_AND_REVOKE=PASS'
    Write-Host 'R99_NO_USER_DATA_OR_RELEASE_MUTATION_AFTER_FULL_CYCLE=PASS'
    Write-Host 'R99_REAL_REBOOT_AND_USER_STARTUP_CHANGES=NO'
    } # no owner variable leakage into R90/Bootstrap rollback
    $global:LASTEXITCODE=0
"""
    s=s.replace(mark,inject,1)
    require(s.count("R99_EXACT_WIN32_COM_GUARDED_LOGON_LINK_NO_DUPLICATE=PASS")==1,
            "R99_NATIVE_INJECTION_CORRUPT")
    before=hashlib.sha256(DRIVER.read_bytes()).hexdigest()
    DRIVER.write_text(s,encoding="utf-8",newline="\n")
    print("R99_GROUNDED_REAL_R98_NATIVE_DRIVER_SHA256="+before)
    print("R99_HOSTED_GUARDED_STARTUP_COM_AND_OWNER_REVOKE=PREPARED")
    print("R99_PUBLIC_MAIN_AND_ACTUAL_USER_WINDOWS=UNMODIFIED")
if __name__=="__main__":
    if sys.argv[1:]:raise SystemExit("No args")
    main()
