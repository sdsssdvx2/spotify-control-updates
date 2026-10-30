from __future__ import annotations
from pathlib import Path
import hashlib, json, re, subprocess

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
OUT=HERE/'out'/'bin'
REPORT=HERE/'candidate-validation.json'

PRODUCTION_MAIN='d38e88d9ae99f6a4983e2ad64f74f6fce7e6cde2'
FULL_CHAIN_HEAD='9ef429542774ddaf0bd0a6d03d81acebb487a62c'
FULL_CHAIN_BUILDER='validation/custom-app-production-full-chain-integration-v0.1.0/build_candidate_v011.py'
FULL_CHAIN_BUILDER_BLOB='bd2f2073837f570fe9d142480f1713f39a36f0a6'
PARENT_ADDON=(928813,'7426430238ec08ea41e2b15c050825f622234fdfd4c1fb9f44db648ee67a9537')
PARENT_MAIN=(284327,'69ef7fb3ca57b4d5faac6873ac06dffc38f6e5b0d1ad8fc31fcbe2bb236f5c99')
JOURNAL_HEAD='7e26187e2360089024e9d72d0701be6f1577a1ef'
JOURNAL_PATH='validation/custom-app-production-crash-recovery-journal-v0.1.0/custom-app-production-crash-recovery-journal.ps1'
JOURNAL_BLOB='a3df7e5d89c594083c10e240e13029ca5640b8ae'
EXPECTED_AUTO=['better-local-files','eternal-jukebox','ivLyrics','playlist-maker','tagify']
REQUIRED_JOURNAL_FUNCTIONS=[
    'New-CustomAppProductionCrashJournalIdentityV010',
    'Test-CustomAppProductionCrashJournalIdentityV010',
    'New-CustomAppProductionCrashJournalEntryV010',
    'Test-CustomAppProductionCrashJournalEntryV010',
    'Test-CustomAppProductionCrashJournalTransitionV010',
    'Get-CustomAppProductionCrashJournalPathsV010',
    'Open-CustomAppProductionCrashJournalLockV010',
    'Write-CustomAppProductionCrashJournalDurableFileV010',
    'Read-CustomAppProductionCrashJournalUnlockedV010',
    'Read-CustomAppProductionCrashJournalV010',
    'Initialize-CustomAppProductionCrashJournalV010',
    'Append-CustomAppProductionCrashJournalPhaseV010',
    'Resolve-CustomAppProductionCrashRecoveryClassificationV010',
]
FORBIDDEN_JOURNAL_MARKERS=[
    '[IO.Directory]::Move','[IO.Directory]::Delete','Move-Item','Copy-Item','Remove-Item',
    'Invoke-WebRequest','Invoke-RestMethod','Start-Process','ProcessStartInfo',
    'spicetify apply','spicetify config','spicetify restore',
    'Restore-CustomAppProductionAtomicLiveSwapV010','Restore-SpotifyPersistenceBackup',
    'Invoke-CustomAppProductionExactSpicetifyApplyProcessV010'
]
DANGEROUS_ENTRYPOINTS={
    'Invoke-CustomAppProductionStageExecutorV010','Invoke-CustomAppProductionPreApplyPreparationV010',
    'Invoke-CustomAppProductionAtomicLiveSwapV010','Invoke-CustomAppProductionSpicetifyApplyExecutorV010',
    'Invoke-CustomAppProductionPostApplyCommitCleanupV010','Invoke-CustomAppProductionFullChainV010'
}

