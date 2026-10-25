from pathlib import Path
import hashlib,io,re,subprocess,sys,tempfile,zipfile,shutil
R=Path.cwd()
BASE_COMMIT='ba031d1fd4bc01a1a1ee54d7f15cb998a6640785'
BASE_ZIP='SpotifyControl-Track-Transition-Background-Guarded-Acceptance-v0.5.3.zip'
BASE_SIZE=126853
BASE_SHA='b7aea344cd9a67c0b46886b41118bc3a33c76d2a2d7d6c8facdfa284b5baea43'
OUT='SpotifyControl-Production-Lazy-Overlay-Revalidation-v0.5.4.zip'
PROD_OVERLAY_APPLY_SHA='053a597e834aab959a588350160ce81046ceda66e2a2ac233eeff8af78fea544'
PROD_OVERLAY_LOADER_SHA='c38af0f6266747f50d2a0c05e9a49d5ffb34135738715fab6321ff4ae79623d9'
PROD_OVERLAY_TARGETS_SHA='c255e53066abbd730467e0c1d92e81dd907e1ea2f245daf6f0d080d2239fea35'

def h(b):return hashlib.sha256(b).hexdigest()
def production_crlf(b):return b.replace(b'\r\n',b'\n').replace(b'\n',b'\r\n')
def span(s,name):
    a=s.index('function '+name+' {');b=s.find('\nfunction ',a+1)
    if b<0:b=s.find('\ntry{',a+1)
    if b<0:b=len(s)
    assert b>a,name
    return a,b
def func(s,name):
    a,b=span(s,name);return s[a:b].strip()
def replace_func(s,name,new):
    a,b=span(s,name);tail='' if b==len(s) else s[b+1:]
    return s[:a]+new.rstrip()+'\n\n'+tail
def r1(s,a,b):
    assert s.count(a)==1,(a[:160],s.count(a));return s.replace(a,b,1)
def parse_functions(text):
    names=re.findall(r'(?m)^function\s+([A-Za-z0-9_-]+)\s*\{',text)
    return {n:func(text,n) for n in names}

# Rebuild the exact Windows-validated v0.5.3 package in an isolated worktree.
subprocess.run(['git','fetch','--no-tags','origin',BASE_COMMIT],check=True)
wd=Path(tempfile.mkdtemp(prefix='v053-base-'))
try:
    subprocess.run(['git','worktree','add','--detach',str(wd),BASE_COMMIT],check=True)
    subprocess.run([sys.executable,'validation/performance-phase2-v0.5.3/build_v053.py'],cwd=wd,check=True)
    raw=(wd/BASE_ZIP).read_bytes()
finally:
    try:subprocess.run(['git','worktree','remove','--force',str(wd)],check=False)
    finally:shutil.rmtree(wd,ignore_errors=True)
assert len(raw)==BASE_SIZE and h(raw)==BASE_SHA,(len(raw),h(raw))
with zipfile.ZipFile(io.BytesIO(raw)) as z:
    assert z.testzip() is None
    files={n:z.read(n) for n in z.namelist()}
base=files['track-transition-direct-patch-acceptance.ps1'].decode('utf-8-sig').replace('\r\n','\n')
s=base

align=(R/'validation/performance-phase2-v0.5.4/runtime_alignment_v054.ps1.inc').read_text(encoding='utf-8').replace('\r\n','\n').strip()
overlay=(R/'validation/performance-phase2-v0.5.4/runtime_overlay_v054.ps1.inc').read_text(encoding='utf-8').replace('\r\n','\n').strip()
A=parse_functions(align);O=parse_functions(overlay)

old_block='''$Version = "0.5.3"
$ExpectedMainSha = "45795b9622953a10c6eca2ee2f5a19fc4467c5143d5bdf7a9f2ad64841b9416f"
$ExpectedAddonSha = "df17018bdb5f62f55624070d047933387f62c049dae73cf5cefcc541bc412afa"
$PreviousMainSha = "27783abc40c446aadf6f2a9373b4525ada89759075f37e934958c8e449f2d98f"
$PreviousAddonSha = "b7d1a4bc7707533400402fe42e60d724f88656c2477d4d4a5c0f47be60f47977"
$Previous2MainSha = "5ff7990564287bc409626d8835e27679fb8de434868443313be42fdc0d9cce3b"
$Previous2AddonSha = "b7d1a4bc7707533400402fe42e60d724f88656c2477d4d4a5c0f47be60f47977"'''
new_block=f'''$Version = "0.5.4"
$ExpectedMainSha = "e9f0181756cfb84c505c30f54b6067e321f6d178d3a1936489714b8f4441ba18"
$ExpectedAddonSha = "3a20fcd552b363ebc05e26854a8fe010ffe50e5c756ebd3d7fca54011e8a8b86"
$PreviousMainSha = "45795b9622953a10c6eca2ee2f5a19fc4467c5143d5bdf7a9f2ad64841b9416f"
$PreviousAddonSha = "df17018bdb5f62f55624070d047933387f62c049dae73cf5cefcc541bc412afa"
$Previous2MainSha = "27783abc40c446aadf6f2a9373b4525ada89759075f37e934958c8e449f2d98f"
$Previous2AddonSha = "b7d1a4bc7707533400402fe42e60d724f88656c2477d4d4a5c0f47be60f47977"
$OverlayRoot = Join-Path $PSScriptRoot 'overlay'
$OverlayApplyPath = Join-Path $OverlayRoot 'apply-overlay.ps1'
$OverlayLoaderPath = Join-Path $OverlayRoot 'lazy-custom-app-loader.js'
$OverlayTargetsPath = Join-Path $OverlayRoot 'targets.json'
$ExpectedOverlayApplySha = "{PROD_OVERLAY_APPLY_SHA}"
$ExpectedOverlayLoaderSha = "{PROD_OVERLAY_LOADER_SHA}"
$ExpectedOverlayTargetsSha = "{PROD_OVERLAY_TARGETS_SHA}"'''
s=r1(s,old_block,new_block)

