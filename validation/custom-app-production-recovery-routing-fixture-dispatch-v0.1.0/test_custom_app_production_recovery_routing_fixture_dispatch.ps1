$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

# Replay the exact validated bounded recovery executor matrix first. This also exposes
# the validated fixture helpers used below; no production path is involved.
. (Join-Path $root 'validation/custom-app-production-bounded-recovery-executor-v0.1.0/test_custom_app_production_bounded_recovery_executor.ps1')
. (Join-Path $root 'validation/custom-app-production-recovery-routing-admission-v0.1.0/custom-app-production-recovery-routing-admission.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-recovery-routing-fixture-dispatch.ps1')

function Assert-FDTrue([bool]$v,[string]$m){if(-not$v){throw $m}}
function Assert-FDFalse([bool]$v,[string]$m){if($v){throw $m}}
function Assert-FDEq($a,$b,[string]$m){if([string]$a-cne[string]$b){throw "$m actual=<$a> expected=<$b>"}}
function Copy-FD($x){return(($x|ConvertTo-Json -Depth 70)|ConvertFrom-Json)}
function FDNonce([string]$c){return (($c*32).Substring(0,32))}
function Get-FDRoute($Q,[DateTimeOffset]$At){
    $r=Resolve-CustomAppProductionRecoveryRoutingAdmissionV010 -AllowedRoot $Q.f.allowed -StoreDirectory $Q.f.store -ExpectedTransactionId ([string]$Q.f.identity.transaction_id) -Now $At
    Assert-FDTrue ([bool]$r.ok) ('route setup failed: '+[string]$r.reason)
    return $r
}
function Invoke-FD {
    param([Parameter(Mandatory=$true)]$Q,[Parameter(Mandatory=$true)]$Route,[DateTimeOffset]$At,[AllowNull()][string]$AllowedRoot=$null,[AllowNull()][string]$SpRoot=$null,[AllowNull()][string]$SpPath=$null)
    if([string]::IsNullOrWhiteSpace($AllowedRoot)){$AllowedRoot=[string]$Q.f.allowed}
    if([string]::IsNullOrWhiteSpace($SpRoot)){$SpRoot=[string]$Q.f.allowed}
    if([string]::IsNullOrWhiteSpace($SpPath)){$SpPath=[string]$Q.exe}
    return Invoke-CustomAppProductionRecoveryRoutingFixtureDispatchV010 -AllowedRoot $AllowedRoot -StoreDirectory $Q.f.store -ExpectedTransactionId ([string]$Q.f.identity.transaction_id) -RoutingReceipt $Route.receipt -LocalAppDataRoot $Q.f.q.persistence.local -AppDataRoot $Q.f.q.persistence.roaming -SpicetifyAllowedRoot $SpRoot -SpicetifyPath $SpPath -ExpectedSpicetifySha256 ([string]$Q.exeSha) -TimeoutSeconds 30 -Now $At
}
function Assert-FDZero($R,[string]$Label){$x=if($R.PSObject.Properties['result']){$R.result}else{$R};foreach($f in @('dispatch_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','permit_issued','production_mutation_authorized')){Assert-FDFalse ([bool]$x.$f) "$Label authority escaped $f"}}
function Assert-FDSuccess($R,[string]$Label,[string]$Status,[string]$Phase){
    Assert-FDTrue ([bool]$R.ok) "$Label denied: $([string]$R.reason)";Assert-FDZero $R $Label;Assert-FDEq $R.result.executor_status $Status "$Label executor status";Assert-FDEq $R.result.final_phase $Phase "$Label final phase";Assert-FDTrue ([bool]$R.result.fixture_environment_verified) "$Label fixture environment missing";Assert-FDTrue ([bool]$R.result.fixture_only_contract) "$Label fixture-only contract missing";$c=Test-CustomAppProductionRecoveryRoutingFixtureDispatchResultV010 -Result $R.result;Assert-FDTrue ([bool]$c.ok) "$Label result invalid: $([string]$c.reason)"
}
function Get-FDJournal($Q){return Read-CustomAppProductionCrashJournalV010 -AllowedRoot $Q.f.allowed -StoreDirectory $Q.f.store}

