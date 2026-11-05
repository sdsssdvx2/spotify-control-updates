# Validation-only pre-permit byte-exact backup preparation. Does NOT grant
# permission to mutate the installed application or run Spicetify.
$CustomAppPrePermitBackupsBridgeSchema=1
$CustomAppPrePermitBackupsBridgeManagedBy='custom-app-production-pre-permit-backups-bridge-v1'
$CustomAppPrePermitBackupsBridgeQualifiedParent='02242daa6258fe552ac19e395612df000ddf779f'
$CustomAppPrePermitBackupsBridgeQualifiedPreApplyBlob='9b039819e7b2278fe4cf15c8585336dd07a8e8e3'

function New-CustomAppPrePermitBackupsBridgeDeniedV010 {
    param([Parameter(Mandatory=$true)][string]$Reason,[bool]$BackupsPrepared=$false)
    return [pscustomobject]@{
        ok=$false;reason=$Reason;receipt=$null;backups_prepared=$BackupsPrepared
        requires_cleanup_if_not_applied=$BackupsPrepared
        prepermit_backup_is_authority=$false;apply_authorized=$false
        production_execution_authorized=$false;production_mutation_authorized=$false
    }
}

function Get-CustomAppPrePermitBackupsBridgeReceiptMaterialV010 {
    param([Parameter(Mandatory=$true)]$Receipt)
    return @(
        [string]$Receipt.schema,[string]$Receipt.managed_by,[string]$Receipt.name
        [string]$Receipt.source_identity,[string]$Receipt.github_repo_id,[string]$Receipt.surface_kind
        [string]$Receipt.remote_tree_sha256,[string]$Receipt.remote_commit_sha
        [string]$Receipt.binding_fingerprint,[string]$Receipt.stage_path,[string]$Receipt.stage_workspace_path
        [string]$Receipt.live_path,[string]$Receipt.live_runtime_tree_sha256,[string]$Receipt.live_full_tree_sha256
        [string]$Receipt.app_backup_root,[string]$Receipt.app_backup_path,[string]$Receipt.app_backup_tree_sha256
        [string]$Receipt.app_backup_file_count,[string]$Receipt.app_backup_total_bytes
        [string]$Receipt.persistence_backup_root,[string]$Receipt.persistence_backup_path,[string]$Receipt.persistence_fingerprint
        [string]$Receipt.prepared_at,[string]$Receipt.prepermit_backup_is_authority
        [string]$Receipt.apply_authorized,[string]$Receipt.production_mutation_authorized
    )-join ([string][char]10)
}

