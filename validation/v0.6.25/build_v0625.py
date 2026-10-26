from pathlib import Path
import argparse, hashlib, json, subprocess, sys

ROOT = Path(__file__).resolve().parents[2]
BASE_OUT = ROOT / 'validation/v0.6.24/out/bin'
OUT = ROOT / 'validation/v0.6.25/out/bin'
REPORT = ROOT / 'validation/v0.6.25/candidate-validation.json'

BASE_MAIN_SIZE = 284312
BASE_MAIN_SHA = 'dc5d7ec17f18f7546786c81f3172c08f6fb1692842c2e6c0a69a86171e6b1151'
BASE_ADDON_SIZE = 275414
BASE_ADDON_SHA = '81343687c475f7f48f1311b09c98205a021776f26e8d55082e0ec47f8ebfb470'
TARGET_MAIN_SIZE = 284313
TARGET_MAIN_SHA = '896bb74e71385b5b6ada118af41cbe9d398dc662ce3719234104028e6eed197f'
TARGET_ADDON_SIZE = 282718
TARGET_ADDON_SHA = '25ebd0a5d5158f7d3cb4b4ce2ecf89f05f4dad3ef6bc799599e7204ce103c29c'
REGISTRY_SHA = '0f05406d7152de1d975f888cb8270be8249115211ba9f41e0157342cd42efbd8'
ADAPTER_SHA = 'c0611a7b96f6ff09d1e235119efce2f2def6eb6d0a4e8e93e276cfa622c3c42d'
AUTHORIZED_NAMES = ['better-local-files', 'eternal-jukebox', 'ivLyrics', 'playlist-maker']

VALIDATION_HEAD = 'c08ce018a8424ce39c4e5692443b78a71e010b26'
VALIDATION_PATH = 'validation/splitify-release-provenance-v0.1.2/build_candidate.py'
VALIDATION_BLOB = '5cab5a8141a13bf7985570aeced3166d7b163c8e'
VALIDATION_PUSH_RUN = '40385692901'
VALIDATION_PR_RUN = '40386074191'
VALIDATION_STABLE_PR_RUN = '40386074179'
VALIDATION_PR = 79
VALIDATION_PUSH_ARTIFACT = 12679968671
VALIDATION_PUSH_ARTIFACT_DIGEST = 'sha256:afe8d76ba6bee31ff12bab10958beb2959d12a3985d637c2bb9639a6b0d1f6fd'
VALIDATION_PR_ARTIFACT = 12680796618
VALIDATION_PR_ARTIFACT_DIGEST = 'sha256:2397dc0039073f8177f6c3e12fcc08db90086db39dcda73d4aad1f98927c263d'
CATALOG_HEAD = '4af252f0d60b371db1cf7456d8f22ea0c200221a'
CATALOG_RUN = '40384980123'
CATALOG_ARTIFACT = 12681395038
CATALOG_ARTIFACT_DIGEST = 'sha256:a275c0e4274b98394d057efd49a2ba45d44ace71d47ed71b9383b44e18993918'
CATALOG_JSON_SHA = '60311e81ae11727528fd5e34879533e1cfacdaaf7b2b21dd1808fb20e3b32454'

