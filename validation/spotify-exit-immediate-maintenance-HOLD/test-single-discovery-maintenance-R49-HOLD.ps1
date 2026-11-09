# HOLD R49 Windows PowerShell 5.1: real source functions, no real Spotify,
# Spicetify, installer, Addon Manager, remote API or mutation; test doubles
# cover network scan count, owner revocation, concurrent manual lease,
# and exact mutation-phase admission receipt.
[CmdletBinding()]
param()
Set-StrictMode -Version 2.0
$ErrorActionPreference="Stop"
if($env:GITHUB_ACTIONS -cne 'true' -or
   $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
  throw 'R49_NATIVE_HOSTED_WINDOWS_ONLY'
}
$source='validation/spotify-exit-immediate-maintenance-HOLD/out/single-discovery-R49/isolated-real-functions.ps1'
if(-not(Test-Path -LiteralPath $source -PathType Leaf)){throw 'R49_TWO_REAL_FUNCTIONS_NOT_BUILT'}
$text=Get-Content -LiteralPath $source -Raw
if($text -cnotmatch 'function Invoke-ResidentAgentTick' -or
   $text -cnotmatch 'function Maintain' -or
   $text -cnotmatch 'Maintain -FromResidentAgent -VerifiedAgentCheck'){
  throw 'R49_REAL_FUNCTION_SOURCE_UNEXPECTED'
}
$tokens=$null;$errors=$null
[void][Management.Automation.Language.Parser]::ParseFile(
   (Join-Path (Get-Location) $source),[ref]$tokens,[ref]$errors)
if(@($errors).Count -ne 0){throw 'R49_SOURCE_POWERSHELL_51_PARSE_FAILED'}
. (Join-Path (Get-Location) $source)

$script:Spicetify='TEST_OWNED_VERSION_ONLY_CLI'
$AgentReport=Join-Path $env:RUNNER_TEMP 'spotify-R49-agent-report.json'
$AgentDiscoveryIntervalHours=12
$ScriptVersion='0.6.30'
$script:MockState=$null
$script:MockDue=$false
$script:MockRunning=$false
$script:MockPending=$true
$script:MockHealthy=$true
$script:MockAmbiguous=0
$script:MockLeaseBusy=$false
$script:MockRevokeOnMaintenanceLease=$false
$script:MockCheckCount=0
$script:MockMutationCount=0
$script:MockSaveCount=0

# All helpers are inert in-memory fakes; there is no connection to real
# Spotify, Windows GUI, GitHub, physical user settings, nor to data paths.
function Enter-SpotifyControlMutex {
  param([string]$Purpose)
  if($Purpose -ceq 'Maintenance'){
    if($script:MockLeaseBusy){return $null}
    if($script:MockRevokeOnMaintenanceLease){
      $script:MockState.agent_mutation_enabled=$false
    }
  }
  return [pscustomobject]@{purpose=$Purpose}
}
function Exit-SpotifyControlMutex {param($Mutex)}
function Ensure-StateShape {param($State) return $State}
function Load-State {return $script:MockState}
function Save-State {param($State) $script:MockSaveCount++;$script:MockState=$State}
function Migrate-StateFromLog {param($State) return $State}
function Test-SpotifyRunning {return [bool]$script:MockRunning}
function Test-DueHours {param($Value,[int]$Hours) return [bool]$script:MockDue}
function Get-MaintenanceMode {param([bool]$SpotifyRunning)
  return $(if($SpotifyRunning){'check-only'}else{'check+mutation'})
}
function Write-Log {param($Message,$Level)}
function Invoke-MaintenanceCheckPhase {
  param($State)
  $script:MockCheckCount++
  $State.last_check_only_utc=[DateTimeOffset]::UtcNow.ToString("o")
  $State.pending_maintenance=[bool]$script:MockPending
  $State.maintenance_check_healthy=[bool]$script:MockHealthy
  $State.pending_addon_auto_ambiguous=[int]$script:MockAmbiguous
  Save-State $State
  return [pscustomobject]@{
    State=$State
    GuardPlan=[pscustomobject]@{CurrentSupported=$true}
    Report=[pscustomobject]@{phase='check-only';healthy=[bool]$script:MockHealthy}
  }
}
function Invoke-MaintenanceMutationPhase {
  param($State,$GuardPlan)
  if($script:MockRunning){throw 'R49_UNEXPECTED_MUTATION_WHILE_SPOTIFY_RUNNING'}
  $script:MockMutationCount++
  return $State
}

