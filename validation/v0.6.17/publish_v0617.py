from pathlib import Path
from io import BytesIO
import base64, gzip, hashlib, json, shutil, subprocess, zipfile

BASE_MAIN='32c317ade5cef4a5931e7a31eb02db4e2f0751b3'
MAIN16_SHA='6d5e154f63dfb77d15e0541a87a653863e0ae9f95df59ffa9bb4b413f97766ad'
MAIN17_SHA='5ff7990564287bc409626d8835e27679fb8de434868443313be42fdc0d9cce3b'
R6_SHA='fb2bd974ee795bb697a0e5b534e03477be77b655e60353d82064b1e751bdc686'
R7_SHA='b7d1a4bc7707533400402fe42e60d724f88656c2477d4d4a5c0f47be60f47977'
R7_SIZE=154926
PAYLOAD17_SHA='0f7fe384630e027466aa734ac669b410774b4569db231982212b7fa565b691a0'
AGENT_SHA='2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278'
BOOTSTRAP_SHA='d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6'
PATCH_B64_SHA='55d886166dcdaff5482f2079004446fae6ae98c27f875b1acb1186416d22741c'
PATCH_B64_SIZE=2040
PATCH_RAW_SHA='490d10ce8c9aa015849a4743a568270297c27ec255f19880c50ea452ebbab254'

def sha(b): return hashlib.sha256(b).hexdigest()
def git_bytes(ref,path): return subprocess.check_output(['git','show',f'{ref}:{path}'])
def load_manifest(ref=None):
    raw=Path('manifest.json').read_bytes() if ref is None else git_bytes(ref,'manifest.json')
    return json.loads(raw.decode('utf-8-sig'))

def reconstruct_full(manifest, edge_from, edge_to, path):
    edge=next(e for e in manifest['updates'] if e['from_version']==edge_from and e['to_version']==edge_to)
    p=next(x for x in edge['patches'] if x['path']==path)
    source=manifest['source_commit']; parts=[]
    for i,c in enumerate(p['chunks']):
        q=c['path'].replace('\\','/')
        assert q.endswith(f'/chunk-{i:03}.txt'),q
        data=git_bytes(source,q)
        assert len(data)==int(c['size']) and sha(data)==c['sha256'],q
        parts.append(data)
    enc=b''.join(parts)
    assert len(enc)==int(p['encoded_size']) and sha(enc)==p['encoded_sha256']
    comp=base64.b64decode(enc,validate=True)
    assert len(comp)==int(p['compressed_size']) and sha(comp)==p['compressed_sha256']
    raw=gzip.decompress(comp)
    return p,raw

def reconstruct_main_0615(manifest):
    enc=b''.join(Path(f'packages/v0.6.11/chunks/chunk-{i:03}.txt').read_bytes() for i in range(8))
    with zipfile.ZipFile(BytesIO(base64.b64decode(b''.join(enc.split()),validate=True))) as z:
        cur=z.read('bin/spotify-control.ps1')
    assert sha(cur)=='045ed3fa898453ce6563a057a31412d254f5958b75286589e8d5cc95c6782a39'
    ver='0.6.11'
    for to in ('0.6.13','0.6.14','0.6.15'):
        edge=next(e for e in manifest['updates'] if e['from_version']==ver and e['to_version']==to)
        p=next(x for x in edge['patches'] if x['path']=='bin/spotify-control.ps1')
        parts=[]
        for c in p['chunks']:
            data=git_bytes(manifest['source_commit'],c['path'])
            assert len(data)==int(c['size']) and sha(data)==c['sha256']
            parts.append(data)
        encoded=b''.join(parts); assert len(encoded)==int(p['encoded_size']) and sha(encoded)==p['encoded_sha256']
        comp=base64.b64decode(encoded,validate=True); assert len(comp)==int(p['compressed_size']) and sha(comp)==p['compressed_sha256']
        raw=gzip.decompress(comp); assert sha(raw)==p['json_sha256']
        doc=json.loads(raw.decode('ascii'))
        assert sha(cur)==p['from_sha256']
        lines=cur.decode('utf-8-sig').splitlines(keepends=True)
        for op in sorted(doc['operations'],key=lambda x:int(x['start_line']),reverse=True):
            s=int(op['start_line']); d=int(op['delete_count']); lines[s:s+d]=str(op.get('insert','')).splitlines(keepends=True)
        cur=b'\xef\xbb\xbf'+''.join(lines).encode('utf-8')
        assert sha(cur)==p['to_sha256']; ver=to
    return cur

