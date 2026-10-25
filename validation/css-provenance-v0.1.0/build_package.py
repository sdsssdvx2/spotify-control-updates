from pathlib import Path
import hashlib, zipfile

ROOT=Path(__file__).resolve().parents[2]
SRC=ROOT/'validation/css-provenance-v0.1.0'
OUT=ROOT/'SpotifyControl-CSS-Provenance-Collector-v0.1.0.zip'
FILES=[
    'RUN_CSS_PROVENANCE_COLLECTOR.cmd',
    'RUN_SELFTEST.cmd',
    'README.md',
    'css-provenance-collector.ps1',
]

def sha(b): return hashlib.sha256(b).hexdigest()

rows=[]
for name in FILES:
    b=(SRC/name).read_bytes()
    rows.append((name,b,sha(b)))
sums=''.join(f'{digest}  {name}\r\n' for name,_,digest in sorted(rows)).encode('ascii')
entries=[(name,b) for name,b,_ in rows]+[('SHA256SUMS.txt',sums)]
with zipfile.ZipFile(OUT,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as z:
    for name,b in sorted(entries):
        info=zipfile.ZipInfo(name,(2026,10,26,0,0,0))
        info.compress_type=zipfile.ZIP_DEFLATED
        info.external_attr=(0o100644<<16)
        info.create_system=3
        z.writestr(info,b,compress_type=zipfile.ZIP_DEFLATED,compresslevel=9)
raw=OUT.read_bytes()
print('CSS_PROVENANCE_PACKAGE_PASS',len(raw),sha(raw))
with zipfile.ZipFile(OUT) as z:
    assert z.testzip() is None
    assert sorted(z.namelist())==sorted([x[0] for x in entries])
    for name,b in entries:
        assert z.read(name)==b
