$CustomAppProductionRecoveryPlanSchema = 1
$CustomAppProductionRecoveryPlanManagedBy = 'custom-app-production-recovery-plan-v1'
$CustomAppProductionRecoveryPlanQualifiedOrchestratorHead = '547a0ef8fb119f9a8a9d4ed5bbc1182bc3d9a12b'

function Get-CustomAppProductionRecoveryPlanSha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}
function Test-CustomAppProductionRecoveryPlanSha256V010 { param([AllowNull()][string]$Value) return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$') }

function Get-CustomAppProductionRecoveryPlanSpecV010 {
    param([Parameter(Mandatory=$true)][string]$Phase,[Parameter(Mandatory=$true)][string]$Classification)
    $p=$Phase.Trim();$c=$Classification.Trim()
    switch($c){
        'safe-abandon-or-restart-only-after-fresh-admission' {
            if($p -cne 'prepared'){throw 'recovery-plan phase/classification mismatch'}
            return [pscustomobject]@{verb='abandon-or-restart-after-fresh-admission';fresh=$true;recovery=$false;housekeeping=$false;no_action=$true;live=$true;txn=$false;stage=$true;app=$true;persist=$true;restore_app=$false;restore_persist=$false;recovery_apply=$false;cleanup=$false;new_permit=$true;manual=$false;spicetify_pin=$false}
        }
        'filesystem-recovery-inspection-required' {
            if($p -cne 'atomic-mutation-starting'){throw 'recovery-plan phase/classification mismatch'}
            return [pscustomobject]@{verb='inspect-filesystem-before-any-recovery';fresh=$true;recovery=$true;housekeeping=$false;no_action=$false;live=$true;txn=$true;stage=$true;app=$true;persist=$true;restore_app=$false;restore_persist=$false;recovery_apply=$false;cleanup=$false;new_permit=$false;manual=$true;spicetify_pin=$false}
        }
        'exact-app-and-persistence-recovery-required' {
            if($p -notin @('live-moved-to-old','candidate-live','transaction-finalized')){throw 'recovery-plan phase/classification mismatch'}
            $txn=($p -in @('live-moved-to-old','candidate-live'))
            return [pscustomobject]@{verb='restore-exact-app-and-persistence';fresh=$true;recovery=$true;housekeeping=$false;no_action=$false;live=$true;txn=$txn;stage=$true;app=$true;persist=$true;restore_app=$true;restore_persist=$true;recovery_apply=$false;cleanup=$false;new_permit=$true;manual=$false;spicetify_pin=$false}
        }
        'rollback-and-recovery-apply-required' {
            if($p -notin @('apply-starting','apply-returned-success-pending-verification','rollback-required')){throw 'recovery-plan phase/classification mismatch'}
            return [pscustomobject]@{verb='restore-exact-app-and-persistence-then-recovery-apply';fresh=$true;recovery=$true;housekeeping=$false;no_action=$false;live=$true;txn=$false;stage=$true;app=$true;persist=$true;restore_app=$true;restore_persist=$true;recovery_apply=$true;cleanup=$false;new_permit=$true;manual=$false;spicetify_pin=$true}
        }
        'fresh-revalidate-then-housekeeping-only' {
            if($p -cne 'apply-verified'){throw 'recovery-plan phase/classification mismatch'}
            return [pscustomobject]@{verb='fresh-revalidate-then-housekeeping';fresh=$true;recovery=$false;housekeeping=$true;no_action=$false;live=$true;txn=$false;stage=$true;app=$true;persist=$true;restore_app=$false;restore_persist=$false;recovery_apply=$false;cleanup=$true;new_permit=$false;manual=$false;spicetify_pin=$false}
        }
        'fresh-revalidate-then-idempotent-housekeeping-only' {
            if($p -cne 'cleanup-starting'){throw 'recovery-plan phase/classification mismatch'}
            return [pscustomobject]@{verb='fresh-revalidate-then-idempotent-housekeeping';fresh=$true;recovery=$false;housekeeping=$true;no_action=$false;live=$true;txn=$false;stage=$true;app=$true;persist=$true;restore_app=$false;restore_persist=$false;recovery_apply=$false;cleanup=$true;new_permit=$false;manual=$false;spicetify_pin=$false}
        }
        'no-action-new-permit-required-for-future-update' {
            if($p -cne 'committed-clean'){throw 'recovery-plan phase/classification mismatch'}
            return [pscustomobject]@{verb='no-action-new-permit-required';fresh=$false;recovery=$false;housekeeping=$false;no_action=$true;live=$true;txn=$false;stage=$false;app=$false;persist=$false;restore_app=$false;restore_persist=$false;recovery_apply=$false;cleanup=$false;new_permit=$true;manual=$false;spicetify_pin=$false}
        }
        'no-action-fresh-permit-required' {
            if($p -cne 'rollback-complete'){throw 'recovery-plan phase/classification mismatch'}
            return [pscustomobject]@{verb='no-action-fresh-permit-required';fresh=$true;recovery=$false;housekeeping=$false;no_action=$true;live=$true;txn=$false;stage=$false;app=$false;persist=$false;restore_app=$false;restore_persist=$false;recovery_apply=$false;cleanup=$false;new_permit=$true;manual=$false;spicetify_pin=$false}
        }
        'fail-closed' {
            return [pscustomobject]@{verb='manual-inspection-fail-closed';fresh=$true;recovery=$true;housekeeping=$false;no_action=$false;live=$false;txn=$false;stage=$false;app=$false;persist=$false;restore_app=$false;restore_persist=$false;recovery_apply=$false;cleanup=$false;new_permit=$true;manual=$true;spicetify_pin=$false}
        }
        default {throw 'recovery-plan classification unsupported'}
    }
}

function Get-CustomAppProductionRecoveryPlanMaterialV010 {
    param([Parameter(Mandatory=$true)]$Plan)
    return @(
        [string]$Plan.schema,[string]$Plan.managed_by,[string]$Plan.qualified_orchestrator_head,[string]$Plan.transaction_id,[string]$Plan.phase,[string]$Plan.classification,[string]$Plan.classification_reason,[string]$Plan.recovery_verb,
        [string]$Plan.requires_fresh_filesystem_revalidation,[string]$Plan.requires_recovery_executor,[string]$Plan.housekeeping_only,[string]$Plan.no_action,[string]$Plan.requires_live_path,[string]$Plan.requires_transaction_root,[string]$Plan.requires_stage_workspace,[string]$Plan.requires_app_backup,[string]$Plan.requires_persistence_backup,
        [string]$Plan.requires_exact_app_restore,[string]$Plan.requires_exact_persistence_restore,[string]$Plan.requires_recovery_apply,[string]$Plan.requires_idempotent_cleanup,[string]$Plan.requires_new_permit,[string]$Plan.requires_manual_inspection,[string]$Plan.requires_exact_spicetify_executable_pin,
        [string]$Plan.plan_is_authority,[string]$Plan.execution_authorized,[string]$Plan.restore_authorized,[string]$Plan.apply_authorized,[string]$Plan.cleanup_authorized,[string]$Plan.production_mutation_authorized
    ) -join "`n"
}

function New-CustomAppProductionRecoveryPlanFromClassificationV010 {
    param([Parameter(Mandatory=$true)]$Classification,[AllowNull()]$StoreRead,[AllowNull()][string]$ExpectedTransactionId=$null)
    $phase=$(if($null -ne $StoreRead -and $null -ne $StoreRead.entry){[string]$StoreRead.entry.phase}else{'unknown'})
    $tx=$(if($null -ne $StoreRead -and -not [string]::IsNullOrWhiteSpace([string]$StoreRead.transaction_id)){([string]$StoreRead.transaction_id).Trim().ToLowerInvariant()}elseif(-not [string]::IsNullOrWhiteSpace($ExpectedTransactionId)){$ExpectedTransactionId.Trim().ToLowerInvariant()}else{('0'*64)})
    if(-not (Test-CustomAppProductionRecoveryPlanSha256V010 $tx)){throw 'recovery-plan transaction id invalid'}
    $spec=Get-CustomAppProductionRecoveryPlanSpecV010 -Phase $phase -Classification ([string]$Classification.classification)
    $plan=[pscustomobject]@{
        schema=$CustomAppProductionRecoveryPlanSchema;managed_by=$CustomAppProductionRecoveryPlanManagedBy;qualified_orchestrator_head=$CustomAppProductionRecoveryPlanQualifiedOrchestratorHead
        transaction_id=$tx;phase=$phase;classification=[string]$Classification.classification;classification_reason=[string]$Classification.reason;recovery_verb=[string]$spec.verb
        requires_fresh_filesystem_revalidation=[bool]$spec.fresh;requires_recovery_executor=[bool]$spec.recovery;housekeeping_only=[bool]$spec.housekeeping;no_action=[bool]$spec.no_action
        requires_live_path=[bool]$spec.live;requires_transaction_root=[bool]$spec.txn;requires_stage_workspace=[bool]$spec.stage;requires_app_backup=[bool]$spec.app;requires_persistence_backup=[bool]$spec.persist
        requires_exact_app_restore=[bool]$spec.restore_app;requires_exact_persistence_restore=[bool]$spec.restore_persist;requires_recovery_apply=[bool]$spec.recovery_apply;requires_idempotent_cleanup=[bool]$spec.cleanup;requires_new_permit=[bool]$spec.new_permit;requires_manual_inspection=[bool]$spec.manual;requires_exact_spicetify_executable_pin=[bool]$spec.spicetify_pin
        plan_is_authority=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false;plan_fingerprint=$null
    }
    $plan.plan_fingerprint=Get-CustomAppProductionRecoveryPlanSha256V010 (Get-CustomAppProductionRecoveryPlanMaterialV010 $plan)
    return $plan
}

function Resolve-CustomAppProductionRecoveryPlanV010 {
    param([Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory,[Parameter(Mandatory=$true)][string]$ExpectedTransactionId)
    $read=$null;$classification=$null
    try{$read=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory;$classification=Resolve-CustomAppProductionCrashRecoveryClassificationV010 -StoreRead $read -ExpectedTransactionId $ExpectedTransactionId}
    catch{$classification=[pscustomobject]@{ok=$false;reason=('recovery-plan-journal-read-or-classification-failed:'+[string]$_.Exception.Message);classification='fail-closed';requires_fresh_filesystem_revalidation=$true;requires_recovery_executor=$true;housekeeping_only=$false;no_action=$false;journal_is_authority=$false;production_execution_authorized=$false;production_mutation_authorized=$false}}
    return New-CustomAppProductionRecoveryPlanFromClassificationV010 -Classification $classification -StoreRead $read -ExpectedTransactionId $ExpectedTransactionId
}

function Test-CustomAppProductionRecoveryPlanV010 {
    param([AllowNull()]$Plan)
    if($null -eq $Plan){return [pscustomobject]@{ok=$false;reason='recovery-plan-null'}}
    foreach($f in @('schema','managed_by','qualified_orchestrator_head','transaction_id','phase','classification','classification_reason','recovery_verb','requires_fresh_filesystem_revalidation','requires_recovery_executor','housekeeping_only','no_action','requires_live_path','requires_transaction_root','requires_stage_workspace','requires_app_backup','requires_persistence_backup','requires_exact_app_restore','requires_exact_persistence_restore','requires_recovery_apply','requires_idempotent_cleanup','requires_new_permit','requires_manual_inspection','requires_exact_spicetify_executable_pin','plan_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized','plan_fingerprint')){if(-not $Plan.PSObject.Properties[$f]){return [pscustomobject]@{ok=$false;reason=('recovery-plan-required-field-missing-'+$f)}}}
    if([int]$Plan.schema -ne $CustomAppProductionRecoveryPlanSchema -or [string]$Plan.managed_by -cne $CustomAppProductionRecoveryPlanManagedBy -or [string]$Plan.qualified_orchestrator_head -cne $CustomAppProductionRecoveryPlanQualifiedOrchestratorHead){return [pscustomobject]@{ok=$false;reason='recovery-plan-owner-schema-parent-mismatch'}}
    if(-not (Test-CustomAppProductionRecoveryPlanSha256V010 (([string]$Plan.transaction_id).Trim().ToLowerInvariant())) -or -not (Test-CustomAppProductionRecoveryPlanSha256V010 (([string]$Plan.plan_fingerprint).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason='recovery-plan-identity-or-fingerprint-invalid'}}
    foreach($f in @('plan_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){if([bool]$Plan.$f){return [pscustomobject]@{ok=$false;reason=('recovery-plan-authority-escaped-'+$f)}}}
    try{$spec=Get-CustomAppProductionRecoveryPlanSpecV010 -Phase ([string]$Plan.phase) -Classification ([string]$Plan.classification)}catch{return [pscustomobject]@{ok=$false;reason=('recovery-plan-mapping-invalid:'+[string]$_.Exception.Message)}}
    $pairs=@(
        @('recovery_verb',[string]$spec.verb),@('requires_fresh_filesystem_revalidation',[bool]$spec.fresh),@('requires_recovery_executor',[bool]$spec.recovery),@('housekeeping_only',[bool]$spec.housekeeping),@('no_action',[bool]$spec.no_action),
        @('requires_live_path',[bool]$spec.live),@('requires_transaction_root',[bool]$spec.txn),@('requires_stage_workspace',[bool]$spec.stage),@('requires_app_backup',[bool]$spec.app),@('requires_persistence_backup',[bool]$spec.persist),
        @('requires_exact_app_restore',[bool]$spec.restore_app),@('requires_exact_persistence_restore',[bool]$spec.restore_persist),@('requires_recovery_apply',[bool]$spec.recovery_apply),@('requires_idempotent_cleanup',[bool]$spec.cleanup),@('requires_new_permit',[bool]$spec.new_permit),@('requires_manual_inspection',[bool]$spec.manual),@('requires_exact_spicetify_executable_pin',[bool]$spec.spicetify_pin))
    foreach($p in $pairs){if($p[1] -is [bool]){if([bool]$Plan.($p[0]) -ne [bool]$p[1]){return [pscustomobject]@{ok=$false;reason=('recovery-plan-mapping-drift-'+$p[0])}}}elseif([string]$Plan.($p[0]) -cne [string]$p[1]){return [pscustomobject]@{ok=$false;reason=('recovery-plan-mapping-drift-'+$p[0])}}}
    $expected=Get-CustomAppProductionRecoveryPlanSha256V010 (Get-CustomAppProductionRecoveryPlanMaterialV010 $Plan)
    if(([string]$Plan.plan_fingerprint).Trim().ToLowerInvariant() -cne $expected){return [pscustomobject]@{ok=$false;reason='recovery-plan-fingerprint-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='recovery-plan-valid-zero-authority';transaction_id=([string]$Plan.transaction_id).Trim().ToLowerInvariant();phase=[string]$Plan.phase;classification=[string]$Plan.classification;recovery_verb=[string]$Plan.recovery_verb}
}
