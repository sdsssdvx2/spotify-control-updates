$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-crash-recovery-journal-v0.1.0/custom-app-production-crash-recovery-journal.ps1')
. (Join-Path $root 'validation/custom-app-production-atomic-live-swap-mutation-v0.1.0/test_custom_app_production_atomic_live_swap_mutation.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-journal-aware-atomic-mutation.ps1')

$script:JournalAwareAtomicFaultMode='none'
function Invoke-CustomAppProductionJournalAwareAtomicValidationHookV010 {
    param([Parameter(Mandatory=$true)][string]$Checkpoint,[Parameter(Mandatory=$true)]$Context)
    if($script:JournalAwareAtomicFaultMode -ceq $Checkpoint){throw ('fixture-crash-window:'+ $Checkpoint)}
}

function Get-JATrustRootV010 {
    $r=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    if(-not (Test-Path -LiteralPath $r -PathType Container)){throw 'fixture profile-like trust root missing'}
    return $r
}
function Get-JAFixtureArgsV010 {
    param($Fixture,[string]$Nonce,[string]$JournalLabel)
    $p=$Fixture.prepared.result
    $journal=Join-Path $Fixture.q.x.store.root ('journal-aware-'+$JournalLabel)
    return @{
        Name=[string]$Fixture.q.x.f.name;CallerAdmissionManagedBy='fixture-qualified-admission-v1';CallerAdmissionFingerprint=[string]$p.pre_apply_admission_fingerprint
        AllowedRoot=(Get-JATrustRootV010);JournalStoreDirectory=$journal;TransactionNonce=$Nonce
        ConsumptionId=[string]$p.consumption_id;SourceIdentity=[string]$p.source_identity;RemoteCommitSha=[string]$p.remote_commit_sha;StageResultFingerprint=[string]$p.stage_result_fingerprint;PreparationFingerprint=[string]$p.preparation_fingerprint;StageWorkspacePath=[string]$p.stage_workspace_path
        LivePath=[string]$Fixture.q.x.live;StagePath=[string]$p.stage_path
        ExpectedLiveRuntimeTreeSha256=[string]$Fixture.runtime_before.tree_sha256;ExpectedLiveFullTreeSha256=[string]$Fixture.full_before.tree_sha256;ExpectedLiveFullFileCount=[int]$Fixture.full_before.file_count;ExpectedLiveFullTotalBytes=[int64]$Fixture.full_before.total_bytes
        ExpectedStageRuntimeTreeSha256=[string]$p.stage_tree_sha256;AppBackupPath=[string]$p.app_backup_path;ExpectedAppBackupTreeSha256=[string]$p.app_backup_tree_sha256;ExpectedAppBackupFileCount=[int]$p.app_backup_file_count;ExpectedAppBackupTotalBytes=[int64]$p.app_backup_total_bytes
        PersistenceBackupPath=[string]$p.persistence_backup_path;ExpectedPersistenceFingerprint=[string]$p.persistence_fingerprint;LocalAppDataRoot=[string]$Fixture.q.persistence.local;AppDataRoot=[string]$Fixture.q.persistence.roaming
    }
}
function Invoke-JAFixtureV010 {
    param($Fixture,[string]$Nonce,[string]$JournalLabel,[string]$Fault='none')
    $script:JournalAwareAtomicFaultMode=$Fault
    $a=Get-JAFixtureArgsV010 -Fixture $Fixture -Nonce $Nonce -JournalLabel $JournalLabel
    return Invoke-CustomAppProductionJournalAwareAtomicMutationV010 @a
}
function Get-JAReadV010 {param($Fixture,[string]$JournalLabel);Read-CustomAppProductionCrashJournalV010 -AllowedRoot (Get-JATrustRootV010) -StoreDirectory (Join-Path $Fixture.q.x.store.root ('journal-aware-'+$JournalLabel))}
function Get-JAInspectionArgsV010 {
    param($Fixture,[string]$JournalLabel)
    $r=Get-JAReadV010 -Fixture $Fixture -JournalLabel $JournalLabel;$p=$Fixture.prepared.result
    return @{
        AllowedRoot=(Get-JATrustRootV010);JournalStoreDirectory=(Join-Path $Fixture.q.x.store.root ('journal-aware-'+$JournalLabel));ExpectedTransactionId=[string]$r.transaction_id;Name=[string]$Fixture.q.x.f.name
        ExpectedLiveFullTreeSha256=[string]$Fixture.full_before.tree_sha256;ExpectedLiveFullFileCount=[int]$Fixture.full_before.file_count;ExpectedLiveFullTotalBytes=[int64]$Fixture.full_before.total_bytes;ExpectedStageRuntimeTreeSha256=[string]$p.stage_tree_sha256
        ExpectedAppBackupTreeSha256=[string]$p.app_backup_tree_sha256;ExpectedAppBackupFileCount=[int]$p.app_backup_file_count;ExpectedAppBackupTotalBytes=[int64]$p.app_backup_total_bytes;ExpectedPersistenceFingerprint=[string]$p.persistence_fingerprint;LocalAppDataRoot=[string]$Fixture.q.persistence.local;AppDataRoot=[string]$Fixture.q.persistence.roaming
    }
}
function Get-JATransactionRootV010 {
    param([AllowNull()]$Result)
    if($null -eq $Result){return $null}
    if($Result.PSObject.Properties['result'] -and $null -ne $Result.result -and $Result.result.PSObject.Properties['transaction_root']){return [string]$Result.result.transaction_root}
    if($Result.PSObject.Properties['transaction_root']){return [string]$Result.transaction_root}
    return $null
}
function Restore-JAFixtureV010 {
    param($Fixture,[AllowNull()][string]$TransactionRoot)
    $p=$Fixture.prepared.result
    $rb=Restore-CustomAppProductionAtomicLiveSwapV010 -LivePath ([string]$Fixture.q.x.live) -AppBackupPath ([string]$p.app_backup_path) -ExpectedAppBackupTreeSha256 ([string]$p.app_backup_tree_sha256) -PersistenceBackupPath ([string]$p.persistence_backup_path) -ExpectedPersistenceFingerprint ([string]$p.persistence_fingerprint) -LocalAppDataRoot ([string]$Fixture.q.persistence.local) -AppDataRoot ([string]$Fixture.q.persistence.roaming)
    Assert-True ([bool]$rb.ok) ('journal-aware cleanup restore failed: '+[string]$rb.reason)
    if(-not [string]::IsNullOrWhiteSpace($TransactionRoot) -and (Test-Path -LiteralPath $TransactionRoot)){
        $parent=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath([string]$Fixture.q.x.live))
        Remove-CustomAppAtomicDirectoryV010 -Path $TransactionRoot -ExpectedParent $parent -ExpectedName ([IO.Path]::GetFileName($TransactionRoot))
    }
    Assert-AtomicOriginalRestoredV010 $Fixture 'journal-aware cleanup'
}
function Assert-JAZeroAuthorityV010 {param($Value,[string]$Label);foreach($f in @('result_is_authority','spicetify_apply_authorized','additional_mutation_authorized','production_execution_authorized','production_mutation_authorized')){if($Value.PSObject.Properties[$f]){Assert-False ([bool]$Value.$f) "$Label authority escaped $f"}}}

