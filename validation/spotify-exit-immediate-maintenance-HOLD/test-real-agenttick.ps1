# Execute ONLY the exact staged AgentTick function, never the full main
# script and never an installed Spotify/Spicetify. Windows PowerShell 5.1.
param([Parameter(Mandatory=$true)][string]$StagedDirectory)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
    throw 'SPOTIFY_EXIT_REAL_SOURCE_TEST_HOSTED_WINDOWS_ONLY'
}
$scriptPath=Join-Path $StagedDirectory 'actual-agenttick-function.ps1'
if(-not [IO.File]::Exists($scriptPath)){throw 'ACTUAL_STAGED_FUNCTION_MISSING'}
$source=Get-Content -LiteralPath $scriptPath -Raw
if($source -cnotmatch 'function Invoke-ResidentAgentTick' -or
   $source -cmatch 'function (?:Update-AutoApps|Maintain|Invoke-MaintenanceCheckPhase)\b'){
    throw 'STAGED_FUNCTION_SCOPE_DRIFT'
}
. $scriptPath

$metaPath=Join-Path (Split-Path $StagedDirectory -Parent) 'source-attestation.json'
$meta=Get-Content -LiteralPath $metaPath -Raw | ConvertFrom-Json
$actualEvent=[string]$meta.agent_vbs_exit_event
if($actualEvent -cnotmatch '^[A-Za-z0-9_-]*[Ee]xit[A-Za-z0-9_-]*$'){
    throw 'STAGED_AGENT_EVENT_NOT_PROVEN'
}
$AgentReport=Join-Path $env:RUNNER_TEMP 'spotify-exit-agent-report-synthetic.json'
$AgentDiscoveryIntervalHours=12
$ScriptVersion='0.6.28'

# All interactions are in-process test doubles; no invocation of existing
# installed main, Addon Manager, Spicetify CLI, schedule, or real user data.
$script:MockRunning=$false
$script:MockCheckCount=0
$script:MockMaintainCount=0
$script:MockCheckPending=$true
$script:MockCheckHealthy=$true
$script:MockCheckAmbiguous=0
$script:MockDue=$false
$script:MockSaveCount=0
$script:MockClaimBeforeCheck=$false
$script:MockState=$null
function Enter-SpotifyControlMutex {param([string]$Purpose)
    return [pscustomobject]@{synthetic_lease=$Purpose}
}
function Exit-SpotifyControlMutex {param($Mutex)}
function Load-State {return $script:MockState}
function Ensure-StateShape {param($State) return $State}
function Migrate-StateFromLog {param($State) return $State}
function Save-State {param($State) $script:MockSaveCount++}
function Test-SpotifyRunning {return [bool]$script:MockRunning}
function Test-DueHours {param($Value,$Hours) return [bool]$script:MockDue}
function Invoke-MaintenanceCheckPhase {param($State)
    $script:MockClaimBeforeCheck=($script:MockSaveCount -gt 0)
    $script:MockCheckCount++
    $script:MockState.pending_maintenance=[bool]$script:MockCheckPending
    $script:MockState.maintenance_check_healthy=[bool]$script:MockCheckHealthy
    $script:MockState.pending_addon_auto_ambiguous=[int]$script:MockCheckAmbiguous
    return [pscustomobject]@{stub='only-readonly-discovery'}
}
function Maintain {$script:MockMaintainCount++}
function Write-Log {param($Message,$Level)}