RELEASES = [
    {'version':'1.0.5','tag':'v1.0.5','asset_size':7301,'asset_sha256':'c2ecc5e9330035b5c1855f537ea42f85a49705519ccc57e10d121e8b4595fab2','tree_sha256':'8c4525b41511fb5a32ad4921fbdbda5c59e0fb613ff0b2f223d0ee295030936a','file_count':5},
    {'version':'1.0.8','tag':'v1.0.8','asset_size':8801,'asset_sha256':'03158572d234c1aba14d7b9c53578886c885ffc568f5004dc03346eaa5dc4508','tree_sha256':'571722765760ccb98697a50742cfc8e66fae5411f91716794359e483b4383c76','file_count':6},
    {'version':'1.1.0','tag':'v1.1.0','asset_size':7822,'asset_sha256':'5de51a885815f78067b8d6f7f3ebe40c93b5a7c7e3c8c841fcd26147a13010ca','tree_sha256':'48bace1b6cef325dd1757bf4428e01fd42759a74da20a93fc16ab1ce49132777','file_count':6},
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
    subprocess.check_call([sys.executable,str(ROOT/'validation/v0.6.24/build_v0624.py'),'--build'],cwd=ROOT)
    main=(BASE_OUT/'spotify-control.ps1').read_bytes();addon=(BASE_OUT/'addon-manager.ps1').read_bytes()
    if (len(main),sha(main))!=(BASE_MAIN_SIZE,BASE_MAIN_SHA): raise RuntimeError(f'v0.6.24 main base drift: {len(main)} {sha(main)}')
    if (len(addon),sha(addon))!=(BASE_ADDON_SIZE,BASE_ADDON_SHA): raise RuntimeError(f'r13 addon base drift: {len(addon)} {sha(addon)}')
    return main,addon


def build_validated_candidate():
    blob=git_blob(VALIDATION_HEAD,VALIDATION_PATH)
    if blob != VALIDATION_BLOB: raise RuntimeError(f'validated v0.1.2 builder blob drift: {blob}')
    source=git_bytes(VALIDATION_HEAD,VALIDATION_PATH)
    fake=ROOT/VALIDATION_PATH
    ns={'__file__':str(fake),'__name__':'spotify_control_validated_splitify_v012'}
    exec(compile(source,str(fake),'exec'),ns)
    ns['build']()
    source_out=ROOT/'validation/splitify-release-provenance-v0.1.2/out/bin'
    main=(source_out/'spotify-control.ps1').read_bytes();addon=(source_out/'addon-manager.ps1').read_bytes()
    if (len(main),sha(main))!=(TARGET_MAIN_SIZE,TARGET_MAIN_SHA): raise RuntimeError(f'validated v0.6.25 main drift: {len(main)} {sha(main)}')
    if (len(addon),sha(addon))!=(TARGET_ADDON_SIZE,TARGET_ADDON_SHA): raise RuntimeError(f'validated r14 addon drift: {len(addon)} {sha(addon)}')
    return main,addon


def validate_candidate(base_addon: bytes, candidate_addon: bytes):
    base=base_addon.decode('utf-8-sig').replace('\r\n','\n')
    cand=candidate_addon.decode('utf-8-sig').replace('\r\n','\n')
    for name in ('Get-AddonPolicyRegistry','Get-AddonSourceAdapterCatalog'):
        if function_block(base,name)!=function_block(cand,name): raise RuntimeError(f'{name} changed unexpectedly')
    registry=function_block(cand,'Get-AddonPolicyRegistry')
    import re
    auto=re.findall(r"name='([^']+)'.*?mutation_mode='auto'",registry,re.I)
    if sorted(x.lower() for x in auto)!=sorted(x.lower() for x in AUTHORIZED_NAMES): raise RuntimeError(f'auto authority drift: {auto}')
    for marker in ("name='splitify'","source='alexander-rebello/splitify'","inventory_policy='monitor-only'","mutation_mode='deny'","install_mode='never-auto-install'","data_policy='preserve-installed-content'","protect-ratings-tags-notes","playlist-backed-ratings-preserve","never-disable-or-optimize"):
        if marker.lower() not in registry.lower(): raise RuntimeError(f'protected policy missing: {marker}')
    update=function_block(cand,'Update-AutoApps')
    if 'splitify' in update.lower(): raise RuntimeError('Splitify gained an automatic update route')
    rollback=function_block(cand,'Rollback-LastTransaction')
    if 'Assert-AddonSourceAdapterTransactionAuthorization' in rollback: raise RuntimeError('RollbackLast became source-adapter-dependent')
    for helper in ('Get-SplitifyReleaseCatalog','Get-SplitifyTreeFingerprint','Resolve-SplitifyInstalledReleaseProvenance'):
        block=function_block(cand,helper)
        for forbidden in ('Invoke-WebRequest','Invoke-RestMethod','Remove-Item','Copy-Item','Move-Item','Start-Process','Expand-Archive','spicetify apply','spicetify backup','spicetify restore'):
            if forbidden.lower() in block.lower(): raise RuntimeError(f'{helper} gained forbidden side effect: {forbidden}')
    fp=function_block(cand,'Get-SplitifyTreeFingerprint')
    if 'Sort-Object' in fp or '.Sort([System.StringComparer]::OrdinalIgnoreCase)' not in fp: raise RuntimeError('Splitify fingerprint ordering contract drifted')
    inv=function_block(cand,'Get-AddonInventory')
    for required in ('Resolve-SplitifyInstalledReleaseProvenance','monitor-current-proven','monitor-update-available-proven-local','authenticated-release-catalog-tree-v1',CATALOG_JSON_SHA):
        if required not in inv: raise RuntimeError(f'Splitify inventory provenance contract missing: {required}')
    if 'Get-SplitifyOfficialReleaseProof' in inv: raise RuntimeError('latest-only Splitify archive proof path returned')


def build():
    _,base_addon=build_base()
    main,addon=build_validated_candidate()
    validate_candidate(base_addon,addon)
    OUT.mkdir(parents=True,exist_ok=True)
    (OUT/'spotify-control.ps1').write_bytes(main);(OUT/'addon-manager.ps1').write_bytes(addon)
    report={
        'schema':2,'base_version':'0.6.24','version':'0.6.25','addon_version':'0.6.5-r14',
        'base_main':{'size':BASE_MAIN_SIZE,'sha256':BASE_MAIN_SHA},'base_addon':{'size':BASE_ADDON_SIZE,'sha256':BASE_ADDON_SHA},
        'candidate_main':{'size':TARGET_MAIN_SIZE,'sha256':TARGET_MAIN_SHA},'candidate_addon':{'size':TARGET_ADDON_SIZE,'sha256':TARGET_ADDON_SHA},
        'validated_source':{'head':VALIDATION_HEAD,'path':VALIDATION_PATH,'blob':VALIDATION_BLOB,'push_run':VALIDATION_PUSH_RUN,'pr_run':VALIDATION_PR_RUN,'stable_pr_run':VALIDATION_STABLE_PR_RUN,'pr':VALIDATION_PR,'pr_closed_unmerged':True,'push_artifact_id':VALIDATION_PUSH_ARTIFACT,'push_artifact_digest':VALIDATION_PUSH_ARTIFACT_DIGEST,'pr_artifact_id':VALIDATION_PR_ARTIFACT,'pr_artifact_digest':VALIDATION_PR_ARTIFACT_DIGEST},
        'catalog_evidence':{'head':CATALOG_HEAD,'run':CATALOG_RUN,'artifact_id':CATALOG_ARTIFACT,'artifact_digest':CATALOG_ARTIFACT_DIGEST,'catalog_json_sha256':CATALOG_JSON_SHA},
        'release_catalog':RELEASES,'unsupported_stable_releases':[{'version':'1.0.1','reason':'no-splitify-zip'},{'version':'1.0.4','reason':'authenticated-asset-missing-manifest'}],
        'canonical_order':'StringComparer.OrdinalIgnoreCase','manifest_version_trusted':False,'authority_expanded':False,'new_auto_install_authority':False,'auto_authority':AUTHORIZED_NAMES,
        'registry_fingerprint':REGISTRY_SHA,'source_adapter_fingerprint':ADAPTER_SHA,'splitify_policy':{'inventory_policy':'monitor-only','mutation_mode':'deny','install_mode':'never-auto-install','data_policy':'preserve-installed-content'},
    }
    REPORT.parent.mkdir(parents=True,exist_ok=True);REPORT.write_text(json.dumps(report,indent=2,sort_keys=True)+'\n',encoding='utf-8',newline='\n')
    print('V0625_R14_BUILD_PASS',len(main),sha(main),len(addon),sha(addon),VALIDATION_BLOB,CATALOG_JSON_SHA)


def main():
    p=argparse.ArgumentParser();p.add_argument('--build',action='store_true');args=p.parse_args()
    if not args.build:p.error('use --build')
    build()

if __name__=='__main__':main()
