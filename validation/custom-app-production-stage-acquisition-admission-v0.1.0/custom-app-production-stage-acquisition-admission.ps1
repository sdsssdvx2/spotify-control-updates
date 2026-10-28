$CustomAppProductionStageAdmissionSchema = 1
$CustomAppProductionStageAdmissionManagedBy = 'custom-app-production-stage-acquisition-admission-v1'
$CustomAppProductionStageAdmissionQualifiedStartHead = '29fe26f505d2f0fb8d9f47e76b5b819ebe1c129d'
$CustomAppProductionStageAdmissionQualifiedStageHead = 'c420a1df6f306c7ba74772b91241cb14abd04738'

function Get-CustomAppProductionStageAdmissionSha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}

function Test-CustomAppProductionStageAdmissionSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}

function Get-CustomAppProductionStageAdmissionMaterialV010 {
    param([Parameter(Mandatory=$true)]$Decision)
    return @(
        [string]$Decision.schema,[string]$Decision.managed_by,[string]$Decision.qualified_executor_start_head,[string]$Decision.qualified_stage_contract_head,
        [string]$Decision.reason,[string]$Decision.consumption_id,[string]$Decision.executor_start_eligibility_fingerprint,[string]$Decision.persistence_envelope_sha256,
        [string]$Decision.name,[string]$Decision.source_identity,[string]$Decision.github_repo_id,[string]$Decision.surface_kind,
        [string]$Decision.current_tree_sha256,[string]$Decision.remote_tree_sha256,[string]$Decision.remote_commit_sha,[string]$Decision.binding_fingerprint,
        [string]$Decision.stage_workspace_root,[string]$Decision.evaluated_at,[string]$Decision.stage_eligibility_expires_at,
        [string]$Decision.stage_acquisition_eligible,[string]$Decision.admission_is_authority,[string]$Decision.requires_immediate_gate_rerun_by_stage_executor,
        [string]$Decision.requires_exact_stage_contract,[string]$Decision.requires_fresh_revalidation_after_stage,[string]$Decision.requires_fresh_revalidation_before_apply,
        [string]$Decision.stage_acquisition_authorized,[string]$Decision.live_destination_authorized,[string]$Decision.apply_authorized,
        [string]$Decision.executor_may_apply,[string]$Decision.production_execution_authorized,[string]$Decision.production_mutation_authorized
    ) -join "`n"
}

