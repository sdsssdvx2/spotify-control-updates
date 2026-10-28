$CustomAppProductionStageExecutorSchema = 1
$CustomAppProductionStageExecutorManagedBy = 'custom-app-production-stage-executor-v1'
$CustomAppProductionStageExecutorQualifiedAdmissionHead = '13f4314b81816b1b1c3bb3c2fb4280b6c015f8de'
$CustomAppProductionStageExecutorQualifiedStageContractHead = 'c420a1df6f306c7ba74772b91241cb14abd04738'

function Get-CustomAppProductionStageExecutorSha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}

function Test-CustomAppProductionStageExecutorSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}

function Test-CustomAppProductionStageExecutorLiveBaselineV010 {
    param([AllowNull()]$LifecycleRow,[AllowNull()]$Permit,[AllowNull()]$BindingRow,[Parameter(Mandatory=$true)][string]$Name)
    if($null -eq $LifecycleRow -or $null -eq $Permit -or $null -eq $BindingRow){return [pscustomobject]@{ok=$false;reason='fresh-live-input-null'}}
    if([string]$LifecycleRow.managed_by -cne 'dynamic-spicetify-v1' -or -not [bool]$LifecycleRow.present -or [bool]$LifecycleRow.user_removed -or [bool]$LifecycleRow.ambiguous -or -not [bool]$LifecycleRow.safe_local_identity){return [pscustomobject]@{ok=$false;reason='fresh-live-lifecycle-not-current-safe'}}
    if([string]$LifecycleRow.mutation_mode -cne 'deny' -or [bool]$LifecycleRow.auto_update_authorized -or [bool]$LifecycleRow.auto_install_authorized){return [pscustomobject]@{ok=$false;reason='fresh-live-lifecycle-authority-drift'}}
    $locations=@($LifecycleRow.locations);if($locations.Count -ne 1 -or [string]::IsNullOrWhiteSpace([string]$locations[0])){return [pscustomobject]@{ok=$false;reason='fresh-live-location-not-single'}}
    try{$fresh=Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath ([string]$locations[0])}catch{return [pscustomobject]@{ok=$false;reason=('fresh-live-baseline-failed:'+[string]$_.Exception.Message)}}
    if(-not [bool]$fresh.safe -or -not [bool]$fresh.installable -or (Test-CustomAppLocalRuntimeBaselineMutationAuthority $fresh)){return [pscustomobject]@{ok=$false;reason='fresh-live-baseline-not-safe-installable-denied'}}
    if(([string]$fresh.tree_sha256).Trim().ToLowerInvariant() -cne ([string]$Permit.current_tree_sha256).Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason='fresh-live-tree-changed-during-staging'}}
    $manifest=([string]$BindingRow.binding.manifest_name).Trim();if([string]::IsNullOrWhiteSpace($manifest) -or [string]$fresh.manifest_name -cne $manifest){return [pscustomobject]@{ok=$false;reason='fresh-live-manifest-changed-during-staging'}}
    return [pscustomobject]@{ok=$true;reason='fresh-live-runtime-unchanged';baseline=$fresh;tree_sha256=([string]$fresh.tree_sha256).Trim().ToLowerInvariant();manifest_name=[string]$fresh.manifest_name;path=[string]$fresh.path}
}

