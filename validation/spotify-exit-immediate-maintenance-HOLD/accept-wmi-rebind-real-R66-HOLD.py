"""R66 HOLD native Windows acceptance: verify fresh WMI service rebind
after a test-injected stale COM service reference; then genuine Spotify.exe
start/stop events through the actual WScript and PowerShell observer.
No WMI service restart, user files, real Spotify app, or release mutation.
"""
from __future__ import annotations
import hashlib, json, os
from importlib import util
from pathlib import Path
import sys

HERE=Path(__file__).resolve().parent
R58=HERE/"run-rapid-restart-real-wmi-R58-HOLD.py"
PRODUCT=HERE/"out/rebind-r66/spotify-control-agent.vbs"
META=HERE/"out/rebind-r66/receipt.json"
SCRATCH=HERE/"out/rebind-injection-r66"
TEMP=Path(os.environ.get("RUNNER_TEMP","/nonexistent"))
ORIGINAL_TEST=TEMP/"spotify-r58-two-real-exits.ps1"
OUTPUT=TEMP/"spotify-r66-rebind-real-wmi.ps1"
PARENT="82f4547a33149a7db2d39b24745c0e3a5a04646bed693c5a6e93d01625798acc"
R58_TEST_SHA="8eb76416848a7da3e3ce02a7d169655f676ea109f9f9a050d94e364e48182874"

def sha(b):return hashlib.sha256(b).hexdigest()
def once(s,old,new,label):
    if s.count(old)!=1:raise RuntimeError("R66_TEST_ANCHOR_"+label)
    return s.replace(old,new,1)

