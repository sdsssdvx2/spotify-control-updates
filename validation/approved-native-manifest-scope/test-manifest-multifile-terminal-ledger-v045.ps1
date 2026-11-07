# V045 manifest-heavy genuine approved ivLyrics source end-to-end.
# Hosted Windows GitHub runner only. Real-source HMAC, real Addon
# persistence guard, one pinned official CLI to FakeSpotify XPUI,
# V037 schema-2 manifest-owned DPAPI receipt, V039 retained terminal,
# V040 CurrentUser-DPAPI single-use ledger.
param([Parameter(Mandatory=$true)][string]$OriginalAddonPath,
      [Parameter(Mandatory=$true)][string]$OfficialExecutable)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot '..\approved-real-native-journaled-swap-recovery\test-approved-native-journal-saga.ps1') -OriginalAddonPath $OriginalAddonPath -OfficialExecutable $OfficialExecutable -LibraryOnly
. (Join-Path $PSScriptRoot '..\approved-real-native-verified-readback\verified-official-readback-v033.ps1')
. (Join-Path $PSScriptRoot '..\approved-real-native-xpui-crash-restore\native-xpui-escrow-recovery.ps1')
. (Join-Path $PSScriptRoot '..\approved-native-complete-output-proof\full-native-output-proof-v037.ps1')
. (Join-Path $PSScriptRoot '..\approved-native-retained-terminal\retained-terminal-v039.ps1')
. (Join-Path $PSScriptRoot '..\custom-app-user-transaction-store-bundle\user-transaction-store.ps1')
. (Join-Path $PSScriptRoot '..\custom-app-user-transaction-transition-guard\user-transaction-guard.ps1')
. (Join-Path $PSScriptRoot '..\approved-native-retained-user-transaction\native-retained-ledger-v040.ps1')
function Assert-MultiV045([bool]$ok,[string]$reason){
 if(-not$ok){throw ('V045_MULTIFILE_TEST_'+$reason)}
}
# This second true published source is independently acquired, not
# imitated by editing an already-authenticated Pithaya staging tree.
$script:item=[pscustomobject]@{
 name='ivLyrics';kind='custom-app';policy='auto'
 source='ivLis-Studio/ivLyrics';installed=$true
}
$script:acquired=Invoke-ApprovedLiveSourceAcquireV028 -Item $item
Assert-MultiV045 ([bool]$acquired.ok -and
 [string]$acquired.runtime_tree_sha256 -cmatch '^[a-f0-9]{64}$' -and
 -not[bool]$acquired.production_mutation_authorized) 'PUBLISHED_IVLYRICS_NOT_QUALIFIED'
$manifest=Get-ApprovedNativeManifestOwnedScopeV044 -Name ([string]$item.name) -SourceAppPath ([string]$acquired.stage_path)
Assert-MultiV045 (@($manifest.owned_files).Count -gt 4 -and
  [int]$manifest.declared_extensions -gt 1 -and
  [string]$manifest.source_tree_sha256 -ceq [string]$acquired.runtime_tree_sha256) 'AUTHENTIC_MULTIFILE_MANIFEST_NOT_PINNED'
