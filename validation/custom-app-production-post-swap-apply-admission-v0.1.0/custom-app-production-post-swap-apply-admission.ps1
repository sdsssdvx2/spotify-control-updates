$CustomAppProductionPostSwapApplyAdmissionSchema = 1
$CustomAppProductionPostSwapApplyAdmissionManagedBy = 'custom-app-production-post-swap-apply-admission-v1'
$CustomAppProductionPostSwapApplyAdmissionQualifiedFinalizationHead = '75a39eea7b0ef7d35d193962607752ef1a873ae0'

function Get-CustomAppProductionPostSwapApplyAdmissionSha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}

function Test-CustomAppProductionPostSwapApplyAdmissionSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}

function Test-CustomAppProductionPostSwapPermitIntegrityV010 {
    param([AllowNull()]$Permit,[Parameter(Mandatory=$true)][byte[]]$SessionKey,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow)
    if($null -eq $Permit){return [pscustomobject]@{ok=$false;reason='permit-null'}}
    if([int]$Permit.schema -ne $CustomAppProductionPermitSchema -or [string]$Permit.managed_by -cne $CustomAppProductionPermitManagedBy -or [string]$Permit.qualified_admission_head -cne $CustomAppProductionPermitQualifiedAdmissionHead -or [string]$Permit.scope -cne $CustomAppProductionPermitScope){return [pscustomobject]@{ok=$false;reason='permit-owner-schema-scope-or-parent-mismatch'}}
    if(-not [bool]$Permit.production_permit_issued -or [bool]$Permit.permit_is_authority -or -not [bool]$Permit.single_use -or -not [bool]$Permit.requires_single_use_consumption -or -not [bool]$Permit.requires_fresh_admission_revalidation_on_consume -or -not [bool]$Permit.replay_protection_requires_external_consumption_ledger){return [pscustomobject]@{ok=$false;reason='permit-contract-invalid'}}
    if([string]$Permit.mutation_mode -cne 'deny'){return [pscustomobject]@{ok=$false;reason='permit-mutation-mode-not-deny'}}
    foreach($field in @('mutation_authorized','auto_update_authorized','auto_install_authorized','canary_execution_authorized','production_execution_authorized','production_mutation_authorized')){if([bool]$Permit.$field){return [pscustomobject]@{ok=$false;reason=('permit-'+$field+'-true')}}}
    if($SessionKey.Length -lt 32){return [pscustomobject]@{ok=$false;reason='permit-session-key-too-short'}}
    if(-not (Test-CustomAppProductionPermitNonceV010 ([string]$Permit.nonce)) -or -not (Test-CustomAppProductionPermitSha256V010 ([string]$Permit.token_id)) -or -not (Test-CustomAppProductionPermitSha256V010 ([string]$Permit.hmac_sha256))){return [pscustomobject]@{ok=$false;reason='permit-token-identity-invalid'}}
    $issued=[DateTimeOffset]::MinValue;$expires=[DateTimeOffset]::MinValue
    if(-not [DateTimeOffset]::TryParse([string]$Permit.issued_at,[ref]$issued) -or -not [DateTimeOffset]::TryParse([string]$Permit.expires_at,[ref]$expires)){return [pscustomobject]@{ok=$false;reason='permit-time-invalid'}}
    if($expires -le $issued -or $expires -gt $issued.AddMinutes(5)){return [pscustomobject]@{ok=$false;reason='permit-ttl-invalid'}}
    if($Now -lt $issued.AddSeconds(-30)){return [pscustomobject]@{ok=$false;reason='permit-not-yet-valid'}}
    if($Now -ge $expires){return [pscustomobject]@{ok=$false;reason='permit-expired'}}
    $material=Get-CustomAppProductionPermitMaterialV010 -Permit $Permit
    $token=Get-CustomAppProductionPermitSha256V010 -Text $material
    $hmac=Get-CustomAppProductionPermitHmacV010 -Text $material -SessionKey $SessionKey
    if(-not (Test-CustomAppProductionPermitFixedTimeHexV010 ([string]$Permit.token_id).ToLowerInvariant() $token)){return [pscustomobject]@{ok=$false;reason='permit-token-id-mismatch'}}
    if(-not (Test-CustomAppProductionPermitFixedTimeHexV010 ([string]$Permit.hmac_sha256).ToLowerInvariant() $hmac)){return [pscustomobject]@{ok=$false;reason='permit-hmac-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='permit-cryptographically-valid-post-swap';token_id=$token;expires_at=$expires}
}

function Test-CustomAppProductionPostSwapConsumptionContinuityV010 {
    param(
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory,[Parameter(Mandatory=$true)][string]$ExpectedConsumptionId,
        [Parameter(Mandatory=$true)]$Permit,[Parameter(Mandatory=$true)]$StageExecutorResult,[Parameter(Mandatory=$true)][string]$Name
    )
    try{$store=Read-CustomAppProductionConsumptionStoreV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory}
    catch{return [pscustomobject]@{ok=$false;reason=('persisted-consumption-read-denied:'+[string]$_.Exception.Message)}}
    if($null -eq $store -or -not [bool]$store.ok -or -not [bool]$store.reloaded_from_persistent_store){return [pscustomobject]@{ok=$false;reason=('persisted-consumption-invalid:'+[string]$store.reason)}}
    $stateCheck=Test-CustomAppProductionExecutorConsumptionStateV010 -State $store.state
    if(-not [bool]$stateCheck.ok){return [pscustomobject]@{ok=$false;reason=('persisted-consumption-state-invalid:'+[string]$stateCheck.reason)}}
    $id=$ExpectedConsumptionId.Trim().ToLowerInvariant()
    if(-not (Test-CustomAppProductionExecutorConsumptionSha256V010 $id)){return [pscustomobject]@{ok=$false;reason='expected-consumption-id-invalid'}}
    $rows=@($store.state.consumptions);$matches=@();$matchedIndex=-1
    for($i=0;$i -lt $rows.Count;$i++){if(([string]$rows[$i].consumption_id).Trim().ToLowerInvariant() -ceq $id){$matches+=@($rows[$i]);$matchedIndex=$i}}
    if($matches.Count -ne 1){return [pscustomobject]@{ok=$false;reason='persisted-consumption-not-found-or-ambiguous'}}
    $row=$matches[0]
    for($i=$matchedIndex+1;$i -lt $rows.Count;$i++){if(([string]$rows[$i].name).Trim().ToLowerInvariant() -ceq $Name.Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason='newer-same-app-consumption-exists'}}}
    $pairs=@(
        @('token_id',[string]$Permit.token_id),@('permit_nonce',[string]$Permit.nonce),@('permit_hmac_sha256',[string]$Permit.hmac_sha256),@('name',[string]$Permit.name),
        @('source_identity',[string]$StageExecutorResult.source_identity),@('surface_kind',[string]$StageExecutorResult.surface_kind),@('current_tree_sha256',[string]$Permit.current_tree_sha256),
        @('remote_tree_sha256',[string]$StageExecutorResult.remote_tree_sha256),@('remote_commit_sha',[string]$StageExecutorResult.remote_commit_sha)
    )
    foreach($pair in $pairs){if(([string]$row.($pair[0])).Trim().ToLowerInvariant() -cne ([string]$pair[1]).Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason=('consumption-continuity-mismatch-'+[string]$pair[0])}}}
    try{if([int64]$row.github_repo_id -ne [int64]$StageExecutorResult.github_repo_id -or [int64]$row.github_repo_id -ne [int64]$Permit.github_repo_id){return [pscustomobject]@{ok=$false;reason='consumption-continuity-mismatch-github_repo_id'}}}catch{return [pscustomobject]@{ok=$false;reason='consumption-repo-id-invalid'}}
    if(([string]$row.current_tree_sha256).Trim().ToLowerInvariant() -cne ([string]$StageExecutorResult.local_tree_sha256).Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason='consumption-stage-old-local-tree-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='persisted-single-use-consumption-continuity-valid';row=$row;store=$store;current_envelope_sha256=([string]$store.envelope.envelope_sha256).Trim().ToLowerInvariant()}
}

function Get-CustomAppProductionPostSwapApplyAdmissionMaterialV010 {
    param([Parameter(Mandatory=$true)]$Decision)
    return @(
        [string]$Decision.schema,[string]$Decision.managed_by,[string]$Decision.qualified_finalization_head,[string]$Decision.reason,
        [string]$Decision.consumption_id,[string]$Decision.finalization_fingerprint,[string]$Decision.preparation_fingerprint,[string]$Decision.stage_result_fingerprint,
        [string]$Decision.name,[string]$Decision.source_identity,[string]$Decision.github_repo_id,[string]$Decision.surface_kind,[string]$Decision.live_tree_sha256,[string]$Decision.remote_tree_sha256,[string]$Decision.remote_commit_sha,[string]$Decision.binding_fingerprint,
        [string]$Decision.preserved_git_tree_sha256,[string]$Decision.persistence_fingerprint,[string]$Decision.current_consumption_envelope_sha256,[string]$Decision.evaluated_at,[string]$Decision.apply_eligibility_expires_at,
        [string]$Decision.apply_eligible,[string]$Decision.admission_is_authority,[string]$Decision.requires_immediate_rerun_by_apply_executor,[string]$Decision.requires_exact_spicetify_apply_executor,[string]$Decision.requires_exact_rollback_on_apply_failure,
        [string]$Decision.apply_execution_authorized,[string]$Decision.spicetify_apply_authorized,[string]$Decision.additional_mutation_authorized,[string]$Decision.production_execution_authorized,[string]$Decision.production_mutation_authorized
    ) -join "`n"
}

function Test-CustomAppProductionPostSwapApplyAdmissionDecisionV010 {
    param([AllowNull()]$Decision)
    if($null -eq $Decision){return [pscustomobject]@{ok=$false;reason='post-swap-apply-admission-null'}}
    $required=@('schema','managed_by','qualified_finalization_head','reason','consumption_id','finalization_fingerprint','preparation_fingerprint','stage_result_fingerprint','name','source_identity','github_repo_id','surface_kind','live_tree_sha256','remote_tree_sha256','remote_commit_sha','binding_fingerprint','persistence_fingerprint','current_consumption_envelope_sha256','evaluated_at','apply_eligibility_expires_at','apply_eligible','admission_fingerprint','admission_is_authority','requires_immediate_rerun_by_apply_executor','requires_exact_spicetify_apply_executor','requires_exact_rollback_on_apply_failure','apply_execution_authorized','spicetify_apply_authorized','additional_mutation_authorized','production_execution_authorized','production_mutation_authorized')
    foreach($field in $required){if(-not $Decision.PSObject.Properties[$field]){return [pscustomobject]@{ok=$false;reason=('post-swap-apply-admission-required-field-missing-'+$field)}}}
    if([int]$Decision.schema -ne $CustomAppProductionPostSwapApplyAdmissionSchema -or [string]$Decision.managed_by -cne $CustomAppProductionPostSwapApplyAdmissionManagedBy -or [string]$Decision.qualified_finalization_head -cne $CustomAppProductionPostSwapApplyAdmissionQualifiedFinalizationHead -or [string]$Decision.reason -cne 'post-swap-current-state-eligible-for-bounded-apply-executor'){return [pscustomobject]@{ok=$false;reason='post-swap-apply-admission-owner-schema-parent-or-reason-invalid'}}
    if(-not [bool]$Decision.apply_eligible -or [bool]$Decision.admission_is_authority -or -not [bool]$Decision.requires_immediate_rerun_by_apply_executor -or -not [bool]$Decision.requires_exact_spicetify_apply_executor -or -not [bool]$Decision.requires_exact_rollback_on_apply_failure){return [pscustomobject]@{ok=$false;reason='post-swap-apply-admission-separation-contract-invalid'}}
    foreach($field in @('apply_execution_authorized','spicetify_apply_authorized','additional_mutation_authorized','production_execution_authorized','production_mutation_authorized')){if([bool]$Decision.$field){return [pscustomobject]@{ok=$false;reason=('post-swap-apply-admission-'+$field+'-true')}}}
    foreach($field in @('consumption_id','finalization_fingerprint','preparation_fingerprint','stage_result_fingerprint','live_tree_sha256','remote_tree_sha256','binding_fingerprint','persistence_fingerprint','current_consumption_envelope_sha256','admission_fingerprint')){if(-not (Test-CustomAppProductionPostSwapApplyAdmissionSha256V010 (([string]$Decision.$field).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('post-swap-apply-admission-invalid-'+$field)}}}
    if($Decision.PSObject.Properties['preserved_git_tree_sha256'] -and -not [string]::IsNullOrWhiteSpace([string]$Decision.preserved_git_tree_sha256) -and -not (Test-CustomAppProductionPostSwapApplyAdmissionSha256V010 (([string]$Decision.preserved_git_tree_sha256).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason='post-swap-apply-admission-invalid-preserved-git-tree'}}
    if(([string]$Decision.remote_commit_sha).Trim().ToLowerInvariant() -notmatch '^[0-9a-f]{40}$'){return [pscustomobject]@{ok=$false;reason='post-swap-apply-admission-invalid-remote-commit'}}
    try{if([int64]$Decision.github_repo_id -le 0){return [pscustomobject]@{ok=$false;reason='post-swap-apply-admission-invalid-repo-id'}}}catch{return [pscustomobject]@{ok=$false;reason='post-swap-apply-admission-invalid-repo-id'}}
    $evaluated=[DateTimeOffset]::MinValue;$expires=[DateTimeOffset]::MinValue
    if(-not [DateTimeOffset]::TryParse([string]$Decision.evaluated_at,[ref]$evaluated) -or -not [DateTimeOffset]::TryParse([string]$Decision.apply_eligibility_expires_at,[ref]$expires) -or $expires -le $evaluated -or $expires -gt $evaluated.AddSeconds(20)){return [pscustomobject]@{ok=$false;reason='post-swap-apply-admission-time-window-invalid'}}
    $expected=Get-CustomAppProductionPostSwapApplyAdmissionSha256V010 (Get-CustomAppProductionPostSwapApplyAdmissionMaterialV010 -Decision $Decision)
    if(([string]$Decision.admission_fingerprint).Trim().ToLowerInvariant() -cne $expected){return [pscustomobject]@{ok=$false;reason='post-swap-apply-admission-fingerprint-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='post-swap-apply-admission-valid-non-authority';admission_fingerprint=$expected}
}

function Resolve-CustomAppProductionPostSwapApplyAdmissionV010 {
    param(
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory,[Parameter(Mandatory=$true)][string]$ExpectedConsumptionId,
        [AllowNull()]$Permit,[AllowNull()]$FinalizationResult,[AllowNull()]$PreparedResult,[AllowNull()]$StageExecutorResult,[Parameter(Mandatory=$true)][string]$Name,
        [AllowNull()]$LifecycleRow,[AllowNull()]$ProvenanceRow,[AllowNull()]$BindingRow,[Parameter(Mandatory=$true)][byte[]]$SessionKey,
        [Parameter(Mandatory=$true)][string]$LocalAppDataRoot,[Parameter(Mandatory=$true)][string]$AppDataRoot,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow,[int]$MaxRemoteObservationAgeHours=36
    )
    $deny={param([string]$Reason)[pscustomobject]@{ok=$false;reason=$Reason;apply_eligible=$false;admission_is_authority=$false;requires_immediate_rerun_by_apply_executor=$true;requires_exact_spicetify_apply_executor=$true;requires_exact_rollback_on_apply_failure=$true;apply_execution_authorized=$false;spicetify_apply_authorized=$false;additional_mutation_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false}}
    if($MaxRemoteObservationAgeHours -lt 1 -or $MaxRemoteObservationAgeHours -gt 168){return & $deny 'remote-observation-age-policy-invalid'}

    $finalCheck=Test-CustomAppProductionTransactionFinalizationResultV010 -Result $FinalizationResult
    if(-not [bool]$finalCheck.ok){return & $deny ('finalization-result-invalid:'+[string]$finalCheck.reason)}
    $preparedCheck=Test-CustomAppProductionPreApplyPreparedResultV010 -Result $PreparedResult
    if(-not [bool]$preparedCheck.ok){return & $deny ('prepared-result-invalid:'+[string]$preparedCheck.reason)}
    $stageCheck=Test-CustomAppProductionStageExecutorResultV010 -Result $StageExecutorResult
    if(-not [bool]$stageCheck.ok){return & $deny ('stage-result-invalid:'+[string]$stageCheck.reason)}
    if(([string]$FinalizationResult.name).Trim().ToLowerInvariant() -cne $Name.Trim().ToLowerInvariant() -or ([string]$PreparedResult.name).Trim().ToLowerInvariant() -cne $Name.Trim().ToLowerInvariant() -or ([string]$StageExecutorResult.name).Trim().ToLowerInvariant() -cne $Name.Trim().ToLowerInvariant()){return & $deny 'name-continuity-mismatch'}
    $cid=$ExpectedConsumptionId.Trim().ToLowerInvariant()
    if(([string]$FinalizationResult.consumption_id).Trim().ToLowerInvariant() -cne $cid -or ([string]$PreparedResult.consumption_id).Trim().ToLowerInvariant() -cne $cid -or ([string]$StageExecutorResult.consumption_id).Trim().ToLowerInvariant() -cne $cid){return & $deny 'consumption-continuity-mismatch'}
    if(([string]$FinalizationResult.stage_result_fingerprint).Trim().ToLowerInvariant() -cne ([string]$StageExecutorResult.result_fingerprint).Trim().ToLowerInvariant() -or ([string]$PreparedResult.stage_result_fingerprint).Trim().ToLowerInvariant() -cne ([string]$StageExecutorResult.result_fingerprint).Trim().ToLowerInvariant()){return & $deny 'stage-result-fingerprint-continuity-mismatch'}
    if(([string]$FinalizationResult.preparation_fingerprint).Trim().ToLowerInvariant() -cne ([string]$PreparedResult.preparation_fingerprint).Trim().ToLowerInvariant()){return & $deny 'preparation-fingerprint-continuity-mismatch'}
    if(Test-Path -LiteralPath ([string]$FinalizationResult.transaction_root)){return & $deny 'finalized-transaction-workspace-reappeared'}

    $permitCheck=Test-CustomAppProductionPostSwapPermitIntegrityV010 -Permit $Permit -SessionKey $SessionKey -Now $Now
    if(-not [bool]$permitCheck.ok){return & $deny ('permit-integrity-denied:'+[string]$permitCheck.reason)}
    $consumption=Test-CustomAppProductionPostSwapConsumptionContinuityV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedConsumptionId $cid -Permit $Permit -StageExecutorResult $StageExecutorResult -Name $Name
    if(-not [bool]$consumption.ok){return & $deny ([string]$consumption.reason)}

    if($null -eq $LifecycleRow -or [string]$LifecycleRow.managed_by -cne 'dynamic-spicetify-v1' -or -not [bool]$LifecycleRow.present -or [bool]$LifecycleRow.user_removed -or [bool]$LifecycleRow.ambiguous -or -not [bool]$LifecycleRow.safe_local_identity -or @($LifecycleRow.locations).Count -ne 1){return & $deny 'lifecycle-not-safe-current-single-location'}
    $elig=Test-CustomAppRemoteBindingEligibilityV040 -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow
    if(-not [bool]$elig.ok){return & $deny ('provenance-or-lifecycle-denied:'+[string]$elig.reason)}
    $binding=Test-CustomAppStageBindingRowV010 -BindingRow $BindingRow -ExpectedName $Name
    if(-not [bool]$binding.ok){return & $deny ('binding-denied:'+[string]$binding.reason)}
    $lastSuccess=[DateTimeOffset]::MinValue
    if(-not [DateTimeOffset]::TryParse([string]$binding.last_success,[ref]$lastSuccess)){return & $deny 'binding-last-success-invalid'}
    if($Now -lt $lastSuccess.AddMinutes(-5)){return & $deny 'binding-observation-from-future'}
    if($Now -gt $lastSuccess.AddHours($MaxRemoteObservationAgeHours)){return & $deny 'binding-observation-stale'}
    if(([string]$elig.source).Trim().ToLowerInvariant() -cne ([string]$StageExecutorResult.source_identity).Trim().ToLowerInvariant() -or ([string]$binding.source).Trim().ToLowerInvariant() -cne ([string]$StageExecutorResult.source_identity).Trim().ToLowerInvariant()){return & $deny 'source-continuity-mismatch'}
    try{if([int64]$binding.repo_id -ne [int64]$StageExecutorResult.github_repo_id){return & $deny 'binding-repo-id-mismatch'}}catch{return & $deny 'binding-repo-id-invalid'}
    foreach($pair in @(@('surface',[string]$StageExecutorResult.surface_kind),@('remote_tree_sha256',[string]$StageExecutorResult.remote_tree_sha256),@('commit_sha',[string]$StageExecutorResult.remote_commit_sha),@('binding_fingerprint',[string]$StageExecutorResult.binding_fingerprint))){if(([string]$binding.($pair[0])).Trim().ToLowerInvariant() -cne ([string]$pair[1]).Trim().ToLowerInvariant()){return & $deny ('binding-continuity-mismatch-'+[string]$pair[0])}}

    try{$livePath=Assert-CustomAppAtomicSafeDirectoryV010 -Path ([string]$LifecycleRow.locations[0]) -Label 'live-path'}catch{return & $deny ('live-path-invalid:'+[string]$_.Exception.Message)}
    if(-not $livePath.Equals((Get-CustomAppAtomicCanonicalPathV010 -Path ([string]$FinalizationResult.live_path)),[StringComparison]::OrdinalIgnoreCase)){return & $deny 'finalization-live-path-mismatch'}
    try{$live=Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath $livePath}catch{return & $deny ('live-runtime-read-failed:'+[string]$_.Exception.Message)}
    if(-not [bool]$live.safe -or -not [bool]$live.installable -or (Test-CustomAppLocalRuntimeBaselineMutationAuthority $live) -or [string]$live.tree_sha256 -cne [string]$StageExecutorResult.remote_tree_sha256 -or [string]$live.tree_sha256 -cne [string]$FinalizationResult.live_runtime_tree_sha256 -or [string]$live.manifest_name -cne [string]$binding.manifest_name){return & $deny 'post-swap-live-runtime-not-exact-remote-stage'}
    try{$git=Get-CustomAppAtomicGitSnapshotV010 -LivePath $livePath}catch{return & $deny ('live-git-read-failed:'+[string]$_.Exception.Message)}
    if($FinalizationResult.PSObject.Properties['preserved_git_tree_sha256'] -and -not [string]::IsNullOrWhiteSpace([string]$FinalizationResult.preserved_git_tree_sha256)){
        if(-not [bool]$git.present -or [string]$git.tree_sha256 -cne [string]$FinalizationResult.preserved_git_tree_sha256){return & $deny 'preserved-git-continuity-mismatch'}
    } elseif([bool]$git.present){return & $deny 'unexpected-git-present-without-finalization-proof'}

    try{$stage=Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath ([string]$PreparedResult.stage_path)}catch{return & $deny ('retained-stage-read-failed:'+[string]$_.Exception.Message)}
    if(-not [bool]$stage.safe -or -not [bool]$stage.installable -or (Test-CustomAppLocalRuntimeBaselineMutationAuthority $stage) -or [string]$stage.tree_sha256 -cne [string]$StageExecutorResult.remote_tree_sha256 -or [string]$stage.manifest_name -cne [string]$binding.manifest_name){return & $deny 'retained-stage-runtime-drift'}
    if(Test-Path -LiteralPath (Join-Path ([string]$PreparedResult.stage_path) '.git')){return & $deny 'retained-stage-vcs-metadata-forbidden'}
    try{$appBackup=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$PreparedResult.app_backup_path)}catch{return & $deny ('app-backup-read-failed:'+[string]$_.Exception.Message)}
    if([string]$appBackup.tree_sha256 -cne [string]$PreparedResult.app_backup_tree_sha256 -or [int]$appBackup.file_count -ne [int]$PreparedResult.app_backup_file_count -or [int64]$appBackup.total_bytes -ne [int64]$PreparedResult.app_backup_total_bytes){return & $deny 'app-rollback-backup-drift'}
    $persistenceBackup=Test-CustomAppProductionPersistenceBackupV010 -BackupPath ([string]$PreparedResult.persistence_backup_path) -ExpectedFingerprint ([string]$PreparedResult.persistence_fingerprint)
    if(-not [bool]$persistenceBackup.ok){return & $deny ('persistence-backup-invalid:'+[string]$persistenceBackup.reason)}
    try{$persistence=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot}catch{return & $deny ('protected-persistence-read-failed:'+[string]$_.Exception.Message)}
    if([string]$persistence.fingerprint -cne [string]$PreparedResult.persistence_fingerprint -or [string]$persistence.fingerprint -cne [string]$FinalizationResult.persistence_fingerprint){return & $deny 'protected-persistence-drift-before-apply-admission'}

    $expires=$Now.AddSeconds(20);if($permitCheck.expires_at -lt $expires){$expires=$permitCheck.expires_at};if($expires -le $Now){return & $deny 'apply-admission-window-empty'}
    $decision=[pscustomobject]@{
        schema=$CustomAppProductionPostSwapApplyAdmissionSchema;managed_by=$CustomAppProductionPostSwapApplyAdmissionManagedBy;qualified_finalization_head=$CustomAppProductionPostSwapApplyAdmissionQualifiedFinalizationHead;reason='post-swap-current-state-eligible-for-bounded-apply-executor'
        consumption_id=$cid;finalization_fingerprint=([string]$FinalizationResult.finalization_fingerprint).Trim().ToLowerInvariant();preparation_fingerprint=([string]$PreparedResult.preparation_fingerprint).Trim().ToLowerInvariant();stage_result_fingerprint=([string]$StageExecutorResult.result_fingerprint).Trim().ToLowerInvariant()
        name=$Name;source_identity=([string]$StageExecutorResult.source_identity).Trim().ToLowerInvariant();github_repo_id=[int64]$StageExecutorResult.github_repo_id;surface_kind=([string]$StageExecutorResult.surface_kind).Trim().ToLowerInvariant();live_tree_sha256=([string]$live.tree_sha256).Trim().ToLowerInvariant();remote_tree_sha256=([string]$StageExecutorResult.remote_tree_sha256).Trim().ToLowerInvariant();remote_commit_sha=([string]$StageExecutorResult.remote_commit_sha).Trim().ToLowerInvariant();binding_fingerprint=([string]$binding.binding_fingerprint).Trim().ToLowerInvariant()
        preserved_git_tree_sha256=$(if([bool]$git.present){([string]$git.tree_sha256).Trim().ToLowerInvariant()}else{$null});persistence_fingerprint=([string]$persistence.fingerprint).Trim().ToLowerInvariant();current_consumption_envelope_sha256=([string]$consumption.current_envelope_sha256).Trim().ToLowerInvariant()
        evaluated_at=$Now.ToUniversalTime().ToString('o');apply_eligibility_expires_at=$expires.ToUniversalTime().ToString('o');apply_eligible=$true;admission_fingerprint=$null;admission_is_authority=$false
        requires_immediate_rerun_by_apply_executor=$true;requires_exact_spicetify_apply_executor=$true;requires_exact_rollback_on_apply_failure=$true;apply_execution_authorized=$false;spicetify_apply_authorized=$false;additional_mutation_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false
    }
    $decision.admission_fingerprint=Get-CustomAppProductionPostSwapApplyAdmissionSha256V010 (Get-CustomAppProductionPostSwapApplyAdmissionMaterialV010 -Decision $decision)
    $check=Test-CustomAppProductionPostSwapApplyAdmissionDecisionV010 -Decision $decision
    if(-not [bool]$check.ok){return & $deny ('post-swap-apply-admission-self-validation-failed:'+[string]$check.reason)}
    return [pscustomobject]@{ok=$true;reason=[string]$decision.reason;decision=$decision;apply_eligible=$true;admission_fingerprint=[string]$decision.admission_fingerprint;admission_is_authority=$false;requires_immediate_rerun_by_apply_executor=$true;requires_exact_spicetify_apply_executor=$true;requires_exact_rollback_on_apply_failure=$true;apply_execution_authorized=$false;spicetify_apply_authorized=$false;additional_mutation_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false}
}
