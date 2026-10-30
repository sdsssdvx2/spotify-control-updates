param(
    [Parameter(Mandatory=$true)][string]$AllowedRoot,
    [Parameter(Mandatory=$true)][string]$StoreDirectory,
    [Parameter(Mandatory=$true)][string]$ExpectedTransactionId
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-crash-recovery-journal-v0.1.0/custom-app-production-crash-recovery-journal.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-recovery-plan.ps1')
$plan=Resolve-CustomAppProductionRecoveryPlanV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $ExpectedTransactionId
$check=Test-CustomAppProductionRecoveryPlanV010 $plan
[ordered]@{valid=[bool]$check.ok;reason=[string]$check.reason;transaction_id=[string]$plan.transaction_id;phase=[string]$plan.phase;classification=[string]$plan.classification;recovery_verb=[string]$plan.recovery_verb;requires_fresh_filesystem_revalidation=[bool]$plan.requires_fresh_filesystem_revalidation;requires_recovery_executor=[bool]$plan.requires_recovery_executor;requires_recovery_apply=[bool]$plan.requires_recovery_apply;requires_manual_inspection=[bool]$plan.requires_manual_inspection;plan_is_authority=[bool]$plan.plan_is_authority;execution_authorized=[bool]$plan.execution_authorized;restore_authorized=[bool]$plan.restore_authorized;apply_authorized=[bool]$plan.apply_authorized;cleanup_authorized=[bool]$plan.cleanup_authorized;production_mutation_authorized=[bool]$plan.production_mutation_authorized;plan_fingerprint=[string]$plan.plan_fingerprint}|ConvertTo-Json -Compress
