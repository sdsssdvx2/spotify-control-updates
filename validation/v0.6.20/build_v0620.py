from pathlib import Path
import argparse,base64,gzip,hashlib,io,json,re,shutil,subprocess,sys

ROOT=Path(__file__).resolve().parents[2]
BASE_VERSION='0.6.19'
NEW_VERSION='0.6.20'
BASE_MAIN_SHA='45795b9622953a10c6eca2ee2f5a19fc4467c5143d5bdf7a9f2ad64841b9416f'
BASE_MAIN_SIZE=281580
BASE_ADDON_SHA='df17018bdb5f62f55624070d047933387f62c049dae73cf5cefcc541bc412afa'
BASE_ADDON_SIZE=202849
AGENT_SHA='2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278'
AGENT_SIZE=4855
BOOTSTRAP={'version':'1.0.6','sha256':'d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6','size':42963}
STAR_ORIGINAL_SHA='198fd7c3307de8f2efc36f40df4e79846188cf35a1d5b550ed3d8ab85e8139b1'
STAR_ORIGINAL_SIZE=43396
STAR_TRANSFORMED_SHA='6e0d1c84408294a619d91191eec83a6d10794ef31093d31ccf1f1bd39ea8c8a3'
STAR_SOURCE_REVISION='33aa3d293f9fbb58d7a749a8cea10c318351e6c6'
STAR_ENGINE=ROOT/'performance/star-ratings/apply-star-ratings-patch.ps1'
STAR_TARGET=ROOT/'performance/star-ratings/target.json'
WRAPPER_TEMPLATE=ROOT/'validation/v0.6.20/star_ratings_wrapper.ps1.inc'
BASE_OUT=ROOT/'validation/v0.6.19/out/bin'
OUT=ROOT/'validation/v0.6.20/out/bin'
META=ROOT/'validation/v0.6.20/candidate-metadata.json'
MAIN_CHUNK_DIR=ROOT/'packages/v0.6.20/main-v0619-to-v0620'
ADDON_CHUNK_DIR=ROOT/'packages/v0.6.20/addon-v065r8-to-v065r9'


def sha(b): return hashlib.sha256(b).hexdigest()
def git_bytes(ref,path): return subprocess.check_output(['git','show',f'{ref}:{path}'])

def deterministic_gzip(data):
    buf=io.BytesIO()
    with gzip.GzipFile(filename='',mode='wb',fileobj=buf,compresslevel=9,mtime=0) as g: g.write(data)
    return buf.getvalue()

def clean_dir(path):
    if path.exists(): shutil.rmtree(path)
    path.mkdir(parents=True,exist_ok=True)

def write_chunks(encoded,folder,size):
    clean_dir(folder); rows=[]
    for i in range(0,len(encoded),size):
        b=encoded[i:i+size]; p=folder/f'chunk-{i//size:03d}.txt'; p.write_bytes(b)
        rows.append({'path':str(p.relative_to(ROOT)).replace('\\','/'),'sha256':sha(b),'size':len(b)})
    assert rows
    return rows

def concat_chunks(patch,reader=lambda p:(ROOT/p).read_bytes()):
    parts=[]
    for c in patch['chunks']:
        b=reader(c['path'])
        assert len(b)==c['size'] and sha(b)==c['sha256'],(c['path'],len(b),sha(b),c)
        parts.append(b)
    encoded=b''.join(parts)
    assert len(encoded)==patch['encoded_size'] and sha(encoded)==patch['encoded_sha256']
    return encoded

def apply_ascii_line_patch(raw,doc):
    assert doc['schema']==1 and doc['kind']=='ascii-line-patch'
    bom=b'\xef\xbb\xbf' if doc.get('bom')=='utf8-bom' else b''
    if bom:
        assert raw.startswith(bom); body=raw[len(bom):]
    else: body=raw
    assert b'\r\n' not in body
    lines=body.decode('ascii').splitlines(keepends=True)
    for op in sorted(doc['operations'],key=lambda x:int(x['start_line']),reverse=True):
        start=int(op['start_line']); delete=int(op['delete_count']); insert=str(op.get('insert',''))
        lines[start:start+delete]=insert.splitlines(keepends=True)
    return bom+''.join(lines).encode('ascii')

def canonical_payload(latest):
    rows=[f"{x['path']}|{int(x['size'])}|{x['sha256']}" for x in sorted(latest,key=lambda x:x['path'])]
    return sha(('\n'.join(rows)+'\n').encode('ascii'))

