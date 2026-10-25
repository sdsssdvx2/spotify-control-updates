from pathlib import Path
import base64,gzip,hashlib,json

ROOT=Path(__file__).resolve().parents[2]
manifest=json.loads((ROOT/'manifest.json').read_text(encoding='utf-8-sig'))

def cat(paths): return b''.join((ROOT/p).read_bytes() for p in paths)

# Inspect the retained v0.6.11 full seed transport.
seed_paths=sorted(str(p.relative_to(ROOT)).replace('\\','/') for p in (ROOT/'packages/v0.6.11/chunks-v2').glob('chunk-*.txt'))
seed_enc=cat(seed_paths)
print('SEED_ENCODED',len(seed_enc),hashlib.sha256(seed_enc).hexdigest(),seed_paths)
try:
    seed_comp=base64.b64decode(seed_enc,validate=True)
    print('SEED_COMPRESSED',len(seed_comp),hashlib.sha256(seed_comp).hexdigest(),seed_comp[:4].hex())
    seed_raw=gzip.decompress(seed_comp)
    print('SEED_RAW',len(seed_raw),hashlib.sha256(seed_raw).hexdigest(),repr(seed_raw[:120]))
except Exception as e:
    print('SEED_DECODE_ERROR',repr(e))
    seed_raw=None

# Decode the exact current v0.6.17->v0.6.18 main patch payload to document its format.
edge=next(e for e in manifest['updates'] if e['from_version']=='0.6.17' and e['to_version']=='0.6.18')
patch=next(p for p in edge['patches'] if p['path']=='bin/spotify-control.ps1')
enc=cat([c['path'] for c in patch['chunks']])
assert len(enc)==patch['encoded_size'] and hashlib.sha256(enc).hexdigest()==patch['encoded_sha256']
comp=base64.b64decode(enc,validate=True)
assert len(comp)==patch['compressed_size'] and hashlib.sha256(comp).hexdigest()==patch['compressed_sha256']
raw=gzip.decompress(comp)
print('V0618_PATCH_RAW',len(raw),hashlib.sha256(raw).hexdigest(),repr(raw[:800]))
obj=json.loads(raw)
print('V0618_PATCH_KEYS',sorted(obj.keys()))
print('V0618_PATCH_JSON',json.dumps(obj,ensure_ascii=False)[:6000])
