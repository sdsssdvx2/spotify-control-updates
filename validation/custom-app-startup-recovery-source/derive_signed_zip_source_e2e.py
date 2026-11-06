"""Extend proven real third-HMAC signed ZIP Windows E2E with sealed source-to-plan
admission in a fresh DPAPI read, while retaining the independent rollback
worker and every prior replay/lock guard. No recovery executor activation.
"""
from pathlib import Path
import hashlib,runpy,subprocess
ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
PARENT=ROOT/'validation/custom-app-durable-recovery-inventory/derive_signed_zip_inventory_e2e.py'
PARENT_BLOB='0cc98c86b0784c9a6787b712437db7a147316430'
PARENT_SCRIPT=ROOT/'validation/custom-app-durable-recovery-inventory/ci_signed_zip_durable_recovery_inventory.ps1'
OUT=HERE/'ci_signed_zip_sealed_startup_source.ps1'
MODULE=HERE/'startup-recovery-source.ps1'
MODULE_BLOB='fa5e143189040607dc4432d410e94164afe99ece'
def pin(p,sha):
    actual=subprocess.check_output(['git','hash-object',str(p)],cwd=ROOT,text=True).strip()
    if actual!=sha:raise RuntimeError('sealed source immutable parent drift '+str(p))
def one(s,a,b,label):
    c=s.count(a)
    if c!=1:raise RuntimeError(f'{label}: required one anchor, got {c}')
    return s.replace(a,b,1)