def prepare_base():
    subprocess.check_call([sys.executable,str(ROOT/'validation/v0.6.19/build_v0619.py'),'--build'],cwd=ROOT)
    main=(BASE_OUT/'spotify-control.ps1').read_bytes(); addon=(BASE_OUT/'addon-manager.ps1').read_bytes()
    assert len(main)==BASE_MAIN_SIZE and sha(main)==BASE_MAIN_SHA,(len(main),sha(main))
    assert len(addon)==BASE_ADDON_SIZE and sha(addon)==BASE_ADDON_SHA,(len(addon),sha(addon))
    return main,addon

def expand_star_wrapper(newline):
    engine=STAR_ENGINE.read_bytes(); target=STAR_TARGET.read_bytes()
    target_doc=json.loads(target.decode('utf-8'))
    assert target_doc['schema']==1
    t=target_doc['target']
    assert t['expected_size']==STAR_ORIGINAL_SIZE and t['expected_sha256']==STAR_ORIGINAL_SHA
    assert t['transformed_sha256']==STAR_TRANSFORMED_SHA and t['source_revision']==STAR_SOURCE_REVISION
    template=WRAPPER_TEMPLATE.read_text(encoding='utf-8').replace('\r\n','\n')
    replacements={
        '@@STAR_ENGINE_B64@@':base64.b64encode(engine).decode('ascii'),
        '@@STAR_ENGINE_SHA@@':sha(engine),
        '@@STAR_TARGET_B64@@':base64.b64encode(target).decode('ascii'),
        '@@STAR_TARGET_SHA@@':sha(target),
    }
    for key,val in replacements.items():
        assert template.count(key)==1,key
        template=template.replace(key,val)
    assert '@@STAR_' not in template
    return template.replace('\n',newline),{
        'engine':{'path':'performance/star-ratings/apply-star-ratings-patch.ps1','sha256':sha(engine),'size':len(engine)},
        'target':{'path':'performance/star-ratings/target.json','sha256':sha(target),'size':len(target)},
        'source_repository':t['source_repository'],'source_revision':t['source_revision'],
        'active_original':{'path':t['relative_path'],'sha256':t['expected_sha256'],'size':t['expected_size']},
        'transformed_sha256':t['transformed_sha256'],
    }

def build_main(base):
    assert base.startswith(b'\xef\xbb\xbf')
    body=base[3:]; assert b'\r\n' not in body
    lines=body.decode('ascii').splitlines(keepends=True)
    assert lines[0]=='# Spotify Control v0.6.19 Performance Overlay\n'
    assert lines[12]=='$ScriptVersion = "0.6.19"\n'
    new_lines=list(lines)
    new_lines[0]='# Spotify Control v0.6.20 Star Ratings Performance\n'
    new_lines[12]='$ScriptVersion = "0.6.20"\n'
    candidate=b'\xef\xbb\xbf'+''.join(new_lines).encode('ascii')
    doc={
        'schema':1,'kind':'ascii-line-patch','from_version':BASE_VERSION,'to_version':NEW_VERSION,
        'from_sha256':sha(base),'to_sha256':sha(candidate),'bom':'utf8-bom','line_ending':'lf',
        'operations':[
            {'start_line':0,'delete_count':1,'insert':new_lines[0]},
            {'start_line':12,'delete_count':1,'insert':new_lines[12]},
        ]
    }
    assert apply_ascii_line_patch(base,doc)==candidate
    assert [i for i,(a,b) in enumerate(zip(lines,new_lines)) if a!=b]==[0,12]
    return candidate,doc

def build_addon(base):
    bom=b'\xef\xbb\xbf' if base.startswith(b'\xef\xbb\xbf') else b''
    text=base[len(bom):].decode('utf-8')
    crlf=text.count('\r\n'); lf=text.count('\n'); newline='\r\n' if crlf and crlf==lf else '\n'
    if newline=='\n': assert '\r\n' not in text
    assert text.count('$Version = "0.6.5-r8"')==1
    text=text.replace('$Version = "0.6.5-r8"','$Version = "0.6.5-r9"',1)
    wrapper,star_meta=expand_star_wrapper(newline)
    marker='function Update-AutoApps {'
    assert text.count(marker)==1
    text=text.replace(marker,wrapper+newline+newline+marker,1)
    for reason,indent in [('update-no-candidates','        '),('update-not-due','                '),('commit-last','            ')]:
        old=indent+'Invoke-PerformanceOverlayBestEffort -Reason "'+reason+'"'
        new=old+newline+indent+'Invoke-StarRatingsPerformanceBestEffort -Reason "'+reason+'"'
        assert text.count(old)==1,(reason,text.count(old))
        text=text.replace(old,new,1)
    assert text.count('# BEGIN SPOTIFY CONTROL PERFORMANCE OVERLAY v0.1.0 / r8')==1
    assert text.count('# BEGIN SPOTIFY CONTROL STAR RATINGS PERFORMANCE v1 / r9')==1
    assert text.count('Invoke-PerformanceOverlayBestEffort -Reason')==3
    assert text.count('Invoke-StarRatingsPerformanceBestEffort -Reason')==3
    assert '"Check" {' in text and '"Update" {' in text
    check=text[text.index('"Check" {'):text.index('"Update" {')]
    assert 'Invoke-PerformanceOverlayBestEffort' not in check
    assert 'Invoke-StarRatingsPerformanceBestEffort' not in check
    assert 'popup-lyrics-worker-gate' not in text.lower()
    raw=bom+text.encode('utf-8')
    return raw,star_meta,newline

