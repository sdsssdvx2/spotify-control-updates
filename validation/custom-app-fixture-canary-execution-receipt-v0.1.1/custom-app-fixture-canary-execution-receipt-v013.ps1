$CustomAppFixtureCanaryReceiptSchema = 1
$CustomAppFixtureCanaryReceiptManagedBy = 'custom-app-fixture-canary-execution-receipt-v1'
$CustomAppFixtureCanaryReceiptQualifiedExecutorHead = 'a5d5839a9d6c1dd01c1fced6e9e1f5f76d16b5ca'
$CustomAppFixtureCanaryReceiptQualifiedPermitImplementationHead = '79c7ef064a216ee3ff34328be282d742f0f7abc0'
$CustomAppFixtureCanaryReceiptQualifiedEligibilityHead = '979e9d6362ead31016b9532f98629d6bcc2bbb56'
$CustomAppFixtureCanaryReceiptProductionMain = 'd38e88d9ae99f6a4983e2ad64f74f6fce7e6cde2'
$CustomAppFixtureCanaryReceiptExecutorPushRunId = [int64]40679218583
$CustomAppFixtureCanaryReceiptExecutorPrRunId = [int64]40679419324
$CustomAppFixtureCanaryReceiptExecutorPushArtifactId = [int64]12811478206
$CustomAppFixtureCanaryReceiptExecutorPrArtifactId = [int64]12812541217
$CustomAppFixtureCanaryReceiptExecutorPushArtifactDigest = 'sha256:1326445d22627b6af1542656f47ec2b7933cba47d1112769d52f8b755510e12e'
$CustomAppFixtureCanaryReceiptExecutorPrArtifactDigest = 'sha256:164d003804c8b6d4bf71f0965c9c7be68d8dacceebb098545341446fa8aa68f7'

