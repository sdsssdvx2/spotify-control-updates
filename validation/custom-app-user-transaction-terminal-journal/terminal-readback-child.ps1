param(
  [Parameter(Mandatory=$true)][string]$LivePath,
  [Parameter(Mandatory=$true)][string]$HostedCiRoot,
  [Parameter(Mandatory=$true)][string]$ExpectedConsumptionId,
  [Parameter(Mandatory=$true)][string]$ExpectedTransactionId
)
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or $env:RUNNER_ENVIRONMENT -cne 'github-hosted'){throw 'USER_TERMINAL_RESTART_HOSTED_WINDOWS_ONLY'}
$root=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
. (Join-Path $root 'validation/custom-app-user-transaction-store-bundle/user-transaction-store.ps1')
. (Join-Path $root 'validation/custom-app-user-transaction-transition-guard/user-transaction-guard.ps1')
$s=Open-CustomAppUserTxnStoreV010 -Name tagify -LivePath $LivePath -HostedCiRoot $HostedCiRoot
try{
  if($null-ne$s.state.active -or [long]$s.state.revision -ne 2 -or
    @($s.state.consumed).Count -ne 1 -or
    @($s.state.consumed) -cnotcontains $ExpectedConsumptionId){
    throw 'USER_TERMINAL_FRESH_PROCESS_LOST_CONSUMED_ID'
  }
  $replayDenied=$false
  try{
    [void](Reserve-CustomAppUserTxnIdV010 -Session $s -ConsumptionId $ExpectedConsumptionId -TransactionId $ExpectedTransactionId -Nonce ('f'*32))
  }catch{$replayDenied=$true}
  if(-not$replayDenied){throw 'USER_TERMINAL_RESTART_REPLAY_ACCEPTED'}
  Write-Host 'USER_TERMINAL_FRESH_PROCESS_REPLAY_DENIED_PASS revision=2 active=false consumed=true'
}finally{$s.lock_handle.Dispose()}