def run():
    if (os.environ.get("GITHUB_ACTIONS")!="true" or
        os.environ.get("RUNNER_OS")!="Windows" or
        os.environ.get("RUNNER_ENVIRONMENT")!="github-hosted"):
        raise RuntimeError("R66_HOSTED_WINDOWS_ONLY")
    p=json.loads(META.read_text("utf-8"))
    raw=PRODUCT.read_bytes()
    target=p.get("agent_sha256")
    if (not isinstance(target,str) or len(target)!=64 or
        any(c not in "0123456789abcdef" for c in target)):
        raise RuntimeError("R66_CANDIDATE_SHA_FORMAT_INVALID")
    if (sha(raw)!=target or
        p.get("r63_parent_sha256")!=PARENT or
        p.get("mode")!="R66_FRESH_WMI_SERVICE_REBIND_AND_NO_FALSE_EXIT_HOLD" or
        p.get("retry_seconds")!=60 or p.get("agent_size")!=len(raw)):
        raise RuntimeError("R66_NEW_RESIDENT_PROVENANCE_CHANGED")
    if SCRATCH.exists() or OUTPUT.exists() or ORIGINAL_TEST.exists():
        raise RuntimeError("R66_SCRATCH_PREEXISTING_NO_REPLACE")
    bom=b"\xef\xbb\xbf" if raw.startswith(b"\xef\xbb\xbf") else b""
    content=raw[len(bom):].decode("utf-8")
    nl="\r\n" if "\r\n" in content else "\n"
    content=content.replace("\r\n","\n")
    anchor='nextSubscriptionRecovery = DateAdd("s", 60, Now)\nwmiNeedsReconnect = False'
    injected=anchor+'\nSet wmi = Nothing\nSet exitSource = Nothing\n'+ \
        'Set startSource = Nothing\nwmiNeedsReconnect = True\n'+ \
        'LogLine "R66 HOSTED STALE WMI COM SERVICE INJECTED"'
    content=once(content,anchor,injected,"EXACT_AFTER_BOTH_REAL_SUBSCRIPTIONS")
    altered=bom+content.replace("\n",nl).encode("utf-8")
    SCRATCH.mkdir(parents=True,exist_ok=False)
    with (SCRATCH/"spotify-control-agent.vbs").open("xb") as f:f.write(altered)

    spec=util.spec_from_file_location("spotify_r66_reuse_r58_native_two_fast_closes",R58)
    if spec is None or spec.loader is None:raise RuntimeError("R58_NATIVE_TEMPLATE_UNAVAILABLE")
    r58=util.module_from_spec(spec)
    spec.loader.exec_module(r58)
    r58.run()
    text=ORIGINAL_TEST.read_text("utf-8")
    text=once(text,"Spotify Control R58 Two Rapid Exits",
              "Spotify Control R66 Genuine Fresh WMI Bind","UNIQUE_SCRATCH_ROOT")
    text=once(text,
       "validation/spotify-exit-immediate-maintenance-HOLD/out/rapid-restart-r58/spotify-control-agent.vbs",
       "validation/spotify-exit-immediate-maintenance-HOLD/out/rebind-injection-r66/spotify-control-agent.vbs",
       "USE_TEST_OWNED_STALE_WMI_COPY")
    text=once(text,"'"+R58_TEST_SHA+"'","'"+sha(altered)+"'",
              "STABLE_NEW_TEST_VBS_SHA")
    wait=r"""  # Require a real WScript resident (not the brief CScript preflight)
  # to survive an injected stale wmi COM binding, acquire a fresh service
  # object, validate an enumerable Win32_Process query, and subscribe
  # to both genuine event streams before stopping the test-owned process.
  $rebound=$false
  for($probe=0;$probe -lt 440;$probe++){
    if(Test-Path -LiteralPath $hostLog -PathType Leaf){
      $logs=@(Get-Content -LiteralPath $hostLog -ErrorAction SilentlyContinue)
      if(@($logs | Where-Object {$_ -like '*R66 HOSTED STALE WMI COM SERVICE INJECTED*'}).Count -ge 1 -and
         @($logs | Where-Object {$_ -like '*WMI SERVICE fresh binding and process query verified*'}).Count -ge 1 -and
         @($logs | Where-Object {$_ -like '*WMI STOP EVENT resubscribed*'}).Count -ge 1 -and
         @($logs | Where-Object {$_ -like '*WMI START EVENT resubscribed*'}).Count -ge 1){
        $rebound=$true
        break
      }
    }
    $resident.Refresh()
    if($resident.HasExited){throw 'R66_REAL_WSCRIPT_EXITED_DURING_STALE_WMI'}
    Start-Sleep -Milliseconds 250
  }
  if(-not $rebound){
    if(Test-Path -LiteralPath $hostLog -PathType Leaf){
      foreach($line in @(Get-Content -LiteralPath $hostLog |
          Where-Object {$_ -like '*WMI*' -or $_ -like '*R66*'} |
          Select-Object -Last 14)){Write-Host ('R66_HOSTED_TRACE='+[string]$line)}
    }
    throw 'R66_FRESH_SERVICE_CONNECTION_NOT_RECOVERED_WITHIN_110S'
  }
  if((EventCount 'SpotifyExit') -ne 0){
    throw 'R66_FALSE_SPOTIFY_EXIT_DURING_WMI_QUERY_FAILURE'
  }
  Write-Host 'R66_FRESH_SWBEMSERVICES_AND_ENUMERABLE_PROCESS_QUERY=PASS'
  Write-Host 'R66_INVALID_WMI_STATUS_DID_NOT_TRIGGER_SPOTIFY_EXIT=PASS'
"""
    mark="  Write-Host 'R44_REAL_VBS_STARTUP_TICK_TO_POWERSHELL=PASS'"
    text=once(text,mark,mark+"\n"+wait,"REAL_WMI_REBIND_BEFORE_FIRST_STOP")
    if "'"+R58_TEST_SHA+"'" in text or "out/rapid-restart-r58/spotify-control-agent.vbs" in text:
        raise RuntimeError("R66_TEST_USING_PRIOR_PRODUCT")
    with OUTPUT.open("x",encoding="utf-8",newline="\n") as f:f.write(text)
    ORIGINAL_TEST.unlink()
    print("R66_EXACT_R63_PARENT_AND_NEW_AGENT_SOURCE_PINNED=PASS")
    print("R66_INJECT_ONLY_STALE_COM_BINDING_IN_HOSTED_COPY=YES")
    print("R66_NATIVE_TRUE_WSCRIPT_WMI_REBIND_AND_TWO_EXITS_PREPARED=YES")
    print("R66_OWNER_MACHINE_RELEASE_AND_WMI_SERVICE=UNTOUCHED")

if __name__=="__main__":
    if sys.argv[1:]:raise SystemExit("No arguments")
    run()
