# Validation-only proof that a byte-real pre-acquired archive and directory match
# the SAME current remote tree bound into the new-cycle HMAC permit and a fresh
# triple-ID start eligibility receipt. Not a stage, swap, apply or mutation grant.
$CustomAppByteRealHandoffSchema=1
$CustomAppByteRealHandoffManagedBy='custom-app-production-byte-real-prepared-stage-handoff-v1'
$CustomAppByteRealHandoffQualifiedNewPermitHead='67e39fd170079e4b1bce920466b5e46365af6050'
$CustomAppByteRealHandoffQualifiedStartBlob='23ddf1bb5a922791bb0f20fee07dc99d0de44629'
$CustomAppByteRealHandoffQualifiedStageBlob='e2f2fc656235883d2a82b106289973f6ded409a5'

function New-CustomAppByteRealHandoffDeniedV010 {
    param([Parameter(Mandatory=$true)][string]$Reason)
    return [pscustomobject]@{
        ok=$false;reason=$Reason;byte_real_stage_attested=$false;new_permit_bound=$false
        fresh_start_attested=$false;ready_for_fresh_post_stage_revalidation=$false
        ready_to_apply=$false;staging_only=$true;stage_authorized=$false
        executor_may_start=$false;executor_may_stage=$false;executor_may_apply=$false
        production_execution_authorized=$false;production_mutation_authorized=$false
    }
}

function Test-CustomAppByteRealHandoffShaV010 {
    param([AllowNull()][string]$Value)
    return ($null-ne$Value -and $Value -cmatch '^[a-f0-9]{64}$')
}

