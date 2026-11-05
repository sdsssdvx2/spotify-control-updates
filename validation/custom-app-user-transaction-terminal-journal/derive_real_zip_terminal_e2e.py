"""Compose the previously Windows-proven real-ZIP/THIRD-signed-permit
journalled rollback test with the new CurrentUser DPAPI retirement adapter.
NEVER change qualified historical fixtures in Git; all derivation is inside
the disposable Actions checkout. No changes to the actual installed app.
"""
from __future__ import annotations
import hashlib, runpy, subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
PARENT=ROOT/'validation/custom-app-production-exclusive-transaction-clock-gate-v0.1.0/derive_exclusive_e2e.py'
PARENT_BLOB='9909e07ea21046df1804ac2bff45d66c66291a9d'
DERIVED=ROOT/'validation/custom-app-production-triple-id-journaled-restart-e2e-v0.1.0/ci_derived_exclusive_gate_restart.ps1'
OUTPUT=HERE/'ci_derived_user_verified_terminal.ps1'
PINS={
    'validation/custom-app-user-transaction-terminal-journal/verified-terminal-adapter.ps1':'8a18de8c49d1c32b1c53ca48518af07aa7a617ad',
    'validation/custom-app-user-transaction-terminal-journal/terminal-readback-child.ps1':'fd5465330d84e874a0b594a66ad1d5fa611273c4',
}
def only(s,old,new,label):
    n=s.count(old)
    if n!=1:raise RuntimeError(f'{label}: anchor count {n} (expected 1)')
    return s.replace(old,new,1)

