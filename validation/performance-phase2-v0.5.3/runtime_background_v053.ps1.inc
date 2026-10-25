function Add-SpotifyBackgroundTypes {
    if(('SpotifyControlAudioGuard' -as [type]) -and ('SpotifyControlWindowHost' -as [type])){return}
    Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;

public sealed class SpotifyControlGuardState {
    public string SessionInstanceId { get; set; }
    public int ProcessId { get; set; }
    public bool Muted { get; set; }
    public float Volume { get; set; }
}

public static class SpotifyControlAudioGuard {
    enum EDataFlow { eRender=0, eCapture=1, eAll=2 }
    enum ERole { eConsole=0, eMultimedia=1, eCommunications=2 }
    [Flags] enum CLSCTX : uint { InprocServer=1, InprocHandler=2, LocalServer=4, RemoteServer=16, All=23 }

    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
    class MMDeviceEnumeratorComObject { }

    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceEnumerator {
        [PreserveSig] int EnumAudioEndpoints(EDataFlow dataFlow, uint stateMask, out IntPtr devices);
        [PreserveSig] int GetDefaultAudioEndpoint(EDataFlow dataFlow, ERole role, out IMMDevice device);
        [PreserveSig] int GetDevice([MarshalAs(UnmanagedType.LPWStr)] string id, out IMMDevice device);
        [PreserveSig] int RegisterEndpointNotificationCallback(IntPtr client);
        [PreserveSig] int UnregisterEndpointNotificationCallback(IntPtr client);
    }

    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDevice {
        [PreserveSig] int Activate(ref Guid iid, CLSCTX clsctx, IntPtr activationParams, [MarshalAs(UnmanagedType.IUnknown)] out object iface);
        [PreserveSig] int OpenPropertyStore(int access, out IntPtr properties);
        [PreserveSig] int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id);
        [PreserveSig] int GetState(out uint state);
    }

    [Guid("641DD20B-4D41-49CC-ABA3-174B9477BB08"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionNotification {
        [PreserveSig] int OnSessionCreated(IAudioSessionControl newSession);
    }

    [ComImport, Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionManager2 {
        [PreserveSig] int GetAudioSessionControl(ref Guid sessionGuid, uint streamFlags, out IntPtr sessionControl);
        [PreserveSig] int GetSimpleAudioVolume(ref Guid sessionGuid, uint streamFlags, out IntPtr audioVolume);
        [PreserveSig] int GetSessionEnumerator(out IAudioSessionEnumerator sessionEnum);
        [PreserveSig] int RegisterSessionNotification(IAudioSessionNotification notification);
        [PreserveSig] int UnregisterSessionNotification(IAudioSessionNotification notification);
        [PreserveSig] int RegisterDuckNotification([MarshalAs(UnmanagedType.LPWStr)] string sessionId, IntPtr notification);
        [PreserveSig] int UnregisterDuckNotification(IntPtr notification);
    }

    [ComImport, Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionEnumerator {
        [PreserveSig] int GetCount(out int count);
        [PreserveSig] int GetSession(int index, out IAudioSessionControl control);
    }

    [ComImport, Guid("F4B1A599-7266-4319-A8CA-E70ACB11E8CD"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionControl {
        [PreserveSig] int GetState(out int state);
        [PreserveSig] int GetDisplayName([MarshalAs(UnmanagedType.LPWStr)] out string name);
        [PreserveSig] int SetDisplayName([MarshalAs(UnmanagedType.LPWStr)] string value, ref Guid context);
        [PreserveSig] int GetIconPath([MarshalAs(UnmanagedType.LPWStr)] out string path);
        [PreserveSig] int SetIconPath([MarshalAs(UnmanagedType.LPWStr)] string value, ref Guid context);
        [PreserveSig] int GetGroupingParam(out Guid grouping);
        [PreserveSig] int SetGroupingParam(ref Guid grouping, ref Guid context);
        [PreserveSig] int RegisterAudioSessionNotification(IntPtr client);
        [PreserveSig] int UnregisterAudioSessionNotification(IntPtr client);
    }

    [ComImport, Guid("BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionControl2 {
        [PreserveSig] int GetState(out int state);
        [PreserveSig] int GetDisplayName([MarshalAs(UnmanagedType.LPWStr)] out string name);
        [PreserveSig] int SetDisplayName([MarshalAs(UnmanagedType.LPWStr)] string value, ref Guid context);
        [PreserveSig] int GetIconPath([MarshalAs(UnmanagedType.LPWStr)] out string path);
        [PreserveSig] int SetIconPath([MarshalAs(UnmanagedType.LPWStr)] string value, ref Guid context);
        [PreserveSig] int GetGroupingParam(out Guid grouping);
        [PreserveSig] int SetGroupingParam(ref Guid grouping, ref Guid context);
        [PreserveSig] int RegisterAudioSessionNotification(IntPtr client);
        [PreserveSig] int UnregisterAudioSessionNotification(IntPtr client);
        [PreserveSig] int GetSessionIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string id);
        [PreserveSig] int GetSessionInstanceIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string id);
        [PreserveSig] int GetProcessId(out uint pid);
        [PreserveSig] int IsSystemSoundsSession();
        [PreserveSig] int SetDuckingPreference([MarshalAs(UnmanagedType.Bool)] bool optOut);
    }

    [ComImport, Guid("87CE5498-68D6-44E5-9215-6DA47EF883D8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface ISimpleAudioVolume {
        [PreserveSig] int SetMasterVolume(float level, ref Guid context);
        [PreserveSig] int GetMasterVolume(out float level);
        [PreserveSig] int SetMute([MarshalAs(UnmanagedType.Bool)] bool mute, ref Guid context);
        [PreserveSig] int GetMute([MarshalAs(UnmanagedType.Bool)] out bool mute);
    }

    [ComVisible(true), ClassInterface(ClassInterfaceType.None)]
    sealed class NotificationClient : IAudioSessionNotification {
        public int OnSessionCreated(IAudioSessionControl newSession) {
            try { TryMuteControl(newSession); } catch { }
            return 0;
        }
    }

    static readonly object Gate = new object();
    static readonly Dictionary<string,SpotifyControlGuardState> States = new Dictionary<string,SpotifyControlGuardState>(StringComparer.Ordinal);
    static IAudioSessionManager2 Manager;
    static NotificationClient Notification;
    static bool Armed;

    static void Check(int hr) { if(hr < 0) Marshal.ThrowExceptionForHR(hr); }

    static bool IsSpotify(uint pid) {
        try { using(var p=Process.GetProcessById((int)pid)) { return String.Equals(p.ProcessName,"Spotify",StringComparison.OrdinalIgnoreCase); } }
        catch { return false; }
    }

    static IAudioSessionManager2 CreateManager() {
        var devEnum=(IMMDeviceEnumerator)(new MMDeviceEnumeratorComObject());
        IMMDevice device; Check(devEnum.GetDefaultAudioEndpoint(EDataFlow.eRender,ERole.eMultimedia,out device));
        object obj; var iid=new Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F");
        Check(device.Activate(ref iid,CLSCTX.All,IntPtr.Zero,out obj));
        return (IAudioSessionManager2)obj;
    }

    static string GetInstanceId(IAudioSessionControl2 c2, uint pid) {
        string id=null;
        if(c2.GetSessionInstanceIdentifier(out id) >= 0 && !String.IsNullOrEmpty(id)) return id;
        return "pid:"+pid.ToString();
    }

    static void TryMuteControl(IAudioSessionControl control) {
        if(control==null) return;
        var c2=(IAudioSessionControl2)control; uint pid; Check(c2.GetProcessId(out pid));
        if(!IsSpotify(pid)) return;
        var vol=(ISimpleAudioVolume)control; string key=GetInstanceId(c2,pid); var context=Guid.Empty;
        lock(Gate) {
            if(!States.ContainsKey(key)) {
                bool muted; float level; Check(vol.GetMute(out muted)); Check(vol.GetMasterVolume(out level));
                States[key]=new SpotifyControlGuardState{SessionInstanceId=key,ProcessId=(int)pid,Muted=muted,Volume=level};
            }
            Check(vol.SetMute(true,ref context));
        }
    }

    static int CaptureNowInternal() {
        if(Manager==null) return 0;
        IAudioSessionEnumerator sessions; Check(Manager.GetSessionEnumerator(out sessions));
        int count; Check(sessions.GetCount(out count));
        for(int i=0;i<count;i++) {
            IAudioSessionControl control;
            if(sessions.GetSession(i,out control)<0 || control==null) continue;
            try { TryMuteControl(control); } catch(InvalidCastException) { }
        }
        lock(Gate) { return States.Count; }
    }

    public static int Arm() {
        lock(Gate) {
            if(Armed) return States.Count;
            States.Clear();
            Manager=CreateManager();
            Notification=new NotificationClient();
            Check(Manager.RegisterSessionNotification(Notification));
            Armed=true;
        }
        return CaptureNowInternal();
    }

    public static int CaptureNow() { return CaptureNowInternal(); }

    public static int WaitForSpotifyCapture(int timeoutMs, int pollMs) {
        var sw=Stopwatch.StartNew();
        do {
            int n=CaptureNowInternal();
            if(n>0) return n;
            Thread.Sleep(Math.Max(1,pollMs));
        } while(sw.ElapsedMilliseconds < timeoutMs);
        return CaptureNowInternal();
    }

    public static int CapturedCount() { lock(Gate) { return States.Count; } }

    public static int RestoreAndDisarm() {
        IAudioSessionManager2 manager;
        NotificationClient notification;
        Dictionary<string,SpotifyControlGuardState> snapshot;
        lock(Gate) {
            manager=Manager; notification=Notification;
            snapshot=new Dictionary<string,SpotifyControlGuardState>(States,StringComparer.Ordinal);
        }
        int restored=0;
        if(manager!=null && snapshot.Count>0) {
            IAudioSessionEnumerator sessions; Check(manager.GetSessionEnumerator(out sessions));
            int count; Check(sessions.GetCount(out count)); var context=Guid.Empty;
            for(int i=0;i<count;i++) {
                IAudioSessionControl control;
                if(sessions.GetSession(i,out control)<0 || control==null) continue;
                try {
                    var c2=(IAudioSessionControl2)control; uint pid; Check(c2.GetProcessId(out pid)); if(!IsSpotify(pid)) continue;
                    string key=GetInstanceId(c2,pid); SpotifyControlGuardState state;
                    if(!snapshot.TryGetValue(key,out state)) continue;
                    var vol=(ISimpleAudioVolume)control;
                    Check(vol.SetMasterVolume(state.Volume,ref context)); Check(vol.SetMute(state.Muted,ref context)); restored++;
                } catch(InvalidCastException) { }
            }
        }
        if(manager!=null && notification!=null) { try { manager.UnregisterSessionNotification(notification); } catch { } }
        lock(Gate) { Armed=false; Manager=null; Notification=null; States.Clear(); }
        return restored;
    }

    public static void DisarmWithoutRestore() {
        IAudioSessionManager2 manager; NotificationClient notification;
        lock(Gate) { manager=Manager; notification=Notification; }
        if(manager!=null && notification!=null) { try { manager.UnregisterSessionNotification(notification); } catch { } }
        lock(Gate) { Armed=false; Manager=null; Notification=null; States.Clear(); }
    }
}

public static class SpotifyControlWindowHost {
    delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    static readonly IntPtr HWND_BOTTOM=new IntPtr(1);
    const uint SWP_NOSIZE=0x0001, SWP_NOMOVE=0x0002, SWP_NOACTIVATE=0x0010;
    const int SW_HIDE=0, SW_SHOWNOACTIVATE=4, GW_OWNER=4, GW_HWNDNEXT=2;

    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool ShowWindowAsync(IntPtr hWnd,int nCmdShow);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr hWnd,IntPtr hWndInsertAfter,int X,int Y,int cx,int cy,uint flags);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
    [DllImport("user32.dll")] static extern int GetWindowTextLength(IntPtr hWnd);
    [DllImport("user32.dll")] static extern IntPtr GetWindow(IntPtr hWnd, int command);
    [DllImport("user32.dll")] static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    static string ProcessNameForWindow(IntPtr hwnd) {
        try { uint pid; GetWindowThreadProcessId(hwnd,out pid); if(pid==0) return ""; using(var p=Process.GetProcessById((int)pid)) return p.ProcessName ?? ""; }
        catch { return ""; }
    }

    static bool IsExcludedUserWindow(IntPtr hwnd) {
        string n=ProcessNameForWindow(hwnd);
        return String.Equals(n,"Spotify",StringComparison.OrdinalIgnoreCase)
            || String.Equals(n,"powershell",StringComparison.OrdinalIgnoreCase)
            || String.Equals(n,"pwsh",StringComparison.OrdinalIgnoreCase)
            || String.Equals(n,"cmd",StringComparison.OrdinalIgnoreCase)
            || String.Equals(n,"conhost",StringComparison.OrdinalIgnoreCase)
            || String.Equals(n,"OpenConsole",StringComparison.OrdinalIgnoreCase)
            || String.Equals(n,"WindowsTerminal",StringComparison.OrdinalIgnoreCase);
    }

    public static IntPtr GetBestUserForegroundWindow() {
        IntPtr fg=GetForegroundWindow();
        if(fg!=IntPtr.Zero && !IsExcludedUserWindow(fg)) return fg;
        IntPtr cur=fg;
        for(int i=0;i<256 && cur!=IntPtr.Zero;i++) {
            cur=GetWindow(cur,GW_HWNDNEXT);
            if(cur==IntPtr.Zero) break;
            if(!IsWindowVisible(cur) || GetWindow(cur,GW_OWNER)!=IntPtr.Zero || GetWindowTextLength(cur)<=0) continue;
            if(!IsExcludedUserWindow(cur)) return cur;
        }
        return fg;
    }

    public static IntPtr[] GetSpotifyTopLevelWindows() {
        var titled=new List<IntPtr>(); var fallback=new List<IntPtr>();
        EnumWindows(delegate(IntPtr hwnd,IntPtr lp) {
            if(GetWindow(hwnd,GW_OWNER)!=IntPtr.Zero) return true;
            if(String.Equals(ProcessNameForWindow(hwnd),"Spotify",StringComparison.OrdinalIgnoreCase)) {
                fallback.Add(hwnd); if(GetWindowTextLength(hwnd)>0) titled.Add(hwnd);
            }
            return true;
        },IntPtr.Zero);
        return (titled.Count>0?titled:fallback).ToArray();
    }

    public static bool Hide(IntPtr hwnd) {
        if(hwnd==IntPtr.Zero || !IsWindow(hwnd)) return false;
        return ShowWindowAsync(hwnd,SW_HIDE);
    }

    public static bool ShowBehind(IntPtr hwnd, IntPtr restoreForeground) {
        if(hwnd==IntPtr.Zero || !IsWindow(hwnd)) return false;
        ShowWindowAsync(hwnd,SW_SHOWNOACTIVATE);
        bool ok=SetWindowPos(hwnd,HWND_BOTTOM,0,0,0,0,SWP_NOMOVE|SWP_NOSIZE|SWP_NOACTIVATE);
        if(restoreForeground!=IntPtr.Zero && IsWindow(restoreForeground)) { try { SetForegroundWindow(restoreForeground); } catch { } }
        return ok;
    }

    public static bool CloseHidden(IntPtr hwnd) {
        if(hwnd==IntPtr.Zero || !IsWindow(hwnd)) return false;
        ShowWindowAsync(hwnd,SW_HIDE);
        return PostMessage(hwnd,0x0010,IntPtr.Zero,IntPtr.Zero);
    }
}
"@
}

function Get-SpotifyMainWindows {
    Add-SpotifyBackgroundTypes
    return @([SpotifyControlWindowHost]::GetSpotifyTopLevelWindows())
}

function Hide-SpotifyWindowsForSetup {
    Add-SpotifyBackgroundTypes
    $n=0
    foreach($hwnd in @(Get-SpotifyMainWindows)){if([SpotifyControlWindowHost]::Hide($hwnd)){$n++}}
    return $n
}

function Show-SpotifyBehindUserForMeasurement {
    Add-SpotifyBackgroundTypes
    $fg=[IntPtr]::Zero
    if($null -ne $script:UserForegroundWindow){$fg=[IntPtr]$script:UserForegroundWindow}
    $n=0
    foreach($hwnd in @(Get-SpotifyMainWindows)){if([SpotifyControlWindowHost]::ShowBehind($hwnd,$fg)){$n++}}
    if($n -lt 1){throw 'Spotify main window was unavailable for non-activating background placement.'}
    Write-LabLog ("Spotify window placed behind the user's foreground app without minimization or activation; renderer remains in normal windowed mode.") 'OK'
    return $n
}

function Start-SpotifyHiddenForVariant {
    Add-SpotifyBackgroundTypes
    $script:UserForegroundWindow=[SpotifyControlWindowHost]::GetBestUserForegroundWindow()
    Start-Process -FilePath $SpotifyExe -WindowStyle Hidden
    $healthy=$false
    for($i=0;$i -lt 450;$i++){
        [void](Hide-SpotifyWindowsForSetup)
        if(@(Get-Process Spotify -ErrorAction SilentlyContinue).Count -ge 3){$healthy=$true;break}
        Start-Sleep -Milliseconds 100
    }
    if(-not $healthy){throw 'Spotify did not become healthy during hidden background startup.'}
    # Keep catching delayed main-window creation during the short setup interval.
    for($i=0;$i -lt 20;$i++){[void](Hide-SpotifyWindowsForSetup);Start-Sleep -Milliseconds 100}
}

function Arm-SpotifySilentGuard {
    Add-SpotifyBackgroundTypes
    $n=[SpotifyControlAudioGuard]::Arm()
    $script:SpotifyAudioGuardArmed=$true
    Write-LabLog ("Spotify-only CoreAudio guard armed before Play; pre-existing Spotify sessions captured={0}." -f $n) 'OK'
    return $n
}

function Start-SpotifyGuardedSilentPlayback {
    param($Session)
    [void](Arm-SpotifySilentGuard)
    try {
        [void](Invoke-SpotifyMediaCommand -Command Play -Session $Session)
        $n=[SpotifyControlAudioGuard]::WaitForSpotifyCapture(5000,5)
        if($n -lt 1){
            try{[void](Invoke-SpotifyMediaCommand -Command Pause -Session $Session)}catch{}
            [void](Restore-SpotifyAudioForTest -BestEffort)
            throw 'Spotify playback did not create a CoreAudio session that could be captured by the pre-armed mute guard.'
        }
        Write-LabLog ("Spotify audio session captured and muted by pre-armed guard; captured session(s)={0}." -f $n) 'OK'
        return $n
    } catch {
        try{[void](Invoke-SpotifyMediaCommand -Command Pause -Session $Session)}catch{}
        [void](Restore-SpotifyAudioForTest -BestEffort)
        throw
    }
}

function Refresh-SpotifySilentForTest {
    Add-SpotifyBackgroundTypes
    if(-not $script:SpotifyAudioGuardArmed){throw 'Spotify audio guard is not armed during silent profiling.'}
    $n=[SpotifyControlAudioGuard]::CaptureNow()
    if($n -lt 1){throw 'Spotify audio guard lost all captured Spotify sessions during silent profiling.'}
    return $n
}

function Restore-SpotifyAudioForTest {
    param([switch]$BestEffort)
    if(-not $script:SpotifyAudioGuardArmed){return 0}
    Add-SpotifyBackgroundTypes
    try {
        $n=[SpotifyControlAudioGuard]::RestoreAndDisarm()
        $script:SpotifyAudioGuardArmed=$false
        if($n -gt 0){Write-LabLog ("Spotify audio mute/volume state restored for {0} exact session(s)." -f $n) 'OK'}
        return $n
    } catch {
        try{[SpotifyControlAudioGuard]::DisarmWithoutRestore()}catch{}
        $script:SpotifyAudioGuardArmed=$false
        if($BestEffort){Write-LabLog ("Best-effort Spotify audio guard restore warning: "+$_.Exception.Message) 'WARN';return 0}
        throw
    }
}

function Close-SpotifyWindowsHidden {
    Add-SpotifyBackgroundTypes
    $n=0
    foreach($hwnd in @(Get-SpotifyMainWindows)){if([SpotifyControlWindowHost]::CloseHidden($hwnd)){$n++}}
    return $n
}
