"""Validation-only shared per-user legacy/new transaction lock.
Build the exact previous signed-ZIP/DPAPI candidate, add one held
FileShare.None lock around all three actual normal legacy actions, and
provide a disabled new-journal pre-enrollment helper using the SAME lock.
No normal new FullChain routing or production changes.
"""
from __future__ import annotations
import hashlib,json,re,subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
OUT=HERE/'out'/'bin'
PARENT='e86cdea0b19b5a8e0b2cb22c59415185e512fdf2'
PARENT_BUILDER='validation/custom-app-legacy-journal-settlement-barrier/build_candidate.py'
PARENT_BLOB='0e57ae759ca37ee51de7b8d8c784212f1794c3bf'
OLD_ADDON=(1478124,'fbcf51a2bf7cb11a0a50cdf40934f0eaa14121d1355e2e26997ee431527d4b33')
OLD_SPOTIFY=(284327,'69ef7fb3ca57b4d5faac6873ac06dffc38f6e5b0d1ad8fc31fcbe2bb236f5c99')
MODULE='validation/custom-app-cooperative-cross-engine-lock/cross-engine-transaction-lock.ps1'
MODULE_BLOB='5139a8c9f461b892fbd30d7dfebec97816863844'
TEST='validation/custom-app-cooperative-cross-engine-lock/test_cross_engine_lock.ps1'
TEST_BLOB='697b296ad7b9632bdc800747cfb5f5c51a8a4324'
OLD_HOOK='    try { Test-CustomAppLegacySettlementBarrierSelfTestV011 } catch { $errors.Add("Custom App dual-engine legacy settlement barrier self-test failed: $($_.Exception.Message)") }'
NEW_HOOK=OLD_HOOK+'\n    try { Test-CustomAppCrossEngineTransactionLockSelfTestV010 } catch { $errors.Add("Custom App cooperative cross-engine transaction lock self-test failed: $($_.Exception.Message)") }'
SWITCH_BEFORE='    switch ($Action) {\n'
SWITCH_AFTER='''    $script:CustomAppCrossEngineActionLock=$null
    try {
        if ($Action -in @("Update","CommitLast","RollbackLast")) {
            $script:CustomAppCrossEngineActionLock=Open-CustomAppCrossEngineTransactionLockV010
        }
        switch ($Action) {
'''
CLOSE_BEFORE='''    }
    exit 0
}
catch {
'''
CLOSE_AFTER='''        }
    } finally {
        if ($null -ne $script:CustomAppCrossEngineActionLock) {
            $script:CustomAppCrossEngineActionLock.lock_handle.Dispose()
            $script:CustomAppCrossEngineActionLock=$null
        }
    }
    exit 0
}
catch {
'''
EXPECTED_FUNCTIONS=('Open-CustomAppCrossEngineTransactionLockV010',
 'Assert-CustomAppCrossEngineTransactionLockHeldV010',
 'Open-CustomAppNewJournalCrossEnginePreflightV010',
 'Test-CustomAppCrossEngineTransactionLockSelfTestV010')
def sha(blob):return hashlib.sha256(blob).hexdigest()
def pin(ref,path,expected):
    actual=subprocess.check_output(['git','rev-parse',f'{ref}:{path}'],cwd=ROOT,text=True).strip()
    if actual!=expected:raise RuntimeError('pinned verified source changed '+path+' '+actual)
def one(s,old,new,label):
    n=s.count(old)
    if n!=1:raise RuntimeError(f'{label} nonunique old anchor={n}')
    return s.replace(old,new,1)
def functions(s):return re.findall(r'(?im)^[ \t]*function\s+([A-Za-z0-9_-]+)\s*\{',s)
def block(s,n):
    m=re.search(r'(?im)^[ \t]*function\s+'+re.escape(n)+r'\s*\{',s)
    if not m:raise RuntimeError('original function absent '+n)
    next_fn=re.search(r'(?im)^[ \t]*function\s+[-A-Za-z0-9_]+\s*\{',s[m.end():])
    return s[m.start():(m.end()+next_fn.start() if next_fn else len(s))]
