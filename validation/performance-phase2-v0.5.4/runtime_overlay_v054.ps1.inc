function Write-JsonUtf8V054 {
    param([string]$Path,$Value)
    $parent=Split-Path -Parent $Path
    if($parent -and -not(Test-Path -LiteralPath $parent -PathType Container)){New-Item -ItemType Directory -Force -Path $parent|Out-Null}
    $json=$Value|ConvertTo-Json -Depth 24
    [IO.File]::WriteAllBytes($Path,(New-Object Text.UTF8Encoding($false)).GetBytes($json))
}

function Assert-OverlayPackageIdentityV054 {
    foreach($p in @($OverlayApplyPath,$OverlayLoaderPath,$OverlayTargetsPath)){if(-not(Test-SafePath $p 'Leaf')){throw "Overlay benchmark package file missing: $p"}}
    if((Get-Sha256Lower $OverlayApplyPath) -ne $ExpectedOverlayApplySha){throw 'Packaged production overlay engine SHA-256 mismatch.'}
    if((Get-Sha256Lower $OverlayLoaderPath) -ne $ExpectedOverlayLoaderSha){throw 'Packaged production overlay loader SHA-256 mismatch.'}
    if((Get-Sha256Lower $OverlayTargetsPath) -ne $ExpectedOverlayTargetsSha){throw 'Packaged production overlay target metadata SHA-256 mismatch.'}
}

function Get-OverlayTargetDocumentV054 {
    Assert-OverlayPackageIdentityV054
    return (Get-Content -LiteralPath $OverlayTargetsPath -Raw|ConvertFrom-Json)
}

function Get-OverlayProductionStateRootV054 {
    if(-not $env:LOCALAPPDATA){throw 'LOCALAPPDATA is unavailable.'}
    return (Join-Path $env:LOCALAPPDATA 'SpotifyControl\performance-overlay\runtime-v010')
}

function Get-OverlaySortedIdsV054 {
    param([object[]]$Ids)
    return @($Ids|ForEach-Object{[string]$_}|Sort-Object)
}

