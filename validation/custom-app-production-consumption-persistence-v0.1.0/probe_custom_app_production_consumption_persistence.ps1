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
$r=Read-CustomAppProductionConsumptionStoreV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory
if(-not [bool]$r.ok){throw ('independent reload failed: '+[string]$r.reason)}
if(-not [bool]$r.reloaded_from_persistent_store){throw 'independent reload did not attest persistent source'}
if([int64]$r.revision -ne $ExpectedRevision){throw "independent reload revision mismatch: $($r.revision) != $ExpectedRevision"}
$rows=@($r.state.consumptions);if($rows.Count -ne $ExpectedRevision){throw 'independent reload row count mismatch'}
if($rows.Count -lt 1 -or ([string]$rows[-1].consumption_id).Trim().ToLowerInvariant() -cne $ExpectedConsumptionId.Trim().ToLowerInvariant()){throw 'independent reload consumption id mismatch'}
if([bool]$r.persistence_is_authority -or [bool]$r.executor_may_stage -or [bool]$r.executor_may_apply -or [bool]$r.production_execution_authorized -or [bool]$r.production_mutation_authorized){throw 'independent reload authority escaped'}
Write-Host ('CUSTOM_APP_PRODUCTION_CONSUMPTION_PERSISTENCE_RELOAD_PROBE_PASS revision='+$r.revision+' consumption_id='+$ExpectedConsumptionId)
