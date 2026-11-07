# Fresh PowerShell process, no V029 HMAC key and no remote network:
# independent after-crash recovery from original V010 central journal +
# V030 DPAPI backup proof + real Addon Manager persistence inventory.
param([Parameter(Mandatory=$true)][string]$WorkRoot,
      [Parameter(Mandatory=$true)][string]$Name,
      [Parameter(Mandatory=$true)][string]$TokenId,
      [Parameter(Mandatory=$true)][string]$ReceiptStore,
      [Parameter(Mandatory=$true)][string]$TransactionId,
      [Parameter(Mandatory=$true)][string]$OriginalAddonPath)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
foreach($file in @(
  'validation/custom-app-remote-source-contract-v0.1.0/custom-app-remote-source-contract.ps1',
  'validation/custom-app-stage-acquisition-contract-v0.1.0/custom-app-stage-acquisition.ps1',
  'validation/custom-app-local-runtime-baseline-v0.1.0/custom-app-local-runtime-baseline.ps1',
  'validation/custom-app-update-transaction-protocol-v0.1.0/custom-app-update-transaction.ps1',
  'validation/custom-app-production-atomic-live-swap-v0.1.0/custom-app-production-atomic-live-swap.ps1',
  'validation/custom-app-production-crash-recovery-journal-v0.1.0/custom-app-production-crash-recovery-journal.ps1',
  'validation/custom-app-production-pre-apply-preparation-v0.1.0/custom-app-production-pre-apply-preparation.ps1',
  'validation/approved-live-hmac-consumed-stage/approved-live-hmac-stage.ps1',
  'validation/approved-hmac-to-prepared-central-journal/approved-prepared-journal.ps1',
  'validation/approved-real-persistence-adapter/real-addon-persistence-core.ps1',
  'validation/approved-real-persistence-adapter/approved-real-persistence-journal.ps1',
  'validation/approved-real-native-journaled-swap-recovery/approved-native-journal-saga.ps1'
)){
    . (Join-Path $root $file)
}
$script:Version='0.6.5-r17'
. (Get-ExactAddonPersistenceFunctionsV031 -OriginalAddonPath $OriginalAddonPath)
$r=Invoke-ApprovedNativeJournalRecoveryV032 -WorkRoot $WorkRoot -Name $Name -TokenId $TokenId -ReceiptStore $ReceiptStore -TransactionId $TransactionId
if(-not[bool]$r.ok -or
   [string]$r.phase -cne 'rollback-complete' -or
   -not[bool]$r.old_app_restored_byte_exact -or
   -not[bool]$r.persistence_fingerprint_unchanged -or
   [bool]$r.production_mutation_authorized){
   throw ('V032_FRESH_PROCESS_CENTRAL_CAS_EXACT_ROLLBACK_FAILED:'+ [string]$r.reason)
}
Write-Host 'V032_FRESH_PROCESS_NO_ISSUER_KEY_REAL_ADDON_BACKUP_ROLLBACK_COMPLETE_PASS'