function Assert-OverlayBenchmarkEligibilityV054 {
    Assert-OverlayPackageIdentityV054
    $doc=Get-OverlayTargetDocumentV054
    $targets=@($doc.targets)
    $expected=@('better-local-files','playlist-maker')
    if($targets.Count -ne 2 -or ((Get-OverlaySortedIdsV054 @($targets|ForEach-Object{$_.id})) -join ',') -ne ($expected -join ',')){throw 'Packaged overlay metadata is not the exact two-target production set.'}

    $stateRoot=Get-OverlayProductionStateRootV054
    $activeStatePath=Join-Path $stateRoot 'active-state.json'
    if(-not(Test-SafePath $activeStatePath 'Leaf')){throw 'Production lazy overlay is not currently active; refusing performance inference from a different runtime state.'}
    $state=Get-Content -LiteralPath $activeStatePath -Raw|ConvertFrom-Json
    if(((Get-OverlaySortedIdsV054 @($state.targets)) -join ',') -ne ($expected -join ',')){throw 'Production overlay active state does not contain exactly Better Local Files + Playlist Maker.'}
    if([string]$state.index_path -ne [string]$IndexPath){throw 'Production overlay state points at a different xpui index path.'}
    $currentIndexSha=Get-Sha256Lower $IndexPath
    if($currentIndexSha -ne [string]$state.transformed_index_sha256){throw 'Production overlay state/index transformed SHA-256 mismatch.'}
    $backup=[string]$state.backup_index_path
    if(-not(Test-SafePath $backup 'Leaf')){throw 'Production overlay original-index backup is missing.'}
    if((Get-Sha256Lower $backup) -ne [string]$state.original_index_sha256){throw 'Production overlay original-index backup SHA-256 mismatch.'}
    $loader=[string]$state.loader_path
    if(-not(Test-SafePath $loader 'Leaf')){throw 'Production overlay loader is missing.'}
    if((Get-Sha256Lower $loader) -ne [string]$state.loader_sha256){throw 'Production overlay loader/state SHA-256 mismatch.'}
    if([string]$state.loader_sha256 -ne $ExpectedOverlayLoaderSha){throw 'Installed production overlay loader differs from the packaged production loader.'}

    foreach($t in $targets){
        $active=Join-Path $XpuiRoot (([string]$t.extension_path)-replace '/','\')
        if(-not(Test-SafePath $active 'Leaf')){throw "Pinned overlay target is absent from active xpui: $($t.id)"}
        $size=[int64](Get-Item -LiteralPath $active).Length;$sha=Get-Sha256Lower $active
        if($size -ne [int64]$t.extension_size -or $sha -ne [string]$t.extension_sha256){throw "Pinned overlay target active bytes drifted: $($t.id)"}
    }

    $transformed=ConvertFrom-Utf8BytesStrict ([IO.File]::ReadAllBytes($IndexPath))
    $original=ConvertFrom-Utf8BytesStrict ([IO.File]::ReadAllBytes($backup))
    foreach($id in $expected){if([string]$transformed.text -notmatch [regex]::Escape('spotify-control-performance-overlay:lazy:'+ $id)){throw "Production transformed index is missing overlay marker: $id"}}
    if([string]$transformed.text -notmatch 'spotify-control-performance-overlay\.v010\.js'){throw 'Production transformed index is missing the lazy-loader hook.'}
    foreach($t in $targets){
        $src=[string]$t.extension_path
        $pattern='<script\b(?=[^>]*\bsrc\s*=\s*["''](?:\./)?'+[regex]::Escape($src)+'["''])[^>]*>\s*</script\s*>'
        if([regex]::Matches([string]$original.text,$pattern,[Text.RegularExpressions.RegexOptions]::IgnoreCase).Count -ne 1){throw "Production original-index backup does not contain exactly one eager hook for $($t.id)."}
    }
    return [pscustomobject]@{state_root=$stateRoot;active_state_path=$activeStatePath;state=$state;targets_doc=$doc;production_transformed_index_sha256=$currentIndexSha;production_original_index_sha256=(Get-Sha256Lower $backup);loader_sha256=(Get-Sha256Lower $loader);loader_path=$loader;backup_index_path=$backup}
}

function Write-OverlayProvenanceV054 {
    param([string]$Path,$TargetsDoc)
    $trusted=[ordered]@{}
    foreach($t in @($TargetsDoc.targets)){
        $active=Join-Path $XpuiRoot (([string]$t.extension_path)-replace '/','\')
        $trusted[[string]$t.id]=[ordered]@{trust='exact-active-extension';trusted_revision=[string]$t.dist_revision;source=[string]$TargetsDoc.distribution_repository;observed_sha256=(Get-Sha256Lower $active);observed_size=[int64](Get-Item -LiteralPath $active).Length}
    }
    $obj=[ordered]@{schema=1;generated_at=(Get-Date).ToString('o');targets=[pscustomobject]$trusted}
    Write-JsonUtf8V054 -Path $Path -Value $obj
    return $Path
}

function Write-OverlaySubsetMetadataV054 {
    param([string]$Name,[string[]]$TargetIds,$TargetsDoc)
    $selected=@($TargetsDoc.targets|Where-Object{$TargetIds -contains [string]$_.id})
    if($selected.Count -ne $TargetIds.Count){throw "Overlay subset $Name could not resolve all requested target ids."}
    $obj=[ordered]@{schema=[int]$TargetsDoc.schema;source_repository=[string]$TargetsDoc.source_repository;source_commit=[string]$TargetsDoc.source_commit;distribution_repository=[string]$TargetsDoc.distribution_repository;targets=$selected}
    $path=Join-Path $script:Session ('overlay-targets-'+$Name+'.json')
    Write-JsonUtf8V054 -Path $path -Value $obj
    return $path
}

function Invoke-OverlayEngineV054 {
    param([string]$MetadataPath,[string]$StateRoot,[string]$ProvenancePath=$script:OverlayProvenancePath,[string]$Root=$XpuiRoot)
    $r=Invoke-Native -FilePath 'powershell.exe' -Arguments @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$OverlayApplyPath,'-Mode','Apply','-XpuiRoot',$Root,'-ProvenancePath',$ProvenancePath,'-StateRoot',$StateRoot,'-TargetMetadataPath',$MetadataPath) -TimeoutSeconds 120
    if($r.ExitCode -ne 0){throw "Production overlay engine Apply failed with exit $($r.ExitCode): $($r.Output)"}
    try{return ([string]$r.Output|ConvertFrom-Json)}catch{throw "Production overlay engine output was not valid JSON: $($_.Exception.Message); output=$($r.Output)"}
}

function Write-IndexBytesAtomicV054 {
    param([byte[]]$Bytes)
    $dir=Split-Path -Parent $IndexPath;$leaf=[IO.Path]::GetFileName($IndexPath);$nonce=[Guid]::NewGuid().ToString('N')
    $tmp=Join-Path $dir ($leaf+'.v054.'+$nonce+'.tmp');$bak=Join-Path $dir ($leaf+'.v054.'+$nonce+'.bak')
    try{
        [IO.File]::WriteAllBytes($tmp,$Bytes)
        [IO.File]::Replace($tmp,$IndexPath,$bak)
    }finally{
        if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue}
        if(Test-Path -LiteralPath $bak){Remove-Item -LiteralPath $bak -Force -ErrorAction SilentlyContinue}
    }
}

function Reset-OverlayIndexToPristineV054 {
    $current=Get-Sha256Lower $IndexPath
    if(@($script:OverlayKnownIndexHashes) -notcontains $current){throw "Refusing overlay reset because current index SHA-256 is not a profiler-owned/known state: $current"}
    if($current -ne $script:PristineIndexHash){Write-IndexBytesAtomicV054 -Bytes ([IO.File]::ReadAllBytes($script:PristineIndexBackup))}
    if((Get-Sha256Lower $IndexPath) -ne $script:PristineIndexHash){throw 'Pristine production original-index restore verification failed.'}
}

function Build-FocusedPatchVariantMatrix {
    return @(
        [pscustomobject]@{label='BASELINE_A';profile='both';optimized_target_ids=@('better-local-files','playlist-maker');original_target_ids=@();definition='Exact production lazy overlay for Better Local Files + Playlist Maker.';category='production-optimized-baseline'},
        [pscustomobject]@{label='BLF_ORIGINAL';profile='playlist-only';optimized_target_ids=@('playlist-maker');original_target_ids=@('better-local-files');definition='Better Local Files eager/original hook; Playlist Maker remains production-lazy.';category='single-original'},
        [pscustomobject]@{label='PLAYLIST_MAKER_ORIGINAL';profile='blf-only';optimized_target_ids=@('better-local-files');original_target_ids=@('playlist-maker');definition='Playlist Maker eager/original hook; Better Local Files remains production-lazy.';category='single-original'},
        [pscustomobject]@{label='BOTH_ORIGINAL';profile='none';optimized_target_ids=@();original_target_ids=@('better-local-files','playlist-maker');definition='Both target hooks restored to exact production original/eager behavior.';category='combined-original'},
        [pscustomobject]@{label='BASELINE_B';profile='both';optimized_target_ids=@('better-local-files','playlist-maker');original_target_ids=@();definition='Exact production lazy overlay restored for closing baseline.';category='production-optimized-baseline'}
    )
}

