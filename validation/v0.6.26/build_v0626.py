from pathlib import Path
import argparse, hashlib, json, re, subprocess, sys

ROOT = Path(__file__).resolve().parents[2]
BASE_OUT = ROOT / 'validation/v0.6.25/out/bin'
OUT = ROOT / 'validation/v0.6.26/out/bin'
REPORT = ROOT / 'validation/v0.6.26/candidate-validation.json'

BASE_MAIN_SIZE = 284313
BASE_MAIN_SHA = '896bb74e71385b5b6ada118af41cbe9d398dc662ce3719234104028e6eed197f'
BASE_ADDON_SIZE = 282718
BASE_ADDON_SHA = '25ebd0a5d5158f7d3cb4b4ce2ecf89f05f4dad3ef6bc799599e7204ce103c29c'
TARGET_MAIN_SIZE = 284311
TARGET_MAIN_SHA = 'd7b484a2a7b10a27db0f182d71fe36f590784171db7208189540045bcf4f54d1'
TARGET_ADDON_SIZE = 291294
TARGET_ADDON_SHA = '4aa56dd5d4ef07da21d3bdf5c76227fabb49c64767a281b1e11ee48e7211a09f'
REGISTRY_SHA = '0f05406d7152de1d975f888cb8270be8249115211ba9f41e0157342cd42efbd8'
ADAPTER_SHA = 'c0611a7b96f6ff09d1e235119efce2f2def6eb6d0a4e8e93e276cfa622c3c42d'
AUTHORIZED_NAMES = ['better-local-files', 'eternal-jukebox', 'ivLyrics', 'playlist-maker']

VALIDATION_HEAD = '91980963f1bd7cca987a3fc15c0a70074ea72c08'
VALIDATION_PATH = 'validation/tagify-release-provenance-v0.1.0/build_candidate.py'
VALIDATION_BLOB = 'e8fed5168af55843f22c66b5a3a82165b1bb13fe'
VALIDATION_PUSH_RUN = '40453161373'
VALIDATION_PR_RUN = '40453275598'
VALIDATION_STABLE_PR_RUN = '40453275661'
VALIDATION_PR = 82
VALIDATION_PUSH_ARTIFACT = 12710864506
VALIDATION_PUSH_ARTIFACT_DIGEST = 'sha256:22c6ac0f3aa527284fc1ce5fd50426a9bb6b3a46a5c9994d4b68178408f67d6b'
VALIDATION_PR_ARTIFACT = 12711157197
VALIDATION_PR_ARTIFACT_DIGEST = 'sha256:e36662f22d6f85823e69a0df07ff42374276a4d180c4ba599e87ef744cb193c8'

AUDIT_HEAD = '4263a53f145fc602fbe81e0c243f8d7a70f46fc5'
AUDIT_RUN = '40388895760'
AUDIT_ARTIFACT = 12682440808
AUDIT_ARTIFACT_DIGEST = 'sha256:9ed6837dccbf5229a9546a16ef4a35fc933289a28cc4929e45138625bd499f50'
AUDIT_CATALOG_JSON_SHA = '75d66f6e06ec76c8f96fbc7941617e7330844979a87d3297e8e4ff824c3b6a1a'

RELEASES = [
    {'version':'2.5.0','tag':'v2.5.0','asset_size':494087,'asset_sha256':'5a47106d50b08aa377a3402258dee94db63797360e21dccf59f81f0827fcaccc','tree_sha256':'3b5ba1c33e4415fe530a029fd93af8f0fc84748eb2ac432422f31747a40c28dc','file_count':13},
    {'version':'3.0.0','tag':'v3.0.0','asset_size':909371,'asset_sha256':'ee04ec7eeb45054b798337ccd9e08f66a2cc881348f74b7a4d2adfbc93ef07b1','tree_sha256':'ac6d7f7567d78cbfbb37df40dc3d76273df3dde80f0962efaea3a217dcba99d0','file_count':18},
    {'version':'3.1.0','tag':'v3.1.0','asset_size':1355380,'asset_sha256':'a84b9c2aefd43035b16edf537b91652b934c09f1ef5037ed17b3738f1e4ecc91','tree_sha256':'f896dc5f83acd8272315aa171ea7893d744dc029422b15574da9c60190750c4e','file_count':21},
    {'version':'3.2.0','tag':'v3.2.0','asset_size':1436949,'asset_sha256':'346f0e746abf3e29aca754240da2e9d2c87e75d7e35fd27109575fed66629c31','tree_sha256':'516f364e8519983ae1bd64158b552a3bb68ed54414402e4ab9523f3e6abe1559','file_count':22},
    {'version':'3.3.0','tag':'v3.3.0','asset_size':1470208,'asset_sha256':'12f2efc0221014464eff2d5884a83bd05882138e87bcd0c208e734538c71604c','tree_sha256':'108e8afba7bcab8cfe8657431041a0118140a774ba4996e60ce91cfa8a4cf2d9','file_count':22},
    {'version':'3.3.1','tag':'v3.3.1','asset_size':1471676,'asset_sha256':'b7510e525297c297d6007305acef947c35bf2df34e0fae492c41a31f555db957','tree_sha256':'8f8abd6f80f88321d6517c1496c985da146e313a949e80f4e4b41c34ad27178a','file_count':22},
    {'version':'3.3.2','tag':'v3.3.2','asset_size':1554948,'asset_sha256':'5261538c8f596cf179b1f6efd20e0a0a60c73b4cd765115fc6bc25c6a6b3b76b','tree_sha256':'e751c2692d0edb5d63ac359df0b81c024ddca4f02e9de46cd5e4d8f3266bbf71','file_count':22},
]
EXCLUDED = [
    {'versions':['1.0.0','1.0.1','1.0.2','2.0.0','2.1.0','2.1.1'],'reason':'no-exact-release-zip'},
    {'versions':['2.1.2','2.2.0','2.3.0','2.4.0'],'reason':'authenticated-zip-without-Tagify-identity-marker'},
]


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def git_bytes(commit: str, path: str) -> bytes:
    return subprocess.check_output(['git','show',f'{commit}:{path}'], cwd=ROOT)


