"""Generated Addon Manager compatibility guard for old vs DPAPI journal engine.
This does NOT promote the disabled new FullChain; only refuses legacy -Action
Update when the new user transaction store has ever been enrolled. The
original candidate must be recovered EXACTLY by inverse transformation.
"""
from __future__ import annotations
import hashlib,json,re,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
OUT=HERE/'out'/'bin'
PARENT='22c548aad75d2dc59699062b4d01f8c4020e5b15'
PARENT_BUILDER='validation/custom-app-user-transaction-terminal-journal/build_candidate.py'
PARENT_BLOB='20902d142ed5a2270ece4ab75671959dd178bd1e'
AUDIT='validation/custom-app-normal-entrypoint-transaction-integration/audit_entrypoint.py'
AUDIT_BLOB='4a931dc02a89c19b7b1fdc09412fa52a77fbfe02'
MODULE='validation/custom-app-normal-entrypoint-transaction-integration/normal-update-engine-fence.ps1'
MODULE_BLOB='5335c610325a4654aaba83749ed5ede500981c7c'
ORIGINAL=(1448757,'6fe25f592fddd30424d670bc20fc68f0a8b78a01c4fa29f8dc2268d2714b46f9')
SPOTIFY=(284327,'69ef7fb3ca57b4d5faac6873ac06dffc38f6e5b0d1ad8fc31fcbe2bb236f5c99')
BEFORE="function Update-AutoApps {\n"
AFTER="function Update-AutoApps {\n    [void](Assert-CustomAppNormalUpdateEngineExclusivityV010)\n"
OLD_HOOK='    try { Test-CustomAppUserTxnVerifiedTerminalBundleSelfTestV011 } catch { $errors.Add("Custom App verified user transaction terminal bundle self-test failed: $($_.Exception.Message)") }'
NEW_HOOK=OLD_HOOK+'\n    try { Test-CustomAppNormalUpdateEngineExclusivitySelfTestV010 } catch { $errors.Add("Custom App normal update two-engine safety self-test failed: $($_.Exception.Message)") }'

def sha(b):return hashlib.sha256(b).hexdigest()
def pin(ref,path,expected):
    got=subprocess.check_output(['git','rev-parse',f'{ref}:{path}'],cwd=ROOT,text=True).strip()
    if got!=expected:raise RuntimeError(f'qualified pin drift: {path} {got}')
def once(s,a,b,label):
    n=s.count(a)
    if n!=1:raise RuntimeError(f'{label} anchor count={n}')
    return s.replace(a,b,1)
def funcs(s):return re.findall(r'(?im)^[ \t]*function\s+([A-Za-z0-9_-]+)\s*\{',s)
def block(s,n):
    m=re.search(r'(?im)^[ \t]*function\s+'+re.escape(n)+r'\s*\{',s)
    if not m:raise RuntimeError('function not found '+n)
    end=re.search(r'(?im)^[ \t]*function\s+[-A-Za-z0-9_]+\s*\{',s[m.end():])
    return s[m.start():m.end()+end.start() if end else len(s)]
