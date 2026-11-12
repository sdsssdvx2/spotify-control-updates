"""R98 HOLD: real native Windows guarded owner startup after R90/R94/R96/R97
scratch. Observe that R98 refuses a second WScript; after exact stop of
the owned process it starts precisely one new v0.6.30 resident, WMI
resubscribes, and original transaction/rollback remains unchanged.
"""
from __future__ import annotations
import hashlib
import os
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parent
TEMP=Path(os.environ.get("RUNNER_TEMP","/not-runner")).resolve()
DRIVER=TEMP/"spotify-r43-integrated-real-owner-cutover.ps1"
GUARD=ROOT/"owner-single-resident-logon-guard-R98-HOLD.ps1"

def require(ok:bool,why:str):
    if not ok:raise RuntimeError("R98_NATIVE_"+why)

def main():
    require(os.environ.get("GITHUB_ACTIONS")=="true" and
            os.environ.get("RUNNER_OS")=="Windows" and
            os.environ.get("RUNNER_ENVIRONMENT")=="github-hosted" and
            TEMP.is_dir() and not TEMP.is_symlink(),"HOSTED_WINDOWS_ONLY")
    require(DRIVER.is_file() and GUARD.is_file(),"R97_DRIVER_AND_R98_GUARD")
    s=DRIVER.read_text("utf-8")
    mark="    Write-Host 'R97_HOSTED_SECOND_WSCRIPT_REMOVED_ORIGINAL_SINGLE_RESIDENT_PRESERVED=PASS'"
    require(s.count(mark)==1 and
            "R94_FRESH_AGENT_NEW_WMI_START_SUBSCRIPTION=PASS" in s and
            "R97_ACTUAL_SECOND_WSCRIPT_LOGON_STYLE_RESULT=" in s and
            "R93FreshSnapshot 'ROLLBACK'" in s,
            "ACTUAL_R97_OWNER_WSCRIPT_PROOF_MISSING")
    addition=r"""    Write-Host 'R97_HOSTED_SECOND_WSCRIPT_REMOVED_ORIGINAL_SINGLE_RESIDENT_PRESERVED=PASS'
    # R98 only tests test-owned ephemeral Win32 process instances.
    $guardSource=(Resolve-Path 'validation/spotify-exit-immediate-maintenance-HOLD/owner-single-resident-logon-guard-R98-HOLD.ps1').Path
    function R98Once(){
      $rows=@(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $guardSource -HostedFixtureRoot $app 2>&1)
      if($LASTEXITCODE -ne 0){throw 'R98_NATIVE_GUARD_PROCESS_EXIT_NONZERO'}
      return $rows
    }
    $log=Join-Path $app 'logs/resident-agent-host.log'
    $logBefore=if(Test-Path -LiteralPath $log){
      @(Get-Content -LiteralPath $log -ErrorAction Stop).Count
    }else{0}
    $originalPID=[int]$newResident.Id
    $before=R98Once
    if($before -cnotcontains 'RESULT=R98_ALREADY_RUNNING_NO_SECOND_PROCESS' -or
       $before -cnotcontains 'R98_BEFORE=ONE_EXACT_OWNER_PRESENT'){
      throw 'R98_GUARD_DID_NOT_SKIP_LIVE_ORIGINAL_OWNER_RESIDENT'
    }
    $newResident.Refresh()
    if($newResident.HasExited){throw 'R98_GUARD_SKIP_TERMINATED_ORIGINAL_RESIDENT'}
    $count=@(Get-CimInstance Win32_Process -Filter "Name='wscript.exe'" -ErrorAction Stop |
      Where-Object {([string]$_.CommandLine).Contains($agent)})
    if($count.Count -ne 1 -or [int]$count[0].ProcessId -ne $originalPID){
      throw 'R98_GUARD_SKIP_DID_NOT_PRESERVE_ONE_OWNER_PROCESS'
    }
    # Simulate shutdown of the exact test-owned resident, not a user OS
    # process, then require the guard to start a new resident exactly once.
    $former=Get-CimInstance Win32_Process -Filter ("ProcessId="+$originalPID) -ErrorAction Stop
    $formerOwner=Invoke-CimMethod -InputObject $former -MethodName GetOwnerSid -ErrorAction Stop
    if([string]$formerOwner.Sid -cne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -or
       [int]$formerOwner.ReturnValue -ne 0 -or
       -not [string]::Equals([string]$former.ExecutablePath,$wscript,[StringComparison]::OrdinalIgnoreCase) -or
       -not([string]$former.CommandLine).Contains($agent)){
      throw 'R98_GUARD_RESTART_OLD_RESIDENT_OWNER_NOT_ATTESTED'
    }
    Stop-Process -Id $originalPID -Force -ErrorAction Stop
    if(-not $newResident.WaitForExit(5000)){throw 'R98_OLD_FIXTURE_RESIDENT_NOT_DRAINED'}
    $start=R98Once
    if($start -cnotcontains 'RESULT=R98_ONE_EXACT_OWNER_RESIDENT_STARTED' -or
       $start -cnotcontains 'R98_BEFORE=NONE'){
      throw ('R98_GUARD_FAILED_TO_START_ONE_AFTER_ABSENCE_'+(@($start|Where-Object {$_ -match '^(HOLD_REASON|R98_BEFORE)='}) -join ';'))
    }
    $newCim=@(Get-CimInstance Win32_Process -Filter "Name='wscript.exe'" -ErrorAction Stop |
      Where-Object {([string]$_.CommandLine).Contains($agent)})
    if($newCim.Count -ne 1 -or [int]$newCim[0].ProcessId -eq $originalPID){
      throw 'R98_GUARD_NEW_PROCESS_OWNER_SCRIPT_COUNT_NOT_ONE'
    }
    $newOwner=Invoke-CimMethod -InputObject $newCim[0] -MethodName GetOwnerSid -ErrorAction Stop
    if([int]$newOwner.ReturnValue -ne 0 -or
       [string]$newOwner.Sid -cne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value){
      throw 'R98_FRESH_GUARD_RESIDENT_SID_NOT_EXACT'
    }
    $newResident=Get-Process -Id ([int]$newCim[0].ProcessId) -ErrorAction Stop
    Set-Variable -Name newResident -Scope 1 -Value $newResident
    $freshWmi=$false
    for($i=0;$i -lt 40;$i++){
      if(Test-Path -LiteralPath $log -PathType Leaf){
        $logs=@(Get-Content -LiteralPath $log -ErrorAction SilentlyContinue)
        if($logs.Count -gt $logBefore -and
           @($logs | Select-Object -Skip $logBefore | Where-Object {
             $_ -like '*WMI START EVENT subscribed*' -or
             $_ -like '*WMI START EVENT resubscribed*'
           }).Count -gt 0){
          $freshWmi=$true;break
        }
      }
      $newResident.Refresh()
      if($newResident.HasExited){throw 'R98_GUARD_FRESH_WSCRIPT_EXITED_EARLY'}
      Start-Sleep -Milliseconds 250
    }
    if(-not $freshWmi){throw 'R98_GUARD_FRESH_WMI_SUBSCRIPTION_NOT_ATTESTED'}
    $repeated=R98Once
    if($repeated -cnotcontains 'RESULT=R98_ALREADY_RUNNING_NO_SECOND_PROCESS'){
      throw 'R98_SECOND_GUARDED_CALL_DID_NOT_SKIP_FRESH_RESIDENT'
    }
    $oneMore=@(Get-CimInstance Win32_Process -Filter "Name='wscript.exe'" -ErrorAction Stop |
      Where-Object {([string]$_.CommandLine).Contains($agent)})
    if($oneMore.Count -ne 1 -or [int]$oneMore[0].ProcessId -ne [int]$newResident.Id){
      throw 'R98_SECOND_GUARD_CALL_CREATED_DUPLICATE'
    }
    Write-Host 'R98_NATIVE_WSCRIPT_EXISTING_OWNER_SKIPPED_DUPLICATE=PASS'
    Write-Host 'R98_NATIVE_WSCRIPT_ABSENT_OWNER_STARTED_SINGLE_FRESH=PASS'
    Write-Host 'R98_NATIVE_FRESH_WMI_SUBSCRIPTION_AND_REPEATED_GUARD_SKIP=PASS'
    R93FreshSnapshot 'CANDIDATE' 'CANDIDATE' 'CANDIDATE' 'CANDIDATE'
"""
    s=s.replace(mark,addition,1)
    require(s.count("R98_NATIVE_WSCRIPT_EXISTING_OWNER_SKIPPED_DUPLICATE=PASS")==1,
            "INJECTION_INCOMPLETE")
    prior=hashlib.sha256(DRIVER.read_bytes()).hexdigest()
    DRIVER.write_text(s,encoding="utf-8",newline="\n")
    print("R98_PRIOR_R97_WIN32_FIXTURE_SHA256="+prior)
    print("R98_GUARDED_OWNER_SKIPS_DUPLICATE_AND_STARTS_ABSENT=PREPARED")
    print("R98_REAL_WINDOWS_LOGON_AND_USER_STARTUP_REGISTRATION=NOT_TESTED")

if __name__=="__main__":
    if sys.argv[1:]:raise SystemExit("No arguments")
    main()