function Get-CustomAppFixtureCanaryReceiptSha256V013 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}
function Get-CustomAppFixtureCanaryReceiptHmacV013 {
    param([Parameter(Mandatory=$true)][string]$Text,[Parameter(Mandatory=$true)][byte[]]$ReceiptKey)
    if($ReceiptKey.Length -lt 32){throw 'Execution receipt key must be at least 32 bytes.'}
    $h=New-Object System.Security.Cryptography.HMACSHA256
    try{$h.Key=$ReceiptKey;return ([BitConverter]::ToString($h.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$h.Dispose()}
}
function Test-CustomAppFixtureCanaryReceiptFixedTimeHexV013 {
    param([AllowNull()][string]$A,[AllowNull()][string]$B)
    if($null -eq $A -or $null -eq $B -or $A.Length -ne $B.Length){return $false}
    $diff=0
    for($i=0;$i -lt $A.Length;$i++){$diff=$diff -bor ([int][char]$A[$i] -bxor [int][char]$B[$i])}
    return ($diff -eq 0)
}
function Test-CustomAppFixtureCanaryReceiptSha256V013 {param([AllowNull()][string]$Value)return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')}
function Test-CustomAppFixtureCanaryReceiptCommitV013 {param([AllowNull()][string]$Value)return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{40}$')}
function Test-CustomAppFixtureCanaryReceiptArtifactDigestV013 {param([AllowNull()][string]$Value)return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^sha256:[0-9a-f]{64}$')}
function Test-CustomAppFixtureCanaryReceiptNonceV013 {param([AllowNull()][string]$Value)return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{32}$')}

function Test-CustomAppFixtureCanaryReceiptAuthorityDeniedV013 {
    param([AllowNull()]$Object,[string]$Label='object')
    if($null -eq $Object){return [pscustomobject]@{ok=$false;reason=($Label+'-null')}}
    foreach($name in @('mutation_mode','mutation_authorized','auto_update_authorized','auto_install_authorized','canary_execution_authorized','production_mutation_authorized')){
        if(-not $Object.PSObject.Properties[$name]){return [pscustomobject]@{ok=$false;reason=($Label+'-authority-schema-missing-'+$name)}}
    }
    if([string]$Object.mutation_mode -cne 'deny'){return [pscustomobject]@{ok=$false;reason=($Label+'-mutation-mode-not-deny')}}
    foreach($name in @('mutation_authorized','auto_update_authorized','auto_install_authorized','canary_execution_authorized','production_mutation_authorized')){
        if([bool]$Object.$name){return [pscustomobject]@{ok=$false;reason=($Label+'-'+$name+'-true')}}
    }
    return [pscustomobject]@{ok=$true;reason=($Label+'-authority-denied')}
}

function New-CustomAppFixtureCanaryExecutorQualificationV013 {
    return [pscustomobject]@{
        schema=1;managed_by='custom-app-fixture-canary-executor-qualification-v1';executor_head=$CustomAppFixtureCanaryReceiptQualifiedExecutorHead;permit_implementation_head=$CustomAppFixtureCanaryReceiptQualifiedPermitImplementationHead;production_main=$CustomAppFixtureCanaryReceiptProductionMain
        push_run_id=$CustomAppFixtureCanaryReceiptExecutorPushRunId;pull_request_run_id=$CustomAppFixtureCanaryReceiptExecutorPrRunId;push_artifact_id=$CustomAppFixtureCanaryReceiptExecutorPushArtifactId;pull_request_artifact_id=$CustomAppFixtureCanaryReceiptExecutorPrArtifactId
        push_artifact_digest=$CustomAppFixtureCanaryReceiptExecutorPushArtifactDigest;pull_request_artifact_digest=$CustomAppFixtureCanaryReceiptExecutorPrArtifactDigest
        push_success=$true;pull_request_success=$true;live_tagify_fixture_canary_passed=$true;durable_replay_passed=$true;expiry_after_stage_passed=$true;missing_marker_preapply_passed=$true;parent_selftest_passed=$true
        mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;canary_execution_authorized=$false;production_mutation_authorized=$false
    }
}
function Test-CustomAppFixtureCanaryExecutorQualificationV013 {
    param([AllowNull()]$Qualification)
    if($null -eq $Qualification){return [pscustomobject]@{ok=$false;reason='executor-qualification-null';fingerprint=$null}}
    if([int]$Qualification.schema -ne 1 -or [string]$Qualification.managed_by -cne 'custom-app-fixture-canary-executor-qualification-v1'){return [pscustomobject]@{ok=$false;reason='executor-qualification-owner-or-schema-mismatch';fingerprint=$null}}
    $authority=Test-CustomAppFixtureCanaryReceiptAuthorityDeniedV013 -Object $Qualification -Label 'executor-qualification'
    if(-not [bool]$authority.ok){return [pscustomobject]@{ok=$false;reason=[string]$authority.reason;fingerprint=$null}}
    if([string]$Qualification.executor_head -cne $CustomAppFixtureCanaryReceiptQualifiedExecutorHead -or [string]$Qualification.permit_implementation_head -cne $CustomAppFixtureCanaryReceiptQualifiedPermitImplementationHead -or [string]$Qualification.production_main -cne $CustomAppFixtureCanaryReceiptProductionMain){return [pscustomobject]@{ok=$false;reason='executor-qualification-lineage-mismatch';fingerprint=$null}}
    if([int64]$Qualification.push_run_id -ne $CustomAppFixtureCanaryReceiptExecutorPushRunId -or [int64]$Qualification.pull_request_run_id -ne $CustomAppFixtureCanaryReceiptExecutorPrRunId -or [int64]$Qualification.push_artifact_id -ne $CustomAppFixtureCanaryReceiptExecutorPushArtifactId -or [int64]$Qualification.pull_request_artifact_id -ne $CustomAppFixtureCanaryReceiptExecutorPrArtifactId){return [pscustomobject]@{ok=$false;reason='executor-qualification-run-or-artifact-mismatch';fingerprint=$null}}
    $pushDigest=([string]$Qualification.push_artifact_digest).Trim().ToLowerInvariant();$prDigest=([string]$Qualification.pull_request_artifact_digest).Trim().ToLowerInvariant()
    if(-not (Test-CustomAppFixtureCanaryReceiptArtifactDigestV013 $pushDigest) -or -not (Test-CustomAppFixtureCanaryReceiptArtifactDigestV013 $prDigest) -or $pushDigest -cne $CustomAppFixtureCanaryReceiptExecutorPushArtifactDigest -or $prDigest -cne $CustomAppFixtureCanaryReceiptExecutorPrArtifactDigest -or $pushDigest -ceq $prDigest){return [pscustomobject]@{ok=$false;reason='executor-qualification-artifact-digest-mismatch';fingerprint=$null}}
    foreach($name in @('push_success','pull_request_success','live_tagify_fixture_canary_passed','durable_replay_passed','expiry_after_stage_passed','missing_marker_preapply_passed','parent_selftest_passed')){
        if(-not [bool]$Qualification.$name){return [pscustomobject]@{ok=$false;reason=('executor-qualification-evidence-false-'+$name);fingerprint=$null}}
    }
    $material=@(
        [string]$Qualification.executor_head,[string]$Qualification.permit_implementation_head,[string]$Qualification.production_main,[string]$Qualification.push_run_id,[string]$Qualification.pull_request_run_id,
        [string]$Qualification.push_artifact_id,[string]$Qualification.pull_request_artifact_id,$pushDigest,$prDigest,[string]$Qualification.push_success,[string]$Qualification.pull_request_success,
        [string]$Qualification.live_tagify_fixture_canary_passed,[string]$Qualification.durable_replay_passed,[string]$Qualification.expiry_after_stage_passed,[string]$Qualification.missing_marker_preapply_passed,[string]$Qualification.parent_selftest_passed,
        [string]$Qualification.mutation_mode,[string]$Qualification.mutation_authorized,[string]$Qualification.auto_update_authorized,[string]$Qualification.auto_install_authorized,[string]$Qualification.canary_execution_authorized,[string]$Qualification.production_mutation_authorized
    ) -join "`n"
    return [pscustomobject]@{ok=$true;reason='executor-independently-qualified';fingerprint=(Get-CustomAppFixtureCanaryReceiptSha256V013 -Text $material)}
}

function New-CustomAppFixtureCanaryEvidenceV013 {
    param([Parameter(Mandatory=$true)][string]$RuntimeTreeSha256,[Parameter(Mandatory=$true)][string]$ManifestName,[Parameter(Mandatory=$true)][string]$PersistenceFingerprint,[Parameter(Mandatory=$true)][string]$ProvenanceSourceIdentity,[Parameter(Mandatory=$true)][string]$ProvenanceGitConfigSha256,[Parameter(Mandatory=$true)][string]$ProvenanceEvidenceFingerprint)
    $tree=$RuntimeTreeSha256.Trim().ToLowerInvariant();$persist=$PersistenceFingerprint.Trim().ToLowerInvariant();$git=$ProvenanceGitConfigSha256.Trim().ToLowerInvariant();$prov=$ProvenanceEvidenceFingerprint.Trim().ToLowerInvariant();$source=$ProvenanceSourceIdentity.Trim().ToLowerInvariant();$manifest=$ManifestName.Trim()
    if(-not (Test-CustomAppFixtureCanaryReceiptSha256V013 $tree) -or -not (Test-CustomAppFixtureCanaryReceiptSha256V013 $persist) -or -not (Test-CustomAppFixtureCanaryReceiptSha256V013 $git) -or -not (Test-CustomAppFixtureCanaryReceiptSha256V013 $prov) -or [string]::IsNullOrWhiteSpace($manifest) -or $source -notmatch '^[a-z0-9_.-]+/[a-z0-9_.-]+$'){throw 'Execution receipt evidence identity is invalid.'}
    $fp=Get-CustomAppFixtureCanaryReceiptSha256V013 -Text ((@($tree,$manifest,$persist,$source,$git,$prov) -join "`n"))
    return [pscustomobject]@{runtime_tree_sha256=$tree;manifest_name=$manifest;persistence_fingerprint=$persist;provenance_source_identity=$source;provenance_git_config_sha256=$git;provenance_evidence_fingerprint=$prov;evidence_fingerprint=$fp}
}
function Test-CustomAppFixtureCanaryEvidenceV013 {
    param([AllowNull()]$Evidence,[string]$Label='evidence')
    if($null -eq $Evidence){return [pscustomobject]@{ok=$false;reason=($Label+'-null')}}
    foreach($name in @('runtime_tree_sha256','manifest_name','persistence_fingerprint','provenance_source_identity','provenance_git_config_sha256','provenance_evidence_fingerprint','evidence_fingerprint')){if(-not $Evidence.PSObject.Properties[$name]){return [pscustomobject]@{ok=$false;reason=($Label+'-field-missing-'+$name)}}}
    try{$rebuilt=New-CustomAppFixtureCanaryEvidenceV013 -RuntimeTreeSha256 ([string]$Evidence.runtime_tree_sha256) -ManifestName ([string]$Evidence.manifest_name) -PersistenceFingerprint ([string]$Evidence.persistence_fingerprint) -ProvenanceSourceIdentity ([string]$Evidence.provenance_source_identity) -ProvenanceGitConfigSha256 ([string]$Evidence.provenance_git_config_sha256) -ProvenanceEvidenceFingerprint ([string]$Evidence.provenance_evidence_fingerprint)}catch{return [pscustomobject]@{ok=$false;reason=($Label+'-identity-invalid')}}
    if([string]$rebuilt.evidence_fingerprint -cne ([string]$Evidence.evidence_fingerprint).Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason=($Label+'-fingerprint-mismatch')}}
    return [pscustomobject]@{ok=$true;reason=($Label+'-valid');normalized=$rebuilt}
}

function Resolve-CustomAppFixtureCanaryReceiptOutcomeV013 {
    param([Parameter(Mandatory=$true)]$ExecutorResult,[Parameter(Mandatory=$true)]$Permit,[Parameter(Mandatory=$true)]$BeforeEvidence,[Parameter(Mandatory=$true)]$AfterEvidence)
    if([int]$ExecutorResult.schema -ne 1 -or [string]$ExecutorResult.managed_by -cne 'custom-app-fixture-canary-executor-v1'){return [pscustomobject]@{classification='failure-unqualified';safe=$false;qualified=$false;reason='executor-result-owner-or-schema-mismatch'}}
    $authority=Test-CustomAppFixtureCanaryReceiptAuthorityDeniedV013 -Object $ExecutorResult -Label 'executor-result';if(-not [bool]$authority.ok){return [pscustomobject]@{classification='failure-unqualified';safe=$false;qualified=$false;reason=[string]$authority.reason}}
    if([string]$ExecutorResult.qualified_permit_head -cne $CustomAppFixtureCanaryReceiptQualifiedPermitImplementationHead -or [string]$ExecutorResult.name -cne [string]$Permit.name){return [pscustomobject]@{classification='failure-unqualified';safe=$false;qualified=$false;reason='executor-result-lineage-or-name-mismatch'}}
    $status=[string]$ExecutorResult.status;$committed=[bool]$ExecutorResult.committed;$rolledBack=[bool]$ExecutorResult.rolled_back;$preConsumption=($status -ceq 'denied-before-consumption')
    if(-not $preConsumption){if([string]$ExecutorResult.token_id -cne [string]$Permit.token_id -or [string]$ExecutorResult.eligibility_fingerprint -cne [string]$Permit.eligibility_fingerprint){return [pscustomobject]@{classification='failure-unqualified';safe=$false;qualified=$false;reason='executor-result-permit-binding-mismatch'}}}
    else {
        if($ExecutorResult.PSObject.Properties['token_id'] -and -not [string]::IsNullOrWhiteSpace([string]$ExecutorResult.token_id) -and [string]$ExecutorResult.token_id -cne [string]$Permit.token_id){return [pscustomobject]@{classification='failure-unqualified';safe=$false;qualified=$false;reason='preconsumption-result-token-mismatch'}}
        if($ExecutorResult.PSObject.Properties['eligibility_fingerprint'] -and -not [string]::IsNullOrWhiteSpace([string]$ExecutorResult.eligibility_fingerprint) -and [string]$ExecutorResult.eligibility_fingerprint -cne [string]$Permit.eligibility_fingerprint){return [pscustomobject]@{classification='failure-unqualified';safe=$false;qualified=$false;reason='preconsumption-result-eligibility-mismatch'}}
    }
    $sameManifest=([string]$BeforeEvidence.manifest_name -ceq [string]$AfterEvidence.manifest_name)
    $sameRuntime=([string]$BeforeEvidence.runtime_tree_sha256 -ceq [string]$AfterEvidence.runtime_tree_sha256 -and $sameManifest)
    $samePersistence=([string]$BeforeEvidence.persistence_fingerprint -ceq [string]$AfterEvidence.persistence_fingerprint)
    $sameProvenance=([string]$BeforeEvidence.provenance_source_identity -ceq [string]$AfterEvidence.provenance_source_identity -and [string]$BeforeEvidence.provenance_git_config_sha256 -ceq [string]$AfterEvidence.provenance_git_config_sha256)
    $sameEvidence=([string]$BeforeEvidence.evidence_fingerprint -ceq [string]$AfterEvidence.evidence_fingerprint)
    $sourceMatches=([string]$AfterEvidence.provenance_source_identity -ceq ([string]$Permit.source_identity).Trim().ToLowerInvariant())
    if($status -ceq 'committed-fixture-canary' -and $committed -and -not $rolledBack){
        if(-not [bool]$ExecutorResult.fixture_canary_execution_authorized){return [pscustomobject]@{classification='failure-unqualified';safe=$false;qualified=$false;reason='committed-result-missing-fixture-execution-evidence'}}
        if([string]$BeforeEvidence.runtime_tree_sha256 -cne ([string]$Permit.current_tree_sha256).Trim().ToLowerInvariant() -or [string]$AfterEvidence.runtime_tree_sha256 -cne ([string]$Permit.remote_tree_sha256).Trim().ToLowerInvariant()){return [pscustomobject]@{classification='failure-unqualified';safe=$false;qualified=$false;reason='committed-runtime-tree-does-not-match-permit'}}
        if(-not $sameManifest -or -not $samePersistence -or -not $sameProvenance -or -not $sourceMatches){return [pscustomobject]@{classification='failure-unqualified';safe=$false;qualified=$false;reason='committed-protected-state-manifest-or-provenance-drift'}}
        return [pscustomobject]@{classification='committed-preserved';safe=$true;qualified=$true;reason='committed-exact-remote-runtime-with-protected-state-preserved'}
    }
    if($rolledBack -and -not $committed){
        if($sameRuntime -and $samePersistence -and $sameProvenance -and $sameEvidence -and $sourceMatches){return [pscustomobject]@{classification='rolled-back-restored';safe=$true;qualified=$true;reason='rollback-restored-complete-evidence'}}
        return [pscustomobject]@{classification='failure-unqualified';safe=$false;qualified=$false;reason='rollback-did-not-restore-complete-evidence'}
    }
    if(-not $committed -and -not $rolledBack -and ($status -like 'denied-*' -or $status -ceq 'denied-or-rolled-back-fixture-canary')){
        if($sameRuntime -and $samePersistence -and $sameProvenance -and $sameEvidence -and $sourceMatches){return [pscustomobject]@{classification='denied-no-mutation';safe=$true;qualified=$true;reason='denial-left-complete-evidence-unchanged'}}
        return [pscustomobject]@{classification='failure-unqualified';safe=$false;qualified=$false;reason='denial-had-observed-state-drift'}
    }
    return [pscustomobject]@{classification='failure-unqualified';safe=$false;qualified=$false;reason='executor-outcome-not-safely-classifiable'}
}

function Get-CustomAppFixtureCanaryReceiptMaterialV013 {
    param([Parameter(Mandatory=$true)]$Receipt)
    return @(
        [string]$Receipt.schema,[string]$Receipt.managed_by,[string]$Receipt.qualified_executor_head,[string]$Receipt.qualified_permit_implementation_head,[string]$Receipt.executor_qualification_fingerprint,
        [string]$Receipt.name,[string]$Receipt.source_identity,[string]$Receipt.github_repo_id,[string]$Receipt.surface_kind,[string]$Receipt.token_id,[string]$Receipt.permit_hmac_sha256,[string]$Receipt.eligibility_fingerprint,[string]$Receipt.eligibility_candidate_snapshot,
        [string]$Receipt.current_tree_sha256,[string]$Receipt.remote_tree_sha256,[string]$Receipt.remote_commit_sha,[string]$Receipt.executor_status,[string]$Receipt.executor_reason,[string]$Receipt.committed,[string]$Receipt.rolled_back,
        [string]$Receipt.outcome_classification,[string]$Receipt.outcome_safe,[string]$Receipt.outcome_evidence_qualified,[string]$Receipt.outcome_reason,[string]$Receipt.before_evidence_fingerprint,[string]$Receipt.after_evidence_fingerprint,
        [string]$Receipt.before_runtime_tree_sha256,[string]$Receipt.after_runtime_tree_sha256,[string]$Receipt.before_manifest_name,[string]$Receipt.after_manifest_name,[string]$Receipt.before_persistence_fingerprint,[string]$Receipt.after_persistence_fingerprint,
        [string]$Receipt.before_provenance_source,[string]$Receipt.after_provenance_source,[string]$Receipt.before_provenance_git_config_sha256,[string]$Receipt.after_provenance_git_config_sha256,[string]$Receipt.before_provenance_evidence_fingerprint,[string]$Receipt.after_provenance_evidence_fingerprint,
        [string]$Receipt.observed_at,[string]$Receipt.nonce,[string]$Receipt.receipt_is_authority,[string]$Receipt.requires_fresh_revalidation_before_any_future_action,[string]$Receipt.mutation_mode,[string]$Receipt.mutation_authorized,[string]$Receipt.auto_update_authorized,[string]$Receipt.auto_install_authorized,[string]$Receipt.canary_execution_authorized,[string]$Receipt.production_mutation_authorized
    ) -join "`n"
}

function New-CustomAppFixtureCanaryExecutionReceiptV013 {
    param([Parameter(Mandatory=$true)]$ExecutorResult,[Parameter(Mandatory=$true)]$Permit,[Parameter(Mandatory=$true)]$EligibilityDecision,[Parameter(Mandatory=$true)]$BeforeEvidence,[Parameter(Mandatory=$true)]$AfterEvidence,[Parameter(Mandatory=$true)]$ExecutorQualification,[Parameter(Mandatory=$true)][byte[]]$ReceiptKey,[Parameter(Mandatory=$true)][string]$Nonce,[DateTimeOffset]$ObservedAt=[DateTimeOffset]::UtcNow)
    if($ReceiptKey.Length -lt 32){throw 'Execution receipt key must be at least 32 bytes.'}
    $nonceKey=$Nonce.Trim().ToLowerInvariant();if(-not (Test-CustomAppFixtureCanaryReceiptNonceV013 $nonceKey)){throw 'Execution receipt nonce must be exactly 32 lowercase hex characters.'}
    $qualification=Test-CustomAppFixtureCanaryExecutorQualificationV013 -Qualification $ExecutorQualification;if(-not [bool]$qualification.ok){throw ('Executor qualification denied: '+[string]$qualification.reason)}
    $permitAuthority=Test-CustomAppFixtureCanaryReceiptAuthorityDeniedV013 -Object $Permit -Label 'permit';if(-not [bool]$permitAuthority.ok){throw ('Permit authority denied: '+[string]$permitAuthority.reason)}
    if([int]$Permit.schema -ne 1 -or [string]$Permit.managed_by -cne 'custom-app-fixture-canary-permit-v1' -or [string]$Permit.qualified_eligibility_head -cne $CustomAppFixtureCanaryReceiptQualifiedEligibilityHead){throw 'Permit owner/schema/eligibility lineage mismatch.'}
    foreach($field in @('token_id','hmac_sha256','eligibility_fingerprint','current_tree_sha256','remote_tree_sha256')){if(-not (Test-CustomAppFixtureCanaryReceiptSha256V013 ([string]$Permit.$field))){throw ('Permit SHA-256 identity invalid: '+$field)}}
    if(-not (Test-CustomAppFixtureCanaryReceiptCommitV013 ([string]$Permit.remote_commit_sha)){throw 'Permit remote commit identity is invalid.'}
    $eligAuthority=Test-CustomAppFixtureCanaryReceiptAuthorityDeniedV013 -Object $EligibilityDecision -Label 'eligibility';if(-not [bool]$eligAuthority.ok){throw ('Eligibility authority denied: '+[string]$eligAuthority.reason)}
    if([int]$EligibilityDecision.schema -ne 1 -or [string]$EligibilityDecision.managed_by -cne 'custom-app-promotion-eligibility-v1'){throw 'Eligibility decision owner/schema mismatch.'}
    if([string]$EligibilityDecision.name -cne [string]$Permit.name -or ([string]$EligibilityDecision.source_identity).Trim().ToLowerInvariant() -cne ([string]$Permit.source_identity).Trim().ToLowerInvariant() -or [string]$EligibilityDecision.eligibility_fingerprint -cne [string]$Permit.eligibility_fingerprint -or [string]$EligibilityDecision.current_tree_sha256 -cne [string]$Permit.current_tree_sha256 -or [string]$EligibilityDecision.remote_tree_sha256 -cne [string]$Permit.remote_tree_sha256 -or [string]$EligibilityDecision.remote_commit_sha -cne [string]$Permit.remote_commit_sha){throw 'Eligibility decision does not match permit execution identity.'}
    $beforeCheck=Test-CustomAppFixtureCanaryEvidenceV013 -Evidence $BeforeEvidence -Label 'before-evidence';if(-not [bool]$beforeCheck.ok){throw ([string]$beforeCheck.reason)}
    $afterCheck=Test-CustomAppFixtureCanaryEvidenceV013 -Evidence $AfterEvidence -Label 'after-evidence';if(-not [bool]$afterCheck.ok){throw ([string]$afterCheck.reason)}
    $before=$beforeCheck.normalized;$after=$afterCheck.normalized;$outcome=Resolve-CustomAppFixtureCanaryReceiptOutcomeV013 -ExecutorResult $ExecutorResult -Permit $Permit -BeforeEvidence $before -AfterEvidence $after
    if([string]$outcome.classification -ceq 'committed-preserved' -and -not [bool]$EligibilityDecision.promotion_candidate_eligible){$outcome=[pscustomobject]@{classification='failure-unqualified';safe=$false;qualified=$false;reason='committed-with-noneligible-decision-snapshot'}}
    $receipt=[pscustomobject]@{
        schema=$CustomAppFixtureCanaryReceiptSchema;managed_by=$CustomAppFixtureCanaryReceiptManagedBy;qualified_executor_head=$CustomAppFixtureCanaryReceiptQualifiedExecutorHead;qualified_permit_implementation_head=$CustomAppFixtureCanaryReceiptQualifiedPermitImplementationHead;executor_qualification_fingerprint=[string]$qualification.fingerprint
        name=[string]$Permit.name;source_identity=([string]$Permit.source_identity).Trim().ToLowerInvariant();github_repo_id=[int64]$Permit.github_repo_id;surface_kind=[string]$Permit.surface_kind;token_id=([string]$Permit.token_id).Trim().ToLowerInvariant();permit_hmac_sha256=([string]$Permit.hmac_sha256).Trim().ToLowerInvariant()
        eligibility_fingerprint=([string]$Permit.eligibility_fingerprint).Trim().ToLowerInvariant();eligibility_candidate_snapshot=[bool]$EligibilityDecision.promotion_candidate_eligible;current_tree_sha256=([string]$Permit.current_tree_sha256).Trim().ToLowerInvariant();remote_tree_sha256=([string]$Permit.remote_tree_sha256).Trim().ToLowerInvariant();remote_commit_sha=([string]$Permit.remote_commit_sha).Trim().ToLowerInvariant()
        executor_status=[string]$ExecutorResult.status;executor_reason=[string]$ExecutorResult.reason;committed=[bool]$ExecutorResult.committed;rolled_back=[bool]$ExecutorResult.rolled_back;outcome_classification=[string]$outcome.classification;outcome_safe=[bool]$outcome.safe;outcome_evidence_qualified=[bool]$outcome.qualified;outcome_reason=[string]$outcome.reason
        before_evidence_fingerprint=[string]$before.evidence_fingerprint;after_evidence_fingerprint=[string]$after.evidence_fingerprint;before_runtime_tree_sha256=[string]$before.runtime_tree_sha256;after_runtime_tree_sha256=[string]$after.runtime_tree_sha256;before_manifest_name=[string]$before.manifest_name;after_manifest_name=[string]$after.manifest_name
        before_persistence_fingerprint=[string]$before.persistence_fingerprint;after_persistence_fingerprint=[string]$after.persistence_fingerprint;before_provenance_source=[string]$before.provenance_source_identity;after_provenance_source=[string]$after.provenance_source_identity;before_provenance_git_config_sha256=[string]$before.provenance_git_config_sha256;after_provenance_git_config_sha256=[string]$after.provenance_git_config_sha256
        before_provenance_evidence_fingerprint=[string]$before.provenance_evidence_fingerprint;after_provenance_evidence_fingerprint=[string]$after.provenance_evidence_fingerprint;observed_at=$ObservedAt.ToUniversalTime().ToString('o');nonce=$nonceKey;receipt_id=$null;hmac_sha256=$null
        receipt_is_authority=$false;requires_fresh_revalidation_before_any_future_action=$true;mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;canary_execution_authorized=$false;production_mutation_authorized=$false
    }
    $material=Get-CustomAppFixtureCanaryReceiptMaterialV013 -Receipt $receipt;$receipt.receipt_id=Get-CustomAppFixtureCanaryReceiptSha256V013 -Text $material;$receipt.hmac_sha256=Get-CustomAppFixtureCanaryReceiptHmacV013 -Text $material -ReceiptKey $ReceiptKey
    return $receipt
}

function Test-CustomAppFixtureCanaryReceiptSemanticsV013 {
    param([Parameter(Mandatory=$true)]$Receipt)
    if([int64]$Receipt.github_repo_id -le 0 -or [string]::IsNullOrWhiteSpace([string]$Receipt.name) -or ([string]$Receipt.source_identity).Trim().ToLowerInvariant() -notmatch '^[a-z0-9_.-]+/[a-z0-9_.-]+$' -or [string]$Receipt.surface_kind -notin @('repo-commit-root','release-asset')){return [pscustomobject]@{ok=$false;reason='receipt-source-or-repository-semantics-invalid'}}
    $sameManifest=([string]$Receipt.before_manifest_name -ceq [string]$Receipt.after_manifest_name);$samePersistence=([string]$Receipt.before_persistence_fingerprint -ceq [string]$Receipt.after_persistence_fingerprint)
    $sameProvenance=([string]$Receipt.before_provenance_source -ceq [string]$Receipt.after_provenance_source -and [string]$Receipt.before_provenance_git_config_sha256 -ceq [string]$Receipt.after_provenance_git_config_sha256);$sameEvidence=([string]$Receipt.before_evidence_fingerprint -ceq [string]$Receipt.after_evidence_fingerprint)
    switch -CaseSensitive ([string]$Receipt.outcome_classification) {
        'committed-preserved' {
            if(-not [bool]$Receipt.committed -or [bool]$Receipt.rolled_back -or -not [bool]$Receipt.outcome_safe -or -not [bool]$Receipt.outcome_evidence_qualified -or -not [bool]$Receipt.eligibility_candidate_snapshot){return [pscustomobject]@{ok=$false;reason='receipt-committed-flags-invalid'}}
            if([string]$Receipt.executor_status -cne 'committed-fixture-canary' -or [string]$Receipt.before_runtime_tree_sha256 -cne [string]$Receipt.current_tree_sha256 -or [string]$Receipt.after_runtime_tree_sha256 -cne [string]$Receipt.remote_tree_sha256 -or -not $sameManifest -or -not $samePersistence -or -not $sameProvenance){return [pscustomobject]@{ok=$false;reason='receipt-committed-semantics-invalid'}}
        }
        'denied-no-mutation' {if([bool]$Receipt.committed -or [bool]$Receipt.rolled_back -or -not [bool]$Receipt.outcome_safe -or -not [bool]$Receipt.outcome_evidence_qualified -or [string]$Receipt.executor_status -notlike 'denied-*' -or -not $sameEvidence){return [pscustomobject]@{ok=$false;reason='receipt-denied-semantics-invalid'}}}
        'rolled-back-restored' {if([bool]$Receipt.committed -or -not [bool]$Receipt.rolled_back -or -not [bool]$Receipt.outcome_safe -or -not [bool]$Receipt.outcome_evidence_qualified -or -not $sameEvidence){return [pscustomobject]@{ok=$false;reason='receipt-rollback-semantics-invalid'}}}
        'failure-unqualified' {if([bool]$Receipt.outcome_safe -or [bool]$Receipt.outcome_evidence_qualified){return [pscustomobject]@{ok=$false;reason='receipt-failure-flags-invalid'}}}
        default {return [pscustomobject]@{ok=$false;reason='receipt-outcome-classification-invalid'}}
    }
    return [pscustomobject]@{ok=$true;reason='receipt-outcome-semantics-valid'}
}

function Test-CustomAppFixtureCanaryExecutionReceiptV013 {
    param([AllowNull()]$Receipt,[Parameter(Mandatory=$true)][byte[]]$ReceiptKey,[AllowNull()]$ExecutorQualification=$null)
    if($null -eq $Receipt){return [pscustomobject]@{ok=$false;reason='receipt-null'}}
    if($ReceiptKey.Length -lt 32){return [pscustomobject]@{ok=$false;reason='receipt-key-too-short'}}
    if([int]$Receipt.schema -ne 1 -or [string]$Receipt.managed_by -cne $CustomAppFixtureCanaryReceiptManagedBy -or [string]$Receipt.qualified_executor_head -cne $CustomAppFixtureCanaryReceiptQualifiedExecutorHead -or [string]$Receipt.qualified_permit_implementation_head -cne $CustomAppFixtureCanaryReceiptQualifiedPermitImplementationHead){return [pscustomobject]@{ok=$false;reason='receipt-owner-schema-or-lineage-mismatch'}}
    $authority=Test-CustomAppFixtureCanaryReceiptAuthorityDeniedV013 -Object $Receipt -Label 'receipt';if(-not [bool]$authority.ok){return [pscustomobject]@{ok=$false;reason=[string]$authority.reason}}
    if([bool]$Receipt.receipt_is_authority -or -not [bool]$Receipt.requires_fresh_revalidation_before_any_future_action){return [pscustomobject]@{ok=$false;reason='receipt-authority-separation-flags-invalid'}}
    foreach($field in @('receipt_id','hmac_sha256','executor_qualification_fingerprint','token_id','permit_hmac_sha256','eligibility_fingerprint','current_tree_sha256','remote_tree_sha256','before_evidence_fingerprint','after_evidence_fingerprint','before_runtime_tree_sha256','after_runtime_tree_sha256','before_persistence_fingerprint','after_persistence_fingerprint','before_provenance_git_config_sha256','after_provenance_git_config_sha256','before_provenance_evidence_fingerprint','after_provenance_evidence_fingerprint')){if(-not (Test-CustomAppFixtureCanaryReceiptSha256V013 ([string]$Receipt.$field))){return [pscustomobject]@{ok=$false;reason=('receipt-sha256-field-invalid-'+$field)}}}
    if(-not (Test-CustomAppFixtureCanaryReceiptCommitV013 ([string]$Receipt.remote_commit_sha)) -or -not (Test-CustomAppFixtureCanaryReceiptNonceV013 ([string]$Receipt.nonce))){return [pscustomobject]@{ok=$false;reason='receipt-commit-or-nonce-invalid'}}
    $observed=[DateTimeOffset]::MinValue;if(-not [DateTimeOffset]::TryParse([string]$Receipt.observed_at,[ref]$observed)){return [pscustomobject]@{ok=$false;reason='receipt-observed-at-invalid'}}
    if($null -ne $ExecutorQualification){$q=Test-CustomAppFixtureCanaryExecutorQualificationV013 -Qualification $ExecutorQualification;if(-not [bool]$q.ok){return [pscustomobject]@{ok=$false;reason=('receipt-executor-qualification-denied:'+[string]$q.reason)}};if([string]$Receipt.executor_qualification_fingerprint -cne [string]$q.fingerprint){return [pscustomobject]@{ok=$false;reason='receipt-executor-qualification-fingerprint-mismatch'}}}
    $material=Get-CustomAppFixtureCanaryReceiptMaterialV013 -Receipt $Receipt;$expectedId=Get-CustomAppFixtureCanaryReceiptSha256V013 -Text $material
    if(-not (Test-CustomAppFixtureCanaryReceiptFixedTimeHexV013 -A ([string]$Receipt.receipt_id) -B $expectedId)){return [pscustomobject]@{ok=$false;reason='receipt-id-mismatch'}}
    $expectedMac=Get-CustomAppFixtureCanaryReceiptHmacV013 -Text $material -ReceiptKey $ReceiptKey
    if(-not (Test-CustomAppFixtureCanaryReceiptFixedTimeHexV013 -A ([string]$Receipt.hmac_sha256) -B $expectedMac)){return [pscustomobject]@{ok=$false;reason='receipt-hmac-mismatch'}}
    $semantic=Test-CustomAppFixtureCanaryReceiptSemanticsV013 -Receipt $Receipt;if(-not [bool]$semantic.ok){return [pscustomobject]@{ok=$false;reason=[string]$semantic.reason}}
    return [pscustomobject]@{ok=$true;reason='execution-receipt-hmac-and-semantics-valid';receipt_id=[string]$Receipt.receipt_id;outcome_classification=[string]$Receipt.outcome_classification;outcome_safe=[bool]$Receipt.outcome_safe;outcome_evidence_qualified=[bool]$Receipt.outcome_evidence_qualified;receipt_is_authority=$false;production_mutation_authorized=$false}
}
