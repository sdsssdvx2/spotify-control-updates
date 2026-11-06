"""Append only a DPAPI journal locator + explicit verified terminal wrapper to
the exact last Windows-proven normal-entrypoint disabled Addon Manager.
No production update action, no old engine change, exact inverse proof.
"""
from __future__ import annotations
import hashlib,json,re,subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
OUT=HERE/'out'/'bin'
PARENT='68dcd4a3dea9602a89eb10f6411bd2d4fe2e5c23'
PARENT_BUILDER='validation/custom-app-normal-entrypoint-transaction-integration/build_candidate.py'
PARENT_BUILDER_SHA='49392b2d345b90e82f383583dbcf1f4e41a00788'
EXPECTED_ADDON=(1453028,'0cb2362dd14772f19ba2970e5f4c2bc07bf0512c0de31494af7b01cb2a98fdd6')
EXPECTED_SPOTIFY=(284327,'69ef7fb3ca57b4d5faac6873ac06dffc38f6e5b0d1ad8fc31fcbe2bb236f5c99')
MODULE='validation/custom-app-journal-restart-locator/user-journal-locator.ps1'
MODULE_SHA='bb29fe26a3d58f63eb70188bd24ad0782db07efc'
DERIVE='validation/custom-app-journal-restart-locator/derive_signed_real_zip_locator_e2e.py'
DERIVE_SHA='af4ddbe703c8c0408ea12f0fdd95aff5297d9a14'
TEST='validation/custom-app-journal-restart-locator/test_user_journal_locator.ps1'
TEST_SHA='4a865eeac38dd26cada4144af8c7f4d0cdd6411e'
PREVIOUS_HOOK='    try { Test-CustomAppNormalUpdateEngineExclusivitySelfTestV010 } catch { $errors.Add("Custom App normal update two-engine safety self-test failed: $($_.Exception.Message)") }'
NEW_HOOK=PREVIOUS_HOOK+'\n    try { Test-CustomAppUserJournalLocatorSelfTestV010 } catch { $errors.Add("Custom App user journal restart locator self-test failed: $($_.Exception.Message)") }'
SELFTEST=r"""function Test-CustomAppUserJournalLocatorSelfTestV010 {
    if([bool]$script:CustomAppProductionPipelineEnabled){throw 'Journal locator unexpectedly enabled production FullChain'}
    foreach($name in @('Bind-CustomAppUserTxnJournalLocatorV010','Read-CustomAppUserTxnJournalLocatorV010','Commit-CustomAppUserTxnBoundJournalTerminalV010')){
        if(-not(Get-Command $name -CommandType Function -ErrorAction SilentlyContinue)){throw ('Missing journal locator '+$name)}
    }
    Write-Host 'CUSTOM_APP_USER_JOURNAL_LOCATOR_SELFTEST_PASS per_id_dpapi_locator=true normal_update_unchanged=true fullchain_disabled=true'
}"""
def sha(b):return hashlib.sha256(b).hexdigest()
def pin(ref,path,expected):
    x=subprocess.check_output(['git','rev-parse',f'{ref}:{path}'],cwd=ROOT,text=True).strip()
    if x!=expected:raise RuntimeError(f'qualified blob drift {path}: {x}')
def unique(s,a,b,label):
    n=s.count(a)
    if n!=1:raise RuntimeError(f'{label}: expected one anchor, found {n}')
    return s.replace(a,b,1)
def funcs(s):return re.findall(r'(?im)^[ \t]*function\s+([A-Za-z0-9_-]+)\s*\{',s)
def block(s,n):
    m=re.search(r'(?im)^[ \t]*function\s+'+re.escape(n)+r'\s*\{',s)
    if not m:raise RuntimeError('missing qualified prior function '+n)
    z=re.search(r'(?im)^[ \t]*function\s+[A-Za-z0-9_-]+\s*\{',s[m.end():])
    return s[m.start():m.end()+z.start() if z else len(s)]
