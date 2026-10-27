from pathlib import Path
import argparse, base64, gzip, hashlib, io, json, re, shutil, subprocess, sys

ROOT=Path(__file__).resolve().parents[2]
BASE_COMMIT='9b97ffba51060e92e687fadeb361da7ba95a1dd0'
BASE_VERSION='0.6.25'
NEW_VERSION='0.6.26'
BASE_MAIN_SHA='896bb74e71385b5b6ada118af41cbe9d398dc662ce3719234104028e6eed197f'
BASE_MAIN_SIZE=284313
BASE_ADDON_SHA='25ebd0a5d5158f7d3cb4b4ce2ecf89f05f4dad3ef6bc799599e7204ce103c29c'
BASE_ADDON_SIZE=282718
TARGET_MAIN_SHA='d7b484a2a7b10a27db0f182d71fe36f590784171db7208189540045bcf4f54d1'
TARGET_MAIN_SIZE=284311
TARGET_ADDON_SHA='4aa56dd5d4ef07da21d3bdf5c76227fabb49c64767a281b1e11ee48e7211a09f'
TARGET_ADDON_SIZE=291294
AGENT_SHA='2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278'
AGENT_SIZE=4855
BOOTSTRAP={'version':'1.0.6','sha256':'d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6','size':42963}
REGISTRY_SHA='0f05406d7152de1d975f888cb8270be8249115211ba9f41e0157342cd42efbd8'
ADAPTER_SHA='c0611a7b96f6ff09d1e235119efce2f2def6eb6d0a4e8e93e276cfa622c3c42d'
AUTHORIZED_NAMES=['better-local-files','eternal-jukebox','ivLyrics','playlist-maker']
VALIDATION_HEAD='91980963f1bd7cca987a3fc15c0a70074ea72c08'
VALIDATION_BLOB='e8fed5168af55843f22c66b5a3a82165b1bb13fe'
VALIDATION_PUSH_RUN='40453161373'
VALIDATION_PR_RUN='40453275598'
VALIDATION_STABLE_PR_RUN='40453275661'
VALIDATION_PR=82
VALIDATION_PUSH_ARTIFACT=12710864506
VALIDATION_PUSH_ARTIFACT_DIGEST='sha256:22c6ac0f3aa527284fc1ce5fd50426a9bb6b3a46a5c9994d4b68178408f67d6b'
VALIDATION_PR_ARTIFACT=12711157197
VALIDATION_PR_ARTIFACT_DIGEST='sha256:e36662f22d6f85823e69a0df07ff42374276a4d180c4ba599e87ef744cb193c8'
AUDIT_HEAD='4263a53f145fc602fbe81e0c243f8d7a70f46fc5'
AUDIT_RUN='40388895760'
AUDIT_ARTIFACT=12682440808
AUDIT_ARTIFACT_DIGEST='sha256:9ed6837dccbf5229a9546a16ef4a35fc933289a28cc4929e45138625bd499f50'
AUDIT_CATALOG_JSON_SHA='75d66f6e06ec76c8f96fbc7941617e7330844979a87d3297e8e4ff824c3b6a1a'
BASE_OUT=ROOT/'validation/v0.6.25/out/bin'
TARGET_OUT=ROOT/'validation/v0.6.26/out/bin'
REPORT=ROOT/'validation/v0.6.26/candidate-validation.json'
META=ROOT/'validation/v0.6.26/release-metadata.json'
MAIN_DIR=ROOT/'packages/v0.6.26/main-v0625-to-v0626'
ADDON_DIR=ROOT/'packages/v0.6.26/addon-v065r14-to-v065r15'


def sha(data:bytes)->str:return hashlib.sha256(data).hexdigest()

def deterministic_gzip(data:bytes)->bytes:
    buf=io.BytesIO()
    with gzip.GzipFile(filename='',mode='wb',fileobj=buf,compresslevel=9,mtime=0) as g:g.write(data)
    return buf.getvalue()

def clean_dir(path:Path):
    if path.exists():shutil.rmtree(path)
    path.mkdir(parents=True,exist_ok=True)

def write_chunks(encoded:bytes,folder:Path,chunk_size:int=4096):
    clean_dir(folder);rows=[]
    for off in range(0,len(encoded),chunk_size):
        b=encoded[off:off+chunk_size];p=folder/f'chunk-{off//chunk_size:03d}.txt';p.write_bytes(b)
        rows.append({'path':str(p.relative_to(ROOT)).replace('\\','/'),'sha256':sha(b),'size':len(b)})
    if not rows:raise RuntimeError('transport produced no chunks')
    return rows

