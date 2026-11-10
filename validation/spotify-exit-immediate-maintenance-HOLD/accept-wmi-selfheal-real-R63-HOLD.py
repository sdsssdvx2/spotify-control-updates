"""R63 Windows proof: inject both WMI event handles' loss ONLY in a
scratched copy of the new resident, wait for automatic re-subscription,
then reuse R58's real WScript, real synthetic Spotify.exe and its second
rapid restart with the original full-speed WMI detection.

No change to Windows WMI service, user app, real resident, or product.
"""
from __future__ import annotations
import hashlib
from importlib import util
import json
import os
from pathlib import Path
import sys
HERE=Path(__file__).resolve().parent
R58=HERE/"run-rapid-restart-real-wmi-R58-HOLD.py"
PRODUCT=HERE/"out/selfheal-r63/spotify-control-agent.vbs"
META=HERE/"out/selfheal-r63/receipt.json"
SCRATCH=HERE/"out/selfheal-injection-r63"
TEMP=Path(os.environ.get("RUNNER_TEMP","/nonexistent"))
R58_TEMP=TEMP/"spotify-r58-two-real-exits.ps1"
OUTPUT=TEMP/"spotify-r63-selfheal-real-wmi.ps1"
OLD="8eb76416848a7da3e3ce02a7d169655f676ea109f9f9a050d94e364e48182874"

def sha(b):return hashlib.sha256(b).hexdigest()
def one(s,b,a,what):
    if s.count(b)!=1:raise RuntimeError("R63_FIXTURE_SOURCE_ANCHOR_"+what)
    return s.replace(b,a,1)

def main():
    if (os.environ.get("GITHUB_ACTIONS")!="true" or
        os.environ.get("RUNNER_OS")!="Windows" or
        os.environ.get("RUNNER_ENVIRONMENT")!="github-hosted"):
        raise RuntimeError("R63_HOSTED_WINDOWS_ONLY")
    p=json.loads(META.read_text("utf-8"))
    raw=PRODUCT.read_bytes()
    if (p.get("agent_sha256")!=sha(raw) or
        p.get("r58_parent_sha256")!=OLD or
        p.get("mode")!="R63_BOUND_WMI_EVENT_RESUBSCRIBE_ONCE_PER_60_SECONDS_HOLD" or
        p.get("retry_seconds")!=60 or len(raw)!=p.get("agent_size")):
        raise RuntimeError("R63_PRODUCT_PROVENANCE_NOT_EXACT")
    if SCRATCH.exists() or OUTPUT.exists() or R58_TEMP.exists():
        raise RuntimeError("R63_TEST_SCRATCH_PREEXISTS_NO_REPLACE")
    bom=b"\xef\xbb\xbf" if raw.startswith(b"\xef\xbb\xbf") else b""
    s=raw[len(bom):].decode("utf-8")
    nl="\r\n" if "\r\n" in s else "\n"
    s=s.replace("\r\n","\n")
    # Injection occurs after both genuine subscriptions, but before
    # the resident's first process snapshot / main loop.
    anchor='nextSubscriptionRecovery = DateAdd("s", 60, Now)\nlastExitStamp = CDbl(0)'
    replacement='nextSubscriptionRecovery = DateAdd("s", 60, Now)\n'+\
        'Set exitSource = Nothing\nSet startSource = Nothing\n'+\
        'LogLine "R63 HOSTED INITIAL EVENT SOURCES LOST"\nlastExitStamp = CDbl(0)'
    s=one(s,anchor,replacement,"INJECT_ONCE_AFTER_REAL_SUBSCRIPTIONS")
    altered=bom+s.replace("\n",nl).encode("utf-8")
    SCRATCH.mkdir(parents=True,exist_ok=False)
    (SCRATCH/"spotify-control-agent.vbs").write_bytes(altered)

    spec=util.spec_from_file_location("spotify_r63_reuses_r58_real_wmi",R58)
    if spec is None or spec.loader is None:raise RuntimeError("R58_NATIVE_TEST_MISSING")
    mod=util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod.run()
    test=R58_TEMP.read_text("utf-8")
    test=one(test,"Spotify Control R58 Two Rapid Exits",
             "Spotify Control R63 Self Heal Native","UNIQUE_SCRATCH_ROOT")
    test=one(test,
       "validation/spotify-exit-immediate-maintenance-HOLD/out/rapid-restart-r58/spotify-control-agent.vbs",
       "validation/spotify-exit-immediate-maintenance-HOLD/out/selfheal-injection-r63/spotify-control-agent.vbs",
       "INJECTED_RESIDENT_PATH_ONLY")
    test=one(test,"'"+OLD+"'","'"+sha(altered)+"'",
             "EXACT_INJECTED_RESIDENT_SHA")
    mark="  Write-Host 'R44_REAL_VBS_STARTUP_TICK_TO_POWERSHELL=PASS'"
    wait=r"""  # R63: leave original synthetic Spotify.exe still running while the
  # live WScript restores both genuine WMI subscriptions after 60 seconds.
  # Only then may we stop that exact test-owned process.
  $recovered=$false
  for($probe=0;$probe -lt 440;$probe++){
    if(Test-Path -LiteralPath $hostLog -PathType Leaf){
      $trace=@(Get-Content -LiteralPath $hostLog -ErrorAction SilentlyContinue)
      if(@($trace | Where-Object {$_ -like '*R63 HOSTED INITIAL EVENT SOURCES LOST*'}).Count -eq 1 -and
         @($trace | Where-Object {$_ -like '*WMI STOP EVENT resubscribed*'}).Count -ge 1 -and
         @($trace | Where-Object {$_ -like '*WMI START EVENT resubscribed*'}).Count -ge 1){
        $recovered=$true
        break
      }
    }
    $resident.Refresh()
    if($resident.HasExited){throw 'R63_WSCRIPT_EXITED_BEFORE_WMI_RECOVERY'}
    Start-Sleep -Milliseconds 250
  }
  if(-not $recovered){throw 'R63_BOTH_REAL_WMI_EVENT_SOURCES_NOT_RECOVERED_IN_110S'}
  if((EventCount 'SpotifyExit') -ne 0){throw 'R63_FALSE_SPOTIFY_EXIT_DURING_WMI_RECOVERY'}
  Write-Host 'R63_BOTH_WMI_SUBSCRIPTIONS_SELF_HEALED_ON_LIVE_WSCRIPT=PASS'
"""
    test=one(test,mark,mark+"\n"+wait,"WAIT_FOR_TRUE_BOTH_SOURCE_RECOVERY")
    if "'"+OLD+"'" in test:
        raise RuntimeError("R63_STALE_VBS_TEST_PIN")
    OUTPUT.write_text(test,encoding="utf-8",newline="\n")
    R58_TEMP.unlink()
    print("R63_REAL_R58_NATIVE_DOUBLE_EXIT_REUSED=PASS")
    print("R63_WMI_EVENT_LOSS_ONLY_SCRATCH_INJECTION=YES")
    print("R63_NATIVE_RECONNECT_THEN_TWO_FAST_EXITS_PREPARED=YES")
    print("R63_USER_WINDOWS_AND_OFFICIAL_RELEASE_UNCHANGED=YES")

if __name__=="__main__":
    if sys.argv[1:]:raise SystemExit("No args")
    main()