function Test-CustomAppProductionStageExecutorStageResultV010 {
    param([AllowNull()]$StageResult,[AllowNull()]$AdmissionDecision,[AllowNull()]$BindingRow)
    if($null -eq $StageResult -or $null -eq $AdmissionDecision -or $null -eq $BindingRow){return [pscustomobject]@{ok=$false;reason='stage-result-input-null'}}
    foreach($required in @('schema','managed_by','status','name','source_identity','github_repo_id','surface_kind','commit_sha','remote_tree_sha256','binding_fingerprint','workspace_path','stage_path','archive_sha256','stage_baseline','mutation_mode','mutation_authorized','auto_update_authorized','auto_install_authorized','production_mutation_authorized')){if(-not $StageResult.PSObject.Properties[$required]){return [pscustomobject]@{ok=$false;reason=('stage-result-required-field-missing-'+$required)}}}
    if([int]$StageResult.schema -ne $CustomAppStageAcquisitionSchema -or [string]$StageResult.managed_by -cne $CustomAppStageWorkspaceManagedBy -or [string]$StageResult.status -cne 'staged-verified'){return [pscustomobject]@{ok=$false;reason='stage-result-schema-owner-or-status-invalid'}}
    if(Test-CustomAppStageAcquisitionMutationAuthorityV010 $StageResult){return [pscustomobject]@{ok=$false;reason='stage-result-authority-drift'}}
    $pairs=@(
        @('name','name'),@('source_identity','source_identity'),@('surface_kind','surface_kind'),@('commit_sha','remote_commit_sha'),
        @('remote_tree_sha256','remote_tree_sha256'),@('binding_fingerprint','binding_fingerprint')
    )
    foreach($pair in $pairs){$left=([string]$StageResult.($pair[0])).Trim().ToLowerInvariant();$right=([string]$AdmissionDecision.($pair[1])).Trim().ToLowerInvariant();if($left -cne $right){return [pscustomobject]@{ok=$false;reason=('stage-result-admission-mismatch-'+$pair[0])}}}
    try{if([int64]$StageResult.github_repo_id -ne [int64]$AdmissionDecision.github_repo_id){return [pscustomobject]@{ok=$false;reason='stage-result-admission-mismatch-github_repo_id'}}}catch{return [pscustomobject]@{ok=$false;reason='stage-result-repo-id-invalid'}}
    if(-not (Test-CustomAppProductionStageExecutorSha256V010 (([string]$StageResult.archive_sha256).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason='stage-result-archive-sha256-invalid'}}
    $root=[IO.Path]::GetFullPath((Get-CustomAppStageWorkspaceRootV010)).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    try{$workspace=Assert-CustomAppStagePathV010 -Root $root -Path ([string]$StageResult.workspace_path) -Label 'production stage workspace';$stage=Assert-CustomAppStagePathV010 -Root $workspace -Path ([string]$StageResult.stage_path) -Label 'production stage path'}catch{return [pscustomobject]@{ok=$false;reason=('stage-result-path-invalid:'+[string]$_.Exception.Message)}}
    $parent=[IO.Path]::GetDirectoryName($workspace);if(-not ([IO.Path]::GetFullPath($parent).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)).Equals($root,[StringComparison]::OrdinalIgnoreCase)){return [pscustomobject]@{ok=$false;reason='stage-result-workspace-not-direct-child'}}
    if(([IO.Path]::GetFileName($workspace)) -notmatch '^[0-9a-fA-F]{32}$'){return [pscustomobject]@{ok=$false;reason='stage-result-workspace-id-invalid'}}
    $expectedStage=[IO.Path]::GetFullPath((Join-Path $workspace 'stage'));if(-not ([IO.Path]::GetFullPath($stage)).Equals($expectedStage,[StringComparison]::OrdinalIgnoreCase)){return [pscustomobject]@{ok=$false;reason='stage-result-stage-path-drift'}}
    if(-not (Test-Path -LiteralPath $workspace -PathType Container) -or -not (Test-Path -LiteralPath $stage -PathType Container)){return [pscustomobject]@{ok=$false;reason='stage-result-workspace-or-stage-missing'}}
    $baseline=$StageResult.stage_baseline;if($null -eq $baseline -or -not [bool]$baseline.safe -or -not [bool]$baseline.installable -or (Test-CustomAppLocalRuntimeBaselineMutationAuthority $baseline)){return [pscustomobject]@{ok=$false;reason='stage-result-baseline-not-safe-installable-denied'}}
    if(([string]$baseline.tree_sha256).Trim().ToLowerInvariant() -cne ([string]$AdmissionDecision.remote_tree_sha256).Trim().ToLowerInvariant() -or ([string]$baseline.tree_sha256).Trim().ToLowerInvariant() -cne ([string]$StageResult.remote_tree_sha256).Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason='stage-result-baseline-tree-mismatch'}}
    if([string]$baseline.manifest_name -cne [string]$BindingRow.binding.manifest_name){return [pscustomobject]@{ok=$false;reason='stage-result-baseline-manifest-mismatch'}}
    try{$baselinePath=[IO.Path]::GetFullPath([string]$baseline.path)}catch{return [pscustomobject]@{ok=$false;reason='stage-result-baseline-path-invalid'}}
    if(-not $baselinePath.Equals([IO.Path]::GetFullPath($stage),[StringComparison]::OrdinalIgnoreCase)){return [pscustomobject]@{ok=$false;reason='stage-result-baseline-path-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='stage-result-exactly-bound-and-isolated';workspace_path=$workspace;stage_path=$stage;archive_sha256=([string]$StageResult.archive_sha256).Trim().ToLowerInvariant();stage_tree_sha256=([string]$baseline.tree_sha256).Trim().ToLowerInvariant();stage_manifest_name=[string]$baseline.manifest_name}
}

function Get-CustomAppProductionStageExecutorResultMaterialV010 {
    param([Parameter(Mandatory=$true)]$Result)
    return @(
        [string]$Result.schema,[string]$Result.managed_by,[string]$Result.qualified_admission_head,[string]$Result.qualified_stage_contract_head,[string]$Result.status,
        [string]$Result.consumption_id,[string]$Result.pre_stage_admission_fingerprint,[string]$Result.post_stage_admission_fingerprint,[string]$Result.persistence_envelope_sha256,
        [string]$Result.name,[string]$Result.source_identity,[string]$Result.github_repo_id,[string]$Result.surface_kind,[string]$Result.remote_commit_sha,
        [string]$Result.local_tree_sha256,[string]$Result.remote_tree_sha256,[string]$Result.binding_fingerprint,[string]$Result.archive_sha256,
        [string]$Result.workspace_path,[string]$Result.stage_path,[string]$Result.staged_at,[string]$Result.post_stage_revalidated_at,
        [string]$Result.stage_performed,[string]$Result.live_runtime_unchanged,[string]$Result.post_stage_revalidated,[string]$Result.result_is_authority,
        [string]$Result.stage_workspace_retained_for_pre_apply,[string]$Result.requires_cleanup_if_not_promoted,[string]$Result.requires_fresh_revalidation_before_apply,
        [string]$Result.apply_authorized,[string]$Result.live_destination_authorized,[string]$Result.production_execution_authorized,[string]$Result.production_mutation_authorized
    ) -join "`n"
}

function Test-CustomAppProductionStageExecutorResultV010 {
    param([AllowNull()]$Result)
    if($null -eq $Result){return [pscustomobject]@{ok=$false;reason='production-stage-result-null'}}
    foreach($required in @('schema','managed_by','qualified_admission_head','qualified_stage_contract_head','status','consumption_id','pre_stage_admission_fingerprint','post_stage_admission_fingerprint','persistence_envelope_sha256','name','source_identity','github_repo_id','surface_kind','remote_commit_sha','local_tree_sha256','remote_tree_sha256','binding_fingerprint','archive_sha256','workspace_path','stage_path','staged_at','post_stage_revalidated_at','stage_performed','live_runtime_unchanged','post_stage_revalidated','result_fingerprint','result_is_authority','stage_workspace_retained_for_pre_apply','requires_cleanup_if_not_promoted','requires_fresh_revalidation_before_apply','apply_authorized','live_destination_authorized','production_execution_authorized','production_mutation_authorized')){if(-not $Result.PSObject.Properties[$required]){return [pscustomobject]@{ok=$false;reason=('production-stage-result-required-field-missing-'+$required)}}}
    if([int]$Result.schema -ne $CustomAppProductionStageExecutorSchema -or [string]$Result.managed_by -cne $CustomAppProductionStageExecutorManagedBy -or [string]$Result.qualified_admission_head -cne $CustomAppProductionStageExecutorQualifiedAdmissionHead -or [string]$Result.qualified_stage_contract_head -cne $CustomAppProductionStageExecutorQualifiedStageContractHead -or [string]$Result.status -cne 'staged-verified-post-stage-revalidated'){return [pscustomobject]@{ok=$false;reason='production-stage-result-owner-schema-parent-or-status-invalid'}}
    if(-not [bool]$Result.stage_performed -or -not [bool]$Result.live_runtime_unchanged -or -not [bool]$Result.post_stage_revalidated -or [bool]$Result.result_is_authority -or -not [bool]$Result.stage_workspace_retained_for_pre_apply -or -not [bool]$Result.requires_cleanup_if_not_promoted -or -not [bool]$Result.requires_fresh_revalidation_before_apply){return [pscustomobject]@{ok=$false;reason='production-stage-result-separation-contract-invalid'}}
    foreach($field in @('apply_authorized','live_destination_authorized','production_execution_authorized','production_mutation_authorized')){if([bool]$Result.$field){return [pscustomobject]@{ok=$false;reason=('production-stage-result-'+$field+'-true')}}}
    foreach($field in @('consumption_id','pre_stage_admission_fingerprint','post_stage_admission_fingerprint','persistence_envelope_sha256','local_tree_sha256','remote_tree_sha256','binding_fingerprint','archive_sha256','result_fingerprint')){if(-not (Test-CustomAppProductionStageExecutorSha256V010 (([string]$Result.$field).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('production-stage-result-invalid-'+$field)}}}
    if(([string]$Result.remote_commit_sha).Trim().ToLowerInvariant() -notmatch '^[0-9a-f]{40}$'){return [pscustomobject]@{ok=$false;reason='production-stage-result-invalid-remote-commit'}}
    try{if([int64]$Result.github_repo_id -le 0){return [pscustomobject]@{ok=$false;reason='production-stage-result-repo-id-invalid'}}}catch{return [pscustomobject]@{ok=$false;reason='production-stage-result-repo-id-invalid'}}
    $root=[IO.Path]::GetFullPath((Get-CustomAppStageWorkspaceRootV010)).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    try{$workspace=Assert-CustomAppStagePathV010 -Root $root -Path ([string]$Result.workspace_path) -Label 'production stage result workspace';$stage=Assert-CustomAppStagePathV010 -Root $workspace -Path ([string]$Result.stage_path) -Label 'production stage result path'}catch{return [pscustomobject]@{ok=$false;reason=('production-stage-result-path-invalid:'+[string]$_.Exception.Message)}}
    if(-not (Test-Path -LiteralPath $workspace -PathType Container) -or -not (Test-Path -LiteralPath $stage -PathType Container)){return [pscustomobject]@{ok=$false;reason='production-stage-result-retained-workspace-missing'}}
    $expected=Get-CustomAppProductionStageExecutorSha256V010 (Get-CustomAppProductionStageExecutorResultMaterialV010 -Result $Result)
    if(([string]$Result.result_fingerprint).Trim().ToLowerInvariant() -cne $expected){return [pscustomobject]@{ok=$false;reason='production-stage-result-fingerprint-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='production-stage-result-valid-no-apply-authority';result_fingerprint=$expected;workspace_path=$workspace;stage_path=$stage}
}

function Invoke-CustomAppProductionStageExecutorCleanupV010 {
    param([AllowNull()][string]$WorkspacePath)
    if([string]::IsNullOrWhiteSpace($WorkspacePath)){return [pscustomobject]@{ok=$true;reason='no-stage-workspace-to-clean'}}
    try{Remove-CustomAppStageWorkspaceV010 -Path $WorkspacePath;return [pscustomobject]@{ok=$true;reason='stage-workspace-cleaned'}}catch{return [pscustomobject]@{ok=$false;reason=('stage-workspace-cleanup-failed:'+[string]$_.Exception.Message)}}
}

function Invoke-CustomAppProductionStageExecutorV010 {
    param(
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory,[Parameter(Mandatory=$true)][string]$ExpectedConsumptionId,
        [AllowNull()]$Permit,[Parameter(Mandatory=$true)][string]$Name,[AllowNull()]$LifecycleRow,[AllowNull()]$ProvenanceRow,[AllowNull()]$BindingRow,[AllowNull()]$CurrentBaseline,[AllowNull()]$ShadowProtocolQualification,[AllowNull()]$LiveAttestedQualification,
        [Parameter(Mandatory=$true)][byte[]]$SessionKey,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow,[Nullable[DateTimeOffset]]$PostStageNow=$null,[int]$MaxRemoteObservationAgeHours=36
    )
    $deny={param([string]$Reason,[AllowNull()][string]$Workspace=$null,[bool]$StagePerformed=$false,[bool]$CleanupAttempted=$false,[bool]$CleanupOk=$true)
        [pscustomobject]@{ok=$false;reason=$Reason;stage_performed=$StagePerformed;cleanup_attempted=$CleanupAttempted;cleanup_ok=$CleanupOk;workspace_path=$Workspace;post_stage_revalidated=$false;result_is_authority=$false;stage_workspace_retained_for_pre_apply=$false;requires_cleanup_if_not_promoted=$false;requires_fresh_revalidation_before_apply=$true;apply_authorized=$false;live_destination_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false}}

    $pre=Resolve-CustomAppProductionStageAdmissionV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedConsumptionId $ExpectedConsumptionId -Permit $Permit -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -CurrentBaseline $CurrentBaseline -ShadowProtocolQualification $ShadowProtocolQualification -LiveAttestedQualification $LiveAttestedQualification -SessionKey $SessionKey -Now $Now -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    if($null -eq $pre -or -not [bool]$pre.ok -or -not [bool]$pre.stage_acquisition_eligible){return & $deny ('pre-stage-admission-denied:'+[string]$pre.reason)}
    $preCheck=Test-CustomAppProductionStageAdmissionDecisionV010 -Decision $pre.decision
    if(-not [bool]$preCheck.ok){return & $deny ('pre-stage-admission-invalid:'+[string]$preCheck.reason)}

    $stage=$null;$workspace=$null
    try{$stage=Invoke-CustomAppStageAcquisitionV010 -Name $Name -BindingRow $BindingRow}catch{return & $deny ('stage-acquisition-failed:'+[string]$_.Exception.Message)}
    if($null -ne $stage -and $stage.PSObject.Properties['workspace_path']){$workspace=[string]$stage.workspace_path}
    $stageCheck=Test-CustomAppProductionStageExecutorStageResultV010 -StageResult $stage -AdmissionDecision $pre.decision -BindingRow $BindingRow
    if(-not [bool]$stageCheck.ok){$cleanup=Invoke-CustomAppProductionStageExecutorCleanupV010 -WorkspacePath $workspace;return & $deny ('stage-result-denied:'+[string]$stageCheck.reason) $workspace $true $true ([bool]$cleanup.ok)}
    $workspace=[string]$stageCheck.workspace_path

    $freshLive=Test-CustomAppProductionStageExecutorLiveBaselineV010 -LifecycleRow $LifecycleRow -Permit $Permit -BindingRow $BindingRow -Name $Name
    if(-not [bool]$freshLive.ok){$cleanup=Invoke-CustomAppProductionStageExecutorCleanupV010 -WorkspacePath $workspace;return & $deny ('post-stage-live-revalidation-denied:'+[string]$freshLive.reason) $workspace $true $true ([bool]$cleanup.ok)}

    $postNow=$(if($null -ne $PostStageNow){[DateTimeOffset]$PostStageNow}else{[DateTimeOffset]::UtcNow})
    if($postNow -lt $Now){$cleanup=Invoke-CustomAppProductionStageExecutorCleanupV010 -WorkspacePath $workspace;return & $deny 'post-stage-time-before-pre-stage-time' $workspace $true $true ([bool]$cleanup.ok)}
    $post=Resolve-CustomAppProductionStageAdmissionV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedConsumptionId $ExpectedConsumptionId -Permit $Permit -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -CurrentBaseline $freshLive.baseline -ShadowProtocolQualification $ShadowProtocolQualification -LiveAttestedQualification $LiveAttestedQualification -SessionKey $SessionKey -Now $postNow -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    if($null -eq $post -or -not [bool]$post.ok -or -not [bool]$post.stage_acquisition_eligible){$cleanup=Invoke-CustomAppProductionStageExecutorCleanupV010 -WorkspacePath $workspace;return & $deny ('post-stage-admission-denied:'+[string]$post.reason) $workspace $true $true ([bool]$cleanup.ok)}
    $postCheck=Test-CustomAppProductionStageAdmissionDecisionV010 -Decision $post.decision
    if(-not [bool]$postCheck.ok){$cleanup=Invoke-CustomAppProductionStageExecutorCleanupV010 -WorkspacePath $workspace;return & $deny ('post-stage-admission-invalid:'+[string]$postCheck.reason) $workspace $true $true ([bool]$cleanup.ok)}
    foreach($field in @('consumption_id','name','source_identity','github_repo_id','surface_kind','remote_tree_sha256','remote_commit_sha','binding_fingerprint')){
        if(([string]$pre.decision.$field).Trim().ToLowerInvariant() -cne ([string]$post.decision.$field).Trim().ToLowerInvariant()){$cleanup=Invoke-CustomAppProductionStageExecutorCleanupV010 -WorkspacePath $workspace;return & $deny ('post-stage-admission-continuity-drift-'+$field) $workspace $true $true ([bool]$cleanup.ok)}
    }
    if(([string]$stageCheck.stage_tree_sha256).Trim().ToLowerInvariant() -cne ([string]$post.decision.remote_tree_sha256).Trim().ToLowerInvariant()){$cleanup=Invoke-CustomAppProductionStageExecutorCleanupV010 -WorkspacePath $workspace;return & $deny 'post-stage-staged-tree-continuity-drift' $workspace $true $true ([bool]$cleanup.ok)}

    $result=[pscustomobject]@{
        schema=$CustomAppProductionStageExecutorSchema;managed_by=$CustomAppProductionStageExecutorManagedBy;qualified_admission_head=$CustomAppProductionStageExecutorQualifiedAdmissionHead;qualified_stage_contract_head=$CustomAppProductionStageExecutorQualifiedStageContractHead;status='staged-verified-post-stage-revalidated'
        consumption_id=([string]$pre.decision.consumption_id).Trim().ToLowerInvariant();pre_stage_admission_fingerprint=([string]$pre.decision.admission_fingerprint).Trim().ToLowerInvariant();post_stage_admission_fingerprint=([string]$post.decision.admission_fingerprint).Trim().ToLowerInvariant();persistence_envelope_sha256=([string]$post.decision.persistence_envelope_sha256).Trim().ToLowerInvariant()
        name=[string]$post.decision.name;source_identity=([string]$post.decision.source_identity).Trim().ToLowerInvariant();github_repo_id=[int64]$post.decision.github_repo_id;surface_kind=([string]$post.decision.surface_kind).Trim().ToLowerInvariant();remote_commit_sha=([string]$post.decision.remote_commit_sha).Trim().ToLowerInvariant()
        local_tree_sha256=([string]$freshLive.tree_sha256).Trim().ToLowerInvariant();remote_tree_sha256=([string]$stageCheck.stage_tree_sha256).Trim().ToLowerInvariant();binding_fingerprint=([string]$post.decision.binding_fingerprint).Trim().ToLowerInvariant();archive_sha256=([string]$stageCheck.archive_sha256).Trim().ToLowerInvariant()
        workspace_path=[string]$workspace;stage_path=[string]$stageCheck.stage_path;staged_at=$Now.ToUniversalTime().ToString('o');post_stage_revalidated_at=$postNow.ToUniversalTime().ToString('o')
        stage_performed=$true;live_runtime_unchanged=$true;post_stage_revalidated=$true;result_fingerprint=$null;result_is_authority=$false;stage_workspace_retained_for_pre_apply=$true;requires_cleanup_if_not_promoted=$true;requires_fresh_revalidation_before_apply=$true
        apply_authorized=$false;live_destination_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false
    }
    $result.result_fingerprint=Get-CustomAppProductionStageExecutorSha256V010 (Get-CustomAppProductionStageExecutorResultMaterialV010 -Result $result)
    $resultCheck=Test-CustomAppProductionStageExecutorResultV010 -Result $result
    if(-not [bool]$resultCheck.ok){$cleanup=Invoke-CustomAppProductionStageExecutorCleanupV010 -WorkspacePath $workspace;return & $deny ('production-stage-result-self-validation-failed:'+[string]$resultCheck.reason) $workspace $true $true ([bool]$cleanup.ok)}
    return [pscustomobject]@{ok=$true;reason='isolated-stage-complete-post-stage-revalidated';result=$result;stage_performed=$true;workspace_path=$workspace;stage_path=[string]$stageCheck.stage_path;post_stage_revalidated=$true;result_fingerprint=[string]$result.result_fingerprint;result_is_authority=$false;stage_workspace_retained_for_pre_apply=$true;requires_cleanup_if_not_promoted=$true;requires_fresh_revalidation_before_apply=$true;apply_authorized=$false;live_destination_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false}
}
