from pathlib import Path
import hashlib,io,re,runpy,zipfile
R=Path.cwd()
BASE='SpotifyControl-Track-Transition-Silent-Targeted-Acceptance-v0.5.2.zip'
OUT='SpotifyControl-Track-Transition-Background-Guarded-Acceptance-v0.5.3.zip'
BASE_SIZE=115926
BASE_SHA='8956f1a2be3628d9e7f8b9efa0c3aaf5f4ca9e633037a6a8f9460e575fc7cc31'

def h(b): return hashlib.sha256(b).hexdigest()
def span(s,name):
    a=s.index('function '+name+' {')
    b=s.find('\nfunction ',a+1)
    if b<0:b=s.find('\ntry{',a+1)
    if b<0:b=len(s)
    assert b>a,name
    return a,b
def func(s,name):
    a,b=span(s,name); return s[a:b].strip()
def replace_func(s,name,new):
    a,b=span(s,name); tail='' if b==len(s) else s[b+1:]
    return s[:a]+new.rstrip()+'\n\n'+tail
def remove_func(s,name):
    a,b=span(s,name); tail='' if b==len(s) else s[b+1:]
    return s[:a]+tail
def r1(s,a,b):
    assert s.count(a)==1,(a[:120],s.count(a))
    return s.replace(a,b,1)

# Rebuild the exact accepted v0.5.2 package first; v0.5.3 is a deterministic delta.
runpy.run_path('validation/performance-phase2-v0.5.2/build_v052_final.py',run_name='__main__')
raw=(R/BASE).read_bytes()
assert len(raw)==BASE_SIZE,(len(raw),BASE_SIZE)
assert h(raw)==BASE_SHA,(h(raw),BASE_SHA)
with zipfile.ZipFile(io.BytesIO(raw)) as z:
    files={n:z.read(n) for n in z.namelist()}
old=files['track-transition-direct-patch-acceptance.ps1'].decode('utf-8-sig').replace('\r\n','\n')
s=old
helper=(R/'validation/performance-phase2-v0.5.3/runtime_background_v053.ps1.inc').read_text(encoding='utf-8').replace('\r\n','\n').strip()
orch=(R/'validation/performance-phase2-v0.5.3/runtime_orchestration_v053.ps1.inc').read_text(encoding='utf-8').replace('\r\n','\n').strip()
stop=func(orch,'Stop-SpotifyForVariant'); prep=func(orch,'Prepare-Variant')

# Retire the v0.5.2 polling-only audio implementation completely.
for name in ['Refresh-SpotifySilentForTest','Set-SpotifySilentForTest','Restore-SpotifyAudioForTest','Add-SpotifyAudioSessionType']:
    s=remove_func(s,name)
s=replace_func(s,'Stop-SpotifyForVariant',stop)
s=replace_func(s,'Prepare-Variant',prep)
a,_=span(s,'Stop-SpotifyForVariant')
s=s[:a]+helper+'\n\n'+s[a:]

# Version/report identity and user-facing behavior.
s=r1(s,'$Version = "0.5.2"','$Version = "0.5.3"')
s=s.replace('v0.5.2','v0.5.3').replace('v052','v053')
s=s.replace('Spotify Control Track Transition Silent Targeted Acceptance Report','Spotify Control Track Transition Background Guarded Acceptance Report')
s=s.replace('Media control: Spotify-targeted Windows media session; global media keys used=False; Spotify audio muted during workload=True; other applications untouched=True',
            'Media control: Spotify-targeted Windows media session; global media keys used=False; pre-armed Spotify-only CoreAudio guard=True; other applications untouched=True; Spotify startup hidden=True; measurement window non-minimized behind user=True')
s=s.replace("$l.Add('- Spotify audio sessions alone were muted during workload and their original mute/volume state was restored before shutdown; other apps were not changed.');$l.Add('- Every recorded transition required Spotify media metadata/position to confirm the Spotify track changed.');",
            "$l.Add('- A Spotify-only CoreAudio session-notification guard was armed before Play, then backed by a 5ms exact-session poll; captured Spotify sessions were muted and restored exactly; other apps were not changed.');$l.Add('- Spotify starts hidden, then its normal non-minimized window is placed behind the user foreground app without activation so renderer behavior is not intentionally minimized/background-throttled.');$l.Add('- Every recorded transition required Spotify media metadata/position to confirm the Spotify track changed.');")

meta_old="media_control='spotify-targeted-gsmtc';global_media_keys_used=$false;spotify_audio_muted_during_workload=$true;other_media_apps_controlled=$false;"
meta_new="media_control='spotify-targeted-gsmtc';global_media_keys_used=$false;spotify_audio_muted_during_workload=$true;spotify_audio_guard='prearmed-session-notification-plus-5ms-poll';other_media_apps_controlled=$false;spotify_window_mode='startup-hidden-then-behind-user-noactivate';spotify_minimized_during_measurement=$false;"
s=r1(s,meta_old,meta_new)

# Fail-closed static invariants.
for forbidden in ['keybd_event','SpotifyControlMediaKeys','Send-MediaKey','[byte]0xB0','[byte]0xB3',
                  'Set-SpotifySilentForTest','SpotifyControlAudioSession','SpotifyAudioOriginalStates']:
    assert forbidden.lower() not in s.lower(),forbidden
