from pathlib import Path
import base64,gzip,hashlib,io,subprocess,sys,zipfile,shutil

ROOT=Path.cwd()
V041_COMMIT='4d9eb71d1fa97b70d839dc887cdc8f5531d2ff8b'
V041_BUILDER='validation/performance-phase2-v0.4.1/build_and_validate.py'
V041_ZIP='SpotifyControl-Track-Transition-Single-Hook-Isolation-v0.4.1.zip'
V041_SIZE=70917
V041_SHA='2c857fa0988cb73d3930c599c30655b8315f53ebb2b425e67fb79b2e0244d5b1'
V041_SCRIPT_SHA='c345e5fbd346b817ad434d1396aa52a84898494eacea53ad47f4d4614ab6ab87'
V050_SCRIPT_SIZE=71026
V050_SCRIPT_SHA='bd306db0109374875bbc62e66fb62ce925be6155f565e5526ddaf9f24150bb2e'
OUT='SpotifyControl-Track-Transition-Direct-Patch-Acceptance-v0.5.0.zip'

def sha(b): return hashlib.sha256(b).hexdigest()

def function_body(text,name):
    marker='function '+name+' {'
    start=text.index(marker)
    nxt=text.find('\nfunction ',start+1)
    if nxt < 0: nxt=text.find('\ntry{',start+1)
    if nxt < 0: raise AssertionError('function boundary missing: '+name)
    return text[start:nxt].strip()

# Recreate the exact previously Windows-validated v0.4.1 measurement engine.
subprocess.run(['git','fetch','--no-tags','--depth=1','origin',V041_COMMIT],check=True)
old_builder=subprocess.check_output(['git','show',f'{V041_COMMIT}:{V041_BUILDER}'])
old_builder_path=ROOT/'validation/performance-phase2-v0.5.0/_v041_builder.py'
old_builder_path.write_bytes(old_builder)
try:
    subprocess.run([sys.executable,str(old_builder_path)],check=True,cwd=ROOT)
finally:
    old_builder_path.unlink(missing_ok=True)
v041=(ROOT/V041_ZIP).read_bytes()
assert len(v041)==V041_SIZE and sha(v041)==V041_SHA,(len(v041),sha(v041))
with zipfile.ZipFile(io.BytesIO(v041)) as z:
    assert z.testzip() is None
    old_script=z.read('track-transition-isolation.ps1')
assert sha(old_script)==V041_SCRIPT_SHA
(ROOT/'v041-input.ps1').write_bytes(old_script)

# Apply the deterministic reviewed v0.4.1 -> v0.5.0 transform payload.
payload=base64.b64decode((ROOT/'validation/performance-phase2-v0.5.0/transform_v050.py.gz.b64').read_text().strip())
transform=gzip.decompress(payload)
assert sha(transform)=='301804586ba8a96f3c9185012a8deb7af8f243e1389e3ad89590af913d70f086'
transform_path=ROOT/'validation/performance-phase2-v0.5.0/_transform_v050.py'
transform_path.write_bytes(transform)
try:
    subprocess.run([sys.executable,str(transform_path)],check=True,cwd=ROOT)
finally:
    transform_path.unlink(missing_ok=True)
script=(ROOT/'v050-output.ps1').read_bytes()
assert len(script)==V050_SCRIPT_SIZE and sha(script)==V050_SCRIPT_SHA,(len(script),sha(script))

# Prove that core sampling/analysis/safety machinery is byte-text identical to validated v0.4.1.
old_text=old_script.decode('utf-8-sig').replace('\r\n','\n')
new_text=script.decode('utf-8-sig').replace('\r\n','\n')
for fn in [
    'Get-TreeFingerprint','Backup-ProtectedPersistence','Stop-SpotifyForVariant',
    'Suspend-Resident','Restore-Resident','Send-MediaKey','Wait-SpotifyReady',
    'Get-ProcessRoleFromCommandLine','Measure-TransitionCondition','Analyze-Transitions',
    'Get-WorkloadPolicy','Average-TwoMetricSummaries','Build-Comparison'
]:
    assert function_body(old_text,fn)==function_body(new_text,fn),fn

patch=(ROOT/'performance/direct-extension-patches/apply-direct-extension-patches.ps1').read_bytes()
targets=(ROOT/'performance/direct-extension-patches/targets.json').read_bytes()
patch_text=patch.decode('utf-8-sig')
target_text=targets.decode('utf-8')
for token in [
    'popup hidden worker start gate','popup PiP enter hidden worker start','popup PiP leave worker stop',
    'star tracklist observer debounce','star body observer debounce','star tracklist identity comparison',
    'conflict-newer-or-unknown-active-bytes','active-bytes-not-exact-pinned-upstream'
]: assert token in patch_text,token
for token in [
    '2b280aea8514bd15044c36403257ca6ac21f1f98e6798beb4aa319bf19a70e4f',
    '198fd7c3307de8f2efc36f40df4e79846188cf35a1d5b550ed3d8ab85e8139b1'
]: assert token in target_text,token

