from pathlib import Path
import hashlib,io,re,runpy,zipfile
R=Path.cwd(); BASE='SpotifyControl-Track-Transition-Direct-Patch-Acceptance-v0.5.1.zip'; OUT='SpotifyControl-Track-Transition-Silent-Targeted-Acceptance-v0.5.2.zip'
def h(b): return hashlib.sha256(b).hexdigest()
def span(s,name):
    a=s.index('function '+name+' {'); b=s.find('\nfunction ',a+1)
    if b<0:b=s.find('\ntry{',a+1)
    assert b>a,name
    return a,b
def func(s,name):
    a,b=span(s,name); return s[a:b].strip()
def replace_func(s,name,new):
    a,b=span(s,name); return s[:a]+new.rstrip()+'\n\n'+s[b+1:]
def remove_func(s,name):
    a,b=span(s,name); return s[:a]+s[b+1:]
def r1(s,a,b):
    assert s.count(a)==1,(a[:100],s.count(a)); return s.replace(a,b,1)
def rr1(s,pattern,repl):
    out,n=re.subn(pattern,repl,s,count=1,flags=re.M); assert n==1,(pattern,n); return out

def parse_functions(text):
    names=re.findall(r'(?m)^function\s+([A-Za-z0-9_-]+)\s*\{',text)
    return {n:func(text,n) for n in names}

runpy.run_path('validation/performance-phase2-v0.5.1/build_v051.py',run_name='__main__')
raw=(R/BASE).read_bytes(); assert len(raw)==98457 and h(raw)=='db2d8836a7d865376c38688dfc3467b999e18437215ef4d5c44b7b9829cd0e11'
with zipfile.ZipFile(io.BytesIO(raw)) as z: files={n:z.read(n) for n in z.namelist()}
old=files['track-transition-direct-patch-acceptance.ps1'].decode('utf-8-sig').replace('\r\n','\n'); s=old
media=(R/'validation/performance-phase2-v0.5.2/runtime_media_v052.ps1.inc').read_text(encoding='utf-8').replace('\r\n','\n').strip()
orch=(R/'validation/performance-phase2-v0.5.2/runtime_orchestration_v052.ps1.inc').read_text(encoding='utf-8').replace('\r\n','\n').strip()
M=parse_functions(media); O=parse_functions(orch)

# Load the WinRT bridge before any function can resolve WindowsRuntimeSystemExtensions.
s=r1(s,'function Write-LabLog {',"try{Add-Type -AssemblyName System.Runtime.WindowsRuntime -ErrorAction Stop}catch{throw ('System.Runtime.WindowsRuntime is required for Spotify-targeted media control: '+$_.Exception.Message)}\n\nfunction Write-LabLog {")
# Remove the legacy global-key implementation completely, then place targeted media helpers in its slot.
a,_=span(s,'Add-MediaKeyType'); _,b=span(s,'Send-MediaKey'); s=s[:a]+media+'\n\n'+s[b+1:]
# Replace runtime orchestration functions and insert the new silent-refresh helper.
for name in ['Stop-SpotifyForVariant','Prepare-Variant','Measure-TransitionCondition','Analyze-Transitions','Get-WorkloadPolicy','Build-TextReport']:
    s=replace_func(s,name,O[name])
a,_=span(s,'Stop-SpotifyForVariant'); s=s[:a]+O['Refresh-SpotifySilentForTest']+'\n\n'+s[a:]

# Short, non-overlapping 3-transition workload.
s=rr1(s,r'(?m)^\s*\[int\]\$TransitionSeconds\s*=\s*90,','    [int]$TransitionSeconds = 27,')
s=rr1(s,r'(?m)^\s*\[int\]\$PlaybackWarmupSeconds\s*=\s*\d+,','    [int]$PlaybackWarmupSeconds = 8,')
s=r1(s,'$NextOffsets = @(15,30,45,60,75)','$NextOffsets = @(5,13,21)')
s=r1(s,"if($TransitionSeconds -lt 85){throw 'TransitionSeconds must be at least 85 to cover all five NEXT events.'}","if($TransitionSeconds -lt 26){throw 'TransitionSeconds must be at least 26 to cover all three verified Spotify NEXT events.'}")

