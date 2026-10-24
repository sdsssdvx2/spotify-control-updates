from pathlib import Path
import base64, gzip, hashlib, json, shutil, subprocess

BASE_MAIN='9c0475db358afb8b3f54fb603c99823ec2b608d0'
OLD_SOURCE='e51f73c90c50cb55e3e3dffe3b55a6f6b1af0b4c'
LATEST='0.6.17'
PAYLOAD='0f7fe384630e027466aa734ac669b410774b4569db231982212b7fa565b691a0'
BOOTSTRAP_SHA='d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6'
REPAIRS=[
    ('0.6.15','0.6.16','packages/v0.6.16/main-v0615-to-v0616-compat','4faef1e70be20efb551f595c02dad171a44abbe8a53af9a0576dc54fd0e2004f','6d5e154f63dfb77d15e0541a87a653863e0ae9f95df59ffa9bb4b413f97766ad'),
    ('0.6.16','0.6.17','packages/v0.6.17/main-v0616-to-v0617-compat','6d5e154f63dfb77d15e0541a87a653863e0ae9f95df59ffa9bb4b413f97766ad','5ff7990564287bc409626d8835e27679fb8de434868443313be42fdc0d9cce3b'),
]

def sha(b): return hashlib.sha256(b).hexdigest()
def git_bytes(ref,path): return subprocess.check_output(['git','show',f'{ref}:{path}'])
def load_manifest(ref=None):
    raw=Path('manifest.json').read_bytes() if ref is None else git_bytes(ref,'manifest.json')
    return json.loads(raw.decode('utf-8-sig'))
def get_edge(m,a,b): return next(e for e in m['updates'] if e['from_version']==a and e['to_version']==b)
def get_main_patch(e): return next(p for p in e['patches'] if p['path']=='bin/spotify-control.ps1')

def decode_doc(m,a,b):
    p=get_main_patch(get_edge(m,a,b)); parts=[]
    for i,c in enumerate(p['chunks']):
        q=c['path'].replace('\\','/')
        assert q.endswith(f'/chunk-{i:03}.txt'),q
        data=git_bytes(m['source_commit'],q)
        assert len(data)==int(c['size']) and sha(data)==c['sha256'],q
        parts.append(data)
    enc=b''.join(parts)
    assert len(enc)==int(p['encoded_size']) and sha(enc)==p['encoded_sha256']
    comp=base64.b64decode(enc,validate=True)
    assert len(comp)==int(p['compressed_size']) and sha(comp)==p['compressed_sha256']
    raw=gzip.decompress(comp)
    assert len(raw)==int(p['json_size']) and sha(raw)==p['json_sha256']
    return p,json.loads(raw.decode('ascii')),raw

def normalize_doc(doc,a,b,from_sha,to_sha):
    assert doc.get('kind')=='ascii-line-patch'
    assert doc.get('from_version')==a and doc.get('to_version')==b
    assert doc.get('from_sha256')==from_sha and doc.get('to_sha256')==to_sha
    assert isinstance(doc.get('operations'),list) and doc['operations']
    # Original 0.6.16/0.6.17 publications omitted exactly these parser-contract fields.
    for k in ('schema','bom','line_ending'):
        assert k not in doc,(a,b,k,doc.get(k))
    return {
        'schema':1,
        'kind':'ascii-line-patch',
        'from_version':a,
        'to_version':b,
        'from_sha256':from_sha,
        'to_sha256':to_sha,
        'bom':'utf8-bom',
        'line_ending':'lf',
        'operations':doc['operations'],
    }

def chunk_rows(folder,data):
    root=Path('publication-bootstrap-contract-repair')/folder
    root.mkdir(parents=True,exist_ok=True); rows=[]
    for off in range(0,len(data),4096):
        part=data[off:off+4096]; name=f'chunk-{off//4096:03}.txt'; (root/name).write_bytes(part)
        rows.append({'path':f'{folder}/{name}','sha256':sha(part),'size':len(part)})
    return rows

def transport_for(doc,folder):
    raw=json.dumps(doc,separators=(',',':'),ensure_ascii=True).encode('ascii')
    comp=gzip.compress(raw,compresslevel=9,mtime=0); enc=base64.b64encode(comp)
    return raw,comp,enc,chunk_rows(folder,enc)

def replace_transport(p,raw,comp,enc,rows):
    q=json.loads(json.dumps(p))
    q['encoding']='gzip-base64-chunks'
    q['encoded_sha256']=sha(enc); q['encoded_size']=len(enc)
    q['compressed_sha256']=sha(comp); q['compressed_size']=len(comp)
    q['json_sha256']=sha(raw); q['json_size']=len(raw)
    q['chunks']=rows
    return q

