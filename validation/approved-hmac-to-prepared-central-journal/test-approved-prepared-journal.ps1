# V030 integration: actual live approved source, genuine V029 HMAC and
# DPAPI one-time consumption -> exact original / protected fixture tree
# backups -> genuine V010 append-only prepared journal + fresh-process
# no-key verification. No new native Spicetify run (qualified V027).
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
   $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted'){
    throw 'V030_TARGETED_HOSTED_WINDOWS_ONLY'
}
$env:TEMP=[IO.Path]::GetFullPath($env:RUNNER_TEMP)
$env:TMP=$env:TEMP
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
foreach($inc in @('validation/v0.6.21/addon_policy_registry.ps1.inc',
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
   'validation/approved-custom-app-native-scope/approved-scoped-native.ps1',
   'validation/approved-live-source-acquisition/approved-live-source-acquisition.ps1',
   'validation/approved-live-hmac-consumed-stage/approved-live-hmac-stage.ps1',
   'validation/approved-hmac-to-prepared-central-journal/approved-prepared-journal.ps1'
)){
    . (Join-Path $root $file)
}
function Assert-V030([bool]$Condition,[string]$Context){
    if(-not$Condition){throw ('V030_TARGETED_INTEGRATION_ASSERTION_FAILED: '+$Context)}
}
$item=[pscustomobject]@{
    name='better-local-files';kind='custom-app';policy='auto'
    source='Pithaya/spicetify-apps-dist';installed=$true
}
$acquired=Invoke-ApprovedLiveSourceAcquireV028 -Item $item
Assert-V030 ([bool]$acquired.ok) 'current actual approved source not fetched'
$workParent=Join-Path $env:RUNNER_TEMP ('v030-'+[Guid]::NewGuid().ToString('N'))
$work=Join-Path $workParent 'v030-fixture'
$live=Join-Path (Join-Path $work 'CustomApps') $item.name
$persist=Join-Path $work 'ProtectedSpotify'
[IO.Directory]::CreateDirectory((Join-Path $work 'CustomApps'))|Out-Null
[IO.Directory]::CreateDirectory((Join-Path $persist 'Local\Spotify'))|Out-Null
[IO.Directory]::CreateDirectory((Join-Path $persist 'Roaming\Spotify'))|Out-Null
[IO.Directory]::CreateDirectory((Join-Path $persist 'Roaming\spicetify'))|Out-Null
[IO.File]::WriteAllText((Join-Path $persist 'Local\Spotify\Local State'),'V030_PROTECTED_LOCAL')
[IO.File]::WriteAllText((Join-Path $persist 'Roaming\Spotify\prefs'),'V030_PROTECTED_ROAMING')
[IO.File]::WriteAllText((Join-Path $persist 'Roaming\spicetify\config.ini'),'V030_PROTECTED_CONFIG')
$beforeClone=Copy-CustomAppAtomicTreeV010 -Source ([string]$acquired.stage_path) -Destination $live
[IO.File]::AppendAllText((Join-Path $live 'index.js'),'/*V030_PREVIOUS_INSTALLED_VERSION_TO_BACKUP*/')
$old=Get-CustomAppLocalRuntimeBaseline -Name ([string]$item.name) -AppPath $live
Assert-V030 ([bool]$old.safe -and [bool]$old.installable -and
   [string]$old.tree_sha256 -cne [string]$acquired.runtime_tree_sha256) 'installed fixture should be a safe changed original version'
