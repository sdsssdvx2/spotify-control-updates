from pathlib import Path
import argparse,base64,gzip,hashlib,io,json,os,re,shutil,subprocess,zipfile

ROOT=Path(__file__).resolve().parents[2]
BASE_VERSION='0.6.18'
NEW_VERSION='0.6.19'
BASE_MAIN_SHA='27783abc40c446aadf6f2a9373b4525ada89759075f37e934958c8e449f2d98f'
BASE_MAIN_SIZE=281593
BASE_ADDON_SHA='b7d1a4bc7707533400402fe42e60d724f88656c2477d4d4a5c0f47be60f47977'
BASE_ADDON_SIZE=154926
AGENT_SHA='2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278'
AGENT_SIZE=4855
BOOTSTRAP={'version':'1.0.6','sha256':'d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6','size':42963}
FROZEN_MAIN_COMMIT='635358a620a9d28d99a52571085558906af967b6'

OVERLAY_APPLY=ROOT/'performance/overlay/apply-overlay.ps1'
OVERLAY_LOADER=ROOT/'performance/overlay/lazy-custom-app-loader.js'
OVERLAY_TARGETS=ROOT/'performance/overlay/targets/pithaya-optional-custom-apps.json'
WRAPPER_TEMPLATE=ROOT/'validation/v0.6.19/performance_overlay_wrapper.ps1.inc'
OUT=ROOT/'validation/v0.6.19/out/bin'
META=ROOT/'validation/v0.6.19/candidate-metadata.json'
MAIN_CHUNK_DIR=ROOT/'packages/v0.6.19/main-v0618-to-v0619'
ADDON_CHUNK_DIR=ROOT/'packages/v0.6.19/addon-v065r7-to-v065r8'


def sha(b): return hashlib.sha256(b).hexdigest()
def git_bytes(ref,path): return subprocess.check_output(['git','show',f'{ref}:{path}'])
def git_text(ref,path): return git_bytes(ref,path).decode('utf-8-sig')

def load_base_manifest():
    try:
        raw=git_bytes('origin/main','manifest.json')
    except Exception:
        raw=(ROOT/'manifest.json').read_bytes()
    m=json.loads(raw.decode('utf-8-sig'))
    assert m['latest_version']==BASE_VERSION,m['latest_version']
    assert m['bootstrap']==BOOTSTRAP,m['bootstrap']
    latest={x['path']:x for x in m['latest_files']}
    assert latest['bin/spotify-control.ps1']=={'path':'bin/spotify-control.ps1','sha256':BASE_MAIN_SHA,'size':BASE_MAIN_SIZE}
    assert latest['bin/addon-manager.ps1']=={'path':'bin/addon-manager.ps1','sha256':BASE_ADDON_SHA,'size':BASE_ADDON_SIZE}
    assert latest['bin/spotify-control-agent.vbs']=={'path':'bin/spotify-control-agent.vbs','sha256':AGENT_SHA,'size':AGENT_SIZE}
    return m

def concat_chunks(patch, reader=lambda p:(ROOT/p).read_bytes()):
    parts=[]
    for c in patch['chunks']:
        b=reader(c['path'])
        assert len(b)==c['size'] and sha(b)==c['sha256'],(c['path'],len(b),sha(b),c)
        parts.append(b)
    encoded=b''.join(parts)
    assert len(encoded)==patch['encoded_size'] and sha(encoded)==patch['encoded_sha256']
    return encoded

def decode_main_seed():
    paths=sorted((ROOT/'packages/v0.6.11/chunks').glob('chunk-*.txt'))
    assert paths
    encoded=b''.join(p.read_bytes() for p in paths)
    blob=base64.b64decode(encoded,validate=True)
    with zipfile.ZipFile(io.BytesIO(blob),'r') as z:
        names=z.namelist(); candidates=[n for n in names if n.lower().endswith('spotify-control.ps1')]
        assert len(candidates)==1,candidates
        raw=z.read(candidates[0])
    assert sha(raw)=='045ed3fa898453ce6563a057a31412d254f5958b75286589e8d5cc95c6782a39'
    return raw

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

def reconstruct_base_main(m):
    raw=decode_main_seed(); current='0.6.11'
    while current!=BASE_VERSION:
        edge=next(e for e in m['updates'] if e['from_version']==current)
        rows=[p for p in edge['patches'] if p['path']=='bin/spotify-control.ps1']
        if rows:
            p=rows[0]; assert sha(raw)==p['from_sha256']
            encoded=concat_chunks(p)
            comp=base64.b64decode(encoded,validate=True)
            assert len(comp)==p['compressed_size'] and sha(comp)==p['compressed_sha256']
            patch_raw=gzip.decompress(comp)
            if 'json_size' in p: assert len(patch_raw)==p['json_size'] and sha(patch_raw)==p['json_sha256']
            doc=json.loads(patch_raw.decode('ascii'))
            raw=apply_ascii_line_patch(raw,doc)
            assert sha(raw)==p['to_sha256']
        current=edge['to_version']
    assert len(raw)==BASE_MAIN_SIZE and sha(raw)==BASE_MAIN_SHA
    return raw

