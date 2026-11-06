"""Derive the *already proven* real THIRD-HMAC signed ZIP + fresh locked
restore worker E2E, inject read-only self-discovery directly from encrypted
user store at three high-risk points. No source or app mutation during scan.
"""
from pathlib import Path
import hashlib,runpy,subprocess
ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
PARENT=ROOT/'validation/custom-app-fresh-worker-lock-handoff/derive_fresh_worker_locked_signed_zip.py'
PARENT_BLOB='34d1abfa71055c955405e2e91cead45d1e7684ee'
PARENT_SCRIPT=ROOT/'validation/custom-app-fresh-worker-lock-handoff/ci_signed_zip_fresh_worker_lock_handoff.ps1'
OUT=HERE/'ci_signed_zip_durable_recovery_inventory.ps1'
MODULE=ROOT/'validation/custom-app-durable-recovery-inventory/durable-recovery-inventory.ps1'
MODULE_BLOB='5452d87053e8d1d7ba69e026c874208ab506dab3'
def pin(p,sha):
    x=subprocess.check_output(['git','hash-object',str(p)],cwd=ROOT,text=True).strip()
    if x!=sha:raise RuntimeError('qualified original source drift '+str(p))
def one(s,old,new,label):
    c=s.count(old)
    if c!=1:raise RuntimeError(f'{label} did not match exact historical test boundary, count={c}')
    return s.replace(old,new,1)