$count=0
$valid=New-AtomicFixtureV010 'journal-aware-valid' -Nonce '31313131313131313131313131313131'
Assert-False (Test-CustomAppProductionCrashJournalWithinV010 -Root ([string]$valid.q.x.store.root) -Path ([string]$valid.q.x.live)) 'fixture unexpectedly collapsed live under consumption-store root'
Assert-True (Test-CustomAppProductionCrashJournalWithinV010 -Root (Get-JATrustRootV010) -Path ([string]$valid.q.x.live)) 'profile-like trust root does not contain live fixture'
$r=Invoke-JAFixtureV010 -Fixture $valid -Nonce 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' -JournalLabel 'valid'
try{
    Assert-True ([bool]$r.ok) ('journal-aware valid denied: '+[string]$r.reason);Assert-True ([bool]$r.result.journal_bound_before_live_side_effect) 'valid journal barrier flag false';Assert-True ([bool]$r.result.live_code_swap_performed) 'valid swap flag false';Assert-JAZeroAuthorityV010 $r.result 'valid'
    Assert-True (([string]$r.result.result_fingerprint) -cmatch '^[0-9a-f]{64}$') 'valid result fingerprint invalid'
    $jr=Get-JAReadV010 $valid 'valid';Assert-True ([string]$jr.entry.phase -ceq 'candidate-live') 'valid journal did not reach candidate-live';Assert-True ([string]$jr.transaction_id -ceq [string]$r.result.transaction_id) 'valid transaction id drift'
    $post=Get-CustomAppLocalRuntimeBaseline -Name $valid.q.x.f.name -AppPath $valid.q.x.live;Assert-True ([string]$post.tree_sha256 -ceq [string]$valid.prepared.result.stage_tree_sha256) 'valid live not candidate'
    $count++
}finally{Restore-JAFixtureV010 $valid (Get-JATransactionRootV010 $r)}

