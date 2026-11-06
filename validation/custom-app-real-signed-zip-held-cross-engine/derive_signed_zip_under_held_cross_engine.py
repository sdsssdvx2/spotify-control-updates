"""Bind the already Windows-proven real THIRD-HMAC signed ZIP journal
transaction to the SAME held cooperative CurrentUser cross-engine lock used
by the generated Addon Manager's normal Update/CommitLast/RollbackLast.

No new/surrogate fake ZIP, no real user machine: a strictly derived hosted
CI script. The common lock is acquired after import, BEFORE any fixture
staging, reservation, atomic swap, independent rollback and terminal
retirement, then released in a PowerShell finally even on failure.
"""
from __future__ import annotations
import hashlib,runpy,subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
OLD=ROOT/'validation/custom-app-missing-live-recovery/derive_actual_signed_zip_missing_live.py'
OLD_BLOB='4733e300f692cc7a741330a9a8fc21328cc7b74d'
PARENT=ROOT/'validation/custom-app-missing-live-recovery/ci_derived_real_zip_missing_live_recovery.ps1'
OUTPUT=HERE/'ci_derived_held_cross_engine_real_signed_zip.ps1'
REQUIRED={
  'validation/custom-app-cooperative-cross-engine-lock/cross-engine-transaction-lock.ps1':'5139a8c9f461b892fbd30d7dfebec97816863844',
  'validation/custom-app-legacy-journal-settlement-barrier/legacy-settlement-barrier.ps1':'ca79b192c99cca29422878caa584075bd39bc845',
  'validation/custom-app-normal-entrypoint-transaction-integration/normal-update-engine-fence.ps1':'5335c610325a4654aaba83749ed5ede500981c7c',
  'validation/custom-app-cooperative-cross-engine-lock/build_candidate.py':'9bb911d3bfd75c283d75970bd06d5ee856c8a5c7',
}
def pin(p,expected):
    actual=subprocess.check_output(['git','hash-object',str(p)],cwd=ROOT,text=True).strip()
    if actual!=expected:raise RuntimeError('qualified signed source drift '+str(p)+' '+actual)
def one(s,before,after,label):
    count=s.count(before)
    if count!=1:raise RuntimeError(label+' expected exactly one qualified anchor, got '+str(count))
    return s.replace(before,after,1)
