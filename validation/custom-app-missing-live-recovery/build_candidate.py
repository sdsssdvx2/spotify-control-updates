"""Build a strictly hard-disabled Addon Manager with a read-only recovery
opener for the missing-live-directory crash window.

The qualified normal Update and all previous signed-ZIP / DPAPI functions are
byte-identical to the PR227 frozen candidate. No app installation, no
migration, no production update authorization, no directory recreation.
"""
from __future__ import annotations
import hashlib,json,re,subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
OUT=HERE/'out'/'bin'
PARENT='f60aa58af69f2aafade3ba9e48d2779872fada2b'
PARENT_BUILDER='validation/custom-app-journal-restart-locator/build_candidate.py'
PARENT_BLOB='f44fc4a08d5a9b9db94f90f5f0edbf27777a13fb'
PRIOR_ADDON=(1465354,'40822a7c51692b801edd80d78faa0cf685ef306b11ef82efaeabed522c9540cc')
PRIOR_SPOTIFY=(284327,'69ef7fb3ca57b4d5faac6873ac06dffc38f6e5b0d1ad8fc31fcbe2bb236f5c99')
MODULE='validation/custom-app-missing-live-recovery/missing-live-recovery.ps1'
MODULE_BLOB='5f25458ebf9c40206fde11918c2ce221966d6b2b'
TEST='validation/custom-app-missing-live-recovery/test_missing_live_recovery.ps1'
TEST_BLOB='d4adc5c1486de6c7684fb4bda1e328b359316823'
DERIVE='validation/custom-app-missing-live-recovery/derive_actual_signed_zip_missing_live.py'
DERIVE_BLOB='4733e300f692cc7a741330a9a8fc21328cc7b74d'
OLD_HOOK='    try { Test-CustomAppUserJournalLocatorSelfTestV010 } catch { $errors.Add("Custom App user journal restart locator self-test failed: $($_.Exception.Message)") }'
NEW_HOOK=OLD_HOOK+'\n    try { Test-CustomAppMissingLiveRecoverySelfTestV011 } catch { $errors.Add("Custom App interrupted live path recovery self-test failed: $($_.Exception.Message)") }'
SELFTEST=r"""function Test-CustomAppMissingLiveRecoverySelfTestV011 {
    if([bool]$script:CustomAppProductionPipelineEnabled){throw 'unexpected production pipeline enablement'}
    foreach($name in @('Get-CustomAppUserTxnMissingLivePathsV011',
                       'Open-CustomAppUserTxnMissingLiveRecoveryV011')){
        if(-not(Get-Command $name -CommandType Function -ErrorAction SilentlyContinue)){
            throw ('Missing recovery-only transaction inspector '+$name)
        }
    }
    Write-Host 'CUSTOM_APP_MISSING_LIVE_RECOVERY_SELFTEST_PASS no_auto_restore=true no_unqualified_live_creation=true'
}"""
def sha(blob):return hashlib.sha256(blob).hexdigest()
def git_pin(ref,p,exp):
    got=subprocess.check_output(['git','rev-parse',f'{ref}:{p}'],cwd=ROOT,text=True).strip()
    if got!=exp:raise RuntimeError('qualified git source drift '+p)
def one(s,a,b,label):
    c=s.count(a)
    if c!=1:raise RuntimeError(f'{label}: expected one anchor but found {c}')
    return s.replace(a,b,1)
def funcs(s):return re.findall(r'(?im)^[ \t]*function\s+([A-Za-z0-9_-]+)\s*\{',s)
def block(s,name):
    m=re.search(r'(?im)^[ \t]*function\s+'+re.escape(name)+r'\s*\{',s)
    if not m:raise RuntimeError('missing expected previous function '+name)
    nxt=re.search(r'(?im)^[ \t]*function\s+[A-Za-z0-9_-]+\s*\{',s[m.end():])
    return s[m.start():m.end()+nxt.start() if nxt else len(s)]