def build_full_file_patch(path:str,before:bytes,after:bytes,folder:Path):
    gz=deterministic_gzip(after);enc=base64.b64encode(gz);chunks=write_chunks(enc,folder)
    return {'path':path,'from_sha256':sha(before),'to_sha256':sha(after),'encoding':'gzip-base64-full-file','encoded_sha256':sha(enc),'encoded_size':len(enc),'compressed_sha256':sha(gz),'compressed_size':len(gz),'target_size':len(after),'chunks':chunks}

def read_chunks(patch,reader):
    parts=[]
    for c in patch['chunks']:
        b=reader(c['path'])
        if len(b)!=int(c['size']) or sha(b)!=c['sha256']:raise RuntimeError(f"chunk mismatch: {c['path']}")
        parts.append(b)
    enc=b''.join(parts)
    if len(enc)!=int(patch['encoded_size']) or sha(enc)!=patch['encoded_sha256']:raise RuntimeError(f"encoded mismatch: {patch['path']}")
    gz=base64.b64decode(enc,validate=True)
    if len(gz)!=int(patch['compressed_size']) or sha(gz)!=patch['compressed_sha256']:raise RuntimeError(f"gzip mismatch: {patch['path']}")
    target=gzip.decompress(gz)
    if len(target)!=int(patch['target_size']) or sha(target)!=patch['to_sha256']:raise RuntimeError(f"target mismatch: {patch['path']}")
    return target

def git_bytes(commit:str,path:str)->bytes:return subprocess.check_output(['git','show',f'{commit}:{path}'],cwd=ROOT)

def canonical_payload(latest):
    rows=[f"{x['path']}|{int(x['size'])}|{x['sha256']}" for x in sorted(latest,key=lambda x:x['path'])]
    return sha(('\n'.join(rows)+'\n').encode('ascii'))

def build_candidate():
    subprocess.check_call([sys.executable,str(ROOT/'validation/v0.6.26/build_v0626.py'),'--build'],cwd=ROOT)
    main=(TARGET_OUT/'spotify-control.ps1').read_bytes();addon=(TARGET_OUT/'addon-manager.ps1').read_bytes()
    if (len(main),sha(main))!=(TARGET_MAIN_SIZE,TARGET_MAIN_SHA):raise RuntimeError('validated v0.6.26 main identity mismatch')
    if (len(addon),sha(addon))!=(TARGET_ADDON_SIZE,TARGET_ADDON_SHA):raise RuntimeError('validated r15 addon identity mismatch')
    return main,addon

def base_payloads():
    subprocess.check_call([sys.executable,str(ROOT/'validation/v0.6.25/build_v0625.py'),'--build'],cwd=ROOT)
    main=(BASE_OUT/'spotify-control.ps1').read_bytes();addon=(BASE_OUT/'addon-manager.ps1').read_bytes()
    if (len(main),sha(main))!=(BASE_MAIN_SIZE,BASE_MAIN_SHA):raise RuntimeError('v0.6.25 main base identity mismatch')
    if (len(addon),sha(addon))!=(BASE_ADDON_SIZE,BASE_ADDON_SHA):raise RuntimeError('r14 addon base identity mismatch')
    return main,addon

