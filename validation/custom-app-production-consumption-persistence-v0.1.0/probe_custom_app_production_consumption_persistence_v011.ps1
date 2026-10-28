param(
    [Parameter(Mandatory=$true)][string]$AllowedRoot,
    [Parameter(Mandatory=$true)][string]$StoreDirectory,
    [Parameter(Mandatory=$true)][int64]$ExpectedRevision,
    [Parameter(Mandatory=$true)][string]$ExpectedConsumptionId
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-executor-consumption-v0.1.0/custom-app-production-executor-consumption.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-consumption-persistence.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-consumption-persistence-contract-v011.ps1')
$r=Read-CustomAppProductionConsumptionStoreV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory
if(-not [bool]$r.ok){throw ('independent reload failed: '+[string]$r.reason)}
if(-not [bool]$r.reloaded_from_persistent_store){throw 'independent reload did not attest persistent source'}
if([int64]$r.revision -ne $ExpectedRevision){throw "independent reload revision mismatch: $($r.revision) != $ExpectedRevision"}
if(-not [bool]$r.envelope.requires_persisted_consumption_before_executor){throw 'persist-before-executor field missing from independent reload envelope'}
$barrier=Test-CustomAppProductionConsumptionPersistedExecutorBarrierV011 -StoreRead $r -ExpectedConsumptionId $ExpectedConsumptionId
if(-not [bool]$barrier.ok){throw ('persisted executor barrier failed after process restart: '+[string]$barrier.reason)}
if(-not [bool]$barrier.requires_persisted_consumption_before_executor){throw 'barrier lost persisted consumption requirement'}
if([bool]$barrier.persistence_is_authority -or [bool]$barrier.executor_may_stage -or [bool]$barrier.executor_may_apply -or [bool]$barrier.production_execution_authorized -or [bool]$barrier.production_mutation_authorized){throw 'independent reload authority escaped'}
Write-Host ('CUSTOM_APP_PRODUCTION_CONSUMPTION_PERSISTENCE_V011_RELOAD_PROBE_PASS revision='+$r.revision+' consumption_id='+$ExpectedConsumptionId)