if([string]$env:GITHUB_ACTIONS-cne'true'){throw 'fixture-dispatch matrix must run only in GitHub Actions'}
if([string]::IsNullOrWhiteSpace([string]$env:RUNNER_TEMP)){throw 'fixture-dispatch matrix requires RUNNER_TEMP'}
$count=0

# 1. candidate-live route -> exact bounded rollback executor in the runner fixture tree.
$q=New-IntegrationFixtureV010 -Label 'fd-candidate' -Phase 'candidate-live' -Nonce (FDNonce '1');[void](Set-RXLiveToStagedV010 $q);$script:RecoveryApplyMode='success';$script:RecoveryApplyCalls=0;$at=[DateTimeOffset]::UtcNow;$route=Get-FDRoute $q $at;$r=Invoke-FD -Q $q -Route $route -At $at;Assert-FDSuccess $r 'candidate dispatch' 'rollback-complete' 'rollback-complete';Assert-FDEq $script:RecoveryApplyCalls 1 'candidate dispatch recovery apply count';Assert-FDEq (Get-FDJournal $q).entry.phase 'rollback-complete' 'candidate dispatch journal';$count++

# 2. apply-verified route -> exact bounded housekeeping executor.
$q=New-IntegrationFixtureV010 -Label 'fd-housekeeping' -Phase 'apply-verified' -Nonce (FDNonce '2');[void](Set-RXLiveToStagedV010 $q);$at=[DateTimeOffset]::UtcNow;$route=Get-FDRoute $q $at;$r=Invoke-FD -Q $q -Route $route -At $at;Assert-FDSuccess $r 'housekeeping dispatch' 'housekeeping-committed-clean' 'committed-clean';Assert-FDEq (Get-FDJournal $q).entry.phase 'committed-clean' 'housekeeping dispatch journal';$count++

# 3. Future app identity remains generic through routing and dispatch.
$q=New-IntegrationFixtureV010 -Label 'fd-future' -Phase 'candidate-live' -Name 'future-app' -Source 'owner/future-app' -Manifest 'Future App' -Nonce (FDNonce '3');[void](Set-RXLiveToStagedV010 $q);$script:RecoveryApplyMode='success';$at=[DateTimeOffset]::UtcNow;$route=Get-FDRoute $q $at;$r=Invoke-FD -Q $q -Route $route -At $at;Assert-FDSuccess $r 'future dispatch' 'rollback-complete' 'rollback-complete';Assert-FDEq $r.executor_result.name 'future-app' 'future dispatch identity';$count++

# 4. Durable journal phase drift after the routing receipt is fail-closed before executor mutation.
$q=New-IntegrationFixtureV010 -Label 'fd-stale' -Phase 'candidate-live' -Nonce (FDNonce '4');[void](Set-RXLiveToStagedV010 $q);$at=[DateTimeOffset]::UtcNow;$route=Get-FDRoute $q $at;$j=Get-FDJournal $q;$advance=Append-CustomAppProductionCrashJournalPhaseV010 -AllowedRoot $q.f.allowed -StoreDirectory $q.f.store -ExpectedRevision ([int64]$j.revision) -ExpectedEntrySha256 ([string]$j.entry.entry_sha256) -Phase 'rollback-required' -Now $at.AddMilliseconds(1);Assert-FDTrue ([bool]$advance.ok) 'stale route fixture advance failed';$script:RecoveryApplyCalls=0;$r=Invoke-FD -Q $q -Route $route -At $at;Assert-FDFalse ([bool]$r.ok) 'stale routing receipt executed';Assert-FDTrue ([string]$r.reason-like'fixture-dispatch-stale-routing-*') ('stale routing reason '+[string]$r.reason);Assert-FDEq $script:RecoveryApplyCalls 0 'stale routing invoked recovery apply';Assert-FDEq (Get-FDJournal $q).entry.phase 'rollback-required' 'stale routing mutated journal';$count++