function Prepare-Variant {
    param($Variant)
    Stop-SpotifyForVariant
    Reset-OverlayIndexToPristineV054
    if((Get-Sha256Lower $ConfigPath) -ne $script:OriginalConfigHash){throw "Spicetify config drifted before $($Variant.label)."}
    $apply=$null
    if(@($Variant.optimized_target_ids).Count -gt 0){
        $metadata=[string]$script:OverlayMetadataPaths[[string]$Variant.profile]
        if([string]::IsNullOrWhiteSpace($metadata)){throw "No overlay target metadata for profile $($Variant.profile)."}
        $stateRoot=Join-Path $script:Session ('overlay-state-'+([string]$Variant.label).ToLowerInvariant())
        $apply=Invoke-OverlayEngineV054 -MetadataPath $metadata -StateRoot $stateRoot
        if([string]$apply.status -ne 'applied'){throw "$($Variant.label) overlay engine did not report applied: $($apply|ConvertTo-Json -Depth 12 -Compress)"}
        $got=Get-OverlaySortedIdsV054 @($apply.optimized_targets);$want=Get-OverlaySortedIdsV054 @($Variant.optimized_target_ids)
        if(($got -join ',') -ne ($want -join ',')){throw "$($Variant.label) optimized unexpected targets: $($got -join ',')"}
        $hash=Get-Sha256Lower $IndexPath
        if(@($script:OverlayKnownIndexHashes) -notcontains $hash){$script:OverlayKnownIndexHashes+=@($hash)}
        if([string]$Variant.profile -eq 'both' -and $hash -ne $script:OriginalIndexHash){throw "$($Variant.label) full production overlay did not reproduce the exact initial transformed index SHA-256."}
    }else{
        if((Get-Sha256Lower $IndexPath) -ne $script:PristineIndexHash){throw "$($Variant.label) did not remain on the exact production original index."}
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
    Write-LabLog ("Spotify-targeted guarded silent playback started for {0}; optimized_targets={1}; original_targets={2}; warmup={3} sec. Spotify stays non-minimized behind the user's foreground app; other apps remain untouched." -f $Variant.label,(@($Variant.optimized_target_ids)-join ','),(@($Variant.original_target_ids)-join ','),$PlaybackWarmupSeconds)
    Start-Sleep -Seconds $PlaybackWarmupSeconds
    $start=Get-SpotifyMediaSnapshot -Session $session
    if([string]::IsNullOrWhiteSpace($start.title)){throw "Spotify media metadata is unavailable before $($Variant.label) measurement."}
    return [pscustomobject]@{profile=$Variant.profile;optimized_target_ids=@($Variant.optimized_target_ids);original_target_ids=@($Variant.original_target_ids);apply_result=$apply;index_sha256=(Get-Sha256Lower $IndexPath);spotify_media_source=$start.source_app_user_model_id;spotify_start_track=$start.identity;spotify_window_mode='startup-hidden-then-behind-user-noactivate';spotify_minimized_during_measurement=$false}
}

function Build-OverlayComparisonV054 {
    param($OptimizedBaseline,$OriginalCondition,$Mutation)
    $b=$OptimizedBaseline;$m=$OriginalCondition.metrics
    return [pscustomobject]@{
        label=$OriginalCondition.label
        cpu_p95_saved=[Math]::Round([double]$m.cpu_percent.p95-[double]$b.cpu_percent.p95,2)
        cpu_p99_saved=[Math]::Round([double]$m.cpu_percent.p99-[double]$b.cpu_percent.p99,2)
        cpu_max_saved=[Math]::Round([double]$m.cpu_percent.max-[double]$b.cpu_percent.max,2)
        renderer_p95_saved=[Math]::Round([double]$m.renderer_cpu_percent.p95-[double]$b.renderer_cpu_percent.p95,2)
        renderer_max_saved=[Math]::Round([double]$m.renderer_cpu_percent.max-[double]$b.renderer_cpu_percent.max,2)
        gpu_p95_saved=[Math]::Round([double]$m.gpu_cpu_percent.p95-[double]$b.gpu_cpu_percent.p95,2)
        working_set_p95_saved_mb=[Math]::Round([double]$m.working_set_mb.p95-[double]$b.working_set_mb.p95,1)
        original_target_ids=@($Mutation.original_target_ids)
        optimized_target_ids=@($Mutation.optimized_target_ids)
    }
}

function Restore-OriginalXpui {
    if($script:XpuiRestored){return}
    if(-not(Test-SafePath $script:OriginalIndexBackup 'Leaf')){throw 'Original production-optimized xpui index backup is missing.'}
    $current=Get-Sha256Lower $IndexPath
    if(@($script:OverlayKnownIndexHashes) -notcontains $current){throw "Refusing final restore because active index changed outside known profiler states: $current"}
    if((Get-Sha256Lower ([string]$script:OverlayPreflight.loader_path)) -ne $ExpectedOverlayLoaderSha){throw 'Production overlay loader changed during benchmark; refusing blind finalization.'}
    Write-IndexBytesAtomicV054 -Bytes ([IO.File]::ReadAllBytes($script:OriginalIndexBackup))
    if((Get-Sha256Lower $IndexPath) -ne $script:OriginalIndexHash){throw 'Original production-optimized xpui index did not restore byte-for-byte.'}
    $tree=Get-TreeFingerprint $XpuiRoot
    if($tree.sha256 -ne $script:OriginalXpuiTree.sha256 -or $tree.file_count -ne $script:OriginalXpuiTree.file_count -or $tree.total_bytes -ne $script:OriginalXpuiTree.total_bytes){throw 'Active xpui tree did not restore exactly.'}
    if((Get-Sha256Lower $ConfigPath) -ne $script:OriginalConfigHash){throw 'Spicetify config changed even though this profiler is read-only for config.'}
    $stateAfter=Get-TreeFingerprint ([string]$script:OverlayPreflight.state_root)
    if($stateAfter.sha256 -ne $script:ProductionOverlayStateFingerprint.sha256 -or $stateAfter.file_count -ne $script:ProductionOverlayStateFingerprint.file_count -or $stateAfter.total_bytes -ne $script:ProductionOverlayStateFingerprint.total_bytes){throw 'Production overlay state root changed during benchmark.'}
    $script:XpuiRestored=$true
    Write-LabLog 'Initial production-optimized xpui tree/index and production overlay state root restored/preserved exactly; Spicetify config remained unchanged.' 'OK'
}

function Build-TextReport {
    param($Report)
    $l=New-Object System.Collections.Generic.List[string]
    $l.Add("Spotify Control Production Lazy-Overlay Revalidation Report v$Version");$l.Add("Generated: $($Report.generated_at)");$l.Add('')
    $l.Add("Measurement runtime: Spotify Control $($Report.accepted_baseline.spotify_control_version) / Addon Manager $($Report.accepted_baseline.addon_manager_version) / Spotify $($Report.accepted_baseline.spotify_version) / Spicetify $($Report.accepted_baseline.spicetify_version)")
    $l.Add('Media control: Spotify-targeted Windows media session; global media keys used=False; pre-armed Spotify-only CoreAudio guard=True; other applications untouched=True; Spotify startup hidden=True; measurement window non-minimized behind user=True')
    $l.Add('Baseline definition: BASELINE_A/B = exact current production Better Local Files + Playlist Maker lazy overlay.')
    $l.Add("CPU/renderer baseline confidence: $($Report.baseline_cpu_confidence)");$l.Add(("Baseline A/B transition p95 drift: CPU={0} pts | renderer={1} pts" -f $Report.baseline_drift.cpu_p95_points,$Report.baseline_drift.renderer_p95_points))
    $l.Add("Memory baseline confidence: $($Report.baseline_memory_confidence)");$l.Add(("Baseline A/B WS p95 drift: {0} MB (memory remains secondary)" -f $Report.baseline_drift.ws_p95_mb));$l.Add('')
    foreach($c in @($Report.conditions)){$m=$c.metrics;$l.Add($c.label);$l.Add(("  CPU p50={0}% p95={1}% p99={2}% max={3}%" -f $m.cpu_percent.p50,$m.cpu_percent.p95,$m.cpu_percent.p99,$m.cpu_percent.max));$l.Add(("  Renderer p95={0}% max={1}% | GPU p95={2}% max={3}% | WS p95={4} MB | evidence={5} | verified Spotify transitions={6}" -f $m.renderer_cpu_percent.p95,$m.renderer_cpu_percent.max,$m.gpu_cpu_percent.p95,$m.gpu_cpu_percent.max,$m.working_set_mb.p95,$c.workload_policy_status,$c.verified_spotify_transitions));$l.Add('')}
    $l.Add('Lazy-overlay savings vs averaged production-optimized BASELINE_A/B (positive = production lazy overlay reduced transition cost):')
    foreach($x in @($Report.comparisons)){$l.Add(("  {0}: CPU p95 {1} pts | p99 {2} | max {3} | renderer p95 {4} | original targets {5}" -f $x.label,$x.cpu_p95_saved,$x.cpu_p99_saved,$x.cpu_max_saved,$x.renderer_p95_saved,(@($x.original_target_ids)-join ',')))}
    $l.Add('');$l.Add('Safety:')
    $l.Add('- Spotify was controlled through its own Windows media session; no global Play/Pause/NEXT key was emitted.')
    $l.Add('- A Spotify-only CoreAudio guard muted/restored Spotify sessions only; other applications were not changed.')
    $l.Add('- Every recorded transition required Spotify media metadata/position to confirm the Spotify track changed.')
    $l.Add('- Measurement started only from an exact active production overlay state for Better Local Files + Playlist Maker with exact pinned extension bytes, state/index hash, original-index backup and loader hash.')
    $l.Add('- Conditions change only index hook loading policy: target extension payload bytes are never edited, deleted or renamed.')
    $l.Add('- The real production overlay state directory is never used as an experimental state root and must remain byte-for-byte/fingerprint unchanged.')
    $l.Add('- Star Ratings v0.6.20 production optimization remains identical in every condition; ivLyrics, Tagify, Splitify, SC Cover Ambience, Marketplace and unknown hooks are untouched.')
    $l.Add('- Browser/Default Spotify WebView persistence is safety-backed up and never edited.')
    $l.Add('- Initial production-optimized index and complete xpui tree are restored exactly; config-xpui.ini remains byte-for-byte unchanged.')
    return ($l -join [Environment]::NewLine)
}

function Invoke-Lab {
    if($SampleIntervalMs -lt 200 -or $SampleIntervalMs -gt 1000){throw 'SampleIntervalMs must be 200..1000.'}
    if($TransitionSeconds -lt 26){throw 'TransitionSeconds must be at least 26 to cover all three verified Spotify NEXT events.'}
    $accepted=Assert-AcceptedRuntimeBaseline
    Suspend-Resident
    if(-not(Wait-ControlWorkersIdle 10)){throw 'A Spotify Control worker became active after resident suspension.'}
    $preflightSpotifyCount=@(Get-Process Spotify -ErrorAction SilentlyContinue).Count
    if($preflightSpotifyCount -gt 0){
        Write-LabLog ("Detected {0} residual Spotify process(es) after accepted-state checks; closing them before any xpui mutation." -f $preflightSpotifyCount) 'WARN'
        Stop-SpotifyForVariant
        if(@(Get-Process Spotify -ErrorAction SilentlyContinue).Count -gt 0){throw 'Residual Spotify process cleanup failed before xpui mutation.'}
        Write-LabLog 'Residual Spotify processes closed before any xpui mutation.' 'OK'
    }
    $script:ProductionAlignment=Align-ReleasedProductionBaseline -Accepted $accepted
    $script:MeasurementBaseline=[pscustomobject]@{baseline_kind='current-v0620-r9';spotify_control_version='0.6.20';addon_manager_version='0.6.5-r9';spotify_version=$accepted.spotify_version;spicetify_version=$accepted.spicetify_version;hashes=$script:ProductionAlignment.hashes}

    $stamp=Get-Date -Format 'yyyyMMdd-HHmmss';$script:Session=Join-Path $BackupRoot $stamp;New-Item -ItemType Directory -Force -Path $script:Session|Out-Null
    $script:OriginalConfigHash=Get-Sha256Lower $ConfigPath
    $script:OriginalExtensions=@(Get-IniList -Path $ConfigPath -Section 'AdditionalOptions' -Key 'extensions')
    $script:OriginalApps=@(Get-IniList -Path $ConfigPath -Section 'AdditionalOptions' -Key 'custom_apps')
    $script:OverlayPreflight=Assert-OverlayBenchmarkEligibilityV054
    $script:ProductionOverlayStateFingerprint=Get-TreeFingerprint ([string]$script:OverlayPreflight.state_root)
    $script:OriginalIndexBackup=Join-Path $script:Session 'xpui-index.production-optimized.original.html';Copy-Item -LiteralPath $IndexPath -Destination $script:OriginalIndexBackup -Force;$script:OriginalIndexHash=Get-Sha256Lower $IndexPath
    $script:PristineIndexBackup=Join-Path $script:Session 'xpui-index.production-original-eager.html';Copy-Item -LiteralPath ([string]$script:OverlayPreflight.backup_index_path) -Destination $script:PristineIndexBackup -Force;$script:PristineIndexHash=Get-Sha256Lower $script:PristineIndexBackup
    if($script:PristineIndexHash -ne [string]$script:OverlayPreflight.production_original_index_sha256){throw 'Copied pristine production index SHA-256 mismatch.'}
    $script:OriginalXpuiTree=Get-TreeFingerprint $XpuiRoot
    $script:OverlayKnownIndexHashes=@($script:OriginalIndexHash,$script:PristineIndexHash)
    $script:XpuiMutationStarted=$true
    $script:HookInventory=Get-IndexHookInventoryFromBytes -Bytes ([IO.File]::ReadAllBytes($IndexPath)) -ConfiguredExtensions $script:OriginalExtensions -ConfiguredApps $script:OriginalApps
    $script:PersistenceBackup=Backup-ProtectedPersistence (Join-Path $script:Session 'protected-persistence')
    $script:OverlayTargetsDoc=$script:OverlayPreflight.targets_doc
    $script:OverlayProvenancePath=Write-OverlayProvenanceV054 -Path (Join-Path $script:Session 'overlay-exact-provenance.json') -TargetsDoc $script:OverlayTargetsDoc
    $script:OverlayMetadataPaths=@{
        both=(Write-OverlaySubsetMetadataV054 -Name 'both' -TargetIds @('better-local-files','playlist-maker') -TargetsDoc $script:OverlayTargetsDoc)
        'playlist-only'=(Write-OverlaySubsetMetadataV054 -Name 'playlist-only' -TargetIds @('playlist-maker') -TargetsDoc $script:OverlayTargetsDoc)
        'blf-only'=(Write-OverlaySubsetMetadataV054 -Name 'blf-only' -TargetIds @('better-local-files') -TargetsDoc $script:OverlayTargetsDoc)
    }
    $variants=@(Build-FocusedPatchVariantMatrix);$variantCount=$variants.Count
    if($variantCount -ne 5){throw 'Overlay revalidation matrix must contain exactly five conditions.'}

    Write-Host '';Write-Host "Spotify Control Production Lazy-Overlay Revalidation v$Version" -ForegroundColor Cyan;Write-Host '-------------------------------------------------------------'
    Write-Host 'One integrated run: 5 conditions x 3 verified Spotify-targeted NEXT transitions.'
    Write-Host 'Production optimized baseline -> BLF original -> Playlist Maker original -> both original -> production optimized baseline.'
    Write-Host 'Target extension payload bytes never change; only exact index loading policy changes.' -ForegroundColor Green
    Write-Host 'Spotify stays silent during measurement. You may use other apps and play other media; do not interact with Spotify itself.' -ForegroundColor Yellow
    Write-Host 'The resident is temporarily suspended and restored automatically.' -ForegroundColor Yellow;Write-Host ''

    $raw=New-Object System.Collections.Generic.List[object];$analyses=New-Object System.Collections.Generic.List[object];$mutations=New-Object System.Collections.Generic.List[object]
    foreach($v in $variants){
        Write-Host ("[{0}/{1}] {2}" -f ($analyses.Count+1),$variantCount,$v.label) -ForegroundColor Cyan
        $mut=Prepare-Variant $v
        $mutations.Add([pscustomobject]@{label=$v.label;profile=$v.profile;optimized_target_ids=@($v.optimized_target_ids);original_target_ids=@($v.original_target_ids);definition=$v.definition;category=$v.category;index_sha256=$mut.index_sha256;apply_result=$mut.apply_result})
        $m=Measure-TransitionCondition -Label $v.label
        foreach($r in $m.rows){$raw.Add($r)}
        $a=Analyze-Transitions -Label $v.label -Rows $m.rows -Events $m.events
        $policy=Get-WorkloadPolicy -Label $v.label -Analysis $a
        Add-Member -InputObject $a -NotePropertyName workload_policy_status -NotePropertyValue ([string]$policy.status) -Force;Add-Member -InputObject $a -NotePropertyName verified_spotify_transitions -NotePropertyValue ([int]$m.verified_spotify_transitions) -Force;Add-Member -InputObject $a -NotePropertyName min_spotify_process_count -NotePropertyValue ([int]$m.min_spotify_process_count) -Force;Add-Member -InputObject $a -NotePropertyName end_spotify_process_count -NotePropertyValue ([int]$m.end_spotify_process_count) -Force
        if(-not $policy.accepted){throw "$($v.label) baseline workload canary failed."}
        if(-not $a.workload_canary_pass){Write-LabLog ("{0} low transition response retained as causal evidence; Spotify stayed alive and all targeted Spotify NEXT transitions were metadata-confirmed." -f $v.label) 'WARN'}
        $analyses.Add($a);Write-ProgressCheckpoint -Analyses $analyses.ToArray() -Mutations $mutations.ToArray() -Raw $raw.ToArray() -VariantCount $variantCount -CurrentLabel $v.label
        Write-LabLog ("Completed {0}: CPU p95={1}% p99={2}% max={3}% renderer p95={4}% evidence={5}" -f $v.label,$a.metrics.cpu_percent.p95,$a.metrics.cpu_percent.p99,$a.metrics.cpu_percent.max,$a.metrics.renderer_cpu_percent.p95,$a.workload_policy_status) 'OK'
    }
    Stop-SpotifyForVariant
    Restore-OriginalXpui

    $a0=@($analyses|Where-Object label -eq 'BASELINE_A')[0];$b0=@($analyses|Where-Object label -eq 'BASELINE_B')[0];$base=Average-TwoMetricSummaries $a0.metrics $b0.metrics
    $drift=[pscustomobject]@{cpu_p95_points=[Math]::Round([Math]::Abs([double]$a0.metrics.cpu_percent.p95-[double]$b0.metrics.cpu_percent.p95),2);cpu_p99_points=[Math]::Round([Math]::Abs([double]$a0.metrics.cpu_percent.p99-[double]$b0.metrics.cpu_percent.p99),2);renderer_p95_points=[Math]::Round([Math]::Abs([double]$a0.metrics.renderer_cpu_percent.p95-[double]$b0.metrics.renderer_cpu_percent.p95),2);ws_p95_mb=[Math]::Round([Math]::Abs([double]$a0.metrics.working_set_mb.p95-[double]$b0.metrics.working_set_mb.p95),1)}
    $cpuConfidence='high';if($drift.cpu_p95_points -gt 8 -or $drift.renderer_p95_points -gt 6){$cpuConfidence='low'}elseif($drift.cpu_p95_points -gt 4 -or $drift.renderer_p95_points -gt 3){$cpuConfidence='medium'}
    $memoryConfidence='high';if($drift.ws_p95_mb -gt 180){$memoryConfidence='low'}elseif($drift.ws_p95_mb -gt 100){$memoryConfidence='medium'}
    $comparisons=New-Object System.Collections.Generic.List[object]
    foreach($a in @($analyses|Where-Object{$_.label -notmatch '^BASELINE_'})){$mut=@($mutations|Where-Object label -eq $a.label)[0];$comparisons.Add((Build-OverlayComparisonV054 -OptimizedBaseline $base -OriginalCondition $a -Mutation $mut))}

    $report=[pscustomobject]@{
        version=$Version;generated_at=(Get-Date).ToString('o');verified_run=$true;accepted_baseline=$script:MeasurementBaseline;production_alignment=$script:ProductionAlignment;production_alignment_precedes_snapshot=$true;preflight_spotify_processes_autoclosed=$preflightSpotifyCount;sample_interval_ms=$SampleIntervalMs;transition_window_seconds=$TransitionWindowSeconds;next_offsets_seconds=$NextOffsets
        original_extensions=$script:OriginalExtensions;original_custom_apps=$script:OriginalApps;protected_apps=$ProtectedAppNames;persistence_backup=$script:PersistenceBackup;session=$script:Session
        media_control='spotify-targeted-gsmtc';global_media_keys_used=$false;spotify_audio_muted_during_workload=$true;spotify_audio_guard='prearmed-session-notification-plus-5ms-poll';other_media_apps_controlled=$false;spotify_window_mode='startup-hidden-then-behind-user-noactivate';spotify_minimized_during_measurement=$false;mutation_engine='exact-production-lazy-overlay-index-policy-only';overlay_preflight=$script:OverlayPreflight;production_overlay_state_root_untouched=$true;spicetify_apply_used=$false;spicetify_config_mutated=$false;xpui_index_mutated=$true;extension_payloads_mutated=$false;xpui_root=$XpuiRoot;production_optimized_index_sha256=$script:OriginalIndexHash;production_original_eager_index_sha256=$script:PristineIndexHash;original_xpui_tree=$script:OriginalXpuiTree
        variant_mutations=$mutations.ToArray();baseline_average=$base;baseline_drift=$drift;baseline_cpu_confidence=$cpuConfidence;baseline_memory_confidence=$memoryConfidence;baseline_confidence=$cpuConfidence;conditions=$analyses.ToArray();comparisons=$comparisons.ToArray()
        config_unchanged_exact=((Get-Sha256Lower $ConfigPath)-eq $script:OriginalConfigHash);index_restored_exact=((Get-Sha256Lower $IndexPath)-eq $script:OriginalIndexHash);xpui_tree_restored_exact=((Get-TreeFingerprint $XpuiRoot).sha256 -eq $script:OriginalXpuiTree.sha256);production_overlay_state_unchanged_exact=((Get-TreeFingerprint ([string]$script:OverlayPreflight.state_root)).sha256 -eq $script:ProductionOverlayStateFingerprint.sha256);resident_process_count_after=$null;workload_canary='All recorded NEXT events must be Spotify-targeted and metadata/position-confirmed; BASELINE_A/B require at least 2/3 verified transition windows >= 1.5% Spotify-process CPU.'
    }
    if(-not $report.config_unchanged_exact -or -not $report.index_restored_exact -or -not $report.xpui_tree_restored_exact -or -not $report.production_overlay_state_unchanged_exact){throw 'Final exact restore/state-preservation verification failed before report publication.'}
    $text=Build-TextReport $report
    $sessionJson=Join-Path $script:Session 'track-transition-overlay-v054.json';$sessionTxt=Join-Path $script:Session 'track-transition-overlay-v054.txt';$sessionCsv=Join-Path $script:Session 'track-transition-overlay-v054-raw.csv'
    $report|ConvertTo-Json -Depth 24|Set-Content -LiteralPath $sessionJson -Encoding UTF8;$text|Set-Content -LiteralPath $sessionTxt -Encoding UTF8;$raw.ToArray()|Export-Csv -LiteralPath $sessionCsv -NoTypeInformation -Encoding UTF8
    Copy-Item $sessionJson $LatestJson -Force;Copy-Item $sessionTxt $LatestTxt -Force;Copy-Item $sessionCsv $LatestCsv -Force
    Restore-Resident;$report.resident_process_count_after=@(Get-ResidentProcesses).Count;$report|ConvertTo-Json -Depth 24|Set-Content -LiteralPath $sessionJson -Encoding UTF8;Copy-Item $sessionJson $LatestJson -Force
    Write-Host '';Write-Host 'PRODUCTION LAZY-OVERLAY REVALIDATION VERIFIED' -ForegroundColor Green;Write-Host $text;Write-Host '';Write-Host ('Report: '+$LatestTxt) -ForegroundColor Cyan;Write-Host ('JSON:   '+$LatestJson);Write-Host ('CSV:    '+$LatestCsv)
}

function Invoke-SelfTest {
    $vals=@();for($i=1;$i -le 100;$i++){$vals+=[double]$i};if((Get-Percentile $vals 95)-ne95){throw 'Percentile self-test failed.'};if((Get-Median @(1.0,2.0,3.0,4.0))-ne2.5){throw 'Median self-test failed.'}
    Assert-OverlayPackageIdentityV054
    $cur=[pscustomobject]@{main=$ExpectedMainSha;addon=$ExpectedAddonSha;agent=$ExpectedAgentSha;bootstrap=$ExpectedBootstrapSha};$prev=[pscustomobject]@{main=$PreviousMainSha;addon=$PreviousAddonSha;agent=$ExpectedAgentSha;bootstrap=$ExpectedBootstrapSha};$prev2=[pscustomobject]@{main=$Previous2MainSha;addon=$Previous2AddonSha;agent=$ExpectedAgentSha;bootstrap=$ExpectedBootstrapSha};$bad=[pscustomobject]@{main='bad';addon=$ExpectedAddonSha;agent=$ExpectedAgentSha;bootstrap=$ExpectedBootstrapSha}
    if((Get-ComponentBaselineKind $cur)-ne'current-v0620-r9' -or (Get-ComponentBaselineKind $prev)-ne'previous-v0619-r8' -or (Get-ComponentBaselineKind $prev2)-ne'previous-v0618-r7' -or (Get-ComponentBaselineKind $bad)-ne'unknown-or-partial'){throw 'Production component baseline classifier self-test failed.'}
    $matrix=@(Build-FocusedPatchVariantMatrix);if($matrix.Count-ne5 -or ($matrix.label-join ',')-ne'BASELINE_A,BLF_ORIGINAL,PLAYLIST_MAKER_ORIGINAL,BOTH_ORIGINAL,BASELINE_B'){throw 'Overlay matrix self-test failed.'};if(@($matrix[0].optimized_target_ids).Count-ne2 -or @($matrix[1].original_target_ids).Count-ne1 -or @($matrix[2].original_target_ids).Count-ne1 -or @($matrix[3].original_target_ids).Count-ne2){throw 'Overlay matrix cardinality self-test failed.'}

    $tmp=Join-Path ([IO.Path]::GetTempPath()) ('spotify-control-overlay-v054-selftest-'+[Guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Force -Path $tmp|Out-Null
    try{
        $root=Join-Path $tmp 'xpui';$ext=Join-Path $root 'extensions';New-Item -ItemType Directory -Force -Path (Join-Path $ext 'better-local-files'),(Join-Path $ext 'playlist-maker')|Out-Null
        $blf=Join-Path $ext 'better-local-files\extension.js';$pm=Join-Path $ext 'playlist-maker\extension.js';[IO.File]::WriteAllText($blf,'window.__blfFixture=1;',(New-Object Text.UTF8Encoding($false)));[IO.File]::WriteAllText($pm,'window.__pmFixture=1;',(New-Object Text.UTF8Encoding($false)))
        $idx=Join-Path $root 'index.html';$html='<html><head></head><body><script defer src="extensions/better-local-files/extension.js"></script><script defer src="extensions/playlist-maker/extension.js"></script></body></html>';[IO.File]::WriteAllText($idx,$html,(New-Object Text.UTF8Encoding($false)));$origSha=Get-Sha256Lower $idx
        $targets=[ordered]@{schema=1;source_repository='fixture/source';source_commit='fixture';distribution_repository='fixture/dist';targets=@([ordered]@{id='better-local-files';dist_revision='fixture-blf';extension_path='extensions/better-local-files/extension.js';extension_size=[int64](Get-Item $blf).Length;extension_sha256=(Get-Sha256Lower $blf);route_prefixes=@('/better-local-files');readiness=[ordered]@{kind='global-property';property='localTracksService';timeoutMs=10000}},[ordered]@{id='playlist-maker';dist_revision='fixture-pm';extension_path='extensions/playlist-maker/extension.js';extension_size=[int64](Get-Item $pm).Length;extension_sha256=(Get-Sha256Lower $pm);route_prefixes=@('/playlist-maker');readiness=[ordered]@{kind='playlist-maker-migrations';timeoutMs=10000}})}
        $targetsPath=Join-Path $tmp 'targets-both.json';Write-JsonUtf8V054 $targetsPath $targets
        $trusted=[ordered]@{'better-local-files'=[ordered]@{trust='exact-active-extension';trusted_revision='fixture-blf';source='fixture/dist';observed_sha256=(Get-Sha256Lower $blf);observed_size=[int64](Get-Item $blf).Length};'playlist-maker'=[ordered]@{trust='exact-active-extension';trusted_revision='fixture-pm';source='fixture/dist';observed_sha256=(Get-Sha256Lower $pm);observed_size=[int64](Get-Item $pm).Length}}
        $prov=Join-Path $tmp 'prov.json';Write-JsonUtf8V054 $prov ([ordered]@{schema=1;targets=[pscustomobject]$trusted})
        $state1=Join-Path $tmp 'state-both';$both=Invoke-OverlayEngineV054 -MetadataPath $targetsPath -StateRoot $state1 -ProvenancePath $prov -Root $root
        if([string]$both.status-ne'applied' -or @($both.optimized_targets).Count-ne2 -or (Get-Sha256Lower $idx)-eq$origSha){throw 'Synthetic both-target overlay apply failed.'}
        $txt=[IO.File]::ReadAllText($idx);if($txt-notmatch'spotify-control-performance-overlay:lazy:better-local-files' -or $txt-notmatch'spotify-control-performance-overlay:lazy:playlist-maker'){throw 'Synthetic both-target markers missing.'}
        [IO.File]::WriteAllText($idx,$html,(New-Object Text.UTF8Encoding($false)));if((Get-Sha256Lower $idx)-ne$origSha){throw 'Synthetic pristine reset failed.'}
        $one=[ordered]@{schema=1;source_repository='fixture/source';source_commit='fixture';distribution_repository='fixture/dist';targets=@($targets.targets[1])};$onePath=Join-Path $tmp 'targets-pm.json';Write-JsonUtf8V054 $onePath $one;$state2=Join-Path $tmp 'state-pm';$pmOnly=Invoke-OverlayEngineV054 -MetadataPath $onePath -StateRoot $state2 -ProvenancePath $prov -Root $root
        $txt=[IO.File]::ReadAllText($idx);if([string]$pmOnly.status-ne'applied' -or $txt-notmatch'spotify-control-performance-overlay:lazy:playlist-maker' -or $txt-match'spotify-control-performance-overlay:lazy:better-local-files' -or $txt-notmatch'extensions/better-local-files/extension.js'){throw 'Synthetic subset overlay apply failed.'}
        [IO.File]::WriteAllText($idx,$html,(New-Object Text.UTF8Encoding($false)));[IO.File]::WriteAllText($pm,'changed',(New-Object Text.UTF8Encoding($false)));$state3=Join-Path $tmp 'state-drift';$drift=Invoke-OverlayEngineV054 -MetadataPath $onePath -StateRoot $state3 -ProvenancePath $prov -Root $root
        if([string]$drift.status-ne'no-op' -or [string]$drift.reason-ne'no-exactly-proven-targets'){throw 'Unknown/drifted extension fail-open self-test failed.'}
        Write-Host 'SELFTEST PASS: real production overlay engine applied both/subset fixture variants and skipped drifted bytes without mutating production paths.'
    }finally{Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue}
    Write-LabLog "Production lazy-overlay revalidation v$Version self-test passed; production paths were not mutated." 'OK'
    Write-Host 'SELFTEST PASS: v0.6.20/r9 classifier, five-condition overlay matrix, exact production engine package identity, subset transform, and fail-open unknown-byte behavior.'
}