def reconstruct_main16(manifest):
    main15=reconstruct_main_0615(manifest)
    edge=next(e for e in manifest['updates'] if e['from_version']=='0.6.15' and e['to_version']=='0.6.16')
    p=next(x for x in edge['patches'] if x['path']=='bin/spotify-control.ps1')
    parts=[]
    for c in p['chunks']:
        data=git_bytes(manifest['source_commit'],c['path']); assert len(data)==c['size'] and sha(data)==c['sha256']; parts.append(data)
    enc=b''.join(parts); assert sha(enc)==p['encoded_sha256'] and len(enc)==p['encoded_size']
    comp=base64.b64decode(enc,validate=True); assert sha(comp)==p['compressed_sha256'] and len(comp)==p['compressed_size']
    raw=gzip.decompress(comp); assert sha(raw)==p['json_sha256']; doc=json.loads(raw.decode('ascii'))
    lines=main15.decode('utf-8-sig').splitlines(keepends=True)
    for op in sorted(doc['operations'],key=lambda x:int(x['start_line']),reverse=True):
        s=int(op['start_line']);d=int(op['delete_count']);lines[s:s+d]=str(op.get('insert','')).splitlines(keepends=True)
    out=b'\xef\xbb\xbf'+''.join(lines).encode('utf-8')
    assert sha(out)==MAIN16_SHA
    return out

def derive_r7(manifest):
    _,r6=reconstruct_full(manifest,'0.6.15','0.6.16','bin/addon-manager.ps1')
    assert sha(r6)==R6_SHA and len(r6)==152481
    enc=Path('validation/v0.6.17/r6-to-r7.patch.json.gz.b64').read_bytes()
    assert len(enc)==PATCH_B64_SIZE and sha(enc)==PATCH_B64_SHA
    raw=gzip.decompress(base64.b64decode(enc,validate=True)); assert sha(raw)==PATCH_RAW_SHA
    doc=json.loads(raw.decode('ascii')); assert doc['from_sha256']==R6_SHA and doc['to_sha256']==R7_SHA
    lines=r6.decode('utf-8-sig').splitlines(keepends=True)
    for op in sorted(doc['operations'],key=lambda x:int(x['start_line']),reverse=True):
        s=int(op['start_line']);d=int(op['delete_count']);lines[s:s+d]=str(op.get('insert','')).splitlines(keepends=True)
    r7=b'\xef\xbb\xbf'+''.join(lines).encode('utf-8')
    assert len(r7)==R7_SIZE and sha(r7)==R7_SHA
    return r6,r7

def derive_main17(main16):
    doc={'kind':'ascii-line-patch','from_version':'0.6.16','to_version':'0.6.17','from_sha256':MAIN16_SHA,'to_sha256':MAIN17_SHA,'operations':[
        {'start_line':0,'delete_count':1,'insert':'# Spotify Control v0.6.17 ivLyrics Proven-or-Monitor Bootstrap\n'},
        {'start_line':12,'delete_count':1,'insert':'$ScriptVersion = "0.6.17"\n'}]}
    lines=main16.decode('utf-8-sig').splitlines(keepends=True)
    for op in sorted(doc['operations'],key=lambda x:int(x['start_line']),reverse=True):
        s=int(op['start_line']);d=int(op['delete_count']);lines[s:s+d]=op['insert'].splitlines(keepends=True)
    out=b'\xef\xbb\xbf'+''.join(lines).encode('utf-8')
    assert len(out)==266318 and sha(out)==MAIN17_SHA
    return doc,out

