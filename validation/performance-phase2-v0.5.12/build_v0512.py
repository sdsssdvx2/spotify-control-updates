from pathlib import Path
import zipfile, io, hashlib, subprocess, sys, tempfile, shutil

V0511_COMMIT='b8da941cf524123460c345005d6f53761c281dad'
V0511_PACKAGE='SpotifyControl-Production-Lazy-Overlay-Media-Command-Free-Idle-Revalidation-v0.5.11.zip'
OUT=Path.cwd()/'SpotifyControl-Production-Lazy-Overlay-Media-Command-Free-Idle-Revalidation-v0.5.12.zip'
BASE_ZIP=(166484,'b0783be52c08b8ea444328b3eb850f10dd374fff87e360e6a8b4d5bc3e68f8ae')
BASE_PS1=(132421,'7530bd421864ff0f67280f35c612a3b3954050f3aa2c086c4750cb9d85e7aeb1')
OUT_ZIP=(168033,'e3251cef34165b62dfbfa0e0831f3d86910debd989b26ee0ad108a8e5de570f2')
OUT_PS1=(133970,'dac2fc82371c62bb8376285c8b1aa90cd04e900d025c36ee9a69e1f0e5e3ba40')
OVERLAY={
'overlay/apply-overlay.ps1':(16748,'053a597e834aab959a588350160ce81046ceda66e2a2ac233eeff8af78fea544'),
'overlay/lazy-custom-app-loader.js':(10600,'c38af0f6266747f50d2a0c05e9a49d5ffb34135738715fab6321ff4ae79623d9'),
'overlay/targets.json':(1756,'c255e53066abbd730467e0c1d92e81dd907e1ea2f245daf6f0d080d2239fea35')}

def ident(b,e,label):
    h=hashlib.sha256(b).hexdigest()
    if len(b)!=e[0] or h!=e[1]: raise RuntimeError(f'{label} drift: {len(b)}/{h}')

tmp=Path(tempfile.mkdtemp(prefix='spotify-v0512-')); wt=tmp/'v0511'
try:
    subprocess.run(['git','cat-file','-e',V0511_COMMIT+'^{commit}'],check=True)
    subprocess.run(['git','worktree','add','--detach',str(wt),V0511_COMMIT],check=True)
    subprocess.run([sys.executable,str(wt/'validation/performance-phase2-v0.5.11/build_v0511.py')],cwd=wt,check=True)
    base=(wt/V0511_PACKAGE).read_bytes(); ident(base,BASE_ZIP,'v0.5.11 ZIP')
    with zipfile.ZipFile(io.BytesIO(base)) as z:
        names=z.namelist(); files={n:z.read(n) for n in names if n!='SHA256SUMS.txt'}
