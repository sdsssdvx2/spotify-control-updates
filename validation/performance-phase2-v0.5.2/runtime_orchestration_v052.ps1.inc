function Refresh-SpotifySilentForTest {
    Add-SpotifyAudioSessionType
    $new=@([SpotifyControlAudioSession]::CaptureAndMute())
    if($new.Count -eq 0){throw 'Spotify audio session disappeared while silent profiling was active.'}
    $merged=New-Object System.Collections.Generic.List[object]
    $seen=@{}
    foreach($s in @($script:SpotifyAudioOriginalStates)){$merged.Add($s);$seen[[int]$s.ProcessId]=$true}
    foreach($s in $new){if(-not $seen.ContainsKey([int]$s.ProcessId)){$merged.Add($s);$seen[[int]$s.ProcessId]=$true}}
    $script:SpotifyAudioOriginalStates=$merged.ToArray()
    return $new.Count
}

function Stop-SpotifyForVariant {
    $procs=@(Get-Process Spotify -ErrorAction SilentlyContinue)
    if($procs.Count -eq 0){[void](Restore-SpotifyAudioForTest -BestEffort);return}
    try{
        $session=Get-SpotifyMediaSession -AllowNone
        if($null -ne $session){[void](Invoke-SpotifyMediaCommand -Command Pause -Session $session)}
    }catch{Write-LabLog ('Spotify-targeted pause before shutdown warning: '+$_.Exception.Message) 'WARN'}
    [void](Restore-SpotifyAudioForTest -BestEffort)
    foreach($p in @($procs|Where-Object{$_.MainWindowHandle -ne 0})){try{[void]$p.CloseMainWindow()}catch{}}
    for($i=0;$i -lt 30;$i++){if(@(Get-Process Spotify -ErrorAction SilentlyContinue).Count -eq 0){return};Start-Sleep -Milliseconds 250}
    Write-LabLog 'Spotify did not exit through its main window; using process termination after targeted pause and audio-state restore.' 'WARN'
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
    $script:SpotifyMediaManager=$null;$script:WinRtAsTaskGeneric=$null;$script:SpotifyAudioOriginalStates=$null
    Start-Process -FilePath $SpotifyExe
    if(-not(Wait-SpotifyReady 45)){throw "Spotify did not become healthy for $($Variant.label)"}
    $script:RoleCacheSignature='';$script:RoleCache=@{}
    Start-Sleep -Seconds 2
    $session=Wait-SpotifyMediaSession -TimeoutSeconds 30
    [void](Set-SpotifySilentForTest)
    [void](Invoke-SpotifyMediaCommand -Command Play -Session $session)
    Start-Sleep -Milliseconds 300
    [void](Refresh-SpotifySilentForTest)
    Write-LabLog ("Spotify-targeted silent playback started for {0}; profile={1}; patched_targets={2}; warmup={3} sec. Other apps remain untouched." -f $Variant.label,$Variant.profile,@($Variant.target_ids).Count,$PlaybackWarmupSeconds)
    Start-Sleep -Seconds $PlaybackWarmupSeconds
    $start=Get-SpotifyMediaSnapshot -Session $session
    if([string]::IsNullOrWhiteSpace($start.title)){throw "Spotify media metadata is unavailable before $($Variant.label) measurement."}
    return [pscustomobject]@{profile=$Variant.profile;target_ids=@($Variant.target_ids);apply_result=$apply;restore_result=$restore;index_sha256=(Get-Sha256Lower $IndexPath);spotify_media_source=$start.source_app_user_model_id;spotify_start_track=$start.identity}
}

