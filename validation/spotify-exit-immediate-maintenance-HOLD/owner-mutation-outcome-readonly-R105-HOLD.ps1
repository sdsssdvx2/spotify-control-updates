# R105 HOLD: inspect real Spotify Control v0.6.30 resident mutation admission and reports.
# Never invoke Spotify, Spicetify, Maintain or AgentTick. No operating writes.
[CmdletBinding()]
param([string]$HostedFixtureRoot='')
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$out=New-Object 'System.Collections.Generic.List[string]'
$out.Add('DIAGNOSTIC=SPOTIFY_R105_OWNER_MUTATION_EVIDENCE_READONLY')
$out.Add('NETWORK=NO;INSTALL=NO;PROCESS_CHANGE=NO;TASK_CHANGE=NO;STATE_WRITE=NO;AUTO_RETRY=NO')
$phase='START'
function Reject([string]$s){throw [InvalidOperationException]::new($s)}
function Regular([string]$p,[long]$cap){
  try {
    $f=Get-Item -LiteralPath $p -Force -ErrorAction Stop
    return (-not $f.PSIsContainer -and
      ($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -and
      [long]$f.Length -gt 0 -and [long]$f.Length -le $cap)
  }catch{return $false}
}
function BoolCode($value){
  if($value -is [bool]){return $(if($value){'TRUE_SAVED'}else{'FALSE_SAVED'})}
  return 'ABSENT_OR_NOT_BOOLEAN'
}
function DecisionClass([string]$value){
  switch -CaseSensitive ($value){
    'maintenance-phase-entered' {'MUTATION_PHASE_ENTERED_NOT_SUCCESS_PROOF';break}
    'maintenance-deferred-or-lease-busy' {'MUTATION_DEFERRED_NOT_EXECUTED';break}
    'mutation-blocked-unhealthy-or-auto-ambiguous' {'MUTATION_BLOCKED_HEALTH_OR_AMBIGUITY';break}
    'pending-observed-mutation-disarmed' {'MUTATION_DISARMED_PENDING';break}
    'observe-only-closed' {'OBSERVATION_ONLY';break}
    'check-only-closed-no-pending' {'CLOSED_CHECK_ONLY';break}
    'closed-check-not-due' {'CLOSED_IDLE_OR_NOT_DUE';break}
    'running-check-not-due' {'RUNNING_IDLE_OR_NOT_DUE';break}
    'check-only-running' {'RUNNING_CHECK_ONLY';break}
    'noop' {'NOOP';break}
    default {'UNKNOWN_OR_UNVERIFIED'}
  }
}
function FreshTime([string]$value){
  $stamp=[DateTimeOffset]::MinValue
  if([string]::IsNullOrWhiteSpace($value)){return $null}
  if(-not [DateTimeOffset]::TryParse($value,[ref]$stamp)){return $null}
  $now=[DateTimeOffset]::UtcNow
  if($stamp -gt $now.AddMinutes(2) -or $stamp -lt $now.AddDays(-365)){return $null}
  return $stamp
}
function JsonRead([string]$path,[long]$cap){
  if(-not(Regular $path $cap)){return $null}
  try {
    $content=Get-Content -LiteralPath $path -Raw -ErrorAction Stop
    return ($content|ConvertFrom-Json -ErrorAction Stop)
  }catch{return $null}
}
try {
  if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
    $PSVersionTable.PSEdition -cne 'Desktop' -or
    $PSVersionTable.PSVersion.Major -ne 5 -or
    -not [Environment]::Is64BitProcess){Reject 'R105_POWERSHELL_51_WINDOWS_X64_ONLY'}
  $fixture= -not [string]::IsNullOrWhiteSpace($HostedFixtureRoot)
  if($fixture){
    if($env:GITHUB_ACTIONS -cne 'true' -or
       $env:RUNNER_OS -cne 'Windows' -or
       $env:RUNNER_ENVIRONMENT -cne 'github-hosted'){
      Reject 'R105_GITHUB_HOSTED_FIXTURE_ONLY'
    }
    $temp=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
    $root=[IO.Path]::GetFullPath($HostedFixtureRoot).TrimEnd('\','/')
    if(-not $root.StartsWith($temp+'\',[StringComparison]::OrdinalIgnoreCase)){
      Reject 'R105_FIXTURE_OUTSIDE_RUNNER_TEMP'
    }
  }else{
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    if(([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole(
       [Security.Principal.WindowsBuiltInRole]::Administrator)){
      Reject 'R105_STANDARD_USER_ONLY'
    }
    $root=Join-Path ([Environment]::GetFolderPath(
      [Environment+SpecialFolder]::LocalApplicationData)) 'SpotifyControl'
  }
  $r=Get-Item -LiteralPath $root -Force -ErrorAction Stop
  if(-not $r.PSIsContainer -or
    ($r.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
    Reject 'R105_ROOT_NON_DIRECTORY_OR_REPARSE'
  }
  $phase='MAIN_IDENTITY'
  $main=Join-Path $root 'bin\spotify-control.ps1'
  $mainOK=$false
  if($fixture){$mainOK=$true}
  else{
    if(Regular $main 500000){
      $f=Get-Item -LiteralPath $main -Force -ErrorAction Stop
      $mainOK=([long]$f.Length -eq 294101 -and
        (Get-FileHash -LiteralPath $main -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant() -ceq
        'b2b2fbf1afb60b58d501312160f7e2437c2452e90cb61ca8c2be0d877f92232d')
    }
  }
  $out.Add('R105_V0630_MAIN='+$(if($fixture){'HOSTED_FIXTURE'}elseif($mainOK){'SHA256_PASS'}else{'HOLD'}))
  $phase='STATE_READING'
  $state=JsonRead (Join-Path $root 'state.json') 2097152
  if($null -eq $state){Reject 'R105_STATE_UNREADABLE'}
  $event=[string]$state.last_agent_event
  $decision=[string]$state.last_agent_decision
  $class=DecisionClass $decision
  $stateTick=FreshTime ([string]$state.last_agent_tick_utc)
  $stateEvent=if($event -ceq 'SpotifyExit'){'SPOTIFYEXIT'}
    elseif($event -cin @('Startup','Periodic')){$event.ToUpperInvariant()}
    else{'OTHER_OR_UNVERIFIED'}
  $out.Add('R105_STATE_LAST_EVENT='+$stateEvent)
  $out.Add('R105_LAST_DECISION_CLASS='+$class)
  $out.Add('R105_MUTATION_ENABLED='+ (BoolCode $state.agent_mutation_enabled))
  $out.Add('R105_PENDING_MAINTENANCE='+ (BoolCode $state.pending_maintenance))
  $out.Add('R105_DISCOVERY_HEALTH='+ (BoolCode $state.maintenance_check_healthy))
  $out.Add('R105_AUTO_AMBIGUOUS='+ $(if($null -ne $state.pending_addon_auto_ambiguous -and
    "$($state.pending_addon_auto_ambiguous)" -match '^\d+$'){
    if([int]$state.pending_addon_auto_ambiguous -gt 0){'NONZERO_SAVED'}else{'ZERO_SAVED'}
  }else{'UNVERIFIED'}))
  $out.Add('R105_LAST_TICK_UTC='+$(if($null -eq $stateTick){'UNVERIFIED'}else{'PARSED'}))
  $lastSuccess=FreshTime ([string]$state.last_success_utc)
  $out.Add('R105_LAST_SUCCESS_TIMESTAMP='+$(if($null -eq $lastSuccess){'UNVERIFIED_OR_ABSENT'}else{'PRESENT_NOT_MUTATION_PROOF'}))
  $phase='REPORT_DISCOVERY'
  # Fixed, bounded locations only; do not recurse through private backups.
  $candidates=@(
    (Join-Path $root 'resident-agent-latest.json'),
    (Join-Path $root 'reports\resident-agent-latest.json'),
    (Join-Path $root 'logs\resident-agent-latest.json'),
    (Join-Path $root 'state\resident-agent-latest.json')
  )
  $present=@($candidates | Where-Object {Regular $_ 2097152})
  $report=$null
  if($present.Count -eq 1){$report=JsonRead $present[0] 2097152}
  $reportStatus=if($present.Count -gt 1){'MULTIPLE_REPORT_LOCATIONS_UNVERIFIED'}
    elseif($present.Count -eq 0){'NOT_FOUND_IN_FIXED_LOCATIONS'}
    elseif($null -eq $report){'UNREADABLE'}else{'PARSED'}
  $out.Add('R105_AGENT_REPORT='+$reportStatus)
  $reportOutcome='NOT_AVAILABLE'
  $same='NOT_PROVEN'
  $phaseEntered='NOT_PROVEN'
  if($null -ne $report){
    $reportEvent=[string]$report.event
    $reportDecision=[string]$report.decision
    $reportOutcome=if($report.mutation_ran -is [bool]){
      if($report.mutation_ran){'MUTATION_PHASE_ENTERED_REPORTED_NOT_SUCCESS_PROOF'}
      else{'MUTATION_PHASE_NOT_ENTERED_REPORTED'}
    }else{'REPORT_MUTATION_FLAG_NOT_BOOLEAN'}
    $reportedTime=FreshTime ([string]$report.generated_at)
    $matched=($reportEvent -ceq $event -and
              $reportDecision -ceq $decision -and
              [string]$report.spotify_control_version -ceq '0.6.30' -and
              $null -ne $reportedTime -and $null -ne $stateTick)
    if($matched){
      $delta=[Math]::Abs(($reportedTime-$stateTick).TotalSeconds)
      if($delta -le 120){
        $same='MATCHING_EVENT_DECISION_TIME_NOT_CAUSAL_PROOF'
      }
    }
    if($reportOutcome -ceq 'MUTATION_PHASE_ENTERED_REPORTED_NOT_SUCCESS_PROOF' -and
       $class -ceq 'MUTATION_PHASE_ENTERED_NOT_SUCCESS_PROOF' -and
       $same -ceq 'MATCHING_EVENT_DECISION_TIME_NOT_CAUSAL_PROOF'){
      $phaseEntered='REPORTED_ENTERED_NOT_OPERATION_SUCCESS'
    }
  }
  $out.Add('R105_AGENT_REPORT_MUTATION_FLAG='+$reportOutcome)
  $out.Add('R105_STATE_REPORT_CORRELATION='+$same)
  $out.Add('R105_MUTATION_PHASE_ADMISSION='+$phaseEntered)
  $out.Add('R105_ACTUAL_SPICETIFY_APPLY_OR_ADDON_CHANGE_SUCCESS=NOT_PROVEN')
  $out.Add('R105_REPORT_DECISION_VS_EXECUTION_NOT_EQUAL=YES')
  $result=if(-not $mainOK){'HOLD_MAIN_UNVERIFIED'}
    elseif($stateEvent -cne 'SPOTIFYEXIT'){'NO_LATEST_EXIT_STATE'}
    elseif($class -ceq 'UNKNOWN_OR_UNVERIFIED'){'HOLD_UNRECOGNIZED_DECISION'}
    elseif($reportStatus -cne 'PARSED'){'EXIT_DECISION_CLASSIFIED_REPORT_UNAVAILABLE'}
    elseif($same -cne 'MATCHING_EVENT_DECISION_TIME_NOT_CAUSAL_PROOF'){
      'EXIT_DECISION_CLASSIFIED_REPORT_UNCORRELATED'
    }elseif($phaseEntered -ceq 'REPORTED_ENTERED_NOT_OPERATION_SUCCESS'){
      'MUTATION_PHASE_ENTERED_NO_RESULT_PROOF'
    }else{'EXIT_DECISION_AND_REPORT_CORRELATED_NO_MUTATION_SUCCESS_CLAIM'}
  $out.Add('RESULT='+$result)
}catch{
  $out.Add('FAILED_PHASE='+$phase)
  $out.Add('RESULT=HOLD_READONLY_INCOMPLETE')
}finally{
  $out.Add('R105_OPERATING_APPLICATION_AND_USER_FILES=UNCHANGED')
  $out.Add('RAW_USER_PATHS_STATE_REPORT_PRIVATE_VALUES_SECRETS_AND_PIDS_OUTPUT=NO')
  try {Set-Clipboard -Value ($out -join [Environment]::NewLine)}catch{}
  $out|ForEach-Object{Write-Output $_}
}
