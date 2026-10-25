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
    if($Actual.main -eq $ExpectedMainSha -and $Actual.addon -eq $ExpectedAddonSha -and $Actual.agent -eq $ExpectedAgentSha -and $Actual.bootstrap -eq $ExpectedBootstrapSha){return 'current-v0619-r8'}
    if($Actual.main -eq $PreviousMainSha -and $Actual.addon -eq $PreviousAddonSha -and $Actual.agent -eq $ExpectedAgentSha -and $Actual.bootstrap -eq $ExpectedBootstrapSha){return 'previous-v0618-r7'}
    return 'unknown-or-partial'
}

function Write-ComponentHashDiagnostics {
    param($Actual,[string]$Prefix='Component identity')
    Write-LabLog ("{0}: main actual={1} expected-current={2} expected-previous={3}" -f $Prefix,$Actual.main,$ExpectedMainSha,$PreviousMainSha) 'INFO'
    Write-LabLog ("{0}: addon actual={1} expected-current={2} expected-previous={3}" -f $Prefix,$Actual.addon,$ExpectedAddonSha,$PreviousAddonSha) 'INFO'
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

function Align-ReleasedAddonManagerBaseline {
    $r=Invoke-Native -FilePath 'powershell.exe' -Arguments @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$AddonPath,'-Action','Update') -TimeoutSeconds 900
    if($r.ExitCode -ne 0){throw "Released Addon Manager r8 Update/alignment failed with exit $($r.ExitCode): $($r.Output)"}
    Write-LabLog 'Released Addon Manager r8 Update/alignment completed before the measurement snapshot.' 'OK'
    return [pscustomobject]@{status='addon-manager-r8-update-completed';output=$r.Output}
}

function Assert-AcceptedRuntimeBaseline {
    if(Test-IsElevated){throw "Run this profiler as the normal desktop user, not as Administrator."}
    foreach($p in @($MainPath,$AddonPath,$AgentPath,$BootstrapPath,$ConfigPath,$SpotifyExe,$IndexPath,$PatchEnginePath,$PatchTargetsPath)){if(-not(Test-SafePath $p "Leaf")){throw "Required accepted-state file is missing: $p"}}
    try{
        $task=Get-ScheduledTask -TaskName $ResidentTaskName -ErrorAction Stop
        if([string]$task.State -eq 'Disabled'){throw 'Resident task is disabled.'}
        $action=@($task.Actions|Select-Object -First 1)[0]
        if($null -eq $action -or [string]$action.Execute -notmatch '(?i)wscript(?:\.exe)?$' -or [string]$action.Arguments -notmatch [regex]::Escape('spotify-control-agent.vbs')){throw 'Resident task action no longer matches the accepted wscript agent.'}
    }catch{throw ('Accepted resident task precheck failed: '+$_.Exception.Message)}
    if(-not(Wait-ControlWorkersIdle 30)){throw 'Spotify Control maintenance is still active. Refusing to overlap production alignment/profiling.'}

    $actual=Get-ComponentHashSnapshot
    $kind=Get-ComponentBaselineKind $actual
    Write-ComponentHashDiagnostics -Actual $actual -Prefix 'Preflight component identity'
    $alignment='already-current-v0619-r8'
    if($kind -eq 'previous-v0618-r7'){
        Write-LabLog 'Exact previous production v0.6.18/r7 detected. Running validated Bootstrap 1.0.6 one-edge update to v0.6.19/r8 before profiling.' 'WARN'
        $check=Invoke-BootstrapJson -BootstrapAction 'Check'
        if(-not [bool]$check.success -or [string]$check.installed_version -ne '0.6.18' -or [int]$check.result.edge_count -ne 1){throw 'Bootstrap Check did not prove the exact one-edge v0.6.18 -> v0.6.19 update path.'}
        $up=Invoke-BootstrapJson -BootstrapAction 'Update'
        if(-not [bool]$up.success -or [string]$up.transaction_status -ne 'committed'){throw 'Bootstrap Update did not commit the exact v0.6.19 production update.'}
        $actual=Get-ComponentHashSnapshot
        Write-ComponentHashDiagnostics -Actual $actual -Prefix 'Post-update component identity'
        if((Get-ComponentBaselineKind $actual) -ne 'current-v0619-r8'){throw 'Bootstrap committed but final v0.6.19/r8 component identities did not match the released production set.'}
        $alignment='auto-updated-v0618-r7-to-v0619-r8'
    }elseif($kind -ne 'current-v0619-r8'){
        $msg=("Unknown or partial Spotify Control component state. No production files were changed. main={0}; addon={1}; agent={2}; bootstrap={3}. Expected current main={4}, addon={5}; previous main={6}, addon={7}; shared agent={8}, bootstrap={9}." -f $actual.main,$actual.addon,$actual.agent,$actual.bootstrap,$ExpectedMainSha,$ExpectedAddonSha,$PreviousMainSha,$PreviousAddonSha,$ExpectedAgentSha,$ExpectedBootstrapSha)
        throw $msg
    }

    $spotifyVersion=([string](Get-Item -LiteralPath $SpotifyExe).VersionInfo.ProductVersion).Trim()
    if($spotifyVersion -notmatch ('^'+[regex]::Escape($ExpectedSpotifyVersion)+'(?:\.|$)')){throw "Spotify version drifted from accepted baseline: $spotifyVersion"}
    $sp=Invoke-Native -FilePath (Get-SpicetifyExe) -Arguments @('--version')
    if($sp.ExitCode -ne 0 -or [string]$sp.Output -notmatch [regex]::Escape($ExpectedSpicetifyVersion)){throw "Spicetify version drifted from accepted baseline: $($sp.Output)"}
    if(-not(Wait-ControlWorkersIdle 30)){throw 'Spotify Control maintenance became active after production alignment.'}
    return [pscustomobject]@{spotify_control_version='0.6.19';addon_manager_version='0.6.5-r8';spotify_version=$spotifyVersion;spicetify_version=$ExpectedSpicetifyVersion;hashes=$actual;production_alignment=$alignment}
}
