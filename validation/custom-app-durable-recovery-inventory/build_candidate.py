"""Assemble a real disabled Addon Manager with read-only DPAPI user-state
startup inventory. Fully inverse-recoverable to PR232. No action dispatcher,
normal legacy update, commit, rollback or new FullChain behavior changes.
"""
from __future__ import annotations
from pathlib import Path
import re,hashlib,json,subprocess
ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
OUT=HERE/'out'/'bin'
PARENT='513e5fa9f174bb481b2cc9a1585c9d5700be409b'
PARENT_BUILDER='validation/custom-app-cooperative-cross-engine-lock/build_candidate.py'
PARENT_BUILDER_SHA='9bb911d3bfd75c283d75970bd06d5ee856c8a5c7'
PRIOR=(1485347,'fbce12662b1135d098503a017d4e4443d55814796cb986dfc59012ea094d66ae')
MAIN=(284327,'69ef7fb3ca57b4d5faac6873ac06dffc38f6e5b0d1ad8fc31fcbe2bb236f5c99')
MODULE='validation/custom-app-durable-recovery-inventory/durable-recovery-inventory.ps1'
MODULE_BLOB='ce6f4d8a04648387ee2bb3d067973c4243006660'
TEST='validation/custom-app-durable-recovery-inventory/test_durable_recovery_inventory.ps1'
TEST_BLOB='b1416f592d183201f9a828c52d38729ebd5d895c'
OLD_HOOK='    try { Test-CustomAppCrossEngineTransactionLockSelfTestV010 } catch { $errors.Add("Custom App cooperative cross-engine transaction lock self-test failed: $($_.Exception.Message)") }'
NEW_HOOK=OLD_HOOK+'\n    try { Test-CustomAppDurableRecoveryInventorySelfTestV012 } catch { $errors.Add("Custom App durable recovery startup inventory self-test failed: $($_.Exception.Message)") }'
NEW_FUNCTIONS=['Get-CustomAppDurableRecoveryInventoryV012','Test-CustomAppDurableRecoveryInventorySelfTestV012']
def sha(b):return hashlib.sha256(b).hexdigest()
def pin(ref,p,expected):
    actual=subprocess.check_output(['git','rev-parse',f'{ref}:{p}'],cwd=ROOT,text=True).strip()
    if actual!=expected:raise RuntimeError('qualified file pin mismatch '+p)
def one(s,old,new,label):
    count=s.count(old)
    if count!=1:raise RuntimeError(f'{label}: expected unique anchor got {count}')
    return s.replace(old,new,1)
def funcs(s):return re.findall(r'(?im)^[ \t]*function\s+([A-Za-z0-9_-]+)\s*\{',s)
def block(s,n):
    m=re.search(r'(?im)^[ \t]*function\s+'+re.escape(n)+r'\s*\{',s)
    if not m:raise RuntimeError('missing original '+n)
    next_fn=re.search(r'(?im)^[ \t]*function\s+[A-Za-z0-9_-]+\s*\{',s[m.end():])
    return s[m.start():(m.end()+next_fn.start() if next_fn else len(s))]