def derive():
    if subprocess.check_output(['git','hash-object',str(PARENT)],cwd=ROOT,text=True).strip()!=PARENT_BLOB:
        raise RuntimeError('qualified old exclusive real-ZIP fixture generator drift')
    for path,blob in PINS.items():
        if subprocess.check_output(['git','hash-object',path],cwd=ROOT,text=True).strip()!=blob:
            raise RuntimeError('exact terminal adapter/test source pin drift '+path)
    if DERIVED.exists() or OUTPUT.exists():raise RuntimeError('refusing to overwrite derived E2E script')
    parent=runpy.run_path(str(PARENT),run_name='validation-import')
    parent['main']()
    s=DERIVED.read_text('utf-8').replace('\r\n','\n')
    anchor=". (Join-Path $root 'validation/custom-app-production-exclusive-transaction-clock-gate-v0.1.0/custom-app-production-exclusive-transaction-clock-gate.ps1')"
    extra="""\n. (Join-Path $root 'validation/custom-app-user-transaction-store-bundle/user-transaction-store.ps1')
. (Join-Path $root 'validation/custom-app-user-transaction-transition-guard/user-transaction-guard.ps1')
. (Join-Path $root 'validation/custom-app-user-transaction-terminal-journal/verified-terminal-adapter.ps1')"""
    s=only(s,anchor,anchor+extra,'qualified verifier module load')
    mutation="$mutation=Invoke-CustomAppProductionExclusiveThirdIdJournalBridgeV010 -AtomicPreconditionArgs $TIDArgs -JournalStoreDirectory $script:TJRStore -TransactionNonce $script:TJRTxnNonce"
    pre=r"""# Reserve the SAME signed Third-ID and deterministic journal transaction
# BEFORE any atomic live-code mutation; DPAPI/ACL and FileShare.None live under
# the hosted runner, and reservations survive the independent rollback worker.
$script:USERStoreRoot=Join-Path $script:TJRRoot ('user-store-terminal-'+[Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($script:USERStoreRoot)|Out-Null
$plannedTxnRoot=Get-CustomAppProductionJournalAwareAtomicTransactionRootV010 -LivePath $script:TIDLive -TransactionNonce $script:TJRTxnNonce
$expectedIdentity=New-CustomAppProductionCrashJournalIdentityV010 -Name 'tagify' -ConsumptionId ([string]$p.consumption_id) -SourceIdentity ([string]$p.source_identity) -RemoteCommitSha ([string]$p.remote_commit_sha) -StageResultFingerprint ([string]$p.stage_result_fingerprint) -PreparationFingerprint ([string]$p.preparation_fingerprint) -AllowedRoot $script:TJRRoot -LivePath $script:TIDLive -TransactionRoot $plannedTxnRoot -StageWorkspacePath ([string]$p.stage_workspace_path) -AppBackupPath ([string]$p.app_backup_path) -PersistenceBackupPath ([string]$p.persistence_backup_path)
$script:USERExpectedTx=[string]$expectedIdentity.transaction_id
$preSession=Open-CustomAppUserTxnStoreV010 -Name tagify -LivePath $script:TIDLive -HostedCiRoot $script:USERStoreRoot -Initialize
try{
    $reserved=Reserve-CustomAppUserTxnIdV010 -Session $preSession -ConsumptionId ([string]$p.consumption_id) -TransactionId $script:USERExpectedTx -Nonce ([string]$script:TJRTxnNonce).ToLowerInvariant()
    Assert-TJR ([bool]$reserved.ok -and [long]$reserved.revision -eq 1 -and [bool]$reserved.active) 'user transaction not reserved before atomic swap'
}finally{$preSession.lock_handle.Dispose()}
Write-Host 'USER_TERMINAL_SIGNED_ID_RESERVED_BEFORE_REAL_ATOMIC_SWAP_PASS'
"""
    s=only(s,mutation,pre+"\n"+mutation,'pre-mutation DPAPI signed reservation')
    after="Write-Host 'TRIPLE_ID_EXCLUSIVE_REAL_JOURNALED_SWAP_PASS active_claim_persisted=true fresh_hmac_and_current_utc=true recovery_possible=true'"
    mid=r"""
Assert-TJR ([string]$mutation.result.transaction_id -ceq $script:USERExpectedTx) 'predicted pre-mutation journal transaction ID does not match actual written journal'
$early=Open-CustomAppUserTxnStoreV010 -Name tagify -LivePath $script:TIDLive -HostedCiRoot $script:USERStoreRoot
try{
    $earlyDenied=$false
    try{
        $x=Test-CustomAppUserTxnTerminalJournalEvidenceV010 -Session $early -AllowedRoot $script:TJRRoot -JournalStoreDirectory $script:TJRStore -ExpectedConsumptionId ([string]$p.consumption_id) -ExpectedTransactionId $script:USERExpectedTx -LocalAppDataRoot $script:PPBLocal -AppDataRoot $script:PPBRoaming
    }catch{$earlyDenied=$true}
    Assert-TJR $earlyDenied 'non-terminal candidate-live journal incorrectly released reservation'
    Assert-TJR ($null-ne$early.state.active -and [long]$early.state.revision -eq 1) 'non-terminal claim changed after denial'
}finally{$early.lock_handle.Dispose()}
Write-Host 'USER_TERMINAL_UNFINISHED_REAL_JOURNAL_DENIED_PASS'
"""
    s=only(s,after,after+"\n"+mid,'nonterminal denial after real atomic swap')
    terminal="Write-Host 'TRIPLE_ID_EXCLUSIVE_REAL_TERMINAL_RETIREMENT_PASS"
    # Terminal E2E insertion goes before the existing exclusive-gate completion
    # summary, after the independent process restored original Spotify files.
    pos=s.find(terminal)
    if pos < 0 or s.count(terminal)!=1:raise RuntimeError('qualified prior terminal summary anchor drift')
    retire=r"""# Both independent restoration and the qualified exclusive gate have already
# completed. The new store must independently re-read the real terminal
# append-only journal, original preparation evidence and current live bytes.
$USERStoreReopened=Open-CustomAppUserTxnStoreV010 -Name tagify -LivePath $script:TIDLive -HostedCiRoot $script:USERStoreRoot
$USERArgs=@{
    Session=$USERStoreReopened;AllowedRoot=$script:TJRRoot
    JournalStoreDirectory=$script:TJRStore
    ExpectedConsumptionId=[string]$p.consumption_id
    ExpectedTransactionId=$script:USERExpectedTx
    LocalAppDataRoot=$script:PPBLocal;AppDataRoot=$script:PPBRoaming
}
try{
    $wrongId=@{};foreach($k in $USERArgs.Keys){$wrongId[$k]=$USERArgs[$k]}
    $wrongId.ExpectedConsumptionId=('0'*64)
    $blocked=$false;try{[void](Commit-CustomAppUserTxnVerifiedTerminalV011 @wrongId)}catch{$blocked=$true}
    Assert-TJR $blocked 'wrong signed consumption ID retired a DPAPI active claim'
    $wrongTx=@{};foreach($k in $USERArgs.Keys){$wrongTx[$k]=$USERArgs[$k]}
    $wrongTx.ExpectedTransactionId=('0'*64)
    $blocked=$false;try{[void](Commit-CustomAppUserTxnVerifiedTerminalV011 @wrongTx)}catch{$blocked=$true}
    Assert-TJR $blocked 'wrong transaction ID retired a DPAPI active claim'
    $valid=Test-CustomAppUserTxnTerminalJournalEvidenceV010 @USERArgs
    Assert-TJR ([bool]$valid.ok -and [string]$valid.phase -ceq 'rollback-complete' -and [bool]$valid.live_and_spotify_persistence_revalidated) 'qualified complete rollback and real file state not accepted'
    $originalState=(Get-FileHash $USERStoreReopened.paths.state -Algorithm SHA256).Hash
    $failureInjected=$false
    try{[void](Commit-CustomAppUserTxnVerifiedTerminalV011 @USERArgs -HostedCiInterruptBeforeReplace)}catch{
        $failureInjected=([string]$_.Exception.Message -match 'user-terminal-ci-interrupted-before-atomic-ledger-replacement')
    }
    Assert-TJR $failureInjected 'terminal fault injection did not stop before atomic consumed-state replacement'
    Assert-TJR ((Get-FileHash $USERStoreReopened.paths.state -Algorithm SHA256).Hash -ceq $originalState) 'partial retirement mutated canonical DPAPI store'
    Assert-TJR (Test-Path -LiteralPath $USERStoreReopened.paths.pending) 'injected interruption did not persist replace-pending bytes'
}finally{$USERStoreReopened.lock_handle.Dispose()}
$USERStoreReopened=Open-CustomAppUserTxnStoreV010 -Name tagify -LivePath $script:TIDLive -HostedCiRoot $script:USERStoreRoot
try{
    Assert-TJR (-not(Test-Path -LiteralPath $USERStoreReopened.paths.pending) -and [long]$USERStoreReopened.state.revision -eq 1 -and $null-ne$USERStoreReopened.state.active) 'fresh caller did not discard uncommitted terminal pending file'
    $USERArgs.Session=$USERStoreReopened
    $done=Commit-CustomAppUserTxnVerifiedTerminalV011 @USERArgs
    Assert-TJR ([bool]$done.ok -and [bool]$done.active_claim_retired -and [bool]$done.single_use_consumption_durable -and [string]$done.phase -ceq 'rollback-complete') 'real journal evidenced terminal DPAPI retirement failed'
    Assert-TJR ($null-eq$USERStoreReopened.state.active -and @($USERStoreReopened.state.consumed) -ccontains ([string]$p.consumption_id)) 'real terminal retirement did not persist consumed ledger'
    $secondDenied=$false;try{[void](Commit-CustomAppUserTxnVerifiedTerminalV011 @USERArgs)}catch{$secondDenied=$true}
    Assert-TJR $secondDenied 'terminal call unexpectedly removed a consumed ID twice'
}finally{$USERStoreReopened.lock_handle.Dispose()}
$child=Join-Path $root 'validation/custom-app-user-transaction-terminal-journal/terminal-readback-child.ps1'
$childOutput=@(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $child -LivePath $script:TIDLive -HostedCiRoot $script:USERStoreRoot -ExpectedConsumptionId ([string]$p.consumption_id) -ExpectedTransactionId $script:USERExpectedTx)
Assert-TJR ($LASTEXITCODE -eq 0 -and ($childOutput -join ' ') -match 'USER_TERMINAL_FRESH_PROCESS_REPLAY_DENIED_PASS') 'independent process did not recover atomic consumed ledger'
# The independent child is checked above, then its positive proof is surfaced
# to the hosted Windows CI log instead of remaining only in a local variable.
Write-Host ($childOutput -join [Environment]::NewLine)
Write-Host 'USER_TERMINAL_REAL_ZIP_SIGNED_JOURNAL_ROLLBACK_RETIREMENT_PASS false_ids_denied=true nonterminal_denied=true real_live_and_persistence_rechecked=true crash_before_replace_recovered=true consumed_id_durable=true fresh_process_replay_denied=true'
"""
    s=s[:pos]+retire+"\n"+s[pos:]
    OUTPUT.write_text(s,'utf-8',newline='\n')
    print('QUALIFIED_REAL_ZIP_USER_TERMINAL_DERIVATION_OK',len(s),hashlib.sha256(s.encode('utf-8')).hexdigest())

if __name__=='__main__':derive()
