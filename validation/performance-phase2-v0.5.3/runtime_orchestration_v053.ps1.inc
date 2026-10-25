function Stop-SpotifyForVariant {
    $procs=@(Get-Process Spotify -ErrorAction SilentlyContinue)
    if($procs.Count -eq 0){[void](Restore-SpotifyAudioForTest -BestEffort);return}
    [void](Hide-SpotifyWindowsForSetup)
    try{
        $session=Get-SpotifyMediaSession -AllowNone
        if($null -ne $session){[void](Invoke-SpotifyMediaCommand -Command Pause -Session $session)}
    }catch{Write-LabLog ('Spotify-targeted pause before shutdown warning: '+$_.Exception.Message) 'WARN'}
    [void](Restore-SpotifyAudioForTest -BestEffort)
    [void](Close-SpotifyWindowsHidden)
    for($i=0;$i -lt 30;$i++){if(@(Get-Process Spotify -ErrorAction SilentlyContinue).Count -eq 0){return};Start-Sleep -Milliseconds 250}
    Write-LabLog 'Spotify did not exit through its hidden main window; using process termination after targeted pause and exact audio-state restore.' 'WARN'
    @(Get-Process Spotify -ErrorAction SilentlyContinue)|Stop-Process -Force -ErrorAction SilentlyContinue
    for($i=0;$i -lt 40;$i++){if(@(Get-Process Spotify -ErrorAction SilentlyContinue).Count -eq 0){return};Start-Sleep -Milliseconds 250}
    throw 'Spotify did not exit before xpui variant swap.'
}

function Prepare-Variant {
    param($Variant)
    Stop-SpotifyForVariant
    $restore=Restore-DirectPatches
    $tree=Get-TreeFingerprint $XpuiRoot
    if($tree.sha256 -ne $script:OriginalXpuiTree.sha256 -or $tree.file_count -ne $script:OriginalXpuiTree.file_count -or $tree.total_bytes -ne $script:OriginalXpuiTree.total_bytes){throw "Could not restore exact original xpui tree before $($Variant.label)."}
    if((Get-Sha256Lower $IndexPath) -ne $script:OriginalIndexHash){throw "Active index drifted before $($Variant.label)."}
    if((Get-Sha256Lower $ConfigPath) -ne $script:OriginalConfigHash){throw "Spicetify config drifted before $($Variant.label)."}

    $apply=$null
    if([string]$Variant.profile -ne 'none'){
        $metadata=[string]$script:PatchMetadataPaths[[string]$Variant.profile]
        if([string]::IsNullOrWhiteSpace($metadata)){throw "No patch metadata path for profile $($Variant.profile)."}
        $script:DirectPatchMutationStarted=$true
        $apply=Invoke-DirectPatchEngine -Mode Apply -MetadataPath $metadata
        $results=@($apply.targets)
        if($results.Count -ne @($Variant.target_ids).Count){throw "$($Variant.label) applied unexpected target count: $($results.Count)."}
        foreach($id in @($Variant.target_ids)){
            $r=@($results|Where-Object id -eq $id)
            if($r.Count -ne 1 -or [string]$r[0].status -notin @('applied','already-applied')){throw "$($Variant.label) did not apply exact requested patch target: $id"}
        }
    }
    if(-not(Test-SafePath $SpotifyExe 'Leaf')){throw 'Spotify executable disappeared before variant launch.'}
    $script:SpotifyMediaManager=$null;$script:WinRtAsTaskGeneric=$null;$script:SpotifyAudioGuardArmed=$false;$script:UserForegroundWindow=$null
    Start-SpotifyHiddenForVariant
    $script:RoleCacheSignature='';$script:RoleCache=@{}
    $session=Wait-SpotifyMediaSession -TimeoutSeconds 30
    [void](Start-SpotifyGuardedSilentPlayback -Session $session)
    [void](Show-SpotifyBehindUserForMeasurement)
    Start-Sleep -Milliseconds 300
    [void](Refresh-SpotifySilentForTest)
    Write-LabLog ("Spotify-targeted guarded silent playback started for {0}; profile={1}; patched_targets={2}; warmup={3} sec. Spotify stays non-minimized but behind the user's foreground app; other apps remain untouched." -f $Variant.label,$Variant.profile,@($Variant.target_ids).Count,$PlaybackWarmupSeconds)
    Start-Sleep -Seconds $PlaybackWarmupSeconds
    $start=Get-SpotifyMediaSnapshot -Session $session
    if([string]::IsNullOrWhiteSpace($start.title)){throw "Spotify media metadata is unavailable before $($Variant.label) measurement."}
    return [pscustomobject]@{profile=$Variant.profile;target_ids=@($Variant.target_ids);apply_result=$apply;restore_result=$restore;index_sha256=(Get-Sha256Lower $IndexPath);spotify_media_source=$start.source_app_user_model_id;spotify_start_track=$start.identity;spotify_window_mode='startup-hidden-then-behind-user-noactivate';spotify_minimized_during_measurement=$false}
}