# 5. Semantic route tamper + recomputed fingerprint is rejected by the routing receipt validator.
$q=New-IntegrationFixtureV010 -Label 'fd-route-tamper' -Phase 'candidate-live' -Nonce (FDNonce '5');$at=[DateTimeOffset]::UtcNow;$route=Get-FDRoute $q $at;$bad=Copy-FD $route.receipt;$bad.route='bounded-recovery-housekeeping-candidate';$bad.routing_fingerprint=Get-CustomAppProductionRecoveryRoutingAdmissionSha256V010 (Get-CustomAppProductionRecoveryRoutingAdmissionMaterialV010 -Receipt $bad);$fake=[pscustomobject]@{receipt=$bad};$r=Invoke-FD -Q $q -Route $fake -At $at;Assert-FDFalse ([bool]$r.ok) 'route tamper+rehash executed';Assert-FDTrue ([string]$r.reason-like'fixture-dispatch-routing-receipt-invalid:*semantic-route-drift*') ('route tamper reason '+[string]$r.reason);Assert-FDEq (Get-FDJournal $q).entry.phase 'candidate-live' 'route tamper mutated journal';$count++

# 6. Authority tamper + recomputed fingerprint is rejected.
$q=New-IntegrationFixtureV010 -Label 'fd-authority-tamper' -Phase 'candidate-live' -Nonce (FDNonce '6');$at=[DateTimeOffset]::UtcNow;$route=Get-FDRoute $q $at;$bad=Copy-FD $route.receipt;$bad.execution_authorized=$true;$bad.routing_fingerprint=Get-CustomAppProductionRecoveryRoutingAdmissionSha256V010 (Get-CustomAppProductionRecoveryRoutingAdmissionMaterialV010 -Receipt $bad);$fake=[pscustomobject]@{receipt=$bad};$r=Invoke-FD -Q $q -Route $fake -At $at;Assert-FDFalse ([bool]$r.ok) 'authority tamper+rehash executed';Assert-FDTrue ([string]$r.reason-like'fixture-dispatch-routing-receipt-invalid:*authority-escaped-execution_authorized*') ('authority tamper reason '+[string]$r.reason);$count++

# 7-10. Routes requiring separate policy are never dispatched.
foreach($spec in @(@('prepared','7'),@('atomic-mutation-starting','8'),@('committed-clean','9'),@('rollback-complete','a'))){
    $q=New-IntegrationFixtureV010 -Label ('fd-refuse-'+$spec[0]) -Phase $spec[0] -Nonce (FDNonce $spec[1]);$before=Get-FDJournal $q;$at=[DateTimeOffset]::UtcNow;$route=Get-FDRoute $q $at;$r=Invoke-FD -Q $q -Route $route -At $at;Assert-FDFalse ([bool]$r.ok) "$($spec[0]) route executed";Assert-FDTrue ([string]$r.reason-like'fixture-dispatch-routing-*') "$($spec[0]) refusal reason drifted: $([string]$r.reason)";$after=Get-FDJournal $q;Assert-FDEq $after.revision $before.revision "$($spec[0]) refusal mutated journal";Assert-FDEq $after.entry.phase $before.entry.phase "$($spec[0]) refusal changed phase";$count++
}

# 11. GITHUB_ACTIONS=false is rejected before any executor path.
$q=New-IntegrationFixtureV010 -Label 'fd-not-gh' -Phase 'candidate-live' -Nonce (FDNonce 'b');$at=[DateTimeOffset]::UtcNow;$route=Get-FDRoute $q $at;$oldGh=$env:GITHUB_ACTIONS;try{$env:GITHUB_ACTIONS='false';$r=Invoke-FD -Q $q -Route $route -At $at}finally{$env:GITHUB_ACTIONS=$oldGh};Assert-FDFalse ([bool]$r.ok) 'non-GitHub environment accepted';Assert-FDEq $r.reason 'fixture-dispatch-not-github-actions' 'non-GitHub reason';Assert-FDEq (Get-FDJournal $q).entry.phase 'candidate-live' 'non-GitHub guard mutated journal';$count++

# 12. Missing RUNNER_TEMP is rejected before any executor path.
$q=New-IntegrationFixtureV010 -Label 'fd-no-runner-temp' -Phase 'candidate-live' -Nonce (FDNonce 'c');$at=[DateTimeOffset]::UtcNow;$route=Get-FDRoute $q $at;$oldRt=$env:RUNNER_TEMP;try{$env:RUNNER_TEMP=$null;$r=Invoke-FD -Q $q -Route $route -At $at}finally{$env:RUNNER_TEMP=$oldRt};Assert-FDFalse ([bool]$r.ok) 'missing RUNNER_TEMP accepted';Assert-FDEq $r.reason 'fixture-dispatch-runner-temp-missing' 'missing RUNNER_TEMP reason';$count++

