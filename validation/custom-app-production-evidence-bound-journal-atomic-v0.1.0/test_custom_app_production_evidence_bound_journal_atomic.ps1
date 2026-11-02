$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-crash-recovery-journal-v0.1.0/custom-app-production-crash-recovery-journal.ps1')
. (Join-Path $root 'validation/custom-app-production-atomic-live-swap-mutation-v0.1.0/test_custom_app_production_atomic_live_swap_mutation.ps1')
. (Join-Path $root 'validation/custom-app-production-journal-aware-atomic-mutation-v0.1.0/custom-app-production-journal-aware-atomic-mutation.ps1')
. (Join-Path $root 'validation/custom-app-production-journal-aware-atomic-mutation-v0.1.0/custom-app-production-journal-aware-atomic-repair-v011.ps1')
. (Join-Path $root 'validation/custom-app-production-recovery-evidence-envelope-v0.1.0/custom-app-production-recovery-evidence.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-evidence-bound-journal-atomic.ps1')

$script:EvidenceBoundAtomicFaultMode='none'
function Invoke-CustomAppProductionEvidenceBoundJournalAtomicValidationHookV010 {
    param([Parameter(Mandatory=$true)][string]$Checkpoint,[Parameter(Mandatory=$true)]$Context)
    if($script:EvidenceBoundAtomicFaultMode -ceq $Checkpoint){throw ('evidence-bound-fixture-crash:'+ $Checkpoint)}
}
function Get-EBTrustRootV010 {
    $r=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    if(-not (Test-Path -LiteralPath $r -PathType Container)){throw 'evidence-bound fixture trust root missing'}
    return $r
}
function Get-EBStoreV010 {param($Fixture,[string]$Label);return (Join-Path $Fixture.q.x.store.root ('evidence-bound-'+$Label))}
function Get-EBArgsV010 {
    param($Fixture,[string]$Nonce,[string]$Label)
    $p=$Fixture.prepared.result
    return @{
        GenericPreparedResult=$p;Name=[string]$Fixture.q.x.f.name;CallerAdmissionManagedBy='fixture-qualified-admission-v1';CallerAdmissionFingerprint=[string]$p.pre_apply_admission_fingerprint
        AllowedRoot=(Get-EBTrustRootV010);JournalStoreDirectory=(Get-EBStoreV010 $Fixture $Label);TransactionNonce=$Nonce
        ConsumptionId=[string]$p.consumption_id;SourceIdentity=[string]$p.source_identity;RemoteCommitSha=[string]$p.remote_commit_sha;StageResultFingerprint=[string]$p.stage_result_fingerprint;PreparationFingerprint=[string]$p.preparation_fingerprint;StageWorkspacePath=[string]$p.stage_workspace_path
        LivePath=[string]$Fixture.q.x.live;StagePath=[string]$p.stage_path;ExpectedLiveRuntimeTreeSha256=[string]$Fixture.runtime_before.tree_sha256;ExpectedLiveFullTreeSha256=[string]$Fixture.full_before.tree_sha256;ExpectedLiveFullFileCount=[int]$Fixture.full_before.file_count;ExpectedLiveFullTotalBytes=[int64]$Fixture.full_before.total_bytes
        ExpectedStageRuntimeTreeSha256=[string]$p.stage_tree_sha256;AppBackupPath=[string]$p.app_backup_path;ExpectedAppBackupTreeSha256=[string]$p.app_backup_tree_sha256;ExpectedAppBackupFileCount=[int]$p.app_backup_file_count;ExpectedAppBackupTotalBytes=[int64]$p.app_backup_total_bytes
        PersistenceBackupPath=[string]$p.persistence_backup_path;ExpectedPersistenceFingerprint=[string]$p.persistence_fingerprint;LocalAppDataRoot=[string]$Fixture.q.persistence.local;AppDataRoot=[string]$Fixture.q.persistence.roaming
    }
}
function Invoke-EBFixtureV010 {param($Fixture,[string]$Nonce,[string]$Label,[string]$Fault='none');$script:EvidenceBoundAtomicFaultMode=$Fault;try{$a=Get-EBArgsV010 $Fixture $Nonce $Label;return Invoke-CustomAppProductionEvidenceBoundJournalAtomicMutationV010 @a}finally{$script:EvidenceBoundAtomicFaultMode='none'}}
function Get-EBJournalV010 {param($Fixture,[string]$Label);return Read-CustomAppProductionCrashJournalV010 -AllowedRoot (Get-EBTrustRootV010) -StoreDirectory (Get-EBStoreV010 $Fixture $Label)}
function Get-EBEvidenceV010 {param($Fixture,[string]$Label,[string]$TransactionId);return Read-CustomAppProductionRecoveryEvidenceV010 -AllowedRoot (Get-EBTrustRootV010) -StoreDirectory (Get-EBStoreV010 $Fixture $Label) -ExpectedTransactionId $TransactionId}
function Get-EBTransactionRootV010 {
    param([AllowNull()]$Result)
    if($null -eq $Result){return $null}
    if($Result.PSObject.Properties['result'] -and $null -ne $Result.result -and $Result.result.PSObject.Properties['transaction_root']){return [string]$Result.result.transaction_root}
    if($Result.PSObject.Properties['transaction_root']){return [string]$Result.transaction_root}
    return $null
}
function Get-EBInspectionArgsV010 {
    param($Fixture,[string]$Label)
    $jr=Get-EBJournalV010 $Fixture $Label;$p=$Fixture.prepared.result
    return @{
        AllowedRoot=(Get-EBTrustRootV010);JournalStoreDirectory=(Get-EBStoreV010 $Fixture $Label);ExpectedTransactionId=[string]$jr.transaction_id;Name=[string]$Fixture.q.x.f.name
        ExpectedLiveFullTreeSha256=[string]$Fixture.full_before.tree_sha256;ExpectedLiveFullFileCount=[int]$Fixture.full_before.file_count;ExpectedLiveFullTotalBytes=[int64]$Fixture.full_before.total_bytes;ExpectedStageRuntimeTreeSha256=[string]$p.stage_tree_sha256
        ExpectedAppBackupTreeSha256=[string]$p.app_backup_tree_sha256;ExpectedAppBackupFileCount=[int]$p.app_backup_file_count;ExpectedAppBackupTotalBytes=[int64]$p.app_backup_total_bytes;ExpectedPersistenceFingerprint=[string]$p.persistence_fingerprint;LocalAppDataRoot=[string]$Fixture.q.persistence.local;AppDataRoot=[string]$Fixture.q.persistence.roaming
    }
}
function Restore-EBFixtureV010 {
    param($Fixture,[AllowNull()][string]$TransactionRoot)
    $p=$Fixture.prepared.result
    $rb=Restore-CustomAppProductionAtomicLiveSwapV010 -LivePath ([string]$Fixture.q.x.live) -AppBackupPath ([string]$p.app_backup_path) -ExpectedAppBackupTreeSha256 ([string]$p.app_backup_tree_sha256) -PersistenceBackupPath ([string]$p.persistence_backup_path) -ExpectedPersistenceFingerprint ([string]$p.persistence_fingerprint) -LocalAppDataRoot ([string]$Fixture.q.persistence.local) -AppDataRoot ([string]$Fixture.q.persistence.roaming)
    Assert-True ([bool]$rb.ok) ('evidence-bound cleanup restore failed: '+[string]$rb.reason)
    if(-not [string]::IsNullOrWhiteSpace($TransactionRoot) -and (Test-Path -LiteralPath $TransactionRoot)){$parent=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath([string]$Fixture.q.x.live));Remove-CustomAppAtomicDirectoryV010 -Path $TransactionRoot -ExpectedParent $parent -ExpectedName ([IO.Path]::GetFileName($TransactionRoot))}
    Assert-AtomicOriginalRestoredV010 $Fixture 'evidence-bound cleanup'
}
function Assert-EBZeroAuthorityV010 {param($Value,[string]$Label);foreach($f in @('result_is_authority','spicetify_apply_authorized','additional_mutation_authorized','production_execution_authorized','production_mutation_authorized')){if($Value.PSObject.Properties[$f]){Assert-False ([bool]$Value.$f) "$Label authority escaped $f"}}}

