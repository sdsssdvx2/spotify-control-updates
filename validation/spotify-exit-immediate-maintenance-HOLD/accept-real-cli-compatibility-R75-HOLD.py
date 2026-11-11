"""R75 HOLD genuine vendor-signed Spotify + official SHA-pinned Spicetify 2.46.4
+ complete unchanged R70 SpotifyControl main, in disposable Windows only.

Only replaces test-owned R73 mock spicetify.exe (not the product) with
authentic official verified CLI. Copies the signed Spotify executable into
the test profile solely for read-only version lookup, never authorizes apply,
backup, upgrade, or ANY addon mutation. Validates actual live metadata
compatibility (Spotify 1.3.8.x vs 2.46.4 documented max Windows 1.3.7).
"""
from __future__ import annotations
import hashlib,importlib.util,os
from pathlib import Path
import sys
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
TEMP=Path(os.environ.get("RUNNER_TEMP","/nonexistent")).resolve()
R73=HERE/"accept-real-signed-fullmain-R73-HOLD.py"
GENERATED=TEMP/"spotify-r73-real-fullmain-signed-exit.ps1"
OUTPUT=TEMP/"spotify-r75-real-spicetify-compatibility.ps1"
CLI=TEMP/"r75-official-spicetify"/"spicetify.exe"
CLI_SHA="3563f26acd7527adc97e6c19272fa1b48ce976a913625d9804ac57d3c54fb4db"
MAIN_SHA="b2b2fbf1afb60b58d501312160f7e2437c2452e90cb61ca8c2be0d877f92232d"
VBS_SHA="e56609ed8927512595f55c01ea50dbb9c8c59e4a2c86dcb3d16195a565c604d5"

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def once(t,a,b,label):
    if t.count(a)!=1:raise RuntimeError("R75_EXACT_SOURCE_ANCHOR_CHANGED_"+label)
    return t.replace(a,b,1)

