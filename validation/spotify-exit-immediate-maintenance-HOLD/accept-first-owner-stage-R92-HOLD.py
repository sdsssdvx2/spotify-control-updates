"""R92 HOLD: test first-time R90->R86->real R84->real R85->real R88
on native GitHub-hosted Win32 WScript scratch. R77 live preflight MUST be
synthetic because this disposable Windows runner is NOT the user's signed
Spotify + authorized Spicetify + production update ACL environment.

All modifications are to generated RUNNER_TEMP test scripts only.
The original R86, R90, R84, R85, R88, and public main remain unchanged.
"""
from __future__ import annotations
import hashlib
import os
from pathlib import Path
import sys

DIR=Path(__file__).resolve().parent
TMP=Path(os.environ.get("RUNNER_TEMP","/not-runner")).resolve()
NATIVE=TMP/"spotify-r43-integrated-real-owner-cutover.ps1"
R90_TEST=TMP/"spotify-r91-hosted-r90-driver.ps1"
R86_ORIGINAL=DIR/"owner-onepass-offline-stage-R86-HOLD.ps1"
R86_HOST=TMP/"spotify-r92-hosted-r86-driver.ps1"

def safe(ok:bool,why:str):
    if not ok: raise RuntimeError("R92_"+why)

def once(text:str,original:str,substitute:str,label:str)->str:
    safe(text.count(original)==1,"UNIQUE_SOURCE_ANCHOR_"+label)
    return text.replace(original,substitute,1)

