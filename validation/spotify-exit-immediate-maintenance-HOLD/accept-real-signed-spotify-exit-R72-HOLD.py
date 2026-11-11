"""R72 HOLD: one hosted Windows acceptance with real signed Spotify.exe.
Strictly no owner PC, no Spotify credentials, no production release or app data.
Reuses exact successful R44 WScript/native observer; replaces only the
synthetic process with a currently Spotify-AB-signed official x64 binary.
Signing authenticity is required; a moving official installer is NOT
a reproducible binary pin and its observed version/hash are only evidence.
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
SOURCE=HERE/"accept-real-vbs-spotifyexit-event-R44-HOLD.ps1"
SOURCE_BLOB="1c8f9d46fcb6a3c035a5dabf2b51e043932ce9c4"
AGENT=HERE/"out/boot-wmi-r69/spotify-control-agent.vbs"
RECEIPT=HERE/"out/boot-wmi-r69/receipt.json"
EXPECTED_AGENT="e56609ed8927512595f55c01ea50dbb9c8c59e4a2c86dcb3d16195a565c604d5"
OUTPUT=Path(os.environ.get("RUNNER_TEMP","/invalid")).resolve()/"spotify-r72-real-signed-exit.ps1"
def sha(b:bytes)->str:return hashlib.sha256(b).hexdigest()
def once(t:str,old:str,new:str,why:str)->str:
    if t.count(old)!=1:raise RuntimeError("R72_PINNED_R44_ANCHOR_DRIFT_"+why)
    return t.replace(old,new,1)

def main()->None:
    if (os.environ.get("GITHUB_ACTIONS")!="true" or
        os.environ.get("RUNNER_OS")!="Windows" or
        os.environ.get("RUNNER_ENVIRONMENT")!="github-hosted"):
        raise RuntimeError("R72_REAL_SPOTIFY_REQUIRES_EPHEMERAL_WINDOWS_RUNNER")
    if OUTPUT.exists() or not OUTPUT.parent.is_dir():
        raise RuntimeError("R72_TEST_SCRIPT_PREEXISTS_OR_TEMP_UNAVAILABLE")
    a=subprocess.run(["git","rev-parse",":"+SOURCE.relative_to(ROOT).as_posix()],
      cwd=ROOT,capture_output=True,check=False,timeout=15)
    if a.returncode or a.stdout.decode("ascii").strip()!=SOURCE_BLOB:
        raise RuntimeError("R72_NATIVE_R44_WSCRIPT_BASELINE_CHANGED")
    r=json.loads(RECEIPT.read_text("utf-8"))
    agent=AGENT.read_bytes()
    if (sha(agent)!=EXPECTED_AGENT or r.get("agent_sha256")!=EXPECTED_AGENT
       or r.get("r66_parent_sha256")!="4eb5940bd68bfbde412db5deba3e9c37cecb19632c66d6ec61dc0791bf838eab"
       or r.get("mode")!="R69_WMI_UNAVAILABLE_AT_LOGON_HOLD"):
        raise RuntimeError("R72_TEST_DID_NOT_PIN_EXACT_R69_RESIDENT")
    t=SOURCE.read_text("utf-8")
    t=once(t,"Spotify Control R44 Actual Exit Event",
        "Spotify Control R72 Real Signed Spotify Exit","SCRATCH_SCOPE")
    t=once(t,
       "validation/spotify-exit-immediate-maintenance-HOLD/out/integrated/spotify-control-agent.vbs",
       "validation/spotify-exit-immediate-maintenance-HOLD/out/boot-wmi-r69/spotify-control-agent.vbs",
       "PRODUCT_R69_VBS_ONLY")
    t=once(t,"'da054351cae6927504e735426d35f6d5e7edafcac7e06881f1adf1c20cecab9d'",
        "'"+EXPECTED_AGENT+"'","R69_SHA_PIN")
    t=once(t,"$fakeExe=Join-Path $root 'Spotify.exe'",
       "$fakeExe=Join-Path $env:APPDATA 'Spotify\\Spotify.exe'","OFFICIAL_APP_PATH")
    # No synthetic executable gets compiled or executed.
    p0=t.index("  Add-Type -TypeDefinition @'")
    p1=t.index("  $wscript=Join-Path $env:WINDIR 'System32/wscript.exe'",p0)
    if p0<0 or p1<0 or "R44_SYNTHETIC_SPOTIFY_EXE_REAL_WMI_PROCESS=VERIFIED" not in t[p0:p1]:
        raise RuntimeError("R72_SYNTHETIC_PROCESS_BLOCK_UNRECOGNIZED")
    real=r"""  # Official binary from Spotify's own current x64 installer, downloaded
  # by the hosted CI job over TLS and Authenticode validated BEFORE execution.
  if(-not(Test-Path -LiteralPath $fakeExe -PathType Leaf)){
    throw 'R72_REAL_SIGNED_SPOTIFY_NOT_INSTALLED'
  }
  $appSignature=Get-AuthenticodeSignature -LiteralPath $fakeExe -ErrorAction Stop
  if([string]$appSignature.Status -cne 'Valid' -or
     $null -eq $appSignature.SignerCertificate -or
     [string]$appSignature.SignerCertificate.Subject -cnotmatch '(?i)(^|,)\s*O=Spotify AB(,|$)'){
     throw 'R72_REAL_APP_CERTIFICATE_NOT_VALID_SPOTIFY_AB'
  }
  $appHash=Hash $fakeExe
  $version=[Diagnostics.FileVersionInfo]::GetVersionInfo($fakeExe).ProductVersion
  if([string]::IsNullOrWhiteSpace($version)){throw 'R72_UNSIGNED_OR_UNKNOWN_SPOTIFY_VERSION'}
  Write-Host ('R72_AUTHENTIC_OFFICIAL_SPOTIFY_EXECUTABLE_SHA256='+$appHash)
  Write-Host ('R72_AUTHENTIC_OFFICIAL_SPOTIFY_EXECUTABLE_VERSION='+[string]$version)
  $fake=Start-Process -FilePath $fakeExe -WorkingDirectory (Split-Path -Parent $fakeExe) -PassThru -ErrorAction Stop
  Start-Sleep -Seconds 7
  $visible=@(Get-CimInstance Win32_Process -Filter "Name='Spotify.exe'" -ErrorAction Stop)
  if($visible.Count -lt 1 -or $visible.Count -gt 80){
    throw 'R72_REAL_SPOTIFY_APP_NOT_STILL_RUNNING_AFTER_7S'
  }
  foreach($p in $visible){
    if(-not [string]::Equals([string]$p.ExecutablePath,$fakeExe,
           [StringComparison]::OrdinalIgnoreCase)){
      throw 'R72_FOREIGN_SPOTIFY_PROCESS_MIXED_WITH_INSTALL'
    }
  }
  Write-Host ('R72_REAL_SIGNED_SPOTIFY_PROCESS_COUNT='+[string]$visible.Count)
  Write-Host 'R72_REAL_SIGNED_SPOTIFY_EXECUTABLE_WMI_PROCESSES=VERIFIED'
