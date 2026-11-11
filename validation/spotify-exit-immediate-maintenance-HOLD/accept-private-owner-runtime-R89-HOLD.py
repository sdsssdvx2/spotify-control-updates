"""R89 HOLD: exercise the ACTUAL production-target R88 PowerShell source
with genuine pinned R84/R85 private source, isolated Win32 WScript resident,
real R27 neutral-CWD handoff and official Bootstrap transactional rollback.

R87 existing Windows fixture creates scratch sources and full owner process
lifecycle. Only the ephemeral generated native test is adapted. No production
R28/R27/R88 source change, live owner PC mutation or GitHub main publication.
"""
from __future__ import annotations
import hashlib
import os
from pathlib import Path
import re
import sys

HERE=Path(__file__).resolve().parent
SCRATCH=Path(os.environ.get("RUNNER_TEMP","/not-runner")).resolve()
TEST=SCRATCH/"spotify-r43-integrated-real-owner-cutover.ps1"
R88=HERE/"owner-approved-private-offline-R88-HOLD.ps1"

def require(condition, why):
    if not condition: raise RuntimeError("R89_"+why)

def one(s:str,old:str,new:str,tag:str)->str:
    require(s.count(old)==1,"NATIVE_R87_ANCHOR_"+tag)
    return s.replace(old,new,1)

