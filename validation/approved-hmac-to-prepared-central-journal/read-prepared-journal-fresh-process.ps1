# Independent keyless process: confirm the original consumed V029 permit,
# persisted DPAPI rollback evidence and the existing V010 PREPARED journal.
# It NEVER calls official Spicetify, mutates live apps, applies or cleans up.
param([Parameter(Mandatory=$true)][string]$WorkRoot,
      [Parameter(Mandatory=$true)][string]$Name,
      [Parameter(Mandatory=$true)][string]$TokenId,
      [Parameter(Mandatory=$true)][string]$ReceiptStore,
      [Parameter(Mandatory=$true)][string]$TransactionId)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
foreach($file in @(
  'validation/custom-app-stage-acquisition-contract-v0.1.0/custom-app-stage-acquisition.ps1',
  'validation/custom-app-local-runtime-baseline-v0.1.0/custom-app-local-runtime-baseline.ps1',
  'validation/custom-app-update-transaction-protocol-v0.1.0/custom-app-update-transaction.ps1',
  'validation/custom-app-production-crash-recovery-journal-v0.1.0/custom-app-production-crash-recovery-journal.ps1',
  'validation/approved-live-hmac-consumed-stage/approved-live-hmac-stage.ps1',
  'validation/approved-hmac-to-prepared-central-journal/approved-prepared-journal.ps1'
)){
    . (Join-Path $root $file)
}
$result=Read-ApprovedPreparedCentralJournalV030 -WorkRoot $WorkRoot -Name $Name -TokenId $TokenId -ReceiptStore $ReceiptStore -TransactionId $TransactionId
if(-not[bool]$result.ok -or
   [string]$result.phase -cne 'prepared' -or
   [int64]$result.journal_revision -ne 0 -or
   [bool]$result.original_hmac_key_needed -or
   [bool]$result.real_spotify_persistence_covered -or
   [bool]$result.production_mutation_authorized){
    throw ('V030_INDEPENDENT_RECOVERY_OF_EXACT_PREPARED_EVIDENCE_FAILED:'+ [string]$result.reason)
}
Write-Host 'V030_FRESH_PROCESS_KEYLESS_SOURCE_CONSUMPTION_AND_BOTH_BACKUPS_VERIFIED_PASS'
