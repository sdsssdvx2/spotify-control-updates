# V032 targeted: single real published source acquired once, 3 new
# transactions. Case A official real scoped refresh & apply-verified CAS;
# cases B/C simulated process loss around rename / apply-starting, followed
# by independent keyless native app rollback and original Spotify guard check.
# Legacy full suite, V027 all-app native suite are not re-run.
param([Parameter(Mandatory=$true)][string]$OriginalAddonPath,
      [Parameter(Mandatory=$true)][string]$OfficialExecutable)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
   $env:GITHUB_ACTIONS -cne 'true' -or
   $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted'){
    throw 'V032_NEW_INTEGRATION_TEST_HOSTED_WINDOWS_ONLY'
}
$env:TEMP=[IO.Path]::GetFullPath($env:RUNNER_TEMP)
$env:TMP=$env:TEMP
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
foreach($inc in @(
  'validation/v0.6.21/addon_policy_registry.ps1.inc',
  'validation/v0.6.22/addon_source_adapter_engine.ps1.inc')){
    . ([ScriptBlock]::Create([IO.File]::ReadAllText((Join-Path $root $inc),[Text.Encoding]::UTF8)))
}
foreach($file in @(
   'validation/marketplace-source-topology-v0.1.0/marketplace-source-topology.ps1',
   'validation/custom-app-remote-source-contract-v0.1.0/custom-app-remote-source-contract.ps1',
   'validation/custom-app-local-runtime-baseline-v0.1.0/custom-app-local-runtime-baseline.ps1',
   'validation/custom-app-remote-observation-collector-v0.1.0/custom-app-remote-observer.ps1',
   'validation/custom-app-stage-acquisition-contract-v0.1.0/custom-app-stage-acquisition.ps1',
   'validation/custom-app-production-permit-v0.1.0/custom-app-production-permit.ps1',
   'validation/custom-app-update-transaction-protocol-v0.1.0/custom-app-update-transaction.ps1',
   'validation/custom-app-production-atomic-live-swap-v0.1.0/custom-app-production-atomic-live-swap.ps1',
   'validation/custom-app-production-crash-recovery-journal-v0.1.0/custom-app-production-crash-recovery-journal.ps1',
   'validation/custom-app-production-pre-apply-preparation-v0.1.0/custom-app-production-pre-apply-preparation.ps1',
   'validation/approved-custom-app-native-scope/approved-scoped-native.ps1',
   'validation/approved-live-source-acquisition/approved-live-source-acquisition.ps1',
   'validation/approved-live-hmac-consumed-stage/approved-live-hmac-stage.ps1',
   'validation/approved-hmac-to-prepared-central-journal/approved-prepared-journal.ps1',
   'validation/approved-real-persistence-adapter/real-addon-persistence-core.ps1',
   'validation/approved-real-persistence-adapter/approved-real-persistence-journal.ps1',
   'validation/approved-real-native-journaled-swap-recovery/approved-native-journal-saga.ps1'
)){
    . (Join-Path $root $file)
}
$script:Version='0.6.5-r17'
. (Get-ExactAddonPersistenceFunctionsV031 -OriginalAddonPath $OriginalAddonPath)
function Assert-V032([bool]$Ok,[string]$Context){
   if(-not$Ok){throw ('V032_REAL_NATIVE_JOURNAL_FAIL: '+$Context)}
}
$item=[pscustomobject]@{
   name='better-local-files';kind='custom-app';policy='auto'
   source='Pithaya/spicetify-apps-dist';installed=$true
}
$acquired=Invoke-ApprovedLiveSourceAcquireV028 -Item $item
Assert-V032 ([bool]$acquired.ok -and
   [string]$acquired.runtime_tree_sha256 -cmatch '^[a-f0-9]{64}$' -and
   -not[bool]$acquired.production_mutation_authorized) 'real GitHub source not qualified'
