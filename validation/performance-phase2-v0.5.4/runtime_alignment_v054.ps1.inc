function Get-ComponentHashSnapshot {
    return [pscustomobject]@{
        main=(Get-Sha256Lower $MainPath)
        addon=(Get-Sha256Lower $AddonPath)
        agent=(Get-Sha256Lower $AgentPath)
        bootstrap=(Get-Sha256Lower $BootstrapPath)
    }
}

function Get-ComponentBaselineKind {
    param($Actual)
    if($Actual.main -eq $ExpectedMainSha -and $Actual.addon -eq $ExpectedAddonSha -and $Actual.agent -eq $ExpectedAgentSha -and $Actual.bootstrap -eq $ExpectedBootstrapSha){return 'current-v0620-r9'}
    if($Actual.main -eq $PreviousMainSha -and $Actual.addon -eq $PreviousAddonSha -and $Actual.agent -eq $ExpectedAgentSha -and $Actual.bootstrap -eq $ExpectedBootstrapSha){return 'previous-v0619-r8'}
    if($Actual.main -eq $Previous2MainSha -and $Actual.addon -eq $Previous2AddonSha -and $Actual.agent -eq $ExpectedAgentSha -and $Actual.bootstrap -eq $ExpectedBootstrapSha){return 'previous-v0618-r7'}
    return 'unknown-or-partial'
}

function Write-ComponentHashDiagnostics {
    param($Actual,[string]$Prefix='Component identity')
    Write-LabLog ("{0}: main actual={1} expected-current={2} expected-v0619={3} expected-v0618={4}" -f $Prefix,$Actual.main,$ExpectedMainSha,$PreviousMainSha,$Previous2MainSha) 'INFO'
    Write-LabLog ("{0}: addon actual={1} expected-current={2} expected-v0619={3} expected-v0618={4}" -f $Prefix,$Actual.addon,$ExpectedAddonSha,$PreviousAddonSha,$Previous2AddonSha) 'INFO'
    Write-LabLog ("{0}: agent actual={1} expected={2}" -f $Prefix,$Actual.agent,$ExpectedAgentSha) 'INFO'
    Write-LabLog ("{0}: bootstrap actual={1} expected={2}" -f $Prefix,$Actual.bootstrap,$ExpectedBootstrapSha) 'INFO'
}

function Invoke-BootstrapJson {
    param([ValidateSet('Check','Update')][string]$BootstrapAction)
    $r=Invoke-Native -FilePath 'powershell.exe' -Arguments @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$BootstrapPath,'-Action',$BootstrapAction,'-Json') -TimeoutSeconds 300
    if($r.ExitCode -ne 0){throw "Bootstrap $BootstrapAction failed with exit $($r.ExitCode): $($r.Output)"}
    $lines=@([string]$r.Output -split "`r?`n")
    $jsonLine=@($lines|Where-Object{([string]$_).TrimStart().StartsWith('{')}|Select-Object -Last 1)
    if($jsonLine.Count -ne 1){throw "Bootstrap $BootstrapAction emitted no unambiguous JSON result."}
    try{return ([string]$jsonLine[0]|ConvertFrom-Json)}catch{throw "Bootstrap $BootstrapAction JSON parse failed: $($_.Exception.Message)"}
}

function Align-ReleasedProductionBaseline {
    param($Accepted)
    if(-not $script:ResidentSuspended){throw 'Production alignment requires the resident to be suspended first.'}
    if(@(Get-Process Spotify -ErrorAction SilentlyContinue).Count -ne 0){throw 'Production alignment requires Spotify to be fully stopped first.'}
    if(-not(Wait-ControlWorkersIdle 30)){throw 'Spotify Control worker is active before production alignment.'}

    $alignment=[string]$Accepted.baseline_kind
    $installed=$null;$edges=0
    if($Accepted.baseline_kind -eq 'previous-v0619-r8'){$installed='0.6.19';$edges=1;$alignment='auto-updated-v0619-r8-to-v0620-r9'}
    elseif($Accepted.baseline_kind -eq 'previous-v0618-r7'){$installed='0.6.18';$edges=2;$alignment='auto-updated-v0618-r7-to-v0620-r9'}
    elseif($Accepted.baseline_kind -eq 'current-v0620-r9'){$alignment='already-current-v0620-r9'}
    else{throw "Unexpected preflight baseline kind during alignment: $($Accepted.baseline_kind)"}

    if($edges -gt 0){
        Write-LabLog ("Exact previous production {0} detected. Running validated Bootstrap 1.0.6 {1}-edge update to v0.6.20 while resident/Spotify are stopped." -f $installed,$edges) 'WARN'
        $check=Invoke-BootstrapJson -BootstrapAction 'Check'
        if(-not [bool]$check.success -or [string]$check.installed_version -ne $installed -or [int]$check.result.edge_count -ne $edges){throw "Bootstrap Check did not prove the exact $installed -> v0.6.20 $edges-edge update path."}
        $up=Invoke-BootstrapJson -BootstrapAction 'Update'
        if(-not [bool]$up.success -or [string]$up.transaction_status -ne 'committed'){throw 'Bootstrap Update did not commit the exact v0.6.20 production update.'}
    }

    $postUpdate=Get-ComponentHashSnapshot
    Write-ComponentHashDiagnostics -Actual $postUpdate -Prefix 'Post-bootstrap component identity'
    if((Get-ComponentBaselineKind $postUpdate) -ne 'current-v0620-r9'){throw 'Production alignment did not converge to exact released v0.6.20/r9 component identities.'}

    $addon=Invoke-Native -FilePath 'powershell.exe' -Arguments @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$AddonPath,'-Action','Update') -TimeoutSeconds 900
    if($addon.ExitCode -ne 0){throw "Released Addon Manager r9 Update/alignment failed with exit $($addon.ExitCode): $($addon.Output)"}
    if(@(Get-ResidentProcesses).Count -ne 0){throw 'Addon Manager alignment unexpectedly restarted the resident.'}
    if(@(Get-Process Spotify -ErrorAction SilentlyContinue).Count -gt 0){Stop-SpotifyForVariant}
    if(-not(Wait-ControlWorkersIdle 30)){throw 'Spotify Control worker remained active after Addon Manager alignment.'}

    $final=Get-ComponentHashSnapshot
    Write-ComponentHashDiagnostics -Actual $final -Prefix 'Final production-aligned component identity'
    if((Get-ComponentBaselineKind $final) -ne 'current-v0620-r9'){throw 'Addon Manager alignment changed released Spotify Control component identities.'}
    Write-LabLog 'Released v0.6.20/r9 production baseline and Addon Manager update/Star-Ratings/overlay cycle aligned before measurement snapshot.' 'OK'
    return [pscustomobject]@{status='aligned';production_alignment=$alignment;addon_manager_alignment='update-completed';hashes=$final;addon_output=$addon.Output}
}

