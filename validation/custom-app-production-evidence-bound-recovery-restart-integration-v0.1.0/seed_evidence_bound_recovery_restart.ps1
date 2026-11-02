param([Parameter(Mandatory=$true)][string]$StatePath)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-evidence-bound-journal-atomic-v0.1.0/test_custom_app_production_evidence_bound_journal_atomic.ps1')

function Assert-SeedTrue([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Assert-SeedEq($Actual,$Expected,[string]$Message){if([string]$Actual -cne [string]$Expected){throw "$Message actual=<$Actual> expected=<$Expected>"}}

$fixture=New-AtomicFixtureV010 'evidence-bound-restart-seed' -Nonce '56565656565656565656565656565656'
$result=Invoke-EBFixtureV010 -Fixture $fixture -Nonce 'abababababababababababababababab' -Label 'restart-seed' -Fault 'after-live-move-before-journal'
Assert-SeedTrue (-not [bool]$result.ok) 'restart seed crash unexpectedly succeeded'
Assert-SeedTrue ([bool]$result.live_move_started) 'restart seed did not cross first live rename'
Assert-SeedTrue ([bool]$result.recovery_evidence_persisted) 'restart seed recovery evidence not durable'

$inspectArgs=Get-EBInspectionArgsV010 $fixture 'restart-seed'
$inspection=Resolve-CustomAppProductionJournalAwareAtomicStartingInspectionV010 @inspectArgs
Assert-SeedTrue ([bool]$inspection.ok) ('restart seed inspection denied: '+[string]$inspection.reason)
Assert-SeedEq $inspection.receipt.state 'first-rename-complete-unjournaled' 'restart seed inspection state'

$repair=Invoke-CustomAppProductionJournalAwareAtomicStartingRepairV010 @inspectArgs -Now ([DateTimeOffset]::UtcNow.AddMinutes(-1))
Assert-SeedTrue ([bool]$repair.ok) ('restart seed normalization denied: '+[string]$repair.reason)
Assert-SeedEq $repair.phase 'live-moved-to-old' 'restart seed normalized phase'

$journal=Get-EBJournalV010 $fixture 'restart-seed'
Assert-SeedTrue ([bool]$journal.ok) 'restart seed journal unreadable after normalization'
Assert-SeedEq $journal.entry.phase 'live-moved-to-old' 'restart seed durable journal phase'
$tx=([string]$journal.transaction_id).Trim().ToLowerInvariant()
$evidence=Read-CustomAppProductionRecoveryEvidenceV010 -AllowedRoot (Get-EBTrustRootV010) -StoreDirectory (Get-EBStoreV010 $fixture 'restart-seed') -ExpectedTransactionId $tx
Assert-SeedTrue ([bool]$evidence.ok) ('restart seed evidence unreadable: '+[string]$evidence.reason)

$prepared=$fixture.prepared.result
$state=[ordered]@{
    schema=1
    managed_by='custom-app-production-evidence-bound-recovery-restart-seed-v1'
    transaction_id=$tx
    allowed_root=(Get-EBTrustRootV010)
    store_directory=(Get-EBStoreV010 $fixture 'restart-seed')
    live_path=[string]$fixture.q.x.live
    local_app_data_root=[string]$fixture.q.persistence.local
    app_data_root=[string]$fixture.q.persistence.roaming
    stage_workspace_path=[string]$prepared.stage_workspace_path
    transaction_root=[string]$journal.entry.transaction_root
    app_backup_path=[string]$prepared.app_backup_path
    app_backup_tree_sha256=([string]$prepared.app_backup_tree_sha256).Trim().ToLowerInvariant()
    app_backup_file_count=[int]$prepared.app_backup_file_count
    app_backup_total_bytes=[int64]$prepared.app_backup_total_bytes
    persistence_backup_path=[string]$prepared.persistence_backup_path
    persistence_fingerprint=([string]$prepared.persistence_fingerprint).Trim().ToLowerInvariant()
    recovery_evidence_fingerprint=([string]$evidence.evidence_fingerprint).Trim().ToLowerInvariant()
    recovery_evidence_path=[string]$evidence.path
    normalized_phase=[string]$journal.entry.phase
    source_identity=[string]$prepared.source_identity
    remote_commit_sha=[string]$prepared.remote_commit_sha
    consumption_id=[string]$prepared.consumption_id
    preparation_fingerprint=[string]$prepared.preparation_fingerprint
}
$parent=Split-Path -Parent $StatePath
if(-not [string]::IsNullOrWhiteSpace($parent)){[IO.Directory]::CreateDirectory($parent)|Out-Null}
[IO.File]::WriteAllText($StatePath,($state|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
Write-Output ('CUSTOM_APP_PRODUCTION_EVIDENCE_BOUND_RECOVERY_RESTART_SEED_PASS tx='+$tx)