def main():
    for ref,p,b in ((PARENT,PARENT_BUILDER,PARENT_BLOB),
                    ('HEAD',MODULE,MODULE_BLOB),('HEAD',TEST,TEST_BLOB)):
        pin(ref,p,b)
    subprocess.check_call(['python',str(ROOT/PARENT_BUILDER)],cwd=ROOT)
    old=ROOT/'validation/custom-app-legacy-journal-settlement-barrier/out/bin'
    files={n:(old/n).read_bytes() for n in ('addon-manager.ps1','spotify-control.ps1',
       'Collect-Marketplace-Records.ps1','LevelDbReadOnly.cs')}
    addon=files['addon-manager.ps1'];main=files['spotify-control.ps1']
    if (len(addon),sha(addon))!=OLD_ADDON or (len(main),sha(main))!=OLD_SPOTIFY:
        raise RuntimeError('previous fully tested legacy settlement bundle does not match')
    bom=b'\xef\xbb\xbf' if addon.startswith(b'\xef\xbb\xbf') else b''
    original=addon[len(bom):].decode('utf-8').replace('\r\n','\n')
    module=(ROOT/MODULE).read_text('utf-8-sig').replace('\r\n','\n').strip()
    names=functions(module)
    if sorted(names)!=sorted(EXPECTED_FUNCTIONS) or (set(names)&set(functions(original))):
        raise RuntimeError('new cross-engine lock unexpected exports or name collision')
    for required in ('[IO.FileShare]::None','[IO.FileMode]::OpenOrCreate',
                     'Assert-CustomAppUserTxnPrivateDirectoryV010',
                     'Assert-CustomAppNewJournalLegacyLedgerClosedV011',
                     'cross-engine-lock-busy-or-unavailable',
                     'requires_cross_engine_lock_before_enrollment'):
        if required not in module:raise RuntimeError('critical cross-lock assertion missing '+required)
    for forbidden in ('Invoke-CustomAppProductionFullChainV010',
                      '$script:CustomAppProductionPipelineEnabled = $true',
                      'Commit-CustomAppUserTxnBoundJournalTerminalV010',
                      'Invoke-AtomicDirectorySwap','[IO.Directory]::Move',
                      'Remove-Item '):
        if forbidden in module:raise RuntimeError('new cross-engine lock unexpectedly performs mutation '+forbidden)
    payload=module+'\n\n'
    changed=one(original,'function Test-Due {',payload+'function Test-Due {','insert distinct currentuser lock')
    changed=one(changed,OLD_HOOK,NEW_HOOK,'selftest registration')
    changed=one(changed,SWITCH_BEFORE,SWITCH_AFTER,'actual normal action switch first lock')
    changed=one(changed,CLOSE_BEFORE,CLOSE_AFTER,'normal action switch always releases lock')
    if 'if ($Action -in @("Update","CommitLast","RollbackLast"))' not in changed:
        raise RuntimeError('actual Update CommitLast RollbackLast not all scoped')
    for name in ('Update-AutoApps','Commit-LastTransaction','Rollback-LastTransaction',
                 'Invoke-CustomAppProductionFullChainV010'):
        if block(changed,name)!=block(original,name):
            raise RuntimeError('prior qualified app mutation/restore body changed '+name)
    if 'Custom App production full-chain execution is intentionally unavailable in integration-only candidate.' not in block(changed,'Invoke-CustomAppProductionFullChainV010'):
        raise RuntimeError('FullChain hard disable unexpectedly lost')
    for name in set(functions(original)):
        if name in ('Invoke-AddonSelfTest','Test-CustomAppLegacySettlementBarrierSelfTestV011'):continue
        if block(changed,name)!=block(original,name):
            raise RuntimeError('previous source function changed '+name)
    inverse=one(changed,CLOSE_AFTER,CLOSE_BEFORE,'reverse action finally')
    inverse=one(inverse,SWITCH_AFTER,SWITCH_BEFORE,'reverse acquire')
    inverse=one(inverse,NEW_HOOK,OLD_HOOK,'reverse selftest')
    inverse=one(inverse,payload,'','reverse module')
    if inverse!=original:raise RuntimeError('previous candidate not EXACTLY restored')
    if changed.count('$script:CustomAppProductionPipelineEnabled = $true')!=original.count('$script:CustomAppProductionPipelineEnabled = $true'):
        raise RuntimeError('production new-engine authority drift')
    result=bom+changed.replace('\n','\r\n').encode('utf-8')
    files['addon-manager.ps1']=result
    OUT.mkdir(parents=True,exist_ok=True)
    for name,blob in files.items():(OUT/name).write_bytes(blob)
    report=dict(schema=1,qualified_parent=PARENT,old_addon_sha256=sha(addon),
       candidate_sha256=sha(result),candidate_bytes=len(result),spotify_sha256=sha(main),
       exact_qualified_parent_inverse=True,prior_fullchain_hard_disabled=True,
       exact_old_transaction_functions_preserved=True,
       scoped_actual_legacy_actions=['Update','CommitLast','RollbackLast'],
       separate_legacy_and_new_engine_shared_lock_path=True,
       currentuser_private_acl_and_fileshare_none=True,
       old_new_enrollment_bounded_preflight_only=True,
       full_new_engine_runtime_not_wired=True,spicetify_not_executed=True,
       existing_spotify_not_touched=True,operating_main_unchanged=True)
    (HERE/'candidate-validation.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n',encoding='utf-8')
    print('COOPERATIVE_CROSS_ENGINE_REAL_ADDON_BUILT',len(result),sha(result),
          'legacy_actions_scoped=true normal_new_engine_disabled=true')
if __name__=='__main__':main()
