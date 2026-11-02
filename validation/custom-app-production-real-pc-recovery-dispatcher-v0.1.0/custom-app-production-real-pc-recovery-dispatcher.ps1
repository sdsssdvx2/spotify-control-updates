$CustomAppProductionRealPcRecoveryDispatcherSchema = 1
$CustomAppProductionRealPcRecoveryDispatcherManagedBy = 'custom-app-production-real-pc-recovery-dispatcher-v1'
$CustomAppProductionRealPcRecoveryDispatcherQualifiedReadinessHead = '999d34a058a6eef3a6f28a137af4f86c26c5c298'
$CustomAppProductionRealPcRecoveryDispatcherQualifiedReadinessCoreBlob = '3729e5e13f5c997e7fe6fb6b83287d71fb2c82eb'
$CustomAppProductionRealPcRecoveryDispatcherQualifiedRoutingHead = 'e4ff8ef949421152999515c5031744e352435f75'
$CustomAppProductionRealPcRecoveryDispatcherQualifiedRoutingCoreBlob = '4225bb042aa8d240706e1f383e54f12894e74512'
$CustomAppProductionRealPcRecoveryDispatcherQualifiedBoundedHead = '5a2840d824f1e28e2920657d0e3a8e139d7e8b71'
$CustomAppProductionRealPcRecoveryDispatcherQualifiedBoundedCoreBlob = 'e580daa3b2f1f506131bc59e0e8969a36bc30441'
$CustomAppProductionRealPcRecoveryDispatcherZeroHash = ('0' * 64)

