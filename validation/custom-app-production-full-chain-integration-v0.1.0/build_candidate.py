from __future__ import annotations
from pathlib import Path
import argparse, hashlib, json, re, subprocess

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUT = HERE / 'out' / 'bin'
REPORT = HERE / 'candidate-validation.json'

PRODUCTION_BASE = 'd38e88d9ae99f6a4983e2ad64f74f6fce7e6cde2'
CLEANUP_HEAD = '67458cbb96b5d1ed92e26c2b81debd6894044749'
BASE_HEAD = 'd92daa3006093a7d966083193302965ee01905f6'
BASE_PATH = 'validation/custom-app-remote-binding-observer-v0.4.1/build_candidate_v041.py'
BASE_BLOB = '92eb87048eac882483bee1ed97bde598cff57e7b'
EXPECTED_MAIN = (284327, '69ef7fb3ca57b4d5faac6873ac06dffc38f6e5b0d1ad8fc31fcbe2bb236f5c99')
EXPECTED_BASE_ADDON = (523216, 'b2cec989ef399aed4a8763105121b21181ffb493ed9e3e884baa1d62a634f94b')
AUTHORIZED = ['better-local-files', 'eternal-jukebox', 'ivLyrics', 'playlist-maker', 'tagify']

# Order is dependency order. Every source is immutable by commit + blob.
MODULES = [
    ('update-transaction','1a2461a6929e9cabd50d27f95e0744f83443b9e8','validation/custom-app-update-transaction-protocol-v0.1.0/custom-app-update-transaction.ps1','47b4d4bb08fe7b14ad43de4300556430eb638869'),
    ('stage-acquisition','c420a1df6f306c7ba74772b91241cb14abd04738','validation/custom-app-stage-acquisition-contract-v0.1.0/custom-app-stage-acquisition.ps1','e2f2fc656235883d2a82b106289973f6ded409a5'),
    ('promotion-eligibility','979e9d6362ead31016b9532f98629d6bcc2bbb56','validation/custom-app-promotion-eligibility-gate-v0.1.0/custom-app-promotion-eligibility.ps1','94c1b0ba8f2454078252a723f89ccc0327cbc181'),
    ('live-attested-production-admission','c128595c3ac7eab338f5d23d7041ae56a6822948','validation/custom-app-live-attested-production-admission-v0.1.0/custom-app-live-attested-production-admission.ps1','9bdcbf0a928539e5f3c4e28b7de1d68589e18525'),
    ('production-permit','d77f646d23652b0f066248230756d9e207a10fbd','validation/custom-app-production-permit-v0.1.0/custom-app-production-permit.ps1','2aff85ca092848ea254423bf5441b1a077dea5b7'),
    ('permit-reservation','edb8a34c61abb28838ba6ca89cf539bdf28bec2a','validation/custom-app-production-permit-reservation-v0.1.0/custom-app-production-permit-reservation.ps1','54c1c6a3be4b8646d87a06cef9903ebb01479fd6'),
    ('executor-consumption','ed7fa27fc9bfaa78858e130743a2de508a3c0bf9','validation/custom-app-production-executor-consumption-v0.1.0/custom-app-production-executor-consumption.ps1','ac1459254ce060806a338a443c755bbc9f65c9a2'),
    ('consumption-persistence','1b680f0fc637b393aa7571690c8aa40adda59800','validation/custom-app-production-consumption-persistence-v0.1.0/custom-app-production-consumption-persistence.ps1','d5b70c943d0880e98ee907ae52d4c02ad8720f73'),
    ('consumption-persistence-v011','1b680f0fc637b393aa7571690c8aa40adda59800','validation/custom-app-production-consumption-persistence-v0.1.0/custom-app-production-consumption-persistence-contract-v011.ps1','07de3a6d3aec00636d8b1c7bd20dcbc72d1b7ada'),
    ('executor-start','29fe26f505d2f0fb8d9f47e76b5b819ebe1c129d','validation/custom-app-production-executor-start-gate-v0.1.0/custom-app-production-executor-start-gate.ps1','1fa3ca9e77b4c8a48ef56afd656fd102e1636676'),
    ('stage-admission','13f4314b81816b1b1c3bb3c2fb4280b6c015f8de','validation/custom-app-production-stage-acquisition-admission-v0.1.0/custom-app-production-stage-acquisition-admission.ps1','df343c9da93444cdb86753ffa17db8b260baec0c'),
    ('stage-executor','6ba560e7980c3492fb032ebc720f029caa97b15c','validation/custom-app-production-stage-executor-v0.1.0/custom-app-production-stage-executor.ps1','349d4028997a9cc7a94540286c8b9ba6d6a5b050'),
    ('pre-apply','ddc84778ab4815d4174198727b8d1d052a02182e','validation/custom-app-production-pre-apply-preparation-v0.1.0/custom-app-production-pre-apply-preparation.ps1','9b039819e7b2278fe4cf15c8585336dd07a8e8e3'),
    ('atomic-live-swap','574fe182168271fa3497d58e269e9af1f60d9033','validation/custom-app-production-atomic-live-swap-v0.1.0/custom-app-production-atomic-live-swap.ps1','e91fa6a125f77352907c1119f6d9f47be9682550'),
    ('transaction-finalization','75a39eea7b0ef7d35d193962607752ef1a873ae0','validation/custom-app-production-transaction-finalization-v0.1.0/custom-app-production-transaction-finalization.ps1','2958ae3f92173215d32ef8bf284a9433c52caa61'),
    ('post-swap-apply-admission','a4f6d4772afb895dd253a4c82a21643711ac0829','validation/custom-app-production-post-swap-apply-admission-v0.1.0/custom-app-production-post-swap-apply-admission.ps1','190382903e23d7abc59b525829c5ecd5c76f7ff1'),
    ('spicetify-apply-executor','fe07d410531ea13c8fca379b01405631a3763e84','validation/custom-app-production-spicetify-apply-executor-v0.1.0/custom-app-production-spicetify-apply-executor.ps1','f7372b069fbfe6a0f8d8a0aad45312ffd33d9f0a'),
    ('post-apply-cleanup','67458cbb96b5d1ed92e26c2b81debd6894044749','validation/custom-app-production-post-apply-commit-cleanup-v0.1.0/custom-app-production-post-apply-commit-cleanup.ps1','3b14280d727287252f71611e4424d78e5705c2f1'),
    ('post-apply-finalization-receipt-v011','67458cbb96b5d1ed92e26c2b81debd6894044749','validation/custom-app-production-post-apply-commit-cleanup-v0.1.0/custom-app-production-post-apply-commit-cleanup-finalization-receipt-v011.ps1','31da8fa6253679f22edc07a6b5c00a47eb26c64d'),
]

