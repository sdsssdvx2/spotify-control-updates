"""R48 HOLD: exercise the final actual WScript/WMI SpotifyExit monitor with
the complete, unmodified, SHA-pinned future spotify-control.ps1.

Reuses the already accepted R44 Windows test's exact test-owned Spotify.exe
identity, WScript launch, stop confirmation and cleanup. Switches only the
test receiver from a stub to the full hosted scratch main and observes native
persistent state, with owner mutation explicitly OFF.

The real production Spotify, user paths/credentials, public update, and
Windows shell shortcuts are never touched.
"""
from __future__ import annotations

import hashlib
import os
from pathlib import Path
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
R44=HERE/"accept-real-vbs-spotifyexit-event-R44-HOLD.ps1"
R44_PIN="1c8f9d46fcb6a3c035a5dabf2b51e043932ce9c4"
MAIN_PIN="7caf4afe19c283aef3b5bebb30e0e598b10de147d3ab1ddd9724bf90594c59fe"
VBS_PIN="1c1563bff9b9a87ae851b4ca555429b5451ce67c6d225a148b5252256d71cdf7"
NEW_SCRATCH="Spotify Control R48 Full Main Exit Bridge"
SOURCE="validation/spotify-exit-immediate-maintenance-HOLD/out/release-staging-eventdriven-R46"

def one(src:str,old:str,new:str,label:str)->str:
    if src.count(old)!=1:
        raise RuntimeError("R48_ANCHOR_DRIFT_"+label)
    return src.replace(old,new,1)