$pre=New-AtomicFixtureV010 'journal-aware-pre-first' -Nonce '32323232323232323232323232323232'
$r=Invoke-JAFixtureV010 -Fixture $pre -Nonce 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' -JournalLabel 'pre-first' -Fault 'after-atomic-starting-before-live-move'
try{
    Assert-False ([bool]$r.ok) 'pre-first crash unexpectedly succeeded';Assert-True ([string]$r.journal_phase -ceq 'atomic-mutation-starting') 'pre-first phase drift';Assert-False ([bool]$r.live_move_started) 'pre-first incorrectly marked live move'
    $ia=Get-JAInspectionArgsV010 $pre 'pre-first';$i=Resolve-CustomAppProductionJournalAwareAtomicStartingInspectionV010 @ia
    Assert-True ([bool]$i.ok) ('pre-first inspection denied: '+[string]$i.reason);Assert-True ([string]$i.receipt.state -ceq 'pre-first-rename-exact') 'pre-first state mismatch';Assert-True ([string]$i.receipt.repair_phase -ceq 'rollback-required') 'pre-first repair phase mismatch'
    $repair=Invoke-CustomAppProductionJournalAwareAtomicStartingRepairV010 @ia;Assert-True ([bool]$repair.ok) ('pre-first repair denied: '+[string]$repair.reason);Assert-True ([string]$repair.phase -ceq 'rollback-required') 'pre-first repair journal phase mismatch'
    $count++
}finally{Restore-JAFixtureV010 $pre (Get-JATransactionRootV010 $r)}

$postFirst=New-AtomicFixtureV010 'journal-aware-post-first' -Nonce '33333333333333333333333333333333'
$r=Invoke-JAFixtureV010 -Fixture $postFirst -Nonce 'cccccccccccccccccccccccccccccccc' -JournalLabel 'post-first' -Fault 'after-live-move-before-journal'
try{
    Assert-False ([bool]$r.ok) 'post-first crash unexpectedly succeeded';Assert-True ([bool]$r.live_move_started) 'post-first did not record live move';Assert-True ([string]$r.journal_phase -ceq 'atomic-mutation-starting') 'post-first durable phase should remain atomic-starting'
    $ia=Get-JAInspectionArgsV010 $postFirst 'post-first';$i=Resolve-CustomAppProductionJournalAwareAtomicStartingInspectionV010 @ia
    Assert-True ([bool]$i.ok) ('post-first inspection denied: '+[string]$i.reason);Assert-True ([string]$i.receipt.state -ceq 'first-rename-complete-unjournaled') 'post-first state mismatch';Assert-True ([string]$i.receipt.repair_phase -ceq 'live-moved-to-old') 'post-first repair phase mismatch'
    $repair=Invoke-CustomAppProductionJournalAwareAtomicStartingRepairV010 @ia;Assert-True ([bool]$repair.ok) ('post-first repair denied: '+[string]$repair.reason);Assert-True ([string]$repair.phase -ceq 'live-moved-to-old') 'post-first repair journal phase mismatch'
    $class=Resolve-CustomAppProductionCrashRecoveryClassificationV010 -StoreRead (Get-JAReadV010 $postFirst 'post-first') -ExpectedTransactionId ([string]$repair.transaction_id);Assert-True ([string]$class.classification -ceq 'exact-app-and-persistence-recovery-required') 'post-first normalized classification drift'
    $count++
}finally{Restore-JAFixtureV010 $postFirst (Get-JATransactionRootV010 $r)}

