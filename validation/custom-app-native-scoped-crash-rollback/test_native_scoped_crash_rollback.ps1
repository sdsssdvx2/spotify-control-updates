# Independent host-only restart contract for genuine official Spicetify.
param([Parameter(Mandatory=$true)][ValidateSet('mutate','tamper-denial','recover','replay')][string]$Mode,
      [Parameter(Mandatory=$true)][string]$FixtureRoot,
      [string]$OfficialExecutable)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
   $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
    throw 'SCOPED_LAB_TEST_CI_WINDOWS_ONLY'
}
$runner=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
$root=[IO.Path]::GetFullPath($FixtureRoot).TrimEnd('\','/')
if(-not$root.StartsWith(($runner+'\'),[StringComparison]::OrdinalIgnoreCase) -or
   $root.StartsWith('\\')){throw 'SCOPED_LAB_TEST_FIXTURE_NOT_DISPOSABLE'}
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
foreach($path in @(
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
 'validation/custom-app-spicetify-sealed-enrollment/spicetify-sealed-enrollment.ps1',
 'validation/custom-app-native-scoped-crash-rollback/native-scoped-crash-rollback.ps1'
)){. (Join-Path $repo $path)}
$store=Join-Path $root 'Store'
$local=Join-Path $root 'Local'
$roaming=Join-Path $root 'Roaming'
$live=Join-Path $roaming 'spicetify\CustomApps\alpha'
$exeDir=Join-Path $local 'spicetify'
$fakeSpotify=Join-Path $root 'FakeSpotify'
$xpui=Join-Path $fakeSpotify 'Apps\xpui'
$journal=Join-Path $root 'Journal'
$source=Join-Path $live 'index.js'
$config=Join-Path $roaming 'spicetify\config-xpui.ini'
$backup=Join-Path $roaming 'spicetify\Backup\xpui.spa'
$exe=Join-Path $exeDir 'spicetify.exe'
$prefs=Join-Path $root 'prefs'
$target=Join-Path $xpui 'spicetify-routes-alpha.js'
$targetJson=Join-Path $xpui 'spicetify-routes-alpha.json'
$targetCss=Join-Path $xpui 'spicetify-routes-alpha.css'
$bystander=Join-Path $xpui 'spicetify-routes-beta.js'
$sentinel=Join-Path $xpui 'irrelevant-user-sentinel.dat'
$pendingText='PENDING-SAFETY-MUST-BE-PRESERVED'
$baseTarget='BEFORE_ALPHA_REFRESH_V0'
$baseJson='BEFORE_ALPHA_ROUTE_JSON'
$baseBystander='BEFORE_BETA_MUST_NOT_CHANGE'
$baseSentinel='BEFORE_UNRELATED_USER_ASSET'
$pinArgs=@{HostedCiRoot=$store;HostedCiLocalAppDataRoot=$local;HostedCiAppDataRoot=$roaming}
if($Mode -ceq 'mutate'){
    $official=[IO.Path]::GetFullPath($OfficialExecutable)
    if(-not$official.StartsWith(($runner+'\'),[StringComparison]::OrdinalIgnoreCase) -or
       -not[IO.File]::Exists($official) -or
       (Get-FileHash -LiteralPath $official -Algorithm SHA256).Hash.ToLowerInvariant() -cne
        '3563f26acd7527adc97e6c19272fa1b48ce976a913625d9804ac57d3c54fb4db'){
        throw 'SCOPED_LAB_OFFICIAL_EXECUTABLE_NOT_AUTHENTIC'
    }
    foreach($dir in @($root,$store,$local,$roaming,$live,$exeDir,$xpui,$journal,
        (Split-Path $config -Parent),(Split-Path $backup -Parent),
        (Join-Path $root 'Txn'),(Join-Path $root 'Stage'),
        (Join-Path $root 'AppBackup'),(Join-Path $root 'PersistBackup'))){
        [void][IO.Directory]::CreateDirectory($dir)
    }
    [IO.File]::Copy($official,$exe,$false)
    $ini=('[Setting]'+[Environment]::NewLine+
      'spotify_path = '+$fakeSpotify+[Environment]::NewLine+
      'prefs_path = '+$prefs+[Environment]::NewLine+
      'check_spicetify_update = false'+[Environment]::NewLine+
      'current_theme = '+[Environment]::NewLine+
      '[Backup]'+[Environment]::NewLine+
      'version = 1.2.3'+[Environment]::NewLine+
      'with = 2.46.4'+[Environment]::NewLine+
      '[AdditionalOptions]'+[Environment]::NewLine+
      'custom_apps = alpha|beta'+[Environment]::NewLine)
    [IO.File]::WriteAllText($config,$ini,([Text.UTF8Encoding]::new($false)))
    [IO.File]::WriteAllText($source,'console.log("NEW_SCOPED_ALPHA_V17");',([Text.UTF8Encoding]::new($false)))
    [IO.File]::WriteAllText($prefs,'app.last-launched-version = 1.2.3'+[Environment]::NewLine,([Text.UTF8Encoding]::new($false)))
    [IO.File]::WriteAllBytes($backup,[byte[]](0x50,0x4b))
    [IO.File]::WriteAllText($target,$baseTarget)
    [IO.File]::WriteAllText($targetJson,$baseJson)
    [IO.File]::WriteAllText($bystander,$baseBystander)
    [IO.File]::WriteAllText($sentinel,$baseSentinel)
    $global=Open-CustomAppCrossEngineTransactionLockV010 -HostedCiRoot $store
    $session=$null
    try{
        $initial=Open-CustomAppUserTxnStoreV010 -Name alpha -LivePath $live -HostedCiRoot $store -Initialize
        $initial.lock_handle.Dispose()
        $session=Open-CustomAppUserTxnStoreV010 -Name alpha -LivePath $live -HostedCiRoot $store
        $cid=('a'*64)
        $identityArgs=@{
            Name='alpha';ConsumptionId=$cid;SourceIdentity='owner/repo'
            RemoteCommitSha=('c'*40);StageResultFingerprint=('d'*64)
            PreparationFingerprint=('e'*64)
            AllowedRoot=$root;LivePath=$live
            TransactionRoot=(Join-Path $root 'Txn')
            StageWorkspacePath=(Join-Path $root 'Stage')
            AppBackupPath=(Join-Path $root 'AppBackup')
            PersistenceBackupPath=(Join-Path $root 'PersistBackup')
        }
        $identity=New-CustomAppProductionCrashJournalIdentityV010 @identityArgs
        $reserve=Reserve-CustomAppUserTxnIdV010 -Session $session -ConsumptionId $cid -TransactionId ([string]$identity.transaction_id) -Nonce ('b'*32)
        if(-not[bool]$reserve.ok){throw 'SCOPED_LAB_RESERVATION_FAILED'}
        $prepared=Initialize-CustomAppProductionCrashJournalV010 -AllowedRoot $root -StoreDirectory $journal -Identity $identity
        if(-not[bool]$prepared.ok -or [string]$prepared.entry.phase -cne 'prepared'){
            throw 'SCOPED_LAB_PREPARED_JOURNAL_FAILED'
        }
        $locator=Bind-CustomAppUserTxnJournalLocatorV010 -Session $session -AllowedRoot $root -JournalStoreDirectory $journal
        if(-not[bool]$locator.ok){throw 'SCOPED_LAB_DPAPI_LOCATOR_FAILED'}
        $pins=Save-CustomAppSpicetifyPreMutationPinV016 -Session $session -HeldCrossEngineSession $global @pinArgs
        if(-not[bool]$pins.ok){throw 'SCOPED_LAB_EXACT_OFFICIAL_PIN_NOT_DURABLE'}
        $saved=Save-CustomAppScopedLabSnapshotV017 -Session $session -HeldCrossEngineSession $global @pinArgs
        if(-not[bool]$saved.ok -or [bool]$saved.intent_written){
            throw 'SCOPED_LAB_SNAPSHOT_DURABILITY_BEFORE_INTENT_FAILED'
        }
        Write-CustomAppUserTxnBytesV010 -Path ([string]$session.paths.pending) -Bytes ([Text.Encoding]::ASCII.GetBytes($pendingText))
        $result=Invoke-CustomAppScopedLabNativeV017 -Session $session -HeldCrossEngineSession $global @pinArgs
        if(-not[bool]$result.ok -or [bool]$result.production_execution_authorized -or
           -not[bool]$result.must_recover_or_finalize -or
           -not[IO.File]::ReadAllText($target).Contains('NEW_SCOPED_ALPHA_V17') -or
           [IO.File]::ReadAllText($bystander) -cne $baseBystander -or
           [IO.File]::ReadAllText($sentinel) -cne $baseSentinel){
            throw 'SCOPED_LAB_NATIVE_OFFICIAL_EXECUTION_POSTSTATE_FAIL'
        }
        Write-Host 'NATIVE_SCOPED_LAB_REAL_OFFICIAL_APPLIED_AND_INTENT_DURABLE_PASS'
        [Environment]::Exit(71)
    }finally{
        if($null-ne$session){$session.lock_handle.Dispose()}
        $global.lock_handle.Dispose()
    }
}
if(-not[IO.Directory]::Exists($root)){throw 'SCOPED_LAB_RECOVERY_FIXTURE_MISSING'}
if($Mode -ceq 'tamper-denial'){
    if(-not[IO.File]::ReadAllText($target).Contains('NEW_SCOPED_ALPHA_V17')){
        throw 'SCOPED_LAB_APPLIED_STATE_MISSING_BEFORE_NEGATIVE_TEST'
    }
    $original=[IO.File]::ReadAllBytes($sentinel)
    [IO.File]::AppendAllText($sentinel,'OUTSIDER_MODIFIED')
    $denied=$false
    try{[void](Invoke-CustomAppScopedLabIndependentRecoveryV017 @pinArgs)}catch{$denied=$true}
    finally{[IO.File]::WriteAllBytes($sentinel,$original)}
    if(-not$denied -or -not[IO.File]::ReadAllText($target).Contains('NEW_SCOPED_ALPHA_V17')){
        throw 'SCOPED_LAB_OUTSIDE_DRIFT_WAS_NOT_FAIL_CLOSED'
    }
    $stateDir=Join-Path (Join-Path $store 'SpotifyControlUpdates-CustomApp-State') (
      Get-CustomAppUserTxnSha256V010 ([IO.Path]::GetFullPath($live).TrimEnd('\','/').ToLowerInvariant()))
    $intent=Join-Path $stateDir ('native-scoped-'+('a'*64)+'.intent')
    $saved=[IO.File]::ReadAllBytes($intent)
    $bad=New-Object byte[] ($saved.Length)
    [Array]::Copy($saved,$bad,$saved.Length)
    $bad[$bad.Length-1]=$bad[$bad.Length-1] -bxor 1
    [IO.File]::WriteAllBytes($intent,$bad)
    $denied=$false
    try{[void](Invoke-CustomAppScopedLabIndependentRecoveryV017 @pinArgs)}catch{$denied=$true}
    finally{[IO.File]::WriteAllBytes($intent,$saved)}
    if(-not$denied -or -not[IO.File]::ReadAllText($target).Contains('NEW_SCOPED_ALPHA_V17')){
        throw 'SCOPED_LAB_INTENT_TAMPER_NOT_FAIL_CLOSED'
    }
    Write-Host 'NATIVE_SCOPED_LAB_FRESH_PROCESS_DENIED_OUTSIDER_AND_INTENT_TAMPER_PASS'
    exit 0
}
$result=Invoke-CustomAppScopedLabIndependentRecoveryV017 @pinArgs
if(-not[bool]$result.ok -or [bool]$result.production_execution_authorized -or
   [bool]$result.production_mutation_authorized -or
   [IO.File]::ReadAllText($target) -cne $baseTarget -or
   [IO.File]::ReadAllText($targetJson) -cne $baseJson -or
   [IO.File]::Exists($targetCss) -or
   [IO.File]::ReadAllText($bystander) -cne $baseBystander -or
   [IO.File]::ReadAllText($sentinel) -cne $baseSentinel -or
   -not[IO.File]::Exists($config) -or
   -not[IO.File]::ReadAllText($config).Contains('custom_apps = alpha|beta')){
    throw 'NATIVE_SCOPED_LAB_FRESH_RESTART_EXACT_RESTORE_FAILED'
}
$stateDir=Join-Path (Join-Path $store 'SpotifyControlUpdates-CustomApp-State') (
  Get-CustomAppUserTxnSha256V010 ([IO.Path]::GetFullPath($live).TrimEnd('\','/').ToLowerInvariant()))
$pending=Join-Path $stateDir 'state.pending'
if(-not[IO.File]::Exists($pending) -or
   [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($pending)) -cne $pendingText){
    throw 'NATIVE_SCOPED_LAB_CANONICAL_PENDING_NOT_PRESERVED'
}
if($Mode -ceq 'recover'){
    if(-not[bool]$result.restored -or [string]$result.status -cne 'restored-exact-before-image'){
        throw 'NATIVE_SCOPED_LAB_FIRST_RESTART_DID_NOT_RESTORE'
    }
    Write-Host 'NATIVE_SCOPED_LAB_FRESH_PROCESS_CRASH_RECOVERY_EXACT_BEFORE_IMAGE_PASS'
}else{
    if([bool]$result.restored -or -not[bool]$result.replay_idempotent -or
       [string]$result.status -cne 'already-recovered-verified'){
        throw 'NATIVE_SCOPED_LAB_TERMINAL_REPLAY_NOT_IDEMPOTENT'
    }
    Write-Host 'NATIVE_SCOPED_LAB_INDEPENDENT_RESTART_TERMINAL_REPLAY_IDEMPOTENT_PASS'
}