# The cleanup receipt overlay intentionally replaces exactly this earlier validator.
ALLOWED_OVERRIDES = {'Test-CustomAppProductionTransactionFinalizationResultV010'}
REQUIRED_FUNCTIONS = [
    'New-CustomAppProductionPermitV010','Reserve-CustomAppProductionPermitV010',
    'Consume-CustomAppProductionPermitReservationV010','Read-CustomAppProductionConsumptionStoreV010',
    'Resolve-CustomAppProductionExecutorStartV010','Resolve-CustomAppProductionStageAdmissionV010',
    'Invoke-CustomAppProductionStageExecutorV010','Invoke-CustomAppProductionPreApplyPreparationV010',
    'Invoke-CustomAppProductionAtomicLiveSwapV010','Invoke-CustomAppProductionTransactionFinalizationV010',
    'Resolve-CustomAppProductionPostSwapApplyAdmissionV010','Invoke-CustomAppProductionSpicetifyApplyExecutorV010',
    'Invoke-CustomAppProductionPostApplyCommitCleanupV010',
]
DANGEROUS_ENTRYPOINTS = {
    'Invoke-CustomAppProductionStageExecutorV010',
    'Invoke-CustomAppProductionPreApplyPreparationV010',
    'Invoke-CustomAppProductionAtomicLiveSwapV010',
    'Invoke-CustomAppProductionSpicetifyApplyExecutorV010',
    'Invoke-CustomAppProductionPostApplyCommitCleanupV010',
    'Invoke-CustomAppProductionFullChainV010',
}

