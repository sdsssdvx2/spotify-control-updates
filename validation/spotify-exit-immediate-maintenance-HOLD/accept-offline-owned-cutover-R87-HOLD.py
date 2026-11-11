"""R87 HOLD: Bind real R84/R85 protected file-URI source to the *existing*
native R82/R28 Windows WScript owner transition and Bootstrap rollback test.

This adapter is exclusively for ephemeral GitHub-hosted Windows RUNNER_TEMP.
It never modifies production sources, owner PC, user shortcuts, or public main.
No HTTP listener: the old scratch Bootstrap and R28 driver consume the exact
locally staged SHA-pinned 21 chunk source from R85. No release authority.
"""
from __future__ import annotations
import hashlib
import importlib.util
import os
from pathlib import Path
import sys

HERE=Path(__file__).resolve().parent
TEMP=Path(os.environ.get("RUNNER_TEMP","/not-runner")).resolve()
POWER=TEMP/"spotify-r43-integrated-real-owner-cutover.ps1"
PREP=TEMP/"spotify-r43-integrated-prepare.py"
R82=HERE/"accept-immutable-review-owned-cutover-R82-HOLD.py"
SOURCE_SHA="27c3bbd2935c8568ee6d260085d8008aec5e173a"
MAIN_SHA="b2b2fbf1afb60b58d501312160f7e2437c2452e90cb61ca8c2be0d877f92232d"
AGENT_SHA="e56609ed8927512595f55c01ea50dbb9c8c59e4a2c86dcb3d16195a565c604d5"
ORIGINAL_MANIFEST_SHA="71395858fcce58500bb42070bf4b248e2ab14613e148e7d74e616c252d6c3332"
BOOT_SHA="d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6"

def once(s:str,a:str,b:str,code:str)->str:
    if s.count(a)!=1: raise RuntimeError("R87_UNEXPECTED_FROZEN_TEST_ANCHOR_"+code)
    return s.replace(a,b,1)

