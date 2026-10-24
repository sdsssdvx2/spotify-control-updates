from pathlib import Path
import hashlib, json, shutil, subprocess, sys, zipfile

BASE_SIZE=23068
BASE_SHA='65057fe1595a7f78a0fd3e138304c6044c42adbaed829541042f485a9e37655d'
OLD_SOURCE='e51f73c90c50cb55e3e3dffe3b55a6f6b1af0b4c'
NEW_SOURCE='36b15a2ed2f9a23fffbeaf91de78b7854f6108b2'
MAIN_SHA='5ff7990564287bc409626d8835e27679fb8de434868443313be42fdc0d9cce3b'
ADDON_SHA='b7d1a4bc7707533400402fe42e60d724f88656c2477d4d4a5c0f47be60f47977'
PAYLOAD='0f7fe384630e027466aa734ac669b410774b4569db231982212b7fa565b691a0'
BOOTSTRAP_SHA='d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6'

base=Path('base-v140.zip')
raw=base.read_bytes()
assert len(raw)==BASE_SIZE,(len(raw),BASE_SIZE)
assert hashlib.sha256(raw).hexdigest()==BASE_SHA
out=Path('stage14-v141-unpacked')
shutil.rmtree(out,ignore_errors=True);out.mkdir(parents=True)
with zipfile.ZipFile(base) as z:
    assert z.testzip() is None
    z.extractall(out)

runp=out/'RUN_RUNTIME_ACCEPTANCE.ps1'
run=runp.read_text(encoding='utf-8-sig')
assert run.count("$AcceptanceVersion = '1.4.0'")==1
assert run.count("$ExpectedSourceCommit = '"+OLD_SOURCE+"'")==1
run=run.replace("$AcceptanceVersion = '1.4.0'","$AcceptanceVersion = '1.4.1'",1)
run=run.replace("$ExpectedSourceCommit = '"+OLD_SOURCE+"'","$ExpectedSourceCommit = '"+NEW_SOURCE+"'",1)
# Target payload bytes/versions remain deliberately unchanged.
for needle in [MAIN_SHA,ADDON_SHA,PAYLOAD,BOOTSTRAP_SHA,"$ExpectedMainVersion = '0.6.17'","$ExpectedAddonVersion = '0.6.5-r7'","[int]$check.result.edge_count -ne 2"]:
    assert needle in run,needle
assert OLD_SOURCE not in run
runp.write_text(run,encoding='utf-8-sig',newline='\n')

readp=out/'README.txt'
readme=readp.read_text(encoding='utf-8')
assert readme.count('Spotify Control Windows Runtime Acceptance v1.4.0')==1
assert readme.count('- source commit '+OLD_SOURCE)==1
readme=readme.replace('Spotify Control Windows Runtime Acceptance v1.4.0','Spotify Control Windows Runtime Acceptance v1.4.1',1)
readme=readme.replace('- source commit '+OLD_SOURCE,'- source commit '+NEW_SOURCE,1)
anchor='- agent 0.1.1 and Bootstrap 1.0.6 unchanged.\n'
assert readme.count(anchor)==1
extra='''\nPublication-contract repair before v1.4.1:\n- The v0.6.15 -> v0.6.16 and v0.6.16 -> v0.6.17 main patch documents now include the exact Bootstrap 1.0.6 `schema:1`, `bom:utf8-bom`, and `line_ending:lf` envelope and canonical `packages/v<to_version>/<single-dir>/chunk-NNN.txt` paths.\n- No target payload bytes changed: v0.6.17/r7 hashes and payload-set SHA remain identical. Only those two main patch transport envelopes and the immutable source commit changed.\n- Production Windows CI reconstructed exact v0.6.15/r5 and used byte-exact Bootstrap 1.0.6 to pass Check -> RollbackTest/restore -> Update/commit -> already-current edge_count=0 against live main.\n'''
readme=readme.replace(anchor,anchor+extra,1)
readp.write_text(readme,encoding='utf-8',newline='\n')

valp=out/'evidence'/'validate_stage14.py'
val=valp.read_text(encoding='utf-8')
assert val.count("$AcceptanceVersion = '1.4.0'")==1
assert val.count(OLD_SOURCE)==1
assert val.count('STAGE14 V1.4.0 SELF VALIDATION')==2
val=val.replace("$AcceptanceVersion = '1.4.0'","$AcceptanceVersion = '1.4.1'",1)
val=val.replace(OLD_SOURCE,NEW_SOURCE,1)
val=val.replace('STAGE14 V1.4.0 SELF VALIDATION','STAGE14 V1.4.1 SELF VALIDATION')
valp.write_text(val,encoding='utf-8',newline='\n')

for p in [out/'evidence'/'SELF_VALIDATION_REPORT.json',out/'evidence'/'SELF_VALIDATION_REPORT.txt',out/'evidence'/'VALIDATION_OUTPUT.txt']:
    if p.exists(): p.unlink()
rels=['RUN_RUNTIME_ACCEPTANCE.ps1','RUN_RUNTIME_ACCEPTANCE.cmd','PRECHECK_RUNTIME_ACCEPTANCE.ps1','README.txt','evidence/validate_stage14.py']
(out/'SHA256SUMS.txt').write_text(''.join(hashlib.sha256((out/x).read_bytes()).hexdigest()+'  '+x+'\n' for x in rels),encoding='ascii')
res=subprocess.run([sys.executable,str(valp)],text=True,capture_output=True)
(out/'evidence'/'VALIDATION_OUTPUT.txt').write_text(res.stdout+res.stderr,encoding='utf-8')
assert res.returncode==0,res.stdout+res.stderr
report=json.loads((out/'evidence'/'SELF_VALIDATION_REPORT.json').read_text(encoding='utf-8'))
assert report['passed']==report['total']==25,report
assert NEW_SOURCE in runp.read_text(encoding='utf-8-sig')
assert OLD_SOURCE not in runp.read_text(encoding='utf-8-sig')

final=Path('SpotifyControl-Windows-Runtime-Acceptance-v1.4.1.zip')
if final.exists():final.unlink()
with zipfile.ZipFile(final,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
    for p in sorted(out.rglob('*')):
        if p.is_file():z.write(p,p.relative_to(out).as_posix())
with zipfile.ZipFile(final) as z:
    assert z.testzip() is None
    for line in z.read('SHA256SUMS.txt').decode('ascii').splitlines():
        h,rel=line.split('  ',1);assert hashlib.sha256(z.read(rel)).hexdigest()==h,(rel,h)
print('STAGE14_V141_BUILD_PASS',final.stat().st_size,hashlib.sha256(final.read_bytes()).hexdigest(),report['passed'],report['total'],report['script_sha256'])