INTEGRATION_GATE = r'''$script:CustomAppProductionFullChainIntegrated = $true
$script:CustomAppProductionPipelineEnabled = $false

function Invoke-CustomAppProductionFullChainV010 {
    # Integration-only checkpoint. Deliberately impossible to enable into a mutating path.
    if([bool]$script:CustomAppProductionPipelineEnabled){
        throw 'Custom App production full-chain execution is intentionally unavailable in integration-only candidate.'
    }
    return [pscustomobject]@{
        schema=1; managed_by='custom-app-production-full-chain-integration-v1'; integrated=$true; enabled=$false
        reason='integration-only-hard-disabled'; result_is_authority=$false; spicetify_apply_authorized=$false
        production_execution_authorized=$false; production_mutation_authorized=$false
    }
}

function Invoke-CustomAppProductionFullChainIntegratedSelfTestV010 {
    if(-not [bool]$script:CustomAppProductionFullChainIntegrated){ throw 'Full-chain integration marker missing.' }
    if([bool]$script:CustomAppProductionPipelineEnabled){ throw 'Full-chain integration gate unexpectedly enabled.' }
    $required=@(
        'New-CustomAppProductionPermitV010','Reserve-CustomAppProductionPermitV010',
        'Consume-CustomAppProductionPermitReservationV010','Read-CustomAppProductionConsumptionStoreV010',
        'Resolve-CustomAppProductionExecutorStartV010','Resolve-CustomAppProductionStageAdmissionV010',
        'Invoke-CustomAppProductionStageExecutorV010','Invoke-CustomAppProductionPreApplyPreparationV010',
        'Invoke-CustomAppProductionAtomicLiveSwapV010','Invoke-CustomAppProductionTransactionFinalizationV010',
        'Resolve-CustomAppProductionPostSwapApplyAdmissionV010','Invoke-CustomAppProductionSpicetifyApplyExecutorV010',
        'Invoke-CustomAppProductionPostApplyCommitCleanupV010'
    )
    foreach($name in $required){ if(-not (Get-Command $name -CommandType Function -ErrorAction SilentlyContinue)){ throw ('Integrated production function missing: '+$name) } }
    $r=Invoke-CustomAppProductionFullChainV010
    if($null -eq $r -or [bool]$r.enabled -or [bool]$r.result_is_authority -or [bool]$r.spicetify_apply_authorized -or [bool]$r.production_execution_authorized -or [bool]$r.production_mutation_authorized){ throw 'Integration-only pipeline gate escaped deny mode.' }
    Write-Host 'CUSTOM_APP_PRODUCTION_FULL_CHAIN_INTEGRATED_SELFTEST_V010_PASS hard-disabled zero-authority'
}
'''


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def git_blob(commit: str, path: str) -> str:
    return subprocess.check_output(['git','rev-parse',f'{commit}:{path}'], cwd=ROOT, text=True).strip()


def git_bytes(commit: str, path: str) -> bytes:
    return subprocess.check_output(['git','show',f'{commit}:{path}'], cwd=ROOT)


def load_pinned(label: str, commit: str, path: str, blob: str) -> str:
    actual=git_blob(commit,path)
    if actual != blob:
        raise RuntimeError(f'{label} blob drift: {actual} != {blob}')
    return git_bytes(commit,path).decode('utf-8-sig').replace('\r\n','\n').rstrip()


def functions(text: str) -> list[str]:
    return re.findall(r'(?im)^\s*function\s+([A-Za-z0-9_-]+)\s*\{', text)


def function_bounds(text: str, name: str) -> tuple[int,int]:
    m=re.search(rf'(?im)^\s*function\s+{re.escape(name)}\s*\{{',text)
    if not m: raise RuntimeError(f'missing function {name}')
    n=re.search(r'(?im)^\s*function\s+[A-Za-z0-9_-]+\s*\{',text[m.end():])
    return m.start(), (m.end()+n.start() if n else len(text))