$count=0

$preEvidence=New-AtomicFixtureV010 'evidence-bound-before-candidate' -Nonce '41414141414141414141414141414141'
$r=Invoke-EBFixtureV010 -Fixture $preEvidence -Nonce 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' -Label 'before-candidate' -Fault 'after-recovery-evidence-before-candidate-preparation'
Assert-False ([bool]$r.ok) 'evidence-before-candidate crash unexpectedly succeeded'
Assert-True ([bool]$r.recovery_evidence_persisted) 'evidence-before-candidate was not durably persisted'
Assert-True ([string]$r.journal_phase -ceq 'prepared') 'evidence-before-candidate phase drift'
Assert-False ([bool]$r.live_move_started) 'evidence-before-candidate incorrectly marked live move'
$jr=Get-EBJournalV010 $preEvidence 'before-candidate';Assert-True ([string]$jr.entry.phase -ceq 'prepared') 'evidence-before-candidate durable journal advanced'
$ev=Get-EBEvidenceV010 $preEvidence 'before-candidate' ([string]$jr.transaction_id);Assert-True ([bool]$ev.ok) ('evidence-before-candidate durable evidence unreadable: '+[string]$ev.reason)
Assert-False (Test-Path -LiteralPath ([string]$r.transaction_root)) 'evidence-before-candidate created transaction workspace before hook'
Assert-AtomicOriginalRestoredV010 $preEvidence 'evidence-before-candidate live state';$count++