SELFTEST=r'''function Invoke-CustomAppProductionCrashJournalIntegratedSelfTestV010 {
    if($CustomAppProductionCrashRecoveryJournalSchema -ne 1){ throw 'Crash journal integrated schema mismatch.' }
    if([string]$CustomAppProductionCrashRecoveryJournalManagedBy -cne 'custom-app-production-crash-recovery-journal-v1'){ throw 'Crash journal integrated owner mismatch.' }
    if([string]$CustomAppProductionCrashRecoveryJournalQualifiedCleanupHead -cne '67458cbb96b5d1ed92e26c2b81debd6894044749'){ throw 'Crash journal integrated parent mismatch.' }
    $required=@(
        'New-CustomAppProductionCrashJournalIdentityV010','Test-CustomAppProductionCrashJournalIdentityV010',
        'New-CustomAppProductionCrashJournalEntryV010','Test-CustomAppProductionCrashJournalEntryV010',
        'Test-CustomAppProductionCrashJournalTransitionV010','Get-CustomAppProductionCrashJournalPathsV010',
        'Open-CustomAppProductionCrashJournalLockV010','Write-CustomAppProductionCrashJournalDurableFileV010',
        'Read-CustomAppProductionCrashJournalUnlockedV010','Read-CustomAppProductionCrashJournalV010',
        'Initialize-CustomAppProductionCrashJournalV010','Append-CustomAppProductionCrashJournalPhaseV010',
        'Resolve-CustomAppProductionCrashRecoveryClassificationV010'
    )
    foreach($name in $required){ if(-not (Get-Command $name -CommandType Function -ErrorAction SilentlyContinue)){ throw ('Integrated crash journal function missing: '+$name) } }
    if(-not (Test-CustomAppProductionCrashJournalTransitionV010 -From 'prepared' -To 'atomic-mutation-starting')){ throw 'Crash journal legal transition rejected.' }
    if(Test-CustomAppProductionCrashJournalTransitionV010 -From 'prepared' -To 'committed-clean'){ throw 'Crash journal illegal transition accepted.' }
    foreach($phase in @('prepared','atomic-mutation-starting','live-moved-to-old','candidate-live','transaction-finalized','apply-starting','apply-returned-success-pending-verification','apply-verified','cleanup-starting','committed-clean','rollback-required','rollback-complete')){
        if($phase -notin $CustomAppProductionCrashRecoveryJournalPhases){ throw ('Crash journal phase missing: '+$phase) }
    }
    $zero=$CustomAppProductionCrashRecoveryJournalZeroHash
    if([string]$zero -cne ('0'*64)){ throw 'Crash journal zero-hash sentinel drift.' }
    $prepared=[pscustomobject]@{ok=$true;reloaded_from_persistent_store=$true;entry=[pscustomobject]@{phase='prepared';transaction_id=('a'*64)}}
    $class=Resolve-CustomAppProductionCrashRecoveryClassificationV010 -StoreRead $prepared -ExpectedTransactionId ('a'*64)
    if(-not [bool]$class.ok -or -not [bool]$class.no_action -or [bool]$class.production_execution_authorized -or [bool]$class.production_mutation_authorized -or [bool]$class.journal_is_authority){ throw 'Crash journal recovery classification authority separation drift.' }
    if([string]$class.classification -cne 'safe-abandon-or-restart-only-after-fresh-admission'){ throw 'Crash journal prepared recovery classification drift.' }
    if([bool]$script:CustomAppProductionPipelineEnabled){ throw 'Crash journal integration observed enabled production pipeline.' }
    Write-Host 'CUSTOM_APP_PRODUCTION_CRASH_JOURNAL_INTEGRATED_SELFTEST_V010_PASS zero-authority hard-disabled coexistence'
}
'''

def sha(b:bytes)->str:return hashlib.sha256(b).hexdigest()
def git_blob(commit:str,path:str)->str:return subprocess.check_output(['git','rev-parse',f'{commit}:{path}'],cwd=ROOT,text=True).strip()
def git_bytes(commit:str,path:str)->bytes:return subprocess.check_output(['git','show',f'{commit}:{path}'],cwd=ROOT)
def functions(t:str)->list[str]:return re.findall(r'(?im)^\s*function\s+([A-Za-z0-9_-]+)\s*\{',t)

