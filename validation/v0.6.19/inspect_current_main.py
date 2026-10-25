from pathlib import Path
import base64,gzip,hashlib,json,struct,zlib,binascii

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

def parse_extra(extra, csize32, usize32):
    csize=csize32; usize=usize32
    p=0
    while p+4<=len(extra):
        tag,size=struct.unpack('<HH',extra[p:p+4]); data=extra[p+4:p+4+size]; p+=4+size
        if tag!=0x0001: continue
        q=0
        if usize32==0xffffffff:
            assert q+8<=len(data); usize=struct.unpack('<Q',data[q:q+8])[0]; q+=8
        if csize32==0xffffffff:
            assert q+8<=len(data); csize=struct.unpack('<Q',data[q:q+8])[0]; q+=8
        break
    return csize,usize

def iter_local_zip_entries(blob):
    off=0
    index=0
    while off+4<=len(blob) and blob[off:off+4]==b'PK\x03\x04':
        assert off+30<=len(blob)
        sig,ver,flags,method,mtime,mdate,crc,csize32,usize32,nlen,xlen=struct.unpack('<4s5H3I2H',blob[off:off+30])
        assert not (flags & 0x08),'data descriptor unsupported in retained seed'
        name_start=off+30; extra_start=name_start+nlen; data_start=extra_start+xlen
        assert data_start<=len(blob)
        name=blob[name_start:name_start+nlen].decode('utf-8','replace')
        extra=blob[extra_start:extra_start+xlen]
        csize,usize=parse_extra(extra,csize32,usize32)
        assert csize is not None and usize is not None
        assert data_start+csize<=len(blob),(index,name,off,data_start,csize,len(blob),extra.hex())
        comp=blob[data_start:data_start+csize]
        if method==0: raw=comp
        elif method==8: raw=zlib.decompress(comp,-15)
        else: raise RuntimeError(f'unsupported ZIP method {method} for {name}')
        assert len(raw)==usize,(name,len(raw),usize)
        if usize or crc:
            assert (binascii.crc32(raw)&0xffffffff)==crc,(name,hex(binascii.crc32(raw)&0xffffffff),hex(crc))
        meta=dict(index=index,offset=off,version=ver,flags=flags,method=method,csize=csize,usize=usize,csize32=csize32,usize32=usize32,xlen=xlen)
        yield name,raw,meta
        off=data_start+csize
        index+=1
    print('LOCAL_ZIP_STREAM_END',off,len(blob),blob[off:off+32].hex())

seed_paths=sorted(str(p.relative_to(ROOT)).replace('\\','/') for p in (ROOT/'packages/v0.6.11/chunks-v2').glob('chunk-*.txt'))
seed_blob=base64.b64decode(cat(seed_paths),validate=True)
print('SEED_BLOB',len(seed_blob),sha(seed_blob),seed_blob[:16].hex(),seed_blob[-16:].hex())
entries=list(iter_local_zip_entries(seed_blob))
print('SEED_ENTRIES',[(n,m) for n,_,m in entries])
candidates=[(n,b) for n,b,_ in entries if n.lower().endswith('spotify-control.ps1')]
assert len(candidates)==1,[n for n,_,_ in entries]
name,raw=candidates[0]
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
