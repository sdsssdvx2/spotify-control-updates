"""Assemble a real disabled Addon Manager with read-only DPAPI user-state
real per-user Spicetify executable/config SHA-only observation. Fully inverse-recoverable to PR235. No action dispatcher,
normal legacy update, commit, rollback or new FullChain behavior changes.
"""
from __future__ import annotations
from pathlib import Path
import re,hashlib,json,subprocess
ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
OUT=HERE/'out'/'bin'
PARENT='7d1969638e995ebbf4c01429f44090d3e9297e71'
PARENT_BUILDER='validation/custom-app-protected-restore-readiness/build_candidate.py'
PARENT_BUILDER_SHA='e5c2f48631cea5848a902a41abfd96acf9d50349'
PRIOR=(1543148,'a14baefb8de54c73a549132017e1090e69f8694f170152e6be40f8291d405638')
MAIN=(284327,'69ef7fb3ca57b4d5faac6873ac06dffc38f6e5b0d1ad8fc31fcbe2bb236f5c99')
MODULE='validation/custom-app-spicetify-passive-provenance/spicetify-passive-provenance.ps1'
MODULE_BLOB='ea07bdabc3ad318b0b80cc4e81560bb6faded225'
TEST='validation/custom-app-spicetify-passive-provenance/test_spicetify_passive_provenance.ps1'
TEST_BLOB='e6249715e7d7cdfa5e526d24f87349f190805ad4'
OLD_HOOK='    try { Test-CustomAppSealedRestoreReadinessSelfTestV014 } catch { $errors.Add("Custom App protected no-create restore readiness self-test failed: $($_.Exception.Message)") }'
NEW_HOOK=OLD_HOOK+'\n    try { Test-CustomAppSpicetifyPassiveObservationSelfTestV015 } catch { $errors.Add("Spicetify passive executable and config observation self-test failed: $($_.Exception.Message)") }'
NEW_FUNCTIONS=['Get-CustomAppSpicetifyPassiveFileSha256V015','Get-CustomAppSpicetifyPassiveObservationV015','Test-CustomAppSpicetifyPassiveObservationSelfTestV015']
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
    d=ROOT/'validation/custom-app-protected-restore-readiness/out/bin'
    files={p:(d/p).read_bytes() for p in ('addon-manager.ps1','spotify-control.ps1',
          'Collect-Marketplace-Records.ps1','LevelDbReadOnly.cs')}
    old=files['addon-manager.ps1']
    if (len(old),sha(old))!=PRIOR or (len(files['spotify-control.ps1']),sha(files['spotify-control.ps1']))!=MAIN:
        raise RuntimeError('previous qualified no-create restore readiness Addon Manager drift')
    bom=b'\xef\xbb\xbf' if old.startswith(b'\xef\xbb\xbf') else b''
    original=old[len(bom):].decode('utf-8').replace('\r\n','\n')
    module=(ROOT/MODULE).read_text('utf-8-sig').replace('\r\n','\n').strip()
    new=funcs(module)
    if sorted(new)!=sorted(NEW_FUNCTIONS) or set(new)&set(funcs(original)):
        raise RuntimeError('startup source exports unqualified or duplicate functions')
    for required in ('[IO.FileMode]::Open','[IO.FileShare]::Read',
       'Open-CustomAppCrossEngineTransactionLockV010',
       'Assert-CustomAppCrossEngineTransactionLockHeldV010',
       'Assert-CustomAppUserTxnNoReparseV010',
       'config-xpui.ini','spicetify.exe',
       "GetEnvironmentVariable('SPICETIFY_CONFIG')",
       "GetEnvironmentVariable('SPICETIFY_STATE')",
       'binary_trusted=$false','enrolled_executable_pin=$false',
       'config_identity_authenticated=$false','recovery_apply_eligible=$false',
       'production_execution_authorized=$false',
       'production_mutation_authorized=$false'):
        if required not in module:raise RuntimeError('Spicetify passive provenance safety contract missing '+required)
    for forbidden in ('[IO.FileMode]::OpenOrCreate',
       '[IO.File]::WriteAllText','[IO.File]::WriteAllBytes','[IO.File]::Delete',
       'Remove-Item','Start-Process','Invoke-Expression','Invoke-WebRequest',
       'Invoke-RestMethod','Invoke-CustomAppProductionSpicetifyApplyExecutorV010',
       'Invoke-CustomAppProductionFullChainV010','$script:CustomAppProductionPipelineEnabled = $true'):
        if forbidden in module:
            raise RuntimeError('Spicetify passive provenance contains mutation/execute primitive '+forbidden)
    if module.count('Get-CustomAppSpicetifyPassiveObservationV015') < 2:
        raise RuntimeError('Spicetify passive source missing observation and selftest')
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
    print('SPICETIFY_PASSIVE_ACTUAL_ADDON_BUILT',len(result),sha(result),
          'no_mutation=true previous_transaction_paths_unchanged=true')
if __name__=='__main__':main()