# 13. AllowedRoot outside RUNNER_TEMP is rejected before journal access/execution.
$q=New-IntegrationFixtureV010 -Label 'fd-outside-root' -Phase 'candidate-live' -Nonce (FDNonce 'd');$at=[DateTimeOffset]::UtcNow;$route=Get-FDRoute $q $at;$outside=$root;$r=Invoke-FD -Q $q -Route $route -At $at -AllowedRoot $outside;Assert-FDFalse ([bool]$r.ok) 'outside AllowedRoot accepted';Assert-FDEq $r.reason 'fixture-dispatch-allowed-root-outside-runner-temp' 'outside AllowedRoot reason';$count++

# 14. Existing spicetify executable outside the supplied spicetify root is rejected.
$q=New-IntegrationFixtureV010 -Label 'fd-sp-outside' -Phase 'candidate-live' -Nonce (FDNonce 'e');$at=[DateTimeOffset]::UtcNow;$route=Get-FDRoute $q $at;$badRoot=Join-Path $q.f.q.x.base 'different-bin-root';[IO.Directory]::CreateDirectory($badRoot)|Out-Null;$r=Invoke-FD -Q $q -Route $route -At $at -SpRoot $badRoot -SpPath $q.exe;Assert-FDFalse ([bool]$r.ok) 'spicetify outside supplied root accepted';Assert-FDEq $r.reason 'fixture-dispatch-spicetify-path-outside-spicetify-root' 'spicetify outside reason';$count++

# 15. Expired routing receipt is refused.
$q=New-IntegrationFixtureV010 -Label 'fd-expired' -Phase 'candidate-live' -Nonce (FDNonce 'f');$at=[DateTimeOffset]::UtcNow;$route=Get-FDRoute $q $at;$r=Invoke-FD -Q $q -Route $route -At $at.AddSeconds(11);Assert-FDFalse ([bool]$r.ok) 'expired routing receipt executed';Assert-FDTrue ([string]$r.reason-like'fixture-dispatch-routing-receipt-invalid:*expired*') ('expired route reason '+[string]$r.reason);$count++

# 16-17. Dispatch result cannot gain a different semantic route or authority even if rehashed.
$q=New-IntegrationFixtureV010 -Label 'fd-result-tamper' -Phase 'candidate-live' -Nonce (FDNonce 'g');[void](Set-RXLiveToStagedV010 $q);$script:RecoveryApplyMode='success';$at=[DateTimeOffset]::UtcNow;$route=Get-FDRoute $q $at;$good=Invoke-FD -Q $q -Route $route -At $at;Assert-FDSuccess $good 'result tamper setup' 'rollback-complete' 'rollback-complete'
$bad=Copy-FD $good.result;$bad.route='bounded-recovery-housekeeping-candidate';$bad.result_fingerprint=Get-CustomAppProductionRecoveryRoutingFixtureDispatchSha256V010 (Get-CustomAppProductionRecoveryRoutingFixtureDispatchResultMaterialV010 $bad);$ck=Test-CustomAppProductionRecoveryRoutingFixtureDispatchResultV010 -Result $bad;Assert-FDFalse ([bool]$ck.ok) 'result route tamper+rehash accepted';Assert-FDEq $ck.reason 'fixture-dispatch-result-housekeeping-status-invalid' 'result route tamper reason';$count++
$bad=Copy-FD $good.result;$bad.production_mutation_authorized=$true;$bad.result_fingerprint=Get-CustomAppProductionRecoveryRoutingFixtureDispatchSha256V010 (Get-CustomAppProductionRecoveryRoutingFixtureDispatchResultMaterialV010 $bad);$ck=Test-CustomAppProductionRecoveryRoutingFixtureDispatchResultV010 -Result $bad;Assert-FDFalse ([bool]$ck.ok) 'result authority tamper+rehash accepted';Assert-FDEq $ck.reason 'fixture-dispatch-result-authority-escaped-production_mutation_authorized' 'result authority tamper reason';$count++

Write-Host "CUSTOM_APP_PRODUCTION_RECOVERY_ROUTING_FIXTURE_DISPATCH_MATRIX_PASS total=$count"