def function_bounds(text:str,name:str)->tuple[int,int]:
    m=re.search(rf'(?im)^\s*function\s+{re.escape(name)}\s*\{{',text)
    if not m:raise RuntimeError(f'missing function {name}')
    n=re.search(r'(?im)^\s*function\s+[A-Za-z0-9_-]+\s*\{',text[m.end():])
    return m.start(),(m.end()+n.start() if n else len(text))
def function_block(text:str,name:str)->str:
    a,b=function_bounds(text,name);return text[a:b]
def replace_function(text:str,name:str,replacement:str)->str:
    a,b=function_bounds(text,name);return text[:a]+replacement.rstrip()+'\n\n'+text[b:].lstrip('\n')
def replace_once(text:str,old:str,new:str,label:str)->str:
    c=text.count(old)
    if c!=1:raise RuntimeError(f'{label} anchor count drift: {c}')
    return text.replace(old,new,1)

def build_parent()->tuple[bytes,bytes,bytes,bytes]:
    if git_blob(FULL_CHAIN_HEAD,FULL_CHAIN_BUILDER)!=FULL_CHAIN_BUILDER_BLOB:raise RuntimeError('full-chain builder pin drift')
    subprocess.check_call(['python',str(ROOT/FULL_CHAIN_BUILDER)],cwd=ROOT)
    d=ROOT/'validation/custom-app-production-full-chain-integration-v0.1.0/out/bin'
    main=(d/'spotify-control.ps1').read_bytes();addon=(d/'addon-manager.ps1').read_bytes();collector=(d/'Collect-Marketplace-Records.ps1').read_bytes();reader=(d/'LevelDbReadOnly.cs').read_bytes()
    if (len(main),sha(main))!=PARENT_MAIN:raise RuntimeError(f'parent main drift {len(main)} {sha(main)}')
    if (len(addon),sha(addon))!=PARENT_ADDON:raise RuntimeError(f'parent addon drift {len(addon)} {sha(addon)}')
    return main,addon,collector,reader

def integrate(addon:bytes)->tuple[bytes,dict]:
    if git_blob(JOURNAL_HEAD,JOURNAL_PATH)!=JOURNAL_BLOB:raise RuntimeError('journal core pin drift')
    journal=git_bytes(JOURNAL_HEAD,JOURNAL_PATH).decode('utf-8-sig').replace('\r\n','\n').rstrip()
    for marker in FORBIDDEN_JOURNAL_MARKERS:
        if marker.lower() in journal.lower():raise RuntimeError(f'journal gained forbidden side-effect primitive {marker}')
    if re.search(r'journal_is_authority\s*=\s*\$true|production_execution_authorized\s*=\s*\$true|production_mutation_authorized\s*=\s*\$true',journal,re.I):raise RuntimeError('journal authority escaped')
    for marker in ('append_only=$true','requires_journal_phase_before_side_effect=$true','journal_is_authority=$false','production_execution_authorized=$false','production_mutation_authorized=$false'):
        if marker.lower() not in journal.lower():raise RuntimeError(f'journal safety marker missing {marker}')

    bom=b'\xef\xbb\xbf' if addon.startswith(b'\xef\xbb\xbf') else b''
    text=addon[len(bom):].decode('utf-8').replace('\r\n','\n')
    existing=set(functions(text));journal_funcs=functions(journal);collisions=sorted(existing&set(journal_funcs))
    if collisions:raise RuntimeError(f'journal function collision(s): {collisions}')
    missing=[x for x in REQUIRED_JOURNAL_FUNCTIONS if x not in journal_funcs]
    if missing:raise RuntimeError(f'journal required export(s) missing: {missing}')

    anchor='function Test-Due {'
    text=replace_once(text,anchor,journal+'\n\n'+SELFTEST.rstrip()+'\n\n'+anchor,'journal insertion')
    selftest=function_block(text,'Invoke-AddonSelfTest')
    hook='    try { Invoke-CustomAppProductionFullChainIntegratedSelfTestV010 } catch { $errors.Add("Custom App production full-chain integration self-test failed: $($_.Exception.Message)") }'
    replacement=hook+'\n    try { Invoke-CustomAppProductionCrashJournalIntegratedSelfTestV010 } catch { $errors.Add("Custom App production crash journal integrated self-test failed: $($_.Exception.Message)") }'
    selftest=replace_once(selftest,hook,replacement,'journal SelfTest hook')
    text=replace_function(text,'Invoke-AddonSelfTest',selftest)

    orch=function_block(text,'Invoke-CustomAppProductionFullChainV010')
    for name in journal_funcs:
        if name in orch:raise RuntimeError(f'hard-disabled full-chain orchestrator gained journal call: {name}')
    if 'Custom App production full-chain execution is intentionally unavailable in integration-only candidate.' not in orch:raise RuntimeError('full-chain hard-disable throw drift')

    parent_funcs=set(existing);leaks=[]
    for name in sorted(parent_funcs):
        if name in {'Invoke-CustomAppProductionFullChainIntegratedSelfTestV010','Invoke-AddonSelfTest'}:continue
        block=function_block(text,name)
        for entry in DANGEROUS_ENTRYPOINTS:
            if entry in block and entry!=name:leaks.append(f'{name}->{entry}')
    if leaks:raise RuntimeError(f'normal-path mutation entrypoint leak after journal integration: {leaks}')
    return bom+text.encode('utf-8'),{'journal_function_count':len(journal_funcs),'journal_collisions':collisions,'normal_path_leaks':leaks}

