# Reuse one frozen V032 real-source E2E run; add only readback and tamper tests.
param([string]$OriginalAddonPath,[string]$OfficialExecutable)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot '..\approved-real-native-journaled-swap-recovery\test-approved-native-journal-saga.ps1') -OriginalAddonPath $OriginalAddonPath -OfficialExecutable $OfficialExecutable
function Assert-V033([bool]$Good,[string]$Reason){if(-not$Good){throw ('V033_TEST_'+$Reason)}}
$child=Join-Path $PSScriptRoot 'read-applied-fresh-process-v033.ps1'
$argv=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$child,
 '-WorkRoot',[string]$success.work,'-Name',[string]$item.name,
 '-TokenId',[string]$success.token_id,'-ReceiptStore',[string]$receiptStore,
 '-TransactionId',[string]$success.prepared.transaction_id,
 '-VendorPrivateRoot',[string]$officialRoot,
 '-OfficialExecutable',[string]$OfficialExecutable,
 '-OriginalAddonPath',[string]$OriginalAddonPath)
$head=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $env:RUNNER_TEMP -StoreDirectory ([string]$p.journal)
Assert-V033 ([string]$head.entry.phase -ceq 'apply-verified' -and [int64]$head.revision -eq 7) 'NO_VERIFIED_HEAD'
& powershell.exe @argv
Assert-V033 ($LASTEXITCODE -eq 0) 'FRESH_READBACK_DENIED'
$xpui=Join-Path $officialRoot 'FakeSpotify\Apps\xpui'
$sentinel=Join-Path $xpui 'user-settings-dont-change.dat'
$target=Join-Path $xpui ('spicetify-routes-'+[string]$item.name+'.js')
Assert-V033 ([IO.File]::Exists($sentinel) -and [IO.File]::Exists($target)) 'ISOLATED_FILES_MISSING'
[IO.File]::WriteAllText($sentinel,'V033_TAMPERED_FOREIGN_STATE')
& powershell.exe @argv
Assert-V033 ($LASTEXITCODE -ne 0) 'NON_TARGET_TAMPER_NOT_REJECTED'
[IO.File]::WriteAllText($sentinel,'V026_PROTECTED_USER_STATE')
[IO.File]::AppendAllText($target,'/*V033_TAMPER_VENDOR_TARGET*/')
& powershell.exe @argv
Assert-V033 ($LASTEXITCODE -ne 0) 'TARGET_TAMPER_NOT_REJECTED'
$end=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $env:RUNNER_TEMP -StoreDirectory ([string]$p.journal)
Assert-V033 ([string]$end.entry.entry_sha256 -ceq [string]$head.entry.entry_sha256 -and
 [int64]$end.revision -eq 7) 'READ_ONLY_AUDIT_CHANGED_CENTRAL_JOURNAL'
Write-Host 'V033_INDEPENDENT_APPLY_AND_BOTH_TAMPER_REJECTIONS_PASS'
Write-Host 'V033_NO_COMMIT_NO_CLEANUP_NO_REAL_SPOTIFY_NO_PRODUCTION_MUTATION_PASS'
