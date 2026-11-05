from __future__ import annotations
import hashlib, json, re, subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
OUT=HERE/'out'/'bin'
PARENT='22c31dc7e1a73d91a13f957a68706c4e8d698d2f'
PARENT_BUILDER='validation/custom-app-user-transaction-transition-guard/build_candidate.py'
PARENT_BUILDER_BLOB='3fc616fd561063c97878e6940c84498af23dc165'
PARENT_ADDON=(1436614,'b026d3c63de39b574ae131a8b1cd526f9a2e7b95059a5019c806c5be1978176b')
PARENT_MAIN=(284327,'69ef7fb3ca57b4d5faac6873ac06dffc38f6e5b0d1ad8fc31fcbe2bb236f5c99')
MODULE='validation/custom-app-user-transaction-terminal-journal/verified-terminal-adapter.ps1'
MODULE_BLOB='8a18de8c49d1c32b1c53ca48518af07aa7a617ad'
DERIVE='validation/custom-app-user-transaction-terminal-journal/derive_real_zip_terminal_e2e.py'
DERIVE_BLOB='dccf4d656d74cb97ba6eb188ba06fc77057ef209'
CHILD='validation/custom-app-user-transaction-terminal-journal/terminal-readback-child.ps1'
CHILD_BLOB='fd5465330d84e874a0b594a66ad1d5fa611273c4'
OLD_HOOK='    try { Test-CustomAppUserTxnGuardBundleSelfTestV010 } catch { $errors.Add("Custom App private user transaction guard bundle self-test failed: $($_.Exception.Message)") }'
NEW_HOOK=OLD_HOOK+'\n    try { Test-CustomAppUserTxnVerifiedTerminalBundleSelfTestV011 } catch { $errors.Add("Custom App verified user transaction terminal bundle self-test failed: $($_.Exception.Message)") }'
SELFTEST=r"""function Test-CustomAppUserTxnVerifiedTerminalBundleSelfTestV011 {
    if([bool]$script:CustomAppProductionPipelineEnabled){throw 'Production pipeline unexpectedly enabled by terminal bridge'}
    foreach($name in @('Test-CustomAppUserTxnTerminalJournalEvidenceV010','Commit-CustomAppUserTxnVerifiedTerminalV011')){
        if(-not(Get-Command $name -CommandType Function -ErrorAction SilentlyContinue)){throw ('Missing qualified terminal bridge '+$name)}
    }
    if(Get-Command Complete-CustomAppUserTxnTerminalV010 -CommandType Function -ErrorAction SilentlyContinue){throw 'Unsafe legacy terminal clearance exposed'}
    Write-Host 'CUSTOM_USER_TXN_VERIFIED_TERMINAL_BUNDLE_SELFTEST_PASS durable_journal_required=true real_file_revalidation_required=true normal_update_disabled=true'
}"""
def digest(data):return hashlib.sha256(data).hexdigest()
def git_blob(ref,path):return subprocess.check_output(['git','rev-parse',f'{ref}:{path}'],cwd=ROOT,text=True).strip()
def unique(s,a,b,label):
    n=s.count(a)
    if n!=1:raise RuntimeError(f'{label}: expected unique anchor got {n}')
    return s.replace(a,b,1)
def funcs(s):return re.findall(r'(?im)^[ \t]*function\s+([A-Za-z0-9_-]+)\s*\{',s)
def block(s,n):
    m=re.search(r'(?im)^[ \t]*function\s+'+re.escape(n)+r'\s*\{',s)
    if not m:raise RuntimeError('missing qualified function '+n)
    nxt=re.search(r'(?im)^[ \t]*function\s+[-A-Za-z0-9_]+\s*\{',s[m.end():])
    return s[m.start():(m.end()+nxt.start() if nxt else len(s))]
