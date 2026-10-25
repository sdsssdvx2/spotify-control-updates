from pathlib import Path
import base64, hashlib, io, shutil, zipfile

ROOT=Path('validation/performance-phase2-v0.4.0')
PAYLOAD=ROOT/'payload'
PARTS=[
 ('chunk-000.txt',4096,'93e4469fb154d4544912c94c40031f69655110a610ef77dd928ca2e1d7f00d28'),
 ('chunk-001.txt',4096,'0a413eeaadd05fce3391b8a59436792aceaa82ad35f01acd09241df60c50a003'),
 ('chunk-002.txt',4096,'8c5172350afa1bbc75ab157e281d6932b2750ac65dafd1dd70482eba7131fdde'),
 ('chunk-003.txt',4096,'fbd4b2b20576c021c0ef675990b642f11d37b0bc24fbb980ab3ffba13272e9a8'),
 ('chunk-004.txt',4096,'23dfb753b7fe3b337290000b2b5ad0f58007121eb5587108c5ebf01dd13b304e'),
 ('chunk-005.txt',4096,'91bff17d99b0735005f647fbb953a7de5969ab2ac3fe16f6d01d3f08216256d3'),
 ('chunk-006.txt',1776,'4062370d81e8b8b5e97cd6bc27ec7d1fdc5d86bac13ca508a2e34d888becd15d'),
]
ENCODED_SIZE=26352
ENCODED_SHA='7174dcd502eaa2ecc5f86a40c0fb5e2ee6d3fa6f1913d3b276cbb975c8b0f5d5'
FINAL_SIZE=19764
FINAL_SHA='ac014e2f5621d8460d307a5df689ce11f9378ba9504b894c5ed54e29b87b3a1d'
ENTRIES={
 'README.md':(4365,'985fdcaffb4a9c48ddae18ea7dc5324d20e6f8840398108f5d117df5d2808e67'),
 'RUN_TRACK_TRANSITION_ISOLATION.cmd':(936,'def7f00e8ad03e584fdf24a2ac61f9be9795d463153f277c92a7147f8e68dd1d'),
 'SELFTEST.cmd':(201,'150b228128e92926be6aaf622cbee87b2f18faf3a5d2e7f22710d817d0e5be37'),
 'SHA256SUMS.txt':(353,'10395b6ffe398f2d177992e4d3c5e1652b12bb29270c9e0cc0179c6a25cfb512'),
 'track-transition-isolation.ps1':(59270,'ce7c4f56e4d206653cbe91969bb43cb81ebb2be074e15530b50a268821877548'),
}

def sha(b): return hashlib.sha256(b).hexdigest()

parts=[]
for i,(name,size,digest) in enumerate(PARTS):
    assert name==f'chunk-{i:03d}.txt',name
    data=(PAYLOAD/name).read_bytes()
    assert len(data)==size,(name,len(data),size)
    assert sha(data)==digest,(name,sha(data),digest)
    data.decode('ascii')
    parts.append(data)
encoded=b''.join(parts)
assert len(encoded)==ENCODED_SIZE,len(encoded)
assert sha(encoded)==ENCODED_SHA,sha(encoded)
raw=base64.b64decode(encoded,validate=True)
assert len(raw)==FINAL_SIZE,len(raw)
assert sha(raw)==FINAL_SHA,sha(raw)

with zipfile.ZipFile(io.BytesIO(raw)) as z:
    assert z.testzip() is None
    assert sorted(z.namelist())==sorted(ENTRIES),z.namelist()
    for name,(size,digest) in ENTRIES.items():
        data=z.read(name)
        assert len(data)==size,(name,len(data),size)
        assert sha(data)==digest,(name,sha(data),digest)
    lines=z.read('SHA256SUMS.txt').decode('ascii').splitlines()
    assert len(lines)==4,lines
    for line in lines:
        digest,name=line.split('  ',1)
        assert name!='SHA256SUMS.txt'
        assert sha(z.read(name))==digest,(name,digest,sha(z.read(name)))
    for name in z.namelist():
        if not name.lower().endswith(('.md','.cmd','.ps1','.txt')): continue
        data=z.read(name)
        bad_cr=[i for i,x in enumerate(data) if x==13 and (i+1>=len(data) or data[i+1]!=10)]
        bad_tab=[i for i,x in enumerate(data) if x==9]
        assert not bad_cr and not bad_tab,(name,bad_cr,bad_tab)

outzip=Path('SpotifyControl-Track-Transition-Single-Hook-Isolation-v0.4.0.zip')
outzip.write_bytes(raw)
outdir=Path('phase2-v040');shutil.rmtree(outdir,ignore_errors=True);outdir.mkdir()
with zipfile.ZipFile(io.BytesIO(raw)) as z:z.extractall(outdir)
print('PHASE2_V040_TRANSPORT_PASS',len(PARTS),len(encoded),sha(encoded))
print('PHASE2_V040_FINAL_PACKAGE_PASS',len(raw),sha(raw))
print('PHASE2_V040_SCRIPT',ENTRIES['track-transition-isolation.ps1'][0],ENTRIES['track-transition-isolation.ps1'][1])
