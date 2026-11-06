param(
    [switch]$RestartProbe,
    [string]$FixtureRoot,
    [string]$OfficialExecutable
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
    throw 'SPICETIFY_SEALED_PIN_TEST_HOSTED_WINDOWS_ONLY'
}
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
foreach($file in @(
    'validation/custom-app-user-transaction-store-bundle/user-transaction-store.ps1',
    'validation/custom-app-journal-restart-locator/user-journal-locator.ps1',
    'validation/custom-app-missing-live-recovery/missing-live-recovery.ps1',
    'validation/custom-app-normal-entrypoint-transaction-integration/normal-update-engine-fence.ps1',
    'validation/custom-app-legacy-journal-settlement-barrier/legacy-settlement-barrier.ps1',
    'validation/custom-app-cooperative-cross-engine-lock/cross-engine-transaction-lock.ps1',
    'validation/custom-app-production-crash-recovery-journal-v0.1.0/custom-app-production-crash-recovery-journal.ps1',
    'validation/custom-app-production-recovery-plan-contract-v0.1.0/custom-app-production-recovery-plan.ps1',
    'validation/custom-app-durable-recovery-inventory/durable-recovery-inventory.ps1',
    'validation/custom-app-startup-recovery-source/startup-recovery-source.ps1',
    'validation/custom-app-spicetify-passive-provenance/spicetify-passive-provenance.ps1',
    'validation/custom-app-spicetify-sealed-enrollment/spicetify-sealed-enrollment.ps1'
)){. (Join-Path $repo $file)}
function Assert-Denied([scriptblock]$Command,[string]$Marker){
    $blocked=$false
    try{& $Command|Out-Null}catch{$blocked=$true}
    if(-not $blocked){throw ('SPICETIFY_SEALED_PIN_FAIL_OPEN_'+$Marker)}
}
$ciBase=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
if($RestartProbe){
    if([string]::IsNullOrWhiteSpace($FixtureRoot) -or
       -not [IO.Path]::GetFullPath($FixtureRoot).StartsWith(($ciBase+'\'),
            [StringComparison]::OrdinalIgnoreCase)){
        throw 'SPICETIFY_SEALED_PIN_RESTART_ROOT_INVALID'
    }
    $store=Join-Path $FixtureRoot 'Store'
    $local=Join-Path $FixtureRoot 'Local'
    $roaming=Join-Path $FixtureRoot 'Roaming'
    $check=Get-CustomAppSpicetifySealedPinReadinessV016 -HostedCiRoot $store -HostedCiLocalAppDataRoot $local -HostedCiAppDataRoot $roaming
    if(-not[bool]$check.ok -or
       [int]$check.inspected_count -ne 1 -or
       [int]$check.active_count -ne 1 -or
       [bool]$check.production_execution_authorized -or
       [bool]$check.production_mutation_authorized -or
       -not[bool]$check.items[0].pin_found -or
       -not[bool]$check.items[0].unchanged -or
       -not[bool]$check.items[0].known_official_executable){
        throw 'SPICETIFY_SEALED_PIN_INDEPENDENT_RESTART_VALIDATION_FAILED'
    }
    Write-Host 'SPICETIFY_SEALED_PIN_FRESH_PROCESS_DPAPI_RESTART_PASS'
    return
}
$official=[IO.Path]::GetFullPath($OfficialExecutable)
if(-not $official.StartsWith(($ciBase+'\'),[StringComparison]::OrdinalIgnoreCase) -or
   -not[IO.File]::Exists($official) -or
   (Get-FileHash -LiteralPath $official -Algorithm SHA256).Hash.ToLowerInvariant() -cne
       '3563f26acd7527adc97e6c19272fa1b48ce976a913625d9804ac57d3c54fb4db'){
    throw 'SPICETIFY_SEALED_PIN_OFFICIAL_EXECUTABLE_NOT_SHA_PINNED'
}
$root=Join-Path $env:RUNNER_TEMP ('sealed-pin-fixture-'+[guid]::NewGuid().ToString('N'))
$store=Join-Path $root 'Store'
$local=Join-Path $root 'Local'
$roaming=Join-Path $root 'Roaming'
$exeDir=Join-Path $local 'spicetify'
$cfgDir=Join-Path $roaming 'spicetify'
$live=Join-Path $root 'Apps\tagify'
$txn=Join-Path $root 'Txn'
$stage=Join-Path $root 'Stage'
$appBackup=Join-Path $root 'AppBackup'
$persistBackup=Join-Path $root 'PersistBackup'
$journalStore=Join-Path $root 'Journal'
foreach($dir in @($root,$store,$local,$roaming,$exeDir,$cfgDir,$live,$txn,$stage,$appBackup,$persistBackup,$journalStore)){
    [void][IO.Directory]::CreateDirectory($dir)
}
$exe=Join-Path $exeDir 'spicetify.exe'
$config=Join-Path $cfgDir 'config-xpui.ini'
$originalExe=[IO.File]::ReadAllBytes($official)
[IO.File]::WriteAllBytes($exe,$originalExe)
$configData=[Text.Encoding]::UTF8.GetBytes("[AdditionalOptions]"+[Environment]::NewLine+"custom_apps = tagify"+[Environment]::NewLine)
[IO.File]::WriteAllBytes($config,$configData)
$initialState=Open-CustomAppUserTxnStoreV010 -Name 'tagify' -LivePath $live -HostedCiRoot $store -Initialize
$initialState.lock_handle.Dispose()
$global=Open-CustomAppCrossEngineTransactionLockV010 -HostedCiRoot $store
$session=$null
try{
    $session=Open-CustomAppUserTxnStoreV010 -Name 'tagify' -LivePath $live -HostedCiRoot $store
    $cid='a'*64;$nonce='b'*32
    $identity=New-CustomAppProductionCrashJournalIdentityV010 -Name tagify -ConsumptionId $cid -SourceIdentity 'owner/repo' -RemoteCommitSha ('c'*40) -StageResultFingerprint ('d'*64) -PreparationFingerprint ('e'*64) -AllowedRoot $root -LivePath $live -TransactionRoot $txn -StageWorkspacePath $stage -AppBackupPath $appBackup -PersistenceBackupPath $persistBackup
    $reserve=Reserve-CustomAppUserTxnIdV010 -Session $session -ConsumptionId $cid -TransactionId ([string]$identity.transaction_id) -Nonce $nonce
    if(-not[bool]$reserve.ok){throw 'SPICETIFY_SEALED_PIN_RESERVATION_FAILED'}
    $pre=Initialize-CustomAppProductionCrashJournalV010 -AllowedRoot $root -StoreDirectory $journalStore -Identity $identity
    if(-not[bool]$pre.ok -or [string]$pre.entry.phase -cne 'prepared'){throw 'SPICETIFY_SEALED_PIN_PREPARED_JOURNAL_FAILED'}
    $loc=Bind-CustomAppUserTxnJournalLocatorV010 -Session $session -AllowedRoot $root -JournalStoreDirectory $journalStore
    if(-not[bool]$loc.ok){throw 'SPICETIFY_SEALED_PIN_DPAPI_LOCATOR_FAILED'}
    $paths=Get-CustomAppUserTxnPathsV010 -Name tagify -LivePath $live -HostedCiRoot $store
    $record=Get-CustomAppSpicetifyPinFileV016 -Session $session
    $pinArgs=@{Session=$session;HeldCrossEngineSession=$global;HostedCiRoot=$store;HostedCiLocalAppDataRoot=$local;HostedCiAppDataRoot=$roaming}
    $before=Read-CustomAppSpicetifySealedPinV016 @pinArgs
    if([bool]$before.ok -or [bool]$before.pin_found -or
       [IO.File]::Exists($record)){throw 'SPICETIFY_SEALED_PIN_MISSING_SEAL_CREATED_BY_READ'}
    [IO.File]::WriteAllBytes($exe,[byte[]](1,2,3,4,5,6,7,8))
    Assert-Denied {Save-CustomAppSpicetifyPreMutationPinV016 @pinArgs} 'FAKE_EXE_ENROLMENT'
    if([IO.File]::Exists($record)){throw 'SPICETIFY_SEALED_PIN_FAKE_EXECUTABLE_CREATED_SEAL'}
    [IO.File]::WriteAllBytes($exe,$originalExe)
    $set=Save-CustomAppSpicetifyPreMutationPinV016 @pinArgs
    if(-not[bool]$set.ok -or -not[bool]$set.read_after_write_verified -or
       [bool]$set.production_execution_authorized){throw 'SPICETIFY_SEALED_PIN_DURABLE_ENROLMENT_FAILED'}
    $saved=[IO.File]::ReadAllBytes($record)
    $savedHash=(Get-FileHash -LiteralPath $record -Algorithm SHA256).Hash
    $pinned=Read-CustomAppSpicetifySealedPinV016 @pinArgs
    if(-not[bool]$pinned.ok -or
       -not[bool]$pinned.known_official_executable -or
       [string]$pinned.transaction_id -cne [string]$identity.transaction_id -or
       [bool]$pinned.production_mutation_authorized){throw 'SPICETIFY_SEALED_PIN_POSTENROLMENT_IDENTITY_MISMATCH'}
    Assert-Denied {Save-CustomAppSpicetifyPreMutationPinV016 @pinArgs} 'DUPLICATE_IMMUTABLE_PIN'
    if((Get-FileHash -LiteralPath $record -Algorithm SHA256).Hash -cne $savedHash){
        throw 'SPICETIFY_SEALED_PIN_DUPLICATE_MODIFIED_FIRST_SEAL'
    }
    [IO.File]::AppendAllText($config,';drift')
    Assert-Denied {Read-CustomAppSpicetifySealedPinV016 @pinArgs} 'CONFIG_DRIFT'
    [IO.File]::WriteAllBytes($config,$configData)
    [IO.File]::WriteAllBytes($exe,[byte[]](1,2,3,4))
    Assert-Denied {Read-CustomAppSpicetifySealedPinV016 @pinArgs} 'EXE_DRIFT'
    [IO.File]::WriteAllBytes($exe,$originalExe)
    $bad=New-Object byte[] $saved.Length
    [Array]::Copy($saved,$bad,$saved.Length)
    $bad[$bad.Length-1]=$bad[$bad.Length-1] -bxor 1
    [IO.File]::WriteAllBytes($record,$bad)
    Assert-Denied {Read-CustomAppSpicetifySealedPinV016 @pinArgs} 'SEALED_BYTES_TAMPER'
    [IO.File]::WriteAllBytes($record,$saved)
    $jp=Get-CustomAppProductionCrashJournalPathsV010 -AllowedRoot $root -StoreDirectory $journalStore
    $heldLock=Join-Path $journalStore '.journal.lock'
    $moved=Join-Path $root 'temporarily-moved-journal-lock'
    [IO.File]::Move($heldLock,$moved)
    try{
        Assert-Denied {Read-CustomAppSpicetifySealedPinV016 @pinArgs} 'ABSENT_JOURNAL_LOCK'
        if([IO.File]::Exists($heldLock)){throw 'SPICETIFY_SEALED_PIN_READ_CREATED_JOURNAL_LOCK'}
    }finally{[IO.File]::Move($moved,$heldLock)}
    $later=Append-CustomAppProductionCrashJournalPhaseV010 -AllowedRoot $root -StoreDirectory $journalStore -ExpectedRevision 0 -ExpectedEntrySha256 ([string]$pre.entry.entry_sha256) -Phase 'atomic-mutation-starting'
    if(-not[bool]$later.ok){throw ('SPICETIFY_SEALED_PIN_JOURNAL_PROGRESS_FAIL_'+[string]$later.reason)}
    $progress=Read-CustomAppSpicetifySealedPinV016 @pinArgs
    if(-not[bool]$progress.ok -or [long]$progress.journal_revision -ne 1 -or
       [bool]$progress.production_execution_authorized){
        throw 'SPICETIFY_SEALED_PIN_PREPARED_HISTORY_NOT_BOUND_ACROSS_PROGRESS'
    }
    Assert-Denied {Save-CustomAppSpicetifyPreMutationPinV016 @pinArgs} 'AFTER_FIRST_MUTATION'
    [IO.File]::WriteAllBytes([string]$paths.pending,[byte[]](10,20,30,40))
    $pendingHash=(Get-FileHash -LiteralPath $paths.pending -Algorithm SHA256).Hash
    Write-Host 'SPICETIFY_SEALED_PIN_PRE_MUTATION_ENROLLMENT_AND_NEGATIVE_MATRIX_PASS'
}finally{
    if($null-ne$session){$session.lock_handle.Dispose()}
    $global.lock_handle.Dispose()
}
$child=@(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $PSCommandPath -RestartProbe -FixtureRoot $root 2>&1 | ForEach-Object{[string]$_})
if($LASTEXITCODE -ne 0 -or -not (($child -join [Environment]::NewLine).Contains('SPICETIFY_SEALED_PIN_FRESH_PROCESS_DPAPI_RESTART_PASS'))){
    $child|Select-Object -Last 35|ForEach-Object{Write-Host $_}
    throw 'SPICETIFY_SEALED_PIN_FRESH_PROCESS_FAILED'
}
if((Get-FileHash -LiteralPath $paths.pending -Algorithm SHA256).Hash -cne $pendingHash -or
   -not[IO.File]::Exists($paths.pending) -or
   (Get-FileHash -LiteralPath $record -Algorithm SHA256).Hash -cne $savedHash){
    throw 'SPICETIFY_SEALED_PIN_RESTART_MODIFIED_PENDING_OR_SEAL'
}
Write-Host 'SPICETIFY_SEALED_PIN_INDEPENDENT_RESTART_PENDING_PRESERVED_PASS'