def main():
    if git_blob(PARENT,PARENT_BUILDER)!=PARENT_BUILDER_BLOB:raise RuntimeError('qualified old builder source changed')
    for path,blob in ((MODULE,MODULE_BLOB),(DERIVE,DERIVE_BLOB),(CHILD,CHILD_BLOB)):
        if git_blob('HEAD',path)!=blob:raise RuntimeError('terminal source/verification drift '+path)
    subprocess.check_call(['python',str(ROOT/PARENT_BUILDER)],cwd=ROOT)
    p=ROOT/'validation/custom-app-user-transaction-transition-guard/out/bin'
    files={n:(p/n).read_bytes() for n in ('addon-manager.ps1','spotify-control.ps1','Collect-Marketplace-Records.ps1','LevelDbReadOnly.cs')}
    addon=files['addon-manager.ps1'];spotify=files['spotify-control.ps1']
    if (len(addon),digest(addon))!=PARENT_ADDON or (len(spotify),digest(spotify))!=PARENT_MAIN:raise RuntimeError('parent candidate bytes drift')
    bom=b'\xef\xbb\xbf' if addon.startswith(b'\xef\xbb\xbf') else b''
    original=addon[len(bom):].decode('utf-8').replace('\r\n','\n')
    module=(ROOT/MODULE).read_text('utf-8-sig').replace('\r\n','\n').strip()
    added=funcs(module)
    if sorted(added)!=['Commit-CustomAppUserTxnVerifiedTerminalV011','Test-CustomAppUserTxnTerminalJournalEvidenceV010']:
        raise RuntimeError('unexpected verified-terminal bridge exports')
    if set(added)&set(funcs(original)):raise RuntimeError('terminal function collision')
    if any(x in module for x in ('Invoke-CustomAppProductionFullChainV010','$script:CustomAppProductionPipelineEnabled = $true','Invoke-CustomAppProductionExactSpicetifyApplyProcessV010')):
        raise RuntimeError('terminal bridge contains unexpected production authorization')
    for binding in ('Read-CustomAppProductionCrashJournalV010','Read-CustomAppProductionRecoveryEvidenceV010','Get-CustomAppUpdateTreeSnapshotV010','Get-SpotifyPersistenceSnapshot','Get-CustomAppLocalRuntimeBaseline','[IO.File]::Replace'):
        if binding not in module:raise RuntimeError('qualified evidence/physical check or atomic commit missing '+binding)
    payload=module+'\n\n'+SELFTEST+'\n\n'
    candidate=unique(original,'function Test-Due {',payload+'function Test-Due {','exact terminal insertion')
    candidate=unique(candidate,OLD_HOOK,NEW_HOOK,'new SelfTest registration')
    if block(candidate,'Invoke-CustomAppProductionFullChainV010')!=block(original,'Invoke-CustomAppProductionFullChainV010'):
        raise RuntimeError('hard-disabled production FullChain changed')
    if 'Custom App production full-chain execution is intentionally unavailable in integration-only candidate.' not in block(candidate,'Invoke-CustomAppProductionFullChainV010'):
        raise RuntimeError('required hard-disable marker lost')
    for name in set(funcs(original)):
        if name in ('Invoke-AddonSelfTest','Test-CustomAppUserTxnGuardBundleSelfTestV010'):continue
        if block(candidate,name)!=block(original,name):raise RuntimeError('previous verified function unexpectedly modified '+name)
    inverse=unique(unique(candidate,NEW_HOOK,OLD_HOOK,'reverse SelfTest'),payload,'','reverse terminal source')
    if inverse!=original:raise RuntimeError('previous hard-disabled candidate not byte-exactly restored by inverse')
    if candidate.count('$script:CustomAppProductionPipelineEnabled = $true')!=original.count('$script:CustomAppProductionPipelineEnabled = $true'):
        raise RuntimeError('normal production authority unexpectedly gained')
    result=bom+candidate.replace('\n','\r\n').encode('utf-8')
    files['addon-manager.ps1']=result
    OUT.mkdir(parents=True,exist_ok=True)
    for name,data in files.items():(OUT/name).write_bytes(data)
    report=dict(schema=1,qualified_parent=PARENT,parent_addon_sha256=digest(addon),
        candidate_addon_sha256=digest(result),candidate_addon_size=len(result),
        candidate_spotify_control_sha256=digest(spotify),
        module_blob=MODULE_BLOB,derivation_blob=DERIVE_BLOB,child_test_blob=CHILD_BLOB,
        added_terminal_exports=added,old_functions_unchanged=True,old_full_chain_unchanged=True,
        exact_parent_inverse=True,verifies_qualified_durable_journal_and_evidence=True,
        verifies_live_tree_and_spotify_persistence=True,consumed_ledger_and_claim_one_atomic_replace=True,
        preterminal_guard_kept=True,normal_auto_update_wired=False,actual_spicetify_invoked=False,
        operating_main_changed=False)
    (HERE/'candidate-validation.json').write_text(json.dumps(report,sort_keys=True,indent=2)+'\n',encoding='utf-8')
    print('CUSTOM_USER_TERMINAL_REAL_ADDON_CANDIDATE_BUILT',len(result),digest(result),'full_chain_disabled=true no_actual_spotify=true')
if __name__=='__main__':main()
