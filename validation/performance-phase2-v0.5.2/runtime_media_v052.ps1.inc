function Initialize-SpotifyWinRtMedia {
    if($null -ne $script:SpotifyMediaManager){return}
    $null=[Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager,Windows.Media.Control,ContentType=WindowsRuntime]
    $null=[Windows.Media.Control.GlobalSystemMediaTransportControlsSession,Windows.Media.Control,ContentType=WindowsRuntime]
    $null=[Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties,Windows.Media.Control,ContentType=WindowsRuntime]
    $generic=@([System.WindowsRuntimeSystemExtensions].GetMethods()|Where-Object{$_.Name -eq 'AsTask' -and $_.IsGenericMethodDefinition -and $_.GetParameters().Count -eq 1})
    if($generic.Count -lt 1){throw 'Windows Runtime AsTask<T> bridge is unavailable.'}
    $script:WinRtAsTaskGeneric=$generic[0]
    $op=[Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]::RequestAsync()
    $task=$script:WinRtAsTaskGeneric.MakeGenericMethod([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]).Invoke($null,@($op))
    if(-not $task.Wait(15000)){throw 'Timed out requesting Windows media-session manager.'}
    $script:SpotifyMediaManager=$task.Result
    if($null -eq $script:SpotifyMediaManager){throw 'Windows media-session manager returned null.'}
}

function Invoke-WinRtResult {
    param($Operation,[Type]$ResultType,[int]$TimeoutMs=10000)
    Initialize-SpotifyWinRtMedia
    $task=$script:WinRtAsTaskGeneric.MakeGenericMethod($ResultType).Invoke($null,@($Operation))
    if(-not $task.Wait($TimeoutMs)){throw "Windows Runtime operation timed out after ${TimeoutMs}ms."}
    return $task.Result
}

function Get-SpotifyMediaSession {
    param([switch]$AllowNone)
    Initialize-SpotifyWinRtMedia
    $all=@($script:SpotifyMediaManager.GetSessions())
    $matches=@($all|Where-Object{([string]$_.SourceAppUserModelId) -match '(?i)spotify'})
    if($matches.Count -eq 1){return $matches[0]}
    if($matches.Count -eq 0 -and $AllowNone){return $null}
    $ids=@($all|ForEach-Object{[string]$_.SourceAppUserModelId}) -join ','
    if($matches.Count -eq 0){throw "No Spotify Windows media session found. Visible sessions: $ids"}
    throw "Multiple Spotify Windows media sessions found; refusing to guess. Visible sessions: $ids"
}

function Wait-SpotifyMediaSession {
    param([int]$TimeoutSeconds=30)
    for($i=0;$i -lt ($TimeoutSeconds*4);$i++){
        $s=Get-SpotifyMediaSession -AllowNone
        if($null -ne $s){return $s}
        Start-Sleep -Milliseconds 250
    }
    throw "Spotify Windows media session did not appear within $TimeoutSeconds seconds."
}

function Get-SpotifyMediaSnapshot {
    param($Session=(Get-SpotifyMediaSession))
    $props=Invoke-WinRtResult -Operation $Session.TryGetMediaPropertiesAsync() -ResultType ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties])
    $timeline=$Session.GetTimelineProperties()
    $info=$Session.GetPlaybackInfo()
    $title=[string]$props.Title;$artist=[string]$props.Artist;$album=[string]$props.AlbumTitle;$track=[int]$props.TrackNumber
    $identity=("{0}|{1}|{2}|{3}" -f $title,$artist,$album,$track)
    return [pscustomobject]@{
        source_app_user_model_id=[string]$Session.SourceAppUserModelId
        title=$title;artist=$artist;album=$album;track_number=$track;identity=$identity
        position_ms=[int64]$timeline.Position.TotalMilliseconds
        playback_status=[string]$info.PlaybackStatus
    }
}

function Invoke-SpotifyMediaCommand {
    param([ValidateSet('Play','Pause','Next')][string]$Command,$Session=(Get-SpotifyMediaSession))
    $op=$null
    switch($Command){
        'Play' {$op=$Session.TryPlayAsync()}
        'Pause' {$op=$Session.TryPauseAsync()}
        'Next' {$op=$Session.TrySkipNextAsync()}
    }
    $ok=[bool](Invoke-WinRtResult -Operation $op -ResultType ([bool]) -TimeoutMs 10000)
    if(-not $ok){throw "Spotify-targeted media command was rejected: $Command"}
    return $true
}

function Wait-SpotifyTrackChange {
    param($Session,$Before,[int]$TimeoutMs=6000)
    $sw=[Diagnostics.Stopwatch]::StartNew()
    do{
        Start-Sleep -Milliseconds 100
        $now=Get-SpotifyMediaSnapshot -Session $Session
        $identityChanged=([string]$now.identity -ne [string]$Before.identity -and -not [string]::IsNullOrWhiteSpace([string]$now.title))
        $positionReset=([int64]$Before.position_ms -ge 2500 -and [int64]$now.position_ms -le ([int64]$Before.position_ms-2000))
        if($identityChanged -or $positionReset){
            $sw.Stop()
            return [pscustomobject]@{changed=$true;confirmation_ms=[int]$sw.ElapsedMilliseconds;before=$Before;after=$now;identity_changed=$identityChanged;position_reset=$positionReset}
        }
    }while($sw.ElapsedMilliseconds -lt $TimeoutMs)
    $sw.Stop()
    return [pscustomobject]@{changed=$false;confirmation_ms=[int]$sw.ElapsedMilliseconds;before=$Before;after=(Get-SpotifyMediaSnapshot -Session $Session);identity_changed=$false;position_reset=$false}
}

