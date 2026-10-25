from pathlib import Path
import hashlib, io, shutil, zipfile

ROOT=Path('validation/performance-phase2-v0.4.0')
SRC=ROOT/'SpotifyControl-Track-Transition-Single-Hook-Isolation-v0.4.0.zip'
OUT=Path('SpotifyControl-Track-Transition-Single-Hook-Isolation-v0.4.0.zip')
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
raw=SRC.read_bytes()
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
        assert not [i for i,x in enumerate(data) if x==13 and (i+1>=len(data) or data[i+1]!=10)],name
        assert not [i for i,x in enumerate(data) if x==9],name
OUT.write_bytes(raw)
outdir=Path('phase2-v040');shutil.rmtree(outdir,ignore_errors=True);outdir.mkdir()
with zipfile.ZipFile(io.BytesIO(raw)) as z:z.extractall(outdir)
print('PHASE2_V040_COMMITTED_PACKAGE_PASS',len(raw),sha(raw))
print('PHASE2_V040_SCRIPT',ENTRIES['track-transition-isolation.ps1'][0],ENTRIES['track-transition-isolation.ps1'][1])
