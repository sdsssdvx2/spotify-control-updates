# V040 fresh-process DPAPI single-use durable ledger proof (synthetic only).
param([Parameter(Mandatory=$true)][string]$Name,
 [Parameter(Mandatory=$true)][string]$LivePath,
 [Parameter(Mandatory=$true)][string]$HostedCiRoot,
 [Parameter(Mandatory=$true)][string]$ConsumedToken,
 [Parameter(Mandatory=$true)][string]$TransactionId)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
 $env:RUNNER_ENVIRONMENT -cne 'github-hosted'){
 throw 'V040_FRESH_LEDGER_TEST_HOSTED_ONLY'
}
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-user-transaction-store-bundle/user-transaction-store.ps1')
. (Join-Path $root 'validation/custom-app-user-transaction-transition-guard/user-transaction-guard.ps1')
$session=Open-CustomAppUserTxnStoreV010 -Name $Name -LivePath $LivePath -HostedCiRoot $HostedCiRoot
try{
 $s=$session.state
 if([long]$s.revision -ne 2 -or $null-ne$s.active -or
   @($s.consumed).Count -ne 1 -or @($s.consumed) -cnotcontains $ConsumedToken){
    throw 'V040_FRESH_PROCESS_DURABLE_CONSUMPTION_NOT_PRESENT'
 }
 $rejected=$false
 try{
  [void](Reserve-CustomAppUserTxnIdV010 -Session $session -ConsumptionId $ConsumedToken -TransactionId $TransactionId -Nonce ([Guid]::NewGuid().ToString('N')))
 }catch{$rejected=$true}
 if(-not$rejected){throw 'V040_FRESH_PROCESS_OLD_CONSUMPTION_REPLAY_ACCEPTED'}
 $same=Read-CustomAppUserTxnStateV010 -Paths $session.paths
 if([long]$same.revision -ne 2 -or $null-ne$same.active){
   throw 'V040_FRESH_PROCESS_FAILED_REPLAY_MUTATED_LEDGER'
 }
 Write-Host 'V040_FRESH_PROCESS_ATOMIC_LEDGER_CONSUMED_AND_REPLAY_BLOCKED_PASS'
}finally{$session.lock_handle.Dispose()}
