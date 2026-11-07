# Keyless independent recovery verifier: real generated Addon Manager
# persistence inventory and exact original app / source archive / V010 CAS.
# No network, HMAC issuer, Spotify installation or mutation on this path.
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
  'validation/approved-real-persistence-adapter/approved-real-persistence-journal.ps1'
)){
    . (Join-Path $root $file)
}
$script:Version='0.6.5-r17'
. (Get-ExactAddonPersistenceFunctionsV031 -OriginalAddonPath $OriginalAddonPath)
$recovered=Read-ApprovedRealPersistPreparedV031 -WorkRoot $WorkRoot -Name $Name -TokenId $TokenId -ReceiptStore $ReceiptStore -TransactionId $TransactionId
if(-not[bool]$recovered.ok -or
   [string]$recovered.phase -cne 'prepared' -or
   [int]$recovered.journal_revision -ne 0 -or
   -not[bool]$recovered.genuine_generated_addon_persistence_contract -or
   -not[bool]$recovered.issuer_key_not_needed_for_readback -or
   [bool]$recovered.production_mutation_authorized){
   throw ('V031_INDEPENDENT_REAL_ORIGINAL_SPOTIFY_BACKUP_PROOF_REFUSED:'+ [string]$recovered.reason)
}
Write-Host 'V031_FRESH_PROCESS_REAL_ADDON_GUARDED_PERSISTENCE_BACKUP_NO_HMAC_KEY_PASS'
