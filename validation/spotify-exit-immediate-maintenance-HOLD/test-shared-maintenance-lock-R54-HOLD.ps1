# R54 HOSTED Windows PowerShell 5.1 focused source acceptance.
# Use real named per-user Windows mutex functions and real optimized
# AgentTick + Maintain, mock ONLY external network/file/app mutation helpers.
# Verify manual maintenance lock excludes the entire AgentTick discovery.
[CmdletBinding()]
param()
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
    throw 'R54_HOSTED_WINDOWS_ONLY'
}
$fixture=(Resolve-Path 'validation/spotify-exit-immediate-maintenance-HOLD/out/shared-maintenance-R54/real-mutex-and-maintenance.ps1').Path
$AgentReport=Join-Path $env:RUNNER_TEMP 'spotify-r54-agent-readonly-report.json'
$agentPath=$fixture
$ScriptVersion='0.6.30'
$AgentDiscoveryIntervalHours=12
$script:Spicetify='READONLY_SYNTHETIC_CLI_ONLY'
$script:MockCheckCount=0
$script:MockMutationCount=0
$script:MockState=$null
. $fixture

# Functions below affect memory only: real PowerShell actions can NEVER
# reach real Spicetify/Spotify/Addon/Marketplace, file updates or networks.
function Load-State {return $script:MockState}
function Ensure-StateShape {param($State) return $State}
function Save-State {param($State) $script:MockState=$State}
function Migrate-StateFromLog {param($State) return $State}
function Test-SpotifyRunning {return $false}
function Test-DueHours {param($Value,$Hours) return $false}
function Get-MaintenanceMode {param($SpotifyRunning) return 'check+mutation'}
function Write-Log {param($Message,$Level)}
function Invoke-MaintenanceCheckPhase {
  param($State)
  $script:MockCheckCount++
  $State.last_check_only_utc=[DateTimeOffset]::UtcNow.ToString("o")
  $State.pending_maintenance=$true
  $State.maintenance_check_healthy=$true
  $State.pending_addon_auto_ambiguous=0
  Save-State $State
  return [pscustomobject]@{
    State=$State
    GuardPlan=[pscustomobject]@{CurrentSupported=$true}
    Report=[pscustomobject]@{phase='check-only';healthy=$true}
  }
}
function Invoke-MaintenanceMutationPhase {
  param($State,$GuardPlan)
  $script:MockMutationCount++
  return $State
}
function Reset-State {
  $script:MockCheckCount=0
  $script:MockMutationCount=0
  $script:MockState=[pscustomobject]@{
    agent_mutation_enabled=$true
    pending_maintenance=$true
    last_check_only_utc='2026-11-08T00:00:00Z'
    maintenance_check_healthy=$true
    pending_addon_auto_ambiguous=0
    pending_addon_nonauto_ambiguous=0
    pending_reasons=@('synthetic-installed-only-allowed-update')
    last_agent_tick_utc=$null
    last_agent_event=$null
    last_agent_decision=$null
    agent_version=$null
  }
  Remove-Item -LiteralPath $AgentReport -Force -ErrorAction SilentlyContinue
}
$hold=Join-Path $env:RUNNER_TEMP 'spotify-r54-manual-mutex-holder.ps1'
$ready=Join-Path $env:RUNNER_TEMP 'spotify-r54-exclusive-maintenance-held.txt'
$owned=$null
try {
  if((Test-Path -LiteralPath $hold) -or (Test-Path -LiteralPath $ready)){
    throw 'R54_TEST_OWNED_PROCESS_STAGING_ALREADY_EXISTS'
  }
  # .NET Windows named Mutex supports recursive acquisition by the SAME
  # thread. The nested Maintain may therefore safely re-enter while its
  # AgentTick caller holds the maintenance mutex.
  $outer=Enter-SpotifyControlMutex -Purpose 'Maintenance'
  if($null -eq $outer){throw 'R54_FIRST_TRUE_MAINTENANCE_MUTEX_NOT_ACQUIRED'}
  try {
    $inner=Enter-SpotifyControlMutex -Purpose 'Maintenance'
    if($null -eq $inner){throw 'R54_SAME_THREAD_REENTRANT_MUTEX_MUST_SUCCEED'}
    Exit-SpotifyControlMutex -Mutex $inner
  } finally {
    Exit-SpotifyControlMutex -Mutex $outer
  }
  Write-Host 'R54_ACTUAL_WINDOWS_MUTEX_SAME_THREAD_REENTRANT_NESTED_MAINTAIN=PASS'

  # Acquire the manual Maintenance mutex in a separate exact test-owned
  # PowerShell PROCESS with same user/SID. Never terminate a foreign process.
  @'
param([string]$RealFunctions,[string]$Signal)
$ErrorActionPreference='Stop'
. $RealFunctions
function Write-Log {param($Message,$Level)}
$mutex=Enter-SpotifyControlMutex -Purpose 'Maintenance'
if($null -eq $mutex){exit 44}
try {
  [IO.File]::WriteAllText($Signal,'EXCLUSIVE_TEST_OWNED_MANUAL_MAINTENANCE')
  Start-Sleep -Seconds 12
} finally {
  Exit-SpotifyControlMutex -Mutex $mutex
}
'@ | Set-Content -LiteralPath $hold -Encoding UTF8 -ErrorAction Stop
  $runner=Join-Path $PSHOME 'powershell.exe'
  $args='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$hold+'" -RealFunctions "'+$agentPath+'" -Signal "'+$ready+'"'
  $owned=Start-Process -FilePath $runner -ArgumentList $args -PassThru -WindowStyle Hidden -ErrorAction Stop
  $arrived=$false
  for($i=0;$i -lt 60;$i++){
    if(Test-Path -LiteralPath $ready){$arrived=$true;break}
    $owned.Refresh()
    if($owned.HasExited){throw 'R54_TEST_OWNED_MANUAL_MUTEX_HOLDER_FAILED'}
    Start-Sleep -Milliseconds 100
  }
  if(-not $arrived){throw 'R54_MANUAL_MUTEX_NOT_ACQUIRED_IN_TIME'}
  if((Get-Content -LiteralPath $ready -Raw) -cne 'EXCLUSIVE_TEST_OWNED_MANUAL_MAINTENANCE'){
    throw 'R54_UNEXPECTED_LOCK_OWNER_SIGNAL'
  }
  Reset-State
  $before=[string]$script:MockState.last_check_only_utc
  Invoke-ResidentAgentTick -EventName 'SpotifyExit'
  if($script:MockCheckCount -ne 0 -or
     $script:MockMutationCount -ne 0 -or
     [string]$script:MockState.last_check_only_utc -cne $before -or
     [string]$script:MockState.last_agent_event -or
     (Test-Path -LiteralPath $AgentReport)){
    throw 'R54_AGENTTICK_OVERLAPPED_TRUE_MANUAL_MUTEX_OR_WROTE_STATE'
  }
  Write-Host 'R54_MANUAL_MAINTENANCE_BLOCKS_ENTIRE_AGENT_DISCOVERY_AND_STATE_WRITES=PASS'

  # Release only the exact process created above. Once its real Windows
  # mutex is free, the original AgentTick may safely run and re-enter
  # Maintenance on the SAME thread with one discovery and one phase.
  $owned.Refresh()
  if(-not $owned.HasExited){Stop-Process -Id $owned.Id -Force -ErrorAction Stop}
  [void]$owned.WaitForExit(5000)
  $owned=$null
  Reset-State
  Invoke-ResidentAgentTick -EventName 'SpotifyExit'
  if($script:MockCheckCount -ne 1 -or $script:MockMutationCount -ne 1 -or
     [string]$script:MockState.last_agent_event -cne 'SpotifyExit' -or
     [string]$script:MockState.last_agent_decision -cne 'maintenance-phase-entered'){
    throw ('R54_AFTER_MANUAL_RELEASE_OWNED_WORKFLOW_FAILED_SCANS_'+$script:MockCheckCount+
      '_PHASE_'+$script:MockMutationCount)
  }
  $report=Get-Content -LiteralPath $AgentReport -Raw -ErrorAction Stop | ConvertFrom-Json
  if(-not [bool]$report.check_ran -or -not [bool]$report.mutation_ran){
    throw 'R54_REAL_SOURCE_AGENT_REPORT_MUST_MATCH_ONE_DISCOVERY'
  }
  Write-Host 'R54_AFTER_MANUAL_LOCK_RELEASE_EXACT_ONE_CHECK_AND_ONE_PHASE=PASS'
  Write-Host 'R54_REAL_NAMED_WINDOWS_MUTEX_AND_ORIGINAL_SINGLE_CHECK_MAINTAIN=PASS'
  Write-Host 'R54_GITHUB_HOSTED_ONLY_USER_SPOTIFY_AND_MANAGED_FILES_UNCHANGED=YES'
} finally {
  if($null -ne $owned){
    try {
      $owned.Refresh()
      if(-not $owned.HasExited){Stop-Process -Id $owned.Id -Force -ErrorAction SilentlyContinue}
      [void]$owned.WaitForExit(5000)
    } catch {}
  }
  foreach($p in @($hold,$ready,$AgentReport)){
    Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
  }
}
