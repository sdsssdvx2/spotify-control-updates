param(
    [Parameter(Mandatory=$true)][string]$AllowedRoot,
    [Parameter(Mandatory=$true)][string]$StoreDirectory,
    [Parameter(Mandatory=$true)][string]$ExpectedTransactionId
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-crash-recovery-journal-v0.1.0/custom-app-production-crash-recovery-journal.ps1')
. (Join-Path $root 'validation/custom-app-production-recovery-restore-executor-v0.1.0/custom-app-production-recovery-restore-executor.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-recovery-completion-evidence.ps1')
$r=Read-CustomAppProductionRecoveryCompletionEvidenceV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $ExpectedTransactionId
if($null-eq$r -or -not[bool]$r.ok){throw ('recovery completion evidence reload probe failed: '+[string]$r.reason)}
[ordered]@{
    ok=$true
    reason=[string]$r.reason
    transaction_id=[string]$r.envelope.transaction_id
    completion_fingerprint=[string]$r.completion_fingerprint
    reloaded_from_persistent_store=[bool]$r.reloaded_from_persistent_store
    evidence_is_authority=[bool]$r.evidence_is_authority
    execution_authorized=[bool]$r.execution_authorized
    restore_authorized=[bool]$r.restore_authorized
    apply_authorized=[bool]$r.apply_authorized
    cleanup_authorized=[bool]$r.cleanup_authorized
    production_mutation_authorized=[bool]$r.production_mutation_authorized
}|ConvertTo-Json -Compress