# Measurement identity must describe the aligned runtime, not the preflight version.
anchor='$script:ProductionAlignment=Align-ReleasedProductionBaseline -Accepted $accepted'
s=r1(s,anchor,anchor+"\n    $script:MeasurementBaseline=[pscustomobject]@{baseline_kind='current-v0619-r8';spotify_control_version='0.6.19';addon_manager_version='0.6.5-r8';spotify_version=$accepted.spotify_version;spicetify_version=$accepted.spicetify_version;hashes=$script:ProductionAlignment.hashes}")
s=r1(s,'accepted_baseline=$accepted;production_alignment=$script:ProductionAlignment;','accepted_baseline=$script:MeasurementBaseline;production_alignment=$script:ProductionAlignment;')

# Self-test policy names follow the verified-targeted workload policy.
s=s.replace("$highPolicy.status -ne 'active-response'","$highPolicy.status -ne 'spotify-transition-verified'")
s=s.replace("$singleLow.status -ne 'low-response-accepted'","$singleLow.status -ne 'low-response-verified'")
# Runtime/report text and evidence contract.
s=s.replace('v0.5.1','v0.5.2').replace('v051','v052')
s=s.replace('One integrated run: 5 conditions x 5 automatic NEXT transitions.','One integrated run: 5 conditions x 3 verified Spotify-targeted NEXT transitions.')
s=s.replace('Do not touch Spotify until the profiler finishes.','Spotify stays silent during measurement. You may use other apps and play other media; do not interact with Spotify itself.')
s=s.replace('all five NEXT keys were emitted.','all targeted Spotify NEXT transitions were metadata-confirmed.')
s=s.replace("workload_canary='BASELINE_A/B require at least 4/5 NEXT windows >= 1.5% total machine CPU; non-baseline low response is retained when Spotify survives and all five NEXT events are emitted'","workload_canary='All recorded NEXT events must be Spotify-targeted and metadata/position-confirmed; BASELINE_A/B require at least 2/3 verified transition windows >= 1.5% Spotify-process CPU.'")
s=r1(s,"mutation_engine='exact-active-xpui-direct-extension-byte-patches';direct_patch_preflight=$script:DirectPatchPreflight;","media_control='spotify-targeted-gsmtc';global_media_keys_used=$false;spotify_audio_muted_during_workload=$true;other_media_apps_controlled=$false;mutation_engine='exact-active-xpui-direct-extension-byte-patches';direct_patch_preflight=$script:DirectPatchPreflight;")
# Add verified count to each analysis object in orchestration output metadata without changing patch engine semantics.
s=s.replace("Add-Member -InputObject $a -NotePropertyName workload_policy_status -NotePropertyValue ([string]$policy.status) -Force;Add-Member -InputObject $a -NotePropertyName min_spotify_process_count", "Add-Member -InputObject $a -NotePropertyName workload_policy_status -NotePropertyValue ([string]$policy.status) -Force;Add-Member -InputObject $a -NotePropertyName verified_spotify_transitions -NotePropertyValue ([int]$m.verified_spotify_transitions) -Force;Add-Member -InputObject $a -NotePropertyName min_spotify_process_count")

# No legacy global key surface may survive anywhere in the integrated profiler.
for forbidden in ['keybd_event','SpotifyControlMediaKeys','Send-MediaKey','[byte]0xB0','[byte]0xB3']:
    assert forbidden.lower() not in s.lower(),forbidden
for required in ['TrySkipNextAsync','TryPlayAsync','TryPauseAsync','SPOTIFY_NEXT_CONFIRMED','SpotifyControlAudioSession','CaptureAndMute','MeasurementBaseline','global_media_keys_used=$false']:
    assert required in s,required
