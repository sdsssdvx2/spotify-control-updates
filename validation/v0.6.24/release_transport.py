from pathlib import Path
import argparse, base64, gzip, hashlib, io, json, re, shutil, subprocess, sys

ROOT = Path(__file__).resolve().parents[2]
BASE_COMMIT = '23e91427fd745227825d94eb48d804654ca54ee4'
BASE_VERSION = '0.6.23'
NEW_VERSION = '0.6.24'
BASE_MAIN_SHA = 'bc9861bdd64ff8af94f68f0f065739f82b235271dcd18ad6325b819205528a08'
BASE_MAIN_SIZE = 281588
BASE_ADDON_SHA = '23ad2210aea4352f535d1cf0b3ebb827a82200dcba2b70bf1ebae96499d82687'
BASE_ADDON_SIZE = 272494
TARGET_MAIN_SHA = 'dc5d7ec17f18f7546786c81f3172c08f6fb1692842c2e6c0a69a86171e6b1151'
TARGET_MAIN_SIZE = 284312
TARGET_ADDON_SHA = '81343687c475f7f48f1311b09c98205a021776f26e8d55082e0ec47f8ebfb470'
TARGET_ADDON_SIZE = 275414
AGENT_SHA = '2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278'
AGENT_SIZE = 4855
BOOTSTRAP = {'version':'1.0.6','sha256':'d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6','size':42963}
VALIDATION_HEAD = 'a3e0519b5d7c9e15c4804061f8ce128a302d8d6a'
VALIDATION_PUSH_RUN = '40377301372'
VALIDATION_PR_RUN = '40377414741'
VALIDATION_PR = 74
VALIDATION_ARTIFACT_ID = '12676150104'
VALIDATION_ARTIFACT_DIGEST = 'sha256:77b4cfb1657126a4e9f32d78ce88576bc74855e50e9327b643979cc6f6a171c7'
ADAPTER_FINGERPRINT = 'c0611a7b96f6ff09d1e235119efce2f2def6eb6d0a4e8e93e276cfa622c3c42d'
REGISTRY_FINGERPRINT = '0f05406d7152de1d975f888cb8270be8249115211ba9f41e0157342cd42efbd8'
AUTHORIZED_NAMES = ['better-local-files','eternal-jukebox','ivLyrics','playlist-maker']
BASE_OUT = ROOT / 'validation/v0.6.23/out/bin'
TARGET_OUT = ROOT / 'validation/v0.6.24/out/bin'
REPORT = ROOT / 'validation/v0.6.24/candidate-validation.json'
META = ROOT / 'validation/v0.6.24/release-metadata.json'
MAIN_DIR = ROOT / 'packages/v0.6.24/main-v0623-to-v0624'
ADDON_DIR = ROOT / 'packages/v0.6.24/addon-v065r12-to-v065r13'


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def deterministic_gzip(data: bytes) -> bytes:
    buf=io.BytesIO()
    with gzip.GzipFile(filename='',mode='wb',fileobj=buf,compresslevel=9,mtime=0) as g:g.write(data)
    return buf.getvalue()


def clean_dir(path: Path):
    if path.exists(): shutil.rmtree(path)
    path.mkdir(parents=True,exist_ok=True)


def write_chunks(encoded: bytes, folder: Path, chunk_size: int=4096):
    clean_dir(folder); chunks=[]
    for offset in range(0,len(encoded),chunk_size):
        data=encoded[offset:offset+chunk_size]; p=folder/f'chunk-{offset//chunk_size:03d}.txt'; p.write_bytes(data)
        chunks.append({'path':str(p.relative_to(ROOT)).replace('\\','/'),'sha256':sha(data),'size':len(data)})
    if not chunks: raise RuntimeError('transport produced no chunks')
    return chunks


def build_full_file_patch(path: str, before: bytes, after: bytes, folder: Path):
    compressed=deterministic_gzip(after); encoded=base64.b64encode(compressed); chunks=write_chunks(encoded,folder)
    return {'path':path,'from_sha256':sha(before),'to_sha256':sha(after),'encoding':'gzip-base64-full-file','encoded_sha256':sha(encoded),'encoded_size':len(encoded),'compressed_sha256':sha(compressed),'compressed_size':len(compressed),'target_size':len(after),'chunks':chunks}


