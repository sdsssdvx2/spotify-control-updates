from __future__ import annotations
from pathlib import Path
import hashlib, json, re, subprocess

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
OUT=HERE/'out'/'bin'
REPORT=HERE/'candidate-validation.json'

PRODUCTION_MAIN='d38e88d9ae99f6a4983e2ad64f74f6fce7e6cde2'
PARENT_JOURNAL_HEAD='f870ee7df375284a98af5870fe4a51cf1b4ed69c'
PARENT_BUILDER='validation/custom-app-production-full-chain-journal-integration-v0.1.0/build_candidate.py'
PARENT_BUILDER_BLOB='4fc3599a0a886089526f14ad0b0a044c78068e5a'
PARENT_ADDON=(973527,'3eac8cf4bfdcbbc38e7d4c01186a583fd13f96a27a98d8f6903147a4341da823')
PARENT_MAIN=(284327,'69ef7fb3ca57b4d5faac6873ac06dffc38f6e5b0d1ad8fc31fcbe2bb236f5c99')
RECOVERY_TIP='2ad528b8a969fd45e88168d22ea787984f5e2714'
EXPECTED_AUTO=['better-local-files','eternal-jukebox','ivLyrics','playlist-maker','tagify']

MODULES=[
 ('plan','b266bad660d4b7bc87e7093c5b12f0cff1dc466f','validation/custom-app-production-recovery-plan-contract-v0.1.0/custom-app-production-recovery-plan.ps1','ae49409973164052d5830b981d804707f9d62b6c'),
 ('preflight','4bfbf485838d8b056cd9daa15d949af7d9b86281','validation/custom-app-production-recovery-preflight-v0.1.0/custom-app-production-recovery-preflight.ps1','b1816a24849a559b4da2537aa1b2436124fbee50'),
 ('execution-admission','ffb5aad4a605691ee7b80392498b0cb6fa4e4052','validation/custom-app-production-recovery-execution-admission-v0.1.0/custom-app-production-recovery-execution-admission.ps1','e8804a7c53ad0d3e5420e037d468d9c397e52529'),
 ('recovery-evidence','993af44afee9adb0c28e5fb702cb6ccfbd7cd99c','validation/custom-app-production-recovery-evidence-envelope-v0.1.0/custom-app-production-recovery-evidence.ps1','910b1c500d33d6d6e0ad403c701f4c08f473f1a3'),
 ('evidence-admission-integration','5232e5adeb13e6942acb210b3cd13058e1eaaf05','validation/custom-app-production-recovery-evidence-admission-integration-v0.1.0/custom-app-production-recovery-evidence-admission-integration.ps1','c92c727b5a2217f5b84a1072608bfc4662e68926'),
 ('cleanup-resume-admission','d3969a746ed1736fe93586bd025116c2526fbff5','validation/custom-app-production-recovery-cleanup-resume-admission-v0.1.0/custom-app-production-recovery-cleanup-resume-admission.ps1','387d97b10d493b3794b24fba2bac67cf39491444'),
 ('restore-resume-admission','d9a1face71511bdaeeef4e8c761415ef9ec95fc0','validation/custom-app-production-recovery-restore-resume-admission-v0.1.0/custom-app-production-recovery-restore-resume-admission.ps1','0273d7e28a56759b1d0ec9cbf037483b04d98d63'),
 ('restore-executor','c3e1f960447ba84d2410af9c37a22a384f2a5436','validation/custom-app-production-recovery-restore-executor-v0.1.0/custom-app-production-recovery-restore-executor.ps1','5fec613c460619da5dbfe88fca5c7334e9e93f76'),
 ('completion-evidence','6d0e964307aaf0c0a8aeece98d5597e81721538e','validation/custom-app-production-recovery-completion-evidence-v0.1.0/custom-app-production-recovery-completion-evidence.ps1','3795f900cbf8ded834f721f7db7b126aa264b0e8'),
 ('retirement-admission','16cac85b7bde1b652be67e8d657136409ec7f8b9','validation/custom-app-production-recovery-artifact-retirement-admission-v0.1.0/custom-app-production-recovery-artifact-retirement-admission.ps1','ec8aec5393f30923226f48df9850fded26ca11c6'),
 ('retirement-executor','3867ceeb56e5c21f0047946af87fb69f6601ef37','validation/custom-app-production-recovery-artifact-retirement-executor-v0.1.0/custom-app-production-recovery-artifact-retirement-executor.ps1','be4ae0b1d67339f80c71a47ecbff8cc9066fff61'),
 ('completion-retirement-bridge','894c5013df0a2f1c17483425a31f49d0f9eaa99d','validation/custom-app-production-recovery-completion-retirement-admission-integration-v0.1.0/custom-app-production-recovery-completion-retirement-admission-integration.ps1','92f2b13f49b0ef6bb6ded173e4e992f53bfdf7b1'),
 ('retirement-resume-executor','2ad528b8a969fd45e88168d22ea787984f5e2714','validation/custom-app-production-recovery-artifact-retirement-resume-executor-v0.1.0/custom-app-production-recovery-artifact-retirement-resume-executor.ps1','2acd062e04ec125e8f44edf31def175a4eb73510'),
]

