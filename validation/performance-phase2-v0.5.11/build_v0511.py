from pathlib import Path
import zipfile, io, hashlib, re, subprocess, sys, tempfile, shutil

V0510_COMMIT='73476df74fae955257ee81d5b7bc740ef05cd529'
V0510_PACKAGE='SpotifyControl-Production-Lazy-Overlay-Media-Command-Free-Idle-Revalidation-v0.5.10.zip'
OUT=Path.cwd()/'SpotifyControl-Production-Lazy-Overlay-Media-Command-Free-Idle-Revalidation-v0.5.11.zip'
BASE_ZIP=(165031,'ad8d9f7149a82073131beef63038fd8fa58d2fb40a33d3b061826cf7b0235aa8')
BASE_PS1=(131328,'928fc049710a026d4d1c7c28c5c92273a3f914d4f5c66f7be8df8dc0642c562a')
OUT_ZIP=(166484,'b0783be52c08b8ea444328b3eb850f10dd374fff87e360e6a8b4d5bc3e68f8ae')
OUT_PS1=(132421,'7530bd421864ff0f67280f35c612a3b3954050f3aa2c086c4750cb9d85e7aeb1')
OVERLAY={
'overlay/apply-overlay.ps1':(16748,'053a597e834aab959a588350160ce81046ceda66e2a2ac233eeff8af78fea544'),
'overlay/lazy-custom-app-loader.js':(10600,'c38af0f6266747f50d2a0c05e9a49d5ffb34135738715fab6321ff4ae79623d9'),
'overlay/targets.json':(1756,'c255e53066abbd730467e0c1d92e81dd907e1ea2f245daf6f0d080d2239fea35')}

def ident(b,e,label):
    h=hashlib.sha256(b).hexdigest()
    if len(b)!=e[0] or h!=e[1]: raise RuntimeError(f'{label} drift: {len(b)}/{h}')

tmp=Path(tempfile.mkdtemp(prefix='spotify-v0511-')); wt=tmp/'v0510'
try:
    subprocess.run(['git','cat-file','-e',V0510_COMMIT+'^{commit}'],check=True)
    subprocess.run(['git','worktree','add','--detach',str(wt),V0510_COMMIT],check=True)
    subprocess.run([sys.executable,str(wt/'validation/performance-phase2-v0.5.10/build_v0510.py')],cwd=wt,check=True)
    base=(wt/V0510_PACKAGE).read_bytes(); ident(base,BASE_ZIP,'v0.5.10 ZIP')
    with zipfile.ZipFile(io.BytesIO(base)) as z:
        names=z.namelist(); files={n:z.read(n) for n in names if n!='SHA256SUMS.txt'}
