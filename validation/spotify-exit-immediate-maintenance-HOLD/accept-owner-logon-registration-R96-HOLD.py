"""R96 HOLD: native Win32 one-user startup link lifecycle only AFTER exact R94
owner WScript candidate startup. Inject one isolated R96 script into the
existing R94 fixture in RUNNER_TEMP, never modify public main, real registry,
tasks, user's Startup folder, system state or actual owner machine.
"""
from __future__ import annotations
import hashlib
import os
from pathlib import Path
import sys

HERE=Path(__file__).resolve().parent
TEMP=Path(os.environ.get("RUNNER_TEMP","/not-runner")).resolve()
TEST=TEMP/"spotify-r43-integrated-real-owner-cutover.ps1"
R96=HERE/"owner-approved-logon-startup-R96-HOLD.ps1"

def require(x:bool,label:str)->None:
    if not x:raise RuntimeError("R96_HOSTED_"+label)

def run()->None:
    require(os.environ.get("GITHUB_ACTIONS")=="true" and
            os.environ.get("RUNNER_OS")=="Windows" and
            os.environ.get("RUNNER_ENVIRONMENT")=="github-hosted" and
            TEMP.is_dir() and not TEMP.is_symlink(),
            "WINDOWS_GITHUB_HOSTED_ONLY")
    require(TEST.is_file() and R96.is_file(),"EXACT_R94_TEST_AND_R96_PRODUCTION_SCRIPT")
    source=TEST.read_text("utf-8")
    require(source.count("Write-Host 'R94_LOGON_STYLE_FRESH_WSCRIPT_ONE_OWNER_RESIDENT_AND_DATA_PRESERVED=PASS'")==1 and
            "R94_FRESH_AGENT_NEW_WMI_START_SUBSCRIPTION=PASS" in source and
            "R93FreshSnapshot 'ROLLBACK'" in source and
            "R93_MIXED_SCRATCH_INTERRUPTION_REJECTED_AND_CLEANED=PASS" in source,
            "GROUNDED_R94_OWNER_LIFECYCLE_NOT_FOUND")
    content=r"""Write-Host 'R94_LOGON_STYLE_FRESH_WSCRIPT_ONE_OWNER_RESIDENT_AND_DATA_PRESERVED=PASS'
    # R96 operated against the fresh R94 native owner process, but modifies
    # exclusively per-runner scratch Startup folders and app receipt.
    $r96Source=(Resolve-Path 'validation/spotify-exit-immediate-maintenance-HOLD/owner-approved-logon-startup-R96-HOLD.ps1').Path
    $userStartup=Join-Path (Split-Path $app -Parent) 'R96UserStartup'
    $commonStartup=Join-Path (Split-Path $app -Parent) 'R96CommonStartup'
    foreach($d in @($userStartup,$commonStartup)){
      if(Test-Path -LiteralPath $d){throw 'R96_HOSTED_STARTUP_FIXTURE_PREEXISTING'}
      [void][IO.Directory]::CreateDirectory($d)
    }
    $ownedLink=Join-Path $userStartup 'Spotify Control Resident (R96 Managed).lnk'
    $receiptFile=Join-Path $app 'startup-owner-r96.json'
    $startState=Get-FileHash -LiteralPath (Join-Path $app 'state.json') -Algorithm SHA256 -ErrorAction Stop
    $mainBefore=Get-FileHash -LiteralPath $main -Algorithm SHA256
    $agentBefore=Get-FileHash -LiteralPath $agent -Algorithm SHA256
    $addonBefore=Get-FileHash -LiteralPath $addon -Algorithm SHA256
    $txnBefore=Get-FileHash -LiteralPath (Join-Path $app 'self-update-last-transaction.json') -Algorithm SHA256
    function R96Once([string[]]$parms){
      $ret=@(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $r96Source -HostedFixtureRoot $app @parms 2>&1)
      if($LASTEXITCODE -ne 0){throw 'R96_NATIVE_RUNNER_EXITED_NONZERO'}
      return ,$ret
    }
    $plan=R96Once @()
    if($plan -cnotcontains 'RESULT=R96_READONLY_OWNER_LOGON_PLAN' -or
       $plan -cnotcontains 'R96_PLAN=READY_FOR_EXACT_OWNER_APPROVAL_NOT_EXECUTION_PROOF' -or
       (Test-Path -LiteralPath $ownedLink) -or
       (Test-Path -LiteralPath $receiptFile)){
      throw 'R96_FIRST_DEFAULT_PLAN_NOT_INERT_OR_NOT_ADMITTED'
    }
    $denied=R96Once @('-Commit')
    if($denied -cnotcontains 'HOLD_REASON=R96_CREATE_EXPLICIT_APPROVAL_REQUIRED' -or
       $denied -cnotcontains 'RESULT=R96_HOLD_NO_RETRY' -or
       (Test-Path -LiteralPath $ownedLink)){
      throw 'R96_NO_APPROVAL_DID_NOT_BLOCK_PREMUTATION'
    }
    $valid=R96Once @('-Commit','-ApprovalPhrase','APPROVE_EXACT_ONE_OWNER_LOGON_SHORTCUT_ONCE')
    if($valid -cnotcontains 'RESULT=R96_EXPLICIT_OWNER_LOGON_LINK_REGISTERED' -or
       $valid -cnotcontains 'R96_COMMIT_RESULT=ONE_EXACT_USER_STARTUP_LINK_CREATED_NOT_LAUNCHED' -or
       -not(Test-Path -LiteralPath $ownedLink) -or
       -not(Test-Path -LiteralPath $receiptFile)){
      throw ('R96_EXACT_SINGLE_USER_STARTUP_COMMIT_NOT_COMPLETED '+($valid -join ';'))
    }
    $receiptBytes=(Get-FileHash -LiteralPath $receiptFile -Algorithm SHA256).Hash
    $ownedBytes=(Get-FileHash -LiteralPath $ownedLink -Algorithm SHA256).Hash
    $after=R96Once @()
    if($after -cnotcontains 'R96_PLAN=OWNED_EXACT_LOGON_LINK_PRESENT_EXECUTION_UNVERIFIED'){
      throw 'R96_OWNER_LINK_READBACK_NOT_GROUNDED'
    }
    $repeat=R96Once @('-Commit','-ApprovalPhrase','APPROVE_EXACT_ONE_OWNER_LOGON_SHORTCUT_ONCE')
    if($repeat -cnotcontains 'HOLD_REASON=R96_NEVER_OVERWRITE_EXISTING_LINK_OR_RECEIPT' -or
       (Get-FileHash -LiteralPath $ownedLink -Algorithm SHA256).Hash -cne $ownedBytes -or
       (Get-FileHash -LiteralPath $receiptFile -Algorithm SHA256).Hash -cne $receiptBytes){
      throw 'R96_REPEAT_OWNER_APPROVAL_OVERWROTE_OWNED_LINK'
    }
    $removeDenied=R96Once @('-Remove','-ApprovalPhrase','WRONG_OWNER_PHRASE')
    if($removeDenied -cnotcontains 'HOLD_REASON=R96_REMOVE_EXPLICIT_APPROVAL_REQUIRED' -or
       (Get-FileHash -LiteralPath $ownedLink -Algorithm SHA256).Hash -cne $ownedBytes){
      throw 'R96_REMOVE_WITHOUT_EXACT_OWNER_APPROVAL_NOT_DENIED'
    }
    $removed=R96Once @('-Remove','-ApprovalPhrase','APPROVE_REMOVE_ONLY_R96_OWNED_LOGON_SHORTCUT_ONCE')
    if($removed -cnotcontains 'RESULT=R96_EXPLICIT_OWNED_LOGON_LINK_REVOKED' -or
       (Test-Path -LiteralPath $ownedLink) -or
       (Test-Path -LiteralPath $receiptFile)){
      throw ('R96_OWNED_ONLY_REVOKE_NOT_SUCCESS '+($removed -join ';'))
    }
    $again=R96Once @()
    if($again -cnotcontains 'R96_PLAN=READY_FOR_EXACT_OWNER_APPROVAL_NOT_EXECUTION_PROOF'){
      throw 'R96_LOGON_ROUTE_NOT_INERT_AFTER_OWNER_REVOKE'
    }
    foreach($test in @(
      @{path=(Join-Path $app 'state.json');sha=$startState.Hash},
      @{path=$main;sha=$mainBefore.Hash},
      @{path=$agent;sha=$agentBefore.Hash},
      @{path=$addon;sha=$addonBefore.Hash},
      @{path=(Join-Path $app 'self-update-last-transaction.json');sha=$txnBefore.Hash})){
      if((Get-FileHash -LiteralPath $test.path -Algorithm SHA256).Hash -cne $test.sha){
        throw 'R96_OWNER_PROGRAM_OR_USER_STATE_CHANGED'
      }
    }
    Write-Host 'R96_REAL_WIN32_USER_LOGON_LNK_ATOMIC_CREATE_AND_EXACT_REVOKE=PASS'
    Write-Host 'R96_OWNER_APPROVAL_AND_REPEAT_NONOVERWRITE=PASS'
    Write-Host 'R96_SPOTIFY_RESIDENT_JOURNAL_AND_ORIGINAL_USER_STATE_PRESERVED=PASS'
    Write-Host 'R96_HOSTED_ONLY_NO_REAL_LOGON_OR_STARTUP_SETTINGS=YES'
    foreach($d in @($userStartup,$commonStartup)){
      if(@(Get-ChildItem -LiteralPath $d -Force -ErrorAction Stop).Count -ne 0){
        throw 'R96_HOSTED_STARTUP_NOT_EMPTY_AFTER_OWNER_REVOKE'
      }
      [IO.Directory]::Delete($d)
    }"""
    source=source.replace(
        "Write-Host 'R94_LOGON_STYLE_FRESH_WSCRIPT_ONE_OWNER_RESIDENT_AND_DATA_PRESERVED=PASS'",
        content,1)
    require(source.count("R96_REAL_WIN32_USER_LOGON_LNK_ATOMIC_CREATE_AND_EXACT_REVOKE=PASS")==1,
            "NATIVE_R94_INJECTION_NOT_UNIQUE")
    TEST.write_text(source,encoding="utf-8",newline="\n")
    print("R96_R94_NATIVE_OWNER_PARENT_SHA256="+hashlib.sha256(TEST.read_bytes()).hexdigest())
    print("R96_STANDALONE_R96_APPROVAL_CREATE_REVOKE_NATIVE_WIN32=PREPARED")
    print("R96_USER_WINDOWS_REAL_STARTUP_AND_PUBLIC_MAIN=UNTOUCHED")

if __name__=="__main__":
    if sys.argv[1:]:raise SystemExit("No arguments")
    run()
