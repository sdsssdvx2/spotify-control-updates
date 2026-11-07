# V039 targeted one official scoped update + reversible evidence fault tests.
# No full old E2E replay, no real Spotify, NO backup deletion or cleanup.
param([Parameter(Mandatory=$true)][string]$OriginalAddonPath,
      [Parameter(Mandatory=$true)][string]$OfficialExecutable)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot '..\approved-real-native-journaled-swap-recovery\test-approved-native-journal-saga.ps1') -OriginalAddonPath $OriginalAddonPath -OfficialExecutable $OfficialExecutable -LibraryOnly
. (Join-Path $PSScriptRoot '..\approved-real-native-verified-readback\verified-official-readback-v033.ps1')
. (Join-Path $PSScriptRoot '..\approved-real-native-xpui-crash-restore\native-xpui-escrow-recovery.ps1')
. (Join-Path $PSScriptRoot '..\approved-native-complete-output-proof\full-native-output-proof-v037.ps1')
. (Join-Path $PSScriptRoot 'retained-terminal-v039.ps1')
function Assert-V039([bool]$Allowed,[string]$Why){
 if(-not$Allowed){throw ('V039_TEST_'+$Why)}
}
$fixture=Create-V032PreparedCase 'v039-non-destructive-terminal'
$vendor=Join-Path $env:RUNNER_TEMP ('v032-official-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
$args=@{
 WorkRoot=$fixture.work;Name=[string]$item.name
 TokenId=[string]$fixture.token_id;ReceiptStore=[string]$receiptStore
 TransactionId=[string]$fixture.prepared.transaction_id
 VendorPrivateRoot=$vendor;OfficialExecutable=$OfficialExecutable
}
$applied=Invoke-ApprovedNativeXpuiEscrowApplyV034 -Item $item -Acquired $acquired -Prepared $fixture.prepared -ReceiptStore $receiptStore -OfficialExecutable $OfficialExecutable -VendorPrivateRoot $vendor
Assert-V039 ([bool]$applied.ok -and [string]$applied.phase -ceq 'apply-verified' -and [int64]$applied.journal_revision -eq 8) 'PINNED_GENUINE_OFFICIAL_UPDATE_NOT_VERIFIED'
$sealed=Save-ApprovedNativeFullOutputReceiptV037 @args
Assert-V039 ([bool]$sealed.ok -and [bool]$sealed.entire_official_output_verified -and
  [string]$sealed.phase -ceq 'apply-verified') 'ALL_FOUR_OFFICIAL_OUTPUT_SEAL_NOT_DURABLE'
$p=Get-ApprovedNativeRecoveryPathsV032 -WorkRoot $fixture.work -Name ([string]$item.name) -TokenId $fixture.token_id
$journal=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $env:RUNNER_TEMP -StoreDirectory ([string]$p.journal)
$preHead=[string]$journal.entry.entry_sha256
$preLive=Get-CustomAppUpdateTreeSnapshotV010 -Root $fixture.live
$preOriginal=Get-CustomAppUpdateTreeSnapshotV010 -Root $p.app_backup
$preStage=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$acquired.stage_path)
$xpui=Join-Path $vendor 'FakeSpotify\Apps\xpui'
$xpuiBefore=Get-CustomAppUpdateTreeSnapshotV010 -Root $xpui
$preimage=Join-Path $p.transaction 'native-xpui-preimage'
$preXpui=Get-CustomAppUpdateTreeSnapshotV010 -Root $preimage
# First reject changed official CSS without attempting a terminal write.
$css=Join-Path $xpui ('spicetify-routes-'+[string]$item.name+'.css')
$originalCss=[IO.File]::ReadAllBytes($css)
[IO.File]::AppendAllText($css,'/* V039_CSS_TAMPER */')
$deny=Invoke-ApprovedNativeRetainedTerminalV039 @args
Assert-V039 (-not[bool]$deny.ok -and
 [string](Read-CustomAppProductionCrashJournalV010 -AllowedRoot $env:RUNNER_TEMP -StoreDirectory ([string]$p.journal)).entry.entry_sha256 -ceq $preHead) 'CHANGED_NATIVE_OUTPUT_WAS_TERMINALLY_COMMITTED'
