# V035 targeted genuine CLI once; V032 setup reused library-only.
# Crash-window atomicity: terminal rollback-complete only after original app,
# guarded Spotify data AND entire prelaunch XPUI are byte-exact.
param([Parameter(Mandatory=$true)][string]$OriginalAddonPath,
      [Parameter(Mandatory=$true)][string]$OfficialExecutable)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot '..\approved-real-native-journaled-swap-recovery\test-approved-native-journal-saga.ps1') -OriginalAddonPath $OriginalAddonPath -OfficialExecutable $OfficialExecutable -LibraryOnly
. (Join-Path $PSScriptRoot '..\approved-real-native-xpui-crash-restore\native-xpui-escrow-recovery.ps1')
function Assert-V035([bool]$pass,[string]$reason){if(-not$pass){throw ('V035_COMPOSITE_TEST_'+$reason)}}
$fixture=Create-V032PreparedCase 'v035-composite-once'
$nativeRoot=Join-Path $env:RUNNER_TEMP ('v032-official-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
$failed=Invoke-ApprovedNativeXpuiEscrowApplyV034 -Item $item -Acquired $acquired -Prepared $fixture.prepared -ReceiptStore $receiptStore -OfficialExecutable $OfficialExecutable -VendorPrivateRoot $nativeRoot -FailurePoint 'after-official-cli-before-pending'
Assert-V035 (-not[bool]$failed.ok -and [string]$failed.phase -ceq 'apply-starting') 'GENUINE_VENDOR_CRASH_NOT_REPRODUCED'
$p=Get-ApprovedNativeRecoveryPathsV032 -WorkRoot $fixture.work -Name ([string]$item.name) -TokenId $fixture.token_id
$tx=[string]$fixture.prepared.transaction_id
$xpui=Join-Path $nativeRoot 'FakeSpotify\Apps\xpui'
$original=Read-ApprovedNativeXpuiEscrowV034 -Paths $p -TransactionId $tx
$before=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$original.preimage_path)
$afterVendor=Get-CustomAppUpdateTreeSnapshotV010 -Root $xpui
Assert-V035 ([string]$afterVendor.tree_sha256 -cne [string]$before.tree_sha256) 'NATIVE_XPUI_NEVER_CHANGED'
$baseArgs=@{
 WorkRoot=$fixture.work;Name=[string]$item.name;TokenId=$fixture.token_id
 ReceiptStore=$receiptStore;TransactionId=$tx;VendorPrivateRoot=$nativeRoot
}
# App recovered, XPUI still modified: journal MUST say rollback-required.
$first=Invoke-ApprovedNativeXpuiEscrowRecoveryV034 @baseArgs -FailurePoint 'after-app-before-xpui'
$j=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $env:RUNNER_TEMP -StoreDirectory ([string]$p.journal)
$oldApp=Get-CustomAppUpdateTreeSnapshotV010 -Root $fixture.live
Assert-V035 (-not[bool]$first.ok -and [string]$j.entry.phase -ceq 'rollback-required' -and
 [string]$oldApp.tree_sha256 -ceq [string]$fixture.initial_tree_sha256 -and
 (Get-CustomAppUpdateTreeSnapshotV010 -Root $xpui).tree_sha256 -cne [string]$before.tree_sha256) 'PREMATURE_ROLLBACK_COMPLETE_AFTER_APP'
# A foreign file written during recovery must never be overwritten or erased.
$foreign=Join-Path $xpui 'user-settings-dont-change.dat'
$foreignBefore=[IO.File]::ReadAllBytes($foreign)
[IO.File]::WriteAllText($foreign,'V035_CONCURRENT_FOREIGN_USER_EDIT')
$denied=Invoke-ApprovedNativeXpuiEscrowRecoveryV034 @baseArgs
$j=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $env:RUNNER_TEMP -StoreDirectory ([string]$p.journal)
Assert-V035 (-not[bool]$denied.ok -and
 [string]$j.entry.phase -ceq 'rollback-required' -and
 [IO.File]::ReadAllText($foreign) -ceq 'V035_CONCURRENT_FOREIGN_USER_EDIT' -and
 -not[IO.Directory]::Exists((Join-Path ([string]$p.transaction) 'native-xpui-after-crash-retained'))) 'FOREIGN_USER_EDIT_WAS_CLOBBERED'
[IO.File]::WriteAllBytes($foreign,$foreignBefore)
# XPUI renamed to quarantine, crash before copy: journal remains pending.
$second=Invoke-ApprovedNativeXpuiEscrowRecoveryV034 @baseArgs -FailurePoint 'after-xpui-quarantine-before-copy'
$j=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $env:RUNNER_TEMP -StoreDirectory ([string]$p.journal)
$q=Join-Path ([string]$p.transaction) 'native-xpui-after-crash-retained'
Assert-V035 (-not[bool]$second.ok -and [string]$j.entry.phase -ceq 'rollback-required' -and
 -not[IO.Directory]::Exists($xpui) -and [IO.Directory]::Exists($q)) 'PREMATURE_COMPLETE_AFTER_QUARANTINE'
