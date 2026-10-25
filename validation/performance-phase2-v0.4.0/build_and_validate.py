from pathlib import Path
import hashlib, io, shutil, zipfile

ROOT=Path('validation/performance-phase2-v0.4.0')
SEED=ROOT/'SpotifyControl-Track-Transition-Single-Hook-Isolation-v0.4.0.zip'
OUT=Path('SpotifyControl-Track-Transition-Single-Hook-Isolation-v0.4.0.zip')
SEED_SIZE=19764
SEED_SHA='ac014e2f5621d8460d307a5df689ce11f9378ba9504b894c5ed54e29b87b3a1d'
FINAL_SIZE=65773
FINAL_SHA='da5b43521883973d783913e571476e342ae64d616c67e7f6eb592f3d013d1549'
SCRIPT_SIZE=59314
SCRIPT_SHA='e1b11adcdcddb1bd8dceb120ebf179b1edf533d49bdfcdd2366f22bb0dd0a957'
SUMS_SIZE=357
SUMS_SHA='baa1ee8e807fed02fd7b225bfa9af3c923f6c9b085e68635f076ad5250407211'
ORDER=['README.md','RUN_TRACK_TRANSITION_ISOLATION.cmd','SELFTEST.cmd','SHA256SUMS.txt','track-transition-isolation.ps1']
OLD=b'$presentationTags=@($themeHooks.tag+$cssHooks.tag)'
NEW=b'$presentationTags=@(@($themeHooks|ForEach-Object{$_.tag})+@($cssHooks|ForEach-Object{$_.tag}))'

def sha(b): return hashlib.sha256(b).hexdigest()

seed=SEED.read_bytes()
assert len(seed)==SEED_SIZE,len(seed)
assert sha(seed)==SEED_SHA,sha(seed)
with zipfile.ZipFile(io.BytesIO(seed)) as z:
    assert z.testzip() is None
    assert sorted(z.namelist())==sorted(ORDER),z.namelist()
    files={name:z.read(name) for name in ORDER}
assert files['track-transition-isolation.ps1'].count(OLD)==1
files['track-transition-isolation.ps1']=files['track-transition-isolation.ps1'].replace(OLD,NEW)
assert len(files['track-transition-isolation.ps1'])==SCRIPT_SIZE
assert sha(files['track-transition-isolation.ps1'])==SCRIPT_SHA
sum_names=['README.md','RUN_TRACK_TRANSITION_ISOLATION.cmd','SELFTEST.cmd','track-transition-isolation.ps1']
files['SHA256SUMS.txt']=''.join(f'{sha(files[name])}  {name}\r\n' for name in sum_names).encode('ascii')
assert len(files['SHA256SUMS.txt'])==SUMS_SIZE
assert sha(files['SHA256SUMS.txt'])==SUMS_SHA

def build():
    buf=io.BytesIO()
    with zipfile.ZipFile(buf,'w',compression=zipfile.ZIP_STORED,strict_timestamps=True) as z:
        for name in ORDER:
            zi=zipfile.ZipInfo(name,(2026,10,25,13,0,0))
            zi.compress_type=zipfile.ZIP_STORED
            zi.create_system=0
            zi.external_attr=0
            z.writestr(zi,files[name])
    return buf.getvalue()

raw=build()
assert raw==build(),'Deterministic ZIP rebuild mismatch.'
assert len(raw)==FINAL_SIZE,len(raw)
assert sha(raw)==FINAL_SHA,sha(raw)
with zipfile.ZipFile(io.BytesIO(raw)) as z:
    assert z.testzip() is None
    assert sorted(z.namelist())==sorted(ORDER),z.namelist()
    lines=z.read('SHA256SUMS.txt').decode('ascii').splitlines()
    assert len(lines)==4,lines
    for line in lines:
        digest,name=line.split('  ',1)
        assert sha(z.read(name))==digest,(name,digest,sha(z.read(name)))
    for name in z.namelist():
        if not name.lower().endswith(('.md','.cmd','.ps1','.txt')): continue
        data=z.read(name)
        assert not [i for i,x in enumerate(data) if x==13 and (i+1>=len(data) or data[i+1]!=10)],name
        assert not [i for i,x in enumerate(data) if x==9],name
OUT.write_bytes(raw)
outdir=Path('phase2-v040');shutil.rmtree(outdir,ignore_errors=True);outdir.mkdir()
with zipfile.ZipFile(io.BytesIO(raw)) as z:z.extractall(outdir)
print('PHASE2_V040_SEED_PASS',len(seed),sha(seed))
print('PHASE2_V040_DETERMINISTIC_BUILD_PASS',len(raw),sha(raw))
print('PHASE2_V040_SCRIPT',SCRIPT_SIZE,SCRIPT_SHA)