$afterBarrier=New-AtomicFixtureV010 'journal-aware-after-barrier' -Nonce '34343434343434343434343434343434'
$r=Invoke-JAFixtureV010 -Fixture $afterBarrier -Nonce 'dddddddddddddddddddddddddddddddd' -JournalLabel 'after-barrier' -Fault 'after-live-moved-before-candidate'
try{
    Assert-False ([bool]$r.ok) 'after live-moved barrier crash unexpectedly succeeded';$jr=Get-JAReadV010 $afterBarrier 'after-barrier';Assert-True ([string]$jr.entry.phase -ceq 'live-moved-to-old') 'after-barrier journal phase drift'
    $class=Resolve-CustomAppProductionCrashRecoveryClassificationV010 -StoreRead $jr -ExpectedTransactionId ([string]$jr.transaction_id);Assert-True ([string]$class.classification -ceq 'exact-app-and-persistence-recovery-required') 'after-barrier recovery classification drift';$count++
}finally{Restore-JAFixtureV010 $afterBarrier (Get-JATransactionRootV010 $r)}

$afterCandidate=New-AtomicFixtureV010 'journal-aware-after-candidate' -Nonce '35353535353535353535353535353535'
$r=Invoke-JAFixtureV010 -Fixture $afterCandidate -Nonce 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee' -JournalLabel 'after-candidate' -Fault 'after-candidate-move-before-journal'
try{
    Assert-False ([bool]$r.ok) 'after candidate move crash unexpectedly succeeded';$jr=Get-JAReadV010 $afterCandidate 'after-candidate';Assert-True ([string]$jr.entry.phase -ceq 'live-moved-to-old') 'after-candidate durable phase drift'
    $class=Resolve-CustomAppProductionCrashRecoveryClassificationV010 -StoreRead $jr -ExpectedTransactionId ([string]$jr.transaction_id);Assert-True ([string]$class.classification -ceq 'exact-app-and-persistence-recovery-required') 'after-candidate recovery classification drift';$count++
}finally{Restore-JAFixtureV010 $afterCandidate (Get-JATransactionRootV010 $r)}

$drift=New-AtomicFixtureV010 'journal-aware-drift' -Nonce '36363636363636363636363636363636'
$r=Invoke-JAFixtureV010 -Fixture $drift -Nonce 'ffffffffffffffffffffffffffffffff' -JournalLabel 'drift' -Fault 'after-atomic-starting-before-live-move'
try{
    $txn=Get-JATransactionRootV010 $r;[IO.File]::AppendAllText((Join-Path $txn 'candidate\index.js'),"// drift`n",[Text.UTF8Encoding]::new($false))
    $ia=Get-JAInspectionArgsV010 $drift 'drift';$i=Resolve-CustomAppProductionJournalAwareAtomicStartingInspectionV010 @ia;Assert-False ([bool]$i.ok) 'candidate drift accepted by atomic-starting inspection';Assert-True ([string]$i.reason -ceq 'journal-aware-atomic-inspection-candidate-drift') 'candidate drift reason mismatch';$count++
}finally{Restore-JAFixtureV010 $drift (Get-JATransactionRootV010 $r)}

$extra=New-AtomicFixtureV010 'journal-aware-extra' -Nonce '37373737373737373737373737373737'
$r=Invoke-JAFixtureV010 -Fixture $extra -Nonce '12121212121212121212121212121212' -JournalLabel 'extra' -Fault 'after-atomic-starting-before-live-move'
try{
    $txn=Get-JATransactionRootV010 $r;[IO.Directory]::CreateDirectory((Join-Path $txn 'unexpected'))|Out-Null
    $ia=Get-JAInspectionArgsV010 $extra 'extra';$i=Resolve-CustomAppProductionJournalAwareAtomicStartingInspectionV010 @ia;Assert-False ([bool]$i.ok) 'unexpected transaction child accepted';Assert-True ([string]$i.reason -ceq 'journal-aware-atomic-inspection-transaction-contents-invalid') 'unexpected child reason mismatch';$count++
}finally{
    $txn=Get-JATransactionRootV010 $r;$unexpected=if([string]::IsNullOrWhiteSpace($txn)){$null}else{Join-Path $txn 'unexpected'};if(-not [string]::IsNullOrWhiteSpace($unexpected) -and (Test-Path -LiteralPath $unexpected)){[IO.Directory]::Delete($unexpected,$true)}
    Restore-JAFixtureV010 $extra $txn
}

if($count -ne 7){throw "journal-aware atomic matrix count mismatch $count"}
Write-Output "CUSTOM_APP_PRODUCTION_JOURNAL_AWARE_ATOMIC_MATRIX_PASS cases=$count"