def function_block(text: str, name: str) -> str:
    a,b=function_bounds(text,name); return text[a:b]


def replace_function(text: str, name: str, replacement: str) -> str:
    a,b=function_bounds(text,name); return text[:a]+replacement.rstrip()+'\n\n'+text[b:].lstrip('\n')


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count=text.count(old)
    if count != 1: raise RuntimeError(f'{label} anchor count drift: {count}')
    return text.replace(old,new,1)


def build_base() -> tuple[bytes,bytes,bytes,bytes]:
    actual=git_blob(BASE_HEAD,BASE_PATH)
    if actual != BASE_BLOB: raise RuntimeError(f'v0.4.1 builder drift: {actual} != {BASE_BLOB}')
    source=git_bytes(BASE_HEAD,BASE_PATH)
    fake=ROOT/'validation/custom-app-remote-binding-observer-v0.4.1/_full_chain_pinned_builder.py'
    ns={'__file__':str(fake),'__name__':'full_chain_pinned_v041'}
    exec(compile(source,str(fake),'exec'),ns); ns['build']()
    base=ROOT/'validation/custom-app-remote-binding-observer-v0.4.0/out/bin'
    main=(base/'spotify-control.ps1').read_bytes(); addon=(base/'addon-manager.ps1').read_bytes()
    collector=(base/'Collect-Marketplace-Records.ps1').read_bytes(); reader=(base/'LevelDbReadOnly.cs').read_bytes()
    if (len(main),sha(main)) != EXPECTED_MAIN: raise RuntimeError(f'base main drift: {len(main)} {sha(main)}')
    if (len(addon),sha(addon)) != EXPECTED_BASE_ADDON: raise RuntimeError(f'base addon drift: {len(addon)} {sha(addon)}')
    return main,addon,collector,reader


def integrate(addon: bytes) -> tuple[bytes,dict]:
    bom=b'\xef\xbb\xbf' if addon.startswith(b'\xef\xbb\xbf') else b''
    base_text=addon[len(bom):].decode('utf-8').replace('\r\n','\n')
    base_function_names=set(functions(base_text))
    seen=set(base_function_names)
    chunks=[]; override_count=0; module_report=[]
    for label,commit,path,blob in MODULES:
        src=load_pinned(label,commit,path,blob)
        names=functions(src)
        dup=sorted(set(names)&seen)
        unexpected=[x for x in dup if x not in ALLOWED_OVERRIDES]
        if unexpected:
            raise RuntimeError(f'{label} unexpected function collision(s): {unexpected}')
        allowed=[x for x in dup if x in ALLOWED_OVERRIDES]
        override_count += len(allowed)
        # For an intentional override, remove the earlier definition from the assembled chunks/base
        # only if it was already in base; otherwise PowerShell's later definition semantics are used.
        chunks.append(src)
        seen.update(names)
        module_report.append({'label':label,'commit':commit,'path':path,'blob':blob,'functions':len(names),'allowed_overrides':allowed})
    if override_count != 1:
        raise RuntimeError(f'intentional override count drift: {override_count} != 1')

    insertion='\n\n'.join(chunks+[INTEGRATION_GATE.rstrip()])
    anchor='function Test-Due {'
    text=replace_once(base_text,anchor,insertion+'\n\n'+anchor,'full-chain module insertion')

    selftest=function_block(text,'Invoke-AddonSelfTest')
    hook="    try { Invoke-CustomAppRemoteBindingIntegratedSelfTestV040 } catch { $errors.Add(\"Custom App remote binding integrated self-test failed: $($_.Exception.Message)\") }"
    replacement=hook+'\n    try { Invoke-CustomAppProductionFullChainIntegratedSelfTestV010 } catch { $errors.Add("Custom App production full-chain integration self-test failed: $($_.Exception.Message)") }'
    selftest=replace_once(selftest,hook,replacement,'full-chain SelfTest hook')
    text=replace_function(text,'Invoke-AddonSelfTest',selftest)

    # No pre-existing/normal Addon Manager function may call a production mutation entrypoint.
    leaks=[]
    for name in sorted(base_function_names):
        block=function_block(text,name)
        for entry in DANGEROUS_ENTRYPOINTS:
            if entry in block:
                leaks.append(f'{name}->{entry}')
    if leaks: raise RuntimeError(f'normal-path production entrypoint leak: {leaks}')

    # Integrated selftest may call only the hard-disabled orchestrator; the orchestrator itself
    # must not call any mutating stage/apply/cleanup entrypoint in this checkpoint.
    orch=function_block(text,'Invoke-CustomAppProductionFullChainV010')
    for entry in DANGEROUS_ENTRYPOINTS-{'Invoke-CustomAppProductionFullChainV010'}:
        if entry in orch: raise RuntimeError(f'integration-only orchestrator gained mutation call: {entry}')

    return bom+text.encode('utf-8'), {'modules':module_report,'base_function_count':len(base_function_names),'intentional_override_count':override_count,'normal_path_leaks':leaks}


