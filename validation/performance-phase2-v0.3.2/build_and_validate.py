from pathlib import Path
import base64, hashlib, io, os, runpy, shutil, subprocess, zipfile

V031_COMMIT='a6e9fe489c4535ddfcefe85a0017c8dd36debed6'
V031_ZIP_SIZE=17946
V031_ZIP_SHA='a0502408df6ff313f434943671db2d00a147f812b18562f5e346f292412921f8'
FINAL_SIZE=18630
FINAL_SHA='384469d4b554a08e9c6d43e4efd5a548bb8f1bc7733dc0bacdc25798e640b3c7'
SCRIPT_SIZE=54075
SCRIPT_SHA='10297a7308c1f758afeef9b0e595ce7f5c21520d5c20ee696b223cf1bf72f77f'

def sha(b): return hashlib.sha256(b).hexdigest()
def replace_once(s, old, new):
    if s.count(old)!=1: raise AssertionError((old,s.count(old)))
    return s.replace(old,new,1)

def get_v031_zip():
    override=os.environ.get('V031_SOURCE_ZIP')
    if override:
        raw=Path(override).read_bytes()
    else:
        root=Path('_v031_anchor'); shutil.rmtree(root,ignore_errors=True)
        (root/'validation/performance-phase2-v0.3.1/payload').mkdir(parents=True)
        paths=['validation/performance-phase2-v0.3.1/build_and_validate.py']+[f'validation/performance-phase2-v0.3.1/payload/chunk-{i:03d}.txt' for i in range(6)]
        for rel in paths:
            data=subprocess.check_output(['git','show',f'{V031_COMMIT}:{rel}'])
            dst=root/rel; dst.parent.mkdir(parents=True,exist_ok=True); dst.write_bytes(data)
        cwd=Path.cwd(); os.chdir(root)
        try: runpy.run_path('validation/performance-phase2-v0.3.1/build_and_validate.py',run_name='__main__')
        finally: os.chdir(cwd)
        raw=(root/'SpotifyControl-Track-Transition-Isolation-v0.3.1.zip').read_bytes()
    assert len(raw)==V031_ZIP_SIZE,len(raw); assert sha(raw)==V031_ZIP_SHA,sha(raw)
    return raw

raw031=get_v031_zip()
root=Path('phase2-v032'); shutil.rmtree(root,ignore_errors=True); root.mkdir()
with zipfile.ZipFile(io.BytesIO(raw031)) as z:
    assert z.testzip() is None
    for n in z.namelist(): (root/n).write_bytes(z.read(n))

ps=root/'track-transition-isolation.ps1'
s=ps.read_text(encoding='utf-8-sig')
s=replace_once(s,'# Spotify Control Track Transition Isolation v0.3.1','# Spotify Control Track Transition Isolation v0.3.2')
s=replace_once(s,'$Version = "0.3.1"','$Version = "0.3.2"')
s=replace_once(s,'    if(@(Get-Process Spotify -ErrorAction SilentlyContinue).Count -gt 0){throw "Close Spotify completely, including tray, before starting Phase 2."}\n','')
s=replace_once(s,"""    $accepted=Assert-AcceptedRuntimeBaseline\n    Suspend-Resident\n    if(-not(Wait-ControlWorkersIdle 10)){throw 'A Spotify Control worker became active after resident suspension.'}\n\n    $stamp=Get-Date -Format 'yyyyMMdd-HHmmss';""","""    $accepted=Assert-AcceptedRuntimeBaseline\n    Suspend-Resident\n    if(-not(Wait-ControlWorkersIdle 10)){throw 'A Spotify Control worker became active after resident suspension.'}\n    $preflightSpotifyCount=@(Get-Process Spotify -ErrorAction SilentlyContinue).Count\n    if($preflightSpotifyCount -gt 0){\n        Write-LabLog ("Detected {0} residual Spotify process(es) after accepted-state checks; closing them before any xpui mutation." -f $preflightSpotifyCount) 'WARN'\n        Stop-SpotifyForVariant\n        if(@(Get-Process Spotify -ErrorAction SilentlyContinue).Count -gt 0){throw 'Residual Spotify process cleanup failed before xpui mutation.'}\n        Write-LabLog 'Residual Spotify processes closed before any xpui mutation.' 'OK'\n    }\n\n    $stamp=Get-Date -Format 'yyyyMMdd-HHmmss';""")
s=replace_once(s,'accepted_baseline=$accepted;sample_interval_ms=$SampleIntervalMs','accepted_baseline=$accepted;preflight_spotify_processes_autoclosed=$preflightSpotifyCount;sample_interval_ms=$SampleIntervalMs')
s=replace_once(s,'$l.Add("- Spicetify backup/apply/restore and config mutation were never invoked.")','$l.Add(("- Startup residual Spotify processes auto-closed before xpui mutation: {0}" -f $Report.preflight_spotify_processes_autoclosed));$l.Add("- Spicetify backup/apply/restore and config mutation were never invoked.")')
needle="""    }finally{Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue}\n    Write-LabLog \"Track transition isolation v$Version direct-xpui self-test passed; production paths were not mutated.\" 'OK'\n    Write-Host 'SELFTEST PASS: direct-xpui hook inventory/matrix, UTF-8 BOM+CRLF preservation, exact tree restore, percentile/process/transition math.'\n"""
rep="""    }finally{Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue}\n    if($env:SPOTIFYCONTROL_TEST_RESIDUAL_CLEANUP -eq '1'){\n        $fakeRoot=Join-Path ([IO.Path]::GetTempPath()) ('spotify-control-residual-selftest-'+[Guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Force -Path $fakeRoot|Out-Null\n        try{\n            $fakeExe=Join-Path $fakeRoot 'Spotify.exe';Copy-Item -LiteralPath (Join-Path $PSHOME 'powershell.exe') -Destination $fakeExe -Force\n            $fake=Start-Process -FilePath $fakeExe -ArgumentList @('-NoProfile','-Command','Start-Sleep -Seconds 60') -PassThru\n            Start-Sleep -Milliseconds 500\n            if(@(Get-Process Spotify -ErrorAction SilentlyContinue).Count -lt 1){throw 'Residual Spotify cleanup fixture could not create a Spotify-named process.'}\n            Stop-SpotifyForVariant\n            if(@(Get-Process Spotify -ErrorAction SilentlyContinue).Count -ne 0){throw 'Residual Spotify cleanup fixture left a Spotify-named process running.'}\n            Write-Host 'SELFTEST PASS: residual Spotify process cleanup before xpui mutation.'\n        }finally{\n            @(Get-Process Spotify -ErrorAction SilentlyContinue)|Where-Object{$_.Path -eq $fakeExe}|Stop-Process -Force -ErrorAction SilentlyContinue\n            Remove-Item -LiteralPath $fakeRoot -Recurse -Force -ErrorAction SilentlyContinue\n        }\n    }\n    Write-LabLog \"Track transition isolation v$Version direct-xpui self-test passed; production paths were not mutated.\" 'OK'\n    Write-Host 'SELFTEST PASS: direct-xpui hook inventory/matrix, UTF-8 BOM+CRLF preservation, exact tree restore, percentile/process/transition math.'\n"""
s=replace_once(s,needle,rep)
ps.write_text(s,encoding='utf-8-sig',newline='')

