# Separate PowerShell: no issuer HMAC key, exact DPAPI+CAS+XPUI recovery.
param([string]$WorkRoot,[string]$Name,[string]$TokenId,
 [string]$ReceiptStore,[string]$TransactionId,[string]$VendorPrivateRoot,
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
   'validation/approved-real-native-xpui-crash-restore/native-xpui-escrow-recovery.ps1'
 )){. (Join-Path $root $f)}
 $script:Version='0.6.5-r17'
 . (Get-ExactAddonPersistenceFunctionsV031 -OriginalAddonPath $OriginalAddonPath)
 $r=Invoke-ApprovedNativeXpuiEscrowRecoveryV034 -WorkRoot $WorkRoot -Name $Name -TokenId $TokenId -ReceiptStore $ReceiptStore -TransactionId $TransactionId -VendorPrivateRoot $VendorPrivateRoot
 if(-not[bool]$r.ok -or [string]$r.phase -cne 'rollback-complete' -or
   -not[bool]$r.native_xpui_restored_byte_exact -or
   -not[bool]$r.original_app_restored_byte_exact -or
   [bool]$r.production_mutation_authorized){throw ('V034_KEYLESS_RECOVERY_DENIED_'+[string]$r.reason)}
 Write-Host 'V034_FRESH_PROCESS_KEYLESS_POST_VENDOR_REAL_CLI_XPUI_AND_APP_RECOVERED_PASS'
 exit 0
}catch{Write-Host ('V034_FRESH_PROCESS_FAILURE_'+[string]$_.Exception.Message);exit 17}