$oldFull=Get-CustomAppUpdateTreeSnapshotV010 -Root $live
$persistFull=Get-CustomAppUpdateTreeSnapshotV010 -Root $persist
$store=Join-Path $workParent 'hmac-receipts'
[IO.Directory]::CreateDirectory($store)|Out-Null
$rng=[Security.Cryptography.RandomNumberGenerator]::Create()
$key=New-Object byte[] 32
$nonceData=New-Object byte[] 16
try{$rng.GetBytes($key);$rng.GetBytes($nonceData)}finally{$rng.Dispose()}
$nonce=([BitConverter]::ToString($nonceData)).Replace('-','').ToLowerInvariant()
try{
   $token=New-ApprovedLiveHmacStagePermitV029 -Item $item -Acquired $acquired -SessionKey $key -Nonce $nonce
   $consumed=Consume-ApprovedLiveHmacStageOnceV029 -Item $item -Acquired $acquired -Permit $token -SessionKey $key -ReceiptStore $store
   Assert-V030 ([bool]$consumed.ok -and [bool]$consumed.single_use_consumed) 'genuine V029 HMAC not consumed before central journal'
   $joined=Invoke-ApprovedHmacToPreparedCentralJournalV030 -Item $item -Acquired $acquired -Permit $token -SessionKey $key -ReceiptStore $store -WorkRoot $work
   Assert-V030 ([bool]$joined.ok -and [string]$joined.phase -ceq 'prepared' -and
      [int64]$joined.journal_revision -eq 0 -and
      -not[bool]$joined.production_mutation_authorized -and
      -not[bool]$joined.real_spotify_persistence_covered) 'V030 refused actual consumed HMAC to V010 prepared CAS'
   $verified=Read-ApprovedPreparedCentralJournalV030 -WorkRoot $work -Name ([string]$item.name) -TokenId ([string]$token.token_id) -ReceiptStore $store -TransactionId ([string]$joined.transaction_id)
   Assert-V030 ([bool]$verified.ok -and [string]$verified.original_tree_sha256 -ceq [string]$oldFull.tree_sha256 -and
      [string]$verified.persistence_fixture_tree_sha256 -ceq [string]$persistFull.tree_sha256) 'V010 prepared stage source or full backups not independently verified'
   $native=Get-CustomAppLocalRuntimeBaseline -Name ([string]$item.name) -AppPath $live
   Assert-V030 ([string]$native.tree_sha256 -ceq [string]$old.tree_sha256) 'central journal preparation changed existing app before apply'
   Write-Host 'V030_REAL_APPROVED_HMAC_CONSUMED_EXACT_APP_AND_FIXTURE_PERSISTENCE_PREPARED_CAS_PASS'
   $worker=Join-Path $PSScriptRoot 'read-prepared-journal-fresh-process.ps1'
   & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $worker -WorkRoot $work -Name ([string]$item.name) -TokenId ([string]$token.token_id) -ReceiptStore $store -TransactionId ([string]$joined.transaction_id)
   Assert-V030 ($LASTEXITCODE -eq 0) 'fresh independent PowerShell could not recover source/backups and actual central journal without HMAC key'
   $double=$false
   try{[void](Invoke-ApprovedHmacToPreparedCentralJournalV030 -Item $item -Acquired $acquired -Permit $token -SessionKey $key -ReceiptStore $store -WorkRoot $work)}
   catch{$double=$true}
   Assert-V030 $double 're-enrollment overwrote existing central journal or backups'
   $p=Get-ApprovedPreparedPathsV030 -WorkRoot $work -Name ([string]$item.name) -TokenId ([string]$token.token_id)
   $tamperPaths=@(
      (Join-Path ([string]$p.app_backup) 'index.js'),
      (Join-Path ([string]$p.persistence_backup) 'Roaming\Spotify\prefs'),
      (Join-Path ([string]$p.persist) 'Local\Spotify\Local State')
   )
   foreach($path in $tamperPaths){
      $original=[IO.File]::ReadAllBytes($path)
      try{
         [IO.File]::AppendAllText($path,'V030_UNAUTHORIZED_CHANGED_AFTER_BACKUP')
         $reject=Read-ApprovedPreparedCentralJournalV030 -WorkRoot $work -Name ([string]$item.name) -TokenId ([string]$token.token_id) -ReceiptStore $store -TransactionId ([string]$joined.transaction_id)
         Assert-V030 (-not[bool]$reject.ok) ('tampered rollback backup or fixture persistence was accepted '+[IO.Path]::GetFileName($path))
      }finally{[IO.File]::WriteAllBytes($path,$original)}
   }
   $sidecar=Get-ApprovedPreparedSealedPathV030 -Paths $p -TransactionId ([string]$joined.transaction_id)
   $envelope=[IO.File]::ReadAllBytes($sidecar)
   try{
      $bad=New-Object byte[] $envelope.Length
      [Array]::Copy($envelope,$bad,$envelope.Length)
      $bad[4]=$bad[4] -bxor 1
      [IO.File]::WriteAllBytes($sidecar,$bad)
      $denied=Read-ApprovedPreparedCentralJournalV030 -WorkRoot $work -Name ([string]$item.name) -TokenId ([string]$token.token_id) -ReceiptStore $store -TransactionId ([string]$joined.transaction_id)
      Assert-V030 (-not[bool]$denied.ok) 'DPAPI backup-proof header altered but central journal accepted'
   }finally{[IO.File]::WriteAllBytes($sidecar,$envelope)}
   $restored=Read-ApprovedPreparedCentralJournalV030 -WorkRoot $work -Name ([string]$item.name) -TokenId ([string]$token.token_id) -ReceiptStore $store -TransactionId ([string]$joined.transaction_id)
   Assert-V030 ([bool]$restored.ok) 'after tamper restored exact backup was not readable'
   $currentJournal=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $env:RUNNER_TEMP -StoreDirectory ([string]$p.journal)
   Assert-V030 ([int64]$currentJournal.revision -eq 0 -and
      [string]$currentJournal.entry.phase -ceq 'prepared' -and
      [string]$currentJournal.transaction_id -ceq [string]$joined.transaction_id) 'negative tests changed existing journal history'
   Write-Host 'V030_ORIGINAL_BACKUP_FIXTURE_PERSISTENCE_DPAPI_TAMPER_AND_REPLAY_DENIED_PASS'
   Write-Host 'V030_GENUINE_SOURCE_HMAC_ONCE_TO_PREPARED_CENTRAL_JOURNAL_FRESH_PROCESS_PASS'
   Write-Host 'V030_HOSTED_FIXTURE_ONLY_REAL_SPOTIFY_PERSISTENCE_NOT_COVERED_NO_MUTATION_AUTHORITY_PASS'
}finally{
   [Array]::Clear($key,0,$key.Length)
}