def build():
    base_main,base_addon=prepare_base()
    candidate_main,patch_doc=build_main(base_main)
    candidate_addon,star_meta,addon_newline=build_addon(base_addon)
    OUT.mkdir(parents=True,exist_ok=True)
    (OUT/'spotify-control.ps1').write_bytes(candidate_main)
    (OUT/'addon-manager.ps1').write_bytes(candidate_addon)

    patch_json=json.dumps(patch_doc,separators=(',',':'),ensure_ascii=True).encode('ascii')
    patch_gz=deterministic_gzip(patch_json); patch_b64=base64.b64encode(patch_gz)
    main_chunks=write_chunks(patch_b64,MAIN_CHUNK_DIR,1024)
    main_transport={
        'path':'bin/spotify-control.ps1','from_sha256':BASE_MAIN_SHA,'to_sha256':sha(candidate_main),
        'encoding':'gzip-base64-chunks','encoded_sha256':sha(patch_b64),'encoded_size':len(patch_b64),
        'compressed_sha256':sha(patch_gz),'compressed_size':len(patch_gz),
        'json_sha256':sha(patch_json),'json_size':len(patch_json),'chunks':main_chunks,
    }
    addon_gz=deterministic_gzip(candidate_addon); addon_b64=base64.b64encode(addon_gz)
    addon_chunks=write_chunks(addon_b64,ADDON_CHUNK_DIR,4096)
    addon_transport={
        'path':'bin/addon-manager.ps1','from_sha256':BASE_ADDON_SHA,'to_sha256':sha(candidate_addon),
        'encoding':'gzip-base64-full-file','encoded_sha256':sha(addon_b64),'encoded_size':len(addon_b64),
        'compressed_sha256':sha(addon_gz),'compressed_size':len(addon_gz),'target_size':len(candidate_addon),'chunks':addon_chunks,
    }
    latest=[
        {'path':'bin/spotify-control.ps1','sha256':sha(candidate_main),'size':len(candidate_main)},
        {'path':'bin/addon-manager.ps1','sha256':sha(candidate_addon),'size':len(candidate_addon)},
        {'path':'bin/spotify-control-agent.vbs','sha256':AGENT_SHA,'size':AGENT_SIZE},
    ]
    meta={
        'schema':1,'version':NEW_VERSION,'base_version':BASE_VERSION,
        'base_main':{'path':'bin/spotify-control.ps1','sha256':BASE_MAIN_SHA,'size':BASE_MAIN_SIZE},
        'candidate_main':latest[0],
        'base_addon':{'path':'bin/addon-manager.ps1','sha256':BASE_ADDON_SHA,'size':BASE_ADDON_SIZE},
        'candidate_addon':latest[1],
        'agent':latest[2],'addon_line_ending':'crlf' if addon_newline=='\r\n' else 'lf',
        'star_ratings':star_meta,
        'runtime_acceptance':{
            'profiler_version':'0.5.3','baseline_confidence':'high','baseline_cpu_p95_drift_points':0.33,'baseline_renderer_p95_drift_points':1.36,
            'star_cpu_p95_saving_points':2.22,'star_renderer_p95_saving_points':1.66,
            'popup_promoted':False,'combined_promoted':False,'combined_cpu_p95_saving_points':-0.99,
        },
        'main_patch':main_transport,'addon_patch':addon_transport,'payload_set_sha256':canonical_payload(latest),
    }
    META.parent.mkdir(parents=True,exist_ok=True)
    META.write_text(json.dumps(meta,indent=2,sort_keys=True)+'\n',encoding='utf-8',newline='\n')
    enc=b''.join((ROOT/c['path']).read_bytes() for c in main_chunks); assert sha(enc)==main_transport['encoded_sha256']
    raw=gzip.decompress(base64.b64decode(enc,validate=True)); assert sha(raw)==main_transport['json_sha256']
    assert apply_ascii_line_patch(base_main,json.loads(raw.decode('ascii')))==candidate_main
    enc=b''.join((ROOT/c['path']).read_bytes() for c in addon_chunks); assert sha(enc)==addon_transport['encoded_sha256']
    assert gzip.decompress(base64.b64decode(enc,validate=True))==candidate_addon
    print('V0620_BUILD_PASS',len(candidate_main),sha(candidate_main),len(candidate_addon),sha(candidate_addon),meta['payload_set_sha256'])