for required in ['RegisterSessionNotification','WaitForSpotifyCapture(5000,5)','Start-Process -FilePath $SpotifyExe -WindowStyle Hidden',
                 'GetBestUserForegroundWindow','SW_SHOWNOACTIVATE','HWND_BOTTOM','Show-SpotifyBehindUserForMeasurement',
                 "spotify_minimized_during_measurement=$false",'TrySkipNextAsync','SPOTIFY_NEXT_CONFIRMED']:
    assert required in s,required
assert s.count('function Restore-SpotifyAudioForTest {')==1
assert s.count('function Refresh-SpotifySilentForTest {')==1
assert s.count('function Stop-SpotifyForVariant {')==1
assert s.count('function Prepare-Variant {')==1

# Exact patch engine/targets remain unchanged.
assert h(files['apply-direct-extension-patches.ps1'])=='486254bc032bbcb2380f69ba01470bb2bda2e23718cc7bbaef1063fdb18c1803'
assert h(files['targets.json'])=='9b49d43bb8ff568f9e1a4f7009e2958edce0f77b857d948e563b81bb514aefa3'

script=('\r\n'.join(s.split('\n'))).encode('utf-8-sig')
readme=("Spotify Control Track Transition Background Guarded Acceptance v0.5.3\r\n\r\n"
        "This fixes the v0.5.2 startup failure where a paused Spotify process had no CoreAudio session yet. v0.5.3 arms a Spotify-only CoreAudio session-notification guard before issuing Play, then checks every 5 ms for the exact Spotify session. The new session is muted as it appears; other applications are not muted or controlled.\r\n\r\n"
        "Spotify startup is hidden so its window should not pop over your work. During measurement the Spotify window is deliberately NOT minimized or left truly hidden, because that can trigger Chromium/Electron background or occlusion throttling and invalidate renderer measurements. Instead the normal window is shown without activation and placed behind the user's foreground application. You may keep using other apps and playing other media; do not interact with Spotify itself.\r\n\r\n"
        "The workload remains 5 conditions x 3 metadata-confirmed Spotify transitions. Exact extension-byte eligibility, rollback, xpui/config restore, protected persistence backup, and resident restoration remain fail-closed.\r\n").encode('utf-8')
cmd=("@echo off\r\nsetlocal\r\necho Spotify Control Track Transition Background Guarded Acceptance v0.5.3\r\necho ---------------------------------------------------------------------\r\necho Spotify starts hidden and is kept behind your foreground app during measurement.\r\necho Spotify alone is muted; other videos/audio may keep playing normally.\r\necho Do not interact with Spotify while this test runs.\r\necho.\r\npowershell.exe -NoProfile -ExecutionPolicy Bypass -File \"%~dp0track-transition-direct-patch-acceptance.ps1\" -Action Run\r\nset \"EC=%ERRORLEVEL%\"\r\necho.\r\nif not \"%EC%\"==\"0\" echo FAILED. Do not rerun automatically; provide the v0.5.3 error log.\r\npause\r\nexit /b %EC%\r\n").encode('ascii')
selftest=("@echo off\r\nsetlocal\r\npowershell.exe -NoProfile -ExecutionPolicy Bypass -File \"%~dp0track-transition-direct-patch-acceptance.ps1\" -Action SelfTest\r\nexit /b %ERRORLEVEL%\r\n").encode('ascii')
outfiles={
    'README.md':readme,
    'RUN_TRACK_TRANSITION_BACKGROUND_GUARDED_ACCEPTANCE.cmd':cmd,
    'SELFTEST.cmd':selftest,
    'apply-direct-extension-patches.ps1':files['apply-direct-extension-patches.ps1'],
    'targets.json':files['targets.json'],
    'track-transition-direct-patch-acceptance.ps1':script,
}
co=['README.md','RUN_TRACK_TRANSITION_BACKGROUND_GUARDED_ACCEPTANCE.cmd','SELFTEST.cmd','apply-direct-extension-patches.ps1','targets.json','track-transition-direct-patch-acceptance.ps1']
outfiles['SHA256SUMS.txt']=''.join(f'{h(outfiles[x])}  {x}\r\n' for x in co).encode('ascii')
order=['README.md','RUN_TRACK_TRANSITION_BACKGROUND_GUARDED_ACCEPTANCE.cmd','SELFTEST.cmd','SHA256SUMS.txt','apply-direct-extension-patches.ps1','targets.json','track-transition-direct-patch-acceptance.ps1']
b=io.BytesIO()
with zipfile.ZipFile(b,'w',compression=zipfile.ZIP_STORED) as z:
    for x in order:
        zi=zipfile.ZipInfo(x,date_time=(2026,10,26,2,25,0));zi.compress_type=zipfile.ZIP_STORED;zi.create_system=0;z.writestr(zi,outfiles[x])
out=b.getvalue();(R/OUT).write_bytes(out)
print('PHASE2_V053_BACKGROUND_HELPER',len(helper.encode()),h(helper.encode()))
print('PHASE2_V053_ORCHESTRATION',len(orch.encode()),h(orch.encode()))
print('PHASE2_V053_SCRIPT',len(script),h(script))
print('PHASE2_V053_PACKAGE',len(out),h(out))