def main():
    for ref,path,expected in (
      (PARENT,PARENT_BUILDER,PARENT_BLOB),
      ('HEAD',AUDIT,AUDIT_BLOB),
      ('HEAD',MODULE,MODULE_BLOB)
    ):pin(ref,path,expected)
    # Run actual qualified candidate generator, not a fixture. Its own checks
    # bind every previous function and the immutable operating base.
    subprocess.check_call(['python',str(ROOT/PARENT_BUILDER)],cwd=ROOT)
    p=ROOT/'validation/custom-app-user-transaction-terminal-journal/out/bin'
    files={n:(p/n).read_bytes() for n in ('addon-manager.ps1','spotify-control.ps1','Collect-Marketplace-Records.ps1','LevelDbReadOnly.cs')}
    addon=files['addon-manager.ps1'];spot=files['spotify-control.ps1']
    if (len(addon),sha(addon))!=ORIGINAL or (len(spot),sha(spot))!=SPOTIFY:
        raise RuntimeError('previous fully validated candidate drift')
    bom=b'\xef\xbb\xbf' if addon.startswith(b'\xef\xbb\xbf') else b''
    original=addon[len(bom):].decode('utf-8').replace('\r\n','\n')
    module=(ROOT/MODULE).read_text('utf-8-sig').replace('\r\n','\n').strip()
    additions=funcs(module)
    expected=['Assert-CustomAppNormalUpdateEngineExclusivityV010','Test-CustomAppNormalUpdateEngineExclusivitySelfTestV010']
    if sorted(additions)!=sorted(expected) or set(additions)&set(funcs(original)):
        raise RuntimeError('unexpected normal update safety module or function collision')
    for forbidden in ('Invoke-CustomAppProductionFullChainV010','Invoke-CustomAppProductionExactSpicetifyApplyProcessV010',
                      'Invoke-AtomicDirectorySwap','$script:CustomAppProductionPipelineEnabled = $true',
                      'Set-StrictMode','Remove-Item','[IO.Directory]::CreateDirectory'):
        if forbidden in module:raise RuntimeError('normal update safety module gained execution power '+forbidden)
    payload=module+'\n\n'
    candidate=once(original,'function Test-Due {',payload+'function Test-Due {','standalone read-only guard')
    candidate=once(candidate,BEFORE,AFTER,'only normal Update-AutoApps call')
    candidate=once(candidate,OLD_HOOK,NEW_HOOK,'normal Addon Manager SelfTest hook')
    update=block(candidate,'Update-AutoApps')
    if not update.startswith(AFTER):raise RuntimeError('gate not first in actual normal update function')
    for risky in ('Rollback-LastTransaction','Backup-SpotifyWebData','Get-AddonInventory','New-RequiredSpotifyPersistenceBackup','Invoke-AtomicDirectorySwap'):
        if risky not in update or update.index('Assert-CustomAppNormalUpdateEngineExclusivityV010')>=update.index(risky):
            raise RuntimeError('old side effect before normal compatibility gate '+risky)
    if block(candidate,'Invoke-CustomAppProductionFullChainV010')!=block(original,'Invoke-CustomAppProductionFullChainV010'):
        raise RuntimeError('FullChain hard-disable unexpectedly touched')
    if 'Custom App production full-chain execution is intentionally unavailable in integration-only candidate.' not in block(candidate,'Invoke-CustomAppProductionFullChainV010'):
        raise RuntimeError('FullChain hard-disable missing')
    for n in set(funcs(original)):
        if n in ('Update-AutoApps','Invoke-AddonSelfTest','Test-CustomAppUserTxnVerifiedTerminalBundleSelfTestV011'):continue
        if block(candidate,n)!=block(original,n):raise RuntimeError('old function mutated '+n)
    reverse=once(once(once(candidate,NEW_HOOK,OLD_HOOK,'reverse SelfTest'),AFTER,BEFORE,'reverse normal update call'),
                 payload,'','reverse standalone guard')
    if reverse!=original:raise RuntimeError('candidate not exactly reversible to prior qualified bundle')
    if candidate.count('$script:CustomAppProductionPipelineEnabled = $true')!=original.count('$script:CustomAppProductionPipelineEnabled = $true'):
        raise RuntimeError('new production enablement leaked')
    result=bom+candidate.replace('\n','\r\n').encode('utf-8')
    files['addon-manager.ps1']=result
    OUT.mkdir(parents=True,exist_ok=True)
    for name,data in files.items():(OUT/name).write_bytes(data)
    report=dict(schema=1,parent=PARENT,parent_addon_sha256=sha(addon),candidate_sha256=sha(result),
                candidate_size=len(result),spotify_sha256=sha(spot),added_functions=additions,
                exact_parent_inverse=True,normal_update_call_site='Update-AutoApps:first-statement',
                no_legacy_rollback_before_gate=True,does_not_enroll_or_create_state=True,
                never_grants_production_authority=True,production_full_chain_still_disabled=True,
                legacy_engine_remains_original_if_no_new_enrollment=True,
                enrolled_new_engine_blocks_legacy_update=True,new_full_chain_normal_wiring=False,
                operating_main_changed=False,actual_spicetify_executed=False)
    (HERE/'candidate-validation.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n',encoding='utf-8')
    print('ACTUAL_NORMAL_ADDON_MIXED_ENGINE_FENCE_BUILT',len(result),sha(result),
          'FullChain_disabled=true legacy_state_preserved=true new_journal_enrollment_blocks_legacy=true')
if __name__=='__main__':main()
