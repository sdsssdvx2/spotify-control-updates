"""Recreate the SHA-pinned real signed THIRD-HMAC ZIP and advance the
qualified cooperative lock contract to a true *process death/restart*:
parent lock released after real swap, separate recovery worker acquires
SAME lock for exact original restore/apply, proves legacy actions cannot
enter mid-recovery, releases, then parent reacquires before durable terminal
receipt and Triple-ID consumption. Validation only; fullchain disabled.
"""
from __future__ import annotations
import hashlib,runpy,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
PARENT=ROOT/'validation/custom-app-real-signed-zip-held-cross-engine/derive_signed_zip_under_held_cross_engine.py'
PARENT_BLOB='c6815fb996db2a51722fe9bbeb2596a1d4fff1b4'
PRIOR_OUTPUT=ROOT/'validation/custom-app-real-signed-zip-held-cross-engine/ci_derived_held_cross_engine_real_signed_zip.ps1'
OUT=HERE/'ci_signed_zip_fresh_worker_lock_handoff.ps1'
PINS={
 'validation/custom-app-fresh-worker-lock-handoff/locked-recovery-worker.ps1':'6132883db80d555238ca6f7f07e2a69c4eadbebf',
 'validation/custom-app-production-evidence-bound-recovery-restart-v0.1.0/invoke_custom_app_production_evidence_bound_recovery_restart_worker.ps1':'9c039860ff0645153205691a11e89d8eb844d43c',
 'validation/custom-app-cooperative-cross-engine-lock/cross-engine-transaction-lock.ps1':'5139a8c9f461b892fbd30d7dfebec97816863844',
}
def pin(path,sha):
    actual=subprocess.check_output(['git','hash-object',str(path)],cwd=ROOT,text=True).strip()
    if actual!=sha:raise RuntimeError('previous validated E2E pin drift '+str(path)+' got '+actual)
def one(s,old,new,label):
    count=s.count(old)
    if count!=1:raise RuntimeError(f'{label}: expected unique anchor, got {count}')
    return s.replace(old,new,1)