def run():
    if (os.environ.get("GITHUB_ACTIONS")!="true" or
        os.environ.get("RUNNER_OS")!="Windows" or
        os.environ.get("RUNNER_ENVIRONMENT")!="github-hosted" or
        not TEMP.is_dir() or TEMP.is_symlink()):
        raise RuntimeError("R87_GITHUB_HOSTED_WINDOWS_ONLY")
    if POWER.exists() or PREP.exists():
        raise RuntimeError("R87_PREVIOUS_DRIVER_ALREADY_GENERATED")
    spec=importlib.util.spec_from_file_location("r87_reuse_actual_r82_native",R82)
    if spec is None or spec.loader is None:
        raise RuntimeError("R87_FROZEN_R82_ADAPTER_UNAVAILABLE")
    module=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.run()
    src=POWER.read_text("utf-8")
    parent=hashlib.sha256(src.encode("utf-8")).hexdigest()
    # Replace only the HTTP-server launch, preserving the original fixture
    # and the R28 owner cutover, rollback, WScript, mutex tests verbatim.
    src=once(src,
        '$server=Start-Process -FilePath $python -ArgumentList (\'"\'+$scriptAbs+\'" serve\') -PassThru -WindowStyle Hidden',
        """[void][IO.Directory]::CreateDirectory($fixture)
    [IO.File]::WriteAllText((Join-Path $fixture 'server-port'),'17865',[Text.Encoding]::ASCII)
    Write-Host 'R87_NO_HTTP_SERVER_OFFLINE_FILE_URI_ONLY=PASS'""",
        "OLD_HTTP_SERVER_LAUNCH")
    src=once(src,
        "Write-Host 'FUTURE_BOOTSTRAP_CONSUMED_IDENTICAL_STAGED_MANIFEST_AND_CHUNKS_PASS'",
        """Write-Host 'FUTURE_BOOTSTRAP_CONSUMED_IDENTICAL_STAGED_MANIFEST_AND_CHUNKS_PASS'
    # R87 proof is sourced from the separate actual R84->R85 private stage,
    # not from the legacy R81 hosted HTTP mirror, which only supplies the
    # original pinned user-state and WScript scratch fixture.
    $r87Dirs=@(Get-ChildItem -LiteralPath $localBefore -Directory -Filter 'SpotifyControlCanary-offline-ready-*' -ErrorAction Stop)
    if($r87Dirs.Count -ne 1 -or $r87Dirs[0].Name -cnotmatch '^SpotifyControlCanary-offline-ready-[0-9a-f]{32}$'){
      throw 'R87_VERIFIED_OFFLINE_PRIVATE_STAGE_NOT_UNIQUE'
    }
    $env:R87_OFFLINE_STAGE=$r87Dirs[0].FullName
    $r87ReceiptPath=Join-Path $env:R87_OFFLINE_STAGE 'offline-receipt.json'
    $r87Receipt=Get-Content -LiteralPath $r87ReceiptPath -Raw | ConvertFrom-Json
    if($r87Receipt.schema -cne 'SPOTIFY_R85_PRIVATE_OFFLINE_TRANSPORT_V1' -or
       $r87Receipt.result -cne 'HOLD_ONLY_NOT_DEPLOYABLE' -or
       $r87Receipt.installed_bootstrap_changed -ne $false -or
       $r87Receipt.owner_approved -ne $false -or
       [int]$r87Receipt.chunks -ne 21 -or
       [string]$r87Receipt.manifest_source_commit -cne '27c3bbd2935c8568ee6d260085d8008aec5e173a' -or
       [string]$r87Receipt.manifest_source_sha256 -cne '71395858fcce58500bb42070bf4b248e2ab14613e148e7d74e616c252d6c3332' -or
       [string]$r87Receipt.original_bootstrap_sha256 -cne 'd9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6'){
      throw 'R87_R85_REAL_SOURCE_AND_OWNER_NO_INSTALL_NOT_PROVEN'
    }
    $r87Manifest=Join-Path $env:R87_OFFLINE_STAGE 'manifest.json'
    $r87Boot=Join-Path $env:R87_OFFLINE_STAGE 'bootstrap-verified-locator-copy.ps1'
    if((Get-FileHash -LiteralPath $r87Manifest -Algorithm SHA256).Hash.ToLowerInvariant() -cne
           [string]$r87Receipt.mirror_manifest_sha256 -or
       (Get-FileHash -LiteralPath $r87Boot -Algorithm SHA256).Hash.ToLowerInvariant() -cne
           [string]$r87Receipt.disposable_bootstrap_sha256){
      throw 'R87_PRIVATE_FILE_URI_BOOTSTRAP_OR_MANIFEST_SHA_INVALID'
    }
    $bootText=[IO.File]::ReadAllText($r87Boot,[Text.Encoding]::ASCII)
    if($bootText.Contains('https://raw.githubusercontent.com/') -or
       -not $bootText.Contains("'file:///")){
      throw 'R87_PRIVATE_BOOTSTRAP_STILL_NETWORK_BOUND'
    }
    # The HTTP bootstrap is an isolated fixture derivative; replace only
    # its scratch copy with the R85 protected FILE-URI derivative.
    [IO.File]::WriteAllBytes($bootstrap,[IO.File]::ReadAllBytes($r87Boot))
    $expect.bootstrap_locator_only_copy_sha256=[string]$r87Receipt.disposable_bootstrap_sha256
    Write-Host 'R87_REAL_R85_IMMUTABLE_OFFLINE_MANIFEST_AND_BOOTSTRAP_BOUND=PASS'""",
        "OFFLINE_RECEIPT_BINDING")
    src=once(src,
        "$manifestFile=Join-Path $fixture 'loopback-source/manifest.json'",
        "$manifestFile=Join-Path $env:R87_OFFLINE_STAGE 'manifest.json'",
        "R28_OFFLINE_MANIFEST_SOURCE")
    src=once(src,
        "$mirror=Join-Path $fixture ('loopback-source/sdsssdvx2/spotify-control-updates/"+SOURCE_SHA+"')",
        "$mirror=Join-Path $env:R87_OFFLINE_STAGE ('sdsssdvx2/spotify-control-updates/"+SOURCE_SHA+"')",
        "NEGATIVE_TAMPER_OFFLINE_CHUNK_SOURCE")
    # R82 derives the original exact R28 production driver for the hosted
    # real Git SHA; amend only its test-only *manifest locator* from HTTP
    # to R85 file URI, while keeping all public and approval guards unchanged.
    src=once(src,
        "  $driver=[ScriptBlock]::Create($r28Text)",
        """  $r87Old='$manifestURL=' + [char]39 + 'http://127.0.0.1:' + [char]39 +
    '+([string]$port)+' + [char]39 + '/manifest.json' + [char]39
  $r87New='$manifestURL=[Uri]::new((Join-Path $env:R87_OFFLINE_STAGE ' +
    [char]39 + 'manifest.json' + [char]39 + ')).AbsoluteUri'
  if(([regex]::Matches($r28Text,[regex]::Escape($r87Old))).Count -ne 1){
    throw 'R87_R28_HOSTED_HTTP_MANIFEST_LOCATOR_UNEXPECTED'
  }
  $r28Text=$r28Text.Replace($r87Old,$r87New)
  $driver=[ScriptBlock]::Create($r28Text)""",
        "HOSTED_R28_ONLY_MANIFEST_LOCATOR")
    src=once(src,
        "R82_EXACT_REAL_REVIEW_SHA_INTEGRATED_OWNER_CUTOVER=PASS",
        "R87_REAL_LOCAL_REVIEW_21_CHUNKS_OWNER_CUTOVER=PASS",
        "R82_PROOF_MARKER_TO_R87")
    for phrase in (
      "R28_ONE_OWNER_APPROVAL_THROUGH_BOOTSTRAP_AND_NEW_VBS_COMPLETE_PASS",
      "R28_FINAL_NEW_AGENT_NOT_SINGLE",
      "FUTURE_OFFICIAL_BOOTSTRAP_LOCALHOST_EXACT_ROLLBACK_AND_USER_DATA_PRESERVATION_PASS",
      "HOSTED_CORRUPTED_CHUNK_NOT_SHA_REJECTED",
      "USER_SHORTCUTS_AND_STATE=BYTE_IDENTICAL",
      "OUTER_MAINTENANCE_AND_AGENTTICK_MUTEXES=HELD",
      "HOLD_REASON=OWNER_ONE_SHOT_APPROVAL_REQUIRED",
    ):
        if phrase not in src:
            raise RuntimeError("R87_NATIVE_OWNER_LIFECYCLE_ASSERTION_MISSING_"+phrase)
    # Source is written only into RUNNER_TEMP by the R82 adapter.
    POWER.write_text(src,encoding="utf-8",newline="\n")
    print("R87_R82_PARENT_OWNER_TEST_SHA256="+parent)
    print("R87_NEW_OFFLINE_WSCRIPT_OWNER_TEST_SHA256="+hashlib.sha256(src.encode()).hexdigest())
    print("R87_R28_OWNER_GUARDS_AND_TRUE_BOOTSTRAP_APPLY=REUSED")
    print("R87_REAL_R84_R85_OFFLINE_FILE_URI_NO_HTTP_SERVER=PREPARED")
    print("R87_PRODUCT_R27_R28_OFFICIAL_BOOTSTRAP_AND_PUBLIC_MAIN=UNMODIFIED")

if __name__=="__main__":
    if sys.argv[1:]: raise SystemExit("No args")
    run()