def main():
    if (os.getenv("GITHUB_ACTIONS")!="true" or
        os.getenv("RUNNER_OS")!="Windows" or
        os.getenv("RUNNER_ENVIRONMENT")!="github-hosted"):
        raise RuntimeError("R48_HOSTED_WINDOWS_REQUIRED")
    rev=subprocess.run(["git","rev-parse",":"+R44.relative_to(ROOT).as_posix()],
       cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.PIPE,check=False,timeout=20)
    if rev.returncode or rev.stdout.decode("ascii").strip()!=R44_PIN:
        raise RuntimeError("R48_PROVEN_REAL_WSCRIPT_TEST_BLOB_DRIFT")
    # Use the selected exact source stage for both SHA preflight and the
    # generated real-WScript fixture; they must not silently disagree.
    target=ROOT/SOURCE/"bin"/"spotify-control.ps1"
    if hashlib.sha256(target.read_bytes()).hexdigest()!=MAIN_PIN:
        raise RuntimeError("R48_REAL_MAIN_TARGET_SOURCE_BYTES_DRIFT")
    text=R44.read_text("utf-8")
    text=one(text,"Spotify Control R44 Actual Exit Event",NEW_SCRATCH,"TEST_SCRATCH_NAME")
    text=one(text,"$bin=Join-Path $root 'bin'",
       "$bin=Join-Path (Join-Path (Join-Path $root 'LocalAppData') 'SpotifyControl') 'bin'",
       "CANONICAL_LOCALAPPDATA_BIN")
    text=one(text,
       "$source='validation/spotify-exit-immediate-maintenance-HOLD/out/integrated/spotify-control-agent.vbs'",
       f"$source='{SOURCE}/bin/spotify-control-agent.vbs'",
       "FAST_WMI_AGENT_SOURCE")
    text=one(text,"'da054351cae6927504e735426d35f6d5e7edafcac7e06881f1adf1c20cecab9d'",
       f"'{VBS_PIN}'","FAST_WMI_AGENT_SHA")
    text=one(text,
       "$hostLog=Join-Path (Join-Path $root 'logs') 'resident-agent-host.log'",
       "$hostLog=Join-Path (Join-Path (Split-Path -Parent $bin) 'logs') 'resident-agent-host.log'",
       "ORIGINAL_HOST_LOG_AT_CANONICAL_APP_ROOT")
    text=one(text,
       "$events=Join-Path $root 'agent-events.txt'",
       "$statePath=Join-Path (Split-Path -Parent $bin) 'state.json'",
       "READ_NATIVE_STATE_RECEIPT")
    text=one(text,
       "$fake=$null\n$resident=$null",
       "$fake=$null\n$resident=$null\n$previousLocal=$env:LOCALAPPDATA\n$previousRoaming=$env:APPDATA",
       "SAVED_PROFILE_ENV")
    start=text.index("function EventCount([string]$name){")
    end=text.index("function WaitEvent([string]$name,[int]$seconds){",start)
    receiver="""function EventCount([string]$name){
  if($name -ceq 'Startup'){
    if(-not(Test-Path -LiteralPath $hostLog -PathType Leaf)){return 0}
    return @((Get-Content -LiteralPath $hostLog -ErrorAction Stop) |
      Where-Object {$_ -like '*TICK LAUNCHED event=Startup*'}).Count
  }
  if($name -ceq 'SpotifyExit'){
    if(-not(Test-Path -LiteralPath $statePath -PathType Leaf)){return 0}
    try {
      $native=Get-Content -LiteralPath $statePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
      if([string]$native.last_agent_event -ceq 'SpotifyExit'){return 1}
    } catch {}
  }
  return 0
}
"""
    text=text[:start]+receiver+text[end:]
    start=text.index("  # The normal VBS dispatch is unmodified.")
    end=text.index("  if(@(Get-CimInstance Win32_Process",start)
    # Unlike R44's no-op PowerShell receiver, the authentic product main
    # refuses AgentTick when Spicetify is not installed/discoverable.
    # Provide only a scratch, version-query-capable Spicetify CLI. Every
    # potential configuration or mutation CLI action returns exit 79.
    harmless_spicetify=r"""
  $spicetifyFixture=Join-Path $env:LOCALAPPDATA 'spicetify'
  [void][IO.Directory]::CreateDirectory($spicetifyFixture)
  $spicetifyExe=Join-Path $spicetifyFixture 'spicetify.exe'
  Add-Type -TypeDefinition @'
using System;
public class ReadOnlySpicetifyFixture {
  public static int Main(string[] args) {
    if (args.Length == 1 && (args[0] == "-v" || args[0] == "--version" || args[0] == "version")) {
      Console.WriteLine("2.41.0");
      return 0;
    }
    return 79;
  }
}
'@ -OutputAssembly $spicetifyExe -OutputType ConsoleApplication -ErrorAction Stop
  $env:PATH=$spicetifyFixture+';'+$env:PATH
  $located=Get-Command spicetify.exe -ErrorAction Stop
  if(-not [string]::Equals([string]$located.Source,$spicetifyExe,[StringComparison]::OrdinalIgnoreCase)){
    throw 'R48_SPICETIFY_NAME_NOT_RESOLVED_TO_HOSTED_MOCK'
  }
  Write-Host 'R48_HOSTED_SPICETIFY_READ_ONLY_VERSION_FIXTURE_REGISTERED=PASS'
"""
    real_main=f"""  # Exact complete product main; all writes redirected to this isolated
  # account-shaped TEMP profile with owner mutation OFF.
  $env:LOCALAPPDATA=Join-Path $root 'LocalAppData'
  $env:APPDATA=Join-Path $root 'Roaming'
  [void][IO.Directory]::CreateDirectory($env:APPDATA)
  # Prevent a duplicate unrelated network scan at startup. The real exit
  # still triggers its own exact full-main discovery independently.
  $nowCheck=[DateTimeOffset]::UtcNow.ToString("o")
  $stateRaw='{{"schema":20,"agent_mutation_enabled":false,"pending_maintenance":false,"maintenance_check_healthy":false,"pending_addon_auto_ambiguous":0,"last_agent_event":null,"last_check_only_utc":"'+$nowCheck+'"}}'
  [IO.File]::WriteAllText($statePath,$stateRaw,[Text.Encoding]::ASCII)
{harmless_spicetify}  $sourceMain='{SOURCE}/bin/spotify-control.ps1'
  if((Hash $sourceMain) -cne '{MAIN_PIN}'){{throw 'R48_SOURCE_MAIN_IS_NOT_THE_EXACT_RELEASE'}}
  [IO.File]::Copy((Resolve-Path $sourceMain).Path,$control,$false)
  if((Hash $control) -cne '{MAIN_PIN}'){{throw 'R48_STAGED_FULL_MAIN_FILE_CHANGED'}}
  $tokens=$null;$errors=$null
  [void][Management.Automation.Language.Parser]::ParseFile($control,[ref]$tokens,[ref]$errors)
  if(@($errors).Count -ne 0){{throw 'R48_FULL_MAIN_WINDOWS_PS51_PARSE_FAILED'}}
  Write-Host 'R48_REAL_UNMODIFIED_MAIN_PLUS_FAST_VBS_INSTALLED_SCRATCH_ONLY=PASS'
"""
    text=text[:start]+real_main+text[end:]
    # R44's stub completed almost instantly, while the complete real main
    # may still be reading its script when VBS logs "TICK LAUNCHED". Wait
    # for the real startup receipt and require the bin handle to become
    # movable within a small bounded drain, rather than treating transient
    # PowerShell script-open handles as a permanent WScript CWD leak.
    old_move="""  $moved=Join-Path $root 'bin-temporary-rename'
  [IO.Directory]::Move($bin,$moved)
  [IO.Directory]::Move($moved,$bin)"""
    new_move="""  $startupObserved=$false
  for($j=0;$j -lt 80;$j++){
    if(Test-Path -LiteralPath $statePath -PathType Leaf){
      try{
        $startup=Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        if([string]$startup.last_agent_event -ceq 'Startup'){
          $startupObserved=$true;break
        }
      }catch{}
    }
    Start-Sleep -Milliseconds 250
  }
  if(-not $startupObserved){throw 'R48_REAL_STARTUP_TICK_NOT_FINISHED'}
  $moved=Join-Path $root 'bin-temporary-rename'
  $binReleased=$false
  for($j=0;$j -lt 30;$j++){
    try {
      [IO.Directory]::Move($bin,$moved)
      [IO.Directory]::Move($moved,$bin)
      $binReleased=$true
      break
    } catch [System.IO.IOException] {
      Start-Sleep -Milliseconds 250
    } catch [System.UnauthorizedAccessException] {
      Start-Sleep -Milliseconds 250
    }
  }
  if(-not $binReleased){throw 'R48_BIN_REMAINED_LOCKED_AFTER_REAL_STARTUP_COMPLETE'}"""
    text=one(text,old_move,new_move,"R48_REAL_STARTUP_CHILD_FINISH_AND_BIN_DRAIN")
    text=one(text,
       "  if(-not(WaitEvent 'SpotifyExit' 105)){",
       """  if(-not(WaitEvent 'SpotifyExit' 75)){
    if(Test-Path -LiteralPath $hostLog -PathType Leaf){
      $messages=@(Get-Content -LiteralPath $hostLog -ErrorAction SilentlyContinue)
      foreach($message in @($messages | Where-Object {
        $_ -match 'TICK LAUNCHED|SPOTIFY EXIT confirmed|FATAL|ERROR'
      } | Select-Object -Last 9)){
        Write-Host ('R48_DIAG_SCRATCH_WSCRIPT='+[string]$message)
      }
    }
    if(Test-Path -LiteralPath $statePath -PathType Leaf){
      try {
        $snapshot=Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        Write-Host ('R48_DIAG_LAST_EVENT='+[string]$snapshot.last_agent_event)
        Write-Host ('R48_DIAG_LAST_DECISION='+[string]$snapshot.last_agent_decision)
      }catch{Write-Host 'R48_DIAG_STATE_READ_FAILED'}
    }
    $appRoot=Split-Path -Parent $bin
    foreach($file in @(Get-ChildItem -LiteralPath $appRoot -Recurse -File -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -in @('resident-agent-latest.json','spotify-control.log','resident-agent-host.log') })){
      Write-Host ('R48_DIAG_SCRATCH_REPORT_EXISTS='+[string]$file.Name)
    }
    """,
       "BOUND_FULL_MAIN_AGENT_COMPLETION")
    text=one(text,
       "  Write-Host 'R44_REAL_POWERSHELL_MAINTENANCE_HANDLER=NOT_INVOKED_STUB_ONLY'",
       """  $final=Get-Content -LiteralPath $statePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
  if([string]$final.last_agent_event -cne 'SpotifyExit' -or
     [bool]$final.agent_mutation_enabled){
    throw 'R48_NATIVE_STATE_DID_NOT_RECORD_EXIT_OR_MUTATION_WAS_ENABLED'
  }
  if(-not([string]$final.last_agent_decision)){
    throw 'R48_NATIVE_AGENTTICK_DID_NOT_PERSIST_DECISION'
  }
  Write-Host ('R48_REAL_MAIN_SAFE_AGENTTICK_DECISION='+[string]$final.last_agent_decision)
  Write-Host 'R48_AUTHENTIC_VBS_TO_FULL_MAIN_AGENTTICK_PERSISTED_SPOTIFYEXIT=PASS'
  Write-Host 'R48_OWNER_MUTATION_OFF_REAL_MAINTENANCE_NOT_AUTHORIZED=PASS'""",
       "REAL_MAIN_STATE_EVIDENCE")
    text=one(text,
       "} finally {\n  if($null -ne $resident)",
       "} finally {\n  $env:LOCALAPPDATA=$previousLocal\n  $env:APPDATA=$previousRoaming\n  if($null -ne $resident)",
       "PROFILE_ENV_RESTORATION")
    # The previous event source and root-dir tests must be reused, unchanged.
    for required in ("R44_SYNTHETIC_SPOTIFY_EXE_REAL_WMI_PROCESS=VERIFIED",
       "R44_REAL_VBS_NEUTRAL_CWD_AND_BIN_RENAME=PASS",
       "R44_EXACT_TEST_OWNED_SPOTIFY_STOPPED=PASS",
       "R44_ACTUAL_WMI_SPOTIFY_EXIT_VBS_SETTLE_AND_EVENT=PASS"):
        if text.count(required)!=1:
            raise RuntimeError("R48_PROVEN_WINDOWS_EVENT_LIFECYCLE_MISSING")
    dest=Path(os.environ["RUNNER_TEMP"]).resolve()/(
        "spotify-r48-real-full-main-spotifyexit.ps1")
    if dest.exists() or not dest.parent.is_dir():
        raise RuntimeError("R48_SCRATCH_RUNNER_SCRIPT_EXISTS")
    with dest.open("x",encoding="utf-8",newline="\n") as f:
        f.write(text)
    print("R48_REAL_FULL_MAIN_SHA256="+MAIN_PIN)
    print("R48_REAL_FAST_WMI_RESIDENT_SHA256="+VBS_PIN)
    print("R48_SOURCE_SCRIPT_REUSES_EXACT_R44_WMI_TEST=PASS")
    print("R48_MODE=GITHUB_HOSTED_SCRATCH;NO_OWNER_PROFILE_OR_PUBLIC_RELEASE")

if __name__=="__main__":
    if sys.argv[1:]:
        raise SystemExit("R48 takes no runtime parameters")
    main()