def main():
    safe(os.environ.get("GITHUB_ACTIONS")=="true" and
         os.environ.get("RUNNER_OS")=="Windows" and
         os.environ.get("RUNNER_ENVIRONMENT")=="github-hosted" and
         TMP.is_dir() and not TMP.is_symlink(),
         "ISOLATED_GITHUB_WINDOWS_ONLY")
    safe(NATIVE.is_file() and R90_TEST.is_file() and
         R86_ORIGINAL.is_file() and not R86_HOST.exists(),
         "PINNED_TEST_SOURCES_REQUIRED")

    b=R86_ORIGINAL.read_bytes()
    safe(8000<=len(b)<=9000 and hashlib.sha1(b"blob "+str(len(b)).encode()+b"\x00"+b).hexdigest() ==
         "698019f4fbce9a9bf0bd838dfb69539e737e0dc5",
         "ORIGINAL_R86_GIT_BLOB_CHANGED")
    r86=b.decode("utf-8")
    r86=once(r86,
      """  if(([Security.Principal.WindowsPrincipal]::new($id)).IsInRole(
      [Security.Principal.WindowsBuiltInRole]::Administrator)){""",
      """  if($false -and ([Security.Principal.WindowsPrincipal]::new($id)).IsInRole(
      [Security.Principal.WindowsBuiltInRole]::Administrator)){""",
      "HOSTED_RUNNER_ACCOUNT_ONLY")

    # Fetch R77 exact immutable original as usual, but produce synthetic
    # owner environmental evidence on this GitHub machine. NO false claim
    # that Spotify signer, installed CLI or actual user's ACL was inspected.
    fixture_audit="""  $audit=@(
    'DIAGNOSTIC=SPOTIFY_R77_OWNER_ACL_READONLY',
    'OWNER_TOKEN=STANDARD_USER',
    'STABLE_MAIN_V0628=EXACT',
    'ADDON_MANAGER_R17=EXACT',
    'RESIDENT_VBS=EXACT',
    'OFFICIAL_BOOTSTRAP=EXACT',
    'EXACT_INSTALLED_STACK=PASS',
    'SPOTIFY_SIGNATURE=VALID_SPOTIFY_AB',
    'SPICETIFY_CLI_SOURCE_PIN=OFFICIAL_2464',
    'CURRENT_COMPATIBILITY=OFFICIALLY_SUPPORTED_RANGE',
    'SPOTIFY_PROCESS=CLOSED',
    'RESIDENT_PROCESS_PATH_MATCH=ONE_MATCH',
    'STATE_FILE=PARSED_NOT_AUTHORITY',
    'SPOTIFY_UPDATE_GUARD_SAVED=BLOCKED_REPORTED_ONLY',
    'UPDATE_FOLDER_ACL_NOW=OWNER_WRITE_DELETE_DENY_ACE_PRESENT',
    'SAVED_GUARD_VS_ACL=SAVED_BLOCKED_MATCHES_LIVE_ACL',
    'ACL_PROOF_LEVEL=OWNER_DENY_ACES_ONLY_NOT_ACCESS_CHECK',
    'OWNER_ENVIRONMENT_PRECHECK=READONLY_CONSISTENT_NOT_DEPLOY_AUTHORITY',
    'AUTHORIZE_DEPLOY=NO;AUTOMATIC_RETRY=NO;OWNER_SOURCE_CHANGE=NO',
    'AGENT_MUTATION_SAVED=ARMED_SAVED',
    'RESULT=READONLY_SNAPSHOT_COMPLETE'
  )
  Write-Host 'R92_R77_ENVIRONMENT=HOSTED_SYNTHETIC_NOT_USER_WINDOWS'"""
    r86=once(r86,
      "  $audit=@(& ([ScriptBlock]::Create([Text.Encoding]::UTF8.GetString($r77))))",
      fixture_audit,
      "R77_SYNTHETIC_WIN_SIGNER_CLI_ACL")
    r86=once(r86,
      "  $readiness=@(& ([ScriptBlock]::Create([Text.Encoding]::UTF8.GetString($r27))))",
      """  $fixture=Join-Path $env:RUNNER_TEMP 'spotify-future-bootstrap-rehearsal'
  $readiness=@(& ([ScriptBlock]::Create([Text.Encoding]::UTF8.GetString($r27))) -HostedFixtureRoot $fixture)""",
      "R27_GENUINE_NATIVE_HOSTED_OWNER_PROCESS")
    safe("R84_RESULT=PRIVATE_CANDIDATE_STAGED_NOT_INSTALLED" in r86 and
         "RESULT=R85_OWNER_PRIVATE_OFFLINE_TRANSPORT_PREPARED_HOLD" in r86 and
         "R86_OFFLINE_PRIVATE_STAGE_ID=" in r86,
         "R84_R85_NATIVE_POSITIVE_STAGE_NOT_PRESENT")

    r90=R90_TEST.read_text("utf-8")
    safe("R90_EXISTING_PRIVATE_STAGE=ONE_EXACT_CANDIDATE_REUSED" in r90 and
         "HOSTED_PRIVATE_OFFLINE_ONESHOT_COMMITTED" in r90,
         "R91_VERIFIED_R90_HOSTED_DERIVATIVE_REQUIRED")
    r90=once(r90,
      """    $existing=@(Get-Item -LiteralPath $env:R87_OFFLINE_STAGE -Force -ErrorAction Stop)""",
      """    $existing=@()""",
      "R90_FIRST_TIME_NO_PREEXISTING_STAGE")
    r90=once(r90,
      """      [byte[]]$r86=FrozenSource '9c98e6a59619b3fa02cbdc61edc0276d733f8598' 'owner-onepass-offline-stage-R86-HOLD.ps1' '698019f4fbce9a9bf0bd838dfb69539e737e0dc5' 20000""",
      """      [byte[]]$r86=[IO.File]::ReadAllBytes((Join-Path $env:RUNNER_TEMP 'spotify-r92-hosted-r86-driver.ps1'))""",
      "EXACT_R86_TEST_DERIVATIVE_ONLY")
    r90=once(r90,
      """      $r86Result=@(& ([ScriptBlock]::Create([Text.Encoding]::UTF8.GetString($r86))))""",
      """      $r86Result=@(& ([ScriptBlock]::Create([Text.Encoding]::UTF8.GetString($r86))))
      foreach($r92Line in @($r86Result)){
        if([string]$r92Line -cmatch '^[A-Z0-9_]{2,64}=[A-Za-z0-9_.;-]{1,150}$'){
          Write-Host ('R92_R86_SAFE_RECEIPT_'+[string]$r92Line)
        }
      }""",
      "R86_OWNER_FIRST_STAGE_PROOF")
    safe(r90.count("$existing=@()")==1 and
         r90.count("spotify-r92-hosted-r86-driver.ps1")==1 and
         "R90_R86_NEW_PRIVATE_STAGE=VERIFIED" in r90,
         "R90_REAL_NEW_STAGE_PATH_NOT_RETAINED")

    src=NATIVE.read_text("utf-8")
    safe("R91_ACTUAL_R90_NATIVE_SINGLE_OWNER_ENTRY_WAS_INVOKED=PASS" in src and
         "R91_REAL_R90_PINNED_OWNER_SINGLE_ENTRY_WITH_R88_WSCRIPT_TRANSACTION=PASS" in src,
         "PREVIOUS_R91_NATIVE_RESULT_NOT_PRESENT")
    src=once(src,
      "$receipt -cnotcontains 'R90_EXISTING_PRIVATE_STAGE=ONE_EXACT_CANDIDATE_REUSED'",
      "$receipt -cnotcontains 'R90_R86_NEW_PRIVATE_STAGE=VERIFIED'",
      "R90_FIRST_STAGE_SUCCESS_REQUIRES_REAL_R86")
    src=once(src,
      "Write-Host 'R91_REAL_R90_PINNED_OWNER_SINGLE_ENTRY_WITH_R88_WSCRIPT_TRANSACTION=PASS'",
      """Write-Host 'R91_REAL_R90_PINNED_OWNER_SINGLE_ENTRY_WITH_R88_WSCRIPT_TRANSACTION=PASS'
    if(@($receipt|Where-Object {$_ -ceq 'R90_R86_NEW_PRIVATE_STAGE=VERIFIED'}).Count -ne 1){
      throw 'R92_FIRST_TIME_R84_R85_OWNER_STAGE_NOT_PROVEN'
    }
    Write-Host 'R92_REAL_R86_R84_R85_FIRST_STAGE_TO_R90_R88_OWNER_WSCRIPT_COMMIT=PASS'""",
      "NEW_SOURCE_FIRST_STAGE_ACTUAL_EXECUTION")

    R86_HOST.write_text(r86,encoding="utf-8",newline="\n")
    R90_TEST.write_text(r90,encoding="utf-8",newline="\n")
    NATIVE.write_text(src,encoding="utf-8",newline="\n")
    print("R92_R86_PINNED_ORIGINAL_SHA256="+hashlib.sha256(b).hexdigest())
    print("R92_HOSTED_SYNTHETIC_R77_NOT_USER_ACL_OR_SIGNER=YES")
    print("R92_REAL_R84_R85_FIRST_STAGE_FROM_NETWORK_TO_OWNER_PRIVACY=PREPARED")
    print("R92_PUBLIC_RELEASE_AND_ACTUAL_USER_PC=UNCHANGED")

if __name__=="__main__":
    if len(sys.argv)!=1: raise SystemExit("No args")
    main()