$exe=(Get-FileHash -LiteralPath $OfficialExecutable -Algorithm SHA256).Hash.ToLowerInvariant()
Assert-V032 ($exe -ceq '3563f26acd7527adc97e6c19272fa1b48ce976a913625d9804ac57d3c54fb4db') 'pinned official executable changed'
$caseBase=Join-Path $env:RUNNER_TEMP ('v032-integrated-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
$receiptStore=Join-Path $caseBase 'single-use-receipts'
[IO.Directory]::CreateDirectory($receiptStore)|Out-Null
function Create-V032PreparedCase([string]$CaseName){
   $work=Join-Path (Join-Path $caseBase $CaseName) 'v031-fixture'
   $live=Join-Path (Join-Path $work 'CustomApps') ([string]$item.name)
   $local=Join-Path $work 'ProtectedSpotify\Local'
   $roaming=Join-Path $work 'ProtectedSpotify\Roaming'
   foreach($p in @((Join-Path $work 'CustomApps'),$local,$roaming)){
      [IO.Directory]::CreateDirectory($p)|Out-Null
   }
   $defs=@(Get-SpotifyPersistenceSurfaceDefinitions -LocalAppDataRoot $local -AppDataRoot $roaming)
   Assert-V032 ($defs.Count -ge 4) 'genuine guarded Spotify inventory unexpectedly small'
   for($n=0;$n -lt $defs.Count;$n++){
       $s=$defs[$n]
       $full=Assert-CustomAppProductionCrashJournalPathV010 -AllowedRoot $env:RUNNER_TEMP -Path ([string]$s.path)
       if([string]$s.kind -ceq 'Directory'){
           [IO.Directory]::CreateDirectory($full)|Out-Null
           $destination=Join-Path $full ('v032-protected-'+$n+'.bin')
       }else{
           [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($full))|Out-Null
           $destination=$full
       }
       [IO.File]::WriteAllText($destination,('V032_REAL_GUARDED_SPOTIFY_SURFACE_FIXTURE_'+$CaseName+'_'+$n),[Text.UTF8Encoding]::new($false))
   }
   [void](Copy-CustomAppAtomicTreeV010 -Source ([string]$acquired.stage_path) -Destination $live)
   [IO.File]::AppendAllText((Join-Path $live 'index.js'),('/*V032_PREVIOUS_INSTALLED_VERSION_'+$CaseName+'*/'))
   $old=Get-CustomAppLocalRuntimeBaseline -Name ([string]$item.name) -AppPath $live
   Assert-V032 ([bool]$old.safe -and [bool]$old.installable -and
        [string]$old.tree_sha256 -cne [string]$acquired.runtime_tree_sha256) ('old app not a real full tree '+$CaseName)
   $original=Get-CustomAppUpdateTreeSnapshotV010 -Root $live
   $prefs=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $local -AppDataRoot $roaming
   $key=New-Object byte[] 32;$nonceBytes=New-Object byte[] 16
   $rng=[Security.Cryptography.RandomNumberGenerator]::Create()
   try{$rng.GetBytes($key);$rng.GetBytes($nonceBytes)}finally{$rng.Dispose()}
   $nonce=([BitConverter]::ToString($nonceBytes)).Replace('-','').ToLowerInvariant()
   try{
       $permit=New-ApprovedLiveHmacStagePermitV029 -Item $item -Acquired $acquired -SessionKey $key -Nonce $nonce
       $claimed=Consume-ApprovedLiveHmacStageOnceV029 -Item $item -Acquired $acquired -Permit $permit -SessionKey $key -ReceiptStore $receiptStore
       Assert-V032 ([bool]$claimed.ok -and [bool]$claimed.single_use_consumed) ('single use HMAC not actually spent '+$CaseName)
       $prepared=Invoke-ApprovedRealPersistPreparedV031 -Item $item -Acquired $acquired -Permit $permit -SessionKey $key -ReceiptStore $receiptStore -WorkRoot $work
       Assert-V032 ([bool]$prepared.ok -and [string]$prepared.central_phase -ceq 'prepared' -and
          [int]$prepared.central_revision -eq 0 -and
          [int]$prepared.protected_surface_count -eq $defs.Count -and
          -not[bool]$prepared.production_mutation_authorized) ('real guarded source backup not journal-prepared '+$CaseName)
       return [pscustomobject]@{
           case=$CaseName;work=$work;live=$live
           local=$local;roaming=$roaming
           initial_tree_sha256=[string]$original.tree_sha256
           initial_persistence_sha256=[string]$prefs.fingerprint
           token_id=[string]$permit.token_id
           prepared=$prepared
       }
   }finally{[Array]::Clear($key,0,$key.Length)}
}
$success=Create-V032PreparedCase 'success'
$officialRoot=Join-Path $env:RUNNER_TEMP ('v032-official-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
$applied=Invoke-ApprovedNativeJournalApplyV032 -Item $item -Acquired $acquired -Prepared $success.prepared -ReceiptStore $receiptStore -OfficialExecutable $OfficialExecutable -VendorPrivateRoot $officialRoot
Assert-V032 ([bool]$applied.ok -and
   [string]$applied.phase -ceq 'apply-verified' -and
   [int]$applied.journal_revision -eq 7 -and
   [bool]$applied.official_cli_executed -and
   [bool]$applied.tested_only_with_fake_Spotify_xpui -and
   [bool]$applied.rollback_backup_preserved -and
   -not[bool]$applied.actually_installed_Spotify_updated -and
   -not[bool]$applied.production_mutation_authorized) ('same-journal official native scope did not reach verified, got '+[string]$applied.reason)
$p=Get-ApprovedRealPersistJournalPathsV031 -WorkRoot $success.work -Name ([string]$item.name) -TokenId $success.token_id
$journal=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $env:RUNNER_TEMP -StoreDirectory ([string]$p.journal)
Assert-V032 ([bool]$journal.ok -and
   [string]$journal.entry.phase -ceq 'apply-verified' -and
   [string]$journal.entry.apply_result_fingerprint -cmatch '^[a-f0-9]{64}$' -and
   [string]$journal.entry.finalization_fingerprint -cmatch '^[a-f0-9]{64}$' -and
   [int]$journal.revision -eq 7) 'same V031 source central CAS did not hold actual official vendor receipt'
$after=Get-CustomAppLocalRuntimeBaseline -Name ([string]$item.name) -AppPath $success.live
$protect=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $success.local -AppDataRoot $success.roaming
Assert-V032 ([string]$after.tree_sha256 -ceq [string]$acquired.runtime_tree_sha256 -and
   [string]$protect.fingerprint -ceq $success.initial_persistence_sha256 -and
   [IO.Directory]::Exists((Join-Path ([string]$p.transaction) 'old-live')) -and
   [IO.Directory]::Exists([string]$p.app_backup)) 'source, old live and Spotify backup not preserved after vendor'
$refused=Invoke-ApprovedNativeJournalRecoveryV032 -WorkRoot $success.work -Name ([string]$item.name) -TokenId $success.token_id -ReceiptStore $receiptStore -TransactionId ([string]$success.prepared.transaction_id)
Assert-V032 (-not[bool]$refused.ok -and
   [string]$refused.reason -like '*ROLLBACK_OUTSIDE_PRECOMMIT*') 'apply-verified journal was incorrectly auto-rolled-back'
Write-Host 'V032_ACTUAL_UPSTREAM_HMAC_ORIGINAL_SPOTIFY_GUARD_AND_REAL_OFFICIAL_SCOPED_JOURNAL_APPLY_VERIFIED_PASS'
foreach($variant in @(
   [pscustomobject]@{id='crash-during-rename';point='after-live-move-before-journal';phase='atomic-mutation-starting';expectedRevision=1},
   [pscustomobject]@{id='crash-before-vendor';point='before-official-cli';phase='apply-starting';expectedRevision=5}
)){
   $fixture=Create-V032PreparedCase ([string]$variant.id)
   $nativeRoot=Join-Path $env:RUNNER_TEMP ('v032-unused-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
   $interrupted=Invoke-ApprovedNativeJournalApplyV032 -Item $item -Acquired $acquired -Prepared $fixture.prepared -ReceiptStore $receiptStore -OfficialExecutable $OfficialExecutable -VendorPrivateRoot $nativeRoot -FailurePoint ([string]$variant.point)
   Assert-V032 (-not[bool]$interrupted.ok -and
       [string]$interrupted.phase -ceq [string]$variant.phase -and
       [bool]$interrupted.independent_recovery_required -and
       -not[bool]$interrupted.production_mutation_authorized) ('intentional stop not fail-closed '+$variant.id+': '+[string]$interrupted.reason)
   $paths=Get-ApprovedNativeRecoveryPathsV032 -WorkRoot $fixture.work -Name ([string]$item.name) -TokenId $fixture.token_id
   $during=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $env:RUNNER_TEMP -StoreDirectory ([string]$paths.journal)
   Assert-V032 ([string]$during.entry.phase -ceq [string]$variant.phase -and
       [int]$during.revision -eq [int]$variant.expectedRevision) ('crash location mismatch '+$variant.id)
   $child=Join-Path $PSScriptRoot 'read-rollback-fresh-process.ps1'
   & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $child -WorkRoot $fixture.work -Name ([string]$item.name) -TokenId $fixture.token_id -ReceiptStore $receiptStore -TransactionId ([string]$fixture.prepared.transaction_id) -OriginalAddonPath $OriginalAddonPath
   Assert-V032 ($LASTEXITCODE -eq 0) ('independent keyless rollback failure '+$variant.id)
   $recovered=Get-CustomAppUpdateTreeSnapshotV010 -Root $fixture.live
   $persist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $fixture.local -AppDataRoot $fixture.roaming
   $done=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $env:RUNNER_TEMP -StoreDirectory ([string]$paths.journal)
   Assert-V032 ([string]$recovered.tree_sha256 -ceq [string]$fixture.initial_tree_sha256 -and
      [string]$persist.fingerprint -ceq [string]$fixture.initial_persistence_sha256 -and
      [string]$done.entry.phase -ceq 'rollback-complete' -and
      [int]$done.revision -eq ([int]$variant.expectedRevision+2) -and
      [IO.Directory]::Exists([string]$paths.app_backup) -and
      [IO.Directory]::Exists([string]$paths.persistence_root)) (
          'original rollback byte state or journal not durable '+$variant.id)
   Write-Host ('V032_FRESH_PROCESS_EXACT_OLD_APP_AND_REAL_ADDON_SPOTIFY_BACKUP_ROLLBACK_PASS case='+$variant.id)
}
Write-Host 'V032_GENUINE_OFFICIAL_SCOPED_IN_SINGLE_CAS_AND_TWO_RESTART_RECOVERIES_PASS'
Write-Host 'V032_NO_USER_SPOTIFY_NO_COMMITTED_CLEAN_NO_ORIGINAL_BACKUP_REMOVAL_NO_PRODUCTION_AUTHORITY_PASS'
