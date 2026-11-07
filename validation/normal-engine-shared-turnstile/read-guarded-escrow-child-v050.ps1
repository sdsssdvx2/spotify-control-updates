# Separate-process DPAPI reader: output is bounded, no private paths/keys.
param([Parameter(Mandatory=$true)][string]$EscrowId,
      [Parameter(Mandatory=$true)][string]$ReceiptSha256,
      [Parameter(Mandatory=$true)][string]$FixtureEscrowRoot,
      [switch]$HostedRestore)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted'){
  throw 'V050_CHILD_HOSTED_WINDOWS_ONLY'
}
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $repo 'validation/custom-app-update-transaction-protocol-v0.1.0/custom-app-update-transaction.ps1')
. (Join-Path $repo 'validation/approved-installed-xpui-readonly/installed-xpui-readonly.ps1')
. (Join-Path $PSScriptRoot 'guarded-profile-escrow-v050.ps1')
. (Join-Path $PSScriptRoot 'hosted-detached-restore-v050.ps1')
$r=Test-CustomAppV050Escrow -EscrowId $EscrowId -ExpectedReceiptSha256 $ReceiptSha256 -HostedEscrowRoot $FixtureEscrowRoot
if(-not[bool]$r.ok -or
   [string]$r.status -cne 'verified-detached-preimage' -or
   [bool]$r.live_update_authorized -or
   [bool]$r.production_mutation_authorized){
    throw 'V050_CHILD_BACKUP_READER_NOT_VERIFIED'
}
Write-Host 'V050_FRESH_PROCESS_DPAPI_RECEIPT_XPUI_AND_APP_TREE_VERIFIED_PASS'
if($HostedRestore){
 $r=Invoke-CustomAppHostedDetachedRestoreV050 -HostedEscrowRoot $FixtureEscrowRoot -EscrowId $EscrowId -ExpectedReceiptSha256 $ReceiptSha256
 if(-not[bool]$r.ok -or [int]$r.dpapi_guard_files_restored -ne 3 -or
    [bool]$r.live_update_authorized -or [bool]$r.production_restore_authorized){
   throw 'V050_CHILD_DETACHED_RESTORE_FAILED'
 }
 Write-Host 'V050_FRESH_PROCESS_XPUI_APP_AND_DPAPI_GUARD_RESTORATION_PASS'
}