def main():
    if (os.environ.get("GITHUB_ACTIONS")!="true" or
        os.environ.get("RUNNER_OS")!="Windows" or
        os.environ.get("RUNNER_ENVIRONMENT")!="github-hosted"):
        raise RuntimeError("R75_HOSTED_WINDOWS_ONLY")
    if sha(CLI)!=CLI_SHA or OUTPUT.exists() or GENERATED.exists():
        raise RuntimeError("R75_SIGNED_VENDOR_CLI_MISSING_OR_SCRATCH_ALREADY_USED")
    spec=importlib.util.spec_from_file_location("R75_reuse_real_Spotify_full_R73",R73)
    if not spec or not spec.loader:raise RuntimeError("R75_R73_SOURCE_MISSING")
    m=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    m.main()
    t=GENERATED.read_text("utf-8")
    start=t.index("  $spicetifyFixture=Join-Path $env:LOCALAPPDATA 'spicetify'")
    end=t.index("  $sourceMain='validation/spotify-exit-immediate-maintenance-HOLD/out/release-staging-boot-wmi-R70/bin/spotify-control.ps1'",start)
    original=t[start:end]
    if ("ReadOnlySpicetifyFixture" not in original or
        "R48_HOSTED_SPICETIFY_READ_ONLY_VERSION_FIXTURE_REGISTERED=PASS" not in original or
        original.count("Add-Type")!=1):
        raise RuntimeError("R75_ONLY_R48_SYNTHETIC_SPICETIFY_BLOCK_BOUNDARY")
    replacement=r"""  # Actual Spicetify 2.46.4 from GitHub official immutable SHA release.
  # Exactly test-owned profile root: never install or execute in user profile.
  $officialCli=Join-Path $env:RUNNER_TEMP 'r75-official-spicetify\spicetify.exe'
  $spicetifyFixture=Join-Path $env:LOCALAPPDATA 'spicetify'
  [void][IO.Directory]::CreateDirectory($spicetifyFixture)
  $spicetifyExe=Join-Path $spicetifyFixture 'spicetify.exe'
  $expectedCLI='3563f26acd7527adc97e6c19272fa1b48ce976a913625d9804ac57d3c54fb4db'
  if((Hash $officialCli) -cne $expectedCLI){
    throw 'R75_OFFICIAL_SPICETIFY_EXE_HASH_CHANGED'
  }
  [IO.File]::Copy($officialCli,$spicetifyExe,$false)
  if((Hash $spicetifyExe) -cne $expectedCLI){
    throw 'R75_COPIED_REAL_CLI_MUTATED'
  }
  $env:PATH=$spicetifyFixture+';'+$env:PATH
  $env:SPICETIFY_CONFIG=Join-Path $env:APPDATA 'spicetify'
  $env:SPICETIFY_STATE=Join-Path $env:LOCALAPPDATA 'spicetify-state'
  $located=Get-Command spicetify.exe -ErrorAction Stop
  if(-not [string]::Equals([string]$located.Source,$spicetifyExe,
     [StringComparison]::OrdinalIgnoreCase)){
    throw 'R75_PRODUCT_MAIN_REAL_CLI_NOT_FROM_PINNED_SANDBOX'
  }
  $cliVersion=& $spicetifyExe -v 2>&1
  if($LASTEXITCODE -ne 0 -or ([string]($cliVersion -join ' ')) -notmatch '\b2\.46\.4\b'){
    throw 'R75_REAL_CLI_VERSION_QUERY_FAILED'
  }
  # Real official Spotify.exe was installed in the runner's original
  # profile, but the real product main intentionally runs in scratch.
  # Clone only signed binary for its exact unmodified Get-SpotifyVersion.
  $snapSpotify=Join-Path $env:APPDATA 'Spotify\Spotify.exe'
  if(Test-Path -LiteralPath $snapSpotify){throw 'R75_SCRATCH_SPOTIFY_ALREADY_EXISTS'}
  [void][IO.Directory]::CreateDirectory((Split-Path -Parent $snapSpotify))
  [IO.File]::Copy($fakeExe,$snapSpotify,$false)
  if((Hash $snapSpotify) -cne (Hash $fakeExe)){
    throw 'R75_SIGNED_SPOTIFY_EXECUTABLE_VERSION_SNAPSHOT_CHANGED'
  }
  $vendorVersion=[Diagnostics.FileVersionInfo]::GetVersionInfo($snapSpotify).ProductVersion
  if($vendorVersion -notmatch '^1\.3\.8(\.|$)'){
    throw 'R75_THIS_ACCEPTANCE_EXPECTS_THE_GENUINE_SPOTIFY_1_3_8'
  }
  Write-Host 'R75_EXACT_REAL_SPICETIFY_2464_IN_ISOLATED_PROFILE=PASS'
  Write-Host 'R75_SIGNED_SPOTIFY_VERSION_SOURCE_IN_SCRATCH_PROFILE=PASS'
"""
    t=t[:start]+replacement+t[end:]
    # Additional actual full-main state observations, not a synthetic
    # bool or mocked function, and no altered application source.
    final_line="  Write-Host 'R73_OWNER_MUTATION_OFF_REAL_ADDON_WRITES_NOT_AUTHORIZED=PASS'"
    insert=r"""  # Guard must come from actual main discovery, not a mock or test
  # callback. Fail closed unless it can verify the exact upper bound.
  $live=Get-Content -LiteralPath $statePath -Raw -ErrorAction Stop |
    ConvertFrom-Json -ErrorAction Stop
  if([string]$live.spicetify_installed_version -cne '2.46.4' -or
     [string]$live.spicetify_max_windows -cne '1.3.7' -or
     $live.current_spotify_supported -ne $false -or
     [bool]$live.agent_mutation_enabled){
     throw ('R75_REAL_VERSION_COMPATIBILITY_GUARD_NOT_VERIFIED: '+[string]$live.last_agent_decision)
  }
  if(-not (Test-Path -LiteralPath $spicetifyExe -PathType Leaf) -or
     (Hash $spicetifyExe) -cne $expectedCLI){
    throw 'R75_REAL_SPICETIFY_BINARY_CHANGED_BY_MAIN_READONLY_TICK'
  }
  Write-Host 'R75_SPOTIFY_138_ABOVE_OFFICIAL_SPICETIFY_2464_MAX_137=TRUE'
  Write-Host 'R75_MAIN_COMPATIBILITY_CURRENT_SUPPORTED_FALSE=PASS'
  Write-Host 'R75_REAL_CLI_AND_SIGNED_SPOTIFY_NO_AUTO_MUTATION=PASS'
"""
    t=once(t,final_line,final_line+"\n"+insert,"REAL_COMPATIBILITY_OUTCOME")
    if ("ReadOnlySpicetifyFixture" in t or
        "R48_HOSTED_SPICETIFY_READ_ONLY_VERSION_FIXTURE_REGISTERED" in t):
        raise RuntimeError("R75_REAL_CLI_TEST_STILL_SYNTHETIC")
    if t.count("R75_MAIN_COMPATIBILITY_CURRENT_SUPPORTED_FALSE=PASS")!=1:
        raise RuntimeError("R75_REAL_OUTCOME_ASSERTION_MISSING")
    with OUTPUT.open("x",encoding="utf-8",newline="\n") as f:f.write(t)
    GENERATED.unlink()
    print("R75_EXACT_COMPLETE_PRODUCT_MAIN_SHA256="+MAIN_SHA)
    print("R75_EXACT_RESIDENT_SHA256="+VBS_SHA)
    print("R75_REAL_SPICETIFY_CLI_SHA256="+CLI_SHA)
    print("R75_HOSTED_REAL_VENDOR_STACK_PREPARED;NO_USER_CLI_INSTALL=YES")

if __name__=="__main__":
    if sys.argv[1:]:raise SystemExit("R75 no args")
    main()