# Move accepted runtime from v0.6.19/r8 to current released v0.6.20/r9, while accepting exact v0.6.19/r8 and v0.6.18/r7 for self-healing alignment.
for name in ['Get-ComponentHashSnapshot','Get-ComponentBaselineKind','Write-ComponentHashDiagnostics','Invoke-BootstrapJson','Align-ReleasedProductionBaseline','Assert-AcceptedRuntimeBaseline']:
    s=replace_func(s,name,A[name])

# Replace only orchestration/report/self-test surfaces. Media targeting, sampler, process-role analysis, CoreAudio guard and background-window behavior remain v0.5.3-identical.
replace_names=['Build-FocusedPatchVariantMatrix','Prepare-Variant','Restore-OriginalXpui','Build-TextReport','Invoke-Lab','Invoke-SelfTest']
for name in replace_names:s=replace_func(s,name,O[name])
new_names=[n for n in O if n not in replace_names]
insert_at=span(s,'Prepare-Variant')[0]
new_text='\n\n'.join(O[n] for n in new_names)
s=s[:insert_at]+new_text+'\n\n'+s[insert_at:]

# User-facing/report path identity.
s=s.replace('track-transition-direct-patch-v053','track-transition-overlay-v054')
s=s.replace('TRACK TRANSITION DIRECT-PATCH FOCUSED ACCEPTANCE FAILED','PRODUCTION LAZY-OVERLAY REVALIDATION FAILED')
s=s.replace('Safety restore completed. Do not rerun this package; send the console output/error log.','Safety restore completed. Do not rerun automatically; send the console output/error log.')
s=s.replace('v0.5.3','v0.5.4').replace('v053','v054')

# The v0.5.3 targeted media/measurement core must remain text-identical.
for name in ['Get-SpotifyMediaSession','Wait-SpotifyMediaSession','Invoke-SpotifyMediaCommand','Start-SpotifyGuardedSilentPlayback','Show-SpotifyBehindUserForMeasurement','Refresh-SpotifySilentForTest','Stop-SpotifyForVariant','Measure-TransitionCondition','Analyze-Transitions','Get-WorkloadPolicy','Average-TwoMetricSummaries','Get-ProcessRoleFromCommandLine']:
    assert func(base,name)==func(s,name),name
for forbidden in ['keybd_event','SpotifyControlMediaKeys','Send-MediaKey','[byte]0xB0','[byte]0xB3']:
    assert forbidden.lower() not in s.lower(),forbidden
for required in ['TrySkipNextAsync','SPOTIFY_NEXT_CONFIRMED','RegisterSessionNotification','WaitForSpotifyCapture(5000,5)','current-v0620-r9','BASELINE_A,BLF_ORIGINAL,PLAYLIST_MAKER_ORIGINAL,BOTH_ORIGINAL,BASELINE_B','exact-production-lazy-overlay-index-policy-only','production_overlay_state_unchanged_exact']:
    assert required in s,required
lab=func(s,'Invoke-Lab')
for forbidden in ['Assert-DirectPatchEligibility','Invoke-DirectPatchEngine','Write-PatchSubsetMetadata','PatchMetadataPaths']:
    assert forbidden not in lab,forbidden

# The release builder embedded Windows-CRLF overlay bytes into Addon Manager r8/r9.
# GitHub stores the source normalized to LF, so normalize deterministically back to the exact released byte identities.
apply=production_crlf((R/'performance/overlay/apply-overlay.ps1').read_bytes())
loader=production_crlf((R/'performance/overlay/lazy-custom-app-loader.js').read_bytes())
targets=production_crlf((R/'performance/overlay/targets/pithaya-optional-custom-apps.json').read_bytes())
assert len(apply)==16748 and h(apply)==PROD_OVERLAY_APPLY_SHA,(len(apply),h(apply))
assert len(loader)==10600 and h(loader)==PROD_OVERLAY_LOADER_SHA,(len(loader),h(loader))
assert len(targets)==1756 and h(targets)==PROD_OVERLAY_TARGETS_SHA,(len(targets),h(targets))

