# V025 independent, keyless cold continuation of genuine official vendor
# success. No HMAC session key, permit, Spicetify CLI or file cleanup passes
# between processes. Only an already-approved hosted temporary V010 journal CAS.
param(
 [Parameter(Mandatory=$true)][string]$AllowedRoot,
 [Parameter(Mandatory=$true)][string]$JournalStoreDirectory,
 [Parameter(Mandatory=$true)][string]$JournalTransactionId
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
   $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
    throw 'v025-cold-resume-must-run-in-hosted-Windows-fixture'
}
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
foreach($file in @(
 'validation/custom-app-production-crash-recovery-journal-v0.1.0/custom-app-production-crash-recovery-journal.ps1',
 'validation/custom-app-production-recovery-evidence-envelope-v0.1.0/custom-app-production-recovery-evidence.ps1',
 'validation/custom-app-local-runtime-baseline-v0.1.0/custom-app-local-runtime-baseline.ps1',
 'validation/custom-app-whole-tree-real-scoped-native/whole-tree-real-scoped-native.ps1',
 'validation/custom-app-real-native-journaled-forward-commit/native-journal-receipt.ps1',
 'validation/custom-app-real-native-pending-recovery-v0.1.0/real-native-pending-recovery.ps1'
)){
    . (Join-Path $root $file)
}
$r=Complete-CustomAppRealNativePendingResumeV025 -AllowedRoot $AllowedRoot -JournalStoreDirectory $JournalStoreDirectory -JournalTransactionId $JournalTransactionId
if(-not[bool]$r.ok -or -not[bool]$r.fresh_process -or
   [int]$r.official_vendor_invocations -ne 0 -or
   [bool]$r.production_mutation_authorized){
    throw 'v025-cold-native-proof-was-not-genuine-keyless-no-reapply'
}
Write-Host 'REAL_NATIVE_V025_FRESH_PROCESS_KEYLESS_JOURNAL_PROGRESS_NO_REAPPLY_PASS'
