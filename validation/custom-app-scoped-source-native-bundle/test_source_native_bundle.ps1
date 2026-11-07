# Independent host-only restart contract for genuine official Spicetify.
param([Parameter(Mandatory=$true)][ValidateSet('bundle-mutate','bundle-tamper','bundle-early-crash','bundle-preintent-tamper','bundle-recover-interrupted','bundle-recover','bundle-replay')][string]$Mode,
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
 'validation/custom-app-native-scoped-crash-rollback/native-scoped-crash-rollback.ps1',
 'validation/custom-app-scoped-source-native-bundle/source-native-bundle.ps1'
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
if($Mode -in @('bundle-mutate','bundle-early-crash')){
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
    [IO.File]::WriteAllText($source,'console.log("ORIGINAL_BUNDLE_ALPHA_V0");',([Text.UTF8Encoding]::new($false)))
    $candidate=Join-Path $root 'Stage\candidate-index.js'
    [IO.File]::WriteAllText($candidate,'console.log("NEW_SCOPED_ALPHA_V17");',([Text.UTF8Encoding]::new($false)))
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
        $bundle=Save-CustomAppScopedBundleV020 -Session $session -HeldCrossEngineSession $global -CandidateIndexPath $candidate @pinArgs
        if(-not[bool]$bundle.ok -or [bool]$bundle.signed_source_provenance_verified){
            throw 'BUNDLE_SYNTHETIC_UNSIGNED_STAGE_NOT_RECORDED'
        }
        # The previous hosted CI failure exposed a Win32 working-directory
        # length violation only AFTER the CAS/source swap. Reject the known
        # unstartable path class while the journal is still prepared.
        $overlong=Join-Path $runner ('x'*245)
        $pathDenied=$false
        try{[void](Assert-CustomAppScopedBundleNativePathBudgetV020 -WorkingDirectory $overlong)}
        catch{$pathDenied=([string]$_.Exception.Message -match 'pre-cas-working-directory-too-long')}
        if(-not$pathDenied){throw 'BUNDLE_PRE_CAS_LONG_CURRENT_DIRECTORY_NOT_DENIED'}
        $shortWorking=Assert-CustomAppScopedBundleNativePathBudgetV020 -WorkingDirectory ([string]$saved.context.scope_root)
        if($shortWorking.Length -ge 248){throw 'BUNDLE_NORMAL_CLONE_UNSTARTABLE_PATH'}
        Write-Host 'NATIVE_BUNDLE_V020_WINDOWS_PATH_BUDGET_PRE_CAS_NEGATIVE_AND_POSITIVE_PASS'
        # Corrupt ONLY the disposable CLI config. Native preflight must deny
        # before the append-only journal, intent, source, or XPUI changes;
        # restore the disposable clone and then run the genuine positive case.
        $cloneConfig=Join-Path ([string]$saved.context.scope_root) 'config-xpui.ini'
        $cloneSource=Join-Path ([string]$saved.context.scope_root) 'CustomApps\alpha\index.js'
        $oldCloneConfig=[IO.File]::ReadAllBytes($cloneConfig)
        try{
            $badConfig=[IO.File]::ReadAllText($cloneConfig).Replace(
                'check_spicetify_update = false','check_spicetify_update = true')
            if($badConfig -ceq [IO.File]::ReadAllText($cloneConfig)){
                throw 'BUNDLE_NEGATIVE_PRIVATE_CONFIG_MUTATION_NOT_INJECTED'
            }
            [IO.File]::WriteAllText($cloneConfig,$badConfig)
            $preflightDenied=$false
            try{[void](Invoke-CustomAppScopedBundleNativeV020 -Session $session -HeldCrossEngineSession $global @pinArgs)}
            catch{$preflightDenied=([string]$_.Exception.Message -match 'pre-cas-private-config-drift')}
            $unchanged=Get-CustomAppScopedLabJournalV018 -Session $session -HeldCrossEngineSession $global -Context $saved.context
            if(-not$preflightDenied -or [long]$unchanged.revision -ne 0 -or
               [string]$unchanged.phase -cne 'prepared' -or
               [IO.File]::Exists([string]$saved.context.intent_path) -or
               [IO.File]::Exists([string]$bundle.bundle.paths.intent) -or
               [IO.File]::ReadAllText($source) -cne 'console.log("ORIGINAL_BUNDLE_ALPHA_V0");' -or
               [IO.File]::ReadAllText($target) -cne $baseTarget){
                throw 'BUNDLE_PRE_CAS_DENIAL_MUTATED_LIVE_OR_JOURNAL'
            }
            Write-Host 'NATIVE_BUNDLE_V020_PRIVATE_CONFIG_DRIFT_DENIED_BEFORE_CAS_PASS'
        }finally{
            [IO.File]::WriteAllBytes($cloneConfig,$oldCloneConfig)
            [IO.File]::WriteAllBytes($cloneSource,[IO.File]::ReadAllBytes($source))
        }
        $beforePhase=Get-CustomAppScopedLabJournalV018 -Session $session -HeldCrossEngineSession $global -Context $saved.context
        if([string]$beforePhase.phase -cne 'prepared' -or [long]$beforePhase.revision -ne 0){
            throw 'SCOPED_LAB_SNAPSHOT_DID_NOT_RETAIN_PREPARED_PHASE'
        }
        Write-Host 'NATIVE_SCOPED_V018_SNAPSHOT_BEFORE_CAS_PREPARED_JOURNAL_PASS'
        Write-CustomAppUserTxnBytesV010 -Path ([string]$session.paths.pending) -Bytes ([Text.Encoding]::ASCII.GetBytes($pendingText))
        if($Mode -ceq 'bundle-early-crash'){
            # This exits 75 AFTER durable journal CAS revision 1, BEFORE
            # creation of either V018 or V020 final intent marker.
            [void](Invoke-CustomAppScopedBundleNativeV020 -Session $session -HeldCrossEngineSession $global @pinArgs -HostedCiExitAfterCasBeforeFinalIntent)
            throw 'BUNDLE_V022_EXPECTED_EARLY_EXIT_DID_NOT_HAPPEN'
        }
        $result=Invoke-CustomAppScopedBundleNativeV020 -Session $session -HeldCrossEngineSession $global @pinArgs
        if(-not[bool]$result.ok -or [bool]$result.production_execution_authorized -or
           -not[bool]$result.recovery_required -or
           -not[IO.File]::ReadAllText($source).Contains('NEW_SCOPED_ALPHA_V17') -or
           -not[IO.File]::ReadAllText($target).Contains('NEW_SCOPED_ALPHA_V17') -or
           [IO.File]::ReadAllText($bystander) -cne $baseBystander -or
           [IO.File]::ReadAllText($sentinel) -cne $baseSentinel){
            throw 'SCOPED_LAB_NATIVE_OFFICIAL_EXECUTION_POSTSTATE_FAIL'
        }
        $mutationPhase=Get-CustomAppScopedLabJournalV018 -Session $session -HeldCrossEngineSession $global -Context $saved.context
        $markerText=[Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes([string]$saved.context.intent_path))
        if([string]$mutationPhase.phase -cne 'atomic-mutation-starting' -or
           [long]$mutationPhase.revision -ne 1 -or
           -not $markerText.Contains(('FIRST_JOURNAL_SHA256='+[string]$mutationPhase.entry_sha256))){
            throw 'SCOPED_LAB_NATIVE_STARTED_WHILE_CENTRAL_JOURNAL_PREPARED'
        }
        Write-Host 'NATIVE_SCOPED_V018_OFFICIAL_NATIVE_EFFECT_MATCHED_CAS_REV1_PASS'
        $swapBackup=Join-Path (Split-Path $live -Parent) ('.native-bundle-'+('a'*64)+'.swap.before.bak')
        if(-not[IO.File]::Exists($swapBackup) -or
           [IO.File]::ReadAllText($swapBackup) -cne 'console.log("ORIGINAL_BUNDLE_ALPHA_V0");'){
            throw 'BUNDLE_SOURCE_SWAP_ATOMIC_BACKUP_NOT_IDENTICAL_TO_ORIGINAL'
        }
        Write-Host 'NATIVE_BUNDLE_V020_SOURCE_AND_VENDOR_OUTPUT_APPLIED_JOURNAL_REV1_PASS'
        [Environment]::Exit(73)
    }finally{
        if($null-ne$session){$session.lock_handle.Dispose()}
        $global.lock_handle.Dispose()
    }
}