function Test-CustomAppPrePermitBackupsBridgeReceiptV010 {
    param([AllowNull()]$Receipt)
    $deny={param([string]$reason)[pscustomobject]@{ok=$false;reason=$reason}}
    if($null-eq$Receipt){return (& $deny 'prepermit-receipt-null')}
    foreach($field in @(
        'schema','managed_by','name','source_identity','github_repo_id','surface_kind'
        'remote_tree_sha256','remote_commit_sha','binding_fingerprint','stage_path','stage_workspace_path'
        'live_path','live_runtime_tree_sha256','live_full_tree_sha256','app_backup_root','app_backup_path'
        'app_backup_tree_sha256','app_backup_file_count','app_backup_total_bytes'
        'persistence_backup_root','persistence_backup_path','persistence_fingerprint','prepared_at'
        'prepermit_backup_is_authority','apply_authorized','production_mutation_authorized','preparation_fingerprint'
    )){
        if(-not$Receipt.PSObject.Properties[$field]){return (& $deny ('prepermit-receipt-missing-'+$field))}
    }
    if([int]$Receipt.schema-ne$CustomAppPrePermitBackupsBridgeSchema-or
       [string]$Receipt.managed_by-cne$CustomAppPrePermitBackupsBridgeManagedBy){
        return (& $deny 'prepermit-receipt-schema-or-owner-drift')
    }
    foreach($field in @('remote_tree_sha256','binding_fingerprint','live_runtime_tree_sha256','live_full_tree_sha256','app_backup_tree_sha256','persistence_fingerprint','preparation_fingerprint')){
        if(-not(Test-CustomAppProductionPreApplySha256V010 -Value (([string]$Receipt.$field).Trim().ToLowerInvariant()))){
            return (& $deny ('prepermit-receipt-hash-invalid-'+$field))
        }
    }
    if(([string]$Receipt.remote_commit_sha).Trim().ToLowerInvariant()-notmatch'^[0-9a-f]{40}$'){
        return (& $deny 'prepermit-receipt-commit-invalid')
    }
    if([bool]$Receipt.prepermit_backup_is_authority-or[bool]$Receipt.apply_authorized-or
       [bool]$Receipt.production_mutation_authorized){return (& $deny 'prepermit-receipt-authority-escaped')}
    try{
        if([int64]$Receipt.github_repo_id-le0-or[int]$Receipt.app_backup_file_count-lt1-or
           [int64]$Receipt.app_backup_total_bytes-lt1){return (& $deny 'prepermit-receipt-inventory-invalid')}
        $when=[DateTimeOffset]::MinValue
        if(-not[DateTimeOffset]::TryParse([string]$Receipt.prepared_at,[ref]$when)){
            return (& $deny 'prepermit-receipt-time-invalid')
        }
    }catch{return (& $deny 'prepermit-receipt-inventory-or-time-invalid')}
    $expected=Get-CustomAppProductionPreApplySha256V010 -Text (Get-CustomAppPrePermitBackupsBridgeReceiptMaterialV010 -Receipt $Receipt)
    if($expected-cne([string]$Receipt.preparation_fingerprint).Trim().ToLowerInvariant()){
        return (& $deny 'prepermit-receipt-fingerprint-drift')
    }
    return [pscustomobject]@{ok=$true;reason='prepermit-backup-metadata-valid-zero-authority'}
}

# Validate output ancestors BEFORE any copy. The existing backup helper checks
# the destination directory itself, but a junction/symlink higher in the path
# could redirect backups into the user's live Spotify persistence surface.
function Test-CustomAppPrePermitBackupTargetAncestorsV010 {
    param([Parameter(Mandatory=$true)][string]$Path)
    try{
        $canonical=[IO.Path]::GetFullPath($Path)
        $probe=$canonical
        while(-not[string]::IsNullOrWhiteSpace($probe)){
            if(Test-Path -LiteralPath $probe){
                $item=Get-Item -LiteralPath $probe -Force -ErrorAction Stop
                if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne0){return $false}
                if(-not $item.PSIsContainer){return $false}
            }
            $parent=[IO.Directory]::GetParent($probe)
            if($null-eq$parent){break}
            if($probe.Equals($parent.FullName,[StringComparison]::OrdinalIgnoreCase)){break}
            $probe=$parent.FullName
        }
        return $true
    }catch{return $false}
}

