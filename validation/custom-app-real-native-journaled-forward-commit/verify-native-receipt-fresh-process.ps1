# V024 independent read-only verification. No permit/session/HMAC key travels
# across the process boundary and this script never starts Spicetify.
param(
 [Parameter(Mandatory=$true)][string]$AllowedRoot,
 [Parameter(Mandatory=$true)][string]$JournalStoreDirectory,
 [Parameter(Mandatory=$true)][string]$JournalTransactionId,
 [Parameter(Mandatory=$true)][string]$ExpectedApplyFingerprint
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
   $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted'){
    throw 'native-receipt-verifier-hosted-only'
}
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-crash-recovery-journal-v0.1.0/custom-app-production-crash-recovery-journal.ps1')
. (Join-Path $root 'validation/custom-app-whole-tree-real-scoped-native/whole-tree-real-scoped-native.ps1')
. (Join-Path $PSScriptRoot 'native-journal-receipt.ps1')
$proof=Read-CustomAppRealNativeReceiptV024 -AllowedRoot $AllowedRoot -JournalStoreDirectory $JournalStoreDirectory -JournalTransactionId $JournalTransactionId -ExpectedApplyFingerprint $ExpectedApplyFingerprint
if(-not[bool]$proof.ok -or [bool]$proof.production_mutation_authorized -or
   [string]$proof.receipt.journal_transaction_id -cne $JournalTransactionId -or
   [string]$proof.journal.entry.apply_result_fingerprint -cne $ExpectedApplyFingerprint){
    throw ('native-independent-receipt-or-journal-invalid:'+[string]$proof.reason)
}
Write-Host 'REAL_NATIVE_V024_FRESH_PROCESS_NO_KEY_OFFICIAL_RECEIPT_AND_JOURNAL_PASS'