$valid=New-AtomicFixtureV010 'evidence-bound-valid' -Nonce '42424242424242424242424242424242'
$r=Invoke-EBFixtureV010 -Fixture $valid -Nonce 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' -Label 'valid'
try{
    Assert-True ([bool]$r.ok) ('evidence-bound valid denied: '+[string]$r.reason);Assert-True ([bool]$r.result.recovery_evidence_persisted) 'valid evidence flag false';Assert-True ([bool]$r.result.recovery_evidence_bound_before_atomic_barrier) 'valid evidence ordering flag false';Assert-EBZeroAuthorityV010 $r.result 'valid'
    $rc=Test-CustomAppProductionEvidenceBoundJournalAtomicResultV010 -Result $r.result;Assert-True ([bool]$rc.ok) ('valid result self-check denied: '+[string]$rc.reason)
    $jr=Get-EBJournalV010 $valid 'valid';Assert-True ([string]$jr.entry.phase -ceq 'candidate-live') 'valid journal phase drift'
    $ev=Get-EBEvidenceV010 $valid 'valid' ([string]$jr.transaction_id);Assert-True ([bool]$ev.ok) ('valid evidence not readable after candidate-live: '+[string]$ev.reason);Assert-True ([string]$ev.evidence_fingerprint -ceq [string]$r.result.recovery_evidence_fingerprint) 'valid evidence fingerprint drift'
    $count++
}finally{Restore-EBFixtureV010 $valid (Get-EBTransactionRootV010 $r)}

$preFirst=New-AtomicFixtureV010 'evidence-bound-pre-first' -Nonce '43434343434343434343434343434343'
$r=Invoke-EBFixtureV010 -Fixture $preFirst -Nonce 'cccccccccccccccccccccccccccccccc' -Label 'pre-first' -Fault 'after-atomic-starting-before-live-move'
try{
    Assert-False ([bool]$r.ok) 'evidence-bound pre-first crash unexpectedly succeeded';Assert-True ([bool]$r.recovery_evidence_persisted) 'pre-first evidence flag false';Assert-True ([string]$r.journal_phase -ceq 'atomic-mutation-starting') 'pre-first phase drift'
    $ia=Get-EBInspectionArgsV010 $preFirst 'pre-first';$i=Resolve-CustomAppProductionJournalAwareAtomicStartingInspectionV010 @ia;Assert-True ([bool]$i.ok) ('pre-first inspection denied: '+[string]$i.reason);Assert-True ([string]$i.receipt.state -ceq 'pre-first-rename-exact') 'pre-first exact state mismatch'
    $repair=Invoke-CustomAppProductionJournalAwareAtomicStartingRepairV010 @ia -Now ([DateTimeOffset]::UtcNow.AddMinutes(-1));Assert-True ([bool]$repair.ok) ('pre-first repair denied: '+[string]$repair.reason);Assert-True ([string]$repair.phase -ceq 'rollback-required') 'pre-first repair phase mismatch'
    $ev=Get-EBEvidenceV010 $preFirst 'pre-first' ([string]$repair.transaction_id);Assert-True ([bool]$ev.ok) ('pre-first evidence unreadable after repair phase advance: '+[string]$ev.reason);$count++
}finally{Restore-EBFixtureV010 $preFirst (Get-EBTransactionRootV010 $r)}