def write_manifest(source_commit):
    assert re.fullmatch(r'[0-9a-f]{40}',source_commit),source_commit
    meta=json.loads(META.read_text(encoding='utf-8'))
    p=ROOT/'manifest.json'; m=json.loads(p.read_text(encoding='utf-8-sig'))
    assert m['bootstrap']==BOOTSTRAP
    if m['latest_version']==NEW_VERSION:
        assert m['source_commit']==source_commit
        validate_published(); return
    assert m['latest_version']==BASE_VERSION,m['latest_version']
    latest={x['path']:x for x in m['latest_files']}
    assert latest['bin/spotify-control.ps1']==meta['base_main']
    assert latest['bin/addon-manager.ps1']==meta['base_addon']
    assert latest['bin/spotify-control-agent.vbs']==meta['agent']
    m['latest_files']=[meta['candidate_main'] if x['path']=='bin/spotify-control.ps1' else meta['candidate_addon'] if x['path']=='bin/addon-manager.ps1' else x for x in m['latest_files']]
    m['latest_version']=NEW_VERSION; m['source_commit']=source_commit; m['payload_set_sha256']=meta['payload_set_sha256']
    assert not any(e['from_version']==BASE_VERSION for e in m['updates'])
    m['updates'].append({'from_version':BASE_VERSION,'to_version':NEW_VERSION,'patches':[meta['main_patch'],meta['addon_patch']]})
    p.write_text(json.dumps(m,separators=(',',':')),encoding='utf-8',newline='')
    print('V0620_MANIFEST_WRITTEN',source_commit,meta['payload_set_sha256'])

def validate_published():
    meta=json.loads(META.read_text(encoding='utf-8'))
    m=json.loads((ROOT/'manifest.json').read_text(encoding='utf-8-sig'))
    assert m['latest_version']==NEW_VERSION and m['bootstrap']==BOOTSTRAP
    assert re.fullmatch(r'[0-9a-f]{40}',m['source_commit'])
    latest={x['path']:x for x in m['latest_files']}
    assert latest['bin/spotify-control.ps1']==meta['candidate_main']
    assert latest['bin/addon-manager.ps1']==meta['candidate_addon']
    assert latest['bin/spotify-control-agent.vbs']==meta['agent']
    assert canonical_payload(m['latest_files'])==meta['payload_set_sha256']==m['payload_set_sha256']
    edges=[e for e in m['updates'] if e['from_version']==BASE_VERSION]
    assert edges==[{'from_version':BASE_VERSION,'to_version':NEW_VERSION,'patches':[meta['main_patch'],meta['addon_patch']]}]
    ref=m['source_commit']; base_main,base_addon=prepare_base()
    main_p=meta['main_patch']; enc=concat_chunks(main_p,lambda p:git_bytes(ref,p)); comp=base64.b64decode(enc,validate=True)
    assert sha(comp)==main_p['compressed_sha256']; raw=gzip.decompress(comp); assert len(raw)==main_p['json_size'] and sha(raw)==main_p['json_sha256']
    candidate=apply_ascii_line_patch(base_main,json.loads(raw.decode('ascii'))); assert len(candidate)==meta['candidate_main']['size'] and sha(candidate)==meta['candidate_main']['sha256']
    addon_p=meta['addon_patch']; enc=concat_chunks(addon_p,lambda p:git_bytes(ref,p)); comp=base64.b64decode(enc,validate=True)
    candidate=gzip.decompress(comp); assert len(candidate)==addon_p['target_size']==meta['candidate_addon']['size'] and sha(candidate)==addon_p['to_sha256']==meta['candidate_addon']['sha256']
    print('V0620_PUBLISHED_PASS',ref,m['payload_set_sha256'])

if __name__=='__main__':
    ap=argparse.ArgumentParser();ap.add_argument('--build',action='store_true');ap.add_argument('--write-manifest',action='store_true');ap.add_argument('--source-commit');ap.add_argument('--validate-published',action='store_true')
    a=ap.parse_args();assert sum(bool(x) for x in [a.build,a.write_manifest,a.validate_published])==1
    if a.build: build()
    elif a.write_manifest:
        assert a.source_commit;write_manifest(a.source_commit)
    else: validate_published()
