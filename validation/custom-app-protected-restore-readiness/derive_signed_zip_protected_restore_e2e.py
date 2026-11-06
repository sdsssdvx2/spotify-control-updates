"""Derive qualified real THIRD-HMAC signed ZIP + independently locked
rollback from PR234 without changing any historical fixture. Inject the
new no-create evidence reader and exact historical restore admission
under hosted CurrentUser DPAPI source and same cross-engine locks.
"""
from pathlib import Path
import hashlib,runpy,subprocess
ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
PARENT=ROOT/'validation/custom-app-startup-recovery-source/derive_signed_zip_source_e2e.py'
PARENT_BLOB='674b231c759be850bb9fe72188d1babf99605a7a'
PARENT_SCRIPT=ROOT/'validation/custom-app-startup-recovery-source/ci_signed_zip_sealed_startup_source.ps1'
OUT=HERE/'ci_signed_zip_protected_restore_readiness.ps1'
MODULE=HERE/'protected-restore-readiness.ps1'
MODULE_BLOB='4578d92f7e751222b939c88011801d8d7930f60a'
def pin(p,sha):
    actual=subprocess.check_output(['git','hash-object',str(p)],cwd=ROOT,text=True).strip()
    if actual!=sha:raise RuntimeError('protected signed ZIP parent immutable pin drift '+str(p))
def one(s,a,b,label):
    c=s.count(a)
    if c!=1:raise RuntimeError(f'{label} must match one exact historical boundary; got {c}')
    return s.replace(a,b,1)
