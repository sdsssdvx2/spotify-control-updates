from pathlib import Path
import base64,gzip,hashlib,json,struct,zlib

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

def extract_local_zip_stream(blob):
    assert blob[:4]==b'PK\x03\x04'
    sig,ver,flags,method,mtime,mdate,crc,csize,usize,nlen,xlen=struct.unpack('<4s5H3I2H',blob[:30])
    name=blob[30:30+nlen].decode('utf-8','replace')
    start=30+nlen+xlen
    print('LOCAL_ZIP_HEADER',dict(ver=ver,flags=flags,method=method,crc=hex(crc),csize=csize,usize=usize,name=name,xlen=xlen,total=len(blob),tail=blob[-32:].hex()))
    if flags & 0x08:
        raise RuntimeError('data-descriptor local ZIP stream requires fallback metadata')
    comp=blob[start:start+csize]
    assert len(comp)==csize
    if method==0: raw=comp
    elif method==8: raw=zlib.decompress(comp,-15)
    else: raise RuntimeError(f'unsupported ZIP method {method}')
    assert len(raw)==usize
    return name,raw

seed_paths=sorted(str(p.relative_to(ROOT)).replace('\\','/') for p in (ROOT/'packages/v0.6.11/chunks-v2').glob('chunk-*.txt'))
seed_blob=base64.b64decode(cat(seed_paths),validate=True)
print('SEED_BLOB',len(seed_blob),sha(seed_blob),seed_blob[:16].hex(),seed_blob[-16:].hex())
name,raw=extract_local_zip_stream(seed_blob)
print('SEED_MAIN',name,len(raw),sha(raw),repr(raw[:100]))

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