function Get-CustomAppProductionRealPcRecoveryDispatcherSha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}
function Test-CustomAppProductionRealPcRecoveryDispatcherSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}
function Get-CustomAppProductionRealPcRecoveryDispatcherCanonicalPathV010 {
    param([Parameter(Mandatory=$true)][string]$Path)
    if([string]::IsNullOrWhiteSpace($Path)){throw 'real-pc-recovery-path-empty'}
    return [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
}
function Test-CustomAppProductionRealPcRecoveryDispatcherWithinV010 {
    param([Parameter(Mandatory=$true)][string]$Root,[Parameter(Mandatory=$true)][string]$Path,[bool]$AllowRoot=$false)
    try{$r=Get-CustomAppProductionRealPcRecoveryDispatcherCanonicalPathV010 $Root;$p=Get-CustomAppProductionRealPcRecoveryDispatcherCanonicalPathV010 $Path}catch{return $false}
    if($p.Equals($r,[StringComparison]::OrdinalIgnoreCase)){return $AllowRoot}
    return $p.StartsWith($r+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)
}
function Test-CustomAppProductionRealPcRecoveryDispatcherNoReparseV010 {
    param([Parameter(Mandatory=$true)][string]$Path,[bool]$RequireExisting=$true)
    try{
        if(-not (Test-Path -LiteralPath $Path)){return (-not $RequireExisting)}
        $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        return (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0)
    }catch{return $false}
}
function New-CustomAppProductionRealPcRecoveryDispatcherDeniedV010 {
    param([Parameter(Mandatory=$true)][string]$Reason,[bool]$ExecutorInvoked=$false,[AllowNull()]$GenericResult=$null)
    return [pscustomobject]@{
        ok=$false;reason=$Reason;executor_invoked=$ExecutorInvoked;generic_result=$GenericResult
        terminal_handoff_required=$false;artifact_retirement_required=$false;new_permit_readiness_required=$false
        result_is_authority=$false;routing_is_authority=$false;permit_issued=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false
        production_execution_authorized=$false;production_mutation_authorized=$false
    }
}
function Get-CustomAppProductionRealPcRecoveryDispatcherResultMaterialV010 {
    param([Parameter(Mandatory=$true)]$Result)
    return @(
        [string]$Result.schema,[string]$Result.managed_by,[string]$Result.qualified_readiness_head,[string]$Result.qualified_readiness_core_blob,[string]$Result.qualified_routing_head,[string]$Result.qualified_routing_core_blob,[string]$Result.qualified_bounded_head,[string]$Result.qualified_bounded_core_blob,
        [string]$Result.status,[string]$Result.reason,[string]$Result.transaction_id,[string]$Result.name,[string]$Result.initial_phase,[string]$Result.route,[string]$Result.initial_journal_revision,[string]$Result.initial_journal_sha256,
        [string]$Result.final_phase,[string]$Result.final_journal_revision,[string]$Result.final_journal_sha256,[string]$Result.generic_result_fingerprint,[string]$Result.generic_fixture_contract_verified,[string]$Result.executor_invoked,
        [string]$Result.spicetify_path,[string]$Result.spicetify_executable_sha256,[string]$Result.live_path,[string]$Result.live_tree_sha256,[string]$Result.persistence_fingerprint,
        [string]$Result.terminal_handoff_required,[string]$Result.artifact_retirement_required,[string]$Result.new_permit_readiness_required,
        [string]$Result.result_is_authority,[string]$Result.routing_is_authority,[string]$Result.permit_issued,[string]$Result.execution_authorized,[string]$Result.restore_authorized,[string]$Result.apply_authorized,[string]$Result.cleanup_authorized,[string]$Result.production_execution_authorized,[string]$Result.production_mutation_authorized
    ) -join "`n"
}
function Test-CustomAppProductionRealPcRecoveryDispatcherResultV010 {
    param([AllowNull()]$Result)
    if($null -eq $Result){return [pscustomobject]@{ok=$false;reason='real-pc-recovery-result-null'}}
    $required=@('schema','managed_by','qualified_readiness_head','qualified_readiness_core_blob','qualified_routing_head','qualified_routing_core_blob','qualified_bounded_head','qualified_bounded_core_blob','status','reason','transaction_id','name','initial_phase','route','initial_journal_revision','initial_journal_sha256','final_phase','final_journal_revision','final_journal_sha256','generic_result_fingerprint','generic_fixture_contract_verified','executor_invoked','spicetify_path','spicetify_executable_sha256','live_path','live_tree_sha256','persistence_fingerprint','terminal_handoff_required','artifact_retirement_required','new_permit_readiness_required','result_is_authority','routing_is_authority','permit_issued','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_execution_authorized','production_mutation_authorized','result_fingerprint')
    foreach($f in $required){if(-not $Result.PSObject.Properties[$f]){return [pscustomobject]@{ok=$false;reason=('real-pc-recovery-result-field-missing-'+$f)}}}
    if([int]$Result.schema-ne$CustomAppProductionRealPcRecoveryDispatcherSchema -or [string]$Result.managed_by-cne$CustomAppProductionRealPcRecoveryDispatcherManagedBy -or [string]$Result.qualified_readiness_head-cne$CustomAppProductionRealPcRecoveryDispatcherQualifiedReadinessHead -or [string]$Result.qualified_readiness_core_blob-cne$CustomAppProductionRealPcRecoveryDispatcherQualifiedReadinessCoreBlob -or [string]$Result.qualified_routing_head-cne$CustomAppProductionRealPcRecoveryDispatcherQualifiedRoutingHead -or [string]$Result.qualified_routing_core_blob-cne$CustomAppProductionRealPcRecoveryDispatcherQualifiedRoutingCoreBlob -or [string]$Result.qualified_bounded_head-cne$CustomAppProductionRealPcRecoveryDispatcherQualifiedBoundedHead -or [string]$Result.qualified_bounded_core_blob-cne$CustomAppProductionRealPcRecoveryDispatcherQualifiedBoundedCoreBlob){return [pscustomobject]@{ok=$false;reason='real-pc-recovery-result-owner-lineage-invalid'}}
    foreach($f in @('transaction_id','initial_journal_sha256','final_journal_sha256','spicetify_executable_sha256','live_tree_sha256','persistence_fingerprint','result_fingerprint')){if(-not (Test-CustomAppProductionRealPcRecoveryDispatcherSha256V010 (([string]$Result.$f).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('real-pc-recovery-result-invalid-'+$f)}}}
    if([bool]$Result.executor_invoked){
        if(-not (Test-CustomAppProductionRealPcRecoveryDispatcherSha256V010 (([string]$Result.generic_result_fingerprint).Trim().ToLowerInvariant())) -or -not [bool]$Result.generic_fixture_contract_verified -or [string]$Result.status -notin @('real-pc-recovery-rollback-complete','real-pc-recovery-housekeeping-committed-clean')){return [pscustomobject]@{ok=$false;reason='real-pc-recovery-result-executor-contract-invalid'}}
    }else{
        if([string]$Result.generic_result_fingerprint-cne$CustomAppProductionRealPcRecoveryDispatcherZeroHash -or [bool]$Result.generic_fixture_contract_verified -or [string]$Result.status-cne'real-pc-recovery-terminal-handoff-required' -or -not [bool]$Result.terminal_handoff_required){return [pscustomobject]@{ok=$false;reason='real-pc-recovery-result-terminal-contract-invalid'}}
    }
    foreach($f in @('result_is_authority','routing_is_authority','permit_issued','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_execution_authorized','production_mutation_authorized')){if([bool]$Result.$f){return [pscustomobject]@{ok=$false;reason=('real-pc-recovery-result-authority-escaped-'+$f)}}}
    try{if([int64]$Result.final_journal_revision-lt[int64]$Result.initial_journal_revision){return [pscustomobject]@{ok=$false;reason='real-pc-recovery-result-journal-regressed'}}}catch{return [pscustomobject]@{ok=$false;reason='real-pc-recovery-result-journal-invalid'}}
    $expected=Get-CustomAppProductionRealPcRecoveryDispatcherSha256V010 (Get-CustomAppProductionRealPcRecoveryDispatcherResultMaterialV010 -Result $Result)
    if(([string]$Result.result_fingerprint).Trim().ToLowerInvariant()-cne$expected){return [pscustomobject]@{ok=$false;reason='real-pc-recovery-result-fingerprint-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='real-pc-recovery-result-valid-zero-authority';result_fingerprint=$expected}
}
function New-CustomAppProductionRealPcRecoveryDispatcherResultV010 {
    param([Parameter(Mandatory=$true)][string]$Status,[Parameter(Mandatory=$true)][string]$Reason,[Parameter(Mandatory=$true)][string]$TransactionId,[Parameter(Mandatory=$true)][string]$Name,[Parameter(Mandatory=$true)][string]$InitialPhase,[Parameter(Mandatory=$true)][string]$Route,[Parameter(Mandatory=$true)][int64]$InitialJournalRevision,[Parameter(Mandatory=$true)][string]$InitialJournalSha256,[Parameter(Mandatory=$true)][string]$FinalPhase,[Parameter(Mandatory=$true)][int64]$FinalJournalRevision,[Parameter(Mandatory=$true)][string]$FinalJournalSha256,[Parameter(Mandatory=$true)][string]$GenericResultFingerprint,[bool]$GenericFixtureContractVerified,[bool]$ExecutorInvoked,[Parameter(Mandatory=$true)][string]$SpicetifyPath,[Parameter(Mandatory=$true)][string]$SpicetifyExecutableSha256,[Parameter(Mandatory=$true)][string]$LivePath,[Parameter(Mandatory=$true)][string]$LiveTreeSha256,[Parameter(Mandatory=$true)][string]$PersistenceFingerprint,[bool]$TerminalHandoffRequired,[bool]$ArtifactRetirementRequired,[bool]$NewPermitReadinessRequired)
    $result=[pscustomobject]@{
        schema=$CustomAppProductionRealPcRecoveryDispatcherSchema;managed_by=$CustomAppProductionRealPcRecoveryDispatcherManagedBy;qualified_readiness_head=$CustomAppProductionRealPcRecoveryDispatcherQualifiedReadinessHead;qualified_readiness_core_blob=$CustomAppProductionRealPcRecoveryDispatcherQualifiedReadinessCoreBlob;qualified_routing_head=$CustomAppProductionRealPcRecoveryDispatcherQualifiedRoutingHead;qualified_routing_core_blob=$CustomAppProductionRealPcRecoveryDispatcherQualifiedRoutingCoreBlob;qualified_bounded_head=$CustomAppProductionRealPcRecoveryDispatcherQualifiedBoundedHead;qualified_bounded_core_blob=$CustomAppProductionRealPcRecoveryDispatcherQualifiedBoundedCoreBlob
        status=$Status;reason=$Reason;transaction_id=$TransactionId;name=$Name;initial_phase=$InitialPhase;route=$Route;initial_journal_revision=$InitialJournalRevision;initial_journal_sha256=$InitialJournalSha256;final_phase=$FinalPhase;final_journal_revision=$FinalJournalRevision;final_journal_sha256=$FinalJournalSha256;generic_result_fingerprint=$GenericResultFingerprint;generic_fixture_contract_verified=$GenericFixtureContractVerified;executor_invoked=$ExecutorInvoked
        spicetify_path=$SpicetifyPath;spicetify_executable_sha256=$SpicetifyExecutableSha256;live_path=$LivePath;live_tree_sha256=$LiveTreeSha256;persistence_fingerprint=$PersistenceFingerprint;terminal_handoff_required=$TerminalHandoffRequired;artifact_retirement_required=$ArtifactRetirementRequired;new_permit_readiness_required=$NewPermitReadinessRequired
        result_is_authority=$false;routing_is_authority=$false;permit_issued=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false;result_fingerprint=$null
    }
    $result.result_fingerprint=Get-CustomAppProductionRealPcRecoveryDispatcherSha256V010 (Get-CustomAppProductionRealPcRecoveryDispatcherResultMaterialV010 -Result $result)
    return $result
}
function Invoke-CustomAppProductionRealPcRecoveryDispatcherV010 {
    param(
        [Parameter(Mandatory=$true)][string]$ExpectedTransactionId,
        [string]$UserProfileRoot=$env:USERPROFILE,[string]$LocalAppDataRoot=$env:LOCALAPPDATA,[string]$AppDataRoot=$env:APPDATA,[AllowNull()][string]$StoreDirectory=$null,
        [Parameter(Mandatory=$true)][string]$SpicetifyPath,[Parameter(Mandatory=$true)][string]$ExpectedSpicetifySha256,
        [int]$TimeoutSeconds=180,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow
    )
    $deny={param([string]$Reason,[bool]$ExecutorInvoked=$false,$GenericResult=$null) New-CustomAppProductionRealPcRecoveryDispatcherDeniedV010 -Reason $Reason -ExecutorInvoked $ExecutorInvoked -GenericResult $GenericResult}
    $tx=$ExpectedTransactionId.Trim().ToLowerInvariant();if(-not (Test-CustomAppProductionRealPcRecoveryDispatcherSha256V010 $tx)){return & $deny 'real-pc-recovery-transaction-id-invalid'}
    if($TimeoutSeconds-lt1 -or $TimeoutSeconds-gt600){return & $deny 'real-pc-recovery-timeout-policy-invalid'}
    try{$profile=Get-CustomAppProductionRealPcRecoveryDispatcherCanonicalPathV010 $UserProfileRoot;$local=Get-CustomAppProductionRealPcRecoveryDispatcherCanonicalPathV010 $LocalAppDataRoot;$app=Get-CustomAppProductionRealPcRecoveryDispatcherCanonicalPathV010 $AppDataRoot;$envProfile=Get-CustomAppProductionRealPcRecoveryDispatcherCanonicalPathV010 $env:USERPROFILE;$envLocal=Get-CustomAppProductionRealPcRecoveryDispatcherCanonicalPathV010 $env:LOCALAPPDATA;$envApp=Get-CustomAppProductionRealPcRecoveryDispatcherCanonicalPathV010 $env:APPDATA}catch{return & $deny 'real-pc-recovery-current-user-root-invalid'}
    if(-not $profile.Equals($envProfile,[StringComparison]::OrdinalIgnoreCase) -or -not $local.Equals($envLocal,[StringComparison]::OrdinalIgnoreCase) -or -not $app.Equals($envApp,[StringComparison]::OrdinalIgnoreCase) -or -not (Test-CustomAppProductionRealPcRecoveryDispatcherWithinV010 -Root $profile -Path $local) -or -not (Test-CustomAppProductionRealPcRecoveryDispatcherWithinV010 -Root $profile -Path $app)){return & $deny 'real-pc-recovery-current-user-root-mismatch'}
    foreach($p in @($profile,$local,$app)){if(-not (Test-CustomAppProductionRealPcRecoveryDispatcherNoReparseV010 -Path $p)){return & $deny 'real-pc-recovery-current-user-root-missing-or-reparse'}}
    $expectedStore=Get-CustomAppProductionRealPcRecoveryDispatcherCanonicalPathV010 (Join-Path $local 'SpotifyControl\custom-app-production\recovery-journal')
    if([string]::IsNullOrWhiteSpace($StoreDirectory)){$store=$expectedStore}else{try{$store=Get-CustomAppProductionRealPcRecoveryDispatcherCanonicalPathV010 $StoreDirectory}catch{return & $deny 'real-pc-recovery-store-invalid'}}
    if(-not $store.Equals($expectedStore,[StringComparison]::OrdinalIgnoreCase) -or -not (Test-CustomAppProductionRealPcRecoveryDispatcherNoReparseV010 -Path $store)){return & $deny 'real-pc-recovery-store-not-exact-current-user-location'}
    try{$sp=Get-CustomAppProductionRealPcRecoveryDispatcherCanonicalPathV010 $SpicetifyPath}catch{return & $deny 'real-pc-recovery-spicetify-path-invalid'}
    if(-not (Test-CustomAppProductionRealPcRecoveryDispatcherWithinV010 -Root $profile -Path $sp) -or -not (Test-CustomAppProductionRealPcRecoveryDispatcherNoReparseV010 -Path $sp)){return & $deny 'real-pc-recovery-spicetify-outside-profile-or-unsafe'}
    $expectedSha=$ExpectedSpicetifySha256.Trim().ToLowerInvariant();if(-not (Test-CustomAppProductionRealPcRecoveryDispatcherSha256V010 $expectedSha)){return & $deny 'real-pc-recovery-spicetify-sha-invalid'}
    try{$actualSha=(Get-FileHash -LiteralPath $sp -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()}catch{return & $deny 'real-pc-recovery-spicetify-hash-read-failed'}
    if($actualSha-cne$expectedSha){return & $deny 'real-pc-recovery-spicetify-hash-mismatch'}
    $spRoot=Get-CustomAppProductionRealPcRecoveryDispatcherCanonicalPathV010 ([IO.Path]::GetDirectoryName($sp));if(-not (Test-CustomAppProductionRealPcRecoveryDispatcherNoReparseV010 -Path $spRoot)){return & $deny 'real-pc-recovery-spicetify-parent-unsafe'}
    try{$pre=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $profile -StoreDirectory $store}catch{return & $deny ('real-pc-recovery-journal-read-failed:'+[string]$_.Exception.Message)}
    if($null-eq$pre -or -not [bool]$pre.ok -or -not [bool]$pre.reloaded_from_persistent_store -or ([string]$pre.transaction_id).Trim().ToLowerInvariant()-cne$tx){return & $deny 'real-pc-recovery-journal-not-durable-or-transaction-mismatch'}
    $e=$pre.entry
    foreach($f in @('transaction_root','stage_workspace_path','app_backup_path','persistence_backup_path')){if(-not (Test-CustomAppProductionRealPcRecoveryDispatcherWithinV010 -Root $profile -Path ([string]$e.$f))){return & $deny ('real-pc-recovery-journal-path-outside-profile-'+$f)}}
    try{
        $live=Get-CustomAppProductionRealPcRecoveryDispatcherCanonicalPathV010 ([string]$e.live_path)
        $roots=@(Get-SpicetifyAssetRoots -Kind 'CustomApp'|ForEach-Object{Get-CustomAppProductionRealPcRecoveryDispatcherCanonicalPathV010 ([string]$_)}|Select-Object -Unique)
        $liveParent=Get-CustomAppProductionRealPcRecoveryDispatcherCanonicalPathV010 ([IO.Path]::GetDirectoryName($live))
    }catch{return & $deny 'real-pc-recovery-live-root-read-failed'}
    $matches=@($roots|Where-Object{$liveParent.Equals($_,[StringComparison]::OrdinalIgnoreCase)})
    if($matches.Count-ne1 -or -not (Test-CustomAppProductionRealPcRecoveryDispatcherNoReparseV010 -Path ([string]$matches[0])) -or -not (Test-CustomAppProductionRealPcRecoveryDispatcherNoReparseV010 -Path $live -RequireExisting:$false)){return & $deny 'real-pc-recovery-live-path-not-bound-to-safe-spicetify-root'}
    $routing=Resolve-CustomAppProductionRecoveryRoutingAdmissionV010 -AllowedRoot $profile -StoreDirectory $store -ExpectedTransactionId $tx -Now $Now
    if($null-eq$routing -or -not [bool]$routing.ok -or $null-eq$routing.receipt){return & $deny ('real-pc-recovery-routing-denied:'+[string]$routing.reason)}
    $rc=Test-CustomAppProductionRecoveryRoutingAdmissionReceiptV010 -Receipt $routing.receipt -Now $Now;if($null-eq$rc -or -not [bool]$rc.ok){return & $deny ('real-pc-recovery-routing-invalid:'+[string]$rc.reason)}
    foreach($f in @('routing_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','permit_issued','production_mutation_authorized')){if([bool]$routing.receipt.$f){return & $deny ('real-pc-recovery-routing-authority-drift-'+$f)}}
    if([int64]$routing.receipt.journal_revision-ne[int64]$pre.revision -or ([string]$routing.receipt.journal_entry_sha256).Trim().ToLowerInvariant()-cne([string]$pre.entry.entry_sha256).Trim().ToLowerInvariant()){return & $deny 'real-pc-recovery-routing-stale-vs-pre-read'}
    if([bool]$routing.receipt.requires_manual_resolution){return & $deny ('real-pc-recovery-manual-resolution-required:'+[string]$routing.receipt.route)}
    $terminal=([string]$routing.receipt.phase-in@('rollback-complete','committed-clean'))
    if($terminal){
        try{$liveBaseline=Get-CustomAppLocalRuntimeBaseline -Name ([string]$e.name) -AppPath $live}catch{return & $deny ('real-pc-recovery-terminal-live-read-failed:'+[string]$_.Exception.Message)}
        if($null-eq$liveBaseline -or -not [bool]$liveBaseline.safe -or -not [bool]$liveBaseline.installable -or -not (Test-CustomAppProductionRealPcRecoveryDispatcherSha256V010 ([string]$liveBaseline.tree_sha256))){return & $deny 'real-pc-recovery-terminal-live-invalid'}
        try{$persist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $local -AppDataRoot $app}catch{return & $deny ('real-pc-recovery-terminal-persistence-read-failed:'+[string]$_.Exception.Message)}
        if($null-eq$persist -or -not (Test-CustomAppProductionRealPcRecoveryDispatcherSha256V010 ([string]$persist.fingerprint))){return & $deny 'real-pc-recovery-terminal-persistence-invalid'}
        $result=New-CustomAppProductionRealPcRecoveryDispatcherResultV010 -Status 'real-pc-recovery-terminal-handoff-required' -Reason 'terminal-journal-reverified-no-executor-invoked' -TransactionId $tx -Name ([string]$e.name) -InitialPhase ([string]$e.phase) -Route ([string]$routing.receipt.route) -InitialJournalRevision ([int64]$pre.revision) -InitialJournalSha256 (([string]$pre.entry.entry_sha256).Trim().ToLowerInvariant()) -FinalPhase ([string]$e.phase) -FinalJournalRevision ([int64]$pre.revision) -FinalJournalSha256 (([string]$pre.entry.entry_sha256).Trim().ToLowerInvariant()) -GenericResultFingerprint $CustomAppProductionRealPcRecoveryDispatcherZeroHash -GenericFixtureContractVerified:$false -ExecutorInvoked:$false -SpicetifyPath $sp -SpicetifyExecutableSha256 $actualSha -LivePath $live -LiveTreeSha256 (([string]$liveBaseline.tree_sha256).Trim().ToLowerInvariant()) -PersistenceFingerprint (([string]$persist.fingerprint).Trim().ToLowerInvariant()) -TerminalHandoffRequired:$true -ArtifactRetirementRequired:([string]$e.phase-ceq'rollback-complete') -NewPermitReadinessRequired:$true
        $check=Test-CustomAppProductionRealPcRecoveryDispatcherResultV010 -Result $result;if(-not [bool]$check.ok){return & $deny ('real-pc-recovery-terminal-self-invalid:'+[string]$check.reason)}
        return [pscustomobject]@{ok=$true;reason=[string]$result.reason;result=$result;executor_invoked=$false;terminal_handoff_required=$true;production_mutation_authorized=$false}
    }
    if(-not ([bool]$routing.receipt.requires_bounded_recovery_executor -or [bool]$routing.receipt.requires_bounded_housekeeping)){return & $deny 'real-pc-recovery-route-not-executable-by-bounded-dispatcher'}
    $generic=Invoke-CustomAppProductionBoundedRecoveryExecutorV010 -AllowedRoot $profile -StoreDirectory $store -ExpectedTransactionId $tx -LocalAppDataRoot $local -AppDataRoot $app -SpicetifyAllowedRoot $spRoot -SpicetifyPath $sp -ExpectedSpicetifySha256 $actualSha -TimeoutSeconds $TimeoutSeconds -Now $Now
    if($null-eq$generic){return & $deny 'real-pc-recovery-bounded-executor-null' $true}
    if(-not [bool]$generic.ok -or $null-eq$generic.result){return & $deny ('real-pc-recovery-bounded-executor-denied:'+[string]$generic.reason) $true $generic}
    $gc=Test-CustomAppProductionBoundedRecoveryExecutorResultV010 -Result $generic.result;if($null-eq$gc -or -not [bool]$gc.ok -or -not [bool]$generic.result.fixture_only_contract){return & $deny ('real-pc-recovery-bounded-result-invalid:'+[string]$gc.reason) $true $generic}
    try{$post=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $profile -StoreDirectory $store}catch{return & $deny ('real-pc-recovery-post-journal-read-failed:'+[string]$_.Exception.Message) $true $generic}
    if($null-eq$post -or -not [bool]$post.ok -or ([string]$post.transaction_id).Trim().ToLowerInvariant()-cne$tx -or [string]$post.entry.phase-notin@('rollback-complete','committed-clean')){return & $deny 'real-pc-recovery-post-journal-not-terminal' $true $generic}
    if([int64]$post.revision-lt[int64]$pre.revision -or [string]$generic.result.final_phase-cne[string]$post.entry.phase -or [int64]$generic.result.journal_end_revision-ne[int64]$post.revision -or ([string]$generic.result.journal_end_sha256).Trim().ToLowerInvariant()-cne([string]$post.entry.entry_sha256).Trim().ToLowerInvariant()){return & $deny 'real-pc-recovery-post-journal-generic-continuity-drift' $true $generic}
    try{$liveAfter=Get-CustomAppLocalRuntimeBaseline -Name ([string]$e.name) -AppPath $live}catch{return & $deny ('real-pc-recovery-post-live-read-failed:'+[string]$_.Exception.Message) $true $generic}
    if($null-eq$liveAfter -or -not [bool]$liveAfter.safe -or -not [bool]$liveAfter.installable -or ([string]$liveAfter.tree_sha256).Trim().ToLowerInvariant()-cne([string]$generic.result.live_runtime_tree_sha256).Trim().ToLowerInvariant()){return & $deny 'real-pc-recovery-post-live-drift' $true $generic}
    try{$persistAfter=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $local -AppDataRoot $app}catch{return & $deny ('real-pc-recovery-post-persistence-read-failed:'+[string]$_.Exception.Message) $true $generic}
    if($null-eq$persistAfter -or ([string]$persistAfter.fingerprint).Trim().ToLowerInvariant()-cne([string]$generic.result.persistence_fingerprint).Trim().ToLowerInvariant()){return & $deny 'real-pc-recovery-post-persistence-drift' $true $generic}
    $status=if([string]$post.entry.phase-ceq'rollback-complete'){'real-pc-recovery-rollback-complete'}else{'real-pc-recovery-housekeeping-committed-clean'}
    $result=New-CustomAppProductionRealPcRecoveryDispatcherResultV010 -Status $status -Reason 'bounded-recovery-executor-completed-under-real-pc-attestation' -TransactionId $tx -Name ([string]$e.name) -InitialPhase ([string]$e.phase) -Route ([string]$routing.receipt.route) -InitialJournalRevision ([int64]$pre.revision) -InitialJournalSha256 (([string]$pre.entry.entry_sha256).Trim().ToLowerInvariant()) -FinalPhase ([string]$post.entry.phase) -FinalJournalRevision ([int64]$post.revision) -FinalJournalSha256 (([string]$post.entry.entry_sha256).Trim().ToLowerInvariant()) -GenericResultFingerprint (([string]$generic.result.result_fingerprint).Trim().ToLowerInvariant()) -GenericFixtureContractVerified:$true -ExecutorInvoked:$true -SpicetifyPath $sp -SpicetifyExecutableSha256 $actualSha -LivePath $live -LiveTreeSha256 (([string]$liveAfter.tree_sha256).Trim().ToLowerInvariant()) -PersistenceFingerprint (([string]$persistAfter.fingerprint).Trim().ToLowerInvariant()) -TerminalHandoffRequired:$true -ArtifactRetirementRequired:([string]$post.entry.phase-ceq'rollback-complete') -NewPermitReadinessRequired:$true
    $check=Test-CustomAppProductionRealPcRecoveryDispatcherResultV010 -Result $result;if(-not [bool]$check.ok){return & $deny ('real-pc-recovery-self-invalid:'+[string]$check.reason) $true $generic}
    return [pscustomobject]@{ok=$true;reason=[string]$result.reason;result=$result;executor_invoked=$true;terminal_handoff_required=$true;production_mutation_authorized=$false}
}