readme='''Spotify Control Track Transition Direct-Patch Focused Acceptance v0.5.0\r\n=======================================================================\r\n\r\nPurpose\r\n-------\r\nThis is a validation-only Phase-2 profiler. It does NOT install or replace Spotify Control production files.\r\nIt measures exactly five conditions using the already validated v0.4.1 transition sampler:\r\n  1. BASELINE_A\r\n  2. POPUP_PATCH\r\n  3. STAR_PATCH\r\n  4. BOTH_PATCHES\r\n  5. BASELINE_B\r\nEach condition emits five automatic NEXT media keys.\r\n\r\nAccepted runtime\r\n----------------\r\n- Spotify Control 0.6.19 exact production SHA\r\n- Addon Manager 0.6.5-r8 exact production SHA\r\n- Spotify 1.3.6.1921\r\n- Spicetify 2.46.2\r\n- Exact pinned active PopupLyrics and Star Ratings bytes\r\n\r\nSafety\r\n------\r\n- Run as the normal desktop user, never Administrator.\r\n- No spicetify apply/backup/restore/config mutation.\r\n- No index.html hook removal.\r\n- No extension/custom-app deletion or rename.\r\n- Star Ratings playlist-backed data, ivLyrics, Tagify, Splitify and unknown hooks are untouched.\r\n- Browser/Default persistence is safety-backed up but never edited.\r\n- Every condition restores prior direct patches to exact original bytes before continuing.\r\n- Restore refuses to overwrite newer/unknown bytes.\r\n- Final xpui tree, index.html and config hashes must match the originals exactly.\r\n- Resident process is temporarily suspended only for uncontaminated measurement and restored afterward.\r\n\r\nBefore RUN\r\n----------\r\nChoose a playlist or album with at least 8 playable tracks. Pause on a normal track and exit Spotify normally.\r\nThe profiler can safely close residual Spotify tray/helper processes after accepted-state checks.\r\nDo not touch Spotify after the run begins.\r\n\r\nOutputs\r\n-------\r\n%LOCALAPPDATA%\\SpotifyControl\\reports\\track-transition-direct-patch-v050-latest.txt\r\n%LOCALAPPDATA%\\SpotifyControl\\reports\\track-transition-direct-patch-v050-latest.json\r\n%LOCALAPPDATA%\\SpotifyControl\\reports\\track-transition-direct-patch-v050-raw-latest.csv\r\n%LOCALAPPDATA%\\SpotifyControl\\reports\\track-transition-direct-patch-v050-progress.json\r\nError log: %LOCALAPPDATA%\\SpotifyControl\\logs\\track-transition-direct-patch-v050-error.log\r\n'''.encode('utf-8')
run_cmd='''@echo off\r\nsetlocal\r\ncd /d "%~dp0"\r\necho Spotify Control Track Transition Direct-Patch Focused Acceptance v0.5.0\r\necho ---------------------------------------------------------------------\r\necho IMPORTANT: playlist/album with 8+ playable tracks; pause and exit Spotify normally first.\r\necho Run this normally, NOT as Administrator. Do not touch Spotify after this starts.\r\necho.\r\npowershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0track-transition-direct-patch-acceptance.ps1" -Action Run\r\nset RC=%ERRORLEVEL%\r\necho.\r\nif not "%RC%"=="0" echo FAILED. Do not rerun automatically; provide console/error log.\r\nif "%RC%"=="0" echo VERIFIED. Provide the v0.5.0 report/JSON for review.\r\npause\r\nexit /b %RC%\r\n'''.encode('ascii')
selftest='''@echo off\r\nsetlocal\r\ncd /d "%~dp0"\r\npowershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0track-transition-direct-patch-acceptance.ps1" -Action SelfTest\r\nexit /b %ERRORLEVEL%\r\n'''.encode('ascii')
entries={
    'README.md':readme,
    'RUN_TRACK_TRANSITION_DIRECT_PATCH_ACCEPTANCE.cmd':run_cmd,
    'SELFTEST.cmd':selftest,
    'track-transition-direct-patch-acceptance.ps1':script,
    'apply-direct-extension-patches.ps1':patch,
    'targets.json':targets,
}
order=['README.md','RUN_TRACK_TRANSITION_DIRECT_PATCH_ACCEPTANCE.cmd','SELFTEST.cmd','apply-direct-extension-patches.ps1','targets.json','track-transition-direct-patch-acceptance.ps1']
entries['SHA256SUMS.txt']=''.join(f'{sha(entries[n])}  {n}\r\n' for n in order).encode('ascii')
zip_order=['README.md','RUN_TRACK_TRANSITION_DIRECT_PATCH_ACCEPTANCE.cmd','SELFTEST.cmd','SHA256SUMS.txt','apply-direct-extension-patches.ps1','targets.json','track-transition-direct-patch-acceptance.ps1']
out=io.BytesIO()
with zipfile.ZipFile(out,'w',compression=zipfile.ZIP_STORED) as z:
    for n in zip_order:
        info=zipfile.ZipInfo(n,date_time=(2026,10,25,23,30,0));info.compress_type=zipfile.ZIP_STORED;info.create_system=0;z.writestr(info,entries[n])
raw=out.getvalue();(ROOT/OUT).write_bytes(raw)
with zipfile.ZipFile(io.BytesIO(raw)) as z:
    assert z.testzip() is None
    assert z.namelist()==zip_order
    for line in z.read('SHA256SUMS.txt').decode('ascii').splitlines():
        h,n=line.split('  ',1);assert sha(z.read(n))==h,(n,h)
print('PHASE2_V050_V041_PROVENANCE_PASS',V041_SIZE,V041_SHA)
print('PHASE2_V050_CORE_ENGINE_IDENTITY_PASS')
print('PHASE2_V050_SCRIPT_PASS',len(script),sha(script))
print('PHASE2_V050_PATCH_ENGINE',len(patch),sha(patch))
print('PHASE2_V050_TARGETS',len(targets),sha(targets))
print('PHASE2_V050_PACKAGE_PASS',len(raw),sha(raw))

for p in [ROOT/'v041-input.ps1',ROOT/'v050-output.ps1',ROOT/V041_ZIP]:
    p.unlink(missing_ok=True)
shutil.rmtree(ROOT/'phase2-v041',ignore_errors=True)