def build_packages():
    target_main,target_addon=build_candidate();base_main,base_addon=base_payloads()
    main_patch=build_full_file_patch('bin/spotify-control.ps1',base_main,target_main,MAIN_DIR)
    addon_patch=build_full_file_patch('bin/addon-manager.ps1',base_addon,target_addon,ADDON_DIR)
    report_bytes=REPORT.read_bytes();report_sha=sha(report_bytes)
    metadata={
      'schema':1,'base_commit':BASE_COMMIT,'base_version':BASE_VERSION,'version':NEW_VERSION,'addon_version':'0.6.5-r15',
      'candidate_main':{'size':TARGET_MAIN_SIZE,'sha256':TARGET_MAIN_SHA},'candidate_addon':{'size':TARGET_ADDON_SIZE,'sha256':TARGET_ADDON_SHA},
      'resident_agent':{'size':AGENT_SIZE,'sha256':AGENT_SHA},'bootstrap':BOOTSTRAP,
      'authority_expanded':False,'new_auto_install_authority':False,'auto_authority':AUTHORIZED_NAMES,'registry_fingerprint':REGISTRY_SHA,'source_adapter_fingerprint':ADAPTER_SHA,
      'tagify_provenance':{'mode':'authenticated-release-catalog-tree-v1','monitor_only':True,'mutation_mode':'deny','install_mode':'never-auto-install','data_policy':'protect-ratings-tags-notes','canonical_order':'StringComparer.OrdinalIgnoreCase','manifest_or_package_version_trusted':False,'catalog_json_sha256':AUDIT_CATALOG_JSON_SHA,'provable_versions':['2.5.0','3.0.0','3.1.0','3.2.0','3.3.0','3.3.1','3.3.2'],'excluded_no_asset':['1.0.0','1.0.1','1.0.2','2.0.0','2.1.0','2.1.1'],'excluded_no_identity_marker':['2.1.2','2.2.0','2.3.0','2.4.0']},
      'validation':{'head':VALIDATION_HEAD,'builder_blob':VALIDATION_BLOB,'push_run':VALIDATION_PUSH_RUN,'pr_run':VALIDATION_PR_RUN,'stable_pr_run':VALIDATION_STABLE_PR_RUN,'pr':VALIDATION_PR,'pr_closed_unmerged':True,'push_artifact_id':VALIDATION_PUSH_ARTIFACT,'push_artifact_digest':VALIDATION_PUSH_ARTIFACT_DIGEST,'pr_artifact_id':VALIDATION_PR_ARTIFACT,'pr_artifact_digest':VALIDATION_PR_ARTIFACT_DIGEST,'audit_head':AUDIT_HEAD,'audit_run':AUDIT_RUN,'audit_artifact_id':AUDIT_ARTIFACT,'audit_artifact_digest':AUDIT_ARTIFACT_DIGEST,'audit_catalog_json_sha256':AUDIT_CATALOG_JSON_SHA,'deterministic_report_sha256':report_sha},
      'transport':{'main':main_patch,'addon':addon_patch},
    }
    META.parent.mkdir(parents=True,exist_ok=True);META.write_text(json.dumps(metadata,indent=2,sort_keys=True)+'\n',encoding='utf-8',newline='\n')
    print('V0626_RELEASE_PACKAGES_PASS',TARGET_MAIN_SIZE,TARGET_MAIN_SHA,TARGET_ADDON_SIZE,TARGET_ADDON_SHA,report_sha)
    return metadata

def assert_base_manifest(m):
    if m.get('schema')!=1 or m.get('channel')!='stable':raise RuntimeError('unexpected manifest schema/channel')
    if m.get('latest_version')!=BASE_VERSION:raise RuntimeError(f"expected stable {BASE_VERSION}, got {m.get('latest_version')}")
    if m.get('min_bootstrap_version')!='1.0.6' or m.get('bootstrap')!=BOOTSTRAP:raise RuntimeError('Bootstrap contract drift')
    latest={x['path']:x for x in m.get('latest_files',[])}
    expected={'bin/spotify-control.ps1':(BASE_MAIN_SIZE,BASE_MAIN_SHA),'bin/addon-manager.ps1':(BASE_ADDON_SIZE,BASE_ADDON_SHA),'bin/spotify-control-agent.vbs':(AGENT_SIZE,AGENT_SHA)}
    if set(latest)!=set(expected):raise RuntimeError('unexpected stable latest_files set')
    for path,(size,digest) in expected.items():
        if (int(latest[path]['size']),latest[path]['sha256'])!=(size,digest):raise RuntimeError(f'base latest_files mismatch: {path}')
    if m.get('payload_set_sha256')!=canonical_payload(m['latest_files']):raise RuntimeError('base payload set internally inconsistent')
def write_manifest(source_commit:str):
    if not re.fullmatch(r'[0-9a-f]{40}',source_commit):raise RuntimeError('source commit invalid')
    subprocess.check_call(['git','cat-file','-e',f'{source_commit}^{{commit}}'],cwd=ROOT)
    metadata=build_packages();p=ROOT/'manifest.json';m=json.loads(p.read_text(encoding='utf-8-sig'));assert_base_manifest(m)
    if any(e.get('from_version')==BASE_VERSION and e.get('to_version')==NEW_VERSION for e in m['updates']):raise RuntimeError('v0.6.25 -> v0.6.26 edge already exists')
    latest=[{'path':'bin/spotify-control.ps1','sha256':TARGET_MAIN_SHA,'size':TARGET_MAIN_SIZE},{'path':'bin/addon-manager.ps1','sha256':TARGET_ADDON_SHA,'size':TARGET_ADDON_SIZE},{'path':'bin/spotify-control-agent.vbs','sha256':AGENT_SHA,'size':AGENT_SIZE}]
    edge={'from_version':BASE_VERSION,'to_version':NEW_VERSION,'patches':[metadata['transport']['main'],metadata['transport']['addon']]}
    m['latest_version']=NEW_VERSION;m['source_commit']=source_commit;m['latest_files']=latest;m['payload_set_sha256']=canonical_payload(latest);m['updates'].append(edge)
    p.write_text(json.dumps(m,separators=(',',':'))+'\n',encoding='utf-8',newline='\n')
    print('V0626_MANIFEST_WRITE_PASS',source_commit,m['payload_set_sha256'])