function Test-CustomAppProductionByteRealPreparedStageHandoffV010 {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$WorkspacePath,
        [Parameter(Mandatory=$true)][string]$ArchivePath,
        [Parameter(Mandatory=$true)][string]$ArchiveSha256,
        [Parameter(Mandatory=$true)][string]$StagePath,
        [Parameter(Mandatory=$true)]$ExtractedStageResult,
        [Parameter(Mandatory=$true)]$LifecycleRow,
        [Parameter(Mandatory=$true)]$BindingRow,
        [AllowNull()]$IssuerResult=$null,
        [AllowNull()]$ExecutorStartResult=$null,
        [AllowNull()][byte[]]$SessionKey=$null,
        [DateTimeOffset]$Now=[DateTimeOffset]::UtcNow
    )
    $deny={param([string]$Reason)New-CustomAppByteRealHandoffDeniedV010 -Reason $Reason}
    if([string]::IsNullOrWhiteSpace($Name)){return (& $deny 'byte-real-handoff-name-empty')}
    $key=$Name.Trim().ToLowerInvariant()
    if($null-eq$LifecycleRow-or$null-eq$BindingRow-or$null-eq$BindingRow.binding){
        return (& $deny 'byte-real-handoff-state-null')
    }
    if(-not[bool]$LifecycleRow.present-or[bool]$LifecycleRow.user_removed-or[bool]$LifecycleRow.ambiguous-or
       -not[bool]$BindingRow.active-or[bool]$BindingRow.user_removed-or[bool]$BindingRow.requires_reenrollment){
        return (& $deny 'byte-real-handoff-user-removed-inactive-or-ambiguous')
    }
    if(([string]$LifecycleRow.name).Trim().ToLowerInvariant()-cne$key-or
       ([string]$BindingRow.name).Trim().ToLowerInvariant()-cne$key){
        return (& $deny 'byte-real-handoff-name-mismatch')
    }
    foreach($state in @($BindingRow,$BindingRow.binding)){
        if([string]$state.mutation_mode-cne'deny'-or
           [bool]$state.auto_update_authorized-or[bool]$state.auto_install_authorized-or
           [bool]$state.production_mutation_authorized){
            return (& $deny 'byte-real-handoff-source-authority-escaped')
        }
    }
    $remote=([string]$BindingRow.last_remote_tree_sha256).Trim().ToLowerInvariant()
    $immutable=([string]$BindingRow.binding.last_verified_remote_tree_sha256).Trim().ToLowerInvariant()
    $manifest=([string]$BindingRow.binding.manifest_name).Trim()
    if(-not(Test-CustomAppByteRealHandoffShaV010 $remote)-or$immutable-cne$remote-or
       [string]::IsNullOrWhiteSpace($manifest)-or[bool]$BindingRow.binding.user_removed){
        return (& $deny 'byte-real-handoff-binding-invalid-or-drift')
    }
    if(-not(Test-CustomAppByteRealHandoffShaV010 $ArchiveSha256)){
        return (& $deny 'byte-real-handoff-archive-digest-invalid')
    }
    $surface=([string]$BindingRow.binding.surface_kind).Trim().ToLowerInvariant()
    if($surface -notin @('release-asset','repo-commit-root')){
        return (& $deny 'byte-real-handoff-binding-surface-invalid')
    }
    if($surface -ceq 'release-asset'){
        $assetDigest=([string]$BindingRow.binding.last_observed_asset_digest_sha256).Trim().ToLowerInvariant()
        if(-not(Test-CustomAppByteRealHandoffShaV010 $assetDigest)-or
           $assetDigest-cne$ArchiveSha256-or
           [string]$BindingRow.binding.release_asset_selector-cne'unique-zip-asset'){
            return (& $deny 'byte-real-handoff-frozen-remote-asset-digest-mismatch')
        }
        if([int64]$BindingRow.binding.last_observed_asset_id-le0){
            return (& $deny 'byte-real-handoff-frozen-remote-asset-id-invalid')
        }
    }
    if($null-eq$ExtractedStageResult-or$null-eq$ExtractedStageResult.baseline){
        return (& $deny 'byte-real-handoff-extraction-result-missing')
    }
    # Read-only path proofs: all candidate files must be confined to a dedicated,
    # non-reparse workspace under the stage-acquisition TEMP root. No live tree
    # or Spotify application path is ever an allowed stage destination.
    try {
        $root=Get-CustomAppStageWorkspaceRootV010
        $workspace=Assert-CustomAppStagePathV010 -Root $root -Path $WorkspacePath -Label 'prepared workspace'
        $zip=Assert-CustomAppStagePathV010 -Root $workspace -Path $ArchivePath -Label 'prepared archive'
        $stage=Assert-CustomAppStagePathV010 -Root $workspace -Path $StagePath -Label 'prepared stage'
    }catch{return (& $deny ('byte-real-handoff-workspace-path-denied:'+[string]$_.Exception.Message))}
    if(-not(Test-Path -LiteralPath $zip -PathType Leaf)-or
       -not(Test-Path -LiteralPath $stage -PathType Container)){
        return (& $deny 'byte-real-handoff-prepared-files-missing')
    }
    if(Test-Path -LiteralPath (Join-Path $stage '.git')){
        return (& $deny 'byte-real-handoff-stage-vcs-metadata-present')
    }
    try {
        $zipHash=(Get-FileHash -LiteralPath $zip -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
        $current=Get-CustomAppLocalRuntimeBaseline -Name $key -AppPath $stage
    }catch{return (& $deny ('byte-real-handoff-current-byte-read-denied:'+[string]$_.Exception.Message))}
    if($zipHash-cne$ArchiveSha256){
        return (& $deny 'byte-real-handoff-archive-bytes-drift')
    }
    if(-not[bool]$current.installable-or-not[bool]$current.safe-or
       ([string]$current.manifest_name).Trim()-cne$manifest){
        return (& $deny 'byte-real-handoff-stage-not-installable-or-manifest-drift')
    }
    $tree=([string]$current.tree_sha256).Trim().ToLowerInvariant()
    if($tree-cne$remote-or
       $tree-cne([string]$ExtractedStageResult.tree_sha256).Trim().ToLowerInvariant()-or
       $tree-cne([string]$ExtractedStageResult.baseline.tree_sha256).Trim().ToLowerInvariant()){
        return (& $deny 'byte-real-handoff-stage-tree-drift')
    }
    if([int]$current.file_count-ne[int]$ExtractedStageResult.baseline.file_count-or
       [int64]$current.total_bytes-ne[int64]$ExtractedStageResult.baseline.total_bytes){
        return (& $deny 'byte-real-handoff-stage-file-inventory-drift')
    }
    $afterPermit=($null-ne$IssuerResult-or$null-ne$ExecutorStartResult-or$null-ne$SessionKey)
    $issuerId=$null;$startId=$null
    if($afterPermit){
        if($null-eq$IssuerResult-or$null-eq$IssuerResult.receipt-or-not[bool]$IssuerResult.ok-or
           $null-eq$ExecutorStartResult-or$null-eq$ExecutorStartResult.receipt-or-not[bool]$ExecutorStartResult.ok-or
           $null-eq$SessionKey-or$SessionKey.Length-lt32){
            return (& $deny 'byte-real-handoff-incomplete-signed-approval')
        }
        $issuerCheck=Test-CustomAppProductionDualIdNewPermitIssuerReceiptV010 -Receipt $IssuerResult.receipt -SessionKey $SessionKey -Now $Now
        if(-not[bool]$issuerCheck.ok){return (& $deny ('byte-real-handoff-issuer-invalid:'+[string]$issuerCheck.reason))}
        $startCheck=Test-DualIdNewExecutorStartReceiptV010 -Receipt $ExecutorStartResult.receipt -Now $Now
        if(-not[bool]$startCheck.ok){return (& $deny ('byte-real-handoff-start-invalid:'+[string]$startCheck.reason))}
        if(-not[bool]$ExecutorStartResult.staging_eligible-or[bool]$ExecutorStartResult.executor_may_start-or
           [bool]$ExecutorStartResult.production_mutation_authorized){
            return (& $deny 'byte-real-handoff-start-result-authority-drift')
        }
        $ir=$IssuerResult.receipt;$sr=$ExecutorStartResult.receipt
        $source=([string]$BindingRow.source_identity).Trim().ToLowerInvariant()
        $bindingFingerprint=Get-CustomAppPromotionBindingFingerprintV010 -BindingRow $BindingRow
        if($source-cne([string]$BindingRow.binding.source_identity).Trim().ToLowerInvariant()-or
           $source-cne([string]$ir.source_identity).Trim().ToLowerInvariant()-or
           [int64]$BindingRow.binding.github_repo_id-ne[int64]$ir.github_repo_id-or
           $surface-cne([string]$ir.surface_kind).Trim().ToLowerInvariant()-or
           ([string]$BindingRow.last_remote_commit_sha).Trim().ToLowerInvariant()-cne([string]$ir.current_remote_commit_sha).Trim().ToLowerInvariant()-or
           ([string]$ir.current_remote_observed_at)-cne([string]$BindingRow.last_success)-or
           $bindingFingerprint-cne([string]$ir.current_binding_fingerprint).Trim().ToLowerInvariant()){
            return (& $deny 'byte-real-handoff-signed-source-remote-commit-or-binding-drift')
        }
        if(([string]$ir.name).Trim().ToLowerInvariant()-cne$key-or
           ([string]$ir.current_remote_tree_sha256).Trim().ToLowerInvariant()-cne$tree-or
           ([string]$sr.name).Trim().ToLowerInvariant()-cne$key-or
           ([string]$sr.issuer_fingerprint).Trim().ToLowerInvariant()-cne([string]$ir.issuer_fingerprint).Trim().ToLowerInvariant()){
            return (& $deny 'byte-real-handoff-signed-identity-or-tree-mismatch')
        }
        foreach($field in @('historical_permit_transaction_id','historical_journal_transaction_id','new_permit_transaction_id')){
            if(([string]$sr.$field).Trim().ToLowerInvariant()-cne([string]$ir.$field).Trim().ToLowerInvariant()){
                return (& $deny ('byte-real-handoff-transaction-id-mismatch-'+$field))
            }
        }
        $issuerId=[string]$ir.new_permit_transaction_id
        $startId=[string]$sr.consumption_id
    }
    return [pscustomobject]@{
        ok=$true;reason=$(if($afterPermit){'byte-real-stage-matches-fresh-signed-new-permit-staging-only'}else{'byte-real-stage-prepared-before-new-permit-zero-authority'})
        byte_real_stage_attested=$true;new_permit_bound=$afterPermit;fresh_start_attested=$afterPermit
        archive_sha256=$zipHash;stage_tree_sha256=$tree;stage_file_count=[int]$current.file_count
        stage_total_bytes=[int64]$current.total_bytes;new_permit_transaction_id=$issuerId
        consumption_id=$startId;ready_for_fresh_post_stage_revalidation=$afterPermit
        ready_to_apply=$false;staging_only=$true;stage_authorized=$false
        executor_may_start=$false;executor_may_stage=$false;executor_may_apply=$false
        production_execution_authorized=$false;production_mutation_authorized=$false
    }
}