function Invoke-CustomAppProductionPrePermitBackupPreparationV010 {
    param(
        [Parameter(Mandatory=$true)][string]$Name,[Parameter(Mandatory=$true)]$LifecycleRow,
        [Parameter(Mandatory=$true)]$BindingRow,[Parameter(Mandatory=$true)][string]$StagePath,
        [Parameter(Mandatory=$true)][string]$StageWorkspacePath,
        [Parameter(Mandatory=$true)][string]$RollbackBackupRoot,
        [Parameter(Mandatory=$true)][string]$PersistenceBackupRoot,
        [Parameter(Mandatory=$true)][string]$LocalAppDataRoot,
        [Parameter(Mandatory=$true)][string]$AppDataRoot,
        [DateTimeOffset]$Now=[DateTimeOffset]::UtcNow
    )
    $deny={param([string]$reason,[bool]$copied=$false)New-CustomAppPrePermitBackupsBridgeDeniedV010 -Reason $reason -BackupsPrepared:$copied}
    if([string]::IsNullOrWhiteSpace($Name)){return (& $deny 'prepermit-name-empty')}
    $nameKey=$Name.Trim().ToLowerInvariant()
    if(([string]$LifecycleRow.name).Trim().ToLowerInvariant()-cne$nameKey-or
       -not[bool]$LifecycleRow.present-or[bool]$LifecycleRow.user_removed-or
       [bool]$LifecycleRow.ambiguous-or-not[bool]$LifecycleRow.safe_local_identity){
        return (& $deny 'prepermit-unsafe-or-removed-lifecycle')
    }
    if([string]$LifecycleRow.mutation_mode-cne'deny'-or[bool]$LifecycleRow.auto_update_authorized-or
       [bool]$LifecycleRow.auto_install_authorized-or
       [bool]$BindingRow.auto_update_authorized-or[bool]$BindingRow.auto_install_authorized){
        return (& $deny 'prepermit-source-or-lifecycle-authority-escaped')
    }
    $locations=@($LifecycleRow.locations)
    if($locations.Count-ne1-or[string]::IsNullOrWhiteSpace([string]$locations[0])){
        return (& $deny 'prepermit-live-location-ambiguous')
    }
    $identity=Test-CustomAppStageBindingRowV010 -BindingRow $BindingRow -ExpectedName $Name
    if($null-eq$identity-or-not[bool]$identity.ok){
        return (& $deny ('prepermit-stage-binding-invalid:'+[string]$identity.reason))
    }
    $livePath=[string]$locations[0]
    try{
        $root=(Get-CustomAppStageWorkspaceRootV010)
        $workspace=Assert-CustomAppStagePathV010 -Root $root -Path $StageWorkspacePath -Label 'prepermit backup stage workspace'
        $stage=Assert-CustomAppStagePathV010 -Root $workspace -Path $StagePath -Label 'prepermit backup stage'
        if(-not([IO.Path]::GetDirectoryName($workspace)).Equals([IO.Path]::GetFullPath($root).TrimEnd([IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)-or
           ([IO.Path]::GetFileName($workspace))-notmatch'^[0-9a-fA-F]{32}$'-or
           -not([IO.Path]::GetFullPath($stage)).Equals((Join-Path $workspace 'stage'),[StringComparison]::OrdinalIgnoreCase)){
            return (& $deny 'prepermit-stage-workspace-layout-invalid')
        }
        $rollback=Get-CustomAppProductionPreApplyCanonicalPathV010 -Path $RollbackBackupRoot
        $persistence=Get-CustomAppProductionPreApplyCanonicalPathV010 -Path $PersistenceBackupRoot
        if(-not(Test-CustomAppPrePermitBackupTargetAncestorsV010 -Path $rollback)-or
           -not(Test-CustomAppPrePermitBackupTargetAncestorsV010 -Path $persistence)){
            return (& $deny 'prepermit-backup-reparse-ancestor-or-file-path')
        }
        # No backup destination may be nested under a protected Spotify
        # persistence surface. A caller must select separate durable roots.
        foreach($protected in @(
            (Join-Path $LocalAppDataRoot 'Spotify'),
            (Join-Path $AppDataRoot 'Spotify'),
            (Join-Path $AppDataRoot 'spicetify')
        )){
            if((Test-CustomAppProductionPreApplyPathsOverlapV010 -A $protected -B $rollback)-or
               (Test-CustomAppProductionPreApplyPathsOverlapV010 -A $protected -B $persistence)){
                return (& $deny 'prepermit-backup-target-overlaps-spotify-persistence')
            }
        }
        if((Test-CustomAppProductionPreApplyPathsOverlapV010 -A $livePath -B $rollback)-or
           (Test-CustomAppProductionPreApplyPathsOverlapV010 -A $livePath -B $persistence)-or
           (Test-CustomAppProductionPreApplyPathsOverlapV010 -A $workspace -B $rollback)-or
           (Test-CustomAppProductionPreApplyPathsOverlapV010 -A $workspace -B $persistence)-or
           (Test-CustomAppProductionPreApplyPathsOverlapV010 -A $rollback -B $persistence)){
            return (& $deny 'prepermit-backup-target-overlaps-protected-inputs')
        }
        $stageBefore=Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath $stage
        $liveBefore=Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath $livePath
        $fullBefore=Get-CustomAppUpdateTreeSnapshotV010 -Root $livePath
        $persistBefore=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot
    }catch{return (& $deny ('prepermit-input-read-or-path-denied:'+[string]$_.Exception.Message))}
    if(-not[bool]$stageBefore.safe-or-not[bool]$stageBefore.installable-or
       -not[bool]$liveBefore.safe-or-not[bool]$liveBefore.installable-or
       (Test-CustomAppLocalRuntimeBaselineMutationAuthority $stageBefore)-or
       (Test-CustomAppLocalRuntimeBaselineMutationAuthority $liveBefore)-or
       ([string]$liveBefore.tree_sha256).Trim().ToLowerInvariant()-cne([string]$BindingRow.last_local_tree_sha256).Trim().ToLowerInvariant()-or
       ([string]$stageBefore.tree_sha256).Trim().ToLowerInvariant()-cne([string]$identity.remote_tree_sha256).Trim().ToLowerInvariant()-or
       [string]$liveBefore.manifest_name-cne[string]$stageBefore.manifest_name-or
       [string]$stageBefore.manifest_name-cne[string]$BindingRow.binding.manifest_name){
        return (& $deny 'prepermit-stage-live-binding-byte-or-manifest-drift')
    }
    if(-not(Test-CustomAppProductionPreApplySha256V010 -Value ([string]$persistBefore.fingerprint))){
        return (& $deny 'prepermit-persistence-fingerprint-invalid')
    }
    $copied=$false
    try{
        $rroot=Assert-CustomAppProductionPreApplyBackupRootV010 -Path $rollback -Label 'prepermit-rollback-root'
        $proot=Assert-CustomAppProductionPreApplyBackupRootV010 -Path $persistence -Label 'prepermit-persistence-root'
        $app=New-CustomAppProductionAppRollbackBackupV010 -LivePath $livePath -BackupRoot $rroot
        $copied=$true
        $persistent=New-RequiredSpotifyPersistenceBackup -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -BackupRootOverride $proot
        if([string]$persistent.fingerprint-cne[string]$persistBefore.fingerprint){
            return (& $deny 'prepermit-persistence-copy-fingerprint-drift' $copied)
        }
        $persistCheck=Test-CustomAppProductionPersistenceBackupV010 -BackupPath ([string]$persistent.path) -ExpectedFingerprint ([string]$persistBefore.fingerprint)
        if(-not[bool]$persistCheck.ok){
            return (& $deny ('prepermit-persistence-backup-invalid:'+[string]$persistCheck.reason) $copied)
        }
        $fullAfter=Get-CustomAppUpdateTreeSnapshotV010 -Root $livePath
        $liveAfter=Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath $livePath
        $stageAfter=Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath $stage
        $persistAfter=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot
    }catch{return (& $deny ('prepermit-backup-or-post-copy-read-failed:'+[string]$_.Exception.Message) $copied)}
    if([string]$fullBefore.tree_sha256-cne[string]$fullAfter.tree_sha256-or
       [int]$fullBefore.file_count-ne[int]$fullAfter.file_count-or
       [int64]$fullBefore.total_bytes-ne[int64]$fullAfter.total_bytes-or
       [string]$app.tree_sha256-cne[string]$fullBefore.tree_sha256-or
       [int]$app.file_count-ne[int]$fullBefore.file_count-or
       [int64]$app.total_bytes-ne[int64]$fullBefore.total_bytes-or
       [string]$liveBefore.tree_sha256-cne[string]$liveAfter.tree_sha256-or
       [string]$stageBefore.tree_sha256-cne[string]$stageAfter.tree_sha256-or
       [string]$persistBefore.fingerprint-cne[string]$persistAfter.fingerprint){
        return (& $deny 'prepermit-copy-or-protected-state-drift' $copied)
    }
    $receipt=[pscustomobject]@{
        schema=$CustomAppPrePermitBackupsBridgeSchema;managed_by=$CustomAppPrePermitBackupsBridgeManagedBy
        name=$nameKey;source_identity=[string]$identity.source;github_repo_id=[int64]$identity.repo_id
        surface_kind=[string]$identity.surface;remote_tree_sha256=([string]$identity.remote_tree_sha256).Trim().ToLowerInvariant()
        remote_commit_sha=([string]$identity.commit_sha).Trim().ToLowerInvariant()
        binding_fingerprint=([string]$identity.binding_fingerprint).Trim().ToLowerInvariant()
        stage_path=$stage;stage_workspace_path=$workspace;live_path=$livePath
        live_runtime_tree_sha256=([string]$liveBefore.tree_sha256).Trim().ToLowerInvariant()
        live_full_tree_sha256=([string]$fullBefore.tree_sha256).Trim().ToLowerInvariant()
        app_backup_root=$rroot;app_backup_path=[string]$app.path
        app_backup_tree_sha256=([string]$app.tree_sha256).Trim().ToLowerInvariant()
        app_backup_file_count=[int]$app.file_count;app_backup_total_bytes=[int64]$app.total_bytes
        persistence_backup_root=$proot;persistence_backup_path=[string]$persistent.path
        persistence_fingerprint=([string]$persistBefore.fingerprint).Trim().ToLowerInvariant()
        prepared_at=$Now.ToUniversalTime().ToString('o')
        prepermit_backup_is_authority=$false;apply_authorized=$false
        production_mutation_authorized=$false;preparation_fingerprint=$null
    }
    $receipt.preparation_fingerprint=Get-CustomAppProductionPreApplySha256V010 -Text (Get-CustomAppPrePermitBackupsBridgeReceiptMaterialV010 -Receipt $receipt)
    $verified=Test-CustomAppPrePermitBackupsBridgeReceiptV010 -Receipt $receipt
    if(-not[bool]$verified.ok){return (& $deny ('prepermit-output-invalid:'+[string]$verified.reason) $copied)}
    return [pscustomobject]@{
        ok=$true;reason='prepermit-code-and-persistence-backups-byte-exact-ready-for-later-signed-handoff'
        receipt=$receipt;backups_prepared=$true;requires_cleanup_if_not_applied=$true
        prepermit_backup_is_authority=$false;apply_authorized=$false
        production_execution_authorized=$false;production_mutation_authorized=$false
    }
}


# This phase never creates backups: it only reads PRE-EXISTING backup copies
# and produces the same zero-authority prepared-result contract that the
# original pre-apply stage would have produced after re-copying.
function Invoke-CustomAppProductionPrePermitBackupsHandoffV010 {
    param(
        [Parameter(Mandatory=$true)]$PreparedBackupResult,
        [Parameter(Mandatory=$true)]$StageExecutorResult,
        [Parameter(Mandatory=$true)]$IssuerResult,
        [Parameter(Mandatory=$true)]$ExecutorStartResult,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)]$LifecycleRow,
        [Parameter(Mandatory=$true)]$ProvenanceRow,
        [Parameter(Mandatory=$true)]$BindingRow,
        [Parameter(Mandatory=$true)][string]$AllowedRoot,
        [Parameter(Mandatory=$true)][string]$ConsumptionStoreDirectory,
        [Parameter(Mandatory=$true)][string]$LocalAppDataRoot,
        [Parameter(Mandatory=$true)][string]$AppDataRoot,
        [Parameter(Mandatory=$true)][byte[]]$SessionKey,
        [AllowNull()]$ShadowProtocolQualification=$null,
        [AllowNull()]$LiveAttestedQualification=$null,
        [DateTimeOffset]$Now=[DateTimeOffset]::UtcNow,
        [Nullable[DateTimeOffset]]$PostCheckNow=$null,
        [int]$MaxRemoteObservationAgeHours=36
    )
    $deny={param([string]$reason)New-CustomAppPrePermitBackupsBridgeDeniedV010 -Reason $reason -BackupsPrepared:$true}
    if($null-eq$PreparedBackupResult-or-not[bool]$PreparedBackupResult.ok-or
       $null-eq$PreparedBackupResult.receipt-or$SessionKey.Length-lt32){
        return (& $deny 'prepermit-handoff-backups-or-key-invalid')
    }
    $p=$PreparedBackupResult.receipt
    $pc=Test-CustomAppPrePermitBackupsBridgeReceiptV010 -Receipt $p
    if(-not[bool]$pc.ok){return (& $deny ('prepermit-handoff-preparation-invalid:'+[string]$pc.reason))}
    if($null-eq$IssuerResult-or-not[bool]$IssuerResult.ok-or$null-eq$IssuerResult.receipt-or
       $null-eq$IssuerResult.permit-or$null-eq$ExecutorStartResult-or-not[bool]$ExecutorStartResult.ok-or
       $null-eq$ExecutorStartResult.receipt){
        return (& $deny 'prepermit-handoff-signed-issuer-or-start-missing')
    }
    $issuerProof=Test-CustomAppProductionDualIdNewPermitIssuerReceiptV010 -Receipt $IssuerResult.receipt -SessionKey $SessionKey -Now $Now
    if(-not[bool]$issuerProof.ok){return (& $deny ('prepermit-handoff-issuer-invalid:'+[string]$issuerProof.reason))}
    $startProof=Test-DualIdNewExecutorStartReceiptV010 -Receipt $ExecutorStartResult.receipt -Now $Now
    if(-not[bool]$startProof.ok){return (& $deny ('prepermit-handoff-start-invalid:'+[string]$startProof.reason))}
    if(-not[bool]$ExecutorStartResult.staging_eligible-or[bool]$ExecutorStartResult.production_mutation_authorized){
        return (& $deny 'prepermit-handoff-start-not-eligible-or-unsafe')
    }
    $preparedAt=[DateTimeOffset]::MinValue;$issuedAt=[DateTimeOffset]::MinValue
    if(-not[DateTimeOffset]::TryParse([string]$p.prepared_at,[ref]$preparedAt)-or
       -not[DateTimeOffset]::TryParse([string]$IssuerResult.receipt.permit_issued_at,[ref]$issuedAt)-or
       $preparedAt-gt$issuedAt){
        return (& $deny 'prepermit-handoff-backup-not-proven-before-permit')
    }
    $nameKey=$Name.Trim().ToLowerInvariant()
    $source=([string]$BindingRow.source_identity).Trim().ToLowerInvariant()
    if(([string]$p.name).Trim().ToLowerInvariant()-cne$nameKey-or
       $source-cne([string]$p.source_identity).Trim().ToLowerInvariant()-or
       $source-cne([string]$IssuerResult.receipt.source_identity).Trim().ToLowerInvariant()-or
       ([string]$p.binding_fingerprint).Trim().ToLowerInvariant()-cne([string]$IssuerResult.receipt.current_binding_fingerprint).Trim().ToLowerInvariant()-or
       ([string]$p.remote_tree_sha256).Trim().ToLowerInvariant()-cne([string]$IssuerResult.receipt.current_remote_tree_sha256).Trim().ToLowerInvariant()-or
       ([string]$p.remote_commit_sha).Trim().ToLowerInvariant()-cne([string]$IssuerResult.receipt.current_remote_commit_sha).Trim().ToLowerInvariant()){
        return (& $deny 'prepermit-handoff-signed-source-or-binding-drift')
    }
    $startReceipt=$ExecutorStartResult.receipt
    foreach($f in @('historical_permit_transaction_id','historical_journal_transaction_id','new_permit_transaction_id')){
        if(([string]$IssuerResult.receipt.$f).Trim().ToLowerInvariant()-cne([string]$startReceipt.$f).Trim().ToLowerInvariant()){
            return (& $deny ('prepermit-handoff-id-mismatch-'+$f))
        }
    }
    $consumption=([string]$startReceipt.consumption_id).Trim().ToLowerInvariant()
    if($consumption-notmatch'^[0-9a-f]{64}$'-or
       ([string]$StageExecutorResult.consumption_id).Trim().ToLowerInvariant()-cne$consumption){
        return (& $deny 'prepermit-handoff-stage-consumption-id-drift')
    }
    $stageCheck=Test-CustomAppProductionStageExecutorResultV010 -Result $StageExecutorResult
    if(-not[bool]$stageCheck.ok){return (& $deny ('prepermit-handoff-stage-receipt-invalid:'+[string]$stageCheck.reason))}
    $permit=$IssuerResult.permit
    if(([string]$StageExecutorResult.stage_path)-cne([string]$p.stage_path)-or
       ([string]$StageExecutorResult.workspace_path)-cne([string]$p.stage_workspace_path)-or
       ([string]$StageExecutorResult.binding_fingerprint).Trim().ToLowerInvariant()-cne([string]$p.binding_fingerprint).Trim().ToLowerInvariant()-or
       ([string]$StageExecutorResult.remote_tree_sha256).Trim().ToLowerInvariant()-cne([string]$p.remote_tree_sha256).Trim().ToLowerInvariant()-or
       ([string]$StageExecutorResult.local_tree_sha256).Trim().ToLowerInvariant()-cne([string]$p.live_runtime_tree_sha256).Trim().ToLowerInvariant()){
        return (& $deny 'prepermit-handoff-prepared-stage-or-local-drift')
    }
    $identity=Test-CustomAppStageBindingRowV010 -BindingRow $BindingRow -ExpectedName $Name
    if(-not[bool]$identity.ok-or
       ([string]$identity.binding_fingerprint).Trim().ToLowerInvariant()-cne([string]$p.binding_fingerprint).Trim().ToLowerInvariant()){
        return (& $deny ('prepermit-handoff-binding-invalid:'+[string]$identity.reason))
    }
    $live=Test-CustomAppProductionStageExecutorLiveBaselineV010 -LifecycleRow $LifecycleRow -Permit $permit -BindingRow $BindingRow -Name $Name
    if(-not[bool]$live.ok){return (& $deny ('prepermit-handoff-current-live-invalid:'+[string]$live.reason))}
    $admissionArgs=@{
        AllowedRoot=$AllowedRoot;StoreDirectory=$ConsumptionStoreDirectory
        ExpectedConsumptionId=$consumption;Permit=$permit;Name=$Name
        LifecycleRow=$LifecycleRow;ProvenanceRow=$ProvenanceRow;BindingRow=$BindingRow
        CurrentBaseline=$live.baseline;ShadowProtocolQualification=$ShadowProtocolQualification
        LiveAttestedQualification=$LiveAttestedQualification;SessionKey=$SessionKey
        Now=$Now;MaxRemoteObservationAgeHours=$MaxRemoteObservationAgeHours
    }
    $admission=Resolve-CustomAppProductionStageAdmissionV010 @admissionArgs
    if($null-eq$admission-or-not[bool]$admission.ok){
        return (& $deny ('prepermit-handoff-stage-admission-denied:'+[string]$admission.reason))
    }
    $stageDecision=$admission.decision
    if(([string]$stageDecision.remote_tree_sha256).Trim().ToLowerInvariant()-cne([string]$p.remote_tree_sha256).Trim().ToLowerInvariant()-or
       ([string]$stageDecision.binding_fingerprint).Trim().ToLowerInvariant()-cne([string]$p.binding_fingerprint).Trim().ToLowerInvariant()){
        return (& $deny 'prepermit-handoff-fresh-stage-admission-drift')
    }
    try{
        $fullLive=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$p.live_path)
        $backupApp=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$p.app_backup_path)
        $freshStage=Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath ([string]$p.stage_path)
        $persistLive=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot
        $persistBackup=Test-CustomAppProductionPersistenceBackupV010 -BackupPath ([string]$p.persistence_backup_path) -ExpectedFingerprint ([string]$p.persistence_fingerprint)
    }catch{return (& $deny ('prepermit-handoff-backup-or-live-read-denied:'+[string]$_.Exception.Message))}
    if([string]$fullLive.tree_sha256-cne[string]$p.live_full_tree_sha256-or
       [string]$backupApp.tree_sha256-cne[string]$p.app_backup_tree_sha256-or
       [int]$backupApp.file_count-ne[int]$p.app_backup_file_count-or
       [int64]$backupApp.total_bytes-ne[int64]$p.app_backup_total_bytes-or
       [string]$freshStage.tree_sha256-cne[string]$p.remote_tree_sha256-or
       [string]$persistLive.fingerprint-cne[string]$p.persistence_fingerprint-or
       -not[bool]$persistBackup.ok){
        return (& $deny 'prepermit-handoff-live-stage-or-backup-byte-drift')
    }
    $after=$(if($null-ne$PostCheckNow){[DateTimeOffset]$PostCheckNow}else{[DateTimeOffset]::UtcNow})
    if($after-lt$Now-or$after-gt$Now.AddSeconds(5)){
        return (& $deny 'prepermit-handoff-final-clock-window-expired')
    }
    $admissionArgs.Now=$after
    $final=Resolve-CustomAppProductionStageAdmissionV010 @admissionArgs
    if($null-eq$final-or-not[bool]$final.ok){
        return (& $deny ('prepermit-handoff-final-stage-admission-denied:'+[string]$final.reason))
    }
    foreach($field in @('consumption_id','name','source_identity','github_repo_id','surface_kind','remote_tree_sha256','remote_commit_sha','binding_fingerprint','persistence_envelope_sha256')){
        if(([string]$final.decision.$field).Trim().ToLowerInvariant()-cne([string]$stageDecision.$field).Trim().ToLowerInvariant()){
            return (& $deny ('prepermit-handoff-post-admission-drift-'+$field))
        }
    }
    $result=[pscustomobject]@{
        schema=$CustomAppProductionPreApplyPreparationSchema
        managed_by=$CustomAppProductionPreApplyPreparationManagedBy
        qualified_stage_executor_head=$CustomAppProductionPreApplyPreparationQualifiedStageHead
        qualified_admission_head=$CustomAppProductionPreApplyPreparationQualifiedAdmissionHead
        qualified_persistence_head=$CustomAppProductionPreApplyPreparationQualifiedPersistenceHead
        qualified_transaction_head=$CustomAppProductionPreApplyPreparationQualifiedTransactionHead
        status='pre-apply-backups-prepared-verified';name=$nameKey
        source_identity=([string]$stageDecision.source_identity).Trim().ToLowerInvariant()
        github_repo_id=[int64]$stageDecision.github_repo_id;surface_kind=[string]$stageDecision.surface_kind
        remote_commit_sha=([string]$stageDecision.remote_commit_sha).Trim().ToLowerInvariant()
        consumption_id=$consumption
        stage_result_fingerprint=([string]$StageExecutorResult.result_fingerprint).Trim().ToLowerInvariant()
        pre_apply_admission_fingerprint=([string]$final.decision.admission_fingerprint).Trim().ToLowerInvariant()
        persistence_envelope_sha256=([string]$final.decision.persistence_envelope_sha256).Trim().ToLowerInvariant()
        live_tree_sha256=([string]$live.tree_sha256).Trim().ToLowerInvariant()
        stage_tree_sha256=([string]$freshStage.tree_sha256).Trim().ToLowerInvariant()
        binding_fingerprint=([string]$p.binding_fingerprint).Trim().ToLowerInvariant()
        stage_path=[string]$p.stage_path;stage_workspace_path=[string]$p.stage_workspace_path
        app_backup_root=[string]$p.app_backup_root;app_backup_path=[string]$p.app_backup_path
        app_backup_tree_sha256=([string]$p.app_backup_tree_sha256).Trim().ToLowerInvariant()
        app_backup_file_count=[int]$p.app_backup_file_count;app_backup_total_bytes=[int64]$p.app_backup_total_bytes
        persistence_backup_root=[string]$p.persistence_backup_root
        persistence_backup_path=[string]$p.persistence_backup_path
        persistence_fingerprint=([string]$p.persistence_fingerprint).Trim().ToLowerInvariant()
        prepared_at=$after.ToUniversalTime().ToString('o');preparation_fingerprint=$null
        preparation_is_authority=$false;backups_are_authority=$false
        requires_atomic_apply_rollback_executor=$true
        requires_fresh_revalidation_before_apply=$true;requires_cleanup_if_not_applied=$true
        apply_authorized=$false;live_destination_authorized=$false
        production_execution_authorized=$false;production_mutation_authorized=$false
    }
    $result.preparation_fingerprint=Get-CustomAppProductionPreApplySha256V010 -Text (Get-CustomAppProductionPreApplyResultMaterialV010 -Result $result)
    $generic=Test-CustomAppProductionPreApplyPreparedResultV010 -Result $result
    if(-not[bool]$generic.ok){return (& $deny ('prepermit-handoff-standard-preapply-invalid:'+[string]$generic.reason))}
    return [pscustomobject]@{
        ok=$true;reason='preissued-byte-exact-backups-reused-in-standard-preapply-contract'
        result=$result;backups_prepared=$true;prepermit_backup_verified_again=$true
        requires_cleanup_if_not_applied=$true
        prepermit_backup_is_authority=$false;preparation_is_authority=$false
        apply_authorized=$false;live_destination_authorized=$false
        production_execution_authorized=$false;production_mutation_authorized=$false
    }
}
