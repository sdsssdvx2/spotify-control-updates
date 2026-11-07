# V051 hosted synthetic, fresh PowerShell 5.1 private recovery only.
param([Parameter(Mandatory=$true)][string]$EscrowId,
      [Parameter(Mandatory=$true)][string]$ReceiptSha256,
      [Parameter(Mandatory=$true)][string]$HostedEscrowRoot)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
  $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
  [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
   throw 'V051_CHILD_HOSTED_ONLY'
}
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $repo 'validation/custom-app-update-transaction-protocol-v0.1.0/custom-app-update-transaction.ps1')
. (Join-Path $repo 'validation/approved-installed-xpui-readonly/installed-xpui-readonly.ps1')
. (Join-Path $PSScriptRoot 'guarded-profile-escrow-v050.ps1')
. (Join-Path $PSScriptRoot 'private-detached-recovery-v051.ps1')
$arg=@{EscrowId=$EscrowId;ReceiptSha256=$ReceiptSha256;HostedEscrowRoot=$HostedEscrowRoot}
$r=Invoke-CustomAppV051PrivateDetachedRecovery @arg -ExplicitDetachedRecoveryAuthorization
if(-not[bool]$r.ok -or [string]$r.status -cne 'detached-private-recovery-created' -or
  [int]$r.xpui_file_count -ne 610 -or [int]$r.approved_app_count -ne 3 -or
  [int]$r.protected_file_count -ne 3 -or
  [bool]$r.live_update_authorized -or [bool]$r.production_mutation_authorized){
  throw 'V051_CHILD_RECONSTRUCTION_NOT_QUALIFIED'
}
$again=Test-CustomAppV051DetachedRecovery @arg
if(-not[bool]$again.ok -or [int]$again.xpui_file_count -ne 610 -or
  [bool]$again.production_mutation_authorized){
  throw 'V051_CHILD_DETACHED_READBACK_FAILED'
}
Write-Host 'V051_NEW_PROCESS_610FILE_DPAPI_GUARDS_PRIVATE_RECOVERY_PASS'
