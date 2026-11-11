"""R73 HOLD: actual Spotify AB signed app -> WMI -> exact R70 WScript
-> complete unchanged R54 Spotify Control main, owner mutation DISABLED.

Reuse TWO accepted Windows suites (R48 authentic full-main no-mutation
bridge, R72 genuine vendor-signed Spotify launcher). Only splice test
owned real Spotify process start/stop into R48 generated native script.
Never install or alter the owner's PC, Spotify settings, Spicetify, or main.
"""
from __future__ import annotations
import hashlib, importlib.util, os
from pathlib import Path
import sys

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
TEMP=Path(os.environ.get("RUNNER_TEMP","/nonexistent")).resolve()
R48=HERE/"prepare-real-main-bridge-R48-HOLD.py"
R72=TEMP/"spotify-r72-real-signed-exit.ps1"
R48_GENERATED=TEMP/"spotify-r48-real-full-main-spotifyexit.ps1"
OUTPUT=TEMP/"spotify-r73-real-fullmain-signed-exit.ps1"
MAIN="b2b2fbf1afb60b58d501312160f7e2437c2452e90cb61ca8c2be0d877f92232d"
VBS="e56609ed8927512595f55c01ea50dbb9c8c59e4a2c86dcb3d16195a565c604d5"
STAGE="validation/spotify-exit-immediate-maintenance-HOLD/out/release-staging-boot-wmi-R70"

def once(s:str,a:str,b:str,why:str)->str:
    if s.count(a)!=1:raise RuntimeError("R73_SOURCE_ANCHOR_"+why)
    return s.replace(a,b,1)

def between(t:str,begin:str,end:str,why:str)->str:
    i=t.find(begin)
    if i<0:raise RuntimeError("R73_SPAN_START_"+why)
    j=t.find(end,i+len(begin))
    if j<0:raise RuntimeError("R73_SPAN_END_"+why)
    return t[i:j]