function Assert-AcceptedRuntimeBaseline {
    if(Test-IsElevated){throw 'Run this profiler as the normal desktop user, not as Administrator.'}
    foreach($p in @($MainPath,$AddonPath,$AgentPath,$BootstrapPath,$ConfigPath,$SpotifyExe,$IndexPath)){if(-not(Test-SafePath $p 'Leaf')){throw "Required accepted-state file is missing: $p"}}
    try{
        $task=Get-ScheduledTask -TaskName $ResidentTaskName -ErrorAction Stop
        if([string]$task.State -eq 'Disabled'){throw 'Resident task is disabled.'}
        $action=@($task.Actions|Select-Object -First 1)[0]
        if($null -eq $action -or [string]$action.Execute -notmatch '(?i)wscript(?:\.exe)?$' -or [string]$action.Arguments -notmatch [regex]::Escape('spotify-control-agent.vbs')){throw 'Resident task action no longer matches the accepted wscript agent.'}
    }catch{throw ('Accepted resident task precheck failed: '+$_.Exception.Message)}
    if(-not(Wait-ControlWorkersIdle 30)){throw 'Spotify Control maintenance is still active. Refusing to overlap profiling.'}

    $actual=Get-ComponentHashSnapshot
    $kind=Get-ComponentBaselineKind $actual
    Write-ComponentHashDiagnostics -Actual $actual -Prefix 'Read-only preflight component identity'
    if($kind -eq 'unknown-or-partial'){
        $msg=("Unknown or partial Spotify Control component state. No production files were changed. main={0}; addon={1}; agent={2}; bootstrap={3}. Expected current v0620/r9 main={4}, addon={5}; v0619/r8 main={6}, addon={7}; v0618/r7 main={8}, addon={9}; shared agent={10}, bootstrap={11}." -f $actual.main,$actual.addon,$actual.agent,$actual.bootstrap,$ExpectedMainSha,$ExpectedAddonSha,$PreviousMainSha,$PreviousAddonSha,$Previous2MainSha,$Previous2AddonSha,$ExpectedAgentSha,$ExpectedBootstrapSha)
        throw $msg
    }

    $spotifyVersion=([string](Get-Item -LiteralPath $SpotifyExe).VersionInfo.ProductVersion).Trim()
    if($spotifyVersion -notmatch ('^'+[regex]::Escape($ExpectedSpotifyVersion)+'(?:\.|$)')){throw "Spotify version drifted from accepted baseline: $spotifyVersion"}
    $sp=Invoke-Native -FilePath (Get-SpicetifyExe) -Arguments @('--version')
    if($sp.ExitCode -ne 0 -or [string]$sp.Output -notmatch [regex]::Escape($ExpectedSpicetifyVersion)){throw "Spicetify version drifted from accepted baseline: $($sp.Output)"}
    $controlVersion=$(if($kind -eq 'current-v0620-r9'){'0.6.20'}elseif($kind -eq 'previous-v0619-r8'){'0.6.19'}else{'0.6.18'})
    $addonVersion=$(if($kind -eq 'current-v0620-r9'){'0.6.5-r9'}elseif($kind -eq 'previous-v0619-r8'){'0.6.5-r8'}else{'0.6.5-r7'})
    return [pscustomobject]@{baseline_kind=$kind;spotify_control_version=$controlVersion;addon_manager_version=$addonVersion;spotify_version=$spotifyVersion;spicetify_version=$ExpectedSpicetifyVersion;hashes=$actual}
}