if(-not[IO.Directory]::Exists($root)){throw 'BUNDLE_RECOVERY_FIXTURE_MISSING'}
if($Mode -ceq 'bundle-preintent-tamper'){
    $stateDir=Join-Path (Join-Path $store 'SpotifyControlUpdates-CustomApp-State') (
      Get-CustomAppUserTxnSha256V010 ([IO.Path]::GetFullPath($live).TrimEnd('\','/').ToLowerInvariant()))
    $stem='native-bundle-'+('a'*64)
    $pre=Join-Path $stateDir ($stem+'.preintent.dpapi')
    $native=Join-Path $stateDir ('native-snapshot-'+('a'*64)+'.intent')
    $bundleIntent=Join-Path $stateDir ($stem+'.intent')
    if(-not[IO.File]::Exists($pre) -or [IO.File]::Exists($bundleIntent)){
        throw 'BUNDLE_V022_EARLY_CAS_PREINTENT_MISSING_OR_FINAL_INTENT_PRESENT'
    }
    if([IO.File]::ReadAllText($source) -cne 'console.log("ORIGINAL_BUNDLE_ALPHA_V0");' -or
       [IO.File]::ReadAllText($target) -cne $baseTarget){
        throw 'BUNDLE_V022_EARLY_CAS_CHANGED_SOURCE_OR_XPUI_PREMATURELY'
    }
    $phase=Read-CustomAppDurableRecoveryJournalReadOnlyV012 -AllowedRoot $root -StoreDirectory $journal
    if(-not[bool]$phase.ok -or [long]$phase.revision -ne 1 -or
       [string]$phase.entry.phase -cne 'atomic-mutation-starting'){
        throw 'BUNDLE_V022_EARLY_CAS_JOURNAL_NOT_DURABLE'
    }
    $bytes=[IO.File]::ReadAllBytes($pre)
    try{
        $tampered=New-Object byte[] $bytes.Length
        [Array]::Copy($bytes,$tampered,$bytes.Length)
        $tampered[12]=$tampered[12] -bxor 1
        [IO.File]::WriteAllBytes($pre,$tampered)
        $denied=$false
        try{[void](Invoke-CustomAppScopedBundleIndependentRecoveryV020 @pinArgs)}catch{$denied=$true}
        if(-not$denied){throw 'BUNDLE_V022_TAMPERED_PREINTENT_NOT_DENIED'}
    }finally{[IO.File]::WriteAllBytes($pre,$bytes)}
    if([IO.File]::Exists($bundleIntent) -or
       [IO.File]::ReadAllText($source) -cne 'console.log("ORIGINAL_BUNDLE_ALPHA_V0");'){
        throw 'BUNDLE_V022_TAMPERED_PREINTENT_CREATED_MARKERS_OR_MUTATED_SOURCE'
    }
    Write-Host 'NATIVE_BUNDLE_V022_DPAPI_PREINTENT_TAMPER_FAIL_CLOSED_PASS'
    exit 0
}
if($Mode -ceq 'bundle-tamper'){
    if(-not[IO.File]::ReadAllText($source).Contains('NEW_SCOPED_ALPHA_V17') -or
       -not[IO.File]::ReadAllText($target).Contains('NEW_SCOPED_ALPHA_V17')){
        throw 'BUNDLE_MUTATION_NOT_PRESENT_BEFORE_NEGATIVE_CASES'
    }
    $stateDir=Join-Path (Join-Path $store 'SpotifyControlUpdates-CustomApp-State') (
      Get-CustomAppUserTxnSha256V010 ([IO.Path]::GetFullPath($live).TrimEnd('\','/').ToLowerInvariant()))
    $stem='native-bundle-'+('a'*64)
    $seal=Join-Path $stateDir ($stem+'.dpapi')
    $intent=Join-Path $stateDir ($stem+'.intent')
    $preintent=Join-Path $stateDir ($stem+'.preintent.dpapi')
    foreach($path in @($seal,$intent,$preintent)){
        if(-not[IO.File]::Exists($path)){throw 'BUNDLE_REQUIRED_DURABLE_RECEIPT_NOT_PRESENT'}
    }
    $originalOutside=[IO.File]::ReadAllBytes($sentinel)
    [IO.File]::AppendAllText($sentinel,'USER_OUTSIDE_CHANGE')
    $denied=$false
    try{[void](Invoke-CustomAppScopedBundleIndependentRecoveryV020 @pinArgs)}catch{$denied=$true}
    finally{[IO.File]::WriteAllBytes($sentinel,$originalOutside)}
    if(-not$denied -or -not[IO.File]::ReadAllText($source).Contains('NEW_SCOPED_ALPHA_V17')){
        throw 'BUNDLE_OUTSIDER_CHANGE_NOT_DENIED'
    }
    $originalSource=[IO.File]::ReadAllBytes($source)
    [IO.File]::WriteAllText($source,'USER_EXTERNAL_MODIFIED')
    $denied=$false
    try{[void](Invoke-CustomAppScopedBundleIndependentRecoveryV020 @pinArgs)}catch{$denied=$true}
    finally{[IO.File]::WriteAllBytes($source,$originalSource)}
    if(-not$denied -or -not[IO.File]::ReadAllText($target).Contains('NEW_SCOPED_ALPHA_V17')){
        throw 'BUNDLE_OUTSIDER_SOURCE_CHANGE_NOT_DENIED'
    }
    foreach($file in @($seal,$intent,$preintent)){
        $original=[IO.File]::ReadAllBytes($file)
        $bad=New-Object byte[] $original.Length
        [Array]::Copy($original,$bad,$original.Length)
        $bad[10]=$bad[10] -bxor 1
        [IO.File]::WriteAllBytes($file,$bad)
        $denied=$false
        try{[void](Invoke-CustomAppScopedBundleIndependentRecoveryV020 @pinArgs)}catch{$denied=$true}
        finally{[IO.File]::WriteAllBytes($file,$original)}
        if(-not$denied -or -not[IO.File]::ReadAllText($source).Contains('NEW_SCOPED_ALPHA_V17')){
            throw 'BUNDLE_CIPHERTEXT_OR_INTENT_TAMPER_NOT_DENIED'
        }
    }
    $phase=Read-CustomAppDurableRecoveryJournalReadOnlyV012 -AllowedRoot $root -StoreDirectory $journal
    if(-not[bool]$phase.ok -or [long]$phase.revision -ne 1 -or
       [string]$phase.entry.phase -cne 'atomic-mutation-starting'){
        throw 'BUNDLE_NEGATIVE_TESTS_MUTATED_JOURNAL'
    }
    Write-Host 'NATIVE_BUNDLE_V020_EXTERNAL_SOURCE_XPUI_AND_BUNDLE_DPAPI_TAMPER_DENIED_PASS'
    exit 0
}
if($Mode -ceq 'bundle-recover-interrupted'){
    [void](Invoke-CustomAppScopedBundleIndependentRecoveryV020 @pinArgs -HostedCiExitAfterSourceRestore)
    throw 'BUNDLE_EXPECTED_SOURCE_ONLY_RECOVERY_CRASH_NOT_OCCURRED'
}
$result=Invoke-CustomAppScopedBundleIndependentRecoveryV020 @pinArgs
$phase=Read-CustomAppDurableRecoveryJournalReadOnlyV012 -AllowedRoot $root -StoreDirectory $journal
if(-not[bool]$result.ok -or [bool]$result.production_mutation_authorized -or
   -not[bool]$result.source_restored_exact -or
   -not[bool]$result.xpui_restored_exact -or
   [string]$phase.entry.phase -cne 'rollback-complete' -or [long]$phase.revision -ne 3 -or
   [IO.File]::ReadAllText($source) -cne 'console.log("ORIGINAL_BUNDLE_ALPHA_V0");' -or
   [IO.File]::ReadAllText($target) -cne $baseTarget -or
   [IO.File]::ReadAllText($targetJson) -cne $baseJson -or
   [IO.File]::Exists($targetCss) -or
   [IO.File]::ReadAllText($bystander) -cne $baseBystander -or
   [IO.File]::ReadAllText($sentinel) -cne $baseSentinel -or
   -not[IO.File]::ReadAllText($config).Contains('custom_apps = alpha|beta')){
    throw 'BUNDLE_FRESH_RESTART_SOURCE_OR_XPUI_NOT_EXACT'
}
$stateDir=Join-Path (Join-Path $store 'SpotifyControlUpdates-CustomApp-State') (
  Get-CustomAppUserTxnSha256V010 ([IO.Path]::GetFullPath($live).TrimEnd('\','/').ToLowerInvariant()))
$pending=Join-Path $stateDir 'state.pending'
if(-not[IO.File]::Exists($pending) -or
   [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($pending)) -cne $pendingText){
    throw 'BUNDLE_UNRELATED_PENDING_STATE_NOT_PRESERVED'
}
$originalBackup=Join-Path (Split-Path $live -Parent) ('.native-bundle-'+('a'*64)+'.swap.before.bak')
$candidateBackup=Join-Path (Split-Path $live -Parent) ('.native-bundle-'+('a'*64)+'.restore.candidate.bak')
if([IO.File]::Exists($originalBackup) -or [IO.File]::Exists($candidateBackup)){
    throw 'BUNDLE_TRANSACTION_OWNED_SOURCE_BACKUPS_NOT_CLEANED_ON_RECOVERY'
}
Write-Host 'NATIVE_BUNDLE_V020_ATOMIC_FILE_REPLACE_BACKUPS_VERIFIED_AND_CLEANED_PASS'
if($Mode -ceq 'bundle-recover'){
    if([bool]$result.replay_idempotent){throw 'BUNDLE_FIRST_RECOVERY_MARKED_REPLAY'}
    Write-Host 'NATIVE_BUNDLE_V020_FRESH_PROCESS_SOURCE_PLUS_XPUI_RESTORED_BYTE_EXACT_PASS'
}elseif($Mode -ceq 'bundle-replay'){
    if(-not[bool]$result.replay_idempotent){throw 'BUNDLE_REPEAT_RECOVERY_NOT_IDEMPOTENT'}
    $old=[IO.File]::ReadAllBytes($source)
    [IO.File]::WriteAllText($source,'TERMINAL_EXTERNAL_SOURCE_CHANGE')
    $denied=$false
    try{[void](Invoke-CustomAppScopedBundleIndependentRecoveryV020 @pinArgs)}catch{$denied=$true}
    finally{[IO.File]::WriteAllBytes($source,$old)}
    if(-not$denied){throw 'BUNDLE_TERMINAL_SOURCE_DRIFT_SILENTLY_REWRITTEN'}
    Write-Host 'NATIVE_BUNDLE_V020_FRESH_PROCESS_REPLAY_AND_POST_TERMINAL_SOURCE_DRIFT_DENIED_PASS'
}