def main():
    if (os.environ.get("GITHUB_ACTIONS")!="true" or
        os.environ.get("RUNNER_OS")!="Windows" or
        os.environ.get("RUNNER_ENVIRONMENT")!="github-hosted"):
        raise RuntimeError("R73_GITHUB_WINDOWS_ONLY")
    if OUTPUT.exists() or R48_GENERATED.exists() or not R72.is_file():
        raise RuntimeError("R73_PINNED_NATIVE_R72_PRECONDITION_FAILED")
    if hashlib.sha256((ROOT/STAGE/"bin/spotify-control.ps1").read_bytes()).hexdigest()!=MAIN:
        raise RuntimeError("R73_REAL_PRODUCT_MAIN_SHA_MISMATCH")
    if hashlib.sha256((ROOT/STAGE/"bin/spotify-control-agent.vbs").read_bytes()).hexdigest()!=VBS:
        raise RuntimeError("R73_REAL_RESIDENT_SHA_MISMATCH")
    spec=importlib.util.spec_from_file_location("spotify_r73_reuse_R48_exact_main_WScript",R48)
    if not spec or not spec.loader:raise RuntimeError("R73_R48_MISSING")
    m=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    m.MAIN_PIN=MAIN
    m.VBS_PIN=VBS
    m.SOURCE=STAGE
    m.NEW_SCRATCH="Spotify Control R73 Signed App Full Main"
    m.main()

    test=R48_GENERATED.read_text("utf-8")
    vendor=R72.read_text("utf-8")
    test=once(test,
       "$fakeExe=Join-Path $root 'Spotify.exe'",
       "$fakeExe=Join-Path $env:APPDATA 'Spotify\\Spotify.exe'",
       "R48_PROCESS_PATH_TO_VENDOR_APP")
    signed_launch=between(vendor,
         "  # Official binary from Spotify's own current x64 installer",
         "  $wscript=Join-Path $env:WINDIR 'System32/wscript.exe'",
         "VENDOR_SIGNED_SPOTIFY_RUN")
    # The verified R48 main runs in a scratch-shaped profile. Spotify itself
    # must start against the vendor installer profile BEFORE its environment
    # is reset; the product main / resident still inherit isolated scratch.
    launch='  $fake=Start-Process -FilePath $fakeExe -WorkingDirectory (Split-Path -Parent $fakeExe) -PassThru -ErrorAction Stop'
    if signed_launch.count(launch)!=1:
        raise RuntimeError("R73_REAL_VENDOR_LAUNCH_CHANGED")
    wrapped='''  $scratchLocal=$env:LOCALAPPDATA
  $scratchRoaming=$env:APPDATA
  try {
    $env:LOCALAPPDATA=$previousLocal
    $env:APPDATA=$previousRoaming
    $fake=Start-Process -FilePath $fakeExe -WorkingDirectory (Split-Path -Parent $fakeExe) -PassThru -ErrorAction Stop
  } finally {
    $env:LOCALAPPDATA=$scratchLocal
    $env:APPDATA=$scratchRoaming
  }'''
    signed_launch=signed_launch.replace(launch,wrapped,1)
    if "R72_REAL_SIGNED_SPOTIFY_EXECUTABLE_WMI_PROCESSES=VERIFIED" not in signed_launch:
        raise RuntimeError("R73_REAL_VENDOR_PROCESS_PROOF_MISSING")
    # R48 contains a separate, harmless Spicetify -v-only test executable.
    # ONLY remove its synthetic Spotify.exe program, never the Spicetify guard.
    synthetic_cls="public class SyntheticSpotifyProcess"
    clspos=test.find(synthetic_cls)
    if clspos<0:raise RuntimeError("R73_R48_SYNTHETIC_CLASS_NOT_FOUND")
    i=test.rfind("  Add-Type -TypeDefinition @'",0,clspos)
    j=test.find("  $wscript=Join-Path $env:WINDIR 'System32/wscript.exe'",clspos)
    if i<0 or j<0 or "R44_SYNTHETIC_SPOTIFY_EXE_REAL_WMI_PROCESS=VERIFIED" not in test[i:j]:
        raise RuntimeError("R73_TEST_START_BLOCK_CHANGED")
    test=test[:i]+signed_launch+test[j:]

    signed_stop=between(vendor,
       "  # Close only the exact vendor-signed executable",
       "  if(-not(WaitEvent 'SpotifyExit' 105))",
       "VENDOR_SIGNED_STOP")
    i=test.find("  $fake.Refresh()")
    j=test.find("  if(-not(WaitEvent 'SpotifyExit' 75))",i)
    if i<0 or j<0 or "R44_EXACT_TEST_OWNED_SPOTIFY_STOPPED=PASS" not in test[i:j]:
        raise RuntimeError("R73_R48_SYNTHETIC_STOP_NOT_ISOLATED")
    test=test[:i]+signed_stop+test[j:]
    cleanup=between(vendor,
       "  # Child Spotify renderer PIDs can outlive",
       "  if(Test-Path -LiteralPath $root){Remove-Item",
       "VENDOR_CHILD_CLEANUP")
    marker="  if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue}"
    test=once(test,marker,cleanup+marker,"TEST_OWNED_CHILD_CLEANUP")
    test=once(test,
       "R48_AUTHENTIC_VBS_TO_FULL_MAIN_AGENTTICK_PERSISTED_SPOTIFYEXIT=PASS",
       "R73_SIGNED_VENDOR_APP_TO_FULL_R54_MAIN_STATE_PERSISTED_SPOTIFYEXIT=PASS",
       "FULL_MAIN_STATE_PROOF")
    test=once(test,
       "R48_OWNER_MUTATION_OFF_REAL_MAINTENANCE_NOT_AUTHORIZED=PASS",
       "R73_OWNER_MUTATION_OFF_REAL_ADDON_WRITES_NOT_AUTHORIZED=PASS",
       "MAINTENANCE_AUTHORITY_OFF")
    test=once(test,
       "R44_REAL_VBS_NEUTRAL_CWD_AND_BIN_RENAME=PASS",
       "R73_SIGNED_VENDOR_APP_REAL_VBS_NEUTRAL_CWD_AND_BIN_RENAME=PASS",
       "NEUTRAL_CWD_PROOF")
    # Supplement source with an explicit stable per-user Spotify signed EXE
    # before and after real main runs. Product main is fully unmodified.
    if "ReadOnlySpicetifyFixture" not in test or \
       "last_agent_decision" not in test or \
       "agent_mutation_enabled" not in test or \
       "SyntheticSpotifyProcess" in test:
        raise RuntimeError("R73_REAL_MAIN_OR_VENDOR_PROCESS_ASSERTIONS_MISSING")
    with OUTPUT.open("x",encoding="utf-8",newline="\n") as f:f.write(test)
    R48_GENERATED.unlink()
    print("R73_R48_EXACT_UNMODIFIED_MAIN_WITH_READONLY_SPICETIFY_GUARD=PASS")
    print("R73_R72_SIGNED_REAL_SPOTIFY_START_STOP_REUSED_EXACT=PASS")
    print("R73_R70_MAIN_SHA256="+MAIN)
    print("R73_R70_VBS_SHA256="+VBS)
    print("R73_HOSTED_ONLY_NO_USER_SIGNIN_NO_OPERATOR_PC=YES")

if __name__=="__main__":
    if sys.argv[1:]:raise SystemExit("No arguments")
    main()