def main():
    pin(PARENT,PARENT_BLOB);pin(MODULE,MODULE_BLOB)
    pin(ROOT/'validation/custom-app-production-recovery-cleanup-resume-admission-v0.1.0/custom-app-production-recovery-cleanup-resume-admission.ps1', '387d97b10d493b3794b24fba2bac67cf39491444')
    if PARENT_SCRIPT.exists() or OUT.exists():
        raise RuntimeError('protected real signed ZIP derivation will not overwrite original')
    ns=runpy.run_path(str(PARENT),run_name='qualified-readonly-source-derivation')
    ns['main']()
    s=PARENT_SCRIPT.read_text('utf-8').replace('\r\n','\n')
    load=". (Join-Path $root 'validation/custom-app-production-recovery-plan-contract-v0.1.0/custom-app-production-recovery-plan.ps1')"
    imports="""
. (Join-Path $root 'validation/custom-app-production-recovery-evidence-envelope-v0.1.0/custom-app-production-recovery-evidence.ps1')
. (Join-Path $root 'validation/custom-app-production-recovery-cleanup-resume-admission-v0.1.0/custom-app-production-recovery-cleanup-resume-admission.ps1')
. (Join-Path $root 'validation/custom-app-production-recovery-restore-resume-admission-v0.1.0/custom-app-production-recovery-restore-resume-admission.ps1')
. (Join-Path $root 'validation/custom-app-protected-restore-readiness/protected-restore-readiness.ps1')"""
    s=one(s,load,load+imports,'historical pure plan and signed evidence imports')
    signed="Write-Host 'TRIPLE_ID_EXCLUSIVE_REAL_JOURNALED_SWAP_PASS active_claim_persisted=true fresh_hmac_and_current_utc=true recovery_possible=true'"
    early=r"""
# This point is immediately after the real HMAC-authorized atomic ZIP swap.
# It is a real sealed DPAPI active transaction, not a caller JSON fixture.
$readonlyRoots=@{
    HostedCiRoot=$script:USERStoreRoot
    HostedCiLocalAppDataRoot=$script:PPBLocal
    HostedCiAppDataRoot=$script:PPBRoaming
}
$earlyReady=Get-CustomAppSealedRestoreReadinessV014 @readonlyRoots
Assert-TJR ([bool]$earlyReady.ok -and [int]$earlyReady.active_count -eq 1 -and
   [int]$earlyReady.inspected_count -eq 1 -and
   -not[bool]$earlyReady.production_mutation_authorized) 'fresh sealed signed ZIP restore readiness scan invalid'
$earlyItem=$earlyReady.items[0]
Assert-TJR ([bool]$earlyItem.active -and [string]$earlyItem.name -ceq 'tagify' -and
   [string]$earlyItem.source_fingerprint -cmatch '^[0-9a-f]{64}$' -and
   -not[bool]$earlyItem.production_execution_authorized) 'real signed ZIP source became execution authority'
if([string]$earlyItem.phase -in @('candidate-live','transaction-finalized','live-moved-to-old')){
    Assert-TJR ([bool]$earlyItem.eligible -and $null-ne$earlyItem.receipt -and
        -not[bool]$earlyItem.receipt.execution_authorized -and
        [string]$earlyItem.receipt.transaction_id -ceq [string]$script:USERExpectedTx) (
        'qualified no-create historical exact-restore pre-apply receipt not accepted: '+[string]$earlyItem.reason)
    Write-Host 'PROTECTED_RESTORE_REAL_SIGNED_ZIP_PREAPPLY_ADMISSION_PASS'
}elseif([string]$earlyItem.phase -in @('apply-starting','apply-returned-success-pending-verification','rollback-required')){
    Assert-TJR (-not[bool]$earlyItem.eligible -and
        [string]$earlyItem.reason -ceq 'verified-spicetify-binary-pin-not-enrolled') 'apply-phase without pin accepted'
    Write-Host 'PROTECTED_RESTORE_REAL_SIGNED_ZIP_APPLY_WITHOUT_PIN_DENIED_PASS'
}else{
    Assert-TJR (-not[bool]$earlyItem.eligible) 'unqualified journal phase admitted as exact restore'
    Write-Host 'PROTECTED_RESTORE_REAL_SIGNED_ZIP_UNQUALIFIED_PHASE_DENIED_PASS'
}
"""
    s=one(s,signed,signed+'\n'+early.strip('\n'),'real signed ZIP early source-to-preflight')
    missing="Write-Host 'SEALED_STARTUP_REAL_SIGNED_ZIP_MISSING_LIVE_NO_MUTATION_PASS'"
    fault=r"""
# A missing lock must remain missing after BOTH the journal reader and the
# separate evidence-envelope reader, even when a complete real envelope exists.
$protectedLock=Join-Path $script:TJRStore '.journal.lock'
Assert-TJR ([IO.File]::Exists($protectedLock)) 'real signed ZIP journal lock vanished before no-create test'
$protectedOriginalHash=(Get-FileHash -LiteralPath $protectedLock -Algorithm SHA256).Hash
$protectedMoved=Join-Path $script:TJRRoot ('protected-no-create-test-'+[Guid]::NewGuid().ToString('N'))
[IO.File]::Move($protectedLock,$protectedMoved)
try{
    $blockedEvidence=Read-CustomAppProtectedEvidenceReadOnlyV014 -AllowedRoot $script:TJRRoot -StoreDirectory $script:TJRStore -ExpectedTransactionId $script:USERExpectedTx
    Assert-TJR (-not[bool]$blockedEvidence.ok -and
       -not[bool]$blockedEvidence.production_mutation_authorized -and
       -not[IO.File]::Exists($protectedLock)) 'evidence read materialized missing journal lock'
    $blockedStartup=$false
    try{$bad=Get-CustomAppSealedRestoreReadinessV014 @readonlyRoots}
    catch{$blockedStartup=$true}
    Assert-TJR ($blockedStartup -and
       -not[IO.File]::Exists($protectedLock)) 'sealed readiness materialized missing journal lock'
}finally{
    if([IO.File]::Exists($protectedMoved) -and -not[IO.File]::Exists($protectedLock)){
        [IO.File]::Move($protectedMoved,$protectedLock)
    }
}
Assert-TJR ([IO.File]::Exists($protectedLock) -and
   (Get-FileHash -LiteralPath $protectedLock -Algorithm SHA256).Hash -ceq $protectedOriginalHash) 'negative no-create lock case failed to restore hosted fixture bytes'
Write-Host 'PROTECTED_RESTORE_REAL_SIGNED_ZIP_MISSING_JOURNAL_LOCK_NO_CREATE_PASS'

# Independently verify the entire persisted evidence envelope while holding
# its existing journal lock (no release between journal and evidence reads).
$protectedEvidence=Read-CustomAppProtectedEvidenceReadOnlyV014 -AllowedRoot $script:TJRRoot -StoreDirectory $script:TJRStore -ExpectedTransactionId $script:USERExpectedTx
Assert-TJR ([bool]$protectedEvidence.ok -and
   [bool]$protectedEvidence.reloaded_from_persistent_store -and
   [string]$protectedEvidence.transaction_id -ceq [string]$script:USERExpectedTx -and
   [string]$protectedEvidence.journal_entry_sha256 -cmatch '^[0-9a-f]{64}$' -and
   -not[bool]$protectedEvidence.production_mutation_authorized) (
       'real signed evidence envelope not qualified by no-create reader: '+[string]$protectedEvidence.reason)
Write-Host 'PROTECTED_RESTORE_REAL_SIGNED_ZIP_NO_CREATE_EVIDENCE_PASS'

$activeReady=Get-CustomAppSealedRestoreReadinessV014 @readonlyRoots
Assert-TJR ([bool]$activeReady.ok -and [int]$activeReady.active_count -eq 1 -and
   -not[bool]$activeReady.production_mutation_authorized -and
   -not[IO.Directory]::Exists([string]$script:TIDLive)) 'missing-live real signed ZIP protected readiness mutated app'
$activeItem=$activeReady.items[0]
if([string]$activeItem.phase -in @('candidate-live','transaction-finalized')){
    # This is a deliberately DISPLACED live candidate after a completed
    # atomic swap. The journal has not recorded an absent live directory:
    # it is not safe to misclassify that tampered layout as a qualified
    # pre-apply restore. Deny even with a valid journal and envelope.
    Assert-TJR (-not[bool]$activeItem.eligible -and $null-eq$activeItem.receipt -and
       [string]$activeItem.reason -match '^qualified-readonly-admission-denied:') (
         'displaced live candidate was admitted against its recorded journal phase: '+[string]$activeItem.reason)
    Write-Host 'PROTECTED_RESTORE_DISPLACED_CANDIDATE_FAIL_CLOSED_PASS'
}elseif([string]$activeItem.phase -ceq 'live-moved-to-old'){
    # A legitimate live-moved-to-old crash can be restorable if the old
    # and staged candidate still match the durable receipt. A second
    # unexplained displacement must instead remain a no-action denial.
    if([bool]$activeItem.eligible){
        Assert-TJR ($null-ne$activeItem.receipt -and
           [string]$activeItem.receipt.transaction_id -ceq [string]$script:USERExpectedTx -and
           -not[bool]$activeItem.receipt.production_mutation_authorized) 'restore receipt identity or authority failed'
    }else{
        Assert-TJR ($null-eq$activeItem.receipt -and
           [string]$activeItem.reason -match '^qualified-readonly-admission-denied:') 'live-moved preflight denied without fail-closed reason'
    }
}elseif([string]$activeItem.phase -in @('apply-starting','apply-returned-success-pending-verification','rollback-required')){
    Assert-TJR (-not[bool]$activeItem.eligible -and
       [string]$activeItem.reason -ceq 'verified-spicetify-binary-pin-not-enrolled') 'missing live apply phase incorrectly admitted'
}else{
    Assert-TJR (-not[bool]$activeItem.eligible) 'missing live unqualified journal phase admitted'
}
Assert-TJR ((Get-FileHash -LiteralPath $inventoryStatePaths.state -Algorithm SHA256).Hash -ceq $sealedBefore) 'qualified missing-live preflight rewrote sealed DPAPI state'
Write-Host 'PROTECTED_RESTORE_REAL_SIGNED_ZIP_MISSING_LIVE_BOUNDED_ADMISSION_PASS'
"""
    s=one(s,missing,missing+'\n'+fault.strip('\n'),'signed ZIP missing-live read-only evidence and negative tests')
    terminal="Write-Host 'SEALED_STARTUP_TERMINAL_REPLAY_NOT_SELECTABLE_PASS'"
    final=r"""
$inactive=Get-CustomAppSealedRestoreReadinessV014 @readonlyRoots
Assert-TJR ([bool]$inactive.ok -and [int]$inactive.inspected_count -eq 1 -and
   [int]$inactive.active_count -eq 0 -and
   -not[bool]$inactive.items[0].eligible -and
   $null-eq$inactive.items[0].receipt -and
   -not[bool]$inactive.production_execution_authorized) 'terminal DPAPI consumption still offered a restore receipt'
Write-Host 'PROTECTED_RESTORE_REAL_SIGNED_ZIP_TERMINAL_NO_REPLAY_PASS'
"""
    s=one(s,terminal,terminal+'\n'+final.strip('\n'),'terminal no replay')
    for mark in ('PROTECTED_RESTORE_REAL_SIGNED_ZIP_MISSING_JOURNAL_LOCK_NO_CREATE_PASS',
       'PROTECTED_RESTORE_REAL_SIGNED_ZIP_NO_CREATE_EVIDENCE_PASS',
       'PROTECTED_RESTORE_REAL_SIGNED_ZIP_MISSING_LIVE_BOUNDED_ADMISSION_PASS',
       'PROTECTED_RESTORE_REAL_SIGNED_ZIP_TERMINAL_NO_REPLAY_PASS',
       'FRESH_WORKER_REAL_SIGNED_ZIP_HANDOFF_END_TO_END_PASS'):
        if s.count(mark)!=1:raise RuntimeError('lost qualified real signed ZIP proof '+mark)
    OUT.write_text(s,encoding='utf-8',newline='\n')
    print('PROTECTED_RESTORE_REAL_SIGNED_ZIP_E2E_DERIVED_PASS',len(s),
          hashlib.sha256(s.encode('utf-8')).hexdigest())
if __name__=='__main__':main()
