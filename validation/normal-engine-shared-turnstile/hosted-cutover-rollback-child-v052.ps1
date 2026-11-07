# V052 fresh-process, HOSTED-WINDOWS-ONLY retained intent recovery.
# Never targets installed Spotify or calls official CLI.
param([Parameter(Mandatory=$true)][string]$HostedFixtureRoot,
      [Parameter(Mandatory=$true)][string]$HostedFixtureCliPath,
      [Parameter(Mandatory=$true)][string]$HostedEscrowRoot,
      [Parameter(Mandatory=$true)][string]$EscrowId,
      [Parameter(Mandatory=$true)][string]$IntentSha256)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted'){
    throw 'V052_CHILD_REAL_PROFILE_FORBIDDEN'
}
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $repo 'validation/custom-app-update-transaction-protocol-v0.1.0/custom-app-update-transaction.ps1')
. (Join-Path $repo 'validation/approved-installed-xpui-readonly/installed-xpui-readonly.ps1')
. (Join-Path $PSScriptRoot 'engine-turnstile-v047.ps1')
. (Join-Path $PSScriptRoot 'guarded-profile-escrow-v050.ps1')
. (Join-Path $PSScriptRoot 'private-detached-recovery-v051.ps1')
. (Join-Path $PSScriptRoot 'hosted-cutover-rollback-v052.ps1')
$args=@{HostedFixtureRoot=$HostedFixtureRoot;HostedFixtureCliPath=$HostedFixtureCliPath
 HostedEscrowRoot=$HostedEscrowRoot;EscrowId=$EscrowId;IntentSha256=$IntentSha256}
$result=Invoke-CustomAppHostedRollbackV052 @args
if(-not[bool]$result.ok -or
   [string]$result.status -cne 'hosted-scoped-rollback-complete' -or
   -not[bool]$result.rollback_complete -or
   -not[bool]$result.quarantine_retained -or
   [bool]$result.production_mutation_authorized -or
   [bool]$result.live_update_authorized){
   throw 'V052_CHILD_DURABLE_ROLLBACK_NOT_QUALIFIED'
}
Write-Host 'V052_FRESH_PROCESS_SHARED_LOCK_APP_AND_XPUI_ROLLBACK_COMPLETE_PASS'