# XPUI recreated exactly, crash before terminal CAS: still rollback-required.
$third=Invoke-ApprovedNativeXpuiEscrowRecoveryV034 @baseArgs -FailurePoint 'after-xpui-copy-before-journal'
$j=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $env:RUNNER_TEMP -StoreDirectory ([string]$p.journal)
Assert-V035 (-not[bool]$third.ok -and [string]$j.entry.phase -ceq 'rollback-required' -and
 (Get-CustomAppUpdateTreeSnapshotV010 -Root $xpui).tree_sha256 -ceq [string]$before.tree_sha256) 'PREMATURE_COMPLETE_AFTER_XPUI_RECREATION'
# Finally finish in a truly independent keyless Windows PowerShell process.
$child=Join-Path $PSScriptRoot '..\approved-real-native-xpui-crash-restore\recover-xpui-fresh-process.ps1'
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $child -WorkRoot $fixture.work -Name ([string]$item.name) -TokenId $fixture.token_id -ReceiptStore $receiptStore -TransactionId $tx -VendorPrivateRoot $nativeRoot -OriginalAddonPath $OriginalAddonPath
Assert-V035 ($LASTEXITCODE -eq 0) 'FRESH_PROCESS_COMPLETION_FAILED'
$j=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $env:RUNNER_TEMP -StoreDirectory ([string]$p.journal)
$sp=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $fixture.local -AppDataRoot $fixture.roaming
Assert-V035 ([string]$j.entry.phase -ceq 'rollback-complete' -and
 [string]$sp.fingerprint -ceq [string]$fixture.initial_persistence_sha256 -and
 (Get-CustomAppUpdateTreeSnapshotV010 -Root $xpui).tree_sha256 -ceq [string]$before.tree_sha256 -and
 (Get-CustomAppUpdateTreeSnapshotV010 -Root $fixture.live).tree_sha256 -ceq [string]$fixture.initial_tree_sha256) 'COMPOSITE_RECOVERY_FINAL_CAS_INVALID'
$head=[string]$j.entry.entry_sha256
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $child -WorkRoot $fixture.work -Name ([string]$item.name) -TokenId $fixture.token_id -ReceiptStore $receiptStore -TransactionId $tx -VendorPrivateRoot $nativeRoot -OriginalAddonPath $OriginalAddonPath
Assert-V035 ($LASTEXITCODE -eq 0 -and
  [string](Read-CustomAppProductionCrashJournalV010 -AllowedRoot $env:RUNNER_TEMP -StoreDirectory ([string]$p.journal)).entry.entry_sha256 -ceq $head) 'FRESH_PROCESS_REPLAY_NOT_IDEMPOTENT'
# Legacy prematurely completed state with later XPUI edit is denied, not silently overwritten.
$route=Join-Path $xpui ('spicetify-routes-'+[string]$item.name+'.js')
[IO.File]::WriteAllText($route,'V035_FOREIGN_OR_UNKNOWN_POST_TERMINAL_CHANGE')
$denyTerminal=Invoke-ApprovedNativeXpuiEscrowRecoveryV034 @baseArgs
Assert-V035 (-not[bool]$denyTerminal.ok -and
 [IO.File]::ReadAllText($route) -ceq 'V035_FOREIGN_OR_UNKNOWN_POST_TERMINAL_CHANGE' -and
 [string](Read-CustomAppProductionCrashJournalV010 -AllowedRoot $env:RUNNER_TEMP -StoreDirectory ([string]$p.journal)).entry.entry_sha256 -ceq $head) 'POST_TERMINAL_USER_CHANGE_OVERWRITTEN'
Write-Host 'V035_GENUINE_OFFICIAL_CLI_CRASH_AFTER_XPUI_MUTATION_ONCE_PASS'
Write-Host 'V035_ALL_THREE_CRASH_WINDOWS_KEEP_ROLLBACK_REQUIRED_PASS'
Write-Host 'V035_FOREIGN_XPUI_USER_WRITE_REFUSED_AND_PRESERVED_PASS'
Write-Host 'V035_INDEPENDENT_KEYLESS_APP_XPUI_GUARD_COMPOSITE_TERMINAL_CAS_PASS'
Write-Host 'V035_IDEMPOTENT_REPLAY_AND_POST_TERMINAL_UNTRUSTED_EDIT_DENIED_PASS'
Write-Host 'V035_NO_REAL_SPOTIFY_NO_CLEANUP_NO_PRODUCTION_AUTHORITY_PASS'
