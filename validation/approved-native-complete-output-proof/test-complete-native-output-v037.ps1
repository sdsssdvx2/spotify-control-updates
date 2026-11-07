# V037 one real official CLI native apply; no old three-case suite replay.
param([string]$OriginalAddonPath,[string]$OfficialExecutable)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot '..\approved-real-native-journaled-swap-recovery\test-approved-native-journal-saga.ps1') -OriginalAddonPath $OriginalAddonPath -OfficialExecutable $OfficialExecutable -LibraryOnly
. (Join-Path $PSScriptRoot '..\approved-real-native-verified-readback\verified-official-readback-v033.ps1')
. (Join-Path $PSScriptRoot '..\approved-real-native-xpui-crash-restore\native-xpui-escrow-recovery.ps1')
. (Join-Path $PSScriptRoot 'full-native-output-proof-v037.ps1')
function Assert-V037([bool]$ok,[string]$why){if(-not$ok){throw ('V037_TEST_'+$why)}}
$f=Create-V032PreparedCase 'v037-entire-native-proof'
$vendor=Join-Path $env:RUNNER_TEMP ('v032-official-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
$applied=Invoke-ApprovedNativeXpuiEscrowApplyV034 -Item $item -Acquired $acquired -Prepared $f.prepared -ReceiptStore $receiptStore -OfficialExecutable $OfficialExecutable -VendorPrivateRoot $vendor
Assert-V037 ([bool]$applied.ok -and [string]$applied.phase -ceq 'apply-verified') 'OFFICIAL_NATIVE_APPLY_NOT_VERIFIED'
$args=@{WorkRoot=$f.work;Name=[string]$item.name;TokenId=$f.token_id
 ReceiptStore=$receiptStore;TransactionId=[string]$f.prepared.transaction_id
 VendorPrivateRoot=$vendor;OfficialExecutable=$OfficialExecutable}
$seal=Save-ApprovedNativeFullOutputReceiptV037 @args
Assert-V037 ([bool]$seal.ok -and [int]$seal.exact_official_owned_files -eq 4 -and
 [bool]$seal.entire_official_output_verified -and
 -not[bool]$seal.final_commit_authorized) 'SIGNED_COMPLETE_VENDOR_RESULT_NOT_DURABLE'
$p=Get-ApprovedNativeRecoveryPathsV032 -WorkRoot $f.work -Name ([string]$item.name) -TokenId $f.token_id
$j=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $env:RUNNER_TEMP -StoreDirectory ([string]$p.journal)
$head=[string]$j.entry.entry_sha256
$child=Join-Path $PSScriptRoot 'read-entire-output-fresh-process.ps1'
$argv=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$child,
 '-WorkRoot',$f.work,'-Name',[string]$item.name,'-TokenId',[string]$f.token_id,
 '-ReceiptStore',$receiptStore,'-TransactionId',[string]$f.prepared.transaction_id,
 '-VendorPrivateRoot',$vendor,'-OfficialExecutable',$OfficialExecutable,
 '-OriginalAddonPath',$OriginalAddonPath)
& powershell.exe @argv
Assert-V037 ($LASTEXITCODE -eq 0) 'FRESH_PROCESS_KEYLESS_ALL_OUTPUT_DENIED'
$xpui=Join-Path $vendor 'FakeSpotify\Apps\xpui'
$css=Join-Path $xpui ('spicetify-routes-'+[string]$item.name+'.css')
$originalCss=[IO.File]::ReadAllBytes($css)
[IO.File]::AppendAllText($css,'V037_TAMPER_CSS')
& powershell.exe @argv
Assert-V037 ($LASTEXITCODE -ne 0) 'CSS_NOT_BOUND_IN_RECEIPT'
[IO.File]::WriteAllBytes($css,$originalCss)
$extension=Join-Path (Join-Path $xpui ('extensions\'+[string]$item.name)) 'extension.js'
$oldExtension=[IO.File]::ReadAllBytes($extension)
[IO.File]::AppendAllText($extension,'V037_TAMPER_EXTENSION')
& powershell.exe @argv
Assert-V037 ($LASTEXITCODE -ne 0) 'EXTENSION_NOT_BOUND_IN_RECEIPT'
[IO.File]::WriteAllBytes($extension,$oldExtension)
$foreign=Join-Path $xpui 'user-settings-dont-change.dat'
$oldForeign=[IO.File]::ReadAllBytes($foreign)
[IO.File]::AppendAllText($foreign,'V037_CONCURRENT_USER_EDIT')
& powershell.exe @argv
Assert-V037 ($LASTEXITCODE -ne 0) 'FOREIGN_XPUI_EDIT_NOT_REJECTED'
[IO.File]::WriteAllBytes($foreign,$oldForeign)
& powershell.exe @argv
Assert-V037 ($LASTEXITCODE -eq 0) 'CLEAN_RECEIPT_CANNOT_REVERIFY'
$end=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $env:RUNNER_TEMP -StoreDirectory ([string]$p.journal)
Assert-V037 ([string]$end.entry.entry_sha256 -ceq $head -and
 [string]$end.entry.phase -ceq 'apply-verified' -and
 [IO.Directory]::Exists([string]$p.app_backup)) 'SEALED_EVIDENCE_CHANGED_CENTRAL_JOURNAL_OR_ROLLBACK'
$sealed=Get-ApprovedNativeOutputProofPathV037 -Paths $p -TransactionId ([string]$f.prepared.transaction_id)
$data=[IO.File]::ReadAllBytes($sealed)
$data[$data.Length-1]=$data[$data.Length-1] -bxor 1
[IO.File]::WriteAllBytes($sealed,$data)
$bad=Read-ApprovedNativeFullOutputReceiptV037 @args
Assert-V037 (-not[bool]$bad.ok -and -not[bool]$bad.final_commit_authorized) 'TAMPERED_OUTPUT_DPAPI_RECEIPT_ACCEPTED'
Write-Host 'V037_REAL_OFFICIAL_CLI_ALL_FOUR_OWNED_OUTPUTS_BOUND_AND_SEALED_PASS'
Write-Host 'V037_KEYLESS_INDEPENDENT_CSS_EXTENSION_FOREIGN_TAMPER_REJECTED_PASS'
Write-Host 'V037_SEALED_DPAPI_TAMPER_REFUSED_V010_HEAD_UNCHANGED_PASS'
Write-Host 'V037_NO_REAL_SPOTIFY_NO_CLEANUP_NO_TERMINAL_COMMIT_AUTHORITY_PASS'