script=('\r\n'.join(s.split('\n'))).encode('utf-8-sig')
readme=("Spotify Control Production Lazy-Overlay Revalidation v0.5.4\r\n\r\n"
        "Purpose: revalidate the real production Better Local Files / Playlist Maker lazy overlay using the trusted v0.5.3 Spotify-targeted media-session sampler. This replaces the old global-media-key-era performance evidence.\r\n\r\n"
        "Conditions: production optimized A -> Better Local Files original/eager -> Playlist Maker original/eager -> both original/eager -> production optimized B. Target extension JavaScript bytes never change; only exact index loading policy changes. Star Ratings v0.6.20 optimization remains enabled in every condition.\r\n\r\n"
        "Safety: exact v0.6.20/r9 is used for measurement (known v0.6.19/r8 or v0.6.18/r7 may self-align through released Bootstrap 1.0.6 first). The run requires an exact active production overlay state, pinned extension bytes, exact state/index/backup/loader hashes, and keeps the real production overlay state root untouched. It uses session-only experimental state, restores the initial production-optimized index/tree exactly, preserves config, backs up protected WebView persistence without editing it, and restores the resident. Unknown/drifted bytes fail closed before profiling mutation.\r\n\r\n"
        "Spotify starts hidden, stays non-minimized behind your foreground app, and Spotify audio alone is muted/restored. Other videos/audio may continue, but for the cleanest CPU/GPU evidence avoid starting heavy new workloads during the short run. Do not interact with Spotify itself.\r\n").encode('utf-8')
cmd=("@echo off\r\nsetlocal\r\ncd /d \"%~dp0\"\r\necho Spotify Control Production Lazy-Overlay Revalidation v0.5.4\r\necho --------------------------------------------------------------\r\necho Choose a playlist/album with at least 8 playable tracks.\r\necho Spotify will be controlled only through its own media session and muted by Spotify-only CoreAudio guard.\r\necho Other media will not be controlled. Do not interact with Spotify until this finishes.\r\necho.\r\npowershell.exe -NoProfile -ExecutionPolicy Bypass -File \"%~dp0track-transition-overlay-revalidation.ps1\" -Action Run\r\nset \"EC=%ERRORLEVEL%\"\r\necho.\r\nif not \"%EC%\"==\"0\" echo FAILED. Do not rerun automatically; provide the v0.5.4 error log.\r\nif \"%EC%\"==\"0\" echo VERIFIED. Upload the v0.5.4 report and JSON.\r\npause\r\nexit /b %EC%\r\n").encode('ascii')
selftest=("@echo off\r\nsetlocal\r\ncd /d \"%~dp0\"\r\npowershell.exe -NoProfile -ExecutionPolicy Bypass -File \"%~dp0track-transition-overlay-revalidation.ps1\" -Action SelfTest\r\nexit /b %ERRORLEVEL%\r\n").encode('ascii')
entries={'README.md':readme,'RUN_PRODUCTION_LAZY_OVERLAY_REVALIDATION.cmd':cmd,'SELFTEST.cmd':selftest,'track-transition-overlay-revalidation.ps1':script,'overlay/apply-overlay.ps1':apply,'overlay/lazy-custom-app-loader.js':loader,'overlay/targets.json':targets}
checks=['README.md','RUN_PRODUCTION_LAZY_OVERLAY_REVALIDATION.cmd','SELFTEST.cmd','track-transition-overlay-revalidation.ps1','overlay/apply-overlay.ps1','overlay/lazy-custom-app-loader.js','overlay/targets.json']
entries['SHA256SUMS.txt']=''.join(f'{h(entries[n])}  {n}\r\n' for n in checks).encode('ascii')
order=['README.md','RUN_PRODUCTION_LAZY_OVERLAY_REVALIDATION.cmd','SELFTEST.cmd','SHA256SUMS.txt','track-transition-overlay-revalidation.ps1','overlay/apply-overlay.ps1','overlay/lazy-custom-app-loader.js','overlay/targets.json']
b=io.BytesIO()
with zipfile.ZipFile(b,'w',compression=zipfile.ZIP_STORED) as z:
    for n in order:
        zi=zipfile.ZipInfo(n,date_time=(2026,10,26,4,0,0));zi.compress_type=zipfile.ZIP_STORED;zi.create_system=0;z.writestr(zi,entries[n])
out=b.getvalue();(R/OUT).write_bytes(out)
with zipfile.ZipFile(io.BytesIO(out)) as z:
    assert z.testzip() is None and z.namelist()==order
    for line in z.read('SHA256SUMS.txt').decode('ascii').splitlines():
        x,n=line.split('  ',1);assert h(z.read(n))==x,(n,x)
print('PHASE2_V054_BASE_V053_PASS',BASE_SIZE,BASE_SHA)
print('PHASE2_V054_PRODUCTION_OVERLAY_CRLF',len(apply),h(apply),len(loader),h(loader),len(targets),h(targets))
print('PHASE2_V054_ALIGNMENT_HELPER',len(align.encode()),h(align.encode()))
print('PHASE2_V054_OVERLAY_HELPER',len(overlay.encode()),h(overlay.encode()))
print('PHASE2_V054_SCRIPT',len(script),h(script))
print('PHASE2_V054_PACKAGE',len(out),h(out))