readme=root/'README.md'; r=readme.read_text(encoding='utf-8')
r=r.replace('v0.3.1','v0.3.2')
r=replace_once(r,'Important v0.3.2 change\n-----------------------\nv0.3.0','Important v0.3.2 change\n-----------------------\nv0.3.1 could stop before profiling if Windows left any `Spotify.exe` process after the user had already exited Spotify.\nv0.3.2 keeps the same direct-xpui safety model, but accepted-state checks no longer require zero Spotify processes. It suspends the resident first, then closes any residual Spotify process before any xpui mutation.\n\nv0.3.0')
r=replace_once(r,'3. Fully exit Spotify, including the tray icon.','3. Exit Spotify normally. If a residual tray/helper Spotify process remains, v0.3.2 closes it automatically after suspending the Spotify Control resident and before any xpui mutation.')
r=replace_once(r,'- Spotify close is attempted normally first. If the client remains in tray, process termination is used only after playback has been paused and before the next xpui variant is written.','- Spotify close is attempted normally first. If a residual tray/helper process remains at startup or between variants, process termination is used only after playback has been paused and before any xpui variant is written.\n- A startup residual Spotify process is no longer a preflight failure: the resident is suspended first, then the residual client is closed before the profiler backs up or mutates active xpui.')
readme.write_text(r,encoding='utf-8',newline='\n')

runner=root/'RUN_TRACK_TRANSITION_ISOLATION.cmd'; c=runner.read_text(encoding='utf-8')
c=c.replace('v0.3.1','v0.3.2')
c=replace_once(c,'echo   2. PAUSE playback on a normal track, then fully EXIT Spotify including tray.','echo   2. PAUSE playback on a normal track, then EXIT Spotify normally.\necho      If a tray/helper process remains, v0.3.2 closes it safely before xpui mutation.')
runner.write_text(c,encoding='utf-8',newline='\r\n')

names=['README.md','RUN_TRACK_TRANSITION_ISOLATION.cmd','SELFTEST.cmd','track-transition-isolation.ps1']
sums=''.join(f"{sha((root/n).read_bytes())}  {n}\n" for n in sorted(names)); (root/'SHA256SUMS.txt').write_text(sums,encoding='ascii',newline='\n')
final=Path('SpotifyControl-Track-Transition-Isolation-v0.3.2.zip')
if final.exists(): final.unlink()
with zipfile.ZipFile(final,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
    for n in sorted(names+['SHA256SUMS.txt']):
        data=(root/n).read_bytes(); zi=zipfile.ZipInfo(n,date_time=(2026,10,25,1,32,0)); zi.create_system=3; zi.compress_type=zipfile.ZIP_DEFLATED; zi.external_attr=0o644<<16; z.writestr(zi,data,compress_type=zipfile.ZIP_DEFLATED,compresslevel=9)
final_raw=final.read_bytes(); assert len(final_raw)==FINAL_SIZE,len(final_raw); assert sha(final_raw)==FINAL_SHA,sha(final_raw)
assert len(ps.read_bytes())==SCRIPT_SIZE; assert sha(ps.read_bytes())==SCRIPT_SHA
with zipfile.ZipFile(final) as z:
    assert z.testzip() is None
    for line in z.read('SHA256SUMS.txt').decode('ascii').splitlines():
        h,n=line.split('  ',1); assert sha(z.read(n))==h
print('PHASE2_V032_BUILD_PASS',len(final_raw),sha(final_raw))
print('PHASE2_V032_SCRIPT',len(ps.read_bytes()),sha(ps.read_bytes()))