REQUIRED_BASE=[
 'Get-CustomAppLocalRuntimeBaseline','Get-CustomAppUpdateTreeSnapshotV010','Get-CustomAppStageWorkspaceRootV010',
 'Test-CustomAppProductionPersistenceBackupV010','Restore-CustomAppProductionAtomicLiveSwapV010',
 'Open-CustomAppProductionSpicetifyExecutableV010','Invoke-CustomAppProductionExactSpicetifyApplyProcessV010',
 'Remove-CustomAppProductionPostApplyBoundedArtifactV010','Read-CustomAppProductionCrashJournalV010',
 'Append-CustomAppProductionCrashJournalPhaseV010','Invoke-CustomAppProductionFullChainV010'
]
REQUIRED_RECOVERY=[
 'Resolve-CustomAppProductionRecoveryPlanV010','Resolve-CustomAppProductionRecoveryPreflightV010',
 'Resolve-CustomAppProductionRecoveryExecutionAdmissionV010','Write-CustomAppProductionRecoveryEvidenceV010','Read-CustomAppProductionRecoveryEvidenceV010',
 'Resolve-CustomAppProductionRecoveryEvidenceAdmissionIntegrationV010','Resolve-CustomAppProductionRecoveryCleanupResumeAdmissionV010',
 'Resolve-CustomAppProductionRecoveryRestoreResumeAdmissionV010','Invoke-CustomAppProductionRecoveryRestoreExecutorV010',
 'Write-CustomAppProductionRecoveryCompletionEvidenceV010','Read-CustomAppProductionRecoveryCompletionEvidenceV010',
 'Resolve-CustomAppProductionRecoveryArtifactRetirementAdmissionV010','Invoke-CustomAppProductionRecoveryArtifactRetirementExecutorV010',
 'Resolve-CustomAppProductionRecoveryCompletionRetirementAdmissionIntegrationV010','Invoke-CustomAppProductionRecoveryArtifactRetirementResumeExecutorV010'
]

SELFTEST=r'''function Invoke-CustomAppProductionRecoveryStackHardDisabledSelfTestV010 {
    if([bool]$script:CustomAppProductionPipelineEnabled){throw 'Recovery stack integration observed enabled production pipeline.'}
    $required=@(
        'Resolve-CustomAppProductionRecoveryPlanV010','Resolve-CustomAppProductionRecoveryPreflightV010',
        'Resolve-CustomAppProductionRecoveryExecutionAdmissionV010','Write-CustomAppProductionRecoveryEvidenceV010','Read-CustomAppProductionRecoveryEvidenceV010',
        'Resolve-CustomAppProductionRecoveryEvidenceAdmissionIntegrationV010','Resolve-CustomAppProductionRecoveryCleanupResumeAdmissionV010',
        'Resolve-CustomAppProductionRecoveryRestoreResumeAdmissionV010','Invoke-CustomAppProductionRecoveryRestoreExecutorV010',
        'Write-CustomAppProductionRecoveryCompletionEvidenceV010','Read-CustomAppProductionRecoveryCompletionEvidenceV010',
        'Resolve-CustomAppProductionRecoveryArtifactRetirementAdmissionV010','Invoke-CustomAppProductionRecoveryArtifactRetirementExecutorV010',
        'Resolve-CustomAppProductionRecoveryCompletionRetirementAdmissionIntegrationV010','Invoke-CustomAppProductionRecoveryArtifactRetirementResumeExecutorV010'
    )
    foreach($name in $required){if(-not(Get-Command $name -CommandType Function -ErrorAction SilentlyContinue)){throw ('Integrated recovery function missing: '+$name)}}
    if([string]$CustomAppProductionRecoveryPlanManagedBy -cne 'custom-app-production-recovery-plan-v1'){throw 'Recovery plan owner drift.'}
    if([string]$CustomAppProductionRecoveryRestoreExecutorQualifiedAdmissionHead -cne 'd9a1face71511bdaeeef4e8c761415ef9ec95fc0'){throw 'Recovery restore executor parent drift.'}
    if([string]$CustomAppProductionRecoveryCompletionEvidenceQualifiedExecutorHead -cne 'c3e1f960447ba84d2410af9c37a22a384f2a5436'){throw 'Recovery completion evidence parent drift.'}
    if([string]$CustomAppProductionRecoveryArtifactRetirementExecutorQualifiedAdmissionHead -cne '16cac85b7bde1b652be67e8d657136409ec7f8b9'){throw 'Recovery retirement executor parent drift.'}
    if([string]$CustomAppProductionRecoveryArtifactRetirementResumeExecutorQualifiedBridgeHead -cne '894c5013df0a2f1c17483425a31f49d0f9eaa99d'){throw 'Recovery retirement resume bridge drift.'}
    if([string]$CustomAppProductionRecoveryArtifactRetirementResumeExecutorQualifiedExecutorHead -cne '3867ceeb56e5c21f0047946af87fb69f6601ef37'){throw 'Recovery retirement resume executor parent drift.'}
    Write-Host 'CUSTOM_APP_PRODUCTION_RECOVERY_STACK_HARD_DISABLED_SELFTEST_V010_PASS loaded-but-unreachable'
}
'''