def read_chunks(patch, reader):
    parts=[]
    for chunk in patch['chunks']:
        data=reader(chunk['path'])
        if len(data)!=int(chunk['size']) or sha(data)!=chunk['sha256']: raise RuntimeError(f"chunk mismatch: {chunk['path']}")
        parts.append(data)
    encoded=b''.join(parts)
    if len(encoded)!=int(patch['encoded_size']) or sha(encoded)!=patch['encoded_sha256']: raise RuntimeError(f"encoded transport mismatch: {patch['path']}")
    compressed=base64.b64decode(encoded,validate=True)
    if len(compressed)!=int(patch['compressed_size']) or sha(compressed)!=patch['compressed_sha256']: raise RuntimeError(f"gzip transport mismatch: {patch['path']}")
    target=gzip.decompress(compressed)
    if len(target)!=int(patch['target_size']) or sha(target)!=patch['to_sha256']: raise RuntimeError(f"target transport mismatch: {patch['path']}")
    return target


def git_bytes(commit: str, path: str) -> bytes:
    return subprocess.check_output(['git','show',f'{commit}:{path}'],cwd=ROOT)


def canonical_payload(latest):
    rows=[f"{x['path']}|{int(x['size'])}|{x['sha256']}" for x in sorted(latest,key=lambda x:x['path'])]
    return sha(('\n'.join(rows)+'\n').encode('ascii'))


def build_candidate():
    subprocess.check_call([sys.executable,str(ROOT/'validation/v0.6.24/build_v0624.py'),'--build'],cwd=ROOT)
    main=(TARGET_OUT/'spotify-control.ps1').read_bytes(); addon=(TARGET_OUT/'addon-manager.ps1').read_bytes()
    if (len(main),sha(main))!=(TARGET_MAIN_SIZE,TARGET_MAIN_SHA): raise RuntimeError('validated v0.6.24 main identity mismatch')
    if (len(addon),sha(addon))!=(TARGET_ADDON_SIZE,TARGET_ADDON_SHA): raise RuntimeError('validated r13 identity mismatch')
    return main,addon


def base_payloads():
    subprocess.check_call([sys.executable,str(ROOT/'validation/v0.6.23/build_v0623.py'),'--build'],cwd=ROOT)
    main=(BASE_OUT/'spotify-control.ps1').read_bytes(); addon=(BASE_OUT/'addon-manager.ps1').read_bytes()
    if (len(main),sha(main))!=(BASE_MAIN_SIZE,BASE_MAIN_SHA): raise RuntimeError('v0.6.23 main base identity mismatch')
    if (len(addon),sha(addon))!=(BASE_ADDON_SIZE,BASE_ADDON_SHA): raise RuntimeError('r12 addon base identity mismatch')
    return main,addon


def build_packages():
    target_main,target_addon=build_candidate(); base_main,base_addon=base_payloads()
    main_patch=build_full_file_patch('bin/spotify-control.ps1',base_main,target_main,MAIN_DIR)
    addon_patch=build_full_file_patch('bin/addon-manager.ps1',base_addon,target_addon,ADDON_DIR)
    report_bytes=REPORT.read_bytes(); report_sha=sha(report_bytes)
    metadata={
        'schema':1,'base_commit':BASE_COMMIT,'base_version':BASE_VERSION,'version':NEW_VERSION,'addon_version':'0.6.5-r13',
        'candidate_main':{'size':TARGET_MAIN_SIZE,'sha256':TARGET_MAIN_SHA},'candidate_addon':{'size':TARGET_ADDON_SIZE,'sha256':TARGET_ADDON_SHA},
        'resident_agent':{'size':AGENT_SIZE,'sha256':AGENT_SHA},'bootstrap':BOOTSTRAP,
        'authority_expanded':False,'new_auto_install_authority':False,'auto_authority':AUTHORIZED_NAMES,
        'adapter_fingerprint':ADAPTER_FINGERPRINT,'registry_fingerprint':REGISTRY_FINGERPRINT,
        'archive_hardening':{
            'marketplace':{'pre_extract':True,'max_entries':16384,'max_entry_bytes':134217728,'max_expanded_bytes':536870912,'path_duplicate_symlink_checks':True},
            'ivlyrics':{'pre_extract':True,'max_entries':4096,'max_entry_bytes':134217728,'max_expanded_bytes':536870912,'path_duplicate_symlink_checks':True,'historical_zipball_precheck':True},
            'pithaya':{'pre_extract':True,'max_entries':8192,'max_entry_bytes':134217728,'max_expanded_bytes':536870912,'path_duplicate_symlink_checks':True},
            'spicetify_existing_extractor_unchanged':True,
        },
        'validation':{'head':VALIDATION_HEAD,'push_run':VALIDATION_PUSH_RUN,'pr_run':VALIDATION_PR_RUN,'pr':VALIDATION_PR,'pr_closed_unmerged':True,'artifact_id':VALIDATION_ARTIFACT_ID,'artifact_digest':VALIDATION_ARTIFACT_DIGEST,'deterministic_report_sha256':report_sha},
        'transport':{'main':main_patch,'addon':addon_patch},
    }
    META.write_text(json.dumps(metadata,indent=2,sort_keys=True)+'\n',encoding='utf-8',newline='\n')
    print('V0624_RELEASE_PACKAGES_PASS',TARGET_MAIN_SIZE,TARGET_MAIN_SHA,TARGET_ADDON_SIZE,TARGET_ADDON_SHA,report_sha)
    return metadata