finally:
    if wt.exists(): subprocess.run(['git','worktree','remove','--force',str(wt)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    shutil.rmtree(tmp,ignore_errors=True)
ident(files['idle-overlay-media-command-free-revalidation.ps1'],BASE_PS1,'v0.5.11 PS1')
for n,e in OVERLAY.items(): ident(files[n],e,n)
ps='idle-overlay-media-command-free-revalidation.ps1'
s=files[ps].decode('utf-8-sig')
s=s.replace('v0.5.11','v0.5.12').replace('V0511','V0512').replace('v0511','v0512')
s=s.replace('Spotify Control Media-Command-Free Idle Counterbalanced Revalidation v0.5.8','Spotify Control Media-Command-Free Idle Counterbalanced Revalidation v0.5.12')
needle='    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hWnd);\r\n'
insert=needle+'    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] static extern bool EnableWindow(IntPtr hWnd, [MarshalAs(UnmanagedType.Bool)] bool bEnable);\r\n    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] static extern bool IsWindowEnabled(IntPtr hWnd);\r\n'
if needle not in s: raise SystemExit('IsWindowVisible import needle missing')
s=s.replace(needle,insert,1)
old='''    public static bool Hide(IntPtr hwnd) {\r\n        if(hwnd==IntPtr.Zero || !IsWindow(hwnd)) return false;\r\n        HardenNoActivate(hwnd);\r\n        return ShowWindowAsync(hwnd,SW_HIDE);\r\n    }\r\n\r\n    public static bool ShowBehind(IntPtr hwnd) {\r\n        if(hwnd==IntPtr.Zero || !IsWindow(hwnd)) return false;\r\n        HardenNoActivate(hwnd);\r\n        ShowWindowAsync(hwnd,SW_SHOWNOACTIVATE);\r\n        bool ok=SetWindowPos(hwnd,HWND_BOTTOM,0,0,0,0,SWP_NOMOVE|SWP_NOSIZE|SWP_NOACTIVATE);\r\n        return ok;\r\n    }'''
new='''    static bool IsInputBlockedNoActivate(IntPtr hwnd) {\r\n        if(hwnd==IntPtr.Zero || !IsWindow(hwnd)) return false;\r\n        var ex=GetWindowLongPtr(hwnd,GWL_EXSTYLE).ToInt64();\r\n        return !IsWindowEnabled(hwnd) && (ex & WS_EX_NOACTIVATE)!=0;\r\n    }\r\n\r\n    public static IntPtr[] GetSpotifyAllWindows() {\r\n        var all=new List<IntPtr>();\r\n        EnumWindows(delegate(IntPtr hwnd,IntPtr lp) {\r\n            if(String.Equals(ProcessNameForWindow(hwnd),"Spotify",StringComparison.OrdinalIgnoreCase)) all.Add(hwnd);\r\n            return true;\r\n        },IntPtr.Zero);\r\n        return all.ToArray();\r\n    }\r\n\r\n    public static bool Hide(IntPtr hwnd) {\r\n        if(hwnd==IntPtr.Zero || !IsWindow(hwnd)) return false;\r\n        HardenNoActivate(hwnd);\r\n        EnableWindow(hwnd,false);\r\n        return ShowWindowAsync(hwnd,SW_HIDE);\r\n    }\r\n\r\n    public static bool ShowBehind(IntPtr hwnd) {\r\n        if(hwnd==IntPtr.Zero || !IsWindow(hwnd)) return false;\r\n        HardenNoActivate(hwnd);\r\n        EnableWindow(hwnd,false);\r\n        ShowWindowAsync(hwnd,SW_SHOWNOACTIVATE);\r\n        bool ok=SetWindowPos(hwnd,HWND_BOTTOM,0,0,0,0,SWP_NOMOVE|SWP_NOSIZE|SWP_NOACTIVATE);\r\n        HardenNoActivate(hwnd);\r\n        return ok && IsInputBlockedNoActivate(hwnd);\r\n    }\r\n\r\n    public static int EnsureSpotifyWindowsInputBlocked() {\r\n        int n=0;\r\n        foreach(var hwnd in GetSpotifyAllWindows()) {\r\n            if(hwnd==IntPtr.Zero || !IsWindow(hwnd)) continue;\r\n            HardenNoActivate(hwnd);\r\n            EnableWindow(hwnd,false);\r\n            if(IsInputBlockedNoActivate(hwnd)) n++;\r\n        }\r\n        return n;\r\n    }\r\n\r\n    public static bool AllSpotifyWindowsInputBlocked() {\r\n        var windows=GetSpotifyAllWindows();\r\n        if(windows.Length<1) return false;\r\n        foreach(var hwnd in windows) if(!IsInputBlockedNoActivate(hwnd)) return false;\r\n        return true;\r\n    }'''
if old not in s: raise SystemExit('window methods block missing')
s=s.replace(old,new,1)
start=s.index('function Show-SpotifyBehindUserForMeasurement {')
end=s.index('\r\nfunction Start-SpotifyHiddenForVariant {',start)
newfun='''function Show-SpotifyBehindUserForMeasurement {\r\n    Add-SpotifyBackgroundTypes\r\n    $settle=[Diagnostics.Stopwatch]::StartNew()\r\n    $n=0\r\n    while($settle.ElapsedMilliseconds -lt 3000){\r\n        $n=0\r\n        foreach($hwnd in @(Get-SpotifyMainWindows)){if([SpotifyControlWindowHost]::ShowBehind($hwnd)){$n++}}\r\n        [void][SpotifyControlWindowHost]::EnsureSpotifyWindowsInputBlocked()\r\n        if($n -ge 1 -and [SpotifyControlWindowHost]::AllSpotifyWindowsInputBlocked()){break}\r\n        Start-Sleep -Milliseconds 60\r\n    }\r\n    $settle.Stop()\r\n    if($n -lt 1){throw 'Spotify main window was unavailable for input-blocked non-activating background placement.'}\r\n    if(-not [SpotifyControlWindowHost]::AllSpotifyWindowsInputBlocked()){throw 'Spotify window input hardening could not be verified before measurement.'}\r\n    if([SpotifyControlWindowHost]::IsSpotifyForeground()){$script:ForegroundBookkeepingObservations=[int]$script:ForegroundBookkeepingObservations+1}\r\n    Write-LabLog 'Spotify window is normally shown behind the user but disabled for keyboard/mouse input and hardened with WS_EX_NOACTIVATE; foreground bookkeeping is telemetry only, not a safety gate.' 'OK'\r\n    return $n\r\n}\r\n'''
s=s[:start]+newfun+s[end:]
start=s.index('function Assert-SpotifyIdleGuardV0512 {')
end=s.index('\r\nfunction Arm-SpotifySilentGuard {',start)
newassert='''function Assert-SpotifyIdleGuardV0512 {\r\n    param($Session,[string]$Context)\r\n    [void](Refresh-SpotifySilentForTest)\r\n    [void][SpotifyControlWindowHost]::EnsureSpotifyWindowsInputBlocked()\r\n    if(-not [SpotifyControlWindowHost]::AllSpotifyWindowsInputBlocked()){throw "$Context Spotify window input hardening escaped; measurement rejected."}\r\n    if([SpotifyControlWindowHost]::IsSpotifyForeground()){$script:ForegroundBookkeepingObservations=[int]$script:ForegroundBookkeepingObservations+1}\r\n    $status='NoSession'\r\n    if($null -ne $Session){$status=[string]$Session.GetPlaybackInfo().PlaybackStatus}\r\n    if($status -eq 'Playing'){\r\n        [void](Refresh-SpotifySilentForTest)\r\n        throw "$Context Spotify unexpectedly entered Playing during media-command-free idle measurement. Audio remained mute+volume-zero guarded; sample rejected without issuing any media command."\r\n    }\r\n    return $status\r\n}\r\n'''
s=s[:start]+newassert+s[end:]
s=s.replace('WS_EX_NOACTIVATE startup-race stabilization','verified disabled-window + WS_EX_NOACTIVATE input hardening')
s=s.replace('$script:FocusRaceRecoveries = 0\r\n','$script:FocusRaceRecoveries = 0\r\n$script:ForegroundBookkeepingObservations = 0\r\n',1)
s=s.replace("sampler_revision='v0.5.12-absolute-deadline-cached-sampler';focus_race_policy='bounded-hide-reshow-stabilization-no-foreground-forcing';focus_race_recoveries_total=[int]$script:FocusRaceRecoveries","sampler_revision='v0.5.12-absolute-deadline-cached-sampler';input_safety_policy='disabled-window-plus-ws-ex-noactivate';foreground_bookkeeping_observations_total=[int]$script:ForegroundBookkeepingObservations",1)
s=s.replace("spotify_focus_hardening='WS_EX_NOACTIVATE + bounded startup-race stabilization; no SetForegroundWindow'","spotify_focus_hardening='disabled top-level Spotify windows + WS_EX_NOACTIVATE; foreground ownership is telemetry only'",1)
s=s.replace('startup-hidden-then-stably-nonforeground-ws-ex-noactivate','startup-hidden-then-input-disabled-ws-ex-noactivate')
s=s.replace("    Write-Host 'v0.5.12 also absorbs transient Spotify startup foreground races by hide/re-show stabilization without forcing focus to another application.'","    Write-Host 'v0.5.12 blocks Spotify top-level windows from keyboard/mouse input and keeps WS_EX_NOACTIVATE; foreground bookkeeping no longer causes false aborts.'",1)
s=s.replace('foreground startup races are stabilized without forcing another app.','Spotify windows are disabled for input and hardened with WS_EX_NOACTIVATE; foreground bookkeeping is telemetry only.',1)
s=s.replace('focus_race_recoveries_total','legacy_focus_race_recoveries_total')
s=s.replace('        [void](Hide-SpotifyWindowsForSetup)\r\n        if(@(Get-Process Spotify -ErrorAction SilentlyContinue).Count -ge 3){$healthy=$true;break}','        [void](Hide-SpotifyWindowsForSetup)\r\n        [void][SpotifyControlWindowHost]::EnsureSpotifyWindowsInputBlocked()\r\n        if(@(Get-Process Spotify -ErrorAction SilentlyContinue).Count -ge 3){$healthy=$true;break}',1)
s=s.replace('for($i=0;$i -lt 20;$i++){[void](Hide-SpotifyWindowsForSetup);Start-Sleep -Milliseconds 100}','for($i=0;$i -lt 20;$i++){[void](Hide-SpotifyWindowsForSetup);[void][SpotifyControlWindowHost]::EnsureSpotifyWindowsInputBlocked();Start-Sleep -Milliseconds 100}',1)
for bad in ['Spotify remained foreground after bounded WS_EX_NOACTIVATE startup-race stabilization.','unexpectedly became the foreground window despite','SetForegroundWindow(']:
    if bad in s: raise SystemExit('survived bad '+bad)
for req in ['EnableWindow(hwnd,false)','AllSpotifyWindowsInputBlocked','EnsureSpotifyWindowsInputBlocked','GetSpotifyAllWindows','disabled for keyboard/mouse input','foreground bookkeeping is telemetry only','*0.75']:
    if req not in s: raise SystemExit('missing '+req)
for x in ['TryPlayAsync','TryPauseAsync','TrySkipNextAsync','Invoke-SpotifyMediaCommand','keybd_event','Send-MediaKey','[byte]0xB0','[byte]0xB3']:
    if x.lower() in s.lower(): raise SystemExit('forbidden '+x)
files[ps]=b'\xef\xbb\xbf'+s.encode('utf-8')
for n in ['README.md','RUN_MEDIA_COMMAND_FREE_IDLE_REVALIDATION.cmd','SELFTEST.cmd']:
    txt=files[n].decode('utf-8',errors='strict')
    txt=txt.replace('v0.5.11','v0.5.12').replace('v0511','v0512').replace('V0511','V0512')
    if n=='README.md':
        txt=txt.replace('- v0.5.12 handles transient Spotify startup foreground races by hiding Spotify, re-showing it with WS_EX_NOACTIVATE at the bottom of Z-order, and requiring repeated non-foreground confirmation. It never calls SetForegroundWindow on another application.\r\n','- v0.5.12 makes Spotify top-level windows disabled for keyboard/mouse input while keeping them normally shown and hardened with WS_EX_NOACTIVATE. Foreground ownership is recorded only as telemetry and can no longer abort the benchmark by itself.\r\n')
    if n=='RUN_MEDIA_COMMAND_FREE_IDLE_REVALIDATION.cmd':
        txt=txt.replace('echo v0.5.12 also stabilizes transient Spotify startup focus races without forcing focus to another app.\r\n','echo v0.5.12 blocks Spotify windows from keyboard/mouse input; foreground bookkeeping no longer aborts the run.\r\n')
    files[n]=txt.encode('utf-8')
def sha(b):return hashlib.sha256(b).hexdigest()
order=[n for n in names if n!='SHA256SUMS.txt']
files['SHA256SUMS.txt']=("\n".join(f"{sha(files[n])}  {n}" for n in order)+"\n").encode('ascii')
order.append('SHA256SUMS.txt')
b=io.BytesIO()
with zipfile.ZipFile(b,'w',compression=zipfile.ZIP_STORED) as z:
    for n in order:
        i=zipfile.ZipInfo(n,(2026,10,26,0,0,0));i.compress_type=zipfile.ZIP_STORED;i.create_system=0;i.external_attr=0;i.flag_bits=0
        z.writestr(i,files[n])
pkg=b.getvalue();ident(files[ps],OUT_PS1,'v0.5.12 PS1');ident(pkg,OUT_ZIP,'v0.5.12 ZIP');OUT.write_bytes(pkg)
print('PHASE2_V0512_SCRIPT_PASS',len(files[ps]),sha(files[ps]));print('PHASE2_V0512_PACKAGE_PASS',len(pkg),sha(pkg))