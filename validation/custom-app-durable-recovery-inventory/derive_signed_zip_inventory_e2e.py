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
MODULE_BLOB='ce6f4d8a04648387ee2bb3d067973c4243006660'
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
    preswap="Write-Host 'USER_JOURNAL_REAL_SIGNED_THIRD_ID_PRE_SWAP_LOCATOR_BOUND_PASS"
    m=src.index(preswap)
    if m<0:raise RuntimeError('previous signed ZIP preswap receipt missing')
    end=src.index("\n",m)
    before=src[m:end]
    injection=r"""
$inventoryStatePaths=Get-CustomAppUserTxnPathsV010 -Name tagify -LivePath $script:TIDLive -HostedCiRoot $script:USERStoreRoot
$sealedBefore=(Get-FileHash -LiteralPath $inventoryStatePaths.state -Algorithm SHA256).Hash
$discovered=Get-CustomAppDurableRecoveryInventoryV012 -HostedCiRoot $script:USERStoreRoot
Assert-TJR ([bool]$discovered.ok -and [bool]$discovered.enrollment_found -and
    [bool]$discovered.needs_recovery -and [int]$discovered.active_count -eq 1 -and
    [int]$discovered.inspected_count -eq 1 -and [bool]$discovered.items[0].active -and
    -not[bool]$discovered.items[0].live_missing -and
    -not[bool]$discovered.items[0].may_execute_recovery -and
    -not[bool]$discovered.production_mutation_authorized -and
    [string]$discovered.items[0].journal_phase -in @('prepared','atomic-mutation-starting',
      'live-moved-to-old','candidate-live','transaction-finalized')) 'active signed journal was not discovered read-only before swap'
Assert-TJR ((Get-FileHash -LiteralPath $inventoryStatePaths.state -Algorithm SHA256).Hash -ceq $sealedBefore) 'inventory modified protected user state before signed swap'
Write-Host 'DURABLE_RECOVERY_REAL_SIGNED_ZIP_ACTIVE_DPAPI_INVENTORY_PASS'
"""
    src=one(src,before,before+'\n'+injection.strip('\n'),'read sealed active original signed journal before live swap')
    missing="$opened=Open-CustomAppUserTxnMissingLiveRecoveryV011 -Name tagify -LivePath $script:TIDLive -HostedCiRoot $script:USERStoreRoot"
    miss=r"""
$missingInventory=Get-CustomAppDurableRecoveryInventoryV012 -HostedCiRoot $script:USERStoreRoot
Assert-TJR ([bool]$missingInventory.ok -and [bool]$missingInventory.needs_recovery -and
   [int]$missingInventory.active_count -eq 1 -and
   [bool]$missingInventory.items[0].live_missing -and
   -not[bool]$missingInventory.items[0].may_execute_recovery) 'encrypted missing-live user transaction could not be discovered'
Assert-TJR (-not[IO.Directory]::Exists([string]$script:TIDLive)) 'read-only missing-live scan recreated custom app'
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
    for x in ('USER_JOURNAL_REAL_SIGNED_THIRD_ID_PRE_SWAP_LOCATOR_BOUND_PASS',
      'DURABLE_RECOVERY_REAL_SIGNED_ZIP_ACTIVE_DPAPI_INVENTORY_PASS',
      'DURABLE_RECOVERY_REAL_SIGNED_ZIP_MISSING_LIVE_DISCOVERY_PASS',
      'DURABLE_RECOVERY_REAL_SIGNED_ZIP_TERMINAL_INVENTORY_PASS',
      'FRESH_WORKER_REAL_SIGNED_ZIP_HANDOFF_END_TO_END_PASS'):
        if src.count(x)!=1:raise RuntimeError('derived real signed ZIP stage not unique '+x)
    OUT.write_text(src,encoding='utf-8',newline='\n')
    print('DURABLE_RECOVERY_REAL_SIGNED_ZIP_INVENTORY_DERIVED_PASS',len(src),
       hashlib.sha256(src.encode('utf-8')).hexdigest())
if __name__=='__main__':main()