def assert_base_manifest(manifest):
    if manifest.get('schema')!=1 or manifest.get('channel')!='stable': raise RuntimeError('unexpected manifest schema/channel')
    if manifest.get('latest_version')!=BASE_VERSION: raise RuntimeError(f"expected stable {BASE_VERSION}, got {manifest.get('latest_version')}")
    if manifest.get('min_bootstrap_version')!='1.0.6' or manifest.get('bootstrap')!=BOOTSTRAP: raise RuntimeError('Bootstrap contract drift')
    latest={x['path']:x for x in manifest.get('latest_files',[])}
    expected={'bin/spotify-control.ps1':(BASE_MAIN_SIZE,BASE_MAIN_SHA),'bin/addon-manager.ps1':(BASE_ADDON_SIZE,BASE_ADDON_SHA),'bin/spotify-control-agent.vbs':(AGENT_SIZE,AGENT_SHA)}
    if set(latest)!=set(expected): raise RuntimeError('unexpected stable latest_files set')
    for path,(size,digest) in expected.items():
        if (int(latest[path]['size']),latest[path]['sha256'])!=(size,digest): raise RuntimeError(f'base latest_files mismatch: {path}')
    if manifest.get('payload_set_sha256')!=canonical_payload(manifest['latest_files']): raise RuntimeError('base payload set is internally inconsistent')


def write_manifest(source_commit: str):
    if not re.fullmatch(r'[0-9a-f]{40}',source_commit): raise RuntimeError('source commit is not a full lowercase SHA')
    subprocess.check_call(['git','cat-file','-e',f'{source_commit}^{{commit}}'],cwd=ROOT)
    metadata=build_packages(); manifest_path=ROOT/'manifest.json'; manifest=json.loads(manifest_path.read_text(encoding='utf-8-sig')); assert_base_manifest(manifest)
    if any(e.get('from_version')==BASE_VERSION and e.get('to_version')==NEW_VERSION for e in manifest['updates']): raise RuntimeError('v0.6.23 -> v0.6.24 edge already exists')
    latest=[{'path':'bin/spotify-control.ps1','sha256':TARGET_MAIN_SHA,'size':TARGET_MAIN_SIZE},{'path':'bin/addon-manager.ps1','sha256':TARGET_ADDON_SHA,'size':TARGET_ADDON_SIZE},{'path':'bin/spotify-control-agent.vbs','sha256':AGENT_SHA,'size':AGENT_SIZE}]
    edge={'from_version':BASE_VERSION,'to_version':NEW_VERSION,'patches':[metadata['transport']['main'],metadata['transport']['addon']]}
    manifest['latest_version']=NEW_VERSION; manifest['source_commit']=source_commit; manifest['latest_files']=latest; manifest['payload_set_sha256']=canonical_payload(latest); manifest['updates'].append(edge)
    manifest_path.write_text(json.dumps(manifest,separators=(',',':'))+'\n',encoding='utf-8',newline='\n')
    print('V0624_MANIFEST_WRITE_PASS',source_commit,manifest['payload_set_sha256'])


