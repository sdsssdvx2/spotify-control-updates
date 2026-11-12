"""R97: Actual second WScript process test after exact R90/R94 native Win32
candidate update and R96 hosted-only COM startup shortcut creation.
This observes whether a second logon-style invocation exits itself or stays
alive. It does not claim Windows reboot or logon. Its own second process is
always terminated after identity checks; the original resident survives.
"""
from __future__ import annotations
import hashlib
import os
from pathlib import Path
import sys
TEMP=Path(os.environ.get("RUNNER_TEMP","/not-runner")).resolve()
TEST=TEMP/"spotify-r43-integrated-real-owner-cutover.ps1"

def check(ok: bool, label: str):
    if not ok: raise RuntimeError("R97_"+label)

def run():
    check(os.environ.get("GITHUB_ACTIONS")=="true" and
          os.environ.get("RUNNER_OS")=="Windows" and
          os.environ.get("RUNNER_ENVIRONMENT")=="github-hosted" and
          TEMP.is_dir() and not TEMP.is_symlink(), "HOSTED_ONLY")
    check(TEST.is_file(), "R96_NATIVE_OWNER_TEST_REQUIRED")
    s=TEST.read_text(encoding="utf-8")
    old="    $receiptBytes=(Get-FileHash -LiteralPath $receiptFile -Algorithm SHA256).Hash"
    check(s.count(old)==1 and
          "R94_FRESH_AGENT_NEW_WMI_START_SUBSCRIPTION=PASS" in s and
          "R96_EXPLICIT_OWNER_LOGON_LINK_REGISTERED" in s and
          "R93FreshSnapshot 'ROLLBACK'" in s,"EXACT_R96_WIN32_OWNER_INTEGRATION_REQUIRED")
    script=r"""    # R97: deliberately simulate an extra OS-style WScript launch while
    # R94's genuinely owned first process is still running. The second
    # process is restricted to this disposable hosted fixture.
    $r97Probe=$null
    $r97Result='UNVERIFIED'
    $r97OriginalPid=[int]$newResident.Id
    $newResident.Refresh()
    if($newResident.HasExited){throw 'R97_ORIGINAL_RESIDENT_UNEXPECTEDLY_EXITED'}
    try{
      $r97Probe=Start-Process -FilePath $wscript -WorkingDirectory $app -ArgumentList ('//B //NoLogo "'+$agent+'"') -PassThru -ErrorAction Stop
      if($r97Probe.Id -eq $r97OriginalPid){throw 'R97_SECOND_PROCESS_SAME_PID'}
      Start-Sleep -Seconds 3
      $r97Probe.Refresh()
      $newResident.Refresh()
      if($newResident.HasExited){throw 'R97_SECOND_LAUNCH_KILLED_EXISTING_RESIDENT'}
      if($r97Probe.HasExited){
        $r97Result='SECOND_EXITED_SELF'
      }else{
        $v=Get-CimInstance Win32_Process -Filter ("ProcessId="+[int]$r97Probe.Id) -ErrorAction Stop
        $own=Invoke-CimMethod -InputObject $v -MethodName GetOwnerSid -ErrorAction Stop
        if($null -eq $v -or
           -not [string]::Equals([string]$v.ExecutablePath,$wscript,[StringComparison]::OrdinalIgnoreCase) -or
           -not ([string]$v.CommandLine).Contains($agent) -or
           [int]$own.ReturnValue -ne 0 -or
           [string]$own.Sid -cne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value){
          throw 'R97_SECOND_PROCESS_OWNER_BINARY_AND_SCRIPT_NOT_EXACT'
        }
        $both=@(Get-CimInstance Win32_Process -Filter "Name='wscript.exe'" -ErrorAction Stop |
          Where-Object {([string]$_.CommandLine).Contains($agent)})
        if($both.Count -ne 2 -or
           -not ($both.ProcessId -contains [uint32]$r97OriginalPid) -or
           -not ($both.ProcessId -contains [uint32]$r97Probe.Id)){
          throw 'R97_OWNED_SCRIPT_TWO_PROCESS_WITNESS_NOT_CONSISTENT'
        }
        $r97Result='SECOND_STAYS_RUNNING_TWO_RESIDENTS'
      }
      Write-Host ('R97_ACTUAL_SECOND_WSCRIPT_LOGON_STYLE_RESULT='+$r97Result)
    }finally{
      if($null -ne $r97Probe){
        try{
          $r97Probe.Refresh()
          if(-not $r97Probe.HasExited){
            # Only the process handle opened in this hosted test can be ended.
            Stop-Process -Id $r97Probe.Id -Force -ErrorAction Stop
          }
          [void]$r97Probe.WaitForExit(5000)
        }catch{throw 'R97_ONLY_SECOND_HOSTED_PROCESS_CLEANUP_FAILED'}
      }
    }
    $newResident.Refresh()
    if($newResident.HasExited){throw 'R97_ORIGINAL_RESIDENT_NOT_PRESERVED'}
    $afterCount=@(Get-CimInstance Win32_Process -Filter "Name='wscript.exe'" -ErrorAction Stop |
      Where-Object {([string]$_.CommandLine).Contains($agent)})
    if($afterCount.Count -ne 1 -or [int]$afterCount[0].ProcessId -ne $r97OriginalPid){
      throw 'R97_RESTORED_SINGLE_ORIGINAL_RESIDENT_NOT_PROVEN'
    }
    Write-Host 'R97_HOSTED_SECOND_WSCRIPT_REMOVED_ORIGINAL_SINGLE_RESIDENT_PRESERVED=PASS'
"""
    s=s.replace(old,script+old,1)
    check(s.count("R97_ACTUAL_SECOND_WSCRIPT_LOGON_STYLE_RESULT=")==1 and
          s.count(old)==1 and s.count("R96_REAL_WIN32_USER_LOGON_LNK_ATOMIC_CREATE_AND_EXACT_REVOKE=PASS")==1,
          "INSERTION_CORRUPT")
    sha=hashlib.sha256(TEST.read_bytes()).hexdigest()
    TEST.write_text(s,encoding="utf-8",newline="\n")
    print("R97_R96_NATIVE_PARENT_SHA256="+sha)
    print("R97_DUPLICATE_WSCRIPT_TEST=GITHUB_HOSTED_UNMODIFIED_CANDIDATE")
    print("R97_REAL_LOGON_AND_USER_PC=NOT_TOUCHED")
if __name__=="__main__":
    if sys.argv[1:]:raise SystemExit("No arguments")
    run()