def reconstruct_base_addon(m):
    latest={x['path']:x for x in m['latest_files']}['bin/addon-manager.ps1']
    candidates=[]
    for edge in m['updates']:
        for p in edge['patches']:
            if p['path']=='bin/addon-manager.ps1' and p['to_sha256']==latest['sha256'] and p['encoding']=='gzip-base64-full-file': candidates.append(p)
    assert len(candidates)>=1
    p=candidates[-1]
    encoded=concat_chunks(p)
    comp=base64.b64decode(encoded,validate=True)
    assert len(comp)==p['compressed_size'] and sha(comp)==p['compressed_sha256']
    raw=gzip.decompress(comp)
    assert len(raw)==p['target_size']==BASE_ADDON_SIZE and sha(raw)==BASE_ADDON_SHA
    return raw

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

def expand_wrapper(addon_newline):
    apply=OVERLAY_APPLY.read_bytes(); loader=OVERLAY_LOADER.read_bytes(); targets=OVERLAY_TARGETS.read_bytes()
    template=WRAPPER_TEMPLATE.read_text(encoding='utf-8').replace('\r\n','\n')
    replacements={
        '@@APPLY_B64@@':base64.b64encode(apply).decode('ascii'),'@@APPLY_SHA@@':sha(apply),
        '@@LOADER_B64@@':base64.b64encode(loader).decode('ascii'),'@@LOADER_SHA@@':sha(loader),
        '@@TARGETS_B64@@':base64.b64encode(targets).decode('ascii'),'@@TARGETS_SHA@@':sha(targets),
    }
    for key,val in replacements.items():
        assert template.count(key)==1,key; template=template.replace(key,val)
    assert '@@' not in template
    return template.replace('\n',addon_newline),{
        'apply_overlay':{'sha256':sha(apply),'size':len(apply)},
        'loader':{'sha256':sha(loader),'size':len(loader)},
        'targets':{'sha256':sha(targets),'size':len(targets)},
    }

def build_addon(base):
    bom=b'\xef\xbb\xbf' if base.startswith(b'\xef\xbb\xbf') else b''
    body=base[len(bom):]
    text=body.decode('utf-8')
    crlf=text.count('\r\n'); lf=text.count('\n')
    newline='\r\n' if crlf and crlf==lf else '\n'
    if newline=='\n': assert '\r\n' not in text
    assert text.count('$Version = "0.6.5-r7"')==1
    text=text.replace('$Version = "0.6.5-r7"','$Version = "0.6.5-r8"',1)
    wrapper,overlay_meta=expand_wrapper(newline)
    marker='function Update-AutoApps {'
    assert text.count(marker)==1
    text=text.replace(marker,wrapper+newline+newline+marker,1)
    old='Write-AddonLog "No safely-proven managed CustomApp updates were needed."'+newline+'        exit 0'
    new='Write-AddonLog "No safely-proven managed CustomApp updates were needed."'+newline+'        Invoke-PerformanceOverlayBestEffort -Reason "update-no-candidates"'+newline+'        exit 0'
    assert text.count(old)==1; text=text.replace(old,new,1)
    old='Write-AddonLog "Addon update cycle is not due."'+newline+'                exit 0'
    new='Write-AddonLog "Addon update cycle is not due."'+newline+'                Invoke-PerformanceOverlayBestEffort -Reason "update-not-due"'+newline+'                exit 0'
    assert text.count(old)==1; text=text.replace(old,new,1)
    old='"CommitLast" {'+newline+'            Commit-LastTransaction'+newline+'        }'
    new='"CommitLast" {'+newline+'            Commit-LastTransaction'+newline+'            Invoke-PerformanceOverlayBestEffort -Reason "commit-last"'+newline+'        }'
    assert text.count(old)==1; text=text.replace(old,new,1)
    assert text.count('# BEGIN SPOTIFY CONTROL PERFORMANCE OVERLAY v0.1.0 / r8')==1
    assert text.count('Invoke-PerformanceOverlayBestEffort -Reason')==4  # function definition + 3 calls
    assert '"Check" {' in text
    check_block=text[text.index('"Check" {'):text.index('"Update" {')]
    assert 'Invoke-PerformanceOverlayBestEffort' not in check_block
    raw=bom+text.encode('utf-8')
    return raw,overlay_meta,newline

def build_main(base):
    assert base.startswith(b'\xef\xbb\xbf')
    body=base[3:]; assert b'\r\n' not in body
    lines=body.decode('ascii').splitlines(keepends=True)
    assert lines[0]=='# Spotify Control v0.6.18 Spicetify Backup-Metadata Repair\n'
    assert lines[12]=='$ScriptVersion = "0.6.18"\n'
    new_lines=list(lines)
    new_lines[0]='# Spotify Control v0.6.19 Performance Overlay\n'
    new_lines[12]='$ScriptVersion = "0.6.19"\n'
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
    # Prove exactly two logical source lines changed.
    diffs=[i for i,(a,b) in enumerate(zip(lines,new_lines)) if a!=b]
    assert diffs==[0,12],diffs
    return candidate,doc