finally:
    if wt.exists(): subprocess.run(['git','worktree','remove','--force',str(wt)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    shutil.rmtree(tmp,ignore_errors=True)
ident(files['idle-overlay-media-command-free-revalidation.ps1'],BASE_PS1,'v0.5.10 PS1')
for n,e in OVERLAY.items(): ident(files[n],e,n)

def sha(b): return hashlib.sha256(b).hexdigest()
ps_name='idle-overlay-media-command-free-revalidation.ps1'
s=files[ps_name].decode('utf-8-sig')
s=s.replace('v0.5.10','v0.5.11').replace('V0510','V0511').replace('v0510','v0511')
s=s.replace('    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr hWnd);\r\n','')
s=s.replace('    public static bool ShowBehind(IntPtr hwnd, IntPtr restoreForeground) {\r\n','    public static bool ShowBehind(IntPtr hwnd) {\r\n')
s=s.replace('        if(restoreForeground!=IntPtr.Zero && IsWindow(restoreForeground)) { try { SetForegroundWindow(restoreForeground); } catch { } }\r\n','')
old='''function Show-SpotifyBehindUserForMeasurement {\r\n    Add-SpotifyBackgroundTypes\r\n    $fg=[IntPtr]::Zero\r\n    if($null -ne $script:UserForegroundWindow){$fg=[IntPtr]$script:UserForegroundWindow}\r\n    $n=0\r\n    foreach($hwnd in @(Get-SpotifyMainWindows)){if([SpotifyControlWindowHost]::ShowBehind($hwnd,$fg)){$n++}}\r\n    if($n -lt 1){throw 'Spotify main window was unavailable for hardened non-activating background placement.'}\r\n    if([SpotifyControlWindowHost]::IsSpotifyForeground()){throw 'Spotify unexpectedly owns foreground focus after WS_EX_NOACTIVATE background placement.'}\r\n    Write-LabLog 'Spotify window placed behind the user with WS_EX_NOACTIVATE; it cannot take keyboard focus while remaining normally windowed for renderer measurement.' 'OK'\r\n    return $n\r\n}'''
new='''function Show-SpotifyBehindUserForMeasurement {\r\n    Add-SpotifyBackgroundTypes\r\n    $settle=[Diagnostics.Stopwatch]::StartNew()\r\n    $stableChecks=0;$raceRecoveries=0;$n=0\r\n    while($settle.ElapsedMilliseconds -lt 3000){\r\n        $n=0\r\n        foreach($hwnd in @(Get-SpotifyMainWindows)){if([SpotifyControlWindowHost]::ShowBehind($hwnd)){$n++}}\r\n        if($n -lt 1){$stableChecks=0;Start-Sleep -Milliseconds 50;continue}\r\n        if([SpotifyControlWindowHost]::IsSpotifyForeground()){\r\n            $raceRecoveries++\r\n            [void](Hide-SpotifyWindowsForSetup)\r\n            $stableChecks=0\r\n            Start-Sleep -Milliseconds 80\r\n            continue\r\n        }\r\n        $stableChecks++\r\n        if($stableChecks -ge 5){break}\r\n        Start-Sleep -Milliseconds 60\r\n    }\r\n    $settle.Stop()\r\n    if($n -lt 1){throw 'Spotify main window was unavailable for hardened non-activating background placement.'}\r\n    if($stableChecks -lt 5 -or [SpotifyControlWindowHost]::IsSpotifyForeground()){throw 'Spotify remained foreground after bounded WS_EX_NOACTIVATE startup-race stabilization.'}\r\n    if($raceRecoveries -gt 0){\r\n        $script:FocusRaceRecoveries=[int]$script:FocusRaceRecoveries+$raceRecoveries\r\n        Write-LabLog ("Recovered transient Spotify startup foreground race without forcing focus to another application; hide/re-show cycles={0}; settle_ms={1}." -f $raceRecoveries,[int]$settle.ElapsedMilliseconds) 'WARN'\r\n    }\r\n    Write-LabLog 'Spotify window placed behind the user with WS_EX_NOACTIVATE after stable non-foreground confirmation; no SetForegroundWindow call is used.' 'OK'\r\n    return $n\r\n}'''
if old not in s: raise SystemExit('old Show function not found')
s=s.replace(old,new,1)
s=s.replace('$script:RoleCimLookups = 0\r\n','$script:RoleCimLookups = 0\r\n$script:FocusRaceRecoveries = 0\r\n',1)
s=s.replace("sampler_revision='v0.5.11-absolute-deadline-cached-sampler'","sampler_revision='v0.5.11-absolute-deadline-cached-sampler';focus_race_policy='bounded-hide-reshow-stabilization-no-foreground-forcing';focus_race_recoveries_total=[int]$script:FocusRaceRecoveries",1)
s=s.replace("spotify_focus_hardening='WS_EX_NOACTIVATE'","spotify_focus_hardening='WS_EX_NOACTIVATE + bounded startup-race stabilization; no SetForegroundWindow'",1)
s=s.replace("startup-hidden-then-behind-user-ws-ex-noactivate","startup-hidden-then-stably-nonforeground-ws-ex-noactivate")
needle="    Write-Host 'v0.5.11 keeps the cached CPU/process-role invariants and schedules samples against absolute 250ms deadlines so measurement work no longer accumulates into the sampling period.'"
if needle in s:
    s=s.replace(needle,needle+"\r\n    Write-Host 'v0.5.11 also absorbs transient Spotify startup foreground races by hide/re-show stabilization without forcing focus to another application.'",1)
s=s.replace('despite WS_EX_NOACTIVATE hardening.','despite WS_EX_NOACTIVATE startup-race stabilization.',1)
s=s.replace('# v0.5.11 ordering: audio guard is armed before Spotify launch. Measurement sends zero media commands.','# v0.5.11 ordering: audio guard is armed before Spotify launch. Measurement sends zero media commands; foreground startup races are stabilized without forcing another app.',1)
for x in ['TryPlayAsync','TryPauseAsync','TrySkipNextAsync','Invoke-SpotifyMediaCommand','keybd_event','Send-MediaKey','[byte]0xB0','[byte]0xB3']:
    if x.lower() in s.lower(): raise SystemExit('forbidden '+x)
if 'SetForegroundWindow(' in s: raise SystemExit('SetForegroundWindow call/declaration survived')
for x in ['$stableChecks -ge 5','Hide-SpotifyWindowsForSetup','settle.ElapsedMilliseconds -lt 3000','FocusRaceRecoveries','ShowBehind($hwnd)']:
    if x not in s: raise SystemExit('missing '+x)
files[ps_name]=b'\xef\xbb\xbf'+s.encode('utf-8')
for n in ['README.md','RUN_MEDIA_COMMAND_FREE_IDLE_REVALIDATION.cmd','SELFTEST.cmd']:
    txt=files[n].decode('utf-8',errors='strict')
    txt=txt.replace('v0.5.10','v0.5.11').replace('v0510','v0511').replace('V0510','V0511')
    if n=='README.md':
        extra='- v0.5.11 handles transient Spotify startup foreground races by hiding Spotify, re-showing it with WS_EX_NOACTIVATE at the bottom of Z-order, and requiring repeated non-foreground confirmation. It never calls SetForegroundWindow on another application.\r\n'
        marker='Safety:\r\n'
        txt=txt.replace(marker,marker+extra,1)
    if n=='RUN_MEDIA_COMMAND_FREE_IDLE_REVALIDATION.cmd':
        line='echo v0.5.11 uses absolute 250ms sample deadlines so profiler work no longer accumulates into the interval.\r\n'
        txt=txt.replace(line,line+'echo v0.5.11 also stabilizes transient Spotify startup focus races without forcing focus to another app.\r\n',1)
    files[n]=txt.encode('utf-8')
order=[n for n in names if n!='SHA256SUMS.txt']
files['SHA256SUMS.txt']=("\n".join(f"{sha(files[n])}  {n}" for n in order)+"\n").encode('ascii')
order.append('SHA256SUMS.txt')
b=io.BytesIO()
with zipfile.ZipFile(b,'w',compression=zipfile.ZIP_STORED) as z:
    for n in order:
        i=zipfile.ZipInfo(n,(2026,10,26,0,0,0)); i.compress_type=zipfile.ZIP_STORED;i.create_system=0;i.external_attr=0;i.flag_bits=0
        z.writestr(i,files[n])
pkg=b.getvalue();ident(files[ps_name],OUT_PS1,'v0.5.11 PS1');ident(pkg,OUT_ZIP,'v0.5.11 ZIP');OUT.write_bytes(pkg)
print('PHASE2_V0511_SCRIPT_PASS',len(files[ps_name]),sha(files[ps_name]));print('PHASE2_V0511_PACKAGE_PASS',len(pkg),sha(pkg))
