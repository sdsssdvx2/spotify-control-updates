"""Validation-only conflict protection of all actual legacy mutating action
entrypoints plus a read-only pre-enrollment check for the new journal engine.
The normal new FullChain is still hard-disabled. All prior candidate bytes
are inverse-recoverable without semantic replacements.
"""
from __future__ import annotations
import hashlib,json,re,subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
OUT=HERE/'out'/'bin'
PARENT='0af3158ea0e3878fbc12dc97857b87a8918934db'
PARENT_BUILDER='validation/custom-app-missing-live-recovery/build_candidate.py'
PARENT_BLOB='00390c7764bce40fd3c5e001cff69a7430c4529f'
PARENT_ADDON=(1472525,'04a398fce2c7c11ebf292ec2ad5aa99b5a9c0a321d1367fe328da4b7b79fa829')
PARENT_SPOTIFY=(284327,'69ef7fb3ca57b4d5faac6873ac06dffc38f6e5b0d1ad8fc31fcbe2bb236f5c99')
MODULE='validation/custom-app-legacy-journal-settlement-barrier/legacy-settlement-barrier.ps1'
MODULE_SHA='ca79b192c99cca29422878caa584075bd39bc845'
TEST='validation/custom-app-legacy-journal-settlement-barrier/test_legacy_settlement_barrier.ps1'
TEST_SHA='95b90f1c1d8b631973bc6994e69087ee911d6cbc'
OLD_HOOK='    try { Test-CustomAppMissingLiveRecoverySelfTestV011 } catch { $errors.Add("Custom App interrupted live path recovery self-test failed: $($_.Exception.Message)") }'
NEW_HOOK=OLD_HOOK+'\n    try { Test-CustomAppLegacySettlementBarrierSelfTestV011 } catch { $errors.Add("Custom App dual-engine legacy settlement barrier self-test failed: $($_.Exception.Message)") }'
NAMES=('Assert-CustomAppLegacySettlementExclusiveV011','Assert-CustomAppNewJournalLegacyLedgerClosedV011','Test-CustomAppLegacySettlementBarrierSelfTestV011')

def sha(x):return hashlib.sha256(x).hexdigest()
def gitpin(ref,p,expected):
    got=subprocess.check_output(['git','rev-parse',f'{ref}:{p}'],cwd=ROOT,text=True).strip()
    if got!=expected:raise RuntimeError('SHA pinned qualified source drift '+p)
def once(s,old,new,label):
    n=s.count(old)
    if n!=1:raise RuntimeError(f'{label}: expected 1 boundary found {n}')
    return s.replace(old,new,1)
def funcs(s):return re.findall(r'(?im)^[ \t]*function\s+([A-Za-z0-9_-]+)\s*\{',s)
def block(s,n):
    m=re.search(r'(?im)^[ \t]*function\s+'+re.escape(n)+r'\s*\{',s)
    if not m:raise RuntimeError('missing qualified original function '+n)
    z=re.search(r'(?im)^[ \t]*function\s+[A-Za-z0-9_-]+\s*\{',s[m.end():])
    return s[m.start():m.end()+z.start() if z else len(s))