$postFirst=New-AtomicFixtureV010 'evidence-bound-post-first' -Nonce '44444444444444444444444444444444'
$r=Invoke-EBFixtureV010 -Fixture $postFirst -Nonce 'dddddddddddddddddddddddddddddddd' -Label 'post-first' -Fault 'after-live-move-before-journal'
try{
    Assert-False ([bool]$r.ok) 'evidence-bound post-first crash unexpectedly succeeded';Assert-True ([bool]$r.live_move_started) 'post-first live move not recorded';Assert-True ([bool]$r.recovery_evidence_persisted) 'post-first evidence flag false'
    $ia=Get-EBInspectionArgsV010 $postFirst 'post-first';$i=Resolve-CustomAppProductionJournalAwareAtomicStartingInspectionV010 @ia;Assert-True ([bool]$i.ok) ('post-first inspection denied: '+[string]$i.reason);Assert-True ([string]$i.receipt.state -ceq 'first-rename-complete-unjournaled') 'post-first exact state mismatch'
    $repair=Invoke-CustomAppProductionJournalAwareAtomicStartingRepairV010 @ia;Assert-True ([bool]$repair.ok) ('post-first repair denied: '+[string]$repair.reason);Assert-True ([string]$repair.phase -ceq 'live-moved-to-old') 'post-first repair phase mismatch'
    $ev=Get-EBEvidenceV010 $postFirst 'post-first' ([string]$repair.transaction_id);Assert-True ([bool]$ev.ok) ('post-first evidence unreadable after normalization: '+[string]$ev.reason)
    $class=Resolve-CustomAppProductionCrashRecoveryClassificationV010 -StoreRead (Get-EBJournalV010 $postFirst 'post-first') -ExpectedTransactionId ([string]$repair.transaction_id);Assert-True ([string]$class.classification -ceq 'exact-app-and-persistence-recovery-required') 'post-first classification drift';$count++
}finally{Restore-EBFixtureV010 $postFirst (Get-EBTransactionRootV010 $r)}

$tamper=New-AtomicFixtureV010 'evidence-bound-prepared-tamper' -Nonce '45454545454545454545454545454545'
$a=Get-EBArgsV010 $tamper 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee' 'prepared-tamper';$bad=(($tamper.prepared.result|ConvertTo-Json -Depth 40)|ConvertFrom-Json);$bad.app_backup_tree_sha256=('0'*64);$a.GenericPreparedResult=$bad
$r=Invoke-CustomAppProductionEvidenceBoundJournalAtomicMutationV010 @a
Assert-False ([bool]$r.ok) 'tampered generic prepared result accepted';Assert-True ([string]$r.reason -like 'evidence-bound-atomic-prepared-denied:*') 'tampered prepared denial reason drift'
Assert-False (Test-Path -LiteralPath (Get-EBStoreV010 $tamper 'prepared-tamper')) 'tampered prepared created journal store'
Assert-AtomicOriginalRestoredV010 $tamper 'tampered prepared live state';$count++

if($count -ne 5){throw "evidence-bound journal atomic matrix count mismatch $count"}
Write-Output "CUSTOM_APP_PRODUCTION_EVIDENCE_BOUND_JOURNAL_ATOMIC_MATRIX_PASS cases=$count"