def main():
    for ref,path,expected in ((PARENT,PARENT_BUILDER,PARENT_BUILDER_SHA),
                              ('HEAD',MODULE,MODULE_SHA),('HEAD',DERIVE,DERIVE_SHA),
                              ('HEAD',TEST,TEST_SHA)):pin(ref,path,expected)
    subprocess.check_call(['python',str(ROOT/PARENT_BUILDER)],cwd=ROOT)
    folder=ROOT/'validation/custom-app-normal-entrypoint-transaction-integration/out/bin'
    files={name:(folder/name).read_bytes() for name in
           ('addon-manager.ps1','spotify-control.ps1','Collect-Marketplace-Records.ps1','LevelDbReadOnly.cs')}
    addon=files['addon-manager.ps1'];spotify=files['spotify-control.ps1']
    if (len(addon),sha(addon))!=EXPECTED_ADDON or (len(spotify),sha(spotify))!=EXPECTED_SPOTIFY:
        raise RuntimeError('qualified previous normal-entrypoint candidate bytes drift')
    bom=b'\xef\xbb\xbf' if addon.startswith(b'\xef\xbb\xbf') else b''
    original=addon[len(bom):].decode('utf-8').replace('\r\n','\n')
    ext=(ROOT/MODULE).read_text('utf-8-sig').replace('\r\n','\n').strip()
    names=funcs(ext)
    expected=['Assert-CustomAppUserTxnJournalLocalPathV010',
              'Get-CustomAppUserTxnJournalLocatorFileV010',
              'Test-CustomAppUserTxnJournalLocatorRecordV010',
              'Read-CustomAppUserTxnJournalLocatorV010',
              'Bind-CustomAppUserTxnJournalLocatorV010',
              'Commit-CustomAppUserTxnBoundJournalTerminalV010']
    if sorted(names)!=sorted(expected) or (set(names)&set(funcs(original))):
        raise RuntimeError('journal locator unexpected exports or function collision')
    for key in ('[Security.Cryptography.ProtectedData]::Protect',
                '[Security.Cryptography.ProtectedData]::Unprotect',
                'DataProtectionScope]::CurrentUser','Read-CustomAppUserTxnStateV010',
                'Commit-CustomAppUserTxnVerifiedTerminalV011','Write-CustomAppUserTxnBytesV010',
                'user-journal-locator-missing-fail-closed'):
        if key not in ext:raise RuntimeError('private immutable locator required dependency absent '+key)
    for forbidden in ('Invoke-CustomAppProductionFullChainV010',
                      'Invoke-CustomAppProductionExactSpicetifyApplyProcessV010',
                      'Invoke-AtomicDirectorySwap',
                      '$script:CustomAppProductionPipelineEnabled = $true',
                      '[IO.File]::Delete'):
        if forbidden in ext:raise RuntimeError('new locator gained unauthorized execution '+forbidden)
    payload=ext+'\n\n'+SELFTEST+'\n\n'
    candidate=unique(original,'function Test-Due {',payload+'function Test-Due {','new locator insertion')
    candidate=unique(candidate,PREVIOUS_HOOK,NEW_HOOK,'exact SelfTest hook')
    if block(candidate,'Invoke-CustomAppProductionFullChainV010')!=block(original,'Invoke-CustomAppProductionFullChainV010'):
        raise RuntimeError('hard disabled production FullChain changed')
    if block(candidate,'Update-AutoApps')!=block(original,'Update-AutoApps'):
        raise RuntimeError('previous early legacy vs DPAPI fence mutated')
    if 'Custom App production full-chain execution is intentionally unavailable in integration-only candidate.' not in block(candidate,'Invoke-CustomAppProductionFullChainV010'):
        raise RuntimeError('hard-disable marker lost')
    for n in set(funcs(original)):
        if n in ('Invoke-AddonSelfTest','Test-CustomAppNormalUpdateEngineExclusivitySelfTestV010'):continue
        if block(candidate,n)!=block(original,n):
            raise RuntimeError('preexisting function changed '+n)
    reverse=unique(unique(candidate,NEW_HOOK,PREVIOUS_HOOK,'inverse SelfTest'),payload,'','inverse locator')
    if reverse!=original:raise RuntimeError('candidate not exactly reversible to latest qualified bundle')
    if candidate.count('$script:CustomAppProductionPipelineEnabled = $true')!=original.count('$script:CustomAppProductionPipelineEnabled = $true'):
        raise RuntimeError('pipeline enablement changed')
    output=bom+candidate.replace('\n','\r\n').encode('utf-8')
    files['addon-manager.ps1']=output
    OUT.mkdir(parents=True,exist_ok=True)
    for name,blob in files.items():(OUT/name).write_bytes(blob)
    report=dict(schema=1,qualified_parent=PARENT,original_addon_sha256=sha(addon),
        candidate_addon_sha256=sha(output),candidate_addon_size=len(output),
        qualified_spotify_sha256=sha(spotify),module_git_blob=MODULE_SHA,
        derived_real_zip_test_blob=DERIVE_SHA,locator_test_blob=TEST_SHA,
        new_locator_exports=names,original_fullchain_identical=True,
        original_update_autoapps_identical=True,qualified_candidate_inverse_exact=True,
        one_locator_per_consumption_id=True,dpapi_currentuser=True,
        locator_not_mutation_authority=True,missing_locator_fails_closed=True,
        qualified_terminal_verifier_still_required=True,normal_new_update_enabled=False,
        real_user_files_touched=False,operating_main_changed=False)
    (HERE/'candidate-validation.json').write_text(json.dumps(report,sort_keys=True,indent=2)+'\n',encoding='utf-8')
    print('USER_JOURNAL_RESTART_LOCATOR_ADDON_BUILT',len(output),sha(output),
          'real_update_disabled=true existing_Update_AutoApps_unchanged=true')
if __name__=='__main__':main()