def main():
    pin(OLD,OLD_BLOB)
    for p,sha in REQUIRED.items():pin(ROOT/p,sha)
    if PARENT.exists() or OUTPUT.exists():
        raise RuntimeError('refuse overwrite of the sealed signed ZIP derivation or held-lock E2E')
    previous=runpy.run_path(str(OLD),run_name='sealed-previous-derivation')
    previous['main']()
    original=PARENT.read_text('utf-8').replace('\r\n','\n')
    s=original
    imports="$root=(Resolve-Path (Join-Path $PSScriptRoot '..\\..')).Path"
    begin=r"""
. (Join-Path $root 'validation/custom-app-user-transaction-store-bundle/user-transaction-store.ps1')
. (Join-Path $root 'validation/custom-app-journal-restart-locator/user-journal-locator.ps1')
. (Join-Path $root 'validation/custom-app-normal-entrypoint-transaction-integration/normal-update-engine-fence.ps1')
. (Join-Path $root 'validation/custom-app-legacy-journal-settlement-barrier/legacy-settlement-barrier.ps1')
. (Join-Path $root 'validation/custom-app-cooperative-cross-engine-lock/cross-engine-transaction-lock.ps1')
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted'){
    throw 'CROSS_ENGINE_SIGNED_REAL_ZIP_E2E_NOT_HOSTED'
}
$script:RealZipCrossLock=Open-CustomAppCrossEngineTransactionLockV010
try{
    [void](Assert-CustomAppCrossEngineTransactionLockHeldV010 -Session $script:RealZipCrossLock)
    $initialLegacy=Assert-CustomAppNewJournalLegacyLedgerClosedV011
    if(-not[bool]$initialLegacy.ok -or [bool]$initialLegacy.safe_to_enroll -or
       -not[bool]$initialLegacy.requires_cross_engine_lock_before_enrollment){
        throw 'CROSS_ENGINE_SIGNED_ZIP_BEFORE_STAGING_LEGACY_CHECK_FAIL_CLOSED'
    }
    Write-Host 'CROSS_ENGINE_SIGNED_ZIP_LOCK_BEFORE_STAGING_PASS'
"""
    s=one(s,imports,imports+'\n'+begin.strip('\n'),'load cooperative lock before executable historical fixture setup and real ZIP staging')
    marker="Write-Host 'MISSING_LIVE_REAL_SIGNED_ZIP_ATOMIC_CRASH_WINDOW_RECOVERY_PASS real_zip_swapped=true immutable_locator_reopened=true old_opener_denied=true exclusive_lock=true no_auto_restore=true'"
    test=r"""
# This is AFTER the actual HMAC-signed THIRD permit's real ZIP swap,
# while the qualified DPAPI active reservation remains durable.
[void](Assert-CustomAppCrossEngineTransactionLockHeldV010 -Session $script:RealZipCrossLock)
$heldProbeDenied=$false
try{
    $probe=Open-CustomAppNewJournalCrossEnginePreflightV010
    if($null-ne$probe -and $null-ne$probe.session){$probe.session.lock_handle.Dispose()}
}catch{
    $heldProbeDenied=([string]$_.Exception.Message -match 'cross-engine-lock-busy-or-unavailable')
}
Assert-TJR $heldProbeDenied 'second new journal entry bypassed an existing cross engine transaction'
$actualAddon=Join-Path $root 'validation/custom-app-cooperative-cross-engine-lock/out/bin/addon-manager.ps1'
Assert-TJR ([IO.File]::Exists($actualAddon)) 'qualified real generated Addon Manager candidate is absent'
$legacyErr=Join-Path $env:LOCALAPPDATA 'SpotifyControl\logs\addons-error.log'
foreach($legacyAction in @('Update','CommitLast','RollbackLast')){
    $oldResult=@(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $actualAddon -Action $legacyAction -Force)
    Assert-TJR ($LASTEXITCODE -ne 0) ('actual legacy '+$legacyAction+' ran while signed ZIP journal lock held')
    Assert-TJR ([IO.File]::Exists($legacyErr) -and
        [IO.File]::ReadAllText($legacyErr).Contains('cross-engine-lock-busy-or-unavailable')) (
         'actual '+$legacyAction+' did not fail at the cooperative cross-engine boundary')
    [void](Assert-CustomAppCrossEngineTransactionLockHeldV010 -Session $script:RealZipCrossLock)
    Write-Host ('CROSS_ENGINE_SIGNED_ZIP_ACTUAL_LEGACY_ACTION_DENIED_PASS action='+$legacyAction)
}
Write-Host 'CROSS_ENGINE_THIRD_SIGNED_ZIP_SWAPPED_WITH_GLOBAL_LOCK_PASS active_signed_reservation=true normal_actions_blocked=true'
"""
    s=one(s,marker,marker+'\n'+test.strip('\n'),'probe real old actions while signed new journal ZIP is active')
    final="Write-Host 'TRIPLE_ID_EXCLUSIVE_REAL_ZIP_END_TO_END_PASS third_hmac_real_zip=true current_utc=true active_claim_before_swap=true independent_process_old_code_restore=true terminal_lock_retirement=true replay_denied=true production_disabled=true'"
    release=r"""
[void](Assert-CustomAppCrossEngineTransactionLockHeldV010 -Session $script:RealZipCrossLock)
Write-Host 'CROSS_ENGINE_SIGNED_ZIP_HELD_THROUGH_VERIFIED_TERMINAL_PASS'
}finally{
    if($null -ne $script:RealZipCrossLock -and $null -ne $script:RealZipCrossLock.lock_handle){
        $script:RealZipCrossLock.lock_handle.Dispose()
    }
}
$after=Open-CustomAppCrossEngineTransactionLockV010
try{
    Assert-TJR ([bool]$after.ok -and
       [bool](Assert-CustomAppCrossEngineTransactionLockHeldV010 -Session $after)) 'cross-engine lock unrecoverable after new terminal retirement'
}finally{$after.lock_handle.Dispose()}
Write-Host 'CROSS_ENGINE_SIGNED_REAL_ZIP_FULL_LIFECYCLE_PASS actual_third_hmac_zip=true legacy_mutations_denied_during_swap=true independent_recovery=true durable_id_retired=true lock_released=true'
"""
    s=one(s,final,final+'\n'+release.strip('\n'),'release common lock after real signed ZIP independent terminal retirement')
    mandatory=[
        'USER_JOURNAL_REAL_SIGNED_THIRD_ID_PRE_SWAP_LOCATOR_BOUND_PASS',
        'MISSING_LIVE_REAL_SIGNED_ZIP_ATOMIC_CRASH_WINDOW_RECOVERY_PASS',
        'USER_JOURNAL_SIGNED_ZIP_BOUND_RESTART_TERMINAL_PASS',
        'USER_TERMINAL_FRESH_PROCESS_REPLAY_DENIED_PASS',
        'TRIPLE_ID_EXCLUSIVE_REAL_ZIP_END_TO_END_PASS',
    ]
    for mark in mandatory:
        if s.count(mark)!=1:raise RuntimeError('historical signed and independent recovery proof lost '+mark)
    if s.count('CROSS_ENGINE_SIGNED_REAL_ZIP_FULL_LIFECYCLE_PASS')!=1:
        raise RuntimeError('global lock positive terminal marker count invalid')
    if len(s)<=len(original):raise RuntimeError('signed ZIP unchanged')
    OUTPUT.write_text(s,'utf-8',newline='\n')
    print('CROSS_ENGINE_REAL_THIRD_HMAC_ZIP_LOCKED_LIFECYCLE_DERIVED_PASS',
          len(s),hashlib.sha256(s.encode('utf-8')).hexdigest())
if __name__=='__main__':main()