def write_chunks(root,data):
    root.mkdir(parents=True,exist_ok=True); rows=[]
    for off in range(0,len(data),4096):
        part=data[off:off+4096]; name=f'chunk-{off//4096:03}.txt'; (root/name).write_bytes(part)
        rows.append({'path':str((root/name)).replace('\\','/').removeprefix('publication-v0.6.17/'),'sha256':sha(part),'size':len(part)})
    return rows

def prepare(manifest):
    base=load_manifest(BASE_MAIN)
    assert manifest==base and manifest['latest_version']=='0.6.16'
    main16=reconstruct_main16(manifest); r6,r7=derive_r7(manifest); doc,main17=derive_main17(main16)
    out=Path('publication-v0.6.17'); shutil.rmtree(out,ignore_errors=True); out.mkdir()
    (out/'candidate-main-v0.6.17.ps1').write_bytes(main17); (out/'candidate-addon-v0.6.5-r7.ps1').write_bytes(r7)
    main_json=json.dumps(doc,separators=(',',':'),ensure_ascii=True).encode('ascii'); assert len(main_json)==434 and sha(main_json)=='8821585f6ec028f8038b93ce250a4db7fe1e24d23c6a9ead24cb49ca5822f8b1'
    main_gz=gzip.compress(main_json,compresslevel=9,mtime=0); main_b64=base64.b64encode(main_gz)
    assert len(main_b64)==408 and sha(main_b64)=='de9de4f5cf0c885faf17c5fd519354a7f17e1719daf4822535133f2ea7f2781c'
    addon_gz=gzip.compress(r7,compresslevel=9,mtime=0); addon_b64=base64.b64encode(addon_gz)
    assert len(addon_b64)==41924 and sha(addon_b64)=='a917b9df8d5ac1a26308319f705f9ba6e1a12413561f28525fcc4a77810aafbf'
    mc=write_chunks(out/'packages/v0.6.17/main-v0616-to-v0617',main_b64)
    ac=write_chunks(out/'packages/v0.6.17/addon-v065r6-to-v065r7',addon_b64)
    mp={'path':'bin/spotify-control.ps1','from_sha256':MAIN16_SHA,'to_sha256':MAIN17_SHA,'encoding':'gzip-base64-chunks','encoded_sha256':sha(main_b64),'encoded_size':len(main_b64),'compressed_sha256':sha(main_gz),'compressed_size':len(main_gz),'json_sha256':sha(main_json),'json_size':len(main_json),'chunks':mc}
    ap={'path':'bin/addon-manager.ps1','from_sha256':R6_SHA,'to_sha256':R7_SHA,'encoding':'gzip-base64-full-file','encoded_sha256':sha(addon_b64),'encoded_size':len(addon_b64),'compressed_sha256':sha(addon_gz),'compressed_size':len(addon_gz),'target_size':len(r7),'chunks':ac}
    latest=[{'path':'bin/spotify-control.ps1','sha256':MAIN17_SHA,'size':len(main17)},{'path':'bin/addon-manager.ps1','sha256':R7_SHA,'size':len(r7)},{'path':'bin/spotify-control-agent.vbs','sha256':AGENT_SHA,'size':4855}]
    rows=[f"{x['path']}|{x['size']}|{x['sha256']}" for x in latest]; assert sha(('\n'.join(sorted(rows))+'\n').encode())==PAYLOAD17_SHA
    nxt=json.loads(json.dumps(manifest)); nxt['latest_version']='0.6.17';nxt['source_commit']='__SOURCE_COMMIT__';nxt['payload_set_sha256']=PAYLOAD17_SHA;nxt['latest_files']=latest;nxt['updates']=list(manifest['updates'])+[{'from_version':'0.6.16','to_version':'0.6.17','patches':[mp,ap]}]
    (out/'manifest-template.json').write_text(json.dumps(nxt,separators=(',',':')),encoding='utf-8',newline='\n')
    print('PREPARE_OK',MAIN17_SHA,R7_SHA,PAYLOAD17_SHA)

