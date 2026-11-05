from __future__ import annotations
import hashlib, json, re, subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
OUT=HERE/'out'/'bin'
PARENT='d257922e24a35ba9ebebddef7e5df25bc5d44a83'
PARENT_BUILDER='validation/custom-app-production-retained-old-live-hard-disabled-bundle-v0.1.0/build_candidate.py'
PARENT_BLOB='b4edd24daf2a3089a4d1d9ff756d30d60064a872'
PARENT_ADDON=(1315455,'2d71338fbf95a3830e6ff286372d85b43e1ebbeb4a3296084e86aa5187984a9c')
PARENT_MAIN=(284327,'69ef7fb3ca57b4d5faac6873ac06dffc38f6e5b0d1ad8fc31fcbe2bb236f5c99')
MODULES=[
('journal-atomic','validation/custom-app-production-journal-aware-atomic-mutation-v0.1.0/custom-app-production-journal-aware-atomic-mutation.ps1','79580da78443a18bd281d4fce61c4a57d958a196'),
('journal-repair','validation/custom-app-production-journal-aware-atomic-mutation-v0.1.0/custom-app-production-journal-aware-atomic-repair-v011.ps1','210c4dda2311eb5defcbcd74977e4f4148ea7c38'),
('evidence-atomic','validation/custom-app-production-evidence-bound-journal-atomic-v0.1.0/custom-app-production-evidence-bound-journal-atomic.ps1','55ca1e3c8d56b2e86a98d8b47e8ac1cc4ccbb6d0'),
('triple-id-bridge','validation/custom-app-production-triple-id-authorized-journal-bridge-v0.1.0/custom-app-production-triple-id-authorized-journal-bridge.ps1','dcff9e27edc12268be8afcf795478bdaeac5bd1e'),
('exclusive-clock','validation/custom-app-production-exclusive-transaction-clock-gate-v0.1.0/custom-app-production-exclusive-transaction-clock-gate.ps1','7f41179bf67428aa736b438ec1185a4f0bc1e831'),
]
REQUIRED=(
'Assert-CustomAppProductionJournalAwareAtomicPreconditionsV010',
'Invoke-CustomAppProductionJournalAwareAtomicStartingRepairV010',
'Invoke-CustomAppProductionEvidenceBoundJournalAtomicMutationV010',
'Test-CustomAppProductionEvidenceBoundJournalAtomicResultV010',
'Invoke-CustomAppProductionTripleIdAuthorizedJournalBridgeV010',
'Test-CustomAppProductionWallClockAdmissionV010',
'Open-CustomAppProductionExclusiveGateLockV010',
'Invoke-CustomAppProductionExclusiveThirdIdJournalBridgeV010',
'Complete-CustomAppProductionExclusiveGateAfterTerminalJournalV010',
)
HOOK='    try { Test-CustomAppProductionRetainedOldLiveCompatibilitySelfTestV011 } catch { $errors.Add("Custom App retained old-live compatibility self-test failed: $($_.Exception.Message)") }'
NEW_HOOK=HOOK+'\n    try { Invoke-CustomAppProductionJournalLockBundleSelfTestV010 } catch { $errors.Add("Custom App journal-lock bundle self-test failed: $($_.Exception.Message)") }'
SELFTEST=r"""function Invoke-CustomAppProductionJournalLockBundleSelfTestV010 {
    if([bool]$script:CustomAppProductionPipelineEnabled){throw 'Candidate pipeline unexpectedly enabled'}
    foreach($name in @(
        'Assert-CustomAppProductionJournalAwareAtomicPreconditionsV010',
        'Invoke-CustomAppProductionJournalAwareAtomicStartingRepairV010',
        'Invoke-CustomAppProductionEvidenceBoundJournalAtomicMutationV010',
        'Test-CustomAppProductionEvidenceBoundJournalAtomicResultV010',
        'Invoke-CustomAppProductionTripleIdAuthorizedJournalBridgeV010',
        'Test-CustomAppProductionWallClockAdmissionV010',
        'Open-CustomAppProductionExclusiveGateLockV010',
        'Invoke-CustomAppProductionExclusiveThirdIdJournalBridgeV010',
        'Complete-CustomAppProductionExclusiveGateAfterTerminalJournalV010'
    )){
        if(-not(Get-Command $name -CommandType Function -ErrorAction SilentlyContinue)){throw ('Missing bundled function '+$name)}
    }
    $r=Invoke-CustomAppProductionFullChainV010
    if($null-eq$r -or [bool]$r.enabled -or [bool]$r.production_mutation_authorized -or [bool]$r.production_execution_authorized){throw 'Normal update authority escaped'}
    Write-Host 'CUSTOM_APP_JOURNAL_LOCK_BUNDLED_SELFTEST_PASS source_pins=true normal_update_disabled=true'
}"""
TRUE_RE=re.compile(r'(?im)^[ \t]*\$script:CustomAppProductionPipelineEnabled[ \t]*=[ \t]*\$true[ \t]*$')

def digest(b):return hashlib.sha256(b).hexdigest()
def git_blob(p):
    return subprocess.check_output(['git','rev-parse',f'{PARENT}:{p}'],cwd=ROOT,text=True).strip()
def git_bytes(h):return subprocess.check_output(['git','cat-file','blob',h],cwd=ROOT)
def once(s,a,b,label):
    n=s.count(a)
    if n!=1:raise RuntimeError(f'{label} expected single anchor, got {n}')
    return s.replace(a,b,1)
