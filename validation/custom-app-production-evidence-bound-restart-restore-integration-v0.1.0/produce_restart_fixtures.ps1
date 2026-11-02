param(
    [Parameter(Mandatory=$true)][string]$OutputDirectory
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-evidence-bound-journal-atomic-v0.1.0/test_custom_app_production_evidence_bound_journal_atomic.ps1')

function Assert-EBRRTrue([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Assert-EBRREq($Actual,$Expected,[string]$Message){if([string]$Actual -cne [string]$Expected){throw "$Message actual=<$Actual> expected=<$Expected>"}}

$handoffRoot=[IO.Path]::GetFullPath($OutputDirectory)
[IO.Directory]::CreateDirectory($handoffRoot)|Out-Null

function Write-EBRRHandoffV010 {
    param(
        [Parameter(Mandatory=$true)]$Fixture,
        [Parameter(Mandatory=$true)][string]$Label,
        [Parameter(Mandatory=$true)][string]$ExpectedPhase,
        [Parameter(Mandatory=$true)][string]$TransactionRoot,
        [Parameter(Mandatory=$true)][string]$FileName
    )
    $jr=Get-EBJournalV010 -Fixture $Fixture -Label $Label
    Assert-EBRRTrue ([bool]$jr.ok) "$Label journal unreadable: $([string]$jr.reason)"
    Assert-EBRREq ([string]$jr.entry.phase) $ExpectedPhase "$Label durable phase"
    $ev=Get-EBEvidenceV010 -Fixture $Fixture -Label $Label -TransactionId ([string]$jr.transaction_id)
    Assert-EBRRTrue ([bool]$ev.ok) "$Label evidence unreadable: $([string]$ev.reason)"
    $txn=[IO.Path]::GetFullPath($TransactionRoot).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    Assert-EBRRTrue (Test-Path -LiteralPath $txn -PathType Container) "$Label transaction root missing before handoff"
    $liveParent=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath([string]$Fixture.q.x.live))
    Assert-EBRREq ([IO.Path]::GetDirectoryName($txn)) $liveParent "$Label transaction root parent"
    Assert-EBRRTrue ([IO.Path]::GetFileName($txn) -cmatch '^\.spotify-control-txn-[0-9a-f]{32}$') "$Label transaction root name invalid"
    $p=$Fixture.prepared.result
    $state=[ordered]@{
        schema=1
        managed_by='custom-app-production-evidence-bound-restart-restore-fixture-v1'
        label=$Label
        producer_pid=[int]$PID
        produced_at=[DateTimeOffset]::UtcNow.ToString('o')
        allowed_root=(Get-EBTrustRootV010)
        store_directory=(Get-EBStoreV010 -Fixture $Fixture -Label $Label)
        transaction_id=([string]$jr.transaction_id).Trim().ToLowerInvariant()
        journal_phase=[string]$jr.entry.phase
        journal_revision=[int64]$jr.revision
        journal_entry_sha256=([string]$jr.entry.entry_sha256).Trim().ToLowerInvariant()
        evidence_fingerprint=([string]$ev.evidence_fingerprint).Trim().ToLowerInvariant()
        evidence_path=[string]$ev.path
        name=[string]$Fixture.q.x.f.name
        source_identity=[string]$p.source_identity
        remote_commit_sha=[string]$p.remote_commit_sha
        consumption_id=([string]$p.consumption_id).Trim().ToLowerInvariant()
        preparation_fingerprint=([string]$p.preparation_fingerprint).Trim().ToLowerInvariant()
        live_path=[string]$Fixture.q.x.live
        transaction_root=$txn
        stage_workspace_path=[string]$p.stage_workspace_path
        stage_path=[string]$p.stage_path
        stage_tree_sha256=([string]$p.stage_tree_sha256).Trim().ToLowerInvariant()
        app_backup_path=[string]$p.app_backup_path
        app_backup_tree_sha256=([string]$p.app_backup_tree_sha256).Trim().ToLowerInvariant()
        app_backup_file_count=[int]$p.app_backup_file_count
        app_backup_total_bytes=[int64]$p.app_backup_total_bytes
        persistence_backup_path=[string]$p.persistence_backup_path
        persistence_fingerprint=([string]$p.persistence_fingerprint).Trim().ToLowerInvariant()
        local_app_data_root=[string]$Fixture.q.persistence.local
        app_data_root=[string]$Fixture.q.persistence.roaming
    }
    $path=Join-Path $handoffRoot $FileName
    [IO.File]::WriteAllText($path,($state|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
    return $path
}

# Case 1: process death after the first same-parent rename but before live-moved-to-old journal append.
# The exact #189 repair layer must recognize the unjournaled rename from durable evidence and
# normalize the journal to live-moved-to-old without restoring anything in this producer process.
$first=New-AtomicFixtureV010 'restart-restore-first-rename' -Nonce '51515151515151515151515151515151'
$firstLabel='restart-first-rename'
$firstResult=Invoke-EBFixtureV010 -Fixture $first -Nonce 'f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1' -Label $firstLabel -Fault 'after-live-move-before-journal'
Assert-EBRRTrue (-not [bool]$firstResult.ok) 'first-rename crash unexpectedly succeeded'
Assert-EBRRTrue ([bool]$firstResult.live_move_started) 'first-rename crash did not perform live rename'
Assert-EBRRTrue ([bool]$firstResult.recovery_evidence_persisted) 'first-rename crash lost durable recovery evidence'
$firstTxn=Get-EBTransactionRootV010 $firstResult
Assert-EBRRTrue (-not [string]::IsNullOrWhiteSpace($firstTxn)) 'first-rename result lost transaction root'
$inspectArgs=Get-EBInspectionArgsV010 -Fixture $first -Label $firstLabel
$inspection=Resolve-CustomAppProductionJournalAwareAtomicStartingInspectionV010 @inspectArgs
Assert-EBRRTrue ([bool]$inspection.ok) "first-rename inspection denied: $([string]$inspection.reason)"
Assert-EBRREq ([string]$inspection.receipt.state) 'first-rename-complete-unjournaled' 'first-rename inspection state'
$repair=Invoke-CustomAppProductionJournalAwareAtomicStartingRepairV010 @inspectArgs -Now ([DateTimeOffset]::UtcNow.AddMinutes(-1))
Assert-EBRRTrue ([bool]$repair.ok) "first-rename normalization denied: $([string]$repair.reason)"
Assert-EBRREq ([string]$repair.phase) 'live-moved-to-old' 'first-rename normalized phase'
$firstPath=Write-EBRRHandoffV010 -Fixture $first -Label $firstLabel -ExpectedPhase 'live-moved-to-old' -TransactionRoot $firstTxn -FileName 'restart-first-rename.json'

# Case 2: the evidence-bound atomic step reached candidate-live and then the owning process died
# before transaction finalization/apply. Leave the exact live candidate + old-live transaction tree
# untouched for the independent recovery process.
$candidate=New-AtomicFixtureV010 'restart-restore-candidate-live' -Nonce '52525252525252525252525252525252'
$candidateLabel='restart-candidate-live'
$candidateResult=Invoke-EBFixtureV010 -Fixture $candidate -Nonce 'f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2f2' -Label $candidateLabel
Assert-EBRRTrue ([bool]$candidateResult.ok) "candidate-live production denied: $([string]$candidateResult.reason)"
Assert-EBRRTrue ([bool]$candidateResult.result.recovery_evidence_persisted) 'candidate-live durable evidence flag false'
Assert-EBRRTrue ([bool]$candidateResult.result.recovery_evidence_bound_before_atomic_barrier) 'candidate-live evidence ordering flag false'
$candidateTxn=Get-EBTransactionRootV010 $candidateResult
Assert-EBRRTrue (-not [string]::IsNullOrWhiteSpace($candidateTxn)) 'candidate-live result lost transaction root'
$candidatePath=Write-EBRRHandoffV010 -Fixture $candidate -Label $candidateLabel -ExpectedPhase 'candidate-live' -TransactionRoot $candidateTxn -FileName 'restart-candidate-live.json'

Write-Output "CUSTOM_APP_PRODUCTION_EVIDENCE_BOUND_RESTART_FIXTURE_PASS first=$firstPath candidate=$candidatePath producer_pid=$PID"
