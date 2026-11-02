$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-crash-recovery-journal-v0.1.0/custom-app-production-crash-recovery-journal.ps1')
. (Join-Path $root 'validation/custom-app-production-atomic-live-swap-mutation-v0.1.0/test_custom_app_production_atomic_live_swap_mutation.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-journal-aware-atomic-mutation.ps1')

function Invoke-CustomAppProductionJournalAwareAtomicValidationHookV010 {
    param([Parameter(Mandatory=$true)][string]$Checkpoint,[Parameter(Mandatory=$true)]$Context)
}

$f=New-AtomicFixtureV010 'journal-aware-debug-valid' -Nonce '41414141414141414141414141414141'
$p=$f.prepared.result
$a=@{
    Name=[string]$f.q.x.f.name
    CallerAdmissionManagedBy='fixture-qualified-admission-v1'
    CallerAdmissionFingerprint=[string]$p.pre_apply_admission_fingerprint
    AllowedRoot=[string]$f.q.x.store.root
    JournalStoreDirectory=(Join-Path $f.q.x.store.root 'journal-aware-debug-valid')
    TransactionNonce='abababababababababababababababab'
    ConsumptionId=[string]$p.consumption_id
    SourceIdentity=[string]$p.source_identity
    RemoteCommitSha=[string]$p.remote_commit_sha
    StageResultFingerprint=[string]$p.stage_result_fingerprint
    PreparationFingerprint=[string]$p.preparation_fingerprint
    StageWorkspacePath=[string]$p.stage_workspace_path
    LivePath=[string]$f.q.x.live
    StagePath=[string]$p.stage_path
    ExpectedLiveRuntimeTreeSha256=[string]$f.runtime_before.tree_sha256
    ExpectedLiveFullTreeSha256=[string]$f.full_before.tree_sha256
    ExpectedLiveFullFileCount=[int]$f.full_before.file_count
    ExpectedLiveFullTotalBytes=[int64]$f.full_before.total_bytes
    ExpectedStageRuntimeTreeSha256=[string]$p.stage_tree_sha256
    AppBackupPath=[string]$p.app_backup_path
    ExpectedAppBackupTreeSha256=[string]$p.app_backup_tree_sha256
    ExpectedAppBackupFileCount=[int]$p.app_backup_file_count
    ExpectedAppBackupTotalBytes=[int64]$p.app_backup_total_bytes
    PersistenceBackupPath=[string]$p.persistence_backup_path
    ExpectedPersistenceFingerprint=[string]$p.persistence_fingerprint
    LocalAppDataRoot=[string]$f.q.persistence.local
    AppDataRoot=[string]$f.q.persistence.roaming
}
$r=Invoke-CustomAppProductionJournalAwareAtomicMutationV010 @a
Write-Output ('DEBUG_VALID_RESULT='+($r|ConvertTo-Json -Depth 20 -Compress))
if(-not [bool]$r.ok){throw ('DEBUG_VALID_DENIED:'+[string]$r.reason)}
Write-Output 'DEBUG_VALID_OK'