def main():
    for ref,p,v in ((PARENT,PARENT_BUILDER,PARENT_BUILDER_SHA),
                    ('HEAD',MODULE,MODULE_BLOB),('HEAD',TEST,TEST_BLOB)):
        pin(ref,p,v)
    subprocess.check_call(['python',str(ROOT/PARENT_BUILDER)],cwd=ROOT)
    d=ROOT/'validation/custom-app-cooperative-cross-engine-lock/out/bin'
    files={p:(d/p).read_bytes() for p in ('addon-manager.ps1','spotify-control.ps1',
          'Collect-Marketplace-Records.ps1','LevelDbReadOnly.cs')}
    old=files['addon-manager.ps1']
    if (len(old),sha(old))!=PRIOR or (len(files['spotify-control.ps1']),sha(files['spotify-control.ps1']))!=MAIN:
        raise RuntimeError('previous Windows-proven signed ZIP Addon Manager drift')
    bom=b'\xef\xbb\xbf' if old.startswith(b'\xef\xbb\xbf') else b''
    original=old[len(bom):].decode('utf-8').replace('\r\n','\n')
    module=(ROOT/MODULE).read_text('utf-8-sig').replace('\r\n','\n').strip()
    new=funcs(module)
    if sorted(new)!=sorted(NEW_FUNCTIONS) or set(new)&set(funcs(original)):
        raise RuntimeError('inventory source exports unqualified or duplicate functions')
    for required in ('[IO.FileMode]::Open','[IO.FileShare]::None',
      'Open-CustomAppCrossEngineTransactionLockV010',
      'Read-CustomAppUserTxnStateV010',
      'Read-CustomAppUserTxnJournalLocatorV010',
      'Read-CustomAppProductionCrashJournalV010',
      'Get-CustomAppUserTxnMissingLivePathsV011',
      'no_app_state_modified=$true'):
        if required not in module:raise RuntimeError('unsafe or missing inventory invariant '+required)
    for forbidden in ('Open-CustomAppUserTxnStoreV010','[IO.File]::Delete',
      'Save-CustomAppUserTxnStoreV010','Write-CustomAppUserTxnBytesV010',
      'FileMode]::OpenOrCreate','Move-Item','Remove-Item',
      'Invoke-CustomAppProductionFullChainV010',
      'Invoke-CustomAppProductionSpicetifyApplyExecutorV010'):
        if forbidden in module and not (forbidden=='Open-CustomAppUserTxnStoreV010' and
           module.count('Open-CustomAppUserTxnStoreV010')==1 and
           'Never call Open-CustomAppUserTxnStoreV010' in module):
            raise RuntimeError('inventory module gained side-effect primitive '+forbidden)
    payload=module+'\n\n'
    changed=one(original,'function Test-Due {',payload+'function Test-Due {','source insertion')
    changed=one(changed,OLD_HOOK,NEW_HOOK,'SelfTest registration')
    for name in ('Update-AutoApps','Commit-LastTransaction','Rollback-LastTransaction',
                 'Invoke-CustomAppProductionFullChainV010'):
        if block(changed,name)!=block(original,name):raise RuntimeError('prior mutating function changed '+name)
    if 'Custom App production full-chain execution is intentionally unavailable in integration-only candidate.' not in block(changed,'Invoke-CustomAppProductionFullChainV010'):
        raise RuntimeError('disabled FullChain guard missing')
    if changed.count('$script:CustomAppProductionPipelineEnabled = $true')!=original.count('$script:CustomAppProductionPipelineEnabled = $true'):
        raise RuntimeError('new production execution authority present')
    inverse=one(changed,NEW_HOOK,OLD_HOOK,'inverse SelfTest')
    inverse=one(inverse,payload,'','inverse inventory module')
    if inverse!=original:raise RuntimeError('not byte-exact inverse to qualified parent')
    result=bom+changed.replace('\n','\r\n').encode('utf-8')
    files['addon-manager.ps1']=result
    OUT.mkdir(parents=True,exist_ok=True)
    for n,b in files.items():(OUT/n).write_bytes(b)
    report=dict(schema=1,qualified_parent=PARENT,old_sha256=sha(old),
      addon_sha256=sha(result),addon_bytes=len(result),
      fullchain_hard_disabled=True,all_legacy_transaction_functions_preserved=True,
      independent_restart_recovery_code_preserved=True,
      no_new_normal_update_entrypoint=True,
      scans_sealed_DPAPI_key_registry_without_user_provided_paths=True,
      FileMode_Open_only_on_user_ledger=True,
      pending_write_never_discarded_by_discovery=True,
      global_and_per_app_lock_scoped_entire_inventory=True,
      journal_identity_verified_before_reporting_active=True,
      no_mutation_authority=True,operating_main_unchanged=True,
      exact_previous_candidate_inverse=True)
    (HERE/'candidate-validation.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n',encoding='utf-8')
    print('DURABLE_RECOVERY_INVENTORY_ACTUAL_ADDON_BUILT',len(result),sha(result),
          'no_mutation=true previous_transaction_paths_unchanged=true')
if __name__=='__main__':main()