def main():
    pin(PARENT,PARENT_BLOB)
    for p,v in PINS.items():pin(ROOT/p,v)
    if PRIOR_OUTPUT.exists() or OUT.exists():
        raise RuntimeError('refuse to overwrite prior immutable E2E fixture')
    previous=runpy.run_path(str(PARENT),run_name='qualified-restart-parent-derivation')
    previous['main']()
    old=PRIOR_OUTPUT.read_text('utf-8').replace('\r\n','\n')
    s=old
    oldworker="$worker=Join-Path $root 'validation/custom-app-production-evidence-bound-recovery-restart-v0.1.0/invoke_custom_app_production_evidence_bound_recovery_restart_worker.ps1'"
    handoff=r"""
# Real ZIP swap was executed under the parent cross-engine lock. The original
# old worker has NO global lock: this test deliberately does not call it as
# an unguarded fresh process. Instead test the new locked worker admission.
$qualifiedWorker=Join-Path $root 'validation/custom-app-production-evidence-bound-recovery-restart-v0.1.0/invoke_custom_app_production_evidence_bound_recovery_restart_worker.ps1'
Assert-TJR ([IO.File]::Exists($qualifiedWorker)) 'qualified original recovery worker source missing'
$worker=Join-Path $root 'validation/custom-app-fresh-worker-lock-handoff/locked-recovery-worker.ps1'
Assert-TJR ([IO.File]::Exists($worker)) 'cross-engine guarded fresh restart worker source missing'
[void](Assert-CustomAppCrossEngineTransactionLockHeldV010 -Session $script:RealZipCrossLock)
# Prove a second recovery worker cannot begin while the original process
# still holds the transaction-wide lock. It must fail *at the lock*, before
# state deserialization or any journal read.
$previousPreference=$ErrorActionPreference
try{
    $ErrorActionPreference='Continue'
    $blockedOutput=@(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $worker -ProbeOnly 2>&1)
    $blockedExit=$LASTEXITCODE
}finally{$ErrorActionPreference=$previousPreference}
Assert-TJR ($blockedExit -ne 0 -and ($blockedOutput -join ' ') -match 'cross-engine-lock-busy-or-unavailable') 'fresh recovery worker bypassed parent lock'
Write-Host 'FRESH_RECOVERY_WORKER_PARENT_LOCK_CONTENTION_DENIED_PASS'
# Model the existing journal-enrollment presence in the ACTUAL hosted
# CurrentUser profile, not only in a HostedCiRoot test override. This keeps
# legacy Update/CommitLast/RollbackLast blocked during the inevitable lock
# transfer interval, even before the fresh recovery process obtains it.
$script:RecoveryEnrollment=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'SpotifyControlUpdates-CustomApp-State'
if([IO.Directory]::Exists($script:RecoveryEnrollment) -or
   [IO.File]::Exists($script:RecoveryEnrollment) -or
   (Test-Path -LiteralPath $script:RecoveryEnrollment -ErrorAction SilentlyContinue)){
    throw 'fresh-recovery-would-overwrite-existing-hosted-enrollment'
}
[IO.Directory]::CreateDirectory($script:RecoveryEnrollment)|Out-Null
$script:RecoveryEnrollmentCreated=$true
$script:RealZipCrossLock.lock_handle.Dispose()
$script:RealZipCrossLock=$null
$handoffFailClosed=$true
$handoffErr=Join-Path $env:LOCALAPPDATA 'SpotifyControl\logs\addons-error.log'
foreach($a in @('Update','CommitLast','RollbackLast')){
    $beforeBytes=if([IO.File]::Exists($handoffErr)){[IO.File]::ReadAllBytes($handoffErr).Length}else{0}
    $legacyResult=@(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $actualAddon -Action $a -Force)
    Assert-TJR ($LASTEXITCODE -ne 0 -and [IO.File]::Exists($handoffErr)) ('legacy '+$a+' ran during crash lock handoff')
    $nowText=[IO.File]::ReadAllText($handoffErr)
    Assert-TJR ($nowText.Length -gt 0 -and
      $nowText.Contains('normal-update-engine-gate-dpapi-enrollment-present-requires-journal-recovery-or-migration')) (
         'legacy '+$a+' did not deny on persistent new-engine enrollment during unlocked handoff')
}
Write-Host 'FRESH_RECOVERY_UNLOCKED_HANDOFF_LEGACY_PRESENCE_GATE_PASS'
"""
    s=one(s,oldworker,handoff.strip('\n'),'replace only the worker call site with real restart lock handoff')
    oldchild="""$childOutput=@(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $worker -StatePath $statePath -ResultPath $resultPath 2>&1)
$childExit=$LASTEXITCODE"""
    newchild=r"""# Real child process must lock BEFORE touching any journal or original app
# files. A deterministic hosted handshake proves lock ownership during the
# exact transaction the old worker restores (not just a preflight stub).
$ready=Join-Path $control 'fresh-worker-locked.ready'
$release=Join-Path $control 'fresh-worker-start-recovery.ack'
$childJob=Start-Job -ScriptBlock {
    param($wrapper,$st,$out,$rdy,$ack)
    $ErrorActionPreference='Continue'
    $lines=@(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $wrapper -StatePath $st -ResultPath $out -LockReadyPath $rdy -LockReleasePath $ack 2>&1)
    [pscustomobject]@{
        exit_code=[int]$LASTEXITCODE
        output=@($lines|ForEach-Object{[string]$_})
    }
} -ArgumentList $worker,$statePath,$resultPath,$ready,$release
$ackWritten=$false
try{
    $deadline=[DateTimeOffset]::UtcNow.AddSeconds(55)
    while(-not[IO.File]::Exists($ready)){
        if([DateTimeOffset]::UtcNow -gt $deadline -or
           $childJob.State -in @('Failed','Completed','Stopped')){
            throw ('fresh recovery worker did not acquire shared lock: '+[string]$childJob.State)
        }
        Start-Sleep -Milliseconds 120
    }
    Assert-TJR ([IO.File]::ReadAllText($ready).Trim() -ceq 'LOCK_HELD') 'worker ready marker did not confirm held lock'
    $blockedByWorker=$false
    try{
        $contender=Open-CustomAppCrossEngineTransactionLockV010
        $contender.lock_handle.Dispose()
    }catch{$blockedByWorker=([string]$_.Exception.Message -match 'cross-engine-lock-busy-or-unavailable')}
    Assert-TJR $blockedByWorker 'fresh child did not own shared lock in parent'
    foreach($a in @('Update','CommitLast','RollbackLast')){
        $legacyResult=@(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $actualAddon -Action $a -Force)
        Assert-TJR ($LASTEXITCODE -ne 0 -and
            [IO.File]::ReadAllText($legacyErr).Contains('cross-engine-lock-busy-or-unavailable')) (
            'actual legacy '+$a+' entered while fresh recovery child owned lock')
        Write-Host ('FRESH_RECOVERY_CHILD_HELD_LOCK_LEGACY_DENIED_PASS action='+$a)
    }
    [IO.File]::WriteAllText($release,'RELEASE_TO_RECOVER',[Text.UTF8Encoding]::new($false))
    $ackWritten=$true
}finally{
    if(-not$ackWritten -and -not[IO.File]::Exists($release)){
        [IO.File]::WriteAllText($release,'FAIL_CLOSED_AFTER_TEST_ASSERTION',[Text.UTF8Encoding]::new($false))
    }
}
$completed=Wait-Job -Job $childJob -Timeout 240
Assert-TJR ($null-ne$completed -and $childJob.State -ceq 'Completed') 'fresh recovery child background execution incomplete'
$jobItems=@(Receive-Job -Job $childJob -ErrorAction Stop)
Assert-TJR ($jobItems.Count -eq 1) 'fresh recovery job output count invalid'
$childExit=[int]$jobItems[0].exit_code
$childOutput=@($jobItems[0].output)
Remove-Job -Job $childJob -Force
Assert-TJR (($childOutput -join ' ') -match 'RECOVERY_CHILD_SHARED_LOCK_HELD_THROUGH_HANDSHAKE_PASS' -and
    ($childOutput -join ' ') -match 'RECOVERY_CHILD_ORIGINAL_WORKER_EXECUTED_UNDER_SHARED_LOCK_PASS') (
    'fresh process recovery worker failed to hold exclusive lock for original exact restore and fake apply')
Write-Host 'FRESH_RECOVERY_REAL_INDEPENDENT_WORKER_LOCKED_APPLY_PASS'"""
    s=one(s,oldchild,newchild,'real independent good recovery worker async handshake')
    oldterminal="Write-Host 'TRIPLE_ID_JOURNALED_RESTART_E2E_PASS cases=7 real_zip=true third_permit_revalidated=true durable_single_use_consumption=true recovery_evidence_before_first_mutation=true journal_candidate_live=true separate_process=true resume_admission=true rollback_required_and_complete_durable=true exact_app_git_spotify_settings_restored=true fake_old_apply_count=1 wrong_identity_and_replay_denied=true no_session_key_persisted=true installed_spotify_untouched=true'"
    reacquire=r"""
# Both the wrong-ID and replay children have finished and released the global
# lock. The terminal DPAPI/append-only receipt mutation belongs to a NEW
# owner with a fresh locked session; never reuse a stale parent handle.
$script:RealZipCrossLock=Open-CustomAppCrossEngineTransactionLockV010
[void](Assert-CustomAppCrossEngineTransactionLockHeldV010 -Session $script:RealZipCrossLock)
Write-Host 'FRESH_RECOVERY_TERMINAL_PARENT_LOCK_REACQUIRED_PASS'
"""
    s=one(s,oldterminal,oldterminal+'\n'+reacquire.strip('\n'),'terminal handoff after independent restoration and replay denial')
    oldfinally="""        $script:RealZipCrossLock.lock_handle.Dispose()
    }
}"""
    newfinally="""        $script:RealZipCrossLock.lock_handle.Dispose()
    }
    if($script:RecoveryEnrollmentCreated -and
       [IO.Directory]::Exists([string]$script:RecoveryEnrollment)){
        [IO.Directory]::Delete([string]$script:RecoveryEnrollment,$false)
    }
}"""
    s=one(s,oldfinally,newfinally,'hosted marker cleanup only in outer finally')
    end="Write-Host 'CROSS_ENGINE_SIGNED_REAL_ZIP_FULL_LIFECYCLE_PASS actual_third_hmac_zip=true legacy_mutations_denied_during_swap=true independent_recovery=true durable_id_retired=true lock_released=true'"
    s=one(s,end,end+"\nWrite-Host 'FRESH_WORKER_REAL_SIGNED_ZIP_HANDOFF_END_TO_END_PASS parent_lock_released=true child_lock_reacquired=true original_recovery_worker_protected=true independent_rollback=true durable_terminal_claim_reacquired=true old_engine_denied=true permanent_replay_denied=true'",'new complete proof')
    for mark in (
       'TRIPLE_ID_EXCLUSIVE_REAL_ZIP_END_TO_END_PASS',
       'CROSS_ENGINE_SIGNED_REAL_ZIP_FULL_LIFECYCLE_PASS',
       'MISSING_LIVE_REAL_SIGNED_ZIP_ATOMIC_CRASH_WINDOW_RECOVERY_PASS',
       'FRESH_RECOVERY_REAL_INDEPENDENT_WORKER_LOCKED_APPLY_PASS',
       'FRESH_WORKER_REAL_SIGNED_ZIP_HANDOFF_END_TO_END_PASS',
    ):
        if s.count(mark)!=1:raise RuntimeError('missing unique original or new real signed ZIP milestone '+mark)
    if old==s:raise RuntimeError('no new protected restart worker')
    OUT.write_text(s,'utf-8',newline='\n')
    print('FRESH_WORKER_LOCKED_REAL_SIGNED_ZIP_DERIVED_PASS',len(s),hashlib.sha256(s.encode('utf-8')).hexdigest())
if __name__=='__main__':main()
