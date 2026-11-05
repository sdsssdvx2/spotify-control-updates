# Validation-only operational bridge: reuse a byte-real stage acquired BEFORE a short-lived
# Triple-ID permit, then invoke the EXISTING generic admission and stage-result
# contracts without another network download or any live-app mutation.
$CustomAppPreparedStageBridgeSchema=1
$CustomAppPreparedStageBridgeManagedBy='custom-app-production-prepared-stage-executor-bridge-v1'
$CustomAppPreparedStageBridgeQualifiedHandoffHead='065acbb3b0b8b641ad2468f9738e98905ffac44e'
$CustomAppPreparedStageBridgeQualifiedHandoffCoreBlob='c53eead027e8f48f9777e5c70ae2f011016bb851'

function New-CustomAppPreparedStageBridgeDeniedV010 {
    param([Parameter(Mandatory=$true)][string]$Reason)
    return [pscustomobject]@{
        ok=$false;reason=$Reason;stage_result=$null;stage_prepared_before_permit=$false
        fetched_again=$false;post_stage_revalidated=$false;requires_cleanup_if_not_promoted=$true
        ready_to_apply=$false;apply_authorized=$false;live_destination_authorized=$false
        production_execution_authorized=$false;production_mutation_authorized=$false
    }
}

function Invoke-CustomAppProductionPreparedStageExecutorBridgeV010 {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$WorkspacePath,
        [Parameter(Mandatory=$true)][string]$ArchivePath,
        [Parameter(Mandatory=$true)][string]$ArchiveSha256,
        [Parameter(Mandatory=$true)][string]$StagePath,
        [Parameter(Mandatory=$true)]$ExtractedStageResult,
        [Parameter(Mandatory=$true)]$LifecycleRow,
        [Parameter(Mandatory=$true)]$ProvenanceRow,
        [Parameter(Mandatory=$true)]$BindingRow,
        [Parameter(Mandatory=$true)]$IssuerResult,
        [Parameter(Mandatory=$true)]$ExecutorStartResult,
        [Parameter(Mandatory=$true)][byte[]]$SessionKey,
        [Parameter(Mandatory=$true)][string]$AllowedRoot,
        [Parameter(Mandatory=$true)][string]$ConsumptionStoreDirectory,
        [AllowNull()]$CurrentBaseline=$null,
        [AllowNull()]$ShadowProtocolQualification=$null,
        [AllowNull()]$LiveAttestedQualification=$null,
        [DateTimeOffset]$Now=[DateTimeOffset]::UtcNow,
        [Nullable[DateTimeOffset]]$PostStageNow=$null,
        [int]$MaxRemoteObservationAgeHours=36
    )
    $deny={param([string]$reason) New-CustomAppPreparedStageBridgeDeniedV010 -Reason $reason}
    if($SessionKey.Length-lt32){return (& $deny 'prepared-bridge-key-too-short')}
    if($MaxRemoteObservationAgeHours-lt1-or$MaxRemoteObservationAgeHours-gt168){
        return (& $deny 'prepared-bridge-observation-age-policy-invalid')
    }
    $postTime=$(if($null-ne$PostStageNow){[DateTimeOffset]$PostStageNow}else{$Now})
    if($postTime-lt$Now){return (& $deny 'prepared-bridge-post-time-before-pre')}
    if($postTime-gt$Now.AddSeconds(5)){return (& $deny 'prepared-bridge-post-check-window-exceeded')}
    if($null-eq$IssuerResult.permit-or$null-eq$IssuerResult.receipt-or
       $null-eq$ExecutorStartResult.receipt){
        return (& $deny 'prepared-bridge-issuer-or-start-missing')
    }
    $consumption=([string]$ExecutorStartResult.receipt.consumption_id).Trim().ToLowerInvariant()
    if($consumption-notmatch'^[a-f0-9]{64}$'){
        return (& $deny 'prepared-bridge-consumption-id-invalid')
    }
    $stageHandoffArgs=@{
        Name=$Name;WorkspacePath=$WorkspacePath;ArchivePath=$ArchivePath
        ArchiveSha256=$ArchiveSha256;StagePath=$StagePath
        ExtractedStageResult=$ExtractedStageResult;LifecycleRow=$LifecycleRow
        BindingRow=$BindingRow;IssuerResult=$IssuerResult;ExecutorStartResult=$ExecutorStartResult
        SessionKey=$SessionKey;AllowedRoot=$AllowedRoot
        ConsumptionStoreDirectory=$ConsumptionStoreDirectory;Now=$Now
    }
    $proof=Test-CustomAppProductionByteRealPreparedStageHandoffV010 @stageHandoffArgs
    if($null-eq$proof-or-not[bool]$proof.ok-or
       -not[bool]$proof.new_permit_bound-or-not[bool]$proof.consumption_store_reloaded-or
       -not[bool]$proof.ready_for_fresh_post_stage_revalidation-or
       [bool]$proof.ready_to_apply-or[bool]$proof.production_mutation_authorized){
        return (& $deny ('prepared-bridge-byte-real-handoff-invalid:'+[string]$proof.reason))
    }

    # The old generic stage admission revalidates the generic permit HMAC and
    # physical single-use consumption store. The new-cycle issuer embeds that
    # exact permit. We deliberately never accept an independently supplied
    # permit, so a historical or second-transaction permit cannot be spliced in.
    $admissionArgs=@{
        AllowedRoot=$AllowedRoot;StoreDirectory=$ConsumptionStoreDirectory
        ExpectedConsumptionId=$consumption;Permit=$IssuerResult.permit;Name=$Name
        LifecycleRow=$LifecycleRow;ProvenanceRow=$ProvenanceRow;BindingRow=$BindingRow
        CurrentBaseline=$CurrentBaseline;ShadowProtocolQualification=$ShadowProtocolQualification
        LiveAttestedQualification=$LiveAttestedQualification
        SessionKey=$SessionKey;Now=$Now;MaxRemoteObservationAgeHours=$MaxRemoteObservationAgeHours
    }
    $pre=Resolve-CustomAppProductionStageAdmissionV010 @admissionArgs
    if($null-eq$pre-or-not[bool]$pre.ok-or-not[bool]$pre.stage_acquisition_eligible){
        return (& $deny ('prepared-bridge-generic-pre-admission-denied:'+[string]$pre.reason))
    }
    $precheck=Test-CustomAppProductionStageAdmissionDecisionV010 -Decision $pre.decision
    if(-not[bool]$precheck.ok){
        return (& $deny ('prepared-bridge-generic-pre-receipt-invalid:'+[string]$precheck.reason))
    }

    # Preserve the exact pre-existing workspace contract (one 32-hex direct
    # child with remote.zip and stage/). No filesystem copies, moves or second
    # acquisition are performed inside the short-lived permit window.
    try{
        $root=(Get-CustomAppStageWorkspaceRootV010)
        $workspace=Assert-CustomAppStagePathV010 -Root $root -Path $WorkspacePath -Label 'prepared bridge workspace'
        $zip=Assert-CustomAppStagePathV010 -Root $workspace -Path $ArchivePath -Label 'prepared bridge ZIP'
        $stage=Assert-CustomAppStagePathV010 -Root $workspace -Path $StagePath -Label 'prepared bridge stage'
        if(-not ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($workspace))).Equals([IO.Path]::GetFullPath($root).TrimEnd([IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)){
            return (& $deny 'prepared-bridge-workspace-not-direct-child')
        }
        if(([IO.Path]::GetFileName($workspace))-notmatch '^[0-9a-fA-F]{32}$'){
            return (& $deny 'prepared-bridge-workspace-name-not-guid')
        }
        if(-not ([IO.Path]::GetFullPath($zip)).Equals((Join-Path $workspace 'remote.zip'),[StringComparison]::OrdinalIgnoreCase)-or
           -not ([IO.Path]::GetFullPath($stage)).Equals((Join-Path $workspace 'stage'),[StringComparison]::OrdinalIgnoreCase)){
            return (& $deny 'prepared-bridge-stage-layout-not-exact')
        }
        $baseline=Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath $stage
    }catch{return (& $deny ('prepared-bridge-stage-path-or-read-denied:'+[string]$_.Exception.Message))}
    if(-not[bool]$baseline.safe-or-not[bool]$baseline.installable-or
       (Test-CustomAppLocalRuntimeBaselineMutationAuthority $baseline)-or
       ([string]$baseline.tree_sha256).Trim().ToLowerInvariant()-cne
       ([string]$proof.stage_tree_sha256).Trim().ToLowerInvariant()){
        return (& $deny 'prepared-bridge-stage-rehash-drift')
    }
    $decision=$pre.decision
    $acquired=[pscustomobject]@{
        schema=$CustomAppStageAcquisitionSchema
        managed_by=$CustomAppStageWorkspaceManagedBy;status='staged-verified'
        name=[string]$decision.name
        source_identity=([string]$decision.source_identity).Trim().ToLowerInvariant()
        github_repo_id=[int64]$decision.github_repo_id
        surface_kind=([string]$decision.surface_kind).Trim().ToLowerInvariant()
        commit_sha=([string]$decision.remote_commit_sha).Trim().ToLowerInvariant()
        remote_tree_sha256=([string]$decision.remote_tree_sha256).Trim().ToLowerInvariant()
        binding_fingerprint=([string]$decision.binding_fingerprint).Trim().ToLowerInvariant()
        binding_last_success=[string]$BindingRow.last_success
        workspace_path=$workspace;stage_path=$stage
        archive_sha256=([string]$proof.archive_sha256).Trim().ToLowerInvariant()
        stage_baseline=$baseline;mutation_mode='deny';mutation_authorized=$false
        auto_update_authorized=$false;auto_install_authorized=$false
        production_mutation_authorized=$false
    }
    $stagecheck=Test-CustomAppProductionStageExecutorStageResultV010 -StageResult $acquired -AdmissionDecision $decision -BindingRow $BindingRow
    if(-not[bool]$stagecheck.ok){
        return (& $deny ('prepared-bridge-exact-existing-stage-result-denied:'+[string]$stagecheck.reason))
    }

    $freshLive=Test-CustomAppProductionStageExecutorLiveBaselineV010 -LifecycleRow $LifecycleRow -Permit $IssuerResult.permit -BindingRow $BindingRow -Name $Name
    if(-not[bool]$freshLive.ok){
        return (& $deny ('prepared-bridge-post-stage-live-drift:'+[string]$freshLive.reason))
    }
    $admissionArgs.CurrentBaseline=$freshLive.baseline
    $admissionArgs.Now=$postTime
    $post=Resolve-CustomAppProductionStageAdmissionV010 @admissionArgs
    if($null-eq$post-or-not[bool]$post.ok-or-not[bool]$post.stage_acquisition_eligible){
        return (& $deny ('prepared-bridge-post-stage-admission-denied:'+[string]$post.reason))
    }
    $postcheck=Test-CustomAppProductionStageAdmissionDecisionV010 -Decision $post.decision
    if(-not[bool]$postcheck.ok){
        return (& $deny ('prepared-bridge-post-stage-receipt-invalid:'+[string]$postcheck.reason))
    }
    foreach($field in @('consumption_id','name','source_identity','github_repo_id','surface_kind','remote_tree_sha256','remote_commit_sha','binding_fingerprint','persistence_envelope_sha256')){
        if(([string]$decision.$field).Trim().ToLowerInvariant()-cne([string]$post.decision.$field).Trim().ToLowerInvariant()){
            return (& $deny ('prepared-bridge-admission-continuity-drift-'+$field))
        }
    }
    $stageHandoffArgs.Now=$postTime
    $postProof=Test-CustomAppProductionByteRealPreparedStageHandoffV010 @stageHandoffArgs
    if($null-eq$postProof-or-not[bool]$postProof.ok-or
       ([string]$postProof.stage_tree_sha256).Trim().ToLowerInvariant()-cne([string]$proof.stage_tree_sha256).Trim().ToLowerInvariant()-or
       ([string]$postProof.archive_sha256).Trim().ToLowerInvariant()-cne([string]$proof.archive_sha256).Trim().ToLowerInvariant()){
        return (& $deny ('prepared-bridge-post-stage-physical-bytes-or-consumption-drift:'+[string]$postProof.reason))
    }

    # Populate the EXACT legacy stage-executor output contract so the existing
    # pre-apply preparation can consume the result without a new install path.
    $result=[pscustomobject]@{
        schema=$CustomAppProductionStageExecutorSchema
        managed_by=$CustomAppProductionStageExecutorManagedBy
        qualified_admission_head=$CustomAppProductionStageExecutorQualifiedAdmissionHead
        qualified_stage_contract_head=$CustomAppProductionStageExecutorQualifiedStageContractHead
        status='staged-verified-post-stage-revalidated'
        consumption_id=$consumption
        pre_stage_admission_fingerprint=([string]$decision.admission_fingerprint).Trim().ToLowerInvariant()
        post_stage_admission_fingerprint=([string]$post.decision.admission_fingerprint).Trim().ToLowerInvariant()
        persistence_envelope_sha256=([string]$post.decision.persistence_envelope_sha256).Trim().ToLowerInvariant()
        name=[string]$post.decision.name;source_identity=([string]$post.decision.source_identity).Trim().ToLowerInvariant()
        github_repo_id=[int64]$post.decision.github_repo_id
        surface_kind=([string]$post.decision.surface_kind).Trim().ToLowerInvariant()
        remote_commit_sha=([string]$post.decision.remote_commit_sha).Trim().ToLowerInvariant()
        local_tree_sha256=([string]$freshLive.tree_sha256).Trim().ToLowerInvariant()
        remote_tree_sha256=([string]$stagecheck.stage_tree_sha256).Trim().ToLowerInvariant()
        binding_fingerprint=([string]$post.decision.binding_fingerprint).Trim().ToLowerInvariant()
        archive_sha256=([string]$postProof.archive_sha256).Trim().ToLowerInvariant()
        workspace_path=$workspace;stage_path=$stage
        staged_at=$Now.ToUniversalTime().ToString('o')
        post_stage_revalidated_at=$postTime.ToUniversalTime().ToString('o')
        stage_performed=$true;live_runtime_unchanged=$true;post_stage_revalidated=$true
        result_fingerprint=$null;result_is_authority=$false
        stage_workspace_retained_for_pre_apply=$true
        requires_cleanup_if_not_promoted=$true;requires_fresh_revalidation_before_apply=$true
        apply_authorized=$false;live_destination_authorized=$false
        production_execution_authorized=$false;production_mutation_authorized=$false
    }
    $result.result_fingerprint=Get-CustomAppProductionStageExecutorSha256V010 (Get-CustomAppProductionStageExecutorResultMaterialV010 -Result $result)
    $valid=Test-CustomAppProductionStageExecutorResultV010 -Result $result
    if(-not[bool]$valid.ok){
        return (& $deny ('prepared-bridge-exact-stage-executor-output-invalid:'+[string]$valid.reason))
    }
    return [pscustomobject]@{
        ok=$true;reason='prepared-real-archive-now-standard-stage-executor-compatible'
        stage_result=$result;workspace_path=$workspace;stage_path=$stage
        stage_prepared_before_permit=$true;fetched_again=$false
        physical_store_reloaded_twice=$true;post_stage_revalidated=$true
        source_issuer_fingerprint=[string]$IssuerResult.receipt.issuer_fingerprint
        new_permit_transaction_id=[string]$IssuerResult.receipt.new_permit_transaction_id
        consumption_id=$consumption
        requires_cleanup_if_not_promoted=$true;ready_to_apply=$false
        apply_authorized=$false;live_destination_authorized=$false
        production_execution_authorized=$false;production_mutation_authorized=$false
    }
}