[IO.File]::WriteAllBytes($css,$originalCss)
# Full V037 sidecar is required; missing evidence must fail-closed.
$receipt=Get-ApprovedNativeOutputProofPathV037 -Paths $p -TransactionId $args.TransactionId
$hidden=$receipt+'.temporarily-unavailable'
[IO.File]::Move($receipt,$hidden)
try{
 $missing=Invoke-ApprovedNativeRetainedTerminalV039 @args
 Assert-V039 (-not[bool]$missing.ok -and
  [string](Read-CustomAppProductionCrashJournalV010 -AllowedRoot $env:RUNNER_TEMP -StoreDirectory ([string]$p.journal)).entry.entry_sha256 -ceq $preHead) 'MISSING_DPAPI_NATIVE_PROOF_WAS_COMMITTED'
}finally{[IO.File]::Move($hidden,$receipt)}
# Fail before CAS => journal unchanged and all backups preserved.
$before=Invoke-ApprovedNativeRetainedTerminalV039 @args -FailurePoint 'before-terminal-cas'
Assert-V039 (-not[bool]$before.ok -and
 [string]$before.reason -ceq 'V039_INJECTED_STOP_BEFORE_TERMINAL_CAS' -and
 [string](Read-CustomAppProductionCrashJournalV010 -AllowedRoot $env:RUNNER_TEMP -StoreDirectory ([string]$p.journal)).entry.entry_sha256 -ceq $preHead) 'PRE_CAS_STOP_ADVANCED_JOURNAL'
# Fail after CAS but before response. A new reader must discover success.
$after=Invoke-ApprovedNativeRetainedTerminalV039 @args -FailurePoint 'after-terminal-cas-before-return'
Assert-V039 (-not[bool]$after.ok -and
 [string]$after.reason -ceq 'V039_INJECTED_STOP_AFTER_DURABLE_TERMINAL') 'POST_CAS_CRASH_WINDOW_NOT_EXERCISED'
$terminal=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $env:RUNNER_TEMP -StoreDirectory ([string]$p.journal)
Assert-V039 ([string]$terminal.entry.phase -ceq 'committed-retained' -and
 [int64]$terminal.revision -eq 9 -and
 [string]$terminal.entry.previous_entry_sha256 -ceq $preHead -and
 [string]$terminal.entry.cleanup_result_fingerprint -cne ('0'*64)) 'TERMINAL_CAS_NOT_DURABLE'
# The already-qualified independent keyless verifier must still work after
# committed-retained, not just at apply-verified.
$child=Join-Path $PSScriptRoot '..\approved-native-complete-output-proof\read-entire-output-fresh-process.ps1'
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $child -WorkRoot $fixture.work -Name ([string]$item.name) -TokenId $fixture.token_id -ReceiptStore $receiptStore -TransactionId $args.TransactionId -VendorPrivateRoot $vendor -OfficialExecutable $OfficialExecutable -OriginalAddonPath $OriginalAddonPath
Assert-V039 ($LASTEXITCODE -eq 0) 'FRESH_PROCESS_KEYLESS_TERMINAL_READBACK_DENIED'
$again=Invoke-ApprovedNativeRetainedTerminalV039 @args
$journalAgain=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $env:RUNNER_TEMP -StoreDirectory ([string]$p.journal)
Assert-V039 ([bool]$again.ok -and
 [string]$again.phase -ceq 'committed-retained' -and
 [bool]$again.terminal_replay_no_mutation -and
 [string]$journalAgain.entry.entry_sha256 -ceq [string]$terminal.entry.entry_sha256) 'TERMINAL_REPLAY_NOT_IDEMPOTENT'
$decision=Resolve-CustomAppProductionCrashRecoveryClassificationV010 -StoreRead $journalAgain -ExpectedTransactionId $args.TransactionId
Assert-V039 ([bool]$decision.ok -and [bool]$decision.no_action -and
 -not[bool]$decision.housekeeping_only -and -not[bool]$decision.production_execution_authorized) 'TERMINAL_CLASSIFICATION_DOES_NOT_PRESERVE_BACKUPS'
