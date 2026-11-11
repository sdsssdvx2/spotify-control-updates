"""R69 HOLD native Windows acceptance: verify fresh WMI service rebind
after a test-injected stale COM service reference; then genuine Spotify.exe
start/stop events through the actual WScript and PowerShell observer.
No WMI service restart, user files, real Spotify app, or release mutation.
"""
from __future__ import annotations
import hashlib, json, os, re
from importlib import util
from pathlib import Path
import sys

HERE=Path(__file__).resolve().parent
R58=HERE/"run-rapid-restart-real-wmi-R58-HOLD.py"
PRODUCT=HERE/"out/boot-wmi-r69/spotify-control-agent.vbs"
META=HERE/"out/boot-wmi-r69/receipt.json"
SCRATCH=HERE/"out/boot-wmi-injection-r69"
TEMP=Path(os.environ.get("RUNNER_TEMP","/nonexistent"))
ORIGINAL_TEST=TEMP/"spotify-r58-two-real-exits.ps1"
OUTPUT=TEMP/"spotify-r69-boot-wmi-real.ps1"
PARENT="4eb5940bd68bfbde412db5deba3e9c37cecb19632c66d6ec61dc0791bf838eab"
R58_TEST_SHA="8eb76416848a7da3e3ce02a7d169655f676ea109f9f9a050d94e364e48182874"

def sha(b):return hashlib.sha256(b).hexdigest()
def once(s,old,new,label):
    if s.count(old)!=1:raise RuntimeError("R69_TEST_ANCHOR_"+label)
    return s.replace(old,new,1)