def sha(b:bytes)->str:return hashlib.sha256(b).hexdigest()
def git_blob(commit:str,path:str)->str:return subprocess.check_output(['git','rev-parse',f'{commit}:{path}'],cwd=ROOT,text=True).strip()
def git_bytes(commit:str,path:str)->bytes:return subprocess.check_output(['git','show',f'{commit}:{path}'],cwd=ROOT)
def functions(text:str)->list[str]:return re.findall(r'(?im)^\s*function\s+([A-Za-z0-9_-]+)\s*\{',text)
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
    if git_blob(PARENT_JOURNAL_HEAD,PARENT_BUILDER)!=PARENT_BUILDER_BLOB:raise RuntimeError('journal integration builder pin drift')
    subprocess.check_call(['python',str(ROOT/PARENT_BUILDER)],cwd=ROOT)
    d=ROOT/'validation/custom-app-production-full-chain-journal-integration-v0.1.0/out/bin'
    main=(d/'spotify-control.ps1').read_bytes();addon=(d/'addon-manager.ps1').read_bytes();collector=(d/'Collect-Marketplace-Records.ps1').read_bytes();reader=(d/'LevelDbReadOnly.cs').read_bytes()
    if (len(main),sha(main))!=PARENT_MAIN:raise RuntimeError(f'parent main drift {len(main)} {sha(main)}')
    if (len(addon),sha(addon))!=PARENT_ADDON:raise RuntimeError(f'parent addon drift {len(addon)} {sha(addon)}')
    return main,addon,collector,reader