Write-Host 'V045_REAL_IVLYRICS_PUBLISHED_MANIFEST_HAS_MULTIPLE_OWNED_OUTPUTS_PASS'
$fixture=Create-V032PreparedCase 'v045-manifest-heavy-native'
$vendor=Join-Path $env:RUNNER_TEMP ('v032-official-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
$userRoot=Join-Path $env:RUNNER_TEMP ('v045-user-ledger-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
[IO.Directory]::CreateDirectory($userRoot)|Out-Null
$token=[string]$fixture.token_id
$tx=[string]$fixture.prepared.transaction_id
$args=@{
 WorkRoot=$fixture.work;Name=[string]$item.name;TokenId=$token
 ReceiptStore=$receiptStore;TransactionId=$tx
 VendorPrivateRoot=$vendor;OfficialExecutable=$OfficialExecutable
}
$session=Open-CustomAppUserTxnStoreV010 -Name ([string]$item.name) -LivePath ([string]$fixture.live) -HostedCiRoot $userRoot -Initialize
try{
 $reservation=Reserve-CustomAppUserTxnIdV010 -Session $session -ConsumptionId $token -TransactionId $tx -Nonce ([Guid]::NewGuid().ToString('N'))
 Assert-MultiV045 ([bool]$reservation.ok -and $null-ne$session.state.active -and
  [string]$session.state.active.consumption_id -ceq $token) 'PRE_VENDOR_RESERVATION_NOT_DURABLE'
}finally{$session.lock_handle.Dispose()}
$applied=Invoke-ApprovedNativeXpuiEscrowApplyV034 -Item $item -Acquired $acquired -Prepared $fixture.prepared -ReceiptStore $receiptStore -OfficialExecutable $OfficialExecutable -VendorPrivateRoot $vendor
Assert-MultiV045 ([bool]$applied.ok -and [string]$applied.phase -ceq 'apply-verified' -and
 [int64]$applied.journal_revision -eq 8) 'REAL_CLI_IVLYRICS_APPLY_NOT_VERIFIED'
$receipt=Save-ApprovedNativeFullOutputReceiptV037 @args
Assert-MultiV045 ([bool]$receipt.ok -and
 [bool]$receipt.manifest_scoped_output_verified -and
 [bool]$receipt.entire_official_output_verified -and
 [int]$receipt.exact_official_owned_files -eq @($manifest.owned_files).Count -and
 [int]$receipt.exact_official_owned_files -gt 4 -and
 [int]$receipt.declared_extension_files -eq [int]$manifest.declared_extensions -and
 [string]$receipt.source_tree_sha256 -ceq [string]$acquired.runtime_tree_sha256 -and
 [string]$receipt.manifest_owned_set_sha256 -cmatch '^[a-f0-9]{64}$') 'MULTIFILE_NATIVE_DPAPI_SEAL_WRONG'
Write-Host 'V045_REAL_OFFICIAL_IVLYRICS_MULTIFILE_MANIFEST_DPAPI_SEAL_PASS'
$paths=Get-ApprovedNativeRecoveryPathsV032 -WorkRoot $fixture.work -Name ([string]$item.name) -TokenId $token
$original=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$paths.app_backup)
$before=Get-CustomAppUpdateTreeSnapshotV010 -Root (Join-Path ([string]$paths.transaction) 'native-xpui-preimage')
$xpui=Join-Path $vendor 'FakeSpotify\Apps\xpui'
$after=Get-CustomAppUpdateTreeSnapshotV010 -Root $xpui
$sealed=Get-ApprovedNativeOutputProofPathV037 -Paths $paths -TransactionId $tx
Assert-MultiV045 ([IO.File]::Exists($sealed) -and
 [int64](Get-Item $sealed).Length -lt 32768) 'MULTIFILE_RECEIPT_SEALED_SIZE_LIMIT'
$terminal=Invoke-ApprovedNativeRetainedTerminalV039 @args
Assert-MultiV045 ([bool]$terminal.ok -and
 [string]$terminal.phase -ceq 'committed-retained' -and
 [int64]$terminal.terminal_revision -eq 9 -and
 [bool]$terminal.all_backups_preserved) 'MULTIFILE_TERMINAL_NOT_DURABLE'
$terminalHead=[string]$terminal.terminal_entry_sha256
$session=Open-CustomAppUserTxnStoreV010 -Name ([string]$item.name) -LivePath ([string]$fixture.live) -HostedCiRoot $userRoot
try{
 $done=Commit-ApprovedNativeRetainedUserLedgerV040 -Session $session @args
 Assert-MultiV045 ([bool]$done.ok -and [bool]$done.consumption_durable -and
  [bool]$done.claim_retired -and [bool]$done.backup_objects_retained) 'MULTIFILE_LEDGER_NOT_DURABLE'
}finally{$session.lock_handle.Dispose()}
$session=Open-CustomAppUserTxnStoreV010 -Name ([string]$item.name) -LivePath ([string]$fixture.live) -HostedCiRoot $userRoot
try{
 Assert-MultiV045 ($null-eq$session.state.active -and
 @($session.state.consumed) -ccontains $token) 'FRESH_MULTIFILE_LEDGER_NOT_CONSUMED'
}finally{$session.lock_handle.Dispose()}
$post=Read-ApprovedNativeFullOutputReceiptV037 @args
$j=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $env:RUNNER_TEMP -StoreDirectory ([string]$paths.journal)
$persist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot ([string]$fixture.local) -AppDataRoot ([string]$fixture.roaming)
Assert-MultiV045 ([bool]$post.ok -and [string]$post.phase -ceq 'committed-retained' -and
 [int]$post.exact_official_owned_files -eq @($manifest.owned_files).Count -and
 [string]$j.entry.entry_sha256 -ceq $terminalHead -and
 [string]$j.entry.phase -ceq 'committed-retained' -and
 [string](Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$paths.app_backup)).tree_sha256 -ceq [string]$original.tree_sha256 -and
 [string](Get-CustomAppUpdateTreeSnapshotV010 -Root (Join-Path ([string]$paths.transaction) 'native-xpui-preimage')).tree_sha256 -ceq [string]$before.tree_sha256 -and
 [string](Get-CustomAppUpdateTreeSnapshotV010 -Root $xpui).tree_sha256 -ceq [string]$after.tree_sha256 -and
 [string]$persist.fingerprint -ceq [string]$fixture.initial_persistence_sha256) 'MULTIFILE_FINAL_REVALIDATION_OR_ORIGINAL_BACKUP_CHANGED'
Write-Host 'V045_IVLYRICS_MULTIFILE_RETAINED_TERMINAL_AND_DPAPI_LEDGER_PASS'
Write-Host 'V045_IVLYRICS_ORIGINAL_APP_XPUI_SPOTIFY_GUARD_PRESERVED_PASS'
Write-Host 'V045_IVLYRICS_GITHUB_HOSTED_ONLY_NO_USER_PROFILE_NO_PRODUCTION_AUTHORITY_PASS'