function Measure-TransitionCondition {
    param([string]$Label)
    if(-not(Wait-SpotifyReady 20)){throw "Spotify is not running for $Label"}
    $session=Get-SpotifyMediaSession
    $rows=New-Object System.Collections.Generic.List[object]
    $events=New-Object System.Collections.Generic.List[object]
    $prev=@{};foreach($p in @(Get-Process Spotify -ErrorAction SilentlyContinue)){if($null -ne $p.CPU){$prev[[int]$p.Id]=[double]$p.CPU}}
    $clock=[Diagnostics.Stopwatch]::StartNew();$lastSample=0.0;$nextIndex=0;$pending=$null
    Write-LabLog "Starting $Label silent targeted transition phase: $TransitionSeconds sec, interval=${SampleIntervalMs}ms, NEXT offsets=$($NextOffsets -join ',')."
    while($clock.Elapsed.TotalSeconds -lt $TransitionSeconds){
        Start-Sleep -Milliseconds $SampleIntervalMs
        $elapsed=$clock.Elapsed.TotalSeconds;$event=''
        if($null -ne $pending -and $elapsed -ge [double]$pending.next_check_seconds){
            $nowMedia=Get-SpotifyMediaSnapshot -Session $session
            $identityChanged=([string]$nowMedia.identity -ne [string]$pending.before.identity -and -not [string]::IsNullOrWhiteSpace([string]$nowMedia.title))
            $positionReset=([int64]$pending.before.position_ms -ge 2500 -and [int64]$nowMedia.position_ms -le ([int64]$pending.before.position_ms-2000))
            if($identityChanged -or $positionReset){
                $confirmMs=[int](($elapsed-[double]$pending.sent_seconds)*1000.0)
                $events.Add([pscustomobject]@{index=[int]$pending.index;planned_seconds=[double]$pending.planned_seconds;actual_seconds=[double]$pending.sent_seconds;confirmation_ms=$confirmMs;before_identity=[string]$pending.before.identity;after_identity=[string]$nowMedia.identity;identity_changed=$identityChanged;position_reset=$positionReset})
                $event="SPOTIFY_NEXT_CONFIRMED_$($pending.index)";Write-LabLog ("{0} {1}: {2} -> {3} ({4}ms)" -f $Label,$event,$pending.before.title,$nowMedia.title,$confirmMs) 'OK';$pending=$null
            }elseif(($elapsed-[double]$pending.sent_seconds) -ge 4.0){
                throw "$Label Spotify-targeted NEXT $($pending.index) was not confirmed by Spotify media metadata/position within 4 seconds. Sample rejected."
            }else{$pending.next_check_seconds=$elapsed+0.45}
        }
        if($null -eq $pending -and $nextIndex -lt $NextOffsets.Count -and $elapsed -ge [double]$NextOffsets[$nextIndex]){
            $before=Get-SpotifyMediaSnapshot -Session $session
            if([string]::IsNullOrWhiteSpace($before.title)){throw "$Label cannot identify Spotify track before NEXT $($nextIndex+1)."}
            [void](Invoke-SpotifyMediaCommand -Command Next -Session $session)
            $actual=$clock.Elapsed.TotalSeconds
            $pending=[pscustomobject]@{index=$nextIndex+1;planned_seconds=[double]$NextOffsets[$nextIndex];sent_seconds=[Math]::Round($actual,3);next_check_seconds=$actual+0.6;before=$before}
            $event="SPOTIFY_NEXT_TARGETED_$($nextIndex+1)";Write-LabLog ("{0} {1} at +{2}s; before={3}" -f $Label,$event,[Math]::Round($actual,2),$before.title);$nextIndex++
        }
        $interval=$elapsed-$lastSample;if($interval -le 0){$interval=$SampleIntervalMs/1000.0}
        $snap=Get-RoleSnapshot -Previous $prev -IntervalSeconds $interval;$prev=$snap.next;$lastSample=$elapsed
        $rows.Add([pscustomobject]@{
            timestamp=(Get-Date).ToString('o');condition=$Label;elapsed_seconds=[Math]::Round($elapsed,3);event=$event;process_count=$snap.count
            cpu_percent=[Math]::Round([double]$snap.cpu.total,3);main_cpu_percent=[Math]::Round([double]$snap.cpu.main,3);renderer_cpu_percent=[Math]::Round([double]$snap.cpu.renderer,3);gpu_cpu_percent=[Math]::Round([double]$snap.cpu.gpu,3);utility_cpu_percent=[Math]::Round([double]$snap.cpu.utility,3)
            working_set_mb=[Math]::Round([double]$snap.ws.total/1MB,2);private_mb=[Math]::Round([double]$snap.private/1MB,2);main_working_set_mb=[Math]::Round([double]$snap.ws.main/1MB,2);renderer_working_set_mb=[Math]::Round([double]$snap.ws.renderer/1MB,2);gpu_working_set_mb=[Math]::Round([double]$snap.ws.gpu/1MB,2)
        })
    }
    $clock.Stop()
    if($null -ne $pending){throw "$Label ended with an unconfirmed Spotify-targeted NEXT event."}
    if($events.Count -ne $NextOffsets.Count){throw "$Label confirmed only $($events.Count)/$($NextOffsets.Count) Spotify track transitions."}
    $rowArray=$rows.ToArray();$minProcessCount=[int](($rowArray|Select-Object -ExpandProperty process_count|Measure-Object -Minimum).Minimum);$endProcessCount=@(Get-Process Spotify -ErrorAction SilentlyContinue).Count
    if($minProcessCount -lt 1 -or $endProcessCount -lt 1){throw "$Label lost all Spotify processes during the transition workload."}
    [void](Invoke-SpotifyMediaCommand -Command Pause -Session $session);Start-Sleep -Milliseconds 250;[void](Restore-SpotifyAudioForTest)
    return [pscustomobject]@{rows=$rowArray;events=$events.ToArray();min_spotify_process_count=$minProcessCount;end_spotify_process_count=$endProcessCount;verified_spotify_transitions=$events.Count}
}