def integrate(addon:bytes)->tuple[bytes,dict]:
    bom=b'\xef\xbb\xbf' if addon.startswith(b'\xef\xbb\xbf') else b''
    parent=addon[len(bom):].decode('utf-8').replace('\r\n','\n')
    parent_funcs=functions(parent);parent_set=set(parent_funcs)
    missing_base=[x for x in REQUIRED_BASE if x not in parent_set]
    if missing_base:raise RuntimeError(f'journal-integrated parent missing recovery dependency functions: {missing_base}')
    if '$script:CustomAppProductionPipelineEnabled = $false' not in parent:raise RuntimeError('parent production pipeline hard-disable missing')

    module_text=[];module_functions=[];seen=set(parent_set);meta=[]
    for label,commit,path,blob in MODULES:
        actual=git_blob(commit,path)
        if actual!=blob:raise RuntimeError(f'{label} blob pin drift {actual} != {blob}')
        text=git_bytes(commit,path).decode('utf-8-sig').replace('\r\n','\n').strip()
        funcs=functions(text)
        if not funcs:raise RuntimeError(f'{label} contains no functions')
        collisions=sorted(seen & set(funcs))
        if collisions:raise RuntimeError(f'{label} function collision(s): {collisions}')
        seen.update(funcs);module_functions.extend(funcs);module_text.append(text)
        meta.append({'label':label,'head':commit,'path':path,'blob':blob,'function_count':len(funcs)})
    missing_recovery=[x for x in REQUIRED_RECOVERY if x not in seen]
    if missing_recovery:raise RuntimeError(f'recovery required export(s) missing: {missing_recovery}')

    first=re.search(r'(?im)^\s*function\s+[A-Za-z0-9_-]+\s*\{',parent)
    if not first:raise RuntimeError('parent first function not found')
    payload='\n\n'.join(module_text)+'\n\n'+SELFTEST.rstrip()+'\n\n'
    text=parent[:first.start()]+payload+parent[first.start():]

    selftest=function_block(text,'Invoke-AddonSelfTest')
    hook='    try { Invoke-CustomAppProductionCrashJournalIntegratedSelfTestV010 } catch { $errors.Add("Custom App production crash journal integrated self-test failed: $($_.Exception.Message)") }'
    replacement=hook+'\n    try { Invoke-CustomAppProductionRecoveryStackHardDisabledSelfTestV010 } catch { $errors.Add("Custom App production recovery stack hard-disabled integration self-test failed: $($_.Exception.Message)") }'
    selftest=replace_once(selftest,hook,replacement,'recovery stack SelfTest hook')
    text=replace_function(text,'Invoke-AddonSelfTest',selftest)

    candidate_funcs=set(functions(text))
    missing_after=[x for x in REQUIRED_RECOVERY if x not in candidate_funcs]
    if missing_after:raise RuntimeError(f'candidate recovery exports missing: {missing_after}')

    changed=[]
    for name in parent_funcs:
        if name=='Invoke-AddonSelfTest':continue
        if function_block(parent,name)!=function_block(text,name):changed.append(name)
    if changed:raise RuntimeError(f'pre-existing normal-path function(s) changed by recovery integration: {changed}')
    if function_block(parent,'Invoke-CustomAppProductionFullChainV010')!=function_block(text,'Invoke-CustomAppProductionFullChainV010'):
        raise RuntimeError('hard-disabled full-chain orchestrator changed')
    orch=function_block(text,'Invoke-CustomAppProductionFullChainV010')
    if 'Custom App production full-chain execution is intentionally unavailable in integration-only candidate.' not in orch:raise RuntimeError('full-chain hard-disable throw drift')
    for entry in REQUIRED_RECOVERY:
        if entry in orch:raise RuntimeError(f'hard-disabled full-chain orchestrator gained recovery call: {entry}')
    if '$script:CustomAppProductionPipelineEnabled = $false' not in text:raise RuntimeError('recovery integration enabled production pipeline')
    return bom+text.encode('utf-8'),{'module_count':len(MODULES),'module_function_count':len(module_functions),'preexisting_functions_changed':changed,'modules':meta}

def validate(main:bytes,addon:bytes,meta:dict)->dict:
    if (len(main),sha(main))!=PARENT_MAIN:raise RuntimeError('recovery stack integration changed Spotify Control')
    text=addon.decode('utf-8-sig').replace('\r\n','\n')
    registry=function_block(text,'Get-AddonPolicyRegistry')
    auto=re.findall(r"name='([^']+)'.*?mutation_mode='auto'",registry,re.I)
    if sorted(x.lower() for x in auto)!=sorted(x.lower() for x in EXPECTED_AUTO):raise RuntimeError(f'auto authority drift {auto}')
    if '$script:CustomAppProductionPipelineEnabled = $false' not in text:raise RuntimeError('hard-disabled production gate missing')
    if 'CUSTOM_APP_PRODUCTION_RECOVERY_STACK_HARD_DISABLED_SELFTEST_V010_PASS' not in text:raise RuntimeError('recovery integrated SelfTest marker missing')
    return {'production_main_changed':False,'production_main_head':PRODUCTION_MAIN,'parent_journal_integration_head':PARENT_JOURNAL_HEAD,'recovery_tip':RECOVERY_TIP,'pipeline_enabled':False,'pipeline_enablement_implemented':False,'recovery_normal_path_wiring_added':False,'generic_auto_authority_expanded':False,'auto_authority':EXPECTED_AUTO,**meta}

def build()->None:
    main,addon,collector,reader=build_parent();candidate,meta=integrate(addon);report=validate(main,candidate,meta)
    OUT.mkdir(parents=True,exist_ok=True)
    (OUT/'spotify-control.ps1').write_bytes(main);(OUT/'addon-manager.ps1').write_bytes(candidate);(OUT/'Collect-Marketplace-Records.ps1').write_bytes(collector);(OUT/'LevelDbReadOnly.cs').write_bytes(reader)
    payload={'schema':1,'candidate_version':'0.6.29-validation-recovery-stack-hard-disabled-integration-v0.1.0','candidate_main':{'size':len(main),'sha256':sha(main)},'candidate_addon':{'size':len(candidate),'sha256':sha(candidate)},**report}
    REPORT.write_text(json.dumps(payload,indent=2,sort_keys=True)+'\n',encoding='utf-8',newline='\n')
    print('CUSTOM_APP_PRODUCTION_RECOVERY_STACK_HARD_DISABLED_INTEGRATION_BUILD_PASS',len(main),sha(main),len(candidate),sha(candidate),len(MODULES),meta['module_function_count'])

if __name__=='__main__':build()