def main():
    pin(PARENT,PARENT_BLOB);pin(MODULE,MODULE_BLOB)
    if PARENT_SCRIPT.exists() or OUT.exists():raise RuntimeError('refuse to overwrite historical E2E derivative')
    old=runpy.run_path(str(PARENT),run_name='previous-signed-ZIP-reader')
    old['main']()
    src=PARENT_SCRIPT.read_text('utf-8').replace('\r\n','\n')
    dot=". (Join-Path $root 'validation/custom-app-cooperative-cross-engine-lock/cross-engine-transaction-lock.ps1')"
    src=one(src,dot,dot+"\n$script:RecoveryEnrollmentCreated=$false\n. (Join-Path $root 'validation/custom-app-durable-recovery-inventory/durable-recovery-inventory.ps1')",'load signed real E2E inventory')
    preswap="Write-Host 'USER_TERMINAL_SIGNED_ID_RESERVED_BEFORE_REAL_ATOMIC_SWAP_PASS'"
    m=src.index(preswap)
    if m<0:raise RuntimeError('previous signed ZIP preswap receipt missing')
    end=src.index("\n",m)
    before=src[m:end]
    injection=r"""
# The DPAPI locator is durable, but this is intentionally BEFORE the
# journal store is created by the actual transaction executor. It must
# be rejected, not elevated into an authenticated recovery instruction.
$inventoryStatePaths=Get-CustomAppUserTxnPathsV010 -Name tagify -LivePath $script:TIDLive -HostedCiRoot $script:USERStoreRoot
$sealedBefore=(Get-FileHash -LiteralPath $inventoryStatePaths.state -Algorithm SHA256).Hash
$earlyDenied=$false
try{
    $early=Get-CustomAppDurableRecoveryInventoryV012 -HostedCiRoot $script:USERStoreRoot
}catch{
    $earlyDenied=([string]$_.Exception.Message -match 'journal store missing')
}
Assert-TJR $earlyDenied 'locator with uncreated journal store was treated as recovery authority'
Assert-TJR ((Get-FileHash -LiteralPath $inventoryStatePaths.state -Algorithm SHA256).Hash -ceq $sealedBefore) 'unready journal probe modified sealed active state'
[void](Assert-CustomAppCrossEngineTransactionLockHeldV010 -Session $script:RealZipCrossLock)
Write-Host 'DURABLE_RECOVERY_REAL_SIGNED_ZIP_UNREADY_JOURNAL_DENIED_PASS'
"""
    src=one(src,before,before+'\n'+injection.strip('\n'),'read sealed active original signed journal before live swap')
    missing="$opened=Open-CustomAppUserTxnMissingLiveRecoveryV011 -Name tagify -LivePath $script:TIDLive -HostedCiRoot $script:USERStoreRoot"
    miss=r"""
# After the actual journal is initialized and the live directory has
# been moved away, a sealed active transaction is discoverable even
# without a caller-supplied path. Acquire the exact hosted registry-root global lock.
# A damaged/missing journal lock must not be silently recreated by
# read-only inventory. The legacy reader used OpenOrCreate, which would have
# altered the active transaction's journal even when discovery fails.
$journalLock=Join-Path $script:TJRStore '.journal.lock'
Assert-TJR ([IO.File]::Exists($journalLock)) 'real signed journal exclusive lock is absent before adversarial test'
$journalLockHash=(Get-FileHash -LiteralPath $journalLock -Algorithm SHA256).Hash
$detachedJournalLock=Join-Path $script:TJRStore ('journal-lock-detached-'+[Guid]::NewGuid().ToString('N'))
[IO.File]::Move($journalLock,$detachedJournalLock)
try{
    $lockMissingDenied=$false
    try{
        $lockMissingProbe=Get-CustomAppDurableRecoveryInventoryV012 -HostedCiRoot $script:USERStoreRoot
    }catch{
        $lockMissingDenied=([string]$_.Exception.Message -match 'durable-recovery-journal-lock-missing')
    }
    Assert-TJR $lockMissingDenied 'missing journal lock was not rejected by the read-only inventory'
    Assert-TJR (-not[IO.File]::Exists($journalLock)) 'journal inventory recreated the missing lock file'
    Assert-TJR ((Get-FileHash -LiteralPath $inventoryStatePaths.state -Algorithm SHA256).Hash -ceq $sealedBefore) 'missing journal lock check changed sealed active record'
}finally{
    if([IO.File]::Exists($detachedJournalLock) -and -not[IO.File]::Exists($journalLock)){
        [IO.File]::Move($detachedJournalLock,$journalLock)
    }
}
Assert-TJR ([IO.File]::Exists($journalLock) -and
    (Get-FileHash -LiteralPath $journalLock -Algorithm SHA256).Hash -ceq $journalLockHash) 'journal lock not restored bit-for-bit after negative test'
Write-Host 'DURABLE_RECOVERY_JOURNAL_LOCK_MISSING_READ_ONLY_DENIED_PASS'

$missingInventory=Get-CustomAppDurableRecoveryInventoryV012 -HostedCiRoot $script:USERStoreRoot
Assert-TJR ([bool]$missingInventory.ok -and [bool]$missingInventory.enrollment_found -and
   [bool]$missingInventory.needs_recovery -and
   [int]$missingInventory.inspected_count -eq 1 -and
   [int]$missingInventory.active_count -eq 1 -and
   [bool]$missingInventory.items[0].active -and
   [bool]$missingInventory.items[0].live_missing -and
   -not[bool]$missingInventory.items[0].may_execute_recovery -and
   -not[bool]$missingInventory.production_mutation_authorized) 'missing live authenticated journal was not safely discovered'
Assert-TJR ((Get-FileHash -LiteralPath $inventoryStatePaths.state -Algorithm SHA256).Hash -ceq $sealedBefore) 'missing-live inventory modified protected state'
Assert-TJR (-not[IO.Directory]::Exists([string]$script:TIDLive)) 'read-only missing-live scan recreated custom app'
[void](Assert-CustomAppCrossEngineTransactionLockHeldV010 -Session $script:RealZipCrossLock)
Write-Host 'DURABLE_RECOVERY_REAL_SIGNED_ZIP_ACTIVE_DPAPI_INVENTORY_PASS'
Write-Host 'DURABLE_RECOVERY_REAL_SIGNED_ZIP_MISSING_LIVE_DISCOVERY_PASS'
"""
    src=one(src,missing,miss.strip('\n')+'\n'+missing,'read DPAPI when real swapped live folder absent')
    terminal="Write-Host 'FRESH_WORKER_REAL_SIGNED_ZIP_HANDOFF_END_TO_END_PASS"
    i=src.index(terminal)
    if i<0:raise RuntimeError('final qualified fresh worker verified terminal marker absent')
    line=src[i:src.index('\n',i) if '\n' in src[i:] else len(src)]
    after=r"""
$finished=Get-CustomAppDurableRecoveryInventoryV012 -HostedCiRoot $script:USERStoreRoot
Assert-TJR ([bool]$finished.ok -and
   -not[bool]$finished.needs_recovery -and [int]$finished.active_count -eq 0 -and
   [int]$finished.inspected_count -eq 1 -and
   [string]$finished.items[0].journal_phase -ceq 'none') 'durably retired consumed ID still appears active in read-only inventory'
Write-Host 'DURABLE_RECOVERY_REAL_SIGNED_ZIP_TERMINAL_INVENTORY_PASS'
"""
    src=one(src,line,line+'\n'+after.strip('\n'),'read terminal DPAPI state after retired signed claim')
    for x in ('DURABLE_RECOVERY_REAL_SIGNED_ZIP_UNREADY_JOURNAL_DENIED_PASS',
      'USER_JOURNAL_REAL_SIGNED_THIRD_ID_PRE_SWAP_LOCATOR_BOUND_PASS',
      'DURABLE_RECOVERY_REAL_SIGNED_ZIP_ACTIVE_DPAPI_INVENTORY_PASS',
      'DURABLE_RECOVERY_REAL_SIGNED_ZIP_MISSING_LIVE_DISCOVERY_PASS',
       'DURABLE_RECOVERY_JOURNAL_LOCK_MISSING_READ_ONLY_DENIED_PASS',
      'DURABLE_RECOVERY_REAL_SIGNED_ZIP_TERMINAL_INVENTORY_PASS',
      'FRESH_WORKER_REAL_SIGNED_ZIP_HANDOFF_END_TO_END_PASS'):
        if src.count(x)!=1:raise RuntimeError('derived real signed ZIP stage not unique '+x)
    OUT.write_text(src,encoding='utf-8',newline='\n')
    print('DURABLE_RECOVERY_REAL_SIGNED_ZIP_INVENTORY_DERIVED_PASS',len(src),
       hashlib.sha256(src.encode('utf-8')).hexdigest())
if __name__=='__main__':main()