function Analyze-Transitions {
    param([string]$Label,[object[]]$Rows,[object[]]$Events)
    $windowRows=New-Object System.Collections.Generic.List[object];$peaks=New-Object System.Collections.Generic.List[object]
    foreach($ev in $Events){
        $s=[double]$ev.actual_seconds;$subset=@($Rows|Where-Object{[double]$_.elapsed_seconds -ge $s -and [double]$_.elapsed_seconds -le ($s+$TransitionWindowSeconds)})
        foreach($r in $subset){$windowRows.Add($r)}
        if($subset.Count -eq 0){throw "No transition samples found for $Label event $($ev.index)."}
        $peaks.Add([pscustomobject]@{index=$ev.index;event_seconds=$s;confirmation_ms=$ev.confirmation_ms;before_identity=$ev.before_identity;after_identity=$ev.after_identity;cpu_peak=[Math]::Round((($subset.cpu_percent|Measure-Object -Maximum).Maximum),2);main_peak=[Math]::Round((($subset.main_cpu_percent|Measure-Object -Maximum).Maximum),2);renderer_peak=[Math]::Round((($subset.renderer_cpu_percent|Measure-Object -Maximum).Maximum),2);gpu_peak=[Math]::Round((($subset.gpu_cpu_percent|Measure-Object -Maximum).Maximum),2);ws_peak_mb=[Math]::Round((($subset.working_set_mb|Measure-Object -Maximum).Maximum),1)})
    }
    $active=@($peaks.ToArray()|Where-Object{[double]$_.cpu_peak -ge 1.5}).Count;$required=[Math]::Max(1,[Math]::Ceiling($peaks.Count*0.67))
    return [pscustomobject]@{label=$Label;transition_sample_count=$windowRows.Count;metrics=(Get-MetricSummary $windowRows.ToArray());transitions=$peaks.ToArray();workload_canary_pass=($active -ge $required);active_transition_windows=$active;required_active_transition_windows=$required;verified_spotify_transitions=$peaks.Count}
}

