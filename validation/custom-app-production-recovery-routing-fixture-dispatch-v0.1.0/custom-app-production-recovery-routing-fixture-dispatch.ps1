$CustomAppProductionRecoveryRoutingFixtureDispatchSchema = 1
$CustomAppProductionRecoveryRoutingFixtureDispatchManagedBy = 'custom-app-production-recovery-routing-fixture-dispatch-v1'
$CustomAppProductionRecoveryRoutingFixtureDispatchQualifiedRouterHead = '2f2f596bb8a86c0b074543992f7634be858821a4'
$CustomAppProductionRecoveryRoutingFixtureDispatchQualifiedBoundedExecutorHead = '5a2840d824f1e28e2920657d0e3a8e139d7e8b71'

function Get-CustomAppProductionRecoveryRoutingFixtureDispatchSha256V010 {
    param([AllowNull()][string]$Text)
    if($null-eq$Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}
function Test-CustomAppProductionRecoveryRoutingFixtureDispatchSha256V010 {
    param([AllowNull()][string]$Value)
    return(-not[string]::IsNullOrWhiteSpace($Value)-and$Value-cmatch'^[0-9a-f]{64}$')
}
function Get-CustomAppProductionRecoveryRoutingFixtureDispatchCanonicalPathV010 {
    param([Parameter(Mandatory=$true)][string]$Path)
    return [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
}
function Test-CustomAppProductionRecoveryRoutingFixtureDispatchPathWithinV010 {
    param([Parameter(Mandatory=$true)][string]$Root,[Parameter(Mandatory=$true)][string]$Path,[switch]$AllowEqual)
    try{$r=Get-CustomAppProductionRecoveryRoutingFixtureDispatchCanonicalPathV010 $Root;$p=Get-CustomAppProductionRecoveryRoutingFixtureDispatchCanonicalPathV010 $Path}catch{return $false}
    if($AllowEqual-and$p-ieq$r){return $true}
    $prefix=$r+[IO.Path]::DirectorySeparatorChar
    return $p.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)
}
function Test-CustomAppProductionRecoveryRoutingFixtureDispatchEnvironmentV010 {
    param(
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory,
        [Parameter(Mandatory=$true)][string]$LocalAppDataRoot,[Parameter(Mandatory=$true)][string]$AppDataRoot,
        [Parameter(Mandatory=$true)][string]$SpicetifyAllowedRoot,[Parameter(Mandatory=$true)][string]$SpicetifyPath
    )
    $deny={param([string]$Reason)[pscustomobject]@{ok=$false;reason=$Reason;fixture_environment_verified=$false}}
    if([string]$env:GITHUB_ACTIONS-cne'true'){return & $deny 'fixture-dispatch-not-github-actions'}
    if([string]::IsNullOrWhiteSpace([string]$env:RUNNER_TEMP)){return & $deny 'fixture-dispatch-runner-temp-missing'}
    try{$runner=Get-CustomAppProductionRecoveryRoutingFixtureDispatchCanonicalPathV010 $env:RUNNER_TEMP;$allowed=Get-CustomAppProductionRecoveryRoutingFixtureDispatchCanonicalPathV010 $AllowedRoot;$store=Get-CustomAppProductionRecoveryRoutingFixtureDispatchCanonicalPathV010 $StoreDirectory;$local=Get-CustomAppProductionRecoveryRoutingFixtureDispatchCanonicalPathV010 $LocalAppDataRoot;$roaming=Get-CustomAppProductionRecoveryRoutingFixtureDispatchCanonicalPathV010 $AppDataRoot;$spRoot=Get-CustomAppProductionRecoveryRoutingFixtureDispatchCanonicalPathV010 $SpicetifyAllowedRoot;$sp=Get-CustomAppProductionRecoveryRoutingFixtureDispatchCanonicalPathV010 $SpicetifyPath}catch{return & $deny ('fixture-dispatch-path-canonicalization-failed:'+[string]$_.Exception.Message)}
    if(-not(Test-Path -LiteralPath $runner -PathType Container)){return & $deny 'fixture-dispatch-runner-temp-not-directory'}
    if(-not(Test-CustomAppProductionRecoveryRoutingFixtureDispatchPathWithinV010 -Root $runner -Path $allowed -AllowEqual)){return & $deny 'fixture-dispatch-allowed-root-outside-runner-temp'}
    foreach($spec in @(@('store',$store),@('localappdata',$local),@('appdata',$roaming),@('spicetify-root',$spRoot))){if(-not(Test-CustomAppProductionRecoveryRoutingFixtureDispatchPathWithinV010 -Root $allowed -Path ([string]$spec[1]) -AllowEqual)){return & $deny ('fixture-dispatch-'+[string]$spec[0]+'-outside-allowed-root')}}
    if(-not(Test-CustomAppProductionRecoveryRoutingFixtureDispatchPathWithinV010 -Root $spRoot -Path $sp)){return & $deny 'fixture-dispatch-spicetify-path-outside-spicetify-root'}
    if(-not(Test-Path -LiteralPath $sp -PathType Leaf)){return & $deny 'fixture-dispatch-spicetify-path-missing'}
    return [pscustomobject]@{ok=$true;reason='fixture-dispatch-github-actions-runner-temp-verified';fixture_environment_verified=$true;runner_temp=$runner;allowed_root=$allowed;store_directory=$store;local_app_data_root=$local;app_data_root=$roaming;spicetify_allowed_root=$spRoot;spicetify_path=$sp}
}
function Get-CustomAppProductionRecoveryRoutingFixtureDispatchResultMaterialV010 {
    param([Parameter(Mandatory=$true)]$Result)
    return @(
        [string]$Result.schema,[string]$Result.managed_by,[string]$Result.qualified_router_head,[string]$Result.qualified_bounded_executor_head,
        [string]$Result.transaction_id,[string]$Result.route,[string]$Result.initial_phase,[string]$Result.route_fingerprint,[string]$Result.route_journal_revision,[string]$Result.route_journal_entry_sha256,
        [string]$Result.executor_result_fingerprint,[string]$Result.executor_status,[string]$Result.final_phase,[string]$Result.executor_journal_start_revision,[string]$Result.executor_journal_end_revision,[string]$Result.executor_journal_end_sha256,
        [string]$Result.fixture_environment_verified,[string]$Result.fixture_only_contract,[string]$Result.requires_future_fresh_revalidation,
        [string]$Result.dispatch_is_authority,[string]$Result.execution_authorized,[string]$Result.restore_authorized,[string]$Result.apply_authorized,[string]$Result.cleanup_authorized,[string]$Result.permit_issued,[string]$Result.production_mutation_authorized
    )-join"`n"
}
function Test-CustomAppProductionRecoveryRoutingFixtureDispatchResultV010 {
    param([AllowNull()]$Result)
    if($null-eq$Result){return [pscustomobject]@{ok=$false;reason='fixture-dispatch-result-null'}}
    foreach($f in @('schema','managed_by','qualified_router_head','qualified_bounded_executor_head','transaction_id','route','initial_phase','route_fingerprint','route_journal_revision','route_journal_entry_sha256','executor_result_fingerprint','executor_status','final_phase','executor_journal_start_revision','executor_journal_end_revision','executor_journal_end_sha256','fixture_environment_verified','fixture_only_contract','requires_future_fresh_revalidation','dispatch_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','permit_issued','production_mutation_authorized','result_fingerprint')){if(-not$Result.PSObject.Properties[$f]){return [pscustomobject]@{ok=$false;reason=('fixture-dispatch-result-required-field-missing-'+$f)}}}
    if([int]$Result.schema-ne1-or[string]$Result.managed_by-cne$CustomAppProductionRecoveryRoutingFixtureDispatchManagedBy-or[string]$Result.qualified_router_head-cne$CustomAppProductionRecoveryRoutingFixtureDispatchQualifiedRouterHead-or[string]$Result.qualified_bounded_executor_head-cne$CustomAppProductionRecoveryRoutingFixtureDispatchQualifiedBoundedExecutorHead){return [pscustomobject]@{ok=$false;reason='fixture-dispatch-result-owner-schema-parent-invalid'}}
    foreach($f in @('transaction_id','route_fingerprint','route_journal_entry_sha256','executor_result_fingerprint','executor_journal_end_sha256','result_fingerprint')){if(-not(Test-CustomAppProductionRecoveryRoutingFixtureDispatchSha256V010(([string]$Result.$f).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('fixture-dispatch-result-invalid-'+$f)}}}
    if(-not[bool]$Result.fixture_environment_verified-or-not[bool]$Result.fixture_only_contract-or-not[bool]$Result.requires_future_fresh_revalidation){return [pscustomobject]@{ok=$false;reason='fixture-dispatch-result-fixture-contract-missing'}}
    foreach($f in @('dispatch_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','permit_issued','production_mutation_authorized')){if([bool]$Result.$f){return [pscustomobject]@{ok=$false;reason=('fixture-dispatch-result-authority-escaped-'+$f)}}}
    if([int64]$Result.executor_journal_start_revision-lt[int64]$Result.route_journal_revision-or[int64]$Result.executor_journal_end_revision-lt[int64]$Result.executor_journal_start_revision){return [pscustomobject]@{ok=$false;reason='fixture-dispatch-result-journal-revision-invalid'}}
    if([string]$Result.route-ceq'bounded-recovery-executor-candidate'){
        if([string]$Result.executor_status-cne'rollback-complete'-or[string]$Result.final_phase-cne'rollback-complete'){return [pscustomobject]@{ok=$false;reason='fixture-dispatch-result-recovery-status-invalid'}}
    }elseif([string]$Result.route-ceq'bounded-recovery-housekeeping-candidate'){
        if([string]$Result.executor_status-cne'housekeeping-committed-clean'-or[string]$Result.final_phase-cne'committed-clean'){return [pscustomobject]@{ok=$false;reason='fixture-dispatch-result-housekeeping-status-invalid'}}
    }else{return [pscustomobject]@{ok=$false;reason='fixture-dispatch-result-route-invalid'}}
    $expected=Get-CustomAppProductionRecoveryRoutingFixtureDispatchSha256V010 (Get-CustomAppProductionRecoveryRoutingFixtureDispatchResultMaterialV010 $Result);if(([string]$Result.result_fingerprint).Trim().ToLowerInvariant()-cne$expected){return [pscustomobject]@{ok=$false;reason='fixture-dispatch-result-fingerprint-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='fixture-dispatch-result-valid-non-authoritative';result_fingerprint=$expected}
}
function Invoke-CustomAppProductionRecoveryRoutingFixtureDispatchV010 {
    param(
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory,[Parameter(Mandatory=$true)][string]$ExpectedTransactionId,
        [Parameter(Mandatory=$true)]$RoutingReceipt,[Parameter(Mandatory=$true)][string]$LocalAppDataRoot,[Parameter(Mandatory=$true)][string]$AppDataRoot,
        [Parameter(Mandatory=$true)][string]$SpicetifyAllowedRoot,[Parameter(Mandatory=$true)][string]$SpicetifyPath,[Parameter(Mandatory=$true)][string]$ExpectedSpicetifySha256,
        [int]$TimeoutSeconds=30,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow
    )
    $deny={param([string]$Reason)[pscustomobject]@{ok=$false;reason=$Reason;fixture_only_contract=$true;dispatch_is_authority=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;permit_issued=$false;production_mutation_authorized=$false}}
    $envCheck=Test-CustomAppProductionRecoveryRoutingFixtureDispatchEnvironmentV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -SpicetifyAllowedRoot $SpicetifyAllowedRoot -SpicetifyPath $SpicetifyPath
    if(-not[bool]$envCheck.ok){return & $deny ([string]$envCheck.reason)}
    $tx=$ExpectedTransactionId.Trim().ToLowerInvariant();if(-not(Test-CustomAppProductionRecoveryRoutingFixtureDispatchSha256V010 $tx)){return & $deny 'fixture-dispatch-transaction-id-invalid'}
    $rc=Test-CustomAppProductionRecoveryRoutingAdmissionReceiptV010 -Receipt $RoutingReceipt -Now $Now;if(-not[bool]$rc.ok){return & $deny ('fixture-dispatch-routing-receipt-invalid:'+[string]$rc.reason)}
    if(([string]$RoutingReceipt.transaction_id).Trim().ToLowerInvariant()-cne$tx){return & $deny 'fixture-dispatch-routing-transaction-mismatch'}
    if([string]$RoutingReceipt.route-notin@('bounded-recovery-executor-candidate','bounded-recovery-housekeeping-candidate')-or[string]$RoutingReceipt.next_validator-cne'Invoke-CustomAppProductionBoundedRecoveryExecutorV010'){return & $deny 'fixture-dispatch-routing-class-not-executable'}
    if([bool]$RoutingReceipt.requires_manual_resolution-or[bool]$RoutingReceipt.requires_recovery_artifact_retirement-or[bool]$RoutingReceipt.requires_new_update_permit_readiness){return & $deny 'fixture-dispatch-routing-requires-separate-policy'}
    $fresh=Resolve-CustomAppProductionRecoveryRoutingAdmissionV010 -AllowedRoot ([string]$envCheck.allowed_root) -StoreDirectory ([string]$envCheck.store_directory) -ExpectedTransactionId $tx -Now $Now
    if($null-eq$fresh-or-not[bool]$fresh.ok){return & $deny ('fixture-dispatch-fresh-routing-denied:'+[string]$fresh.reason)}
    $fc=Test-CustomAppProductionRecoveryRoutingAdmissionReceiptV010 -Receipt $fresh.receipt -Now $Now;if(-not[bool]$fc.ok){return & $deny ('fixture-dispatch-fresh-routing-invalid:'+[string]$fc.reason)}
    foreach($f in @('routing_fingerprint','phase','route','next_validator','journal_revision','journal_entry_sha256')){if([string]$fresh.receipt.$f-cne[string]$RoutingReceipt.$f){return & $deny ('fixture-dispatch-stale-routing-'+$f)}}
    $exec=Invoke-CustomAppProductionBoundedRecoveryExecutorV010 -AllowedRoot ([string]$envCheck.allowed_root) -StoreDirectory ([string]$envCheck.store_directory) -ExpectedTransactionId $tx -LocalAppDataRoot ([string]$envCheck.local_app_data_root) -AppDataRoot ([string]$envCheck.app_data_root) -SpicetifyAllowedRoot ([string]$envCheck.spicetify_allowed_root) -SpicetifyPath ([string]$envCheck.spicetify_path) -ExpectedSpicetifySha256 $ExpectedSpicetifySha256 -TimeoutSeconds $TimeoutSeconds -Now $Now
    if($null-eq$exec-or-not[bool]$exec.ok-or$null-eq$exec.result){return & $deny ('fixture-dispatch-bounded-executor-denied:'+[string]$exec.reason)}
    $ec=Test-CustomAppProductionBoundedRecoveryExecutorResultV010 -Result $exec.result;if(-not[bool]$ec.ok){return & $deny ('fixture-dispatch-bounded-result-invalid:'+[string]$ec.reason)}
    if(([string]$exec.result.transaction_id).Trim().ToLowerInvariant()-cne$tx-or[string]$exec.result.initial_phase-cne[string]$fresh.receipt.phase){return & $deny 'fixture-dispatch-bounded-result-continuity-mismatch'}
    if([string]$fresh.receipt.route-ceq'bounded-recovery-executor-candidate' -and [string]$exec.result.status-cne'rollback-complete'){return & $deny 'fixture-dispatch-recovery-status-mismatch'}
    if([string]$fresh.receipt.route-ceq'bounded-recovery-housekeeping-candidate' -and [string]$exec.result.status-cne'housekeeping-committed-clean'){return & $deny 'fixture-dispatch-housekeeping-status-mismatch'}
    $result=[pscustomobject]@{
        schema=$CustomAppProductionRecoveryRoutingFixtureDispatchSchema;managed_by=$CustomAppProductionRecoveryRoutingFixtureDispatchManagedBy;qualified_router_head=$CustomAppProductionRecoveryRoutingFixtureDispatchQualifiedRouterHead;qualified_bounded_executor_head=$CustomAppProductionRecoveryRoutingFixtureDispatchQualifiedBoundedExecutorHead
        transaction_id=$tx;route=[string]$fresh.receipt.route;initial_phase=[string]$fresh.receipt.phase;route_fingerprint=([string]$fresh.receipt.routing_fingerprint).Trim().ToLowerInvariant();route_journal_revision=[int64]$fresh.receipt.journal_revision;route_journal_entry_sha256=([string]$fresh.receipt.journal_entry_sha256).Trim().ToLowerInvariant()
        executor_result_fingerprint=([string]$exec.result.result_fingerprint).Trim().ToLowerInvariant();executor_status=[string]$exec.result.status;final_phase=[string]$exec.result.final_phase;executor_journal_start_revision=[int64]$exec.result.journal_start_revision;executor_journal_end_revision=[int64]$exec.result.journal_end_revision;executor_journal_end_sha256=([string]$exec.result.journal_end_sha256).Trim().ToLowerInvariant()
        fixture_environment_verified=$true;fixture_only_contract=$true;requires_future_fresh_revalidation=$true;dispatch_is_authority=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;permit_issued=$false;production_mutation_authorized=$false;result_fingerprint=$null
    }
    $result.result_fingerprint=Get-CustomAppProductionRecoveryRoutingFixtureDispatchSha256V010 (Get-CustomAppProductionRecoveryRoutingFixtureDispatchResultMaterialV010 $result)
    $check=Test-CustomAppProductionRecoveryRoutingFixtureDispatchResultV010 -Result $result;if(-not[bool]$check.ok){return & $deny ('fixture-dispatch-self-invalid:'+[string]$check.reason)}
    return [pscustomobject]@{ok=$true;reason='fixture-dispatch-bounded-recovery-complete';result=$result;executor_result=$exec.result;fixture_only_contract=$true;dispatch_is_authority=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;permit_issued=$false;production_mutation_authorized=$false}
}
