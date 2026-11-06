"""Assemble a real disabled Addon Manager with read-only DPAPI user-state
immutable pre-mutation DPAPI Spicetify exe/config enrollment and restart binding. Fully inverse-recoverable to PR237. No action dispatcher,
normal legacy update, commit, rollback or new FullChain behavior changes.
"""
from __future__ import annotations
from pathlib import Path
import re,hashlib,json,subprocess
ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
OUT=HERE/'out'/'bin'
PARENT='3667b1435bcc8f19390730cedb424771b9cebca2'
PARENT_BUILDER='validation/custom-app-spicetify-passive-provenance/build_candidate.py'
PARENT_BUILDER_SHA='97ec42277aa23a22e9378b0d3063abb26ca02b77'
PRIOR=(1551626,'f5569c450025e307bb7d42ab6ac0774c0bb600ea7bd795575309106a28291eef')
MAIN=(284327,'69ef7fb3ca57b4d5faac6873ac06dffc38f6e5b0d1ad8fc31fcbe2bb236f5c99')
MODULE='validation/custom-app-spicetify-sealed-enrollment/spicetify-sealed-enrollment.ps1'
MODULE_BLOB='7140631a0da495ecf2c696e8188476b3e5c9f685'
TEST='validation/custom-app-spicetify-sealed-enrollment/test_spicetify_sealed_enrollment.ps1'
TEST_BLOB='7ba1573827fd16e550264609a05b3b23a86150fc'
OLD_HOOK='    try { Test-CustomAppSpicetifyPassiveObservationSelfTestV015 } catch { $errors.Add("Spicetify passive executable and config observation self-test failed: $($_.Exception.Message)") }'
NEW_HOOK=OLD_HOOK+'\n    try { Test-CustomAppSpicetifySealedPinSelfTestV016 } catch { $errors.Add("Spicetify sealed pre-mutation pin and restart verification self-test failed: $($_.Exception.Message)") }'
NEW_FUNCTIONS=['Assert-CustomAppSpicetifyPinLocksV016','Get-CustomAppSpicetifyPinFileV016','Read-CustomAppSpicetifySealedPinV016','Save-CustomAppSpicetifyPreMutationPinV016','Get-CustomAppSpicetifySealedPinReadinessV016','Test-CustomAppSpicetifySealedPinSelfTestV016']
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
    d=ROOT/'validation/custom-app-spicetify-passive-provenance/out/bin'
    files={p:(d/p).read_bytes() for p in ('addon-manager.ps1','spotify-control.ps1',
          'Collect-Marketplace-Records.ps1','LevelDbReadOnly.cs')}
    old=files['addon-manager.ps1']
    if (len(old),sha(old))!=PRIOR or (len(files['spotify-control.ps1']),sha(files['spotify-control.ps1']))!=MAIN:
        raise RuntimeError('previous qualified passive Spicetify evidence Addon Manager drift')
    bom=b'\xef\xbb\xbf' if old.startswith(b'\xef\xbb\xbf') else b''
    original=old[len(bom):].decode('utf-8').replace('\r\n','\n')
    module=(ROOT/MODULE).read_text('utf-8-sig').replace('\r\n','\n').strip()
    new=funcs(module)
    if sorted(new)!=sorted(NEW_FUNCTIONS) or set(new)&set(funcs(original)):
        raise RuntimeError('startup source exports unqualified or duplicate functions')
    for required in ('Write-CustomAppUserTxnBytesV010 -Path','immutable_create_new=$true',
        'Read-CustomAppDurableRecoveryJournalReadOnlyV012',
        'Get-CustomAppSealedStartupRecoveryAssessmentV013',
        'Read-CustomAppUserTxnJournalLocatorV010',
        'Assert-CustomAppCrossEngineTransactionLockHeldV010',
        'Assert-CustomAppSpicetifyPinLocksV016',
        '3563f26acd7527adc97e6c19272fa1b48ce976a913625d9804ac57d3c54fb4db',
        'spicetify-pin-enrollment-only-before-first-atomic-mutation',
        'spicetify-pin-executable-config-or-path-changed',
        'spicetify-pin-prepared-history-anchor-drift',
        'spicetify-pin-immutable-duplicate-denied',
        'Get-CustomAppSpicetifySealedPinReadinessV016',
        'production_execution_authorized=$false',
        'production_mutation_authorized=$false'):
        if required not in module:raise RuntimeError('spicetify-sealed-enrollment-source-contract-missing '+required)
    for forbidden in ('[IO.FileMode]::OpenOrCreate',
        '[IO.File]::Replace','[IO.File]::Delete',
        '[IO.Directory]::Move','Start-Process','Invoke-Expression',
        'Invoke-CustomAppProductionSpicetifyApplyExecutorV010',
        '$script:CustomAppProductionPipelineEnabled = $true',
        'Open-CustomAppUserTxnStoreV010 -Name'):
        if forbidden in module:
            raise RuntimeError('spicetify-sealed-enrollment-mutation-or-unsafe-open '+forbidden)
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
      historical_restore_admission_exact_safe_derivative=True,
      real_spicetify_execution_disabled=True,
      no_external_executable_path_or_sha_trusted=True,
      currentuser_spicetify_executable_and_config_observed_readonly=True,
      prepared_only_immutable_spicetify_pin_available=True,
      sealed_pin_restart_no_create_revalidation_available=True,
      exact_official_v2464_exe_sha_contract=True,
      no_restore_apply_authority_from_pin=True,
      evidence_and_journal_readers_FileMode_Open_only=True,
      no_caller_supplied_recovery_json_identity_or_plan=True,
      verified_spicetify_pin_required_for_apply_phase=True,
      triple_identity_and_journal_binding_read_only=True,
      qualified_phase_to_plan_mapping_no_mutation=True,
      FileMode_Open_only_on_user_ledger=True,
      pending_write_never_discarded_by_discovery=True,
      global_and_per_app_lock_scoped_entire_inventory=True,
      journal_identity_verified_before_reporting_active=True,
      no_mutation_authority=True,operating_main_unchanged=True,
      exact_previous_candidate_inverse=True)
    (HERE/'candidate-validation.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n',encoding='utf-8')
    print('SPICETIFY_SEALED_PIN_ACTUAL_ADDON_BUILT',len(result),sha(result),
          'no_mutation=true previous_transaction_paths_unchanged=true')
if __name__=='__main__':main()
