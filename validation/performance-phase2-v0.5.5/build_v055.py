from pathlib import Path
import hashlib,io,re,zipfile,subprocess,sys,tempfile,shutil,gzip,base64
R=Path.cwd()
BASE_COMMIT='ec242e8243a9669593197f756f3edbe317473218'
BASE_ZIP='SpotifyControl-Production-Lazy-Overlay-Revalidation-v0.5.4.zip'
BASE_SIZE=150788
BASE_SHA='7aae6cf469fc70e5c6484ac88adf06c7eed8fdc27db4ee6725b414c1d3d127f3'
OUT='SpotifyControl-Production-Lazy-Overlay-Counterbalanced-Revalidation-v0.5.5.zip'
def h(b): return hashlib.sha256(b).hexdigest()
def span(s,name):
    a=s.index('function '+name+' {'); b=s.find('\nfunction ',a+1)
    if b<0:b=s.find('\ntry{',a+1)
    if b<0:b=len(s)
    assert b>a,name
    return a,b
def func(s,name):
    a,b=span(s,name); return s[a:b].strip()
def replace_func(s,name,new):
    a,b=span(s,name); tail='' if b==len(s) else s[b+1:]
    return s[:a]+new.rstrip()+'\n\n'+tail
def parse_functions(text):
    names=re.findall(r'(?m)^function\s+([A-Za-z0-9_-]+)\s*\{',text)
    return {n:func(text,n) for n in names}

# Rebuild the exact fully Windows-validated v0.5.4 package; v0.5.5 is a deterministic measurement-design delta.
subprocess.run(['git','fetch','--no-tags','origin',BASE_COMMIT],check=True)
wd=Path(tempfile.mkdtemp(prefix='v054-base-'))
try:
    subprocess.run(['git','worktree','add','--detach',str(wd),BASE_COMMIT],check=True)
    subprocess.run([sys.executable,'validation/performance-phase2-v0.5.4/build_v054.py'],cwd=wd,check=True)
    raw=(wd/BASE_ZIP).read_bytes()
finally:
    try:subprocess.run(['git','worktree','remove','--force',str(wd)],check=False)
    finally:shutil.rmtree(wd,ignore_errors=True)
assert len(raw)==BASE_SIZE and h(raw)==BASE_SHA,(len(raw),h(raw))
with zipfile.ZipFile(io.BytesIO(raw)) as z:
    assert z.testzip() is None
    files={n:z.read(n) for n in z.namelist()}
assert len(files['overlay/apply-overlay.ps1'])==16748 and h(files['overlay/apply-overlay.ps1'])=='053a597e834aab959a588350160ce81046ceda66e2a2ac233eeff8af78fea544'
assert len(files['overlay/lazy-custom-app-loader.js'])==10600 and h(files['overlay/lazy-custom-app-loader.js'])=='c38af0f6266747f50d2a0c05e9a49d5ffb34135738715fab6321ff4ae79623d9'
assert len(files['overlay/targets.json'])==1756 and h(files['overlay/targets.json'])=='c255e53066abbd730467e0c1d92e81dd907e1ea2f245daf6f0d080d2239fea35'
base=files['track-transition-overlay-revalidation.ps1'].decode('utf-8-sig').replace('\r\n','\n')
s=base
inc=gzip.decompress(base64.b64decode((R/'validation/performance-phase2-v0.5.5/runtime_counterbalanced_v055.ps1.inc.gz.b64').read_text(encoding='ascii'))).decode('utf-8').replace('\r\n','\n').strip()
F=parse_functions(inc)
replace_names=['Build-FocusedPatchVariantMatrix','Write-ProgressCheckpoint','Build-TextReport','Invoke-Lab','Invoke-SelfTest']
for n in replace_names: s=replace_func(s,n,F[n])
helpers=[n for n in F if n not in replace_names]
insert_at=span(s,'Build-FocusedPatchVariantMatrix')[0]
s=s[:insert_at]+'\n\n'.join(F[n] for n in helpers)+'\n\n'+s[insert_at:]
s=s.replace('$Version = "0.5.4"','$Version = "0.5.5"')
s=s.replace('track-transition-overlay-v054','track-transition-overlay-v055')
s=s.replace('v0.5.4','v0.5.5').replace('v054','v055')
s=s.replace('PRODUCTION LAZY-OVERLAY REVALIDATION FAILED','COUNTERBALANCED PRODUCTION LAZY-OVERLAY REVALIDATION FAILED')
# trusted measurement core and production overlay mutation surfaces stay identical
for n in ['Get-SpotifyMediaSession','Wait-SpotifyMediaSession','Invoke-SpotifyMediaCommand','Start-SpotifyGuardedSilentPlayback','Show-SpotifyBehindUserForMeasurement','Refresh-SpotifySilentForTest','Stop-SpotifyForVariant','Measure-TransitionCondition','Analyze-Transitions','Get-WorkloadPolicy','Prepare-Variant','Restore-OriginalXpui','Assert-OverlayBenchmarkEligibilityV054','Invoke-OverlayEngineV054','Reset-OverlayIndexToPristineV054']:
    assert func(base,n)==func(s,n),n
for x in ['keybd_event','SpotifyControlMediaKeys','Send-MediaKey','[byte]0xB0','[byte]0xB3']:
    assert x.lower() not in s.lower(),x
for x in ['williams-counterbalanced-4x4','A,B,D,C','B,C,A,D','C,D,B,A','D,A,C,B','verified_transitions_expected=48','production_overlay_state_unchanged_exact']:
    assert x in s,x