def main():
    pin(PARENT,PARENT_BLOB);pin(MODULE,MODULE_BLOB)
    if PARENT_SCRIPT.exists() or OUT.exists():
        raise RuntimeError('refuse overwrite existing signed ZIP fixture')
    parent=runpy.run_path(str(PARENT),run_name='parent-proven-real-signed-zip')
    parent['main']()
    s=PARENT_SCRIPT.read_text('utf-8').replace('\r\n','\n')
    load=". (Join-Path $root 'validation/custom-app-durable-recovery-inventory/durable-recovery-inventory.ps1')"
    add="""\n. (Join-Path $root 'validation/custom-app-startup-recovery-source/startup-recovery-source.ps1')
. (Join-Path $root 'validation/custom-app-production-recovery-plan-contract-v0.1.0/custom-app-production-recovery-plan.ps1')"""
    s=one(s,load,load+add,'seal-source and pure plan module import')
    early="Write-Host 'DURABLE_RECOVERY_REAL_SIGNED_ZIP_UNREADY_JOURNAL_DENIED_PASS'"
    early_add=r"""
$sealedUnreadyDenied=$false
try{
    $void=Get-CustomAppSealedStartupRecoveryAssessmentV013 -HostedCiRoot $script:USERStoreRoot
}catch{$sealedUnreadyDenied=$true}
Assert-TJR $sealedUnreadyDenied 'uninitialized signed journal became trusted sealed startup recovery source'
Write-Host 'SEALED_STARTUP_UNREADY_JOURNAL_DENIED_PASS'
"""
    s=one(s,early,early+'\n'+early_add.strip(),'reject not-yet-durable journal')
    missing="Write-Host 'DURABLE_RECOVERY_REAL_SIGNED_ZIP_MISSING_LIVE_DISCOVERY_PASS'"
    missing_add=r"""
# This source bridge selects the journal and plan itself while holding
# the CURRENTUSER registry lock and per-app lock; no app or transaction
# identity, paths, plan or fixture JSON are supplied by the caller.
$activeBound=Get-CustomAppSealedStartupRecoveryAssessmentV013 -HostedCiRoot $script:USERStoreRoot
Assert-TJR ([bool]$activeBound.ok -and
  [int]$activeBound.active_count -eq 1 -and
  [int]$activeBound.inspected_count -eq 1) 'signed active state not self-selected by sealed startup assessment'
$bound=$activeBound.items[0]
Assert-TJR ([bool]$bound.active -and
  [string]$bound.source.name -ceq 'tagify' -and
  [string]$bound.source.live -ceq [string]$script:TIDLive -and
  [string]$bound.phase -ceq [string]$missingInventory.items[0].journal_phase -and
  [string]$bound.source.transaction_id -ceq [string]$bound.plan.transaction_id -and
  [string]$bound.source.consumption_id -cmatch '^[0-9a-f]{64}$' -and
  [string]$bound.source.nonce -cmatch '^[0-9a-f]{32}$' -and
  [string]$bound.source.journal_entry_sha256 -cmatch '^[0-9a-f]{64}$' -and
  [string]$bound.source.source_fingerprint -cmatch '^[0-9a-f]{64}$' -and
  [string]$bound.plan.plan_fingerprint -cmatch '^[0-9a-f]{64}$' -and
  -not[bool]$bound.source.production_mutation_authorized -and
  -not[bool]$bound.plan.execution_authorized -and
  -not[bool]$activeBound.production_execution_authorized) 'sealed signed source lacked triple-ID plan proof or leaked authority'
Assert-TJR ((Get-FileHash -LiteralPath $inventoryStatePaths.state -Algorithm SHA256).Hash -ceq $sealedBefore) 'sealed assessment rewrote encrypted transaction'
Assert-TJR (-not[IO.Directory]::Exists([string]$script:TIDLive)) 'sealed assessment recreated missing live'
$boundAgain=Get-CustomAppSealedStartupRecoveryAssessmentV013 -HostedCiRoot $script:USERStoreRoot
Assert-TJR ([string]$boundAgain.items[0].source.source_fingerprint -ceq
  [string]$bound.source.source_fingerprint) 'source fingerprint drifted across no-op restart reads'
Write-Host 'SEALED_STARTUP_REAL_SIGNED_ZIP_SOURCE_AND_PLAN_PASS'
Write-Host 'SEALED_STARTUP_REAL_SIGNED_ZIP_MISSING_LIVE_NO_MUTATION_PASS'
"""
    s=one(s,missing,missing+'\n'+missing_add.strip(),'bind real signed missing-live journal to source plan')
    terminal="Write-Host 'DURABLE_RECOVERY_REAL_SIGNED_ZIP_TERMINAL_INVENTORY_PASS'"
    terminal_add=r"""
$terminalBound=Get-CustomAppSealedStartupRecoveryAssessmentV013 -HostedCiRoot $script:USERStoreRoot
Assert-TJR ([bool]$terminalBound.ok -and
   [int]$terminalBound.active_count -eq 0 -and
   [int]$terminalBound.inspected_count -eq 1 -and
   $null -eq $terminalBound.items[0].source -and
   $null -eq $terminalBound.items[0].plan -and
   -not[bool]$terminalBound.production_mutation_authorized) 'consumed terminal transaction was admitted again'
Write-Host 'SEALED_STARTUP_TERMINAL_REPLAY_NOT_SELECTABLE_PASS'
"""
    s=one(s,terminal,terminal+'\n'+terminal_add.strip(),'terminal replay blocked by sealed selector')
    for proof in ('SEALED_STARTUP_UNREADY_JOURNAL_DENIED_PASS',
                  'SEALED_STARTUP_REAL_SIGNED_ZIP_SOURCE_AND_PLAN_PASS',
                  'SEALED_STARTUP_REAL_SIGNED_ZIP_MISSING_LIVE_NO_MUTATION_PASS',
                  'SEALED_STARTUP_TERMINAL_REPLAY_NOT_SELECTABLE_PASS',
                  'FRESH_WORKER_REAL_SIGNED_ZIP_HANDOFF_END_TO_END_PASS'):
        if s.count(proof)!=1:raise RuntimeError('signed ZIP source proof absent or duplicated '+proof)
    OUT.write_text(s,encoding='utf-8',newline='\n')
    print('SEALED_STARTUP_REAL_SIGNED_ZIP_DERIVED_PASS',len(s),
          hashlib.sha256(s.encode('utf-8')).hexdigest())
if __name__=='__main__':main()
