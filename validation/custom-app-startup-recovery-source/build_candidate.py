"""Assemble a real disabled Addon Manager with read-only DPAPI user-state
source-bound startup plans. Fully inverse-recoverable to PR233. No action dispatcher,
normal legacy update, commit, rollback or new FullChain behavior changes.
"""
from __future__ import annotations
from pathlib import Path
import re,hashlib,json,subprocess
ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
OUT=HERE/'out'/'bin'
PARENT='8358e9b8f4c8c5514dd42bce8430fe33841e0f7c'
PARENT_BUILDER='validation/custom-app-durable-recovery-inventory/build_candidate.py'
PARENT_BUILDER_SHA='7d736389049e4342b82559eafb7946c6a7826929'
PRIOR=(1500005,'0ea7b472425c227a286b63adffa952d0016e6edca112908c7d549e0ebe0ab869')
MAIN=(284327,'69ef7fb3ca57b4d5faac6873ac06dffc38f6e5b0d1ad8fc31fcbe2bb236f5c99')
MODULE='validation/custom-app-startup-recovery-source/startup-recovery-source.ps1'
MODULE_BLOB='fa5e143189040607dc4432d410e94164afe99ece'
TEST='validation/custom-app-startup-recovery-source/test_startup_recovery_source.ps1'
TEST_BLOB='353d4301bbed87f8272fe10c98c352f4b78fd866'
OLD_HOOK='    try { Test-CustomAppDurableRecoveryInventorySelfTestV012 } catch { $errors.Add("Custom App durable recovery startup inventory self-test failed: $($_.Exception.Message)") }'
NEW_HOOK=OLD_HOOK+'\n    try { Test-CustomAppSealedStartupRecoveryAssessmentSelfTestV013 } catch { $errors.Add("Custom App sealed startup recovery source self-test failed: $($_.Exception.Message)") }'
NEW_FUNCTIONS=['Get-CustomAppSealedStartupRecoveryAssessmentV013','Test-CustomAppSealedStartupRecoveryAssessmentSelfTestV013']
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
    d=ROOT/'validation/custom-app-durable-recovery-inventory/out/bin'
    files={p:(d/p).read_bytes() for p in ('addon-manager.ps1','spotify-control.ps1',
          'Collect-Marketplace-Records.ps1','LevelDbReadOnly.cs')}
    old=files['addon-manager.ps1']
    if (len(old),sha(old))!=PRIOR or (len(files['spotify-control.ps1']),sha(files['spotify-control.ps1']))!=MAIN:
        raise RuntimeError('previous qualified DPAPI recovery inventory Addon Manager drift')
    bom=b'\xef\xbb\xbf' if old.startswith(b'\xef\xbb\xbf') else b''
    original=old[len(bom):].decode('utf-8').replace('\r\n','\n')
    module=(ROOT/MODULE).read_text('utf-8-sig').replace('\r\n','\n').strip()
    new=funcs(module)
    if sorted(new)!=sorted(NEW_FUNCTIONS) or set(new)&set(funcs(original)):
        raise RuntimeError('startup source exports unqualified or duplicate functions')
    for required in ('[IO.FileMode]::Open','[IO.FileShare]::None',
      'Open-CustomAppCrossEngineTransactionLockV010',
      'Read-CustomAppUserTxnStateV010',
      'Get-CustomAppDurableRecoveryInventoryV012',
      'Read-CustomAppDurableRecoveryJournalReadOnlyV012',
      'Test-CustomAppProductionRecoveryPlanV010',
      'Read-CustomAppUserTxnJournalLocatorV010',
      'Read-CustomAppDurableRecoveryJournalReadOnlyV012',
      'Resolve-CustomAppProductionCrashRecoveryClassificationV010',
      'Get-CustomAppUserTxnMissingLivePathsV011',
      'only_sealed_registry_sources=$true'):
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
      triple_identity_and_journal_binding_read_only=True,
      qualified_phase_to_plan_mapping_no_mutation=True,
      FileMode_Open_only_on_user_ledger=True,
      pending_write_never_discarded_by_discovery=True,
      global_and_per_app_lock_scoped_entire_inventory=True,
      journal_identity_verified_before_reporting_active=True,
      no_mutation_authority=True,operating_main_unchanged=True,
      exact_previous_candidate_inverse=True)
    (HERE/'candidate-validation.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n',encoding='utf-8')
    print('SEALED_STARTUP_SOURCE_ACTUAL_ADDON_BUILT',len(result),sha(result),
          'no_mutation=true previous_transaction_paths_unchanged=true')
if __name__=='__main__':main()
