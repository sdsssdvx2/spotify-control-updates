param()
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
    throw 'PROTECTED_RESTORE_TEST_HOSTED_WINDOWS_ONLY'
}
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
foreach($m in @(
    'validation/custom-app-user-transaction-store-bundle/user-transaction-store.ps1',
    'validation/custom-app-journal-restart-locator/user-journal-locator.ps1',
    'validation/custom-app-missing-live-recovery/missing-live-recovery.ps1',
    'validation/custom-app-normal-entrypoint-transaction-integration/normal-update-engine-fence.ps1',
    'validation/custom-app-legacy-journal-settlement-barrier/legacy-settlement-barrier.ps1',
    'validation/custom-app-cooperative-cross-engine-lock/cross-engine-transaction-lock.ps1',
    'validation/custom-app-production-crash-recovery-journal-v0.1.0/custom-app-production-crash-recovery-journal.ps1',
    'validation/custom-app-production-recovery-evidence-envelope-v0.1.0/custom-app-production-recovery-evidence.ps1',
    'validation/custom-app-durable-recovery-inventory/durable-recovery-inventory.ps1',
    'validation/custom-app-startup-recovery-source/startup-recovery-source.ps1',
    'validation/custom-app-protected-restore-readiness/protected-restore-readiness.ps1'
)){
    $p=Join-Path $repo $m
    if(-not[IO.File]::Exists($p)){throw ('PROTECTED_RESTORE_MISSING_QUALIFIED_SOURCE_'+$m)}
    . $p
}
function Assert-Blocked([scriptblock]$Call,[string]$Reason){
    $blocked=$false
    try{& $Call|Out-Null}catch{$blocked=$true}
    if(-not $blocked){throw ('PROTECTED_RESTORE_TEST_FAIL_OPEN_'+$Reason)}
}
$root=Join-Path $env:RUNNER_TEMP ('protected-readiness-'+[Guid]::NewGuid().ToString('N'))
$store=Join-Path $root 'user-ledger'
$local=Join-Path $root 'local'
$roaming=Join-Path $root 'roaming'
$live=Join-Path $root 'live-tagify'
$journal=Join-Path $root 'journal'
$history=Join-Path $journal 'history'
foreach($path in @($store,$local,$roaming,$live,$journal,$history)){
    [void][IO.Directory]::CreateDirectory($path)
}
$readinessRoots=@{HostedCiRoot=$store;HostedCiLocalAppDataRoot=$local;HostedCiAppDataRoot=$roaming}
$empty=Get-CustomAppSealedRestoreReadinessV014 @readinessRoots
if(-not[bool]$empty.ok -or $empty.inspected_count -ne 0 -or
   [bool]$empty.production_mutation_authorized -or
   [IO.Directory]::Exists((Join-Path $store 'SpotifyControlUpdates-CustomApp-State'))){
    throw 'PROTECTED_RESTORE_EMPTY_ENROLMENT_DID_NOT_REMAIN_EMPTY'
}
$session=Open-CustomAppUserTxnStoreV010 -Name tagify -LivePath $live -HostedCiRoot $store -Initialize
try{
    if($null-ne$session.state.active){throw 'PROTECTED_RESTORE_BOOTSTRAP_SHOULD_BE_IDLE'}
}finally{$session.lock_handle.Dispose()}
$paths=Get-CustomAppUserTxnPathsV010 -Name tagify -LivePath $live -HostedCiRoot $store
[IO.File]::WriteAllBytes([string]$paths.pending,[byte[]](1,2,4,8,16))
$sealedHash=(Get-FileHash -LiteralPath $paths.state -Algorithm SHA256).Hash
$pendingHash=(Get-FileHash -LiteralPath $paths.pending -Algorithm SHA256).Hash
$owned=Open-CustomAppCrossEngineTransactionLockV010 -HostedCiRoot $store
try{
    $idle=Get-CustomAppSealedRestoreReadinessV014 @readinessRoots -HeldCrossEngineSession $owned
    if(-not[bool]$idle.ok -or $idle.inspected_count -ne 1 -or
       $idle.active_count -ne 0 -or $idle.items.Count -ne 1 -or
       [bool]$idle.items[0].eligible -or $null-ne$idle.items[0].receipt -or
       [bool]$idle.production_execution_authorized -or
       [bool]$idle.production_mutation_authorized){
        throw 'PROTECTED_RESTORE_IDLE_STATUS_INVALID'
    }
    Assert-Blocked {
        Get-CustomAppSealedRestoreReadinessV014 -HostedCiRoot (Join-Path $root 'other') -HostedCiLocalAppDataRoot $local -HostedCiAppDataRoot $roaming -HeldCrossEngineSession $owned
    } 'global_lock_wrong_root'
    [void](Assert-CustomAppCrossEngineTransactionLockHeldV010 -Session $owned)
}finally{$owned.lock_handle.Dispose()}
Assert-Blocked {
    Get-CustomAppSealedRestoreReadinessV014 -HostedCiLocalAppDataRoot $local -HostedCiAppDataRoot $roaming
} 'hosted_profile_override_without_hosted_root'
if((Get-FileHash -LiteralPath $paths.state -Algorithm SHA256).Hash -cne $sealedHash -or
   (Get-FileHash -LiteralPath $paths.pending -Algorithm SHA256).Hash -cne $pendingHash){
    throw 'PROTECTED_RESTORE_IDLE_READ_MUTATED_DPAPI_OR_PENDING'
}
$missing=Join-Path $root 'live-moved-out'
[IO.Directory]::Move($live,$missing)
$missingIdle=Get-CustomAppSealedRestoreReadinessV014 @readinessRoots
if(-not[bool]$missingIdle.ok -or $missingIdle.active_count -ne 0 -or
   [IO.Directory]::Exists($live)){
    throw 'PROTECTED_RESTORE_IDLE_MISSING_LIVE_RECREATED_FOLDER'
}
$lockPath=Join-Path $journal '.journal.lock'
Assert-Blocked {
    $raw=Read-CustomAppDurableRecoveryJournalReadOnlyV012 -AllowedRoot $root -StoreDirectory $journal
} 'prior_reader_missing_lock'
$noEvidence=Read-CustomAppProtectedEvidenceReadOnlyV014 -AllowedRoot $root -StoreDirectory $journal -ExpectedTransactionId ('a'*64)
if([bool]$noEvidence.ok -or [bool]$noEvidence.production_mutation_authorized -or
   [IO.File]::Exists($lockPath)){
    throw 'PROTECTED_RESTORE_EVIDENCE_READER_CREATED_MISSING_LOCK'
}
[IO.File]::WriteAllBytes($lockPath,[byte[]](2,4,8))
$beforeLockHash=(Get-FileHash -LiteralPath $lockPath -Algorithm SHA256).Hash
$exclusive=[IO.File]::Open($lockPath,[IO.FileMode]::Open,
    [IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try{
    $busy=Read-CustomAppProtectedEvidenceReadOnlyV014 -AllowedRoot $root -StoreDirectory $journal -ExpectedTransactionId ('a'*64)
    if([bool]$busy.ok -or [bool]$busy.execution_authorized){
        throw 'PROTECTED_RESTORE_EVIDENCE_READER_IGNORED_LOCK_CONTENTION'
    }
}finally{$exclusive.Dispose()}
$uninitialized=Read-CustomAppProtectedEvidenceReadOnlyV014 -AllowedRoot $root -StoreDirectory $journal -ExpectedTransactionId ('a'*64)
if([bool]$uninitialized.ok -or
   (Get-FileHash -LiteralPath $lockPath -Algorithm SHA256).Hash -cne $beforeLockHash){
    throw 'PROTECTED_RESTORE_EVIDENCE_READER_MUTATED_UNINITIALIZED_JOURNAL'
}
[IO.File]::WriteAllBytes([string]$paths.state,[byte[]](1,2,3,4))
Assert-Blocked {Get-CustomAppSealedRestoreReadinessV014 @readinessRoots} 'corrupted_DPAPI_state'
if((Get-FileHash -LiteralPath $paths.pending -Algorithm SHA256).Hash -cne $pendingHash){
    throw 'PROTECTED_RESTORE_READ_DELETED_INCOMPLETE_PENDING'
}
Write-Host 'PROTECTED_RESTORE_NO_CREATE_UNIT_PASS empty=true idle=true sealed_dpapi=true pending_unchanged=true missing_live=true absent_journal_lock_not_created=true journal_lock_contention=true invalid_journal_read_only=true corrupted_dpapi_denied=true global_lock_owner=true'