def main():
    for ref,p,expected in ((PARENT,PARENT_BUILDER,PARENT_BLOB),
                           ('HEAD',MODULE,MODULE_SHA),('HEAD',TEST,TEST_SHA)):
        gitpin(ref,p,expected)
    subprocess.check_call(['python',str(ROOT/PARENT_BUILDER)],cwd=ROOT)
    p=ROOT/'validation/custom-app-missing-live-recovery/out/bin'
    files={n:(p/n).read_bytes() for n in (
        'addon-manager.ps1','spotify-control.ps1','Collect-Marketplace-Records.ps1','LevelDbReadOnly.cs')}
    addon=files['addon-manager.ps1'];spotify=files['spotify-control.ps1']
    if (len(addon),sha(addon))!=PARENT_ADDON or (len(spotify),sha(spotify))!=PARENT_SPOTIFY:
        raise RuntimeError('previous real signed ZIP missing-live candidate differs')
    bom=b'\xef\xbb\xbf' if addon.startswith(b'\xef\xbb\xbf') else b''
    original=addon[len(bom):].decode('utf-8').replace('\r\n','\n')
    ext=(ROOT/MODULE).read_text('utf-8-sig').replace('\r\n','\n').strip()
    if sorted(funcs(ext))!=sorted(NAMES) or (set(funcs(ext))&set(funcs(original))):
        raise RuntimeError('unexpected duplicate or unreviewed safety functions')
    if 'requires_cross_engine_lock_before_enrollment=$true' not in ext or 'safe_to_enroll=$false' not in ext:
        raise RuntimeError('read-only new engine preflight cannot grant authority')
    for forbidden in ('File]::Delete','Remove-Item','CreateDirectory(','Move-Item',
                      'Invoke-CustomAppProductionFullChainV010','Invoke-AtomicDirectorySwap',
                      '$script:CustomAppProductionPipelineEnabled = $true'):
        if forbidden in ext:raise RuntimeError('legacy-new compatibility module attempts mutation '+forbidden)
    payload=ext+'\n\n'
    candidate=once(original,'function Test-Due {',payload+'function Test-Due {','two-way guard injection')
    barriers={}
    for n in ('Commit-LastTransaction','Rollback-LastTransaction'):
        before='function '+n+' {\n'
        after=before+'    [void](Assert-CustomAppLegacySettlementExclusiveV011)\n'
        candidate=once(candidate,before,after,'legacy '+n+' first statement')
        barriers[n]=(before,after)
    candidate=once(candidate,OLD_HOOK,NEW_HOOK,'selftest hook')
    for n in ('Commit-LastTransaction','Rollback-LastTransaction'):
        b=block(candidate,n)
        assert b.startswith(barriers[n][1])
        for side_effect in ('Test-PathSafe $TransactionPath','Get-Process Spotify'):
            if side_effect not in b or b.index('Assert-CustomAppLegacySettlementExclusiveV011')>=b.index(side_effect):
                raise RuntimeError('legacy '+n+' mutating or parsing before journal presence guard '+side_effect)
    if block(candidate,'Update-AutoApps')!=block(original,'Update-AutoApps'):
        raise RuntimeError('original Update-AutoApps previous exclusive fence modified')
    if block(candidate,'Invoke-CustomAppProductionFullChainV010')!=block(original,'Invoke-CustomAppProductionFullChainV010'):
        raise RuntimeError('previous hard-disabled FullChain changed')
    if 'Custom App production full-chain execution is intentionally unavailable in integration-only candidate.' not in block(candidate,'Invoke-CustomAppProductionFullChainV010'):
        raise RuntimeError('missing prior hard-disable')
    for n in set(funcs(original)):
        if n in ('Commit-LastTransaction','Rollback-LastTransaction',
                 'Invoke-AddonSelfTest','Test-CustomAppMissingLiveRecoverySelfTestV011'):
            continue
        if block(candidate,n)!=block(original,n):
            raise RuntimeError('unqualified original function modified '+n)
    inverse=once(candidate,NEW_HOOK,OLD_HOOK,'reverse SelfTest')
    for n in ('Rollback-LastTransaction','Commit-LastTransaction'):
        before,after=barriers[n];inverse=once(inverse,after,before,'reverse '+n)
    inverse=once(inverse,payload,'','reverse safety module')
    if inverse!=original:raise RuntimeError('not exactly inverse-recoverable to prior qualified candidate')
    if candidate.count('$script:CustomAppProductionPipelineEnabled = $true')!=original.count('$script:CustomAppProductionPipelineEnabled = $true'):
        raise RuntimeError('new production authority')
    output=bom+candidate.replace('\n','\r\n').encode('utf-8')
    files['addon-manager.ps1']=output
    OUT.mkdir(parents=True,exist_ok=True)
    for name,data in files.items():(OUT/name).write_bytes(data)
    report=dict(schema=1,qualified_parent=PARENT,old_addon_sha256=sha(addon),
        addon_sha256=sha(output),addon_size=len(output),spotify_sha256=sha(spotify),
        exact_frozen_parent_inverse=True,original_fullchain_hard_disabled=True,
        original_Update_AutoApps_unchanged=True,
        CommitLast_first_statement_exclusivity=True,RollbackLast_first_statement_exclusivity=True,
        legacy_ledger_untouched_by_new_journal_preflight=True,
        new_engine_preflight_never_grants_enrollment=True,
        cross_engine_atomic_lock_not_yet_implemented=True,
        normal_new_auto_update_enabled=False,operating_main_changed=False,
        installed_user_spotify_changed=False)
    (HERE/'candidate-validation.json').write_text(json.dumps(report,sort_keys=True,indent=2)+'\n',encoding='utf-8')
    print('LEGACY_AND_NEW_JOURNAL_DUAL_SETTLEMENT_ACTUAL_ADDON_BUILT',len(output),sha(output),
          'original_legacy_update_preserved=true no_new_auto_update=true')
if __name__=='__main__':main()