function Invoke-OneCase {
    param([string]$Event,[bool]$Running,[bool]$Armed,
          [bool]$Healthy,[int]$Ambiguous,[int]$CheckExpected,
          [int]$MaintExpected,[bool]$Due=$false,[bool]$PendingBefore=$false,
          [ValidateSet('Same','Unhealthy')][string]$InitialHealth='Same',
          [int]$InitialAmbiguous=0,[bool]$ClaimExpected=$false)
    $script:MockRunning=$Running
    $script:MockCheckCount=0
    $script:MockMaintainCount=0
    $script:MockSaveCount=0
    $script:MockClaimBeforeCheck=$false
    $script:MockDue=$Due
    $script:MockCheckPending=$true
    $script:MockCheckHealthy=$Healthy
    $script:MockCheckAmbiguous=$Ambiguous
    $script:MockState=[pscustomobject]@{
        last_check_only_utc='2026-11-08T00:00:00Z'
        agent_mutation_enabled=$Armed
        pending_maintenance=$PendingBefore
        maintenance_check_healthy=$(if($InitialHealth -ceq 'Unhealthy'){$false}else{$Healthy})
        pending_addon_auto_ambiguous=$InitialAmbiguous
        pending_addon_nonauto_ambiguous=0
        pending_reasons=@()
        last_agent_tick_utc=$null
        last_agent_event=$null
        last_agent_decision=$null
        agent_version=$null
    }
    Invoke-ResidentAgentTick -EventName $Event
    if($script:MockCheckCount -ne $CheckExpected -or
       $script:MockMaintainCount -ne $MaintExpected -or
       $script:MockClaimBeforeCheck -ne $ClaimExpected){
        throw ('SOURCE_BEHAVIOR_MISMATCH_'+$Event+
               '_running='+$Running+'_armed='+$Armed+
               '_check='+$script:MockCheckCount+'_maint='+$script:MockMaintainCount+
               '_retry_epoch_claimed='+$script:MockClaimBeforeCheck)
    }
    $receipt=Get-Content -LiteralPath $AgentReport -Raw | ConvertFrom-Json
    if([bool]$receipt.mutation_ran -ne ($MaintExpected -gt 0) -or
       [bool]$receipt.check_ran -ne ($CheckExpected -gt 0)){
        throw 'AGENT_REPORT_FALSE_PROOF'
    }
}
# Critical functional regression: normal 12-hour timer says NOT due,
# but the exact VBS emitted exit event must discover + run the already-
# approved normal maintenance, without a second duplicate discovery.
Invoke-OneCase -Event $actualEvent -Running $false -Armed $true  -Healthy $true  -Ambiguous 0 -CheckExpected 1 -MaintExpected 1
Invoke-OneCase -Event 'OrdinaryTick' -Running $false -Armed $true -Healthy $true -Ambiguous 0 -CheckExpected 0 -MaintExpected 0
Invoke-OneCase -Event $actualEvent -Running $true -Armed $true  -Healthy $true -Ambiguous 0 -CheckExpected 0 -MaintExpected 0
Invoke-OneCase -Event $actualEvent -Running $false -Armed $false -Healthy $true -Ambiguous 0 -CheckExpected 1 -MaintExpected 0
Invoke-OneCase -Event $actualEvent -Running $false -Armed $true  -Healthy $false -Ambiguous 0 -CheckExpected 1 -MaintExpected 0
Invoke-OneCase -Event $actualEvent -Running $false -Armed $true  -Healthy $true  -Ambiguous 1 -CheckExpected 1 -MaintExpected 0
# New R10 real source behavior: a CLOSED agent with a previous unhealthy
# or auto-ambiguous pending result cannot remain permanently inert. It may
# retry discovery ONCE when the original 12-hour timer is due; every
# mutation still requires fresh healthy+unambiguous state and user opt-in.
Invoke-OneCase -Event 'OrdinaryTick' -Running $false -Armed $true -Healthy $true -Ambiguous 0 -PendingBefore $true -InitialHealth Unhealthy -Due $true -CheckExpected 1 -MaintExpected 1 -ClaimExpected $true
Invoke-OneCase -Event 'OrdinaryTick' -Running $false -Armed $true -Healthy $false -Ambiguous 0 -PendingBefore $true -InitialHealth Unhealthy -Due $true -CheckExpected 1 -MaintExpected 0 -ClaimExpected $true
Invoke-OneCase -Event 'OrdinaryTick' -Running $false -Armed $true -Healthy $true -Ambiguous 1 -PendingBefore $true -InitialAmbiguous 1 -Due $true -CheckExpected 1 -MaintExpected 0 -ClaimExpected $true
Invoke-OneCase -Event 'OrdinaryTick' -Running $false -Armed $true -Healthy $true -Ambiguous 0 -PendingBefore $true -InitialHealth Unhealthy -Due $false -CheckExpected 0 -MaintExpected 0
Invoke-OneCase -Event 'OrdinaryTick' -Running $false -Armed $false -Healthy $true -Ambiguous 0 -PendingBefore $true -InitialHealth Unhealthy -Due $true -CheckExpected 1 -MaintExpected 0 -ClaimExpected $true
Invoke-OneCase -Event $actualEvent -Running $false -Armed $true -Healthy $false -Ambiguous 0 -PendingBefore $true -InitialHealth Unhealthy -Due $true -CheckExpected 1 -MaintExpected 0
Write-Host 'R10_UNHEALTHY_AND_AMBIGUOUS_CLOSED_TICK_RATE_LIMITED_DISCOVERY_PASS'
Write-Host 'R10_RECHECK_FAILURE_MUTATION_BLOCKED_AND_FAILED_CHECK_EPOCH_PERSISTED_PASS'
Write-Host 'R10_FRESH_HEALTHY_PENDING_ONLY_MUTATES_WHEN_USER_ARMED_PASS'
Remove-Item -LiteralPath $AgentReport -Force -ErrorAction SilentlyContinue
Write-Host 'STABLE_REAL_AGENTTICK_SPOTIFY_EXIT_IMMEDIATE_CHECK_AND_MAINTENANCE_PASS'
Write-Host 'SPOTIFY_RUNNING_AND_UNARMED_AND_UNHEALTHY_AND_AUTO_AMBIGUOUS_NO_MUTATION_PASS'
Write-Host 'NORMAL_TICK_12_HOUR_POLICY_UNCHANGED_NO_DUPLICATE_CHECK_PASS'
Write-Host 'SYNTHETIC_WINDOWS_ONLY_USER_SPOTIFY_DATA_UNTOUCHED_PASS'
