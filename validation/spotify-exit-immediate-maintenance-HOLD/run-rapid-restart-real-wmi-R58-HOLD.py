"""R58 genuine Windows WScript/WMI two Spotify.exe close cycles <60s.
Reuses exact original successful R44 synthetic fake process and benign
PowerShell stub, the only changed input is SHA-pinned R58 WMI VBS.

No production/real installed Spotify, network or personal files.
"""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
R44=HERE/"accept-real-vbs-spotifyexit-event-R44-HOLD.ps1"
PIN_R44="1c8f9d46fcb6a3c035a5dabf2b51e043932ce9c4"
NEW=HERE/"out"/"rapid-restart-r58"/"spotify-control-agent.vbs"
PIN_ORIGINAL_VBS="da054351cae6927504e735426d35f6d5e7edafcac7e06881f1adf1c20cecab9d"
def one(s,a,b,name):
    if s.count(a)!=1:raise RuntimeError("R58_ORIGINAL_TEST_ANCHOR_CHANGED_"+name)
    return s.replace(a,b,1)
def run():
    if (os.getenv("GITHUB_ACTIONS")!="true" or
        os.getenv("RUNNER_OS")!="Windows" or
        os.getenv("RUNNER_ENVIRONMENT")!="github-hosted"):
        raise RuntimeError("R58_GITHUB_HOSTED_WINDOWS_ONLY")
    head=subprocess.run(["git","rev-parse",":"+R44.relative_to(ROOT).as_posix()],
      cwd=ROOT,capture_output=True,check=False,timeout=15)
    if head.returncode or head.stdout.decode("ascii").strip()!=PIN_R44:
        raise RuntimeError("R58_REPRODUCIBLE_R44_REAL_WSCRIPT_LIFECYCLE_CHANGED")
    p=json.loads((NEW.parent/"receipt.json").read_text("utf-8"))
    sh=hashlib.sha256(NEW.read_bytes()).hexdigest()
    if (p.get("new_sha256")!=sh or
        p.get("mode")!="R58_RAPID_RESTART_DISTINCT_WMI_SESSION_HOLD" or
        p.get("r45_parent_sha256")!="1c1563bff9b9a87ae851b4ca555429b5451ce67c6d225a148b5252256d71cdf7"):
        raise RuntimeError("R58_VBS_NOT_FROM_EXACT_R45_PIN")
    test=R44.read_text("utf-8")
    test=one(test,"Spotify Control R44 Actual Exit Event",
        "Spotify Control R58 Two Rapid Exits","ISOLATED_SCRATCH_NAME")
    test=one(test,
        "validation/spotify-exit-immediate-maintenance-HOLD/out/integrated/spotify-control-agent.vbs",
        "validation/spotify-exit-immediate-maintenance-HOLD/out/rapid-restart-r58/spotify-control-agent.vbs",
        "R58_REAL_WMI_VBS_SOURCE_PATH")
    test=one(test,"'"+PIN_ORIGINAL_VBS+"'","'"+sh+"'","R58_REAL_VBS_SHA")
    test=one(test,"  if(-not(WaitEvent 'SpotifyExit' 105)){",
        "  if(-not(WaitEvent 'SpotifyExit' 18)){","FAST_FIRST_EXIT_WAIT")
    test=one(test,"$fake=$null\n$resident=$null","$fake=$null\n$second=$null\n$resident=$null",
      "SECOND_EXACT_TEST_OWNED_PROCESS")
    # Diagnose real WMI subscription initialization with console CScript
    # before launching the tested WScript resident. Valid 'probe' exits
    # before subscribing; this test-owned child dies before startup tick.
    preflight_anchor='  Add-Type -TypeDefinition @' + chr(39)
    preflight_test=r"""  $cscript=Join-Path $env:WINDIR 'System32/cscript.exe'
  $cscriptError=Join-Path $root 'r58-scratch-console-error.txt'
  $cscriptRun=Start-Process -FilePath $cscript -WorkingDirectory $bin -ArgumentList ('//NoLogo "'+$agent+'"') -RedirectStandardError $cscriptError -WindowStyle Hidden -PassThru -ErrorAction Stop
  try {
    Start-Sleep -Milliseconds 1200
    $cscriptRun.Refresh()
    if($cscriptRun.HasExited){
      if(Test-Path -LiteralPath $cscriptError){
        foreach($line in (Get-Content -LiteralPath $cscriptError -ErrorAction SilentlyContinue | Select-Object -Last 8)){
          Write-Host ('R58_REAL_CONSOLE_SCRIPT_ERROR='+[string]$line)
        }
      }
      throw 'R58_REAL_WMI_START_EVENT_CONSOLE_HOST_EXITED_DURING_INIT'
    }
  } finally {
    $cscriptRun.Refresh()
    if(-not $cscriptRun.HasExited){
      Stop-Process -Id $cscriptRun.Id -Force -ErrorAction Stop
      [void]$cscriptRun.WaitForExit(5000)
    }
  }
  Write-Host 'R58_REAL_VBS_START_STOP_SUBSCRIPTION_CONSOLE_INIT_SURVIVED=PASS'
"""
    test=one(test,preflight_anchor,preflight_test+preflight_anchor,
             "REAL_CONSOLE_RUNTIME_WMI_SUBSCRIPTION_INITIALIZATION")
    marker="  Write-Host 'R44_AUTHENTIC_WSCRIPT_TO_POWERSHELL_AGENTTICK_SPOTIFYEXIT=PASS'"
    injected=r"""  # Do not relax or disable legacy 60s debounce. Exactly one genuine
  # Spotify.exe restart and stop within 60 seconds after the first stop
  # must still generate a second event, and no duplicate third event.
  $rapidTimer=[Diagnostics.Stopwatch]::StartNew()
  $second=Start-Process -FilePath $fakeExe -WorkingDirectory $root -PassThru -ErrorAction Stop
  Start-Sleep -Milliseconds 650
  $secondVisible=@(Get-CimInstance Win32_Process -Filter "Name='Spotify.exe'" -ErrorAction Stop)
  if($secondVisible.Count -ne 1 -or [int]$secondVisible[0].ProcessId -ne $second.Id -or
     -not [string]::Equals([string]$secondVisible[0].ExecutablePath,$fakeExe,[StringComparison]::OrdinalIgnoreCase)){
     throw 'R58_SECOND_TEST_OWNED_SPOTIFY_WMI_PID_OR_PATH_NOT_EXACT'
  }
  $secondIdentity=@(Get-CimInstance Win32_Process -Filter ('ProcessId='+$second.Id) -ErrorAction Stop)
  if($secondIdentity.Count -ne 1 -or
    -not [string]::Equals([string]$secondIdentity[0].ExecutablePath,$fakeExe,[StringComparison]::OrdinalIgnoreCase)){
    throw 'R58_SECOND_PROCESS_AUTHORITY_WITNESS_NOT_VALID'
  }
  Stop-Process -Id $second.Id -Force -ErrorAction Stop
  [void]$second.WaitForExit(5000)
  if(@(Get-CimInstance Win32_Process -Filter "Name='Spotify.exe'" -ErrorAction Stop).Count -ne 0){
    throw 'R58_SECOND_SYNTHETIC_PROCESS_STILL_ACTIVE'
  }
  $observedSecond=$false
  for($i=0;$i -lt 68;$i++){
    if((EventCount 'SpotifyExit') -ge 2){$observedSecond=$true;break}
    $resident.Refresh()
    if($resident.HasExited){throw 'R58_REAL_WSCRIPT_HOST_EXITED_BEFORE_SECOND_EXIT'}
    Start-Sleep -Milliseconds 250
  }
  $rapidTimer.Stop()
  if(-not $observedSecond){
    $lines=@(Get-Content -LiteralPath $hostLog -ErrorAction SilentlyContinue)
    foreach($line in @($lines | Where-Object {
      $_ -like '*WMI START EVENT*' -or $_ -like '*WMI STOP EVENT*' -or
      $_ -like '*SPOTIFY EXIT confirmed*' -or $_ -like '*TICK LAUNCHED event=SpotifyExit*'
    } | Select-Object -Last 9)){
       Write-Host ('R58_SYNTHETIC_DIAG='+[string]$line)
    }
    throw 'R58_DISTINCT_START_STOP_SESSION_WITHIN_60S_WAS_SUPPRESSED'
  }
  if($rapidTimer.Elapsed.TotalSeconds -ge 60){
    throw 'R58_TWO_EXIT_EVENTS_NOT_WITHIN_LEGACY_DEBOUNCE_WINDOW'
  }
  Start-Sleep -Seconds 4
  if((EventCount 'SpotifyExit') -ne 2){
    throw 'R58_SAME_SESSION_DUPLICATE_WMI_STOP_EVENT_OVER_DISPATCHED'
  }
  $trace=@(Get-Content -LiteralPath $hostLog -ErrorAction Stop)
  if(@($trace | Where-Object {$_ -like '*WMI START EVENT subscribed*'}).Count -lt 1 -or
     @($trace | Where-Object {$_ -like '*TICK LAUNCHED event=SpotifyExit*'}).Count -ne 2){
    throw 'R58_GENUINE_START_TRACE_OR_SECOND_POWERSHELL_BRIDGE_NOT_PROVEN'
  }
  Write-Host ('R58_FIRST_AND_SECOND_FULL_STOP_EVENTS_SECONDS='+
    [Math]::Round($rapidTimer.Elapsed.TotalSeconds,2))
  Write-Host 'R58_NEW_SESSION_BYPASSES_60S_DEBOUNCE_WITH_EXACTLY_TWO_EVENTS=PASS'
  Write-Host 'R58_OLD_POLLING_FALLBACK_AND_DUPLICATE_PROTECTION_UNCHANGED=YES'
  Write-Host 'R58_ACTUAL_WMI_START_STOP_WSCRIPT_TO_REAL_POWERSHELL_STUB=PASS'
""" + marker
    test=one(test,marker,injected,"REAL_R44_WSCRIPT_SECOND_RAPID_STOP")
    old="""  if($null -ne $fake){try{$fake.Refresh();if(-not $fake.HasExited){Stop-Process -Id $fake.Id -Force -ErrorAction SilentlyContinue;[void]$fake.WaitForExit(5000)}}catch{}}"""
    new=old+"""
  if($null -ne $second){try{$second.Refresh();if(-not $second.HasExited){Stop-Process -Id $second.Id -Force -ErrorAction SilentlyContinue;[void]$second.WaitForExit(5000)}}catch{}}"""
    test=one(test,old,new,"SECOND_PROCESS_ALWAYS_CLEANUP")
    if PIN_ORIGINAL_VBS in test or "WaitEvent 'SpotifyExit' 105" in test:
        raise RuntimeError("R58_TEST_EXECUTES_OLD_VBS_OR_SLOW_POLL")
    target=Path(os.environ["RUNNER_TEMP"]).resolve()/"spotify-r58-two-real-exits.ps1"
    if target.exists() or not target.parent.is_dir():
        raise RuntimeError("R58_TEST_PREEXISTS")
    with target.open("x",encoding="utf-8",newline="\n") as f:
        f.write(test)
    print("R58_EXACT_ORIGINAL_R44_TEST_WSCRIPT_WMI_PROCESS_LIFECYCLE=SOURCE_PINNED")
    print("R58_NEW_WMI_SESSION_VBS_SHA256="+sh)
    print("R58_TWO_TEST_OWNED_SPOTIFY_EXECUTABLE_START_STOP_CYCLES=PREPARED")
    print("R58_NO_WINDOWS_APP_INSTALL_OR_USER_DATA_MUTATION=YES")
if __name__=="__main__":
    if sys.argv[1:]:raise SystemExit("R58 no args")
    run()