def main():
    for ref,path,expect in ((PARENT,PARENT_BUILDER,PARENT_BLOB),
                            ('HEAD',MODULE,MODULE_BLOB),('HEAD',TEST,TEST_BLOB),('HEAD',DERIVE,DERIVE_BLOB)):
        git_pin(ref,path,expect)
    subprocess.check_call(['python',str(ROOT/PARENT_BUILDER)],cwd=ROOT)
    d=ROOT/'validation/custom-app-journal-restart-locator/out/bin'
    original_files={n:(d/n).read_bytes() for n in
                    ('addon-manager.ps1','spotify-control.ps1','Collect-Marketplace-Records.ps1','LevelDbReadOnly.cs')}
    addon=original_files['addon-manager.ps1'];spotify=original_files['spotify-control.ps1']
    if (len(addon),sha(addon))!=PRIOR_ADDON or (len(spotify),sha(spotify))!=PRIOR_SPOTIFY:
        raise RuntimeError('previous signed real ZIP journal locator candidate changed')
    bom=b'\xef\xbb\xbf' if addon.startswith(b'\xef\xbb\xbf') else b''
    source=addon[len(bom):].decode('utf-8').replace('\r\n','\n')
    ext=(ROOT/MODULE).read_text('utf-8-sig').replace('\r\n','\n').strip()
    new_functions=funcs(ext)
    if sorted(new_functions)!=sorted(('Get-CustomAppUserTxnMissingLivePathsV011',
                                     'Open-CustomAppUserTxnMissingLiveRecoveryV011')):
        raise RuntimeError('invalid new exports in missing-live recovery')
    if set(new_functions)&set(funcs(source)):raise RuntimeError('qualified function name collision')
    for required in ('Get-CustomAppUserTxnSha256V010',
                     'Assert-CustomAppUserTxnPrivateDirectoryV010',
                     'Read-CustomAppUserTxnStateV010',
                     'Read-CustomAppUserTxnJournalLocatorV010',
                     '[IO.FileMode]::Open','[IO.FileShare]::None'):
        if required not in ext:raise RuntimeError('critical read-only recovery invariant missing '+required)
    for forbidden in ('FileMode]::Create','CreateDirectory(', 'Remove-Item ',
                      '[IO.File]::Delete','Commit-CustomAppUserTxnVerifiedTerminalV011',
                      'Invoke-CustomAppProductionFullChainV010',
                      '$script:CustomAppProductionPipelineEnabled = $true'):
        if forbidden in ext:raise RuntimeError('unexpected live re-creation or production mutation '+forbidden)
    payload=ext+'\n\n'+SELFTEST+'\n\n'
    candidate=one(source,'function Test-Due {',payload+'function Test-Due {','missing-live recovery insertion')
    candidate=one(candidate,OLD_HOOK,NEW_HOOK,'new SelfTest exact hook')
    if block(candidate,'Update-AutoApps')!=block(source,'Update-AutoApps'):
        raise RuntimeError('existing mixed-engine normal Update preflight unexpectedly touched')
    if block(candidate,'Invoke-CustomAppProductionFullChainV010')!=block(source,'Invoke-CustomAppProductionFullChainV010'):
        raise RuntimeError('unqualified FullChain enablement')
    if 'Custom App production full-chain execution is intentionally unavailable in integration-only candidate.' not in block(candidate,'Invoke-CustomAppProductionFullChainV010'):
        raise RuntimeError('FullChain hard disable lost')
    for name in set(funcs(source)):
        if name in ('Invoke-AddonSelfTest','Test-CustomAppUserJournalLocatorSelfTestV010'):
            continue
        if block(candidate,name)!=block(source,name):
            raise RuntimeError('existing qualified function changed '+name)
    inverse=one(one(candidate,NEW_HOOK,OLD_HOOK,'inverse selftest'),payload,'','inverse recovery adapter')
    if inverse!=source:raise RuntimeError('candidate cannot be exactly reverted to frozen prior version')
    if candidate.count('$script:CustomAppProductionPipelineEnabled = $true')!=source.count('$script:CustomAppProductionPipelineEnabled = $true'):
        raise RuntimeError('production authority count drift')
    output=bom+candidate.replace('\n','\r\n').encode('utf-8')
    original_files['addon-manager.ps1']=output
    OUT.mkdir(parents=True,exist_ok=True)
    for n,data in original_files.items():(OUT/n).write_bytes(data)
    report=dict(schema=1,qualified_parent=PARENT,prior_addon_sha256=sha(addon),
        addon_sha256=sha(output),addon_size=len(output),spotify_control_sha256=sha(spotify),
        new_function_names=new_functions,source_git_blob=MODULE_BLOB,
        regression_git_blob=TEST_BLOB,real_signed_zip_derived_regression_blob=DERIVE_BLOB,original_update_autoapps_unchanged=True,
        original_fullchain_hard_disabled=True,exact_parent_inverse=True,
        absent_live_parent_and_ancestor_validation=True,
        original_user_store_never_re_enrolled=True,
        no_user_live_directory_recreated=True,
        FileShareNone_lock_reused=True,
        DPAPI_locator_and_active_claim_reloaded=True,
        unresolved_pending_preserved=True,
        no_restoration_or_mutation_authority=True,
        automatic_fullchain_enabled=False,operating_main_changed=False)
    (HERE/'candidate-validation.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n',encoding='utf-8')
    print('MISSING_LIVE_READONLY_RECOVERY_ACTUAL_ADDON_BUILT',len(output),sha(output),
          'automatic_update_disabled=true never_creates_live=true')
if __name__=='__main__':main()
