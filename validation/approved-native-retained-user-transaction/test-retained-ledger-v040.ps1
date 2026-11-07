# V040: one official native update, reuse V039 terminal, retire the same
# signed TokenId into the normal DPAPI user ledger, and prove crash/restart.
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
. (Join-Path $PSScriptRoot 'native-retained-ledger-v040.ps1')
function Assert-V040([bool]$c,[string]$why){if(-not$c){throw ('V040_TEST_'+$why)}}
$f=Create-V032PreparedCase 'v040-normal-ledger-retained-once'
$vendor=Join-Path $env:RUNNER_TEMP ('v032-official-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
$userRoot=Join-Path $env:RUNNER_TEMP ('v040-protected-ledger-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
[IO.Directory]::CreateDirectory($userRoot)|Out-Null
$tx=[string]$f.prepared.transaction_id
$token=[string]$f.token_id
$args=@{
 WorkRoot=$f.work;Name=[string]$item.name;TokenId=$token
 ReceiptStore=$receiptStore;TransactionId=$tx
 VendorPrivateRoot=$vendor;OfficialExecutable=$OfficialExecutable
}
$session=Open-CustomAppUserTxnStoreV010 -Name ([string]$item.name) -LivePath $f.live -HostedCiRoot $userRoot -Initialize
try{
 $reservation=Reserve-CustomAppUserTxnIdV010 -Session $session -ConsumptionId $token -TransactionId $tx -Nonce ([Guid]::NewGuid().ToString('N'))
 Assert-V040 ([bool]$reservation.ok -and [bool]$reservation.active -and
   [long]$session.state.revision -eq 1 -and
   [string]$session.state.active.consumption_id -ceq $token) 'SIGNED_ID_NOT_RESERVED_BEFORE_NATIVE_WRITE'
 # Never retire a user claim before fully verified terminal.
 $early=Commit-ApprovedNativeRetainedUserLedgerV040 -Session $session @args
 Assert-V040 (-not[bool]$early.ok -and
   [string]$early.reason -ceq 'V040_NOT_VERIFIED_V039_RETAINED_TERMINAL' -and
   $null-ne$session.state.active) 'NONTERMINAL_ALLOWED_CLAIM_RETIREMENT'
}finally{$session.lock_handle.Dispose()}
$applied=Invoke-ApprovedNativeXpuiEscrowApplyV034 -Item $item -Acquired $acquired -Prepared $f.prepared -ReceiptStore $receiptStore -OfficialExecutable $OfficialExecutable -VendorPrivateRoot $vendor
Assert-V040 ([bool]$applied.ok -and [string]$applied.phase -ceq 'apply-verified' -and
  [int64]$applied.journal_revision -eq 8) 'REAL_OFFICIAL_NATIVE_RESULT_UNVERIFIED'
$nativeSeal=Save-ApprovedNativeFullOutputReceiptV037 @args
Assert-V040 ([bool]$nativeSeal.ok -and [bool]$nativeSeal.entire_official_output_verified -and
 [bool]$nativeSeal.manifest_scoped_output_verified -and
 [int]$nativeSeal.exact_official_owned_files -eq 4 -and
 [int]$nativeSeal.declared_extension_files -eq 1 -and
 [int]$nativeSeal.declared_asset_files -eq 0 -and
 [string]$nativeSeal.source_tree_sha256 -ceq [string]$acquired.runtime_tree_sha256 -and
 [string]$nativeSeal.manifest_owned_set_sha256 -cmatch '^[a-f0-9]{64}$') 'V045_MANIFEST_SEALED_CHAIN_NOT_DURABLE'
# V045 regression: once the V037 schema-2 manifest/native receipt exists,
# changed staged assets or a changed generated extension deny terminal
# without a central journal transition or user-ledger mutation.
$sourceFile=Join-Path ([string]$acquired.stage_path) 'manifest.json'
$sourceOrig=[IO.File]::ReadAllBytes($sourceFile)
[IO.File]::AppendAllText($sourceFile,' ')
try{
 $tampered=Read-ApprovedNativeFullOutputReceiptV037 @args
 Assert-V040 (-not[bool]$tampered.ok -and
   -not[bool]$tampered.final_commit_authorized) 'SOURCE_MANIFEST_CHANGED_BUT_DPAPI_ACCEPTED'
}finally{[IO.File]::WriteAllBytes($sourceFile,$sourceOrig)}
$xpuiExt=Join-Path (Join-Path $vendor 'FakeSpotify\Apps\xpui') ('extensions\'+[string]$item.name+'\extension.js')
$extensionOriginal=[IO.File]::ReadAllBytes($xpuiExt)
[IO.File]::AppendAllText($xpuiExt,'/*V045_TAMPER*/')
try{
 $denied=Invoke-ApprovedNativeRetainedTerminalV039 @args
 Assert-V040 (-not[bool]$denied.ok -and -not[bool]$denied.cleanup_performed) 'TAMPERED_MANIFEST_OUTPUT_TERMINAL_ACCEPTED'
}finally{[IO.File]::WriteAllBytes($xpuiExt,$extensionOriginal)}
$still=Read-ApprovedNativeFullOutputReceiptV037 @args
Assert-V040 ([bool]$still.ok -and [bool]$still.manifest_scoped_output_verified) 'RESTORED_V045_NATIVE_EVIDENCE_INVALID'
Write-Host 'V045_MANIFEST_SOURCE_AND_GENERATED_EXTENSION_TAMPER_REJECTED_BEFORE_TERMINAL_PASS'
$terminal=Invoke-ApprovedNativeRetainedTerminalV039 @args
Assert-V040 ([bool]$terminal.ok -and [string]$terminal.phase -ceq 'committed-retained' -and
  [int64]$terminal.terminal_revision -eq 9 -and [bool]$terminal.all_backups_preserved) 'NATIVE_RETAINED_TERMINAL_FAILED'
$p=Get-ApprovedNativeRecoveryPathsV032 -WorkRoot $f.work -Name ([string]$item.name) -TokenId $token
$head=[string](Read-CustomAppProductionCrashJournalV010 -AllowedRoot $env:RUNNER_TEMP -StoreDirectory ([string]$p.journal)).entry.entry_sha256
$orig=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$p.app_backup)
$pre=Get-CustomAppUpdateTreeSnapshotV010 -Root (Join-Path ([string]$p.transaction) 'native-xpui-preimage')
$xpui=Get-CustomAppUpdateTreeSnapshotV010 -Root (Join-Path $vendor 'FakeSpotify\Apps\xpui')
$session=Open-CustomAppUserTxnStoreV010 -Name ([string]$item.name) -LivePath $f.live -HostedCiRoot $userRoot
try{
 $wrong=@{};foreach($k in $args.Keys){$wrong[$k]=$args[$k]}
 $wrong.TokenId=('0'*64)
 $bad=Commit-ApprovedNativeRetainedUserLedgerV040 -Session $session @wrong
 Assert-V040 (-not[bool]$bad.ok -and $null-ne$session.state.active) 'WRONG_ID_CLEARED_LEDGER'
 $wrong.TransactionId=('0'*64);$wrong.TokenId=$token
 $bad=Commit-ApprovedNativeRetainedUserLedgerV040 -Session $session @wrong
 Assert-V040 (-not[bool]$bad.ok -and $null-ne$session.state.active) 'WRONG_TX_CLEARED_LEDGER'
 $before=(Get-FileHash -LiteralPath ([string]$session.paths.state) -Algorithm SHA256).Hash
 $stop=Commit-ApprovedNativeRetainedUserLedgerV040 -Session $session @args -FailurePoint 'before-ledger-replace'
 Assert-V040 (-not[bool]$stop.ok -and
  [string]$stop.reason -ceq 'V040_TEST_INTERRUPTED_BEFORE_ATOMIC_CONSUMPTION' -and
  (Get-FileHash -LiteralPath ([string]$session.paths.state) -Algorithm SHA256).Hash -ceq $before -and
  [IO.File]::Exists([string]$session.paths.pending)) 'INTERRUPTION_BEFORE_REPLACE_CHANGED_CANONICAL_STATE'
}finally{$session.lock_handle.Dispose()}
# Independent reopen of the old durable store rejects unpromoted pending
# while protecting the same active claim; existing code clears only pending.
$session=Open-CustomAppUserTxnStoreV010 -Name ([string]$item.name) -LivePath $f.live -HostedCiRoot $userRoot
try{
 Assert-V040 ([long]$session.state.revision -eq 1 -and $null-ne$session.state.active -and
   -not[IO.File]::Exists([string]$session.paths.pending)) 'PENDING_CRASH_NOT_RECOVERED_SAFELY'
 $stop=Commit-ApprovedNativeRetainedUserLedgerV040 -Session $session @args -FailurePoint 'after-ledger-replace-before-return'
 Assert-V040 (-not[bool]$stop.ok -and
  [string]$stop.reason -ceq 'V040_TEST_INTERRUPTED_AFTER_ATOMIC_CONSUMPTION' -and
  [long](Read-CustomAppUserTxnStateV010 -Paths $session.paths).revision -eq 2) 'POST_REPLACE_DURABLE_STATE_NOT_PRESENT'
}finally{$session.lock_handle.Dispose()}
$session=Open-CustomAppUserTxnStoreV010 -Name ([string]$item.name) -LivePath $f.live -HostedCiRoot $userRoot
try{
 Assert-V040 ([long]$session.state.revision -eq 2 -and
   $null-eq$session.state.active -and
   @($session.state.consumed).Count -eq 1 -and
   @($session.state.consumed) -ccontains $token) 'FRESH_SESSION_CONSUMPTION_NOT_PERSISTED'
 $replay=Commit-ApprovedNativeRetainedUserLedgerV040 -Session $session @args
 Assert-V040 (-not[bool]$replay.ok -and
   [string]$replay.reason -ceq 'V040_NO_MATCHING_ACTIVE_SINGLE_USE_RESERVATION') 'CONSUMED_ID_RETIRED_TWICE'
}finally{$session.lock_handle.Dispose()}
$child=Join-Path $PSScriptRoot 'check-native-ledger-fresh-process-v040.ps1'
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $child -Name ([string]$item.name) -LivePath $f.live -HostedCiRoot $userRoot -ConsumedToken $token -TransactionId $tx
Assert-V040 ($LASTEXITCODE -eq 0) 'INDEPENDENT_DPAPI_LEDGER_READBACK_FAILED'
$session=Open-CustomAppUserTxnStoreV010 -Name ([string]$item.name) -LivePath $f.live -HostedCiRoot $userRoot
try{
 # Verify that a *new, different* ID can be stored in the existing
 # consumed ledger. This issues NO update authorization or network call.
 $nextId=Get-CustomAppUserTxnSha256V010 ([Guid]::NewGuid().ToString('N'))
 $nextTx=Get-CustomAppUserTxnSha256V010 ([Guid]::NewGuid().ToString('N'))
 $canReserve=Reserve-CustomAppUserTxnIdV010 -Session $session -ConsumptionId $nextId -TransactionId $nextTx -Nonce ([Guid]::NewGuid().ToString('N'))
 Assert-V040 ([bool]$canReserve.ok -and [long]$session.state.revision -eq 3 -and
   @($session.state.consumed) -ccontains $token -and
   [string]$session.state.active.consumption_id -ceq $nextId) 'NEXT_DIFFERENT_ID_CANNOT_RESERVE_AFTER_VERIFIED_TERMINAL'
}finally{$session.lock_handle.Dispose()}
$journal=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $env:RUNNER_TEMP -StoreDirectory ([string]$p.journal)
$persist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $f.local -AppDataRoot $f.roaming
Assert-V040 ([string]$journal.entry.entry_sha256 -ceq $head -and
 [string]$journal.entry.phase -ceq 'committed-retained' -and
 [string](Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$p.app_backup)).tree_sha256 -ceq [string]$orig.tree_sha256 -and
 [string](Get-CustomAppUpdateTreeSnapshotV010 -Root (Join-Path ([string]$p.transaction) 'native-xpui-preimage')).tree_sha256 -ceq [string]$pre.tree_sha256 -and
 [string](Get-CustomAppUpdateTreeSnapshotV010 -Root (Join-Path $vendor 'FakeSpotify\Apps\xpui')).tree_sha256 -ceq [string]$xpui.tree_sha256 -and
 [string]$persist.fingerprint -ceq [string]$f.initial_persistence_sha256) 'CLAIM_RETIREMENT_DID_NOT_PRESERVE_BACKUPS_OR_JOURNAL'
Write-Host 'V045_V037_MANIFEST_SCOPE_V039_TERMINAL_V040_LEDGER_ATOMIC_CHAIN_PASS'
Write-Host 'V040_REAL_OFFICIAL_NATIVE_TERMINAL_SINGLE_USE_LEDGER_BOUND_PASS'
Write-Host 'V040_PRETERMINAL_WRONG_ID_WRONG_TX_DENIED_PASS'
Write-Host 'V040_DPAPI_BEFORE_AFTER_REPLACE_CRASH_RESUME_PASS'
Write-Host 'V040_INDEPENDENT_FRESH_PROCESS_REPLAY_DENIED_PASS'
Write-Host 'V040_NEXT_DIFFERENT_ID_RESERVABLE_OLD_CONSUMED_PASS'
Write-Host 'V040_APP_SPOTIFY_GUARD_XPUI_BACKUPS_NOT_CHANGED_PASS'
Write-Host 'V040_FIXTURE_ONLY_NO_REAL_SPOTIFY_NO_PRODUCTION_AUTO_ENABLE_PASS'
