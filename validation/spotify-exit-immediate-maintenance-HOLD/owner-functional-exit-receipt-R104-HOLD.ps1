# R104 HOLD: existing v0.6.30 functional exit evidence, read-only.
# Observe native state + bounded resident host log, never run Spotify or a tick.
# Host fixtures are restricted to GitHub-hosted ephemeral Windows test runners.
[CmdletBinding()]
param([string]$HostedFixtureRoot='')
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$out=New-Object 'System.Collections.Generic.List[string]'
$out.Add('DIAGNOSTIC=SPOTIFY_R104_OWNER_FUNCTIONAL_EXIT_READONLY')
$out.Add('NETWORK=NO;INSTALL=NO;TASK_CHANGE=NO;REGISTRY_CHANGE=NO;PROCESS_CHANGE=NO;STATE_WRITE=NO;AUTO_RETRY=NO')
$phase='ENTRY'
function Fail([string]$name){throw [InvalidOperationException]::new($name)}
function PlainFile([string]$p,[long]$max){
  try{
    $f=Get-Item -LiteralPath $p -Force -ErrorAction Stop
    return (-not $f.PSIsContainer -and
            ($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -and
            [long]$f.Length -ge 1 -and [long]$f.Length -le $max)
  }catch{return $false}
}
function ExactFile([string]$path,[long]$length,[string]$expected){
  try{
    if(-not(PlainFile $path 1000000)){return $false}
    if((Get-Item -LiteralPath $path -Force).Length -ne $length){return $false}
    return (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant() -ceq $expected
  }catch{return $false}
}
function BoundedTail([string]$path,[int]$maxBytes){
  if(-not(PlainFile $path 2147483647)){return $null}
  $file=$null
  try{
    $file=[IO.FileStream]::new($path,[IO.FileMode]::Open,[IO.FileAccess]::Read,
                               ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    $n=[int][Math]::Min([long]$maxBytes,$file.Length)
    if($file.Length -gt $n){$null=$file.Seek(-[long]$n,[IO.SeekOrigin]::End)}
    [byte[]]$data=New-Object byte[] $n
    $read=0
    while($read -lt $n){
      $count=$file.Read($data,$read,$n-$read)
      if($count -le 0){break}
      $read+=$count
    }
    return [Text.Encoding]::UTF8.GetString($data,0,$read)
  }catch{return $null}
  finally{if($null -ne $file){$file.Dispose()}}
}
try{
  if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
     $PSVersionTable.PSEdition -cne 'Desktop' -or
     $PSVersionTable.PSVersion.Major -ne 5 -or
     -not [Environment]::Is64BitProcess){
    Fail 'R104_WINDOWS_POWERSHELL_51_X64_REQUIRED'
  }
  $fixture= -not [string]::IsNullOrWhiteSpace($HostedFixtureRoot)
  if($fixture){
    if($env:GITHUB_ACTIONS -cne 'true' -or
       $env:RUNNER_OS -cne 'Windows' -or
       $env:RUNNER_ENVIRONMENT -cne 'github-hosted'){
      Fail 'R104_GITHUB_HOSTED_FIXTURE_ONLY'
    }
    $temp=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
    $parent=[IO.Path]::GetFullPath($HostedFixtureRoot).TrimEnd('\','/')
    if(-not $parent.StartsWith($temp+'\',[StringComparison]::OrdinalIgnoreCase) -or
       -not (Test-Path -LiteralPath $parent -PathType Container)){
      Fail 'R104_FIXTURE_OUTSIDE_RUNNER_TEMP'
    }
    $root=$parent
  }else{
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    if(([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)){
      Fail 'R104_OWNER_STANDARD_USER_ONLY'
    }
    $root=Join-Path ([Environment]::GetFolderPath(
      [Environment+SpecialFolder]::LocalApplicationData)) 'SpotifyControl'
  }
  $rootItem=Get-Item -LiteralPath $root -Force -ErrorAction Stop
  if(-not $rootItem.PSIsContainer -or
     ($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
    Fail 'R104_OPERATING_ROOT_REPARSE_OR_UNVERIFIED'
  }
  $phase='INSTALLED_FILE_PINS'
  $bin=Join-Path $root 'bin'
  $main=Join-Path $bin 'spotify-control.ps1'
  $agent=Join-Path $bin 'spotify-control-agent.vbs'
  $addon=Join-Path $bin 'addon-manager.ps1'
  $installed=$false
  if($fixture){
    $installed=$true
    $out.Add('R104_INSTALLED_V0630_FILES=HOSTED_FIXTURE_NOT_OPERATING_PROOF')
  }else{
    $installed=((ExactFile $main 294101 'b2b2fbf1afb60b58d501312160f7e2437c2452e90cb61ca8c2be0d877f92232d') -and
                (ExactFile $agent 13308 'e56609ed8927512595f55c01ea50dbb9c8c59e4a2c86dcb3d16195a565c604d5') -and
                (ExactFile $addon 323385 '5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285'))
    $out.Add('R104_INSTALLED_V0630_FILES='+$(if($installed){'PASS'}else{'HOLD'}))
  }
  $phase='TRANSACTION_AND_STATE_READONLY'
  $commitTime=$null
  $journal=Join-Path $root 'self-update-last-transaction.json'
  $journalStatus='UNVERIFIED'
  if(PlainFile $journal 1048576){
    try{
      $j=Get-Content -LiteralPath $journal -Raw -ErrorAction Stop|ConvertFrom-Json -ErrorAction Stop
      if([string]$j.status -ceq 'committed'){
        $journalStatus='COMMITTED_REPORTED'
        $commitTime=(Get-Item -LiteralPath $journal -Force).LastWriteTimeUtc
      }
    }catch{}
  }
  if($fixture){$journalStatus='HOSTED_FIXTURE_NOT_OPERATING_PROOF'}
  $out.Add('R104_COMMIT_JOURNAL='+$journalStatus)
  $statePath=Join-Path $root 'state.json'
  $stateGood=$false;$last='UNKNOWN';$decision='UNVERIFIED'
  $check='UNVERIFIED';$statePost='NOT_PROVEN';$stateAge='UNKNOWN'
  if(PlainFile $statePath 2097152){
    try{
      $doc=Get-Content -LiteralPath $statePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
      $stateGood=$true
      $event=[string]$doc.last_agent_event
      $last=if($event -cin @('Startup','Periodic','SpotifyExit')){$event.ToUpperInvariant()}else{'OTHER_OR_ABSENT'}
      $decision=if([string]::IsNullOrWhiteSpace([string]$doc.last_agent_decision)){
        'ABSENT'
      }else{'PRESENT_UNINTERPRETED'}
      $check=if($doc.maintenance_check_healthy -eq $true){'TRUE_SAVED'}
        elseif($doc.maintenance_check_healthy -eq $false){'FALSE_SAVED'}
        else{'NOT_BOOLEAN'}
      $mtime=(Get-Item -LiteralPath $statePath -Force).LastWriteTimeUtc
      if($null -ne $commitTime -and $mtime -gt $commitTime){
        $statePost='FILE_MODIFIED_AFTER_JOURNAL_NOT_EVENT_TIME_PROOF'
      }
      $age=[datetime]::UtcNow-$mtime
      $stateAge=if($age.TotalSeconds -lt -120){'FUTURE_UNVERIFIED'}
        elseif($age.TotalHours -le 24){'WITHIN_24H'}
        elseif($age.TotalDays -le 7){'WITHIN_7D'}
        else{'OLDER_OR_UNVERIFIED'}
    }catch{}
  }
  $out.Add('R104_STATE_JSON='+$(if($stateGood){'PARSED'}else{'UNAVAILABLE'}))
  $out.Add('R104_LAST_AGENT_EVENT='+$last)
  $out.Add('R104_LAST_AGENT_DECISION='+$decision)
  $out.Add('R104_MAINTENANCE_CHECK_HEALTH='+$check)
  $out.Add('R104_STATE_AGE='+$stateAge)
  $out.Add('R104_STATE_UPDATED_AFTER_COMMIT='+$statePost)
  $phase='BOUND_HOST_LOG_READONLY'
  $hostLog=Join-Path (Join-Path $root 'logs') 'resident-agent-host.log'
  $tail=BoundedTail $hostLog 262144
  $logRead=($null -ne $tail)
  $exitLog=($logRead -and $tail.Contains('SPOTIFY EXIT confirmed'))
  $dispatchLog=($logRead -and $tail.Contains('TICK LAUNCHED event=SpotifyExit'))
  $out.Add('R104_HOST_LOG_READABLE='+$(if($logRead){'YES'}else{'NO'}))
  $out.Add('R104_HOST_EXIT_SIGNAL_IN_BOUNDED_TAIL='+$(if($exitLog){'SEEN'}else{'NOT_PROVEN'}))
  $out.Add('R104_HOST_EXIT_TICK_IN_BOUNDED_TAIL='+$(if($dispatchLog){'SEEN'}else{'NOT_PROVEN'}))
  $out.Add('R104_HOST_LOG_SENSITIVE_CONTENT_EMITTED=NO')
  if($fixture){
    $running='HOSTED_NOT_TESTED'
  }else{
    try{
      $running=if(@(Get-Process -Name Spotify -ErrorAction Stop).Count -gt 0){
        'RUNNING'
      }else{'CLOSED'}
    }catch [Microsoft.PowerShell.Commands.ProcessCommandException]{$running='CLOSED'}
    catch{$running='UNKNOWN'}
  }
  $out.Add('R104_SPOTIFY_PROCESS_AT_OBSERVATION='+$running)
  $out.Add('R104_EXIT_EVIDENCE_CANNOT_PROVE_CURRENT_SESSION_OR_CAUSAL_ORDER=YES')
  $out.Add('R104_SPOTIFY_AUDIO_PLAYBACK=NOT_TESTED')
  $out.Add('R104_SPICETIFY_APPLY_OR_RECOVERY_SUCCESS=NOT_PROVEN')
  $result=if(-not $installed){'HOLD_INSTALLED_RELEASE_UNVERIFIED'}
  elseif(-not $stateGood){'HOLD_STATE_UNAVAILABLE'}
  elseif(-not $logRead){'HOLD_HOST_LOG_UNAVAILABLE'}
  elseif($last -cne 'SPOTIFYEXIT'){'LAST_PERSISTED_EVENT_NOT_SPOTIFYEXIT'}
  elseif(-not($exitLog -and $dispatchLog)){'EXIT_RECORDED_BUT_HOST_DISPATCH_NOT_PROVEN_IN_TAIL'}
  else{'PERSISTED_EXIT_AND_HOST_DISPATCH_PRESENT_NOT_CAUSAL_OR_MAINTENANCE_PROOF'}
  $out.Add('RESULT='+$result)
}catch{
  $out.Add('FAILED_PHASE='+$phase)
  $out.Add('RESULT=HOLD_READONLY_INCOMPLETE')
}finally{
  $out.Add('R104_OWNER_OPERATING_FILES_AND_ORIGINAL_DATA=UNCHANGED')
  $out.Add('RAW_STATE_LOG_PATHS_SECRETS_PROCESS_ARGS_AND_USER_IDS_OUTPUT=NO')
  try{Set-Clipboard -Value ($out -join [Environment]::NewLine) -ErrorAction Stop}catch{}
  $out|ForEach-Object {Write-Output $_}
}
