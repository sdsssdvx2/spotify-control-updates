param()
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
    throw 'SEALED_STARTUP_SOURCE_TEST_HOSTED_WINDOWS_ONLY'
}
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
foreach($module in @(
    'validation/custom-app-user-transaction-store-bundle/user-transaction-store.ps1',
    'validation/custom-app-journal-restart-locator/user-journal-locator.ps1',
    'validation/custom-app-missing-live-recovery/missing-live-recovery.ps1',
    'validation/custom-app-normal-entrypoint-transaction-integration/normal-update-engine-fence.ps1',
    'validation/custom-app-legacy-journal-settlement-barrier/legacy-settlement-barrier.ps1',
    'validation/custom-app-cooperative-cross-engine-lock/cross-engine-transaction-lock.ps1',
    'validation/custom-app-durable-recovery-inventory/durable-recovery-inventory.ps1',
    'validation/custom-app-startup-recovery-source/startup-recovery-source.ps1'
)){
    . (Join-Path $repo $module)
}
function Assert-Denied([scriptblock]$Action,[string]$Why){
    $denied=$false
    try{& $Action|Out-Null}catch{$denied=$true}
    if(-not $denied){throw ('SEALED_STARTUP_FAIL_OPEN_'+$Why)}
}
$root=Join-Path $env:RUNNER_TEMP ('sealed-source-'+[guid]::NewGuid().ToString('N'))
$store=Join-Path $root 'private'
$live=Join-Path $root 'live-tagify'
[IO.Directory]::CreateDirectory($store)|Out-Null
[IO.Directory]::CreateDirectory($live)|Out-Null
$empty=Get-CustomAppSealedStartupRecoveryAssessmentV013 -HostedCiRoot $store
if(-not[bool]$empty.ok -or [bool]$empty.enrollment_found -or
   [bool]$empty.production_mutation_authorized -or $empty.items.Count -ne 0){
    throw 'SEALED_STARTUP_EMPTY_SOURCE_INVALID'
}
$session=Open-CustomAppUserTxnStoreV010 -Name tagify -LivePath $live -HostedCiRoot $store -Initialize
try{
    if($null -ne $session.state.active){throw 'SEALED_STARTUP_TEST_EXPECTED_IDLE'}
}finally{$session.lock_handle.Dispose()}
$paths=Get-CustomAppUserTxnPathsV010 -Name tagify -LivePath $live -HostedCiRoot $store
[IO.File]::WriteAllBytes([string]$paths.pending,[byte[]](4,3,2,1))
$before=(Get-FileHash -LiteralPath $paths.state -Algorithm SHA256).Hash
$pending=(Get-FileHash -LiteralPath $paths.pending -Algorithm SHA256).Hash
$owned=Open-CustomAppCrossEngineTransactionLockV010 -HostedCiRoot $store
try{
    $idle=Get-CustomAppSealedStartupRecoveryAssessmentV013 -HostedCiRoot $store -HeldCrossEngineSession $owned
    if(-not[bool]$idle.ok -or [int]$idle.inspected_count -ne 1 -or
       [int]$idle.active_count -ne 0 -or [bool]$idle.items[0].active -or
       $null -ne $idle.items[0].source -or $null -ne $idle.items[0].plan -or
       [bool]$idle.production_execution_authorized -or
       [bool]$idle.items[0].production_mutation_authorized){
        throw 'SEALED_STARTUP_IDLE_SOURCE_INVALID'
    }
    Assert-Denied {Get-CustomAppSealedStartupRecoveryAssessmentV013 -HostedCiRoot (Join-Path $root 'wrong') -HeldCrossEngineSession $owned} 'wrong_global_lock_root'
    [void](Assert-CustomAppCrossEngineTransactionLockHeldV010 -Session $owned)
}finally{$owned.lock_handle.Dispose()}
if((Get-FileHash -LiteralPath $paths.state -Algorithm SHA256).Hash -cne $before -or
   (Get-FileHash -LiteralPath $paths.pending -Algorithm SHA256).Hash -cne $pending){
    throw 'SEALED_STARTUP_READ_CHANGED_STATE_OR_PENDING'
}
$missing=Join-Path $root 'moved-tagify'
Move-Item -LiteralPath $live -Destination $missing
$missingIdle=Get-CustomAppSealedStartupRecoveryAssessmentV013 -HostedCiRoot $store
if(-not[bool]$missingIdle.ok -or [bool]$missingIdle.items[0].active -or
   [IO.Directory]::Exists($live)){
    throw 'SEALED_STARTUP_MISSING_IDLE_RECREATED_LIVE'
}
[IO.File]::WriteAllBytes([string]$paths.state,[byte[]](1,2,3))
Assert-Denied {Get-CustomAppSealedStartupRecoveryAssessmentV013 -HostedCiRoot $store} 'corrupt_sealed_registry'
# Restore only the hosted test fixture to compare exact immutable bytes.
# The test never touches a real user profile or Spotify.
Write-Host 'SEALED_STARTUP_SOURCE_READ_ONLY_TEST_PASS no_enrollment=true idle=true held_lock=true wrong_root_denied=true state_pending_preserved=true missing_live=true corrupt_dpapi_denied=true'