def canonical_payload(latest):
    rows=[f"{x['path']}|{int(x['size'])}|{x['sha256']}" for x in sorted(latest,key=lambda x:x['path'])]
    return sha(('\n'.join(rows)+'\n').encode('ascii'))

def build():
    m=load_base_manifest(); base_main=reconstruct_base_main(m); base_addon=reconstruct_base_addon(m)
    candidate_main,patch_doc=build_main(base_main)
    candidate_addon,overlay_meta,addon_newline=build_addon(base_addon)
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
        'schema':1,'version':NEW_VERSION,'base_version':BASE_VERSION,'frozen_main_commit':FROZEN_MAIN_COMMIT,
        'base_main':{'sha256':BASE_MAIN_SHA,'size':BASE_MAIN_SIZE},
        'candidate_main':latest[0],
        'base_addon':{'sha256':BASE_ADDON_SHA,'size':BASE_ADDON_SIZE},
        'candidate_addon':latest[1],
        'agent':latest[2],
        'overlay':overlay_meta,'addon_line_ending':'crlf' if addon_newline=='\r\n' else 'lf',
        'main_patch':main_transport,'addon_patch':addon_transport,
        'payload_set_sha256':canonical_payload(latest),
    }
    META.write_text(json.dumps(meta,indent=2,sort_keys=True)+'\n',encoding='utf-8',newline='\n')
    # Reconstruct both generated transports immediately.
    enc=b''.join((ROOT/c['path']).read_bytes() for c in main_chunks); assert sha(enc)==main_transport['encoded_sha256']
    doc2=json.loads(gzip.decompress(base64.b64decode(enc,validate=True)).decode('ascii')); assert apply_ascii_line_patch(base_main,doc2)==candidate_main
    enc=b''.join((ROOT/c['path']).read_bytes() for c in addon_chunks); assert sha(enc)==addon_transport['encoded_sha256']
    assert gzip.decompress(base64.b64decode(enc,validate=True))==candidate_addon
    print('V0619_BUILD_PASS',len(candidate_main),sha(candidate_main),len(candidate_addon),sha(candidate_addon),meta['payload_set_sha256'])

def write_manifest(source_commit):
    assert re.fullmatch(r'[0-9a-f]{40}',source_commit),source_commit
    meta=json.loads(META.read_text(encoding='utf-8'))
    p=ROOT/'manifest.json'; m=json.loads(p.read_text(encoding='utf-8-sig'))
    assert m['bootstrap']==BOOTSTRAP
    if m['latest_version']==NEW_VERSION:
        assert m['source_commit']==source_commit
        validate_published(); return
    assert m['latest_version']==BASE_VERSION
    latest={x['path']:x for x in m['latest_files']}
    latest['bin/spotify-control.ps1']=meta['candidate_main']
    latest['bin/addon-manager.ps1']=meta['candidate_addon']
    assert latest['bin/spotify-control-agent.vbs']==meta['agent']
    m['latest_version']=NEW_VERSION
    m['source_commit']=source_commit
    m['payload_set_sha256']=meta['payload_set_sha256']
    assert not any(e['from_version']==BASE_VERSION for e in m['updates'])
    m['updates'].append({'from_version':BASE_VERSION,'to_version':NEW_VERSION,'patches':[meta['main_patch'],meta['addon_patch']]})
    p.write_text(json.dumps(m,separators=(',',':')),encoding='utf-8',newline='')
    print('V0619_MANIFEST_WRITTEN',source_commit,meta['payload_set_sha256'])

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
    ref=m['source_commit']
    base=load_base_manifest(); base_main=reconstruct_base_main(base)
    main_p=meta['main_patch']; enc=concat_chunks(main_p,lambda p:git_bytes(ref,p)); comp=base64.b64decode(enc,validate=True)
    assert sha(comp)==main_p['compressed_sha256']; raw=gzip.decompress(comp); assert len(raw)==main_p['json_size'] and sha(raw)==main_p['json_sha256']
    candidate=apply_ascii_line_patch(base_main,json.loads(raw.decode('ascii'))); assert len(candidate)==meta['candidate_main']['size'] and sha(candidate)==meta['candidate_main']['sha256']
    addon_p=meta['addon_patch']; enc=concat_chunks(addon_p,lambda p:git_bytes(ref,p)); comp=base64.b64decode(enc,validate=True)
    candidate=gzip.decompress(comp); assert len(candidate)==addon_p['target_size']==meta['candidate_addon']['size'] and sha(candidate)==addon_p['to_sha256']==meta['candidate_addon']['sha256']
    print('V0619_PUBLISHED_PASS',ref,m['payload_set_sha256'])

if __name__=='__main__':
    ap=argparse.ArgumentParser(); ap.add_argument('--build',action='store_true'); ap.add_argument('--write-manifest',action='store_true'); ap.add_argument('--source-commit'); ap.add_argument('--validate-published',action='store_true')
    a=ap.parse_args(); assert sum(bool(x) for x in [a.build,a.write_manifest,a.validate_published])==1
    if a.build: build()
    elif a.write_manifest:
        assert a.source_commit; write_manifest(a.source_commit)
    else: validate_published()