def validate_published():
    metadata=build_packages();m=json.loads((ROOT/'manifest.json').read_text(encoding='utf-8-sig'))
    if m.get('latest_version')!=NEW_VERSION:raise RuntimeError(f"expected published {NEW_VERSION}, got {m.get('latest_version')}")
    if m.get('bootstrap')!=BOOTSTRAP or m.get('min_bootstrap_version')!='1.0.6':raise RuntimeError('published Bootstrap contract drift')
    source=m.get('source_commit','')
    if not re.fullmatch(r'[0-9a-f]{40}',source):raise RuntimeError('published source_commit invalid')
    subprocess.check_call(['git','cat-file','-e',f'{source}^{{commit}}'],cwd=ROOT)
    base_manifest=json.loads(git_bytes(BASE_COMMIT,'manifest.json').decode('utf-8-sig'));assert_base_manifest(base_manifest)
    if m['updates'][:-1]!=base_manifest['updates']:raise RuntimeError('historical update edges changed')
    edge=m['updates'][-1]
    if edge.get('from_version')!=BASE_VERSION or edge.get('to_version')!=NEW_VERSION:raise RuntimeError('published edge missing at tail')
    patches={p['path']:p for p in edge.get('patches',[])}
    if set(patches)!={'bin/spotify-control.ps1','bin/addon-manager.ps1'}:raise RuntimeError('published edge patch set mismatch')
    target_main=read_chunks(patches['bin/spotify-control.ps1'],lambda p:git_bytes(source,p));target_addon=read_chunks(patches['bin/addon-manager.ps1'],lambda p:git_bytes(source,p))
    if (len(target_main),sha(target_main))!=(TARGET_MAIN_SIZE,TARGET_MAIN_SHA):raise RuntimeError('immutable source main reconstruction mismatch')
    if (len(target_addon),sha(target_addon))!=(TARGET_ADDON_SIZE,TARGET_ADDON_SHA):raise RuntimeError('immutable source addon reconstruction mismatch')
    expected_latest=[{'path':'bin/spotify-control.ps1','sha256':TARGET_MAIN_SHA,'size':TARGET_MAIN_SIZE},{'path':'bin/addon-manager.ps1','sha256':TARGET_ADDON_SHA,'size':TARGET_ADDON_SIZE},{'path':'bin/spotify-control-agent.vbs','sha256':AGENT_SHA,'size':AGENT_SIZE}]
    if m['latest_files']!=expected_latest:raise RuntimeError('published latest_files mismatch')
    if m.get('payload_set_sha256')!=canonical_payload(expected_latest):raise RuntimeError('published payload set mismatch')
    for name,path in [('main',MAIN_DIR),('addon',ADDON_DIR)]:
        expected=metadata['transport'][name];actual=patches['bin/spotify-control.ps1' if name=='main' else 'bin/addon-manager.ps1']
        if expected!=actual:raise RuntimeError(f'published {name} transport differs from deterministic rebuild')
        for c in expected['chunks']:
            if (ROOT/c['path']).read_bytes()!=git_bytes(source,c['path']):raise RuntimeError(f"working transport differs from source commit: {c['path']}")
    print('V0626_PUBLISHED_TRANSPORT_PASS',source,m['payload_set_sha256'])
def main():
    p=argparse.ArgumentParser();p.add_argument('--build-packages',action='store_true');p.add_argument('--write-manifest',action='store_true');p.add_argument('--validate-published',action='store_true');p.add_argument('--source-commit');a=p.parse_args();modes=sum(bool(x) for x in (a.build_packages,a.write_manifest,a.validate_published))
    if modes!=1:p.error('choose exactly one mode')
    if a.build_packages:build_packages()
    elif a.write_manifest:
        if not a.source_commit:p.error('--write-manifest requires --source-commit')
        write_manifest(a.source_commit)
    else:validate_published()
if __name__=='__main__':main()