# Exact patch engine/targets remain unchanged.
assert h(files['apply-direct-extension-patches.ps1'])=='486254bc032bbcb2380f69ba01470bb2bda2e23718cc7bbaef1063fdb18c1803'
assert h(files['targets.json'])=='9b49d43bb8ff568f9e1a4f7009e2958edce0f77b857d948e563b81bb514aefa3'

script=('\r\n'.join(s.split('\n'))).encode('utf-8-sig')
readme=("Spotify Control Track Transition Silent Targeted Acceptance v0.5.2\r\n\r\n"
        "This replaces the contaminated global-media-key profiler. Spotify is controlled only through its own Windows media session and only Spotify audio sessions are muted during measurement. Other applications are not controlled, so you may keep watching/listening to other media. Do not interact with Spotify itself while the test runs.\r\n\r\n"
        "The run uses 5 conditions x 3 metadata-confirmed Spotify transitions with short non-overlapping windows. Any unconfirmed Spotify transition invalidates the run. Exact extension-byte eligibility, patch rollback, xpui/config restore, protected persistence backup, and resident restoration remain fail-closed.\r\n").encode('utf-8')
cmd=("@echo off\r\nsetlocal\r\necho Spotify Control Track Transition Silent Targeted Acceptance v0.5.2\r\necho -----------------------------------------------------------------\r\necho Spotify will be muted. Other videos/audio may keep playing normally.\r\necho Do not interact with Spotify while this test runs.\r\necho.\r\npowershell.exe -NoProfile -ExecutionPolicy Bypass -File \"%~dp0track-transition-direct-patch-acceptance.ps1\" -Action Run\r\nset \"EC=%ERRORLEVEL%\"\r\necho.\r\nif not \"%EC%\"==\"0\" echo FAILED. Do not rerun automatically; provide the v0.5.2 error log.\r\npause\r\nexit /b %EC%\r\n").encode('ascii')
selftest=("@echo off\r\nsetlocal\r\npowershell.exe -NoProfile -ExecutionPolicy Bypass -File \"%~dp0track-transition-direct-patch-acceptance.ps1\" -Action SelfTest\r\nexit /b %ERRORLEVEL%\r\n").encode('ascii')
outfiles={'README.md':readme,'RUN_TRACK_TRANSITION_SILENT_TARGETED_ACCEPTANCE.cmd':cmd,'SELFTEST.cmd':selftest,'apply-direct-extension-patches.ps1':files['apply-direct-extension-patches.ps1'],'targets.json':files['targets.json'],'track-transition-direct-patch-acceptance.ps1':script}
co=['README.md','RUN_TRACK_TRANSITION_SILENT_TARGETED_ACCEPTANCE.cmd','SELFTEST.cmd','apply-direct-extension-patches.ps1','targets.json','track-transition-direct-patch-acceptance.ps1']
outfiles['SHA256SUMS.txt']=''.join(f'{h(outfiles[x])}  {x}\r\n' for x in co).encode('ascii')
order=['README.md','RUN_TRACK_TRANSITION_SILENT_TARGETED_ACCEPTANCE.cmd','SELFTEST.cmd','SHA256SUMS.txt','apply-direct-extension-patches.ps1','targets.json','track-transition-direct-patch-acceptance.ps1']
b=io.BytesIO()
with zipfile.ZipFile(b,'w',compression=zipfile.ZIP_STORED) as z:
    for x in order:
        zi=zipfile.ZipInfo(x,date_time=(2026,10,26,1,50,0));zi.compress_type=zipfile.ZIP_STORED;zi.create_system=0;z.writestr(zi,outfiles[x])
out=b.getvalue();(R/OUT).write_bytes(out)
print('PHASE2_V052_MEDIA_HELPER',len(media.encode()),h(media.encode()))
print('PHASE2_V052_ORCHESTRATION',len(orch.encode()),h(orch.encode()))
print('PHASE2_V052_SCRIPT',len(script),h(script))
print('PHASE2_V052_PACKAGE',len(out),h(out))
