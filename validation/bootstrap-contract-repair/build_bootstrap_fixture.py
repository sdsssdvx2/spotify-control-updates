from pathlib import Path
from io import BytesIO
import base64,gzip,hashlib,json,shutil,subprocess,zipfile

BOOTSTRAP_SHA='d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6'
MAIN11_SHA='045ed3fa898453ce6563a057a31412d254f5958b75286589e8d5cc95c6782a39'
MAIN15_SHA='4faef1e70be20efb551f595c02dad171a44abbe8a53af9a0576dc54fd0e2004f'
ADDON15_SHA='56185d3b23c4b0df455673ad3f601d67c7980b7428f1d15b3e0465d1a7859022'
AGENT_SHA='2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278'

def sha(b): return hashlib.sha256(b).hexdigest()
def git_bytes(ref,path): return subprocess.check_output(['git','show',f'{ref}:{path}'])
def load_manifest(): return json.loads(Path('manifest.json').read_text(encoding='utf-8-sig'))

def decoded_payload(m,a,b,path):
    e=next(x for x in m['updates'] if x['from_version']==a and x['to_version']==b)
    p=next(x for x in e['patches'] if x['path']==path)
    parts=[]
    for i,c in enumerate(p['chunks']):
        q=c['path'].replace('\\','/'); assert q.endswith(f'/chunk-{i:03}.txt'),q
        data=git_bytes(m['source_commit'],q); assert len(data)==int(c['size']) and sha(data)==c['sha256']; parts.append(data)
    enc=b''.join(parts); assert len(enc)==int(p['encoded_size']) and sha(enc)==p['encoded_sha256']
    comp=base64.b64decode(enc,validate=True); assert len(comp)==int(p['compressed_size']) and sha(comp)==p['compressed_sha256']
    raw=gzip.decompress(comp)
    return p,raw

def apply_main(cur,m,a,b):
    p,raw=decoded_payload(m,a,b,'bin/spotify-control.ps1')
    assert len(raw)==int(p['json_size']) and sha(raw)==p['json_sha256']
    doc=json.loads(raw.decode('ascii'))
    assert doc.get('schema')==1 and doc.get('kind')=='ascii-line-patch'
    assert doc.get('bom')=='utf8-bom' and doc.get('line_ending')=='lf'
    assert sha(cur)==p['from_sha256']==doc['from_sha256']
    lines=cur.decode('utf-8-sig').splitlines(keepends=True)
    for op in sorted(doc['operations'],key=lambda x:int(x['start_line']),reverse=True):
        s=int(op['start_line']);d=int(op['delete_count']);lines[s:s+d]=str(op.get('insert','')).splitlines(keepends=True)
    out=b'\xef\xbb\xbf'+''.join(lines).encode('utf-8')
    assert sha(out)==p['to_sha256']==doc['to_sha256']
    return out

m=load_manifest()
# Rebuild the original full v0.6.11 bundle. Some obsolete archive members have historical CRC defects,
# so do not trust a whole-archive test; identify the three required immutable files by exact SHA-256.
def scan_bundle(folder):
    enc=b''.join(p.read_bytes() for p in sorted(Path(folder).glob('chunk-*.txt')))
    zip_bytes=base64.b64decode(b''.join(enc.split()),validate=True)
    found={}; unreadable=[]
    with zipfile.ZipFile(BytesIO(zip_bytes)) as z:
        for name in z.namelist():
            if name.endswith('/'): continue
            try: data=z.read(name)
            except Exception as exc:
                unreadable.append((name,type(exc).__name__))
                continue
            h=sha(data)
            if h in (BOOTSTRAP_SHA,MAIN11_SHA,AGENT_SHA): found.setdefault(h,[]).append((name,data))
    return found,unreadable

by_hash={}; unreadable=[]
for folder in ('packages/v0.6.11/chunks','packages/v0.6.11/chunks-v2'):
    f,bad=scan_bundle(folder); unreadable += [(folder,)+x for x in bad]
    for h,rows in f.items(): by_hash.setdefault(h,[]).extend(rows)
for required in (BOOTSTRAP_SHA,MAIN11_SHA,AGENT_SHA):
    # Deduplicate identical path/data copies across historical archive variants.
    uniq={ (n,sha(d)):(n,d) for n,d in by_hash.get(required,[]) }
    assert len(uniq)==1,(required,list(uniq),unreadable[:10])
    by_hash[required]=list(uniq.values())
bootstrap_name,bootstrap=by_hash[BOOTSTRAP_SHA][0]
_,main=by_hash[MAIN11_SHA][0]
_,agent=by_hash[AGENT_SHA][0]
assert len(bootstrap)==42963

# Reconstruct the exact user's current v0.6.15 main via the historical supported patch chain.
for a,b in [('0.6.11','0.6.13'),('0.6.13','0.6.14'),('0.6.14','0.6.15')]: main=apply_main(main,m,a,b)
assert sha(main)==MAIN15_SHA
# r5 is a full-file transport, so no earlier addon fixture is needed.
p,addon=decoded_payload(m,'0.6.14','0.6.15','bin/addon-manager.ps1')
assert p['encoding']=='gzip-base64-full-file' and len(addon)==int(p['target_size']) and sha(addon)==ADDON15_SHA

root=Path('ci-bootstrap-fixture/LocalAppData/SpotifyControl'); shutil.rmtree(root.parent.parent,ignore_errors=True)
(root/'bin').mkdir(parents=True)
(root/'bin/spotify-control.ps1').write_bytes(main)
(root/'bin/addon-manager.ps1').write_bytes(addon)
(root/'bin/spotify-control-agent.vbs').write_bytes(agent)
(root/'bin/spotify-control-bootstrap.ps1').write_bytes(bootstrap)
print('BOOTSTRAP_FIXTURE_OK',bootstrap_name,len(bootstrap),sha(bootstrap),sha(main),sha(addon),sha(agent),'unreadable_old_members',len(unreadable))
