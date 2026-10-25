from pathlib import Path
import base64,gzip,hashlib,json,re

ROOT=Path(__file__).resolve().parents[2]
manifest=json.loads((ROOT/'manifest.json').read_text(encoding='utf-8-sig'))
latest={x['path']:x for x in manifest['latest_files']}
target=latest['bin/addon-manager.ps1']
edge=None
for e in manifest['updates']:
    for p in e['patches']:
        if p['path']=='bin/addon-manager.ps1' and p['to_sha256']==target['sha256'] and p['encoding']=='gzip-base64-full-file':
            edge=p
assert edge, 'latest addon-manager full-file transport not found'
enc=b''.join((ROOT/c['path']).read_bytes() for c in edge['chunks'])
assert len(enc)==edge['encoded_size'] and hashlib.sha256(enc).hexdigest()==edge['encoded_sha256']
comp=base64.b64decode(enc,validate=True)
assert len(comp)==edge['compressed_size'] and hashlib.sha256(comp).hexdigest()==edge['compressed_sha256']
raw=gzip.decompress(comp)
assert len(raw)==target['size']==edge['target_size']
assert hashlib.sha256(raw).hexdigest()==target['sha256']
text=raw.decode('utf-8-sig')
lines=text.splitlines()
print('ADDON_RECONSTRUCT_PASS',len(raw),target['sha256'],len(lines))

def emit(lo,hi,title):
    print(f'=== {title} {lo}-{hi} ===')
    for n in range(lo,min(hi,len(lines))+1):
        s=lines[n-1]
        if len(s)>900: s=s[:900]+'...[truncated]'
        print(f'{n:05d}: {s}')

emit(1760,1895,'UPDATE_AUTO_APPS')
emit(1935,2025,'COMMIT_AND_PREFLIGHT')
emit(2538,2615,'MAIN_SWITCH')
