# Single new post-vendor crash window. Reuse existing V032 genuine CLI
# setup/sources once, no duplicate standalone full regression.
param([string]$OriginalAddonPath,[string]$OfficialExecutable)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot '..\approved-real-native-journaled-swap-recovery\test-approved-native-journal-saga.ps1') -OriginalAddonPath $OriginalAddonPath -OfficialExecutable $OfficialExecutable
. (Join-Path $PSScriptRoot 'native-xpui-escrow-recovery.ps1')
function Assert-V034([bool]$pass,[string]$why){if(-not$pass){throw ('V034_TEST_'+$why)}}
$fixture=Create-V032PreparedCase 'xpui-after-vendor'
$nativeRoot=Join-Path $env:RUNNER_TEMP ('v032-official-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
$failed=Invoke-ApprovedNativeXpuiEscrowApplyV034 -Item $item -Acquired $acquired -Prepared $fixture.prepared -ReceiptStore $receiptStore -OfficialExecutable $OfficialExecutable -VendorPrivateRoot $nativeRoot -FailurePoint 'after-official-cli-before-pending'
Assert-V034 (-not[bool]$failed.ok -and
  [string]$failed.phase -ceq 'apply-starting' -and
  [bool]$failed.independent_recovery_required -and
  -not[bool]$failed.production_mutation_authorized) 'EXPECTED_POST_VENDOR_STOP_NOT_OBSERVED'
$p=Get-ApprovedNativeRecoveryPathsV032 -WorkRoot $fixture.work -Name ([string]$item.name) -TokenId $fixture.token_id
$seal=Read-ApprovedNativeXpuiEscrowV034 -Paths $p -TransactionId ([string]$fixture.prepared.transaction_id)
$xpui=Join-Path $nativeRoot 'FakeSpotify\Apps\xpui'
$before=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$seal.preimage_path)
$afterVendor=Get-CustomAppUpdateTreeSnapshotV010 -Root $xpui
Assert-V034 ([string]$afterVendor.tree_sha256 -cne [string]$before.tree_sha256) 'OFFICIAL_VENDOR_DID_NOT_MUTATE_XPUI'
$recover=Join-Path $PSScriptRoot 'recover-xpui-fresh-process.ps1'
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $recover -WorkRoot $fixture.work -Name ([string]$item.name) -TokenId $fixture.token_id -ReceiptStore $receiptStore -TransactionId ([string]$fixture.prepared.transaction_id) -VendorPrivateRoot $nativeRoot -OriginalAddonPath $OriginalAddonPath
Assert-V034 ($LASTEXITCODE -eq 0) 'INDEPENDENT_XPUI_AND_APP_RESTORE_FAILED'
$restored=Get-CustomAppUpdateTreeSnapshotV010 -Root $xpui
$app=Get-CustomAppUpdateTreeSnapshotV010 -Root $fixture.live
$sp=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $fixture.local -AppDataRoot $fixture.roaming
$j=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $env:RUNNER_TEMP -StoreDirectory ([string]$p.journal)
Assert-V034 ([string]$restored.tree_sha256 -ceq [string]$before.tree_sha256 -and
 [string]$app.tree_sha256 -ceq [string]$fixture.initial_tree_sha256 -and
 [string]$sp.fingerprint -ceq [string]$fixture.initial_persistence_sha256 -and
 [string]$j.entry.phase -ceq 'rollback-complete' -and
 [IO.Directory]::Exists((Join-Path ([string]$p.transaction) 'native-xpui-after-crash-retained'))) 'XPUI_APP_ORIGINAL_BACKUP_NOT_RESTORED'
# A second keyless run is idempotent even after the rename checkpoint.
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $recover -WorkRoot $fixture.work -Name ([string]$item.name) -TokenId $fixture.token_id -ReceiptStore $receiptStore -TransactionId ([string]$fixture.prepared.transaction_id) -VendorPrivateRoot $nativeRoot -OriginalAddonPath $OriginalAddonPath
Assert-V034 ($LASTEXITCODE -eq 0) 'REPEATED_RECOVERY_NOT_IDEMPOTENT'
$end=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $env:RUNNER_TEMP -StoreDirectory ([string]$p.journal)
Assert-V034 ([string]$end.entry.entry_sha256 -ceq [string]$j.entry.entry_sha256) 'REPLAY_CHANGED_JOURNAL'
# Tamper DPAPI after complete to prove no future false trust.
$sealFile=Get-ApprovedNativeXpuiEscrowPathV034 -Paths $p -TransactionId ([string]$fixture.prepared.transaction_id)
$data=[IO.File]::ReadAllBytes($sealFile);$data[$data.Length-1]=$data[$data.Length-1] -bxor 1
[IO.File]::WriteAllBytes($sealFile,$data)
$refused=Invoke-ApprovedNativeXpuiEscrowRecoveryV034 -WorkRoot $fixture.work -Name ([string]$item.name) -TokenId $fixture.token_id -ReceiptStore $receiptStore -TransactionId ([string]$fixture.prepared.transaction_id) -VendorPrivateRoot $nativeRoot
Assert-V034 (-not[bool]$refused.ok -and -not[bool]$refused.production_mutation_authorized) 'TAMPERED_DPAPI_RECEIPT_ACCEPTED'
Write-Host 'V034_POST_OFFICIAL_REAL_NATIVE_PREIMAGE_SEALED_AND_RECOVERED_PASS'
Write-Host 'V034_INDEPENDENT_KEYLESS_XPUI_APP_AND_SPOTIFY_GUARD_BYTE_EXACT_PASS'
Write-Host 'V034_REPEAT_IDEMPOTENT_SEAL_TAMPER_FAIL_CLOSED_NO_CLEANUP_PASS'
Write-Host 'V034_FAKE_XPUI_ONLY_NO_REAL_SPOTIFY_NO_PRODUCTION_AUTHORITY_PASS'