def validate_published():
    metadata=build_packages(); manifest=json.loads((ROOT/'manifest.json').read_text(encoding='utf-8-sig'))
    if manifest.get('latest_version')!=NEW_VERSION: raise RuntimeError(f"expected published {NEW_VERSION}, got {manifest.get('latest_version')}")
    if manifest.get('bootstrap')!=BOOTSTRAP or manifest.get('min_bootstrap_version')!='1.0.6': raise RuntimeError('published Bootstrap contract drift')
    source=manifest.get('source_commit','')
    if not re.fullmatch(r'[0-9a-f]{40}',source): raise RuntimeError('published source_commit invalid')
    subprocess.check_call(['git','cat-file','-e',f'{source}^{{commit}}'],cwd=ROOT)
    base_manifest=json.loads(git_bytes(BASE_COMMIT,'manifest.json').decode('utf-8-sig')); assert_base_manifest(base_manifest)
    if manifest['updates'][:-1]!=base_manifest['updates']: raise RuntimeError('historical update edges changed')
    edge=manifest['updates'][-1]
    if edge.get('from_version')!=BASE_VERSION or edge.get('to_version')!=NEW_VERSION: raise RuntimeError('published v0.6.23 -> v0.6.24 edge missing at tail')
    patches={p['path']:p for p in edge.get('patches',[])}
    if set(patches)!={'bin/spotify-control.ps1','bin/addon-manager.ps1'}: raise RuntimeError('published edge patch set mismatch')
    target_main=read_chunks(patches['bin/spotify-control.ps1'],lambda p:git_bytes(source,p)); target_addon=read_chunks(patches['bin/addon-manager.ps1'],lambda p:git_bytes(source,p))
    if (len(target_main),sha(target_main))!=(TARGET_MAIN_SIZE,TARGET_MAIN_SHA): raise RuntimeError('immutable source main reconstruction mismatch')
    if (len(target_addon),sha(target_addon))!=(TARGET_ADDON_SIZE,TARGET_ADDON_SHA): raise RuntimeError('immutable source addon reconstruction mismatch')
    expected_latest=[{'path':'bin/spotify-control.ps1','sha256':TARGET_MAIN_SHA,'size':TARGET_MAIN_SIZE},{'path':'bin/addon-manager.ps1','sha256':TARGET_ADDON_SHA,'size':TARGET_ADDON_SIZE},{'path':'bin/spotify-control-agent.vbs','sha256':AGENT_SHA,'size':AGENT_SIZE}]
    if manifest['latest_files']!=expected_latest: raise RuntimeError('published latest_files mismatch')
    if manifest.get('payload_set_sha256')!=canonical_payload(expected_latest): raise RuntimeError('published payload set mismatch')
    for name,path in [('main',MAIN_DIR),('addon',ADDON_DIR)]:
        expected=metadata['transport'][name]; actual=patches['bin/spotify-control.ps1' if name=='main' else 'bin/addon-manager.ps1']
        if expected!=actual: raise RuntimeError(f'published {name} transport metadata differs from deterministic rebuild')
        for chunk in expected['chunks']:
            working=(ROOT/chunk['path']).read_bytes(); pinned=git_bytes(source,chunk['path'])
            if working!=pinned: raise RuntimeError(f"working transport differs from source commit: {chunk['path']}")
    print('V0624_PUBLISHED_TRANSPORT_PASS',source,manifest['payload_set_sha256'])


def main():
    parser=argparse.ArgumentParser(); parser.add_argument('--build-packages',action='store_true'); parser.add_argument('--write-manifest',action='store_true'); parser.add_argument('--validate-published',action='store_true'); parser.add_argument('--source-commit')
    args=parser.parse_args(); modes=sum(bool(x) for x in (args.build_packages,args.write_manifest,args.validate_published))
    if modes!=1: parser.error('choose exactly one mode')
    if args.build_packages: build_packages()
    elif args.write_manifest:
        if not args.source_commit: parser.error('--write-manifest requires --source-commit')
        write_manifest(args.source_commit)
    else: validate_published()

if __name__=='__main__': main()