function Add-SpotifyAudioSessionType {
    if('SpotifyControlAudioSession' -as [type]){return}
    Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;

public sealed class SpotifyControlAudioState {
    public int ProcessId { get; set; }
    public bool Muted { get; set; }
    public float Volume { get; set; }
}

public static class SpotifyControlAudioSession {
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

    [ComImport, Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionManager2 {
        [PreserveSig] int GetAudioSessionControl(ref Guid sessionGuid, uint streamFlags, out IntPtr sessionControl);
        [PreserveSig] int GetSimpleAudioVolume(ref Guid sessionGuid, uint streamFlags, out IntPtr audioVolume);
        [PreserveSig] int GetSessionEnumerator(out IAudioSessionEnumerator sessionEnum);
        [PreserveSig] int RegisterSessionNotification(IntPtr notification);
        [PreserveSig] int UnregisterSessionNotification(IntPtr notification);
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

    static void Check(int hr) { if(hr < 0) Marshal.ThrowExceptionForHR(hr); }
    static bool IsSpotify(uint pid) {
        try { using(var p=Process.GetProcessById((int)pid)) { return String.Equals(p.ProcessName,"Spotify",StringComparison.OrdinalIgnoreCase); } }
        catch { return false; }
    }
    static IAudioSessionEnumerator GetEnumerator() {
        var devEnum=(IMMDeviceEnumerator)(new MMDeviceEnumeratorComObject());
        IMMDevice device; Check(devEnum.GetDefaultAudioEndpoint(EDataFlow.eRender,ERole.eMultimedia,out device));
        object obj; var iid=new Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"); Check(device.Activate(ref iid,CLSCTX.All,IntPtr.Zero,out obj));
        var mgr=(IAudioSessionManager2)obj; IAudioSessionEnumerator sessions; Check(mgr.GetSessionEnumerator(out sessions)); return sessions;
    }
    public static SpotifyControlAudioState[] CaptureAndMute() {
        var result=new List<SpotifyControlAudioState>(); var sessions=GetEnumerator(); int count; Check(sessions.GetCount(out count)); var context=Guid.Empty;
        for(int i=0;i<count;i++) {
            IAudioSessionControl control; if(sessions.GetSession(i,out control)<0 || control==null) continue;
            try {
                var c2=(IAudioSessionControl2)control; uint pid; Check(c2.GetProcessId(out pid)); if(!IsSpotify(pid)) continue;
                var vol=(ISimpleAudioVolume)control; bool muted; float level; Check(vol.GetMute(out muted)); Check(vol.GetMasterVolume(out level));
                result.Add(new SpotifyControlAudioState{ProcessId=(int)pid,Muted=muted,Volume=level}); Check(vol.SetMute(true,ref context));
            } catch(InvalidCastException) { }
        }
        return result.ToArray();
    }
    public static int Restore(SpotifyControlAudioState[] states) {
        if(states==null || states.Length==0) return 0; var byPid=new Dictionary<int,SpotifyControlAudioState>(); foreach(var s in states) byPid[s.ProcessId]=s;
        var fallback=states[0]; var sessions=GetEnumerator(); int count; Check(sessions.GetCount(out count)); int restored=0; var context=Guid.Empty;
        for(int i=0;i<count;i++) {
            IAudioSessionControl control; if(sessions.GetSession(i,out control)<0 || control==null) continue;
            try {
                var c2=(IAudioSessionControl2)control; uint pid; Check(c2.GetProcessId(out pid)); if(!IsSpotify(pid)) continue;
                SpotifyControlAudioState s; if(!byPid.TryGetValue((int)pid,out s)) s=fallback;
                var vol=(ISimpleAudioVolume)control; Check(vol.SetMasterVolume(s.Volume,ref context)); Check(vol.SetMute(s.Muted,ref context)); restored++;
            } catch(InvalidCastException) { }
        }
        return restored;
    }
}
"@
}

function Set-SpotifySilentForTest {
    Add-SpotifyAudioSessionType
    for($i=0;$i -lt 40;$i++){
        $states=@([SpotifyControlAudioSession]::CaptureAndMute())
        if($states.Count -gt 0){
            $script:SpotifyAudioOriginalStates=$states
            Write-LabLog ("Spotify-only audio mute engaged for {0} session(s); other applications are untouched." -f $states.Count) 'OK'
            return $states
        }
        Start-Sleep -Milliseconds 250
    }
    throw 'Spotify audio session did not become available for silent profiling; refusing to start audible playback.'
}

function Restore-SpotifyAudioForTest {
    param([switch]$BestEffort)
    if($null -eq $script:SpotifyAudioOriginalStates){return 0}
    Add-SpotifyAudioSessionType
    try{
        $n=[SpotifyControlAudioSession]::Restore([SpotifyControlAudioState[]]@($script:SpotifyAudioOriginalStates))
        if($n -lt 1 -and -not $BestEffort){throw 'Spotify audio session could not be restored before shutdown.'}
        if($n -gt 0){Write-LabLog ("Spotify audio mute/volume state restored on {0} session(s)." -f $n) 'OK'}
        $script:SpotifyAudioOriginalStates=$null
        return $n
    }catch{
        if($BestEffort){Write-LabLog ("Best-effort Spotify audio restore warning: "+$_.Exception.Message) 'WARN';return 0}
        throw
    }
}