function Invoke-Case {
  param(
    [string]$Name,[string]$Event='SpotifyExit',
    [bool]$Armed=$true,[bool]$Pending=$true,
    [bool]$Healthy=$true,[int]$AutoAmbiguous=0,
    [bool]$Due=$false,[bool]$LeaseBusy=$false,
    [bool]$Revoke=$false,
    [int]$ExpectedScans=1,[int]$ExpectedPhase=1,
    [string]$ExpectedDecision='maintenance-phase-entered'
  )
  $script:MockState=[pscustomobject]@{
    agent_mutation_enabled=$Armed
    last_check_only_utc='2026-11-01T00:00:00Z'
    pending_maintenance=$Pending
    maintenance_check_healthy=$Healthy
    pending_addon_auto_ambiguous=$AutoAmbiguous
    pending_addon_nonauto_ambiguous=0
    pending_reasons=@('synthetic-available-update')
    last_agent_tick_utc=$null
    last_agent_event=$null
    last_agent_decision=$null
    agent_version=$null
  }
  $script:MockDue=$Due
  $script:MockRunning=$false
  $script:MockPending=$Pending
  $script:MockHealthy=$Healthy
  $script:MockAmbiguous=$AutoAmbiguous
  $script:MockLeaseBusy=$LeaseBusy
  $script:MockRevokeOnMaintenanceLease=$Revoke
  $script:MockCheckCount=0;$script:MockMutationCount=0;$script:MockSaveCount=0
  Remove-Item -LiteralPath $AgentReport -Force -ErrorAction SilentlyContinue
  Invoke-ResidentAgentTick -EventName $Event
  if($script:MockCheckCount -ne $ExpectedScans -or
     $script:MockMutationCount -ne $ExpectedPhase){
    throw ("R49_REAL_FUNCTION_SCAN_OR_MUTATION_MISMATCH_"+$Name+
      "_scans="+$script:MockCheckCount+"_phase="+$script:MockMutationCount)
  }
  if([string]$script:MockState.last_agent_decision -cne $ExpectedDecision -or
     [string]$script:MockState.last_agent_event -cne $Event){
    throw ("R49_NATIVE_STATE_DECISION_MISMATCH_"+$Name)
  }
  $report=Get-Content -LiteralPath $AgentReport -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
  if([bool]$report.mutation_ran -ne ($ExpectedPhase -gt 0) -or
     [bool]$report.check_ran -ne ($ExpectedScans -gt 0)){
    throw ("R49_NATIVE_RECEIPT_INCORRECT_"+$Name)
  }
  Write-Host ('R49_'+$Name+'=PASS')
}
try {
  # R46 used to perform two real discovery scans per single armed exit,
  # because AgentTick checked, then Maintain checked again.
  Invoke-Case -Name 'ARMED_EXIT_EXACTLY_ONE_CHECK'
  Invoke-Case -Name 'DISARMED_EXIT_NO_MUTATION' -Armed $false -ExpectedPhase 0 -ExpectedDecision 'pending-observed-mutation-disarmed'
  Invoke-Case -Name 'UNHEALTHY_EXIT_NO_MUTATION' -Healthy $false -ExpectedPhase 0 -ExpectedDecision 'mutation-blocked-unhealthy-or-auto-ambiguous'
  Invoke-Case -Name 'AUTO_AMBIGUOUS_EXIT_NO_MUTATION' -AutoAmbiguous 1 -ExpectedPhase 0 -ExpectedDecision 'mutation-blocked-unhealthy-or-auto-ambiguous'
  Invoke-Case -Name 'MANUAL_MUTEX_BUSY_NO_FALSE_MUTATION' -LeaseBusy $true -ExpectedPhase 0 -ExpectedDecision 'maintenance-deferred-or-lease-busy'
  Invoke-Case -Name 'OWNER_REVOKED_AFTER_DISCOVERY_NO_MUTATION' -Revoke $true -ExpectedPhase 0 -ExpectedDecision 'maintenance-deferred-or-lease-busy'
  # Already pending, healthy, and not scan-due: Maintain must still
  # discover exactly once (no unchecked stale mutation admission).
  Invoke-Case -Name 'PENDING_ORDINARY_TICK_ONE_NEW_CHECK' -Event 'Periodic' -Due $false -ExpectedScans 1
  # Manual maintenance does not silently inherit agent-only owner gating.
  $script:MockState=[pscustomobject]@{
    agent_mutation_enabled=$false
    last_check_only_utc=$null
    pending_maintenance=$true
    maintenance_check_healthy=$true
    pending_addon_auto_ambiguous=0
    pending_reasons=@()
  }
  $script:MockCheckCount=0
  $script:MockMutationCount=0
  $script:MockLeaseBusy=$false
  $script:MockRevokeOnMaintenanceLease=$false
  Maintain
  if($script:MockCheckCount -ne 1 -or $script:MockMutationCount -ne 1){
    throw 'R49_MANUAL_MAINTAIN_MUST_RETAIN_FRESH_SCAN'
  }
  Write-Host 'R49_MANUAL_MAINTAIN_ALWAYS_DISCOVERS_FRESH=PASS'
  Write-Host 'R49_REAL_SOURCE_TWO_FUNCTIONS_SINGLE_DISCOVERY_AND_AUTHORITY_RECHECK=PASS'
  Write-Host 'R49_NO_REAL_SPOTIFY_NETWORK_OR_ADDON_MUTATION=YES'
} finally {
  Remove-Item -LiteralPath $AgentReport -Force -ErrorAction SilentlyContinue
}