def git_blob(commit: str, path: str) -> str:
    return subprocess.check_output(['git','rev-parse',f'{commit}:{path}'], cwd=ROOT, text=True).strip()


def function_block(text: str, name: str) -> str:
    marker=f'function {name} {{'
    start=text.find(marker)
    if start < 0: raise RuntimeError(f'missing function {name}')
    nxt=text.find('\nfunction ',start+len(marker))
    return text[start:len(text) if nxt < 0 else nxt]


def build_base():
    subprocess.check_call([sys.executable,str(ROOT/'validation/v0.6.25/build_v0625.py'),'--build'],cwd=ROOT)
    main=(BASE_OUT/'spotify-control.ps1').read_bytes();addon=(BASE_OUT/'addon-manager.ps1').read_bytes()
    if (len(main),sha(main))!=(BASE_MAIN_SIZE,BASE_MAIN_SHA): raise RuntimeError(f'v0.6.25 main base drift: {len(main)} {sha(main)}')
    if (len(addon),sha(addon))!=(BASE_ADDON_SIZE,BASE_ADDON_SHA): raise RuntimeError(f'r14 addon base drift: {len(addon)} {sha(addon)}')
    return main,addon


def build_validated_candidate():
    blob=git_blob(VALIDATION_HEAD,VALIDATION_PATH)
    if blob != VALIDATION_BLOB: raise RuntimeError(f'validated Tagify builder blob drift: {blob}')
    source=git_bytes(VALIDATION_HEAD,VALIDATION_PATH)
    fake=ROOT/VALIDATION_PATH
    ns={'__file__':str(fake),'__name__':'spotify_control_validated_tagify_v010'}
    exec(compile(source,str(fake),'exec'),ns)
    ns['build']()
    source_out=ROOT/'validation/tagify-release-provenance-v0.1.0/out/bin'
    main=(source_out/'spotify-control.ps1').read_bytes();addon=(source_out/'addon-manager.ps1').read_bytes()
    if (len(main),sha(main))!=(TARGET_MAIN_SIZE,TARGET_MAIN_SHA): raise RuntimeError(f'validated v0.6.26 main drift: {len(main)} {sha(main)}')
    if (len(addon),sha(addon))!=(TARGET_ADDON_SIZE,TARGET_ADDON_SHA): raise RuntimeError(f'validated r15 addon drift: {len(addon)} {sha(addon)}')
    return main,addon