def final_validate(manifest):
    base=load_manifest(BASE_MAIN)
    assert manifest['latest_version']=='0.6.17' and manifest['payload_set_sha256']==PAYLOAD17_SHA
    assert manifest['bootstrap']['sha256']==BOOTSTRAP_SHA and manifest['bootstrap']['size']==42963
    assert manifest['updates'][:-1]==base['updates'], 'Historical edges changed'
    edge=manifest['updates'][-1]; assert (edge['from_version'],edge['to_version'])==('0.6.16','0.6.17')
    froms=[e['from_version'] for e in manifest['updates']]; assert len(froms)==len(set(froms))
    source=manifest['source_commit']; subprocess.check_call(['git','merge-base','--is-ancestor',source,'HEAD'])
    main16=reconstruct_main16(base)
    out=Path('publication-v0.6.17'); shutil.rmtree(out,ignore_errors=True); out.mkdir()
    patches={p['path']:p for p in edge['patches']}; assert set(patches)=={'bin/spotify-control.ps1','bin/addon-manager.ps1'}
    for path,target,size in [('bin/spotify-control.ps1',MAIN17_SHA,266318),('bin/addon-manager.ps1',R7_SHA,R7_SIZE)]:
        p=patches[path]; parts=[]
        for i,c in enumerate(p['chunks']):
            q=c['path'].replace('\\','/'); assert q.endswith(f'/chunk-{i:03}.txt') and q.startswith('packages/v0.6.17/')
            data=git_bytes(source,q); assert len(data)==int(c['size']) and sha(data)==c['sha256']; parts.append(data)
        enc=b''.join(parts); assert len(enc)==int(p['encoded_size']) and sha(enc)==p['encoded_sha256']
        comp=base64.b64decode(enc,validate=True); assert len(comp)==int(p['compressed_size']) and sha(comp)==p['compressed_sha256']; raw=gzip.decompress(comp)
        if path.endswith('spotify-control.ps1'):
            assert sha(raw)==p['json_sha256']; doc=json.loads(raw.decode('ascii')); lines=main16.decode('utf-8-sig').splitlines(keepends=True)
            for op in sorted(doc['operations'],key=lambda x:int(x['start_line']),reverse=True):
                s=int(op['start_line']);d=int(op['delete_count']);lines[s:s+d]=str(op.get('insert','')).splitlines(keepends=True)
            payload=b'\xef\xbb\xbf'+''.join(lines).encode('utf-8')
        else: payload=raw
        assert len(payload)==size and sha(payload)==target and p['to_sha256']==target
        (out/('candidate-main-v0.6.17.ps1' if path.endswith('spotify-control.ps1') else 'candidate-addon-v0.6.5-r7.ps1')).write_bytes(payload)
    latest={x['path']:(int(x['size']),x['sha256']) for x in manifest['latest_files']}
    assert latest=={'bin/spotify-control.ps1':(266318,MAIN17_SHA),'bin/addon-manager.ps1':(R7_SIZE,R7_SHA),'bin/spotify-control-agent.vbs':(4855,AGENT_SHA)}
    rows=[f'{p}|{s}|{h}' for p,(s,h) in latest.items()]; assert sha(('\n'.join(sorted(rows))+'\n').encode())==PAYLOAD17_SHA
    txt=(out/'candidate-addon-v0.6.5-r7.ps1').read_text(encoding='utf-8-sig')
    assert '$Version = "0.6.5-r7"' in txt
    assert 'monitor-update-available-unproven' in txt and 'monitor-unproven-baseline' in txt
    assert 'ivLyrics unproven-current fallback self-test passed' in txt
    print('FINAL_VALIDATE_OK',source,MAIN17_SHA,R7_SHA,PAYLOAD17_SHA)

m=load_manifest()
if m['latest_version']=='0.6.16': prepare(m)
elif m['latest_version']=='0.6.17': final_validate(m)
else: raise SystemExit('Unexpected stable latest_version '+str(m.get('latest_version')))
