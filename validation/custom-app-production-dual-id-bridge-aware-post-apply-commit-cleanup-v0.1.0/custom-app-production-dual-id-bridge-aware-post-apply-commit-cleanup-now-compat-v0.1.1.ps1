$CustomAppProductionDualIdBridgeAwarePostApplyCommitCleanupNowCompatSchema=1
$CustomAppProductionDualIdBridgeAwarePostApplyCommitCleanupNowCompatManagedBy='custom-app-production-dual-id-bridge-aware-post-apply-commit-cleanup-now-compat-v1'

if(-not(Test-Path Function:\Test-CustomAppProductionDualIdBridgeAwarePostApplyCommitCleanupCurrentStateV010)){throw 'dual-id-cleanup-now-compat-base-current-state-function-missing'}
$script:CustomAppProductionDualIdBridgeAwarePostApplyCommitCleanupOriginalCurrentStateV010=${function:Test-CustomAppProductionDualIdBridgeAwarePostApplyCommitCleanupCurrentStateV010}

function Test-CustomAppProductionDualIdBridgeAwarePostApplyCommitCleanupCurrentStateV010 {
    param(
        [Parameter(Mandatory=$true)]$DualIdApplyResult,
        [Parameter(Mandatory=$true)]$DualIdFinalizationResult,
        [Parameter(Mandatory=$true)]$DurableBridgeIntegrationResult,
        [Parameter(Mandatory=$true)]$EvidenceBoundAtomicResult,
        [Parameter(Mandatory=$true)]$GenericPreparedResult,
        [Parameter(Mandatory=$true)]$GenericStageExecutorResult,
        [Parameter(Mandatory=$true)]$Permit,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)]$LifecycleRow,
        [Parameter(Mandatory=$true)]$ProvenanceRow,
        [Parameter(Mandatory=$true)]$BindingRow,
        [Parameter(Mandatory=$true)][string]$AllowedRoot,
        [Parameter(Mandatory=$true)][string]$JournalStoreDirectory,
        [Parameter(Mandatory=$true)][string]$ConsumptionStoreDirectory,
        [Parameter(Mandatory=$true)][byte[]]$SessionKey,
        [Parameter(Mandatory=$true)][string]$LocalAppDataRoot,
        [Parameter(Mandatory=$true)][string]$AppDataRoot,
        [DateTimeOffset]$Now=[DateTimeOffset]::UtcNow
    )
    $forward=@{}
    foreach($key in $PSBoundParameters.Keys){if([string]$key-cne'Now'){$forward[$key]=$PSBoundParameters[$key]}}
    return (& $script:CustomAppProductionDualIdBridgeAwarePostApplyCommitCleanupOriginalCurrentStateV010 @forward)
}