"""
    t=t[:p0]+real+t[p1:]
    p0=t.index("  $fake.Refresh()")
    p1=t.index("  if(-not(WaitEvent 'SpotifyExit' 105))",p0)
    if p0<0 or p1<0 or "R44_EXACT_TEST_OWNED_SPOTIFY_STOPPED=PASS" not in t[p0:p1]:
        raise RuntimeError("R72_SYNTHETIC_TERMINATION_SCOPE_UNRECOGNIZED")
    terminate=r"""  # Close only the exact vendor-signed executable installed on this
  # fresh ephemeral runner, never any other Spotify or arbitrary process.
  $closed=$false
  for($attempt=0;$attempt -lt 5;$attempt++){
    $observed=@(Get-CimInstance Win32_Process -Filter "Name='Spotify.exe'" -ErrorAction Stop)
    if($observed.Count -eq 0){$closed=$true;break}
    if($observed.Count -gt 80){throw 'R72_UNEXPECTED_MULTIPLE_SPOTIFY_PROCESSES'}
    foreach($p in $observed){
      if(-not [string]::Equals([string]$p.ExecutablePath,$fakeExe,
          [StringComparison]::OrdinalIgnoreCase)){
        throw 'R72_FOREIGN_SPOTIFY_PROCESS_STOP_FORBIDDEN'
      }
    }
    foreach($p in $observed){
      Stop-Process -Id ([int]$p.ProcessId) -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Milliseconds 800
  }
  if(-not $closed -and
     @(Get-CimInstance Win32_Process -Filter "Name='Spotify.exe'" -ErrorAction Stop).Count -gt 0){
    throw 'R72_REAL_SPOTIFY_PROCESSES_NOT_CLOSED'
  }
  Write-Host 'R72_SIGNED_REAL_SPOTIFY_PROCESSES_STOPPED=PASS'
"""
    t=t[:p0]+terminate+t[p1:]
    t=t.replace("R44_REAL_VBS","R72_REAL_SPOTIFY_VBS")
    # The R44 completed/observer semantics remain unchanged and must not
    # claim actual Spotify audio or signed Spicetify modification.
    t=once(t,"Write-Host 'R44_REAL_POWERSHELL_MAINTENANCE_HANDLER=NOT_INVOKED_STUB_ONLY'",
     "Write-Host 'R72_SPICETIFY_AND_USER_AUDIO=NOT_TESTED'\n  Write-Host 'R72_POWERSHELL_MAINTENANCE_HANDLER=NO_MUTATION_STUB_ONLY'",
     "NO_REAL_ADDON_MUTATIONS")
    # End-of-test cleanup: only original exact installed Spotify application.
    # The ephemeral GitHub-hosted runner is discarded after the test.
    marker="  if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue}"
    cleanup=r"""  # Child Spotify renderer PIDs can outlive the initial process object.
  # Cleanup is confined to the same verified path, on a hosted disposable PC.
  try {
    $left=@(Get-CimInstance Win32_Process -Filter "Name='Spotify.exe'" -ErrorAction SilentlyContinue)
    foreach($p in $left){
      if([string]::Equals([string]$p.ExecutablePath,$fakeExe,
          [StringComparison]::OrdinalIgnoreCase)){
        Stop-Process -Id ([int]$p.ProcessId) -Force -ErrorAction SilentlyContinue
      }
    }
  } catch {}
"""
    t=once(t,marker,cleanup+marker,"EXACT_VENDOR_PROCESS_CHILD_CLEANUP")
    # Only source-owned scratch, no machine private location in reports.
    if ("SyntheticSpotifyProcess" in t or "Add-Type -TypeDefinition" in t
        or "fake process" in t.lower()):
        raise RuntimeError("R72_SYNTHETIC_EXE_REFERENCE_STILL_PRESENT")
    with OUTPUT.open("x",encoding="utf-8",newline="\n") as f:f.write(t)
    print("R72_PINNED_R69_WSCRIPT_AND_R44_BRIDGE=PASS")
    print("R72_REAL_VENDOR_SIGNED_SPOTIFY_INSTALL_AND_PROCESS_PROOF=PREPARED")
    print("R72_SPOTIFY_USER_ACCOUNT_AND_OWNER_PC=NOT_ACCESSED")
    print("R72_NO_MUTATING_SPOTIFYCONTROL_MAIN_HANDLER=BENIGN_STUB")

if __name__=="__main__":
    if sys.argv[1:]:raise SystemExit("R72 no options")
    main()
