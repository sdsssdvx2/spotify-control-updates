$CustomAppProductionRecoveryHousekeepingResumeSchema = 1
$CustomAppProductionRecoveryHousekeepingResumeManagedBy = 'custom-app-production-recovery-housekeeping-resume-v1'
$CustomAppProductionRecoveryHousekeepingResumeQualifiedIntegrationHead = '5232e5adeb13e6942acb210b3cd13058e1eaaf05'
$CustomAppProductionRecoveryHousekeepingResumeQualifiedCleanupHead = '67458cbb96b5d1ed92e26c2b81debd6894044749'

function Get-CustomAppProductionRecoveryHousekeepingResumeSha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}
function Test-CustomAppProductionRecoveryHousekeepingResumeSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}
function Get-CustomAppProductionRecoveryHousekeepingResumeCanonicalPathV010 {
    param([Parameter(Mandatory=$true)][string]$Path)
    if([string]::IsNullOrWhiteSpace($Path)){throw 'housekeeping-resume-path-empty'}
    return [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
}

function Get-CustomAppProductionRecoveryHousekeepingResumeEnvelopeMaterialV010 {
    param([Parameter(Mandatory=$true)]$Envelope)
    return @(
        [string]$Envelope.schema,[string]$Envelope.managed_by,[string]$Envelope.qualified_integration_head,[string]$Envelope.qualified_cleanup_head,
        [string]$Envelope.transaction_id,[string]$Envelope.evidence_fingerprint,[string]$Envelope.preparation_fingerprint,[string]$Envelope.source_journal_revision,[string]$Envelope.source_journal_entry_sha256,[string]$Envelope.source_phase,
        [string]$Envelope.name,[string]$Envelope.source_identity,[string]$Envelope.remote_commit_sha,[string]$Envelope.consumption_id,
        [string]$Envelope.live_path,[string]$Envelope.live_runtime_tree_sha256,[string]$Envelope.preserved_git_present,[string]$Envelope.preserved_git_tree_sha256,[string]$Envelope.persistence_fingerprint,
        [string]$Envelope.local_appdata_root,[string]$Envelope.appdata_root,[string]$Envelope.stage_workspace_root,[string]$Envelope.stage_workspace_path,[string]$Envelope.stage_path,[string]$Envelope.stage_tree_sha256,
        [string]$Envelope.app_backup_root,[string]$Envelope.app_backup_path,[string]$Envelope.app_backup_tree_sha256,[string]$Envelope.app_backup_file_count,[string]$Envelope.app_backup_total_bytes,[string]$Envelope.persistence_backup_root,[string]$Envelope.persistence_backup_path,[string]$Envelope.created_at,
        [string]$Envelope.resume_is_authority,[string]$Envelope.cleanup_authorized,[string]$Envelope.execution_authorized,[string]$Envelope.production_execution_authorized,[string]$Envelope.production_mutation_authorized
    ) -join "`n"
}

function Test-CustomAppProductionRecoveryHousekeepingResumeEnvelopeV010 {
    param([AllowNull()]$Envelope)
    if($null -eq $Envelope){return [pscustomobject]@{ok=$false;reason='housekeeping-resume-envelope-null'}}
    $required=@('schema','managed_by','qualified_integration_head','qualified_cleanup_head','transaction_id','evidence_fingerprint','preparation_fingerprint','source_journal_revision','source_journal_entry_sha256','source_phase','name','source_identity','remote_commit_sha','consumption_id','live_path','live_runtime_tree_sha256','preserved_git_present','preserved_git_tree_sha256','persistence_fingerprint','local_appdata_root','appdata_root','stage_workspace_root','stage_workspace_path','stage_path','stage_tree_sha256','app_backup_root','app_backup_path','app_backup_tree_sha256','app_backup_file_count','app_backup_total_bytes','persistence_backup_root','persistence_backup_path','created_at','resume_is_authority','cleanup_authorized','execution_authorized','production_execution_authorized','production_mutation_authorized','resume_fingerprint')
    foreach($f in $required){if(-not $Envelope.PSObject.Properties[$f]){return [pscustomobject]@{ok=$false;reason=('housekeeping-resume-envelope-required-field-missing-'+$f)}}}
    if([int]$Envelope.schema -ne 1 -or [string]$Envelope.managed_by -cne $CustomAppProductionRecoveryHousekeepingResumeManagedBy -or [string]$Envelope.qualified_integration_head -cne $CustomAppProductionRecoveryHousekeepingResumeQualifiedIntegrationHead -or [string]$Envelope.qualified_cleanup_head -cne $CustomAppProductionRecoveryHousekeepingResumeQualifiedCleanupHead){return [pscustomobject]@{ok=$false;reason='housekeeping-resume-envelope-owner-schema-parent-mismatch'}}
    foreach($f in @('transaction_id','evidence_fingerprint','preparation_fingerprint','source_journal_entry_sha256','consumption_id','live_runtime_tree_sha256','persistence_fingerprint','stage_tree_sha256','app_backup_tree_sha256','resume_fingerprint')){if(-not(Test-CustomAppProductionRecoveryHousekeepingResumeSha256V010(([string]$Envelope.$f).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('housekeeping-resume-envelope-invalid-'+$f)}}}
    if([string]$Envelope.remote_commit_sha -notmatch '^[0-9a-fA-F]{40}$' -or [string]$Envelope.source_identity -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' -or [string]::IsNullOrWhiteSpace([string]$Envelope.name)){return [pscustomobject]@{ok=$false;reason='housekeeping-resume-envelope-identity-invalid'}}
    if([string]$Envelope.source_phase -notin @('apply-verified','cleanup-starting')){return [pscustomobject]@{ok=$false;reason='housekeeping-resume-envelope-source-phase-invalid'}}
    try{if([int64]$Envelope.source_journal_revision -lt 0 -or [int]$Envelope.app_backup_file_count -lt 1 -or [int64]$Envelope.app_backup_total_bytes -lt 1){return [pscustomobject]@{ok=$false;reason='housekeeping-resume-envelope-count-invalid'}}}catch{return [pscustomobject]@{ok=$false;reason='housekeeping-resume-envelope-count-invalid'}}
    foreach($f in @('resume_is_authority','cleanup_authorized','execution_authorized','production_execution_authorized','production_mutation_authorized')){if([bool]$Envelope.$f){return [pscustomobject]@{ok=$false;reason=('housekeeping-resume-envelope-authority-escaped-'+$f)}}}
    if([bool]$Envelope.preserved_git_present){if(-not(Test-CustomAppProductionRecoveryHousekeepingResumeSha256V010(([string]$Envelope.preserved_git_tree_sha256).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason='housekeeping-resume-envelope-git-hash-invalid'}}}elseif(-not [string]::IsNullOrWhiteSpace([string]$Envelope.preserved_git_tree_sha256)){return [pscustomobject]@{ok=$false;reason='housekeeping-resume-envelope-unexpected-git-hash'}}
    $at=[DateTimeOffset]::MinValue;if(-not[DateTimeOffset]::TryParse([string]$Envelope.created_at,[ref]$at)){return [pscustomobject]@{ok=$false;reason='housekeeping-resume-envelope-time-invalid'}}
    $expected=Get-CustomAppProductionRecoveryHousekeepingResumeSha256V010 (Get-CustomAppProductionRecoveryHousekeepingResumeEnvelopeMaterialV010 $Envelope)
    if(([string]$Envelope.resume_fingerprint).Trim().ToLowerInvariant() -cne $expected){return [pscustomobject]@{ok=$false;reason='housekeeping-resume-envelope-fingerprint-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='housekeeping-resume-envelope-valid-zero-authority';fingerprint=$expected}
}

function Get-CustomAppProductionRecoveryHousekeepingResumeDecisionMaterialV010 {
    param([Parameter(Mandatory=$true)]$Decision)
    return @([string]$Decision.schema,[string]$Decision.managed_by,[string]$Decision.qualified_integration_head,[string]$Decision.transaction_id,[string]$Decision.resume_fingerprint,[string]$Decision.evidence_fingerprint,[string]$Decision.preparation_fingerprint,[string]$Decision.journal_revision,[string]$Decision.journal_entry_sha256,[string]$Decision.phase,[string]$Decision.name,[string]$Decision.live_runtime_tree_sha256,[string]$Decision.preserved_git_present,[string]$Decision.preserved_git_tree_sha256,[string]$Decision.persistence_fingerprint,[string]$Decision.stage_cleanup_status,[string]$Decision.app_backup_cleanup_status,[string]$Decision.persistence_backup_cleanup_status,[string]$Decision.checked_at,[string]$Decision.eligible_until,[string]$Decision.resume_preconditions_satisfied,[string]$Decision.resume_is_authority,[string]$Decision.cleanup_authorized,[string]$Decision.execution_authorized,[string]$Decision.production_execution_authorized,[string]$Decision.production_mutation_authorized) -join "`n"
}
function Test-CustomAppProductionRecoveryHousekeepingResumeDecisionV010 {
    param([AllowNull()]$Decision,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow)
    if($null-eq$Decision){return [pscustomobject]@{ok=$false;reason='housekeeping-resume-decision-null'}}
    $required=@('schema','managed_by','qualified_integration_head','transaction_id','resume_fingerprint','evidence_fingerprint','preparation_fingerprint','journal_revision','journal_entry_sha256','phase','name','live_runtime_tree_sha256','preserved_git_present','preserved_git_tree_sha256','persistence_fingerprint','stage_cleanup_status','app_backup_cleanup_status','persistence_backup_cleanup_status','checked_at','eligible_until','resume_preconditions_satisfied','resume_is_authority','cleanup_authorized','execution_authorized','production_execution_authorized','production_mutation_authorized','decision_fingerprint')
    foreach($f in $required){if(-not$Decision.PSObject.Properties[$f]){return [pscustomobject]@{ok=$false;reason=('housekeeping-resume-decision-required-field-missing-'+$f)}}}
    if([int]$Decision.schema-ne1-or[string]$Decision.managed_by-cne$CustomAppProductionRecoveryHousekeepingResumeManagedBy-or[string]$Decision.qualified_integration_head-cne$CustomAppProductionRecoveryHousekeepingResumeQualifiedIntegrationHead-or[string]$Decision.phase-cne'cleanup-starting'){return [pscustomobject]@{ok=$false;reason='housekeeping-resume-decision-owner-schema-parent-or-phase-invalid'}}
    foreach($f in @('transaction_id','resume_fingerprint','evidence_fingerprint','preparation_fingerprint','journal_entry_sha256','live_runtime_tree_sha256','persistence_fingerprint','decision_fingerprint')){if(-not(Test-CustomAppProductionRecoveryHousekeepingResumeSha256V010(([string]$Decision.$f).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('housekeeping-resume-decision-invalid-'+$f)}}}
    if([bool]$Decision.preserved_git_present){if(-not(Test-CustomAppProductionRecoveryHousekeepingResumeSha256V010(([string]$Decision.preserved_git_tree_sha256).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason='housekeeping-resume-decision-git-hash-invalid'}}}elseif(-not[string]::IsNullOrWhiteSpace([string]$Decision.preserved_git_tree_sha256)){return [pscustomobject]@{ok=$false;reason='housekeeping-resume-decision-unexpected-git-hash'}}
    foreach($f in @('stage_cleanup_status','app_backup_cleanup_status','persistence_backup_cleanup_status')){if([string]$Decision.$f -notin @('present-verified','already-absent')){return [pscustomobject]@{ok=$false;reason=('housekeeping-resume-decision-invalid-'+$f)}}}
    if(-not[bool]$Decision.resume_preconditions_satisfied){return [pscustomobject]@{ok=$false;reason='housekeeping-resume-decision-preconditions-not-satisfied'}}
    foreach($f in @('resume_is_authority','cleanup_authorized','execution_authorized','production_execution_authorized','production_mutation_authorized')){if([bool]$Decision.$f){return [pscustomobject]@{ok=$false;reason=('housekeeping-resume-decision-authority-escaped-'+$f)}}}
    $start=[DateTimeOffset]::MinValue;$end=[DateTimeOffset]::MinValue;if(-not[DateTimeOffset]::TryParse([string]$Decision.checked_at,[ref]$start)-or-not[DateTimeOffset]::TryParse([string]$Decision.eligible_until,[ref]$end)-or$end-le$start-or$end-gt$start.AddSeconds(10)){return [pscustomobject]@{ok=$false;reason='housekeeping-resume-decision-time-invalid'}}
    if($Now-lt$start.AddSeconds(-5)){return [pscustomobject]@{ok=$false;reason='housekeeping-resume-decision-not-yet-valid'}};if($Now-ge$end){return [pscustomobject]@{ok=$false;reason='housekeeping-resume-decision-expired'}}
    $expected=Get-CustomAppProductionRecoveryHousekeepingResumeSha256V010 (Get-CustomAppProductionRecoveryHousekeepingResumeDecisionMaterialV010 $Decision);if(([string]$Decision.decision_fingerprint).Trim().ToLowerInvariant()-cne$expected){return [pscustomobject]@{ok=$false;reason='housekeeping-resume-decision-fingerprint-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='housekeeping-resume-decision-valid-zero-authority';transaction_id=([string]$Decision.transaction_id).Trim().ToLowerInvariant()}
}
