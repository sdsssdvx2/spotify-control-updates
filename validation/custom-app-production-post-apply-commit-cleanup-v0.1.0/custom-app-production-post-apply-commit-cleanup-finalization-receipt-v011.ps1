$CustomAppProductionPostApplyCommitCleanupFinalizationReceiptSchema = 1

function Test-CustomAppProductionTransactionFinalizationResultV010 {
    param([AllowNull()]$Result)
    if($null -eq $Result){ return [pscustomobject]@{ok=$false;reason='finalization-result-null'} }
    $required=@('schema','managed_by','qualified_atomic_head','status','name','live_path','transaction_root','consumption_id','stage_result_fingerprint','preparation_fingerprint','atomic_fresh_admission_fingerprint','old_live_tree_sha256','live_runtime_tree_sha256','persistence_fingerprint','finalized_at','stage_workspace_path','app_backup_path','persistence_backup_path','transaction_workspace_deleted','stage_workspace_preserved','app_backup_preserved','persistence_backup_preserved','requires_spicetify_apply_phase','result_is_authority','spicetify_apply_authorized','additional_mutation_authorized','production_mutation_authorized','finalization_fingerprint')
    foreach($field in $required){ if(-not $Result.PSObject.Properties[$field]){ return [pscustomobject]@{ok=$false;reason=('finalization-result-required-field-missing-'+$field)} } }
    if([int]$Result.schema -ne $CustomAppProductionTransactionFinalizationSchema -or [string]$Result.managed_by -cne $CustomAppProductionTransactionFinalizationManagedBy -or [string]$Result.qualified_atomic_head -cne $CustomAppProductionTransactionFinalizationQualifiedAtomicHead -or [string]$Result.status -cne 'transaction-workspace-finalized-live-and-persistence-reverified'){ return [pscustomobject]@{ok=$false;reason='finalization-result-owner-schema-parent-or-status-invalid'} }
    if(-not [bool]$Result.transaction_workspace_deleted -or -not [bool]$Result.stage_workspace_preserved -or -not [bool]$Result.app_backup_preserved -or -not [bool]$Result.persistence_backup_preserved -or -not [bool]$Result.requires_spicetify_apply_phase){ return [pscustomobject]@{ok=$false;reason='finalization-result-preservation-contract-invalid'} }
    foreach($field in @('result_is_authority','spicetify_apply_authorized','additional_mutation_authorized','production_mutation_authorized')){ if([bool]$Result.$field){ return [pscustomobject]@{ok=$false;reason=('finalization-result-'+$field+'-true')} } }
    foreach($field in @('consumption_id','stage_result_fingerprint','preparation_fingerprint','atomic_fresh_admission_fingerprint','old_live_tree_sha256','live_runtime_tree_sha256','persistence_fingerprint','finalization_fingerprint')){ if(-not (Test-CustomAppProductionTransactionFinalizationSha256V010 -Value (([string]$Result.$field).Trim().ToLowerInvariant()))){ return [pscustomobject]@{ok=$false;reason=('finalization-result-invalid-'+$field)} } }
    if($Result.PSObject.Properties['preserved_git_tree_sha256'] -and -not [string]::IsNullOrWhiteSpace([string]$Result.preserved_git_tree_sha256) -and -not (Test-CustomAppProductionTransactionFinalizationSha256V010 -Value (([string]$Result.preserved_git_tree_sha256).Trim().ToLowerInvariant()))){ return [pscustomobject]@{ok=$false;reason='finalization-result-invalid-preserved-git-tree'} }
    try {
        $transactionRoot=Get-CustomAppProductionPostApplyCommitCleanupCanonicalPathV010 -Path ([string]$Result.transaction_root)
        $livePath=Get-CustomAppProductionPostApplyCommitCleanupCanonicalPathV010 -Path ([string]$Result.live_path)
        if(Test-Path -LiteralPath $transactionRoot){ return [pscustomobject]@{ok=$false;reason='finalization-result-transaction-root-still-exists'} }
        if(-not (Test-Path -LiteralPath $livePath -PathType Container)){ return [pscustomobject]@{ok=$false;reason='finalization-result-live-path-missing'} }
        foreach($field in @('stage_workspace_path','app_backup_path','persistence_backup_path')){
            $p=Get-CustomAppProductionPostApplyCommitCleanupCanonicalPathV010 -Path ([string]$Result.$field)
            if([string]::IsNullOrWhiteSpace($p)){ return [pscustomobject]@{ok=$false;reason=('finalization-result-preserved-path-invalid-'+$field)} }
        }
    } catch { return [pscustomobject]@{ok=$false;reason=('finalization-result-path-shape-check-failed:'+[string]$_.Exception.Message)} }
    $expected=Get-CustomAppProductionTransactionFinalizationSha256V010 -Text (Get-CustomAppProductionTransactionFinalizationResultMaterialV010 -Result $Result)
    if(([string]$Result.finalization_fingerprint).Trim().ToLowerInvariant() -cne $expected){ return [pscustomobject]@{ok=$false;reason='finalization-result-fingerprint-mismatch'} }
    return [pscustomobject]@{ok=$true;reason='finalization-receipt-integrity-valid-without-preserved-artifact-presence';fingerprint=$expected}
}