def validate(main:bytes,addon:bytes,meta:dict)->dict:
    if (len(main),sha(main))!=PARENT_MAIN:raise RuntimeError('journal integration changed Spotify Control')
    text=addon.decode('utf-8-sig').replace('\r\n','\n')
    registry=function_block(text,'Get-AddonPolicyRegistry')
    auto=re.findall(r"name='([^']+)'.*?mutation_mode='auto'",registry,re.I)
    if sorted(x.lower() for x in auto)!=sorted(x.lower() for x in EXPECTED_AUTO):raise RuntimeError(f'auto authority drift {auto}')
    if '$script:CustomAppProductionPipelineEnabled = $false' not in text:raise RuntimeError('hard-disabled production gate missing')
    if 'CUSTOM_APP_PRODUCTION_CRASH_JOURNAL_INTEGRATED_SELFTEST_V010_PASS' not in text:raise RuntimeError('journal integrated selftest marker missing')
    return {'production_main_changed':False,'parent_full_chain_head':FULL_CHAIN_HEAD,'crash_journal_head':JOURNAL_HEAD,'pipeline_enabled':False,'pipeline_enablement_implemented':False,'generic_auto_authority_expanded':False,'auto_authority':EXPECTED_AUTO,**meta}

def build()->None:
    main,addon,collector,reader=build_parent();candidate,meta=integrate(addon);report=validate(main,candidate,meta)
    OUT.mkdir(parents=True,exist_ok=True)
    (OUT/'spotify-control.ps1').write_bytes(main);(OUT/'addon-manager.ps1').write_bytes(candidate);(OUT/'Collect-Marketplace-Records.ps1').write_bytes(collector);(OUT/'LevelDbReadOnly.cs').write_bytes(reader)
    payload={'schema':1,'candidate_version':'0.6.29-validation-production-full-chain-journal-integration-v0.1.0','candidate_main':{'size':len(main),'sha256':sha(main)},'candidate_addon':{'size':len(candidate),'sha256':sha(candidate)},**report}
    REPORT.write_text(json.dumps(payload,indent=2,sort_keys=True)+'\n',encoding='utf-8',newline='\n')
    print('CUSTOM_APP_PRODUCTION_FULL_CHAIN_JOURNAL_INTEGRATION_BUILD_PASS',len(main),sha(main),len(candidate),sha(candidate))

if __name__=='__main__':build()