function Get-WorkloadPolicy {
    param([string]$Label,$Analysis)
    $strictBaseline=($Label -like 'BASELINE_*');$canary=[bool]$Analysis.workload_canary_pass
    $status=if($canary){'spotify-transition-verified'}elseif($strictBaseline){'baseline-invalid'}else{'low-response-verified'}
    return [pscustomobject]@{accepted=($canary -or -not $strictBaseline);strict_baseline=$strictBaseline;status=$status}
}

function Build-TextReport {
    param($Report)
    $l=New-Object System.Collections.Generic.List[string]
    $l.Add("Spotify Control Track Transition Silent Targeted Acceptance Report v$Version");$l.Add("Generated: $($Report.generated_at)");$l.Add('')
    $l.Add("Measurement runtime: Spotify Control $($Report.accepted_baseline.spotify_control_version) / Addon Manager $($Report.accepted_baseline.addon_manager_version) / Spotify $($Report.accepted_baseline.spotify_version) / Spicetify $($Report.accepted_baseline.spicetify_version)")
    $l.Add("Media control: Spotify-targeted Windows media session; global media keys used=False; Spotify audio muted during workload=True; other applications untouched=True")
    $l.Add("CPU/renderer baseline confidence: $($Report.baseline_cpu_confidence)");$l.Add(("Baseline A/B transition p95 drift: CPU={0} pts | renderer={1} pts" -f $Report.baseline_drift.cpu_p95_points,$Report.baseline_drift.renderer_p95_points))
    $l.Add("Memory baseline confidence: $($Report.baseline_memory_confidence)");$l.Add(("Baseline A/B WS p95 drift: {0} MB (memory remains secondary)" -f $Report.baseline_drift.ws_p95_mb));$l.Add('')
    foreach($c in @($Report.conditions)){$m=$c.metrics;$l.Add($c.label);$l.Add(("  CPU p50={0}% p95={1}% p99={2}% max={3}%" -f $m.cpu_percent.p50,$m.cpu_percent.p95,$m.cpu_percent.p99,$m.cpu_percent.max));$l.Add(("  Renderer p95={0}% max={1}% | GPU p95={2}% max={3}% | WS p95={4} MB | evidence={5} | verified Spotify transitions={6}" -f $m.renderer_cpu_percent.p95,$m.renderer_cpu_percent.max,$m.gpu_cpu_percent.p95,$m.gpu_cpu_percent.max,$m.working_set_mb.p95,$c.workload_policy_status,$c.verified_spotify_transitions));$l.Add('')}
    $l.Add('Patch savings vs averaged BASELINE_A/B (positive = optimized bytes reduced transition cost):');foreach($x in @($Report.comparisons)){$l.Add(("  {0}: CPU p95 {1} pts | p99 {2} | max {3} | renderer p95 {4} | patches {5}" -f $x.label,$x.cpu_p95_saved,$x.cpu_p99_saved,$x.cpu_max_saved,$x.renderer_p95_saved,(@($x.target_ids)-join ',')))}
    $l.Add('');$l.Add('Safety:');$l.Add('- Spotify was controlled through its own Windows media session; no global Play/Pause/NEXT key was emitted.');$l.Add('- Spotify audio sessions alone were muted during workload and their original mute/volume state was restored before shutdown; other apps were not changed.');$l.Add('- Every recorded transition required Spotify media metadata/position to confirm the Spotify track changed.');$l.Add('- Both active extension files had to match exact pinned upstream SHA-256/size before measurement began.');$l.Add('- Every condition starts by restoring prior direct patches to exact original bytes before the next profile is applied.');$l.Add('- Restore refuses to overwrite newer or unknown active bytes; there is no destructive fallback.');$l.Add('- No extension/CustomApp payload was deleted or renamed; playlist-backed Star Ratings data was not touched.');$l.Add('- Browser/Default Spotify WebView persistence was safety-backed up and never edited; ivLyrics/Tagify/splitify/unknown hooks were preserved.');$l.Add('- Original index.html and complete xpui tree were verified exact after final direct-patch restore; config-xpui.ini remained byte-for-byte unchanged.')
    return ($l -join [Environment]::NewLine)
}