# After committed-retained, an unexpected change denies revalidation but
# does not delete content or rewrite the terminal journal.
$foreign=Join-Path $xpui 'user-settings-dont-change.dat'
$foreignBytes=[IO.File]::ReadAllBytes($foreign)
[IO.File]::AppendAllText($foreign,'V039_CONCURRENT_FOREIGN_EDIT')
$changed=Invoke-ApprovedNativeRetainedTerminalV039 @args
Assert-V039 (-not[bool]$changed.ok -and
 [string](Read-CustomAppProductionCrashJournalV010 -AllowedRoot $env:RUNNER_TEMP -StoreDirectory ([string]$p.journal)).entry.entry_sha256 -ceq [string]$terminal.entry.entry_sha256) 'POST_TERMINAL_FOREIGN_CHANGE_WAS_IGNORED'
[IO.File]::WriteAllBytes($foreign,$foreignBytes)
$denyOld=Invoke-ApprovedNativeJournalRecoveryV032 -WorkRoot $fixture.work -Name ([string]$item.name) -TokenId $fixture.token_id -ReceiptStore $receiptStore -TransactionId $args.TransactionId
Assert-V039 (-not[bool]$denyOld.ok) 'TERMINAL_LEGACY_ROLLBACK_UNEXPECTEDLY_ALLOWED'
# No source/archive, original app, protected Spotify data, XPUI preimage
# or failed-candidate rollback artifact was deleted.
$originalNow=Get-CustomAppUpdateTreeSnapshotV010 -Root $p.app_backup
$liveNow=Get-CustomAppUpdateTreeSnapshotV010 -Root $fixture.live
$stageNow=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$acquired.stage_path)
$xpuiNow=Get-CustomAppUpdateTreeSnapshotV010 -Root $xpui
$preXpuiNow=Get-CustomAppUpdateTreeSnapshotV010 -Root $preimage
$persistent=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $fixture.local -AppDataRoot $fixture.roaming
Assert-V039 ([string]$originalNow.tree_sha256 -ceq [string]$preOriginal.tree_sha256 -and
 [string]$liveNow.tree_sha256 -ceq [string]$preLive.tree_sha256 -and
 [string]$stageNow.tree_sha256 -ceq [string]$preStage.tree_sha256 -and
 [string]$xpuiNow.tree_sha256 -ceq [string]$xpuiBefore.tree_sha256 -and
 [string]$preXpuiNow.tree_sha256 -ceq [string]$preXpui.tree_sha256 -and
 [string]$persistent.fingerprint -ceq [string]$fixture.initial_persistence_sha256 -and
 [IO.Directory]::Exists([string]$p.transaction) -and
 [IO.Directory]::Exists([string]$p.app_backup) -and
 [IO.Directory]::Exists([string]$p.persistence_root) -and
 [IO.File]::Exists($receipt) -and
 [IO.File]::Exists((Get-ApprovedNativeXpuiEscrowPathV034 -Paths $p -TransactionId $args.TransactionId))) 'BACKUP_OR_SOURCE_DELETED_AFTER_TERMINAL'
Write-Host 'V039_OFFICIAL_NATIVE_AND_ALL_FOUR_OUTPUTS_RETENTION_TERMINAL_PASS'
Write-Host 'V039_CAS_CRASH_BEFORE_AFTER_AND_IDEMPOTENT_REPLAY_PASS'
Write-Host 'V039_KEYLESS_TERMINAL_READBACK_AND_FOREIGN_TAMPER_REFUSAL_PASS'
Write-Host 'V039_APP_SPOTIFY_GUARD_XPUI_SOURCE_ZIP_BACKUPS_NOT_DELETED_PASS'
Write-Host 'V039_NO_REAL_SPOTIFY_NO_PRODUCTION_AUTHORITY_NO_VERSION_CHANGE_PASS'