def validate_candidate(base_addon: bytes, candidate_addon: bytes):
    base=base_addon.decode('utf-8-sig').replace('\r\n','\n')
    cand=candidate_addon.decode('utf-8-sig').replace('\r\n','\n')
    for name in ('Get-AddonPolicyRegistry','Get-AddonSourceAdapterCatalog'):
        if function_block(base,name)!=function_block(cand,name): raise RuntimeError(f'{name} changed unexpectedly')
    registry=function_block(cand,'Get-AddonPolicyRegistry')
    auto=re.findall(r"name='([^']+)'.*?mutation_mode='auto'",registry,re.I)
    if sorted(x.lower() for x in auto)!=sorted(x.lower() for x in AUTHORIZED_NAMES): raise RuntimeError(f'auto authority drift: {auto}')
    for marker in ("name='tagify'","source='alexk218/tagify'","inventory_policy='monitor-only'","mutation_mode='deny'","install_mode='never-auto-install'","data_policy='protect-ratings-tags-notes'","name='splitify'","source='alexander-rebello/splitify'","preserve-installed-content","playlist-backed-ratings-preserve","never-disable-or-optimize"):
        if marker.lower() not in registry.lower(): raise RuntimeError(f'protected policy missing: {marker}')
    update=function_block(cand,'Update-AutoApps')
    if 'tagify' in update.lower() or 'splitify' in update.lower(): raise RuntimeError('protected monitor-only app gained an automatic update route')
    rollback=function_block(cand,'Rollback-LastTransaction')
    if 'Assert-AddonSourceAdapterTransactionAuthorization' in rollback: raise RuntimeError('RollbackLast became source-adapter-dependent')
    for helper in ('Get-TagifyReleaseCatalog','Get-TagifyTreeFingerprint','Resolve-TagifyInstalledReleaseProvenance'):
        block=function_block(cand,helper)
        for forbidden in ('Invoke-WebRequest','Invoke-RestMethod','Remove-Item','Copy-Item','Move-Item','Start-Process','Expand-Archive','$env:APPDATA','$env:LOCALAPPDATA','IndexedDB','localStorage','spicetify apply','spicetify backup','spicetify restore'):
            if forbidden.lower() in block.lower(): raise RuntimeError(f'{helper} gained forbidden side effect/data access: {forbidden}')
    fp=function_block(cand,'Get-TagifyTreeFingerprint')
    if 'Sort-Object' in fp or '.Sort([System.StringComparer]::OrdinalIgnoreCase)' not in fp: raise RuntimeError('Tagify fingerprint ordering contract drifted')
    inv=function_block(cand,'Get-AddonInventory')
    for required in ('Resolve-TagifyInstalledReleaseProvenance','monitor-current-proven','monitor-update-available-proven-local','authenticated-release-catalog-tree-v1',AUDIT_CATALOG_JSON_SHA,'Resolve-SplitifyInstalledReleaseProvenance','60311e81ae11727528fd5e34879533e1cfacdaaf7b2b21dd1808fb20e3b32454'):
        if required not in inv: raise RuntimeError(f'provenance inventory contract missing: {required}')
    if 'Get-TagifyLocalVersion $dir' in inv: raise RuntimeError('Tagify inventory still trusts local metadata version for provenance')


def build():
    _,base_addon=build_base()
    main,addon=build_validated_candidate()
    validate_candidate(base_addon,addon)
    OUT.mkdir(parents=True,exist_ok=True)
    (OUT/'spotify-control.ps1').write_bytes(main);(OUT/'addon-manager.ps1').write_bytes(addon)
    report={
        'schema':2,'base_version':'0.6.25','version':'0.6.26','addon_version':'0.6.5-r15',
        'base_main':{'size':BASE_MAIN_SIZE,'sha256':BASE_MAIN_SHA},'base_addon':{'size':BASE_ADDON_SIZE,'sha256':BASE_ADDON_SHA},
        'candidate_main':{'size':TARGET_MAIN_SIZE,'sha256':TARGET_MAIN_SHA},'candidate_addon':{'size':TARGET_ADDON_SIZE,'sha256':TARGET_ADDON_SHA},
        'validated_source':{'head':VALIDATION_HEAD,'path':VALIDATION_PATH,'blob':VALIDATION_BLOB,'push_run':VALIDATION_PUSH_RUN,'pr_run':VALIDATION_PR_RUN,'stable_pr_run':VALIDATION_STABLE_PR_RUN,'pr':VALIDATION_PR,'pr_closed_unmerged':True,'push_artifact_id':VALIDATION_PUSH_ARTIFACT,'push_artifact_digest':VALIDATION_PUSH_ARTIFACT_DIGEST,'pr_artifact_id':VALIDATION_PR_ARTIFACT,'pr_artifact_digest':VALIDATION_PR_ARTIFACT_DIGEST},
        'audit_evidence':{'head':AUDIT_HEAD,'run':AUDIT_RUN,'artifact_id':AUDIT_ARTIFACT,'artifact_digest':AUDIT_ARTIFACT_DIGEST,'catalog_json_sha256':AUDIT_CATALOG_JSON_SHA},
        'release_catalog':RELEASES,'excluded_releases':EXCLUDED,'canonical_order':'StringComparer.OrdinalIgnoreCase','local_provenance_source':'exact-install-tree-only','manifest_or_package_version_trusted_for_provenance':False,
        'authority_expanded':False,'new_auto_install_authority':False,'auto_authority':AUTHORIZED_NAMES,'registry_fingerprint':REGISTRY_SHA,'source_adapter_fingerprint':ADAPTER_SHA,
        'tagify_policy':{'inventory_policy':'monitor-only','mutation_mode':'deny','install_mode':'never-auto-install','data_policy':'protect-ratings-tags-notes'},'splitify_policy_preserved':True,'rollback_last_source_adapter_independent':True,
    }
    REPORT.parent.mkdir(parents=True,exist_ok=True);REPORT.write_text(json.dumps(report,indent=2,sort_keys=True)+'\n',encoding='utf-8',newline='\n')
    print('V0626_R15_BUILD_PASS',len(main),sha(main),len(addon),sha(addon),VALIDATION_BLOB,AUDIT_CATALOG_JSON_SHA)


def main():
    p=argparse.ArgumentParser();p.add_argument('--build',action='store_true');args=p.parse_args()
    if not args.build:p.error('use --build')
    build()

if __name__=='__main__':main()