script=('\r\n'.join(s.split('\n'))).encode('utf-8-sig')
readme=("Spotify Control Production Lazy-Overlay Counterbalanced Revalidation v0.5.5\r\n\r\n"
"Purpose: resolve the v0.5.4 medium-confidence/order-drift result without changing production. This keeps the trusted Spotify-targeted v0.5.3 measurement core and exact production overlay engine, but measures the four BLF/Playlist Maker loading-policy states in a 4-block Williams counterbalance.\r\n\r\n"
"Design: 16 conditions total, 3 metadata-confirmed Spotify NEXT transitions per condition. Every state appears once in each ordinal position, and every ordered carryover pair appears exactly once. The report computes block-level 2x2 factorial effects for BLF lazy, Playlist Maker lazy, both-lazy combined, and their interaction.\r\n\r\n"
"Safety is unchanged from v0.5.4: exact v0.6.20/r9 measurement state (known v0.6.19/r8 or v0.6.18/r7 may self-align first), exact pinned extension bytes and production overlay state/index/backup/loader hashes, session-only experimental state roots, no extension payload edits, exact xpui/config/state restore, protected persistence backup without edits, resident restoration, ivLyrics/Tagify/Splitify/SC Cover Ambience/Marketplace/unknown hooks untouched, and fail-closed behavior on drift.\r\n\r\n"
"This run is deliberately longer than v0.5.4. Do not interact with Spotify itself and avoid starting heavy new CPU/GPU workloads while it runs. Other media applications are never controlled.\r\n").encode('utf-8')
cmd=("@echo off\r\nsetlocal\r\ncd /d \"%~dp0\"\r\necho Spotify Control Production Lazy-Overlay Counterbalanced Revalidation v0.5.5\r\necho --------------------------------------------------------------------------\r\necho Choose a playlist/album with at least 8 playable tracks.\r\necho This is one longer 16-condition counterbalanced run. Do not interact with Spotify until it finishes.\r\necho Spotify alone is controlled/muted through its own media/audio sessions; other media is untouched.\r\necho Avoid starting heavy new CPU/GPU work during the run.\r\necho.\r\npowershell.exe -NoProfile -ExecutionPolicy Bypass -File \"%~dp0track-transition-overlay-counterbalanced-revalidation.ps1\" -Action Run\r\nset \"EC=%ERRORLEVEL%\"\r\necho.\r\nif not \"%EC%\"==\"0\" echo FAILED. Do not rerun automatically; provide the v0.5.5 error log.\r\nif \"%EC%\"==\"0\" echo VERIFIED. Upload the v0.5.5 report and JSON.\r\npause\r\nexit /b %EC%\r\n").encode('ascii')
selftest=("@echo off\r\nsetlocal\r\ncd /d \"%~dp0\"\r\npowershell.exe -NoProfile -ExecutionPolicy Bypass -File \"%~dp0track-transition-overlay-counterbalanced-revalidation.ps1\" -Action SelfTest\r\nexit /b %ERRORLEVEL%\r\n").encode('ascii')
entries={
'README.md':readme,
'RUN_COUNTERBALANCED_LAZY_OVERLAY_REVALIDATION.cmd':cmd,
'SELFTEST.cmd':selftest,
'track-transition-overlay-counterbalanced-revalidation.ps1':script,
'overlay/apply-overlay.ps1':files['overlay/apply-overlay.ps1'],
'overlay/lazy-custom-app-loader.js':files['overlay/lazy-custom-app-loader.js'],
'overlay/targets.json':files['overlay/targets.json'],
}
checks=list(entries)
entries['SHA256SUMS.txt']=''.join(f'{h(entries[n])}  {n}\r\n' for n in checks).encode('ascii')
order=['README.md','RUN_COUNTERBALANCED_LAZY_OVERLAY_REVALIDATION.cmd','SELFTEST.cmd','SHA256SUMS.txt','track-transition-overlay-counterbalanced-revalidation.ps1','overlay/apply-overlay.ps1','overlay/lazy-custom-app-loader.js','overlay/targets.json']
b=io.BytesIO()
with zipfile.ZipFile(b,'w',compression=zipfile.ZIP_STORED) as z:
    for n in order:
        zi=zipfile.ZipInfo(n,date_time=(2026,10,26,4,45,0));zi.compress_type=zipfile.ZIP_STORED;zi.create_system=0;z.writestr(zi,entries[n])
out=b.getvalue();(R/OUT).write_bytes(out)
with zipfile.ZipFile(io.BytesIO(out)) as z:
    assert z.testzip() is None and z.namelist()==order
    for line in z.read('SHA256SUMS.txt').decode().splitlines():
        x,n=line.split('  ',1); assert h(z.read(n))==x
print('PHASE2_V055_BASE_V054_PASS',len(raw),h(raw))
print('PHASE2_V055_COUNTERBALANCE_HELPER',len(inc.encode()),h(inc.encode()))
print('PHASE2_V055_SCRIPT',len(script),h(script))
print('PHASE2_V055_PACKAGE',len(out),h(out))
print('PHASE2_V055_PRODUCTION_OVERLAY_IDENTITIES',len(files['overlay/apply-overlay.ps1']),h(files['overlay/apply-overlay.ps1']),len(files['overlay/lazy-custom-app-loader.js']),h(files['overlay/lazy-custom-app-loader.js']),len(files['overlay/targets.json']),h(files['overlay/targets.json']))