def funcs(t):return re.findall(r'(?im)^[ \t]*function\s+([A-Za-z0-9_-]+)\s*\{',t)
def block(t,name):
    pat=r'(?im)^[ \t]*function\s+'+re.escape(name)+r'\s*\{'
    m=re.search(pat,t)
    if not m:raise RuntimeError(f'qualified function absent {name}')
    n=re.search(r'(?im)^[ \t]*function\s+[A-Za-z0-9_-]+\s*\{',t[m.end():])
    return t[m.start():m.end()+n.start()] if n else t[m.start():]
def main():
    if git_blob(PARENT_BUILDER)!=PARENT_BLOB:raise RuntimeError('qualified parent builder drift')
    subprocess.check_call(['python',str(ROOT/PARENT_BUILDER)],cwd=ROOT)
    pd=ROOT/'validation/custom-app-production-retained-old-live-hard-disabled-bundle-v0.1.0/out/bin'
    files={n:(pd/n).read_bytes() for n in ('spotify-control.ps1','addon-manager.ps1','Collect-Marketplace-Records.ps1','LevelDbReadOnly.cs')}
    addon=files['addon-manager.ps1'];main=files['spotify-control.ps1']
    if (len(addon),digest(addon))!=PARENT_ADDON:raise RuntimeError('qualified Addon Manager changed')
    if (len(main),digest(main))!=PARENT_MAIN:raise RuntimeError('Spotify Control changed')
    bom=b'\xef\xbb\xbf' if addon.startswith(b'\xef\xbb\xbf') else b''
    original=addon[len(bom):].decode('utf-8').replace('\r\n','\n')
    if '$script:CustomAppProductionPipelineEnabled = $false' not in original:raise RuntimeError('parent hard-disable missing')
    if len(TRUE_RE.findall(original))!=1:raise RuntimeError('unexpected parent forced-enable count')
    existing=funcs(original);seen=set(existing);exported=set();overrides=[];parts=[];manifest=[]
    for label,path,blob in MODULES:
        if git_blob(path)!=blob:raise RuntimeError(f'{label} immutable source changed')
        src=git_bytes(blob).decode('utf-8-sig').replace('\r\n','\n').strip()
        names=funcs(src)
        if not names:raise RuntimeError(f'{label} empty exports')
        duplicate=sorted(set(names)&seen)
        expect=['Invoke-CustomAppProductionJournalAwareAtomicStartingRepairV010'] if label=='journal-repair' else []
        if duplicate!=expect:raise RuntimeError(f'{label} unexpected duplicate exports: {duplicate}')
        overrides+=duplicate;seen.update(names);exported.update(names);parts.append(src)
        manifest.append(dict(label=label,blob=blob,path=path,functions=len(names),intentional_override=duplicate))
    if len(exported)!=34 or overrides!=['Invoke-CustomAppProductionJournalAwareAtomicStartingRepairV010']:
        raise RuntimeError('expected exactly 34 exports, one qualified repair override')
    if any(n not in exported for n in REQUIRED):raise RuntimeError('missing required transaction entrypoints')
    payload='\n\n'.join(parts+[SELFTEST])+'\n\n'
    candidate=once(original,'function Test-Due {',payload+'function Test-Due {','bundle insertion')
    candidate=once(candidate,HOOK,NEW_HOOK,'SelfTest registration')
    if block(candidate,'Invoke-CustomAppProductionFullChainV010')!=block(original,'Invoke-CustomAppProductionFullChainV010'):
        raise RuntimeError('hard-disabled FullChain changed')
    if 'Custom App production full-chain execution is intentionally unavailable in integration-only candidate.' not in block(candidate,'Invoke-CustomAppProductionFullChainV010'):
        raise RuntimeError('hard-disabled FullChain marker missing')
    if len(TRUE_RE.findall(candidate))!=1:raise RuntimeError('added production-enable assignment')
    for name in existing:
        if name=='Invoke-AddonSelfTest':continue
        old=block(original,name)
        if any(entry in old for entry in REQUIRED[-3:]):raise RuntimeError(f'new lock unexpectedly callable by old entry {name}')
    inverse=once(once(candidate,NEW_HOOK,HOOK,'reverse hook'),payload,'','reverse source')
    if inverse!=original:raise RuntimeError('candidate not byte-exactly reversible')
    compiled=bom+candidate.replace('\n','\r\n').encode('utf-8')
    files['addon-manager.ps1']=compiled
    OUT.mkdir(parents=True,exist_ok=True)
    for name,data in files.items():(OUT/name).write_bytes(data)
    evidence=dict(schema=1,qualified_parent=PARENT,parent_addon_sha256=digest(addon),
        parent_addon_size=len(addon),candidate_addon_sha256=digest(compiled),
        candidate_addon_size=len(compiled),source_manifest=manifest,
        added_unique_export_functions=len(exported),intentional_overrides=overrides,
        exact_parent_inverse=True,full_chain_unchanged=True,source_e2e_proven_in_parent=True,
        normal_update_wired=False,production_main_unchanged=True,
        production_pipeline_enabled=False,protected_user_pc_store_implemented=False,
        actual_spicetify_executed=False)
    (HERE/'candidate-validation.json').write_text(json.dumps(evidence,indent=2,sort_keys=True)+'\n',encoding='utf-8')
    print('CUSTOM_APP_JOURNAL_LOCK_BUNDLE_BUILT',len(compiled),digest(compiled),'normal_update_disabled=true')
if __name__=='__main__':main()
