param(
    [Parameter(Mandatory=$true)][string]$AllowedRoot,
    [Parameter(Mandatory=$true)][string]$StoreDirectory,
    [Parameter(Mandatory=$true)][string]$ExpectedTransactionId
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-pre-apply-preparation-v0.1.0/custom-app-production-pre-apply-preparation.ps1')
. (Join-Path $root 'validation/custom-app-production-crash-recovery-journal-v0.1.0/custom-app-production-crash-recovery-journal.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-recovery-evidence.ps1')
$r=Read-CustomAppProductionRecoveryEvidenceV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $ExpectedTransactionId
[ordered]@{ok=[bool]$r.ok;reason=[string]$r.reason;reloaded_from_persistent_store=$(if($r.PSObject.Properties['reloaded_from_persistent_store']){[bool]$r.reloaded_from_persistent_store}else{$false});transaction_id=$(if($r.PSObject.Properties['transaction_id']){[string]$r.transaction_id}else{$null});preparation_fingerprint=$(if($r.PSObject.Properties['preparation_fingerprint']){[string]$r.preparation_fingerprint}else{$null});evidence_fingerprint=$(if($r.PSObject.Properties['evidence_fingerprint']){[string]$r.evidence_fingerprint}else{$null});journal_phase=$(if($r.PSObject.Properties['journal_phase']){[string]$r.journal_phase}else{$null});evidence_is_authority=[bool]$r.evidence_is_authority;execution_authorized=[bool]$r.execution_authorized;restore_authorized=[bool]$r.restore_authorized;apply_authorized=[bool]$r.apply_authorized;cleanup_authorized=[bool]$r.cleanup_authorized;production_mutation_authorized=[bool]$r.production_mutation_authorized}|ConvertTo-Json -Compress
if(-not[bool]$r.ok){exit 1}
