$CustomAppProductionRecoveryExecutionAdmissionSchema = 1
$CustomAppProductionRecoveryExecutionAdmissionManagedBy = 'custom-app-production-recovery-execution-admission-v1'
$CustomAppProductionRecoveryExecutionAdmissionQualifiedPreflightHead = '4bfbf485838d8b056cd9daa15d949af7d9b86281'

function Get-CustomAppProductionRecoveryExecutionAdmissionSha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}
function Test-CustomAppProductionRecoveryExecutionAdmissionSha256V010 {param([AllowNull()][string]$Value)return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')}

function Get-CustomAppProductionRecoveryExecutorSpecV010 {
    param([Parameter(Mandatory=$true)][string]$Phase,[Parameter(Mandatory=$true)][string]$Classification)
    $planSpec=Get-CustomAppProductionRecoveryPlanSpecV010 -Phase $Phase -Classification $Classification
    if([bool]$planSpec.manual){return [pscustomobject]@{class='manual-inspection';eligible=$false;restore=$false;recovery_apply=$false;cleanup=$false;new_permit=[bool]$planSpec.new_permit}}
    if([bool]$planSpec.no_action){return [pscustomobject]@{class='no-action';eligible=$false;restore=$false;recovery_apply=$false;cleanup=$false;new_permit=[bool]$planSpec.new_permit}}
    if([bool]$planSpec.restore_app -or [bool]$planSpec.restore_persist){
        if(-not ([bool]$planSpec.restore_app -and [bool]$planSpec.restore_persist)){throw 'recovery executor partial restore mapping forbidden'}
        if([bool]$planSpec.recovery_apply){return [pscustomobject]@{class='exact-app-persistence-restore-and-recovery-apply';eligible=$true;restore=$true;recovery_apply=$true;cleanup=$false;new_permit=[bool]$planSpec.new_permit}}
        return [pscustomobject]@{class='exact-app-persistence-restore';eligible=$true;restore=$true;recovery_apply=$false;cleanup=$false;new_permit=[bool]$planSpec.new_permit}
    }
    if([bool]$planSpec.cleanup -or [bool]$planSpec.housekeeping){return [pscustomobject]@{class='idempotent-housekeeping';eligible=$true;restore=$false;recovery_apply=$false;cleanup=$true;new_permit=[bool]$planSpec.new_permit}}
    throw 'recovery executor mapping unsupported'
}

function Get-CustomAppProductionRecoveryExecutionAdmissionMaterialV010 {
    param([Parameter(Mandatory=$true)]$Decision)
    return @(
        [string]$Decision.schema,[string]$Decision.managed_by,[string]$Decision.qualified_preflight_head,[string]$Decision.transaction_id,[string]$Decision.phase,[string]$Decision.classification,[string]$Decision.recovery_verb,[string]$Decision.executor_class,
        [string]$Decision.plan_fingerprint,[string]$Decision.preflight_fingerprint,[string]$Decision.journal_revision,[string]$Decision.journal_entry_sha256,[string]$Decision.live_evidence_fingerprint,[string]$Decision.transaction_evidence_fingerprint,[string]$Decision.stage_evidence_fingerprint,[string]$Decision.app_backup_evidence_fingerprint,[string]$Decision.persistence_backup_evidence_fingerprint,[string]$Decision.spicetify_executable_sha256,
        [string]$Decision.recovery_action_eligible,[string]$Decision.requires_exact_restore,[string]$Decision.requires_recovery_apply,[string]$Decision.requires_idempotent_cleanup,[string]$Decision.requires_new_permit,[string]$Decision.requires_fresh_revalidation_by_executor,
        [string]$Decision.decided_at,[string]$Decision.eligible_until,[string]$Decision.admission_is_authority,[string]$Decision.execution_authorized,[string]$Decision.restore_authorized,[string]$Decision.apply_authorized,[string]$Decision.cleanup_authorized,[string]$Decision.production_mutation_authorized
    ) -join "`n"
}

function Resolve-CustomAppProductionRecoveryExecutionAdmissionV010 {
    param(
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory,[Parameter(Mandatory=$true)][string]$ExpectedTransactionId,
        [Parameter(Mandatory=$true)]$Plan,[Parameter(Mandatory=$true)]$PreflightReceipt,
        [AllowNull()][string]$SpicetifyAllowedRoot=$null,[AllowNull()][string]$SpicetifyPath=$null,[AllowNull()][string]$ExpectedSpicetifySha256=$null,
        [DateTimeOffset]$Now=[DateTimeOffset]::UtcNow
    )
    $deny={param([string]$Reason)[pscustomobject]@{ok=$false;reason=$Reason;admission_is_authority=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false}}
    $pc=Test-CustomAppProductionRecoveryPlanV010 $Plan;if(-not [bool]$pc.ok){return & $deny ('recovery-plan-invalid:'+[string]$pc.reason)}
    $rc=Test-CustomAppProductionRecoveryPreflightReceiptV010 $PreflightReceipt;if(-not [bool]$rc.ok){return & $deny ('recovery-preflight-receipt-invalid:'+[string]$rc.reason)}
    $tx=$ExpectedTransactionId.Trim().ToLowerInvariant();if(-not (Test-CustomAppProductionRecoveryExecutionAdmissionSha256V010 $tx)){return & $deny 'recovery-admission-transaction-id-invalid'}
    if(([string]$Plan.transaction_id).Trim().ToLowerInvariant() -cne $tx -or ([string]$PreflightReceipt.transaction_id).Trim().ToLowerInvariant() -cne $tx){return & $deny 'recovery-admission-transaction-continuity-mismatch'}
    foreach($f in @('phase','classification','recovery_verb')){if([string]$Plan.$f -cne [string]$PreflightReceipt.$f){return & $deny ('recovery-admission-plan-preflight-mismatch-'+$f)}}
    if(([string]$Plan.plan_fingerprint).Trim().ToLowerInvariant() -cne ([string]$PreflightReceipt.plan_fingerprint).Trim().ToLowerInvariant()){return & $deny 'recovery-admission-plan-fingerprint-continuity-mismatch'}

    $fresh=Resolve-CustomAppProductionRecoveryPreflightV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $tx -Plan $Plan -SpicetifyAllowedRoot $SpicetifyAllowedRoot -SpicetifyPath $SpicetifyPath -ExpectedSpicetifySha256 $ExpectedSpicetifySha256
    if($null -eq $fresh -or -not [bool]$fresh.ok){return & $deny ('recovery-admission-fresh-preflight-denied:'+[string]$fresh.reason)}
    $freshCheck=Test-CustomAppProductionRecoveryPreflightReceiptV010 $fresh.receipt;if(-not [bool]$freshCheck.ok){return & $deny ('recovery-admission-fresh-preflight-invalid:'+[string]$freshCheck.reason)}
    if(([string]$fresh.receipt.preflight_fingerprint).Trim().ToLowerInvariant() -cne ([string]$PreflightReceipt.preflight_fingerprint).Trim().ToLowerInvariant()){return & $deny 'recovery-admission-fresh-preflight-fingerprint-mismatch'}
    foreach($f in @('journal_revision','journal_entry_sha256','live_evidence_fingerprint','transaction_evidence_fingerprint','stage_evidence_fingerprint','app_backup_evidence_fingerprint','persistence_backup_evidence_fingerprint','spicetify_executable_sha256')){if([string]$fresh.receipt.$f -cne [string]$PreflightReceipt.$f){return & $deny ('recovery-admission-fresh-evidence-mismatch-'+$f)}}

    try{$spec=Get-CustomAppProductionRecoveryExecutorSpecV010 -Phase ([string]$Plan.phase) -Classification ([string]$Plan.classification)}catch{return & $deny ('recovery-admission-executor-mapping-denied:'+[string]$_.Exception.Message)}
    $decision=[pscustomobject]@{
        schema=$CustomAppProductionRecoveryExecutionAdmissionSchema;managed_by=$CustomAppProductionRecoveryExecutionAdmissionManagedBy;qualified_preflight_head=$CustomAppProductionRecoveryExecutionAdmissionQualifiedPreflightHead
        transaction_id=$tx;phase=[string]$Plan.phase;classification=[string]$Plan.classification;recovery_verb=[string]$Plan.recovery_verb;executor_class=[string]$spec.class
        plan_fingerprint=([string]$Plan.plan_fingerprint).Trim().ToLowerInvariant();preflight_fingerprint=([string]$fresh.receipt.preflight_fingerprint).Trim().ToLowerInvariant();journal_revision=[int64]$fresh.receipt.journal_revision;journal_entry_sha256=([string]$fresh.receipt.journal_entry_sha256).Trim().ToLowerInvariant()
        live_evidence_fingerprint=[string]$fresh.receipt.live_evidence_fingerprint;transaction_evidence_fingerprint=[string]$fresh.receipt.transaction_evidence_fingerprint;stage_evidence_fingerprint=[string]$fresh.receipt.stage_evidence_fingerprint;app_backup_evidence_fingerprint=[string]$fresh.receipt.app_backup_evidence_fingerprint;persistence_backup_evidence_fingerprint=[string]$fresh.receipt.persistence_backup_evidence_fingerprint;spicetify_executable_sha256=[string]$fresh.receipt.spicetify_executable_sha256
        recovery_action_eligible=[bool]$spec.eligible;requires_exact_restore=[bool]$spec.restore;requires_recovery_apply=[bool]$spec.recovery_apply;requires_idempotent_cleanup=[bool]$spec.cleanup;requires_new_permit=[bool]$spec.new_permit;requires_fresh_revalidation_by_executor=$true
        decided_at=$Now.ToUniversalTime().ToString('o');eligible_until=$Now.AddSeconds(15).ToUniversalTime().ToString('o')
        admission_is_authority=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false;admission_fingerprint=$null
    }
    $decision.admission_fingerprint=Get-CustomAppProductionRecoveryExecutionAdmissionSha256V010 (Get-CustomAppProductionRecoveryExecutionAdmissionMaterialV010 $decision)
    return [pscustomobject]@{ok=$true;reason='recovery-execution-admission-current-zero-authority';decision=$decision}
}

function Test-CustomAppProductionRecoveryExecutionAdmissionDecisionV010 {
    param([AllowNull()]$Decision,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow)
    if($null -eq $Decision){return [pscustomobject]@{ok=$false;reason='recovery-admission-decision-null'}}
    foreach($f in @('schema','managed_by','qualified_preflight_head','transaction_id','phase','classification','recovery_verb','executor_class','plan_fingerprint','preflight_fingerprint','journal_revision','journal_entry_sha256','live_evidence_fingerprint','transaction_evidence_fingerprint','stage_evidence_fingerprint','app_backup_evidence_fingerprint','persistence_backup_evidence_fingerprint','spicetify_executable_sha256','recovery_action_eligible','requires_exact_restore','requires_recovery_apply','requires_idempotent_cleanup','requires_new_permit','requires_fresh_revalidation_by_executor','decided_at','eligible_until','admission_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized','admission_fingerprint')){if(-not $Decision.PSObject.Properties[$f]){return [pscustomobject]@{ok=$false;reason=('recovery-admission-required-field-missing-'+$f)}}}
    if([int]$Decision.schema -ne 1 -or [string]$Decision.managed_by -cne $CustomAppProductionRecoveryExecutionAdmissionManagedBy -or [string]$Decision.qualified_preflight_head -cne $CustomAppProductionRecoveryExecutionAdmissionQualifiedPreflightHead){return [pscustomobject]@{ok=$false;reason='recovery-admission-owner-schema-parent-mismatch'}}
    foreach($f in @('transaction_id','plan_fingerprint','preflight_fingerprint','journal_entry_sha256','admission_fingerprint')){if(-not (Test-CustomAppProductionRecoveryExecutionAdmissionSha256V010 (([string]$Decision.$f).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('recovery-admission-invalid-'+$f)}}}
    foreach($f in @('admission_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){if([bool]$Decision.$f){return [pscustomobject]@{ok=$false;reason=('recovery-admission-authority-escaped-'+$f)}}}
    if(-not [bool]$Decision.requires_fresh_revalidation_by_executor){return [pscustomobject]@{ok=$false;reason='recovery-admission-fresh-revalidation-contract-missing'}}
    try{$spec=Get-CustomAppProductionRecoveryExecutorSpecV010 -Phase ([string]$Decision.phase) -Classification ([string]$Decision.classification)}catch{return [pscustomobject]@{ok=$false;reason=('recovery-admission-mapping-invalid:'+[string]$_.Exception.Message)}}
    if([string]$Decision.executor_class -cne [string]$spec.class -or [bool]$Decision.recovery_action_eligible -ne [bool]$spec.eligible -or [bool]$Decision.requires_exact_restore -ne [bool]$spec.restore -or [bool]$Decision.requires_recovery_apply -ne [bool]$spec.recovery_apply -or [bool]$Decision.requires_idempotent_cleanup -ne [bool]$spec.cleanup -or [bool]$Decision.requires_new_permit -ne [bool]$spec.new_permit){return [pscustomobject]@{ok=$false;reason='recovery-admission-semantic-mapping-drift'}}
    $start=[DateTimeOffset]::MinValue;$end=[DateTimeOffset]::MinValue;if(-not [DateTimeOffset]::TryParse([string]$Decision.decided_at,[ref]$start) -or -not [DateTimeOffset]::TryParse([string]$Decision.eligible_until,[ref]$end)){return [pscustomobject]@{ok=$false;reason='recovery-admission-time-invalid'}}
    if($end -le $start -or $end -gt $start.AddSeconds(15)){return [pscustomobject]@{ok=$false;reason='recovery-admission-window-invalid'}}
    if($Now -lt $start.AddSeconds(-5)){return [pscustomobject]@{ok=$false;reason='recovery-admission-not-yet-valid'}}
    if($Now -ge $end){return [pscustomobject]@{ok=$false;reason='recovery-admission-expired'}}
    $expected=Get-CustomAppProductionRecoveryExecutionAdmissionSha256V010 (Get-CustomAppProductionRecoveryExecutionAdmissionMaterialV010 $Decision)
    if(([string]$Decision.admission_fingerprint).Trim().ToLowerInvariant() -cne $expected){return [pscustomobject]@{ok=$false;reason='recovery-admission-fingerprint-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='recovery-execution-admission-valid-zero-authority';transaction_id=([string]$Decision.transaction_id).Trim().ToLowerInvariant();executor_class=[string]$Decision.executor_class;eligible=[bool]$Decision.recovery_action_eligible}
}