def run():
    if (os.environ.get("GITHUB_ACTIONS")!="true" or
        os.environ.get("RUNNER_OS")!="Windows" or
        os.environ.get("RUNNER_ENVIRONMENT")!="github-hosted"):
        raise RuntimeError("R69_HOSTED_WINDOWS_ONLY")
    p=json.loads(META.read_text("utf-8"))
    raw=PRODUCT.read_bytes()
    target=p.get("agent_sha256")
    if (not isinstance(target,str) or len(target)!=64 or
        any(c not in "0123456789abcdef" for c in target)):
        raise RuntimeError("R69_CANDIDATE_SHA_FORMAT_INVALID")
    if (sha(raw)!=target or
        p.get("r66_parent_sha256")!=PARENT or
        p.get("mode")!="R69_WMI_UNAVAILABLE_AT_LOGON_HOLD" or
        p.get("retry_seconds")!=60 or p.get("agent_size")!=len(raw)):
        raise RuntimeError("R69_NEW_RESIDENT_PROVENANCE_CHANGED")
    if SCRATCH.exists() or OUTPUT.exists() or ORIGINAL_TEST.exists():
        raise RuntimeError("R69_SCRATCH_PREEXISTING_NO_REPLACE")
    bom=b"\xef\xbb\xbf" if raw.startswith(b"\xef\xbb\xbf") else b""
    content=raw[len(bom):].decode("utf-8")
    nl="\r\n" if "\r\n" in content else "\n"
    content=content.replace("\r\n","\n")
    # Force only the FIRST GetObject call to fail, in the scratch copy.
    # The original WMI service stays healthy for later genuine recovery.
    initial=re.findall(r'(?m)^[ \t]*Set[ \t]+wmi[ \t]*=[ \t]*GetObject\([^\r\n]*\)[ \t]*$',content)
    if len(initial)!=1:
        raise RuntimeError("R69_INITIAL_WMI_MONIKER_NOT_UNIQUE")
    content=once(content,initial[0],"Err.Raise 5",
                 "SCRATCH_ONLY_INITIAL_COM_BINDING_FAILURE")
    altered=bom+content.replace("\n",nl).encode("utf-8")
    SCRATCH.mkdir(parents=True,exist_ok=False)
    with (SCRATCH/"spotify-control-agent.vbs").open("xb") as f:f.write(altered)

    spec=util.spec_from_file_location("spotify_r69_reuse_r58_native_two_fast_closes",R58)
    if spec is None or spec.loader is None:raise RuntimeError("R58_NATIVE_TEMPLATE_UNAVAILABLE")
    r58=util.module_from_spec(spec)
    spec.loader.exec_module(r58)
    r58.run()
    text=ORIGINAL_TEST.read_text("utf-8")
    text=once(text,"Spotify Control R58 Two Rapid Exits",
              "Spotify Control R69 Boot WMI Recovery","UNIQUE_SCRATCH_ROOT")
    text=once(text,
       "validation/spotify-exit-immediate-maintenance-HOLD/out/rapid-restart-r58/spotify-control-agent.vbs",
       "validation/spotify-exit-immediate-maintenance-HOLD/out/boot-wmi-injection-r69/spotify-control-agent.vbs",
       "USE_TEST_OWNED_STALE_WMI_COPY")
    text=once(text,"'"+R58_TEST_SHA+"'","'"+sha(altered)+"'",
              "STABLE_NEW_TEST_VBS_SHA")
    wait=r"""  # Require a real WScript resident (not the brief CScript preflight)
  # to survive an injected unavailable startup WMI COM binding, acquire a fresh service
  # object, validate an enumerable Win32_Process query, and subscribe
  # to both genuine event streams before stopping the test-owned process.
  $rebound=$false
  for($probe=0;$probe -lt 440;$probe++){
    if(Test-Path -LiteralPath $hostLog -PathType Leaf){
      $logs=@(Get-Content -LiteralPath $hostLog -ErrorAction SilentlyContinue)
      if(@($logs | Where-Object {$_ -like '*WMI STARTUP COM binding unavailable, polling and bounded recovery*'}).Count -ge 1 -and
         @($logs | Where-Object {$_ -like '*WMI SERVICE fresh binding and process query verified*'}).Count -ge 1 -and
         @($logs | Where-Object {$_ -like '*WMI STOP EVENT resubscribed*'}).Count -ge 1 -and
         @($logs | Where-Object {$_ -like '*WMI START EVENT resubscribed*'}).Count -ge 1){
        $rebound=$true
        break
      }
    }
    $resident.Refresh()
    if($resident.HasExited){throw 'R69_REAL_WSCRIPT_EXITED_DURING_STALE_WMI'}
    Start-Sleep -Milliseconds 250
  }
  if(-not $rebound){
    if(Test-Path -LiteralPath $hostLog -PathType Leaf){
      foreach($line in @(Get-Content -LiteralPath $hostLog |
          Where-Object {$_ -like '*WMI*' -or $_ -like '*R69*'} |
          Select-Object -Last 14)){Write-Host ('R69_HOSTED_TRACE='+[string]$line)}
    }
    throw 'R69_FRESH_SERVICE_CONNECTION_NOT_RECOVERED_WITHIN_110S'
  }
  if((EventCount 'SpotifyExit') -ne 0){
    throw 'R69_FALSE_SPOTIFY_EXIT_DURING_WMI_QUERY_FAILURE'
  }
  Write-Host 'R69_BOOT_MISSING_WMI_AUTO_RECOVERED_AND_QUERY_VALID=PASS'
  Write-Host 'R69_BOOT_WMI_FAILURE_NEVER_FAKED_SPOTIFY_EXIT=PASS'
"""
    mark="  Write-Host 'R44_REAL_VBS_STARTUP_TICK_TO_POWERSHELL=PASS'"
    text=once(text,mark,mark+"\n"+wait,"REAL_WMI_REBIND_BEFORE_FIRST_STOP")
    if "'"+R58_TEST_SHA+"'" in text or "out/rapid-restart-r58/spotify-control-agent.vbs" in text:
        raise RuntimeError("R69_TEST_USING_PRIOR_PRODUCT")
    with OUTPUT.open("x",encoding="utf-8",newline="\n") as f:f.write(text)
    ORIGINAL_TEST.unlink()
    print("R69_EXACT_R66_PARENT_AND_NEW_AGENT_SOURCE_PINNED=PASS")
    print("R69_INJECT_INITIAL_GETOBJECT_FAILURE_ONLY_HOSTED_COPY=YES")
    print("R69_BOOT_FAULT_THEN_NATIVE_WSCRIPT_RECOVERY_TWO_EXITS_PREPARED=YES")
    print("R69_OWNER_MACHINE_RELEASE_AND_WMI_SERVICE=UNTOUCHED")

if __name__=="__main__":
    if sys.argv[1:]:raise SystemExit("No arguments")
    run()