def validate(main: bytes, addon: bytes, meta: dict) -> dict:
    if (len(main),sha(main)) != EXPECTED_MAIN: raise RuntimeError('full-chain integration changed Spotify Control bytes')
    text=addon.decode('utf-8-sig').replace('\r\n','\n')
    registry=function_block(text,'Get-AddonPolicyRegistry')
    auto=re.findall(r"name='([^']+)'.*?mutation_mode='auto'",registry,re.I)
    if sorted(x.lower() for x in auto) != sorted(x.lower() for x in AUTHORIZED):
        raise RuntimeError(f'auto authority drift: {auto}')
    for name in REQUIRED_FUNCTIONS:
        if len(re.findall(rf'(?im)^\s*function\s+{re.escape(name)}\s*\{{',text)) != 1:
            raise RuntimeError(f'required production function count drift: {name}')
    if '$script:CustomAppProductionPipelineEnabled = $false' not in text:
        raise RuntimeError('hard-disabled integration gate missing')
    if "integration-only-hard-disabled" not in text or 'production_mutation_authorized=$false' not in text:
        raise RuntimeError('zero-authority integration receipt marker missing')
    return {
        'auto_authority':AUTHORIZED,
        'production_main_changed':False,
        'full_chain_modules_integrated':len(MODULES),
        'pipeline_enabled_by_default':False,
        'pipeline_enablement_implemented':False,
        'generic_auto_authority_expanded':False,
        **meta,
    }


def build() -> None:
    main,base_addon,collector,reader=build_base()
    candidate,meta=integrate(base_addon)
    result=validate(main,candidate,meta)
    OUT.mkdir(parents=True,exist_ok=True)
    (OUT/'spotify-control.ps1').write_bytes(main)
    (OUT/'addon-manager.ps1').write_bytes(candidate)
    (OUT/'Collect-Marketplace-Records.ps1').write_bytes(collector)
    (OUT/'LevelDbReadOnly.cs').write_bytes(reader)
    report={'schema':1,'production_base':PRODUCTION_BASE,'validated_cleanup_head':CLEANUP_HEAD,'validated_base_builder':{'head':BASE_HEAD,'path':BASE_PATH,'blob':BASE_BLOB},'candidate_version':'0.6.29-validation-production-full-chain-integration-v0.1.0','candidate_main':{'size':len(main),'sha256':sha(main)},'candidate_addon':{'size':len(candidate),'sha256':sha(candidate)},**result}
    REPORT.write_text(json.dumps(report,indent=2,sort_keys=True)+'\n',encoding='utf-8',newline='\n')
    print('CUSTOM_APP_PRODUCTION_FULL_CHAIN_INTEGRATION_BUILD_PASS',len(main),sha(main),len(candidate),sha(candidate))


def main() -> None:
    p=argparse.ArgumentParser();p.add_argument('--build',action='store_true');a=p.parse_args()
    if not a.build:p.error('use --build')
    build()

if __name__=='__main__':main()