def main():
    require(os.environ.get("GITHUB_ACTIONS")=="true" and
            os.environ.get("RUNNER_OS")=="Windows" and
            os.environ.get("RUNNER_ENVIRONMENT")=="github-hosted" and
            SCRATCH.is_dir() and not SCRATCH.is_symlink(),
            "GITHUB_HOSTED_WINDOWS_ONLY")
    require(TEST.is_file() and R88.is_file(), "SOURCE_AND_R87_DRIVER_NOT_READY")
    src=TEST.read_text("utf-8")
    original=hashlib.sha256(src.encode("utf-8")).hexdigest()
    require("R87_REAL_R85_IMMUTABLE_OFFLINE_MANIFEST_AND_BOOTSTRAP_BOUND=PASS" in src,
            "GENUINE_REAL_SOURCE_R87_NOT_BOUND")
    # All real owner process creation, exact owner+PID checks, 2 outer mutexes,
    # shortcut preservation, rollback and corrupt chunk rejection remain.
    src=one(src,"  $driver=[ScriptBlock]::Create($r28Text)",
      """  $r88Bytes=[IO.File]::ReadAllBytes((Resolve-Path 'validation/spotify-exit-immediate-maintenance-HOLD/owner-approved-private-offline-R88-HOLD.ps1'))
  $r88Text=[Text.Encoding]::UTF8.GetString($r88Bytes)
  $driver=[ScriptBlock]::Create($r88Text)
  Write-Host 'R89_NATIVE_PRODUCTION_CANDIDATE_R88_DRIVER_ACTUALLY_SELECTED=PASS'""",
      "REAL_R88_DRIVER")
    import re
    pattern=r"(?m)^(?P<pad>[ \t]*)\$r28Args=@\{\n(?:[ \t]+[A-Za-z][^\n]*\n){7}(?P=pad)\}"
    matches=list(re.finditer(pattern,src))
    require(len(matches)==1,"NATIVE_R87_ARGS_BLOCK_NOT_UNIQUE")
    indent=matches[0].group("pad")
    src=src[:matches[0].start()]+(
        indent+"$r28Args=@{\n"+
        indent+"  PrivateOfflineReadyPath=$env:R87_OFFLINE_STAGE\n"+
        indent+"  HostedFixtureRoot=$fixture\n"+
        indent+"}")+src[matches[0].end():]

    src=one(src,
      "$publicNoPhrase=@(& $driver -PinnedR27Source $r27Bytes -Commit -ApprovedPublicManifestSHA256 ('0'*64) -ApprovedPublicSourceCommit ('1'*40))",
      "$publicNoPhrase=@(& $driver @r28Args -Commit)",
      "NO_APPROVAL_GATE")
    src=one(src,
      "$unpublished=@(& $driver -PinnedR27Source $r27Bytes -Commit -ApprovalPhrase 'APPROVE_EXACT_OWNER_CUTOVER_AND_ONE_STABLE_UPDATE')",
      "$unpublished=@(& $driver @r28Args -Commit -ApprovalPhrase 'PUBLIC_UNAPPROVED_PHRASE_MUST_BE_REJECTED')",
      "BAD_PUBLIC_APPROVAL_PHRASE")
    src=one(src,
      "$unpublished -cnotcontains 'HOLD_REASON=PUBLIC_RELEASE_INDEPENDENT_PINS_REQUIRED'",
      "$unpublished -cnotcontains 'HOLD_REASON=OWNER_ONE_SHOT_APPROVAL_REQUIRED'",
      "NO_FAKE_PUBLIC_RELEASE_REASON")
    src=one(src,
      "$tamperedArgs.PinnedReleaseFactsJson=($wrongReleaseFacts | ConvertTo-Json -Compress)",
      "$tamperedArgs.PrivateOfflineReadyPath=Join-Path $env:R87_OFFLINE_STAGE 'unexpected-nonprivate-child'",
      "TAMPERED_PRIVATE_SOURCE_PATH")
    src=one(src,
      "$notAdmitted=@(& $driver @tamperedArgs -Commit -ApprovalPhrase 'APPROVE_EXACT_OWNER_CUTOVER_AND_ONE_STABLE_UPDATE')",
      "$notAdmitted=@(& $driver @tamperedArgs -Commit -ApprovalPhrase 'APPROVE_EXACT_PRIVATE_V0630_OWNER_CUTOVER_ONCE')",
      "TAMPER_DENIAL_WITH_REAL_APPROVAL")
    src=one(src,
      "$notAdmitted -cnotcontains 'HOLD_REASON=RELEASE_SOURCE_FACTS_NOT_BOUND_TO_MANIFEST_AND_PAYLOAD'",
      "$notAdmitted -cnotcontains 'RESULT=HOLD_NO_AUTOMATIC_RETRY'",
      "INVALID_PRIVATE_ROOT_BLOCKED")
    src=one(src,
      "RESULT=READY_FOR_ONE_SHOT_APPROVED_STABLE_NO_MUTATION",
      "RESULT=READY_FOR_PRIVATE_OFFLINE_ONESHOT_NO_MUTATION",
      "READONLY_REAL_R88_PLAN")
    src=one(src,
      "$receipt=@(& $driver @r28Args -Commit -ApprovalPhrase 'APPROVE_EXACT_OWNER_CUTOVER_AND_ONE_STABLE_UPDATE')",
      "$receipt=@(& $driver @r28Args -Commit -ApprovalPhrase 'APPROVE_EXACT_PRIVATE_V0630_OWNER_CUTOVER_ONCE')",
      "REAL_R88_OWNER_APPROVAL")
    src=one(src,
      "RESULT=HOSTED_FUTURE_STABLE_ONESHOT_COMMITTED",
      "RESULT=HOSTED_PRIVATE_OFFLINE_ONESHOT_COMMITTED",
      "COMMIT_RECEIPT_ACTUAL_R88")
    src=one(src,
      "R30_RELEASE_SOURCE_FACTS=EXACT_HOSTED_UNPUBLISHED_ONLY",
      "R88_PRIVATE_SOURCE=EXACT_PINNED_NOT_PUBLISHED_AND_NOT_INSTALL_AUTHORITY",
      "PRIVATE_NOT_PUBLIC_SOURCE_RECEIPT")
    src=one(src,
      "USER_SHORTCUTS_AND_STATE=BYTE_IDENTICAL",
      "USER_SHORTCUTS_AND_STATE=BYTE_IDENTICAL",
      "EXACT_USER_PRESERVE_UNCHANGED") if False else src
    # Require the R88-specific receipt proving exact installed official
    # Bootstrap stayed original while the private script applied the patch.
    src=one(src,
      "$receipt -cnotcontains 'OFFICIAL_POSTCHECK=PASS' -or",
      "$receipt -cnotcontains 'OFFICIAL_POSTCHECK=PASS' -or\n         $receipt -cnotcontains 'R88_OFFICIAL_INSTALLED_BOOTSTRAP=UNCHANGED_PINNED' -or",
      "REAL_PRIVATE_BOOTSTRAP_NOT_INSTALLED")
    src=one(src,
      "$repeat=@(& $driver @r28Args -Commit -ApprovalPhrase 'APPROVE_EXACT_OWNER_CUTOVER_AND_ONE_STABLE_UPDATE')",
      "$repeat=@(& $driver @r28Args -Commit -ApprovalPhrase 'APPROVE_EXACT_PRIVATE_V0630_OWNER_CUTOVER_ONCE')",
      "REPEAT_AFTER_COMMIT_FAIL_CLOSED")
    # Prevent R28's now-obsolete "installed Bootstrap SHA" check from being
    # lost after the real private R88 controller returns. Original Bootstrap
    # must remain immutable until AFTER the separate explicit rollback too.
    src=one(src,
      "Write-Host 'R28_ONE_OWNER_APPROVAL_THROUGH_BOOTSTRAP_AND_NEW_VBS_COMPLETE_PASS'",
      """if((Get-FileHash -LiteralPath (Join-Path $app 'bootstrap/spotify-control-self-updater.ps1') -Algorithm SHA256).Hash.ToLowerInvariant() -cne
         'd9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6'){
      throw 'R89_REAL_R88_INSTALLED_ORIGINAL_BOOTSTRAP_CHANGED_POST_CUTOVER'
    }
    Write-Host 'R89_ACTUAL_R88_OWNER_CUTOVER_PRESERVED_OFFICIAL_BOOTSTRAP=PASS'
    Write-Host 'R28_ONE_OWNER_APPROVAL_THROUGH_BOOTSTRAP_AND_NEW_VBS_COMPLETE_PASS'""",
      "AFTER_PRIVATE_OWNER_CUTOVER")
    src=one(src,
      "R87_REAL_LOCAL_REVIEW_21_CHUNKS_OWNER_CUTOVER=PASS",
      "R89_REAL_R88_NATIVE_WIN32_OWNER_PRIVATE_OFFLINE_CUTOVER=PASS",
      "REAL_R88_RESULT_MARKER")
    require("R87_NO_HTTP_SERVER_OFFLINE_FILE_URI_ONLY=PASS" in src and
            "FUTURE_OFFICIAL_BOOTSTRAP_CORRUPT_CHUNK_REJECTED_ORIGINAL_AND_OWNER_DATA_UNCHANGED_PASS" in src and
            "R28_FINAL_NEW_AGENT_NOT_SINGLE" in src,
            "OWNER_R28_ROLLBACK_REGRESSION_SOURCE_LOST")
    # The original hosted pre-existing test is deliberately not a user installer.
    TEST.write_text(src,encoding="utf-8",newline="\n")
    print("R89_R87_ORIGINAL_NATIVE_OWNER_DRIVER_SHA256="+original)
    print("R89_REAL_R88_PRODUCTION_CANDIDATE_SHA256="+hashlib.sha256(R88.read_bytes()).hexdigest())
    print("R89_R88_NATIVE_OWNER_WSCRIPT_BOOTSTRAP_AND_ROLLBACK=PREPARED")
    print("R89_LIVE_OWNER_PC_AND_PUBLIC_RELEASE=UNCHANGED")

if __name__=="__main__":
    if sys.argv[1:]: raise SystemExit("no arguments")
    main()