def prepare(m):
    base=load_manifest(BASE_MAIN)
    assert m==base
    assert m['latest_version']==LATEST and m['source_commit']==OLD_SOURCE
    assert m['payload_set_sha256']==PAYLOAD
    assert m['bootstrap']['version']=='1.0.6' and m['bootstrap']['sha256']==BOOTSTRAP_SHA
    out=Path('publication-bootstrap-contract-repair'); shutil.rmtree(out,ignore_errors=True); out.mkdir()
    nxt=json.loads(json.dumps(m)); proofs=[]
    for a,b,folder,fs,ts in REPAIRS:
        oldp,doc,_=decode_doc(m,a,b)
        nd=normalize_doc(doc,a,b,fs,ts)
        raw,comp,enc,rows=transport_for(nd,folder)
        e=get_edge(nxt,a,b); idx=next(i for i,p in enumerate(e['patches']) if p['path']=='bin/spotify-control.ps1')
        e['patches'][idx]=replace_transport(oldp,raw,comp,enc,rows)
        proofs.append((a,b,folder,len(raw),sha(raw),len(enc),sha(enc)))
    nxt['source_commit']='__SOURCE_COMMIT__'
    assert nxt['latest_version']==m['latest_version']
    assert nxt['payload_set_sha256']==m['payload_set_sha256']
    assert nxt['latest_files']==m['latest_files']
    assert nxt['bootstrap']==m['bootstrap']
    (out/'manifest-template.json').write_text(json.dumps(nxt,separators=(',',':')),encoding='utf-8',newline='\n')
    for x in proofs: print('PREPARED_COMPAT_DOC',*x)
    print('BOOTSTRAP_CONTRACT_REPAIR_PREPARE_OK')

def final_validate(m):
    base=load_manifest(BASE_MAIN)
    assert m['latest_version']==LATEST and m['source_commit']!=OLD_SOURCE
    assert m['payload_set_sha256']==PAYLOAD
    assert m['bootstrap']==base['bootstrap']
    assert m['latest_files']==base['latest_files']
    subprocess.check_call(['git','merge-base','--is-ancestor',m['source_commit'],'HEAD'])
    tmp=json.loads(json.dumps(m)); tmp['source_commit']=base['source_commit']
    for a,b,folder,fs,ts in REPAIRS:
        bp=get_main_patch(get_edge(base,a,b)); cp=get_main_patch(get_edge(tmp,a,b))
        for k in ('path','from_sha256','to_sha256','encoding'):
            assert cp[k]==bp[k],(a,b,k,cp[k],bp[k])
        p,doc,raw=decode_doc(m,a,b)
        assert doc['schema']==1 and doc['kind']=='ascii-line-patch'
        assert doc['bom']=='utf8-bom' and doc['line_ending']=='lf'
        assert doc['from_version']==a and doc['to_version']==b
        assert doc['from_sha256']==fs and doc['to_sha256']==ts
        assert doc['operations']==decode_doc(base,a,b)[1]['operations']
        assert len(p['chunks'])>=1
        for i,c in enumerate(p['chunks']):
            q=c['path'].replace('\\','/')
            assert q==f'{folder}/chunk-{i:03}.txt',q
            assert q.startswith(f'packages/v{b}/')
            # Match bootstrap 1.0.6 safe-path grammar: exactly one directory below packages/vX.Y.Z.
            assert q.count('/')==3,q
        e=get_edge(tmp,a,b); idx=next(i for i,x in enumerate(e['patches']) if x['path']=='bin/spotify-control.ps1'); e['patches'][idx]=bp
        print('VALIDATED_COMPAT_DOC',a,b,folder,len(raw),sha(raw))
    assert tmp==base,'Repair changed data outside source_commit and the two main-patch transport envelopes'
    froms=[e['from_version'] for e in m['updates']]; assert len(froms)==len(set(froms))
    print('BOOTSTRAP_CONTRACT_REPAIR_FINAL_OK',m['source_commit'])

m=load_manifest()
new_paths=[]
for a,b,folder,_,_ in REPAIRS:
    new_paths += [c['path'] for c in get_main_patch(get_edge(m,a,b))['chunks'] if c['path'].startswith(folder+'/')]
if not new_paths:
    prepare(m)
else:
    assert len(new_paths)>=2
    final_validate(m)