function Test-CustomAppProductionStageAdmissionDecisionV010 {
    param([AllowNull()]$Decision)
    if($null -eq $Decision){return [pscustomobject]@{ok=$false;reason='stage-admission-null'}}
    foreach($required in @(
        'schema','managed_by','qualified_executor_start_head','qualified_stage_contract_head','reason','consumption_id','executor_start_eligibility_fingerprint','persistence_envelope_sha256',
        'name','source_identity','github_repo_id','surface_kind','current_tree_sha256','remote_tree_sha256','remote_commit_sha','binding_fingerprint','stage_workspace_root',
        'evaluated_at','stage_eligibility_expires_at','stage_acquisition_eligible','admission_fingerprint','admission_is_authority','requires_immediate_gate_rerun_by_stage_executor',
        'requires_exact_stage_contract','requires_fresh_revalidation_after_stage','requires_fresh_revalidation_before_apply','stage_acquisition_authorized','live_destination_authorized','apply_authorized',
        'executor_may_apply','production_execution_authorized','production_mutation_authorized'
    )){if(-not $Decision.PSObject.Properties[$required]){return [pscustomobject]@{ok=$false;reason=('stage-admission-required-field-missing-'+$required)}}}
    if([int]$Decision.schema -ne $CustomAppProductionStageAdmissionSchema -or [string]$Decision.managed_by -cne $CustomAppProductionStageAdmissionManagedBy -or [string]$Decision.qualified_executor_start_head -cne $CustomAppProductionStageAdmissionQualifiedStartHead -or [string]$Decision.qualified_stage_contract_head -cne $CustomAppProductionStageAdmissionQualifiedStageHead -or [string]$Decision.reason -cne 'fresh-start-and-stage-binding-eligible'){return [pscustomobject]@{ok=$false;reason='stage-admission-owner-schema-parent-or-reason-invalid'}}
    if(-not [bool]$Decision.stage_acquisition_eligible -or [bool]$Decision.admission_is_authority -or -not [bool]$Decision.requires_immediate_gate_rerun_by_stage_executor -or -not [bool]$Decision.requires_exact_stage_contract -or -not [bool]$Decision.requires_fresh_revalidation_after_stage -or -not [bool]$Decision.requires_fresh_revalidation_before_apply){return [pscustomobject]@{ok=$false;reason='stage-admission-separation-contract-invalid'}}
    foreach($field in @('stage_acquisition_authorized','live_destination_authorized','apply_authorized','executor_may_apply','production_execution_authorized','production_mutation_authorized')){if([bool]$Decision.$field){return [pscustomobject]@{ok=$false;reason=('stage-admission-'+$field+'-true')}}}
    foreach($field in @('consumption_id','executor_start_eligibility_fingerprint','persistence_envelope_sha256','current_tree_sha256','remote_tree_sha256','binding_fingerprint','admission_fingerprint')){if(-not (Test-CustomAppProductionStageAdmissionSha256V010 (([string]$Decision.$field).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('stage-admission-invalid-'+$field)}}}
    if(([string]$Decision.remote_commit_sha).Trim().ToLowerInvariant() -notmatch '^[0-9a-f]{40}$'){return [pscustomobject]@{ok=$false;reason='stage-admission-invalid-remote-commit'}}
    try{$repo=[int64]$Decision.github_repo_id}catch{return [pscustomobject]@{ok=$false;reason='stage-admission-repo-id-invalid'}}
    if($repo -le 0){return [pscustomobject]@{ok=$false;reason='stage-admission-repo-id-invalid'}}
    $workspace=[IO.Path]::GetFullPath([string]$Decision.stage_workspace_root).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    $expectedWorkspace=[IO.Path]::GetFullPath((Get-CustomAppStageWorkspaceRootV010)).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    if(-not $workspace.Equals($expectedWorkspace,[StringComparison]::OrdinalIgnoreCase)){return [pscustomobject]@{ok=$false;reason='stage-admission-workspace-root-drift'}}
    $evaluated=[DateTimeOffset]::MinValue;$expires=[DateTimeOffset]::MinValue
    if(-not [DateTimeOffset]::TryParse([string]$Decision.evaluated_at,[ref]$evaluated) -or -not [DateTimeOffset]::TryParse([string]$Decision.stage_eligibility_expires_at,[ref]$expires) -or $expires -le $evaluated -or $expires -gt $evaluated.AddSeconds(30)){return [pscustomobject]@{ok=$false;reason='stage-admission-time-window-invalid'}}
    $expected=Get-CustomAppProductionStageAdmissionSha256V010 (Get-CustomAppProductionStageAdmissionMaterialV010 -Decision $Decision)
    if(([string]$Decision.admission_fingerprint).Trim().ToLowerInvariant() -cne $expected){return [pscustomobject]@{ok=$false;reason='stage-admission-fingerprint-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='stage-admission-valid-non-authority';admission_fingerprint=$expected}
}

function Resolve-CustomAppProductionStageAdmissionV010 {
    param(
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory,[Parameter(Mandatory=$true)][string]$ExpectedConsumptionId,
        [AllowNull()]$Permit,[Parameter(Mandatory=$true)][string]$Name,[AllowNull()]$LifecycleRow,[AllowNull()]$ProvenanceRow,[AllowNull()]$BindingRow,[AllowNull()]$CurrentBaseline,[AllowNull()]$ShadowProtocolQualification,[AllowNull()]$LiveAttestedQualification,
        [Parameter(Mandatory=$true)][byte[]]$SessionKey,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow,[int]$MaxRemoteObservationAgeHours=36
    )
    $deny={param([string]$Reason)[pscustomobject]@{ok=$false;reason=$Reason;stage_acquisition_eligible=$false;admission_is_authority=$false;requires_immediate_gate_rerun_by_stage_executor=$true;requires_exact_stage_contract=$true;requires_fresh_revalidation_after_stage=$true;requires_fresh_revalidation_before_apply=$true;stage_acquisition_authorized=$false;live_destination_authorized=$false;apply_authorized=$false;executor_may_apply=$false;production_execution_authorized=$false;production_mutation_authorized=$false}}

    $start=Resolve-CustomAppProductionExecutorStartGateV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedConsumptionId $ExpectedConsumptionId -Permit $Permit -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -CurrentBaseline $CurrentBaseline -ShadowProtocolQualification $ShadowProtocolQualification -LiveAttestedQualification $LiveAttestedQualification -SessionKey $SessionKey -Now $Now -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    if($null -eq $start -or -not [bool]$start.ok -or -not [bool]$start.staging_eligible){return & $deny ('executor-start-gate-denied:'+[string]$start.reason)}
    $startCheck=Test-CustomAppProductionExecutorStartEligibilityV010 -Decision $start.decision
    if(-not [bool]$startCheck.ok){return & $deny ('executor-start-eligibility-invalid:'+[string]$startCheck.reason)}
    $stageBinding=Test-CustomAppStageBindingRowV010 -BindingRow $BindingRow -ExpectedName $Name
    if(-not [bool]$stageBinding.ok){return & $deny ('stage-binding-denied:'+[string]$stageBinding.reason)}

    $startDecision=$start.decision
    if(([string]$startDecision.name).Trim().ToLowerInvariant() -cne ([string]$stageBinding.name).Trim().ToLowerInvariant()){return & $deny 'start-stage-name-mismatch'}
    if(([string]$startDecision.source_identity).Trim().ToLowerInvariant() -cne ([string]$stageBinding.source).Trim().ToLowerInvariant()){return & $deny 'start-stage-source-mismatch'}
    try{if([int64]$startDecision.github_repo_id -ne [int64]$stageBinding.repo_id){return & $deny 'start-stage-repo-id-mismatch'}}catch{return & $deny 'start-stage-repo-id-invalid'}
    if(([string]$startDecision.surface_kind).Trim().ToLowerInvariant() -cne ([string]$stageBinding.surface).Trim().ToLowerInvariant()){return & $deny 'start-stage-surface-mismatch'}
    if(([string]$startDecision.remote_tree_sha256).Trim().ToLowerInvariant() -cne ([string]$stageBinding.remote_tree_sha256).Trim().ToLowerInvariant()){return & $deny 'start-stage-remote-tree-mismatch'}
    if(([string]$startDecision.remote_commit_sha).Trim().ToLowerInvariant() -cne ([string]$stageBinding.commit_sha).Trim().ToLowerInvariant()){return & $deny 'start-stage-commit-mismatch'}

    $startExpiry=[DateTimeOffset]::MinValue
    if(-not [DateTimeOffset]::TryParse([string]$startDecision.staging_eligibility_expires_at,[ref]$startExpiry)){return & $deny 'executor-start-expiry-invalid'}
    $expires=$Now.AddSeconds(30);if($startExpiry -lt $expires){$expires=$startExpiry};if($expires -le $Now){return & $deny 'stage-admission-window-empty'}
    $workspace=[IO.Path]::GetFullPath((Get-CustomAppStageWorkspaceRootV010)).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    $decision=[pscustomobject]@{
        schema=$CustomAppProductionStageAdmissionSchema;managed_by=$CustomAppProductionStageAdmissionManagedBy;qualified_executor_start_head=$CustomAppProductionStageAdmissionQualifiedStartHead;qualified_stage_contract_head=$CustomAppProductionStageAdmissionQualifiedStageHead
        reason='fresh-start-and-stage-binding-eligible';consumption_id=([string]$startDecision.consumption_id).Trim().ToLowerInvariant();executor_start_eligibility_fingerprint=([string]$startDecision.eligibility_fingerprint).Trim().ToLowerInvariant();persistence_envelope_sha256=([string]$startDecision.persistence_envelope_sha256).Trim().ToLowerInvariant()
        name=[string]$startDecision.name;source_identity=([string]$startDecision.source_identity).Trim().ToLowerInvariant();github_repo_id=[int64]$startDecision.github_repo_id;surface_kind=([string]$startDecision.surface_kind).Trim().ToLowerInvariant()
        current_tree_sha256=([string]$startDecision.current_tree_sha256).Trim().ToLowerInvariant();remote_tree_sha256=([string]$startDecision.remote_tree_sha256).Trim().ToLowerInvariant();remote_commit_sha=([string]$startDecision.remote_commit_sha).Trim().ToLowerInvariant();binding_fingerprint=([string]$stageBinding.binding_fingerprint).Trim().ToLowerInvariant()
        stage_workspace_root=$workspace;evaluated_at=$Now.ToUniversalTime().ToString('o');stage_eligibility_expires_at=$expires.ToUniversalTime().ToString('o');stage_acquisition_eligible=$true;admission_fingerprint=$null;admission_is_authority=$false
        requires_immediate_gate_rerun_by_stage_executor=$true;requires_exact_stage_contract=$true;requires_fresh_revalidation_after_stage=$true;requires_fresh_revalidation_before_apply=$true
        stage_acquisition_authorized=$false;live_destination_authorized=$false;apply_authorized=$false;executor_may_apply=$false;production_execution_authorized=$false;production_mutation_authorized=$false
    }
    $decision.admission_fingerprint=Get-CustomAppProductionStageAdmissionSha256V010 (Get-CustomAppProductionStageAdmissionMaterialV010 -Decision $decision)
    $check=Test-CustomAppProductionStageAdmissionDecisionV010 -Decision $decision
    if(-not [bool]$check.ok){return & $deny ('stage-admission-self-validation-failed:'+[string]$check.reason)}
    return [pscustomobject]@{
        ok=$true;reason=[string]$decision.reason;decision=$decision;stage_acquisition_eligible=$true;admission_fingerprint=[string]$decision.admission_fingerprint;admission_is_authority=$false
        requires_immediate_gate_rerun_by_stage_executor=$true;requires_exact_stage_contract=$true;requires_fresh_revalidation_after_stage=$true;requires_fresh_revalidation_before_apply=$true
        stage_acquisition_authorized=$false;live_destination_authorized=$false;apply_authorized=$false;executor_may_apply=$false;production_execution_authorized=$false;production_mutation_authorized=$false
    }
}
