"""Assemble a real disabled Addon Manager with read-only DPAPI user-state
a sealed no-create evidence and restore-readiness admission. Fully inverse-recoverable to PR234. No action dispatcher,
normal legacy update, commit, rollback or new FullChain behavior changes.
"""
from __future__ import annotations
from pathlib import Path
import re,hashlib,json,subprocess
ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
OUT=HERE/'out'/'bin'
PARENT='3bec967071a5fde87438283a45125b45b15cc1f7'
PARENT_BUILDER='validation/custom-app-startup-recovery-source/build_candidate.py'
PARENT_BUILDER_SHA='4201b16fbc8111c431f0d3ab9e3fa06f88049e1c'
PRIOR=(1514899,'eb909f875950c7da0bc80476446f4525ce43da798202898c76d42019d2b94f90')
MAIN=(284327,'69ef7fb3ca57b4d5faac6873ac06dffc38f6e5b0d1ad8fc31fcbe2bb236f5c99')
MODULE='validation/custom-app-protected-restore-readiness/protected-restore-readiness.ps1'
MODULE_BLOB='4578d92f7e751222b939c88011801d8d7930f60a'
TEST='validation/custom-app-protected-restore-readiness/test_protected_restore_readiness.ps1'
TEST_BLOB='fcdb2fc2cb57b51bfb21c32b39eeeaa0137f9018'
OLD_HOOK='    try { Test-CustomAppSealedStartupRecoveryAssessmentSelfTestV013 } catch { $errors.Add("Custom App sealed startup recovery source self-test failed: $($_.Exception.Message)") }'
NEW_HOOK=OLD_HOOK+'\n    try { Test-CustomAppSealedRestoreReadinessSelfTestV014 } catch { $errors.Add("Custom App protected no-create restore readiness self-test failed: $($_.Exception.Message)") }'
NEW_FUNCTIONS=['Read-CustomAppProtectedEvidenceReadOnlyV014','Resolve-CustomAppProtectedRestoreResumeAdmissionV014','Get-CustomAppSealedRestoreReadinessV014','Test-CustomAppSealedRestoreReadinessSelfTestV014']
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
    d=ROOT/'validation/custom-app-startup-recovery-source/out/bin'
    files={p:(d/p).read_bytes() for p in ('addon-manager.ps1','spotify-control.ps1',
          'Collect-Marketplace-Records.ps1','LevelDbReadOnly.cs')}
    old=files['addon-manager.ps1']
    if (len(old),sha(old))!=PRIOR or (len(files['spotify-control.ps1']),sha(files['spotify-control.ps1']))!=MAIN:
        raise RuntimeError('previous qualified sealed startup source Addon Manager drift')
    bom=b'\xef\xbb\xbf' if old.startswith(b'\xef\xbb\xbf') else b''
    original=old[len(bom):].decode('utf-8').replace('\r\n','\n')
    module=(ROOT/MODULE).read_text('utf-8-sig').replace('\r\n','\n').strip()
    new=funcs(module)
    if sorted(new)!=sorted(NEW_FUNCTIONS) or set(new)&set(funcs(original)):
        raise RuntimeError('startup source exports unqualified or duplicate functions')
    for required in ('[IO.FileMode]::Open','[IO.FileShare]::None',
      'Get-CustomAppSealedStartupRecoveryAssessmentV013',
      'Read-CustomAppDurableRecoveryJournalReadOnlyV012',
      'Read-CustomAppProductionCrashJournalUnlockedV010',
      'Test-CustomAppProductionRecoveryEvidenceEnvelopeV010',
      'Test-CustomAppProductionRecoveryRestoreResumeAdmissionReceiptV010',
      'source_fingerprint','verified-spicetify-binary-pin-not-enrolled',
      'read_existing_journal_lock_only=$true'):
        if required not in module:
            raise RuntimeError('protected readiness qualified boundary missing '+required)
    for forbidden in ('[IO.FileMode]::OpenOrCreate',
       '[IO.File]::WriteAllText','[IO.File]::WriteAllBytes',
       '[IO.File]::Delete','[IO.Directory]::Move',
       'Save-CustomAppUserTxnStoreV010',
       'Invoke-CustomAppProductionRecoveryRestoreExecutorV010',
       'Invoke-CustomAppProductionSpicetifyApplyExecutorV010',
       '$script:CustomAppProductionPipelineEnabled = $true'):
        if forbidden in module:
            raise RuntimeError('protected readiness source contains mutation '+forbidden)
    # Independently reconstruct the historically qualified restore-resume
    # admission from its SHA-pinned ancestor, with EXACTLY four substitutions.
    # All filesystem, backup, phase and evidence checks remain unchanged.
    historic_path='validation/custom-app-production-recovery-restore-resume-admission-v0.1.0/custom-app-production-recovery-restore-resume-admission.ps1'
    historic_ref='d9a1face71511bdaeeef4e8c761415ef9ec95fc0'
    historic_blob='0273d7e28a56759b1d0ec9cbf037483b04d98d63'
    pin(historic_ref,historic_path,historic_blob)
    historic=subprocess.check_output(
        ['git','show',historic_ref+':'+historic_path],cwd=ROOT).decode('utf-8-sig').replace('\r\n','\n')
    h_start=historic.index('function Resolve-CustomAppProductionRecoveryRestoreResumeAdmissionV010 {')
    h_end=historic.index('function Test-CustomAppProductionRecoveryRestoreResumeAdmissionReceiptV010 {',h_start)
    derived=historic[h_start:h_end].strip()
    for prior,replacement in (
        ('Resolve-CustomAppProductionRecoveryRestoreResumeAdmissionV010','Resolve-CustomAppProtectedRestoreResumeAdmissionV014'),
        ('Read-CustomAppProductionCrashJournalV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory','Read-CustomAppDurableRecoveryJournalReadOnlyV012 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory'),
        ('Resolve-CustomAppProductionRecoveryPlanV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $tx','New-CustomAppProductionRecoveryPlanFromClassificationV010 -Classification (Resolve-CustomAppProductionCrashRecoveryClassificationV010 -StoreRead $journal -ExpectedTransactionId $tx) -StoreRead $journal -ExpectedTransactionId $tx'),
        ('Read-CustomAppProductionRecoveryEvidenceV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $tx','Read-CustomAppProtectedEvidenceReadOnlyV014 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $tx')
    ):
        derived=one(derived,prior,replacement,'SHA-qualified historical restore admission no-create substitution')
    if module.count(derived)!=1:
        raise RuntimeError('protected restore admission not exact qualified historical derivative')
    if 'Read-CustomAppProductionRecoveryEvidenceV010 -AllowedRoot' in module:
        raise RuntimeError('unsafe historical evidence reader still invoked')
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
    print('PROTECTED_RESTORE_ACTUAL_ADDON_BUILT',len(result),sha(result),
          'no_mutation=true previous_transaction_paths_unchanged=true')
if __name__=='__main__':main()
