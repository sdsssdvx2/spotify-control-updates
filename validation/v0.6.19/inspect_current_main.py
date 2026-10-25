from pathlib import Path
import base64,gzip,hashlib,json,zipfile,io

ROOT=Path(__file__).resolve().parents[2]
manifest=json.loads((ROOT/'manifest.json').read_text(encoding='utf-8-sig'))

def cat(paths): return b''.join((ROOT/p).read_bytes() for p in paths)
def sha(b): return hashlib.sha256(b).hexdigest()

def apply_line_patch(raw, patch):
    assert patch['kind']=='ascii-line-patch'
    bom=b'\xef\xbb\xbf' if patch.get('bom')=='utf8-bom' else b''
    if bom:
        assert raw.startswith(bom)
        body=raw[len(bom):]
    else:
        body=raw
    text=body.decode('ascii')
    lines=text.splitlines(keepends=True)
    for op in sorted(patch['operations'],key=lambda x:int(x['start_line']),reverse=True):
        start=int(op['start_line']); delete=int(op['delete_count']); ins=op.get('insert','')
        lines[start:start+delete]=ins.splitlines(keepends=True)
    return bom+''.join(lines).encode('ascii')

seed_paths=sorted(str(p.relative_to(ROOT)).replace('\\','/') for p in (ROOT/'packages/v0.6.11/chunks-v2').glob('chunk-*.txt'))
seed_zip=base64.b64decode(cat(seed_paths),validate=True)
print('SEED_ZIP',len(seed_zip),sha(seed_zip),seed_zip[:4].hex())
with zipfile.ZipFile(io.BytesIO(seed_zip),'r') as z:
    print('SEED_ENTRIES',z.namelist())
    candidates=[n for n in z.namelist() if n.lower().endswith('spotify-control.ps1')]
    assert len(candidates)==1,candidates
    raw=z.read(candidates[0])
print('SEED_MAIN',len(raw),sha(raw),repr(raw[:100]))

current='0.6.11'
while current!=manifest['latest_version']:
    edge=next(e for e in manifest['updates'] if e['from_version']==current)
    patches=[p for p in edge['patches'] if p['path']=='bin/spotify-control.ps1']
    if patches:
        p=patches[0]
        assert sha(raw)==p['from_sha256'],(current,sha(raw),p['from_sha256'])
        enc=cat([c['path'] for c in p['chunks']])
        assert len(enc)==p['encoded_size'] and sha(enc)==p['encoded_sha256']
        comp=base64.b64decode(enc,validate=True)
        assert len(comp)==p['compressed_size'] and sha(comp)==p['compressed_sha256']
        patch=json.loads(gzip.decompress(comp))
        raw=apply_line_patch(raw,patch)
        assert len(raw)==p['target_size'] and sha(raw)==p['to_sha256'],(edge['to_version'],len(raw),sha(raw),p['target_size'],p['to_sha256'])
    current=edge['to_version']
    print('APPLIED_MAIN',current,len(raw),sha(raw))
latest=next(x for x in manifest['latest_files'] if x['path']=='bin/spotify-control.ps1')
assert len(raw)==latest['size'] and sha(raw)==latest['sha256']
print('CURRENT_MAIN_PASS',current,len(raw),sha(raw))
text=raw.decode('utf-8-sig')
for i,line in enumerate(text.splitlines(),1):
    if i<=25 or 'addon-manager.ps1' in line or 'CommitLast' in line or 'RollbackLast' in line or 'DirectExtensionPreflight' in line:
        print(f'MAIN {i:05d}: {line[:900]}')
