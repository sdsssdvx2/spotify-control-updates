# Separate process has neither V029 issuer HMAC key nor mutable authorization.
param([string]$WorkRoot,[string]$Name,[string]$TokenId,[string]$ReceiptStore,
 [string]$TransactionId,[string]$VendorPrivateRoot,[string]$OfficialExecutable,
 [string]$OriginalAddonPath)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
try{
 $root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
 foreach($f in @(
  'validation/custom-app-remote-source-contract-v0.1.0/custom-app-remote-source-contract.ps1',
  'validation/custom-app-stage-acquisition-contract-v0.1.0/custom-app-stage-acquisition.ps1',
  'validation/custom-app-local-runtime-baseline-v0.1.0/custom-app-local-runtime-baseline.ps1',
  'validation/custom-app-update-transaction-protocol-v0.1.0/custom-app-update-transaction.ps1',
  'validation/custom-app-production-atomic-live-swap-v0.1.0/custom-app-production-atomic-live-swap.ps1',
  'validation/custom-app-production-crash-recovery-journal-v0.1.0/custom-app-production-crash-recovery-journal.ps1',
  'validation/custom-app-production-pre-apply-preparation-v0.1.0/custom-app-production-pre-apply-preparation.ps1',
  'validation/approved-custom-app-native-scope/approved-scoped-native.ps1',
  'validation/approved-live-hmac-consumed-stage/approved-live-hmac-stage.ps1',
  'validation/approved-hmac-to-prepared-central-journal/approved-prepared-journal.ps1',
  'validation/approved-real-persistence-adapter/real-addon-persistence-core.ps1',
  'validation/approved-real-persistence-adapter/approved-real-persistence-journal.ps1',
  'validation/approved-real-native-journaled-swap-recovery/approved-native-journal-saga.ps1',
  'validation/approved-real-native-verified-readback/verified-official-readback-v033.ps1'
 )){. (Join-Path $root $f)}
 $script:Version='0.6.5-r17'
 . (Get-ExactAddonPersistenceFunctionsV031 -OriginalAddonPath $OriginalAddonPath)
 $r=Test-ApprovedNativeAppliedReadbackV033 -WorkRoot $WorkRoot -Name $Name -TokenId $TokenId -ReceiptStore $ReceiptStore -TransactionId $TransactionId -VendorPrivateRoot $VendorPrivateRoot -OfficialExecutable $OfficialExecutable
 if(-not[bool]$r.ok -or [string]$r.phase -cne 'apply-verified' -or
   [int64]$r.revision -ne 7 -or [bool]$r.final_commit_authorized -or
   [bool]$r.production_mutation_authorized){Write-Host ('V033_REFUSED '+[string]$r.reason);exit 17}
 Write-Host 'V033_INDEPENDENT_KEYLESS_OFFICIAL_APPLY_READBACK_PASS'
 exit 0
}catch{Write-Host ('V033_REFUSED '+[string]$_.Exception.Message);exit 17}
