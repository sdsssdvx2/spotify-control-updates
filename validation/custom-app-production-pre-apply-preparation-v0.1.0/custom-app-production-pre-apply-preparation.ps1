$CustomAppProductionPreApplyPreparationSchema = 1
$CustomAppProductionPreApplyPreparationManagedBy = 'custom-app-production-pre-apply-preparation-v1'
$CustomAppProductionPreApplyPreparationQualifiedStageHead = '6ba560e7980c3492fb032ebc720f029caa97b15c'
$CustomAppProductionPreApplyPreparationQualifiedAdmissionHead = '13f4314b81816b1b1c3bb3c2fb4280b6c015f8de'
$CustomAppProductionPreApplyPreparationQualifiedPersistenceHead = '57be1dcd10e339e9da2b8f15b9910a2ae1b79c1b'
$CustomAppProductionPreApplyPreparationQualifiedTransactionHead = '1a2461a6929e9cabd50d27f95e0744f83443b9e8'

function Get-CustomAppProductionPreApplySha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}

function Test-CustomAppProductionPreApplySha256V010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}

function Get-CustomAppProductionPreApplyCanonicalPathV010 {
    param([Parameter(Mandatory=$true)][string]$Path)
    if([string]::IsNullOrWhiteSpace($Path)){throw 'Pre-apply path cannot be empty.'}
    return [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
}

function Test-CustomAppProductionPreApplyPathWithinRootV010 {
    param([Parameter(Mandatory=$true)][string]$Root,[Parameter(Mandatory=$true)][string]$Path)
    $r=Get-CustomAppProductionPreApplyCanonicalPathV010 $Root;$p=Get-CustomAppProductionPreApplyCanonicalPathV010 $Path
    if($p.Equals($r,[StringComparison]::OrdinalIgnoreCase)){return $false}
    return $p.StartsWith($r+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)
}

function Test-CustomAppProductionPreApplyPathsOverlapV010 {
    param([Parameter(Mandatory=$true)][string]$A,[Parameter(Mandatory=$true)][string]$B)
    $a=Get-CustomAppProductionPreApplyCanonicalPathV010 $A;$b=Get-CustomAppProductionPreApplyCanonicalPathV010 $B
    if($a.Equals($b,[StringComparison]::OrdinalIgnoreCase)){return $true}
    return ($a.StartsWith($b+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or $b.StartsWith($a+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase))
}

function Assert-CustomAppProductionPreApplyBackupRootV010 {
    param([Parameter(Mandatory=$true)][string]$Path,[string]$Label='backup root')
    $p=Get-CustomAppProductionPreApplyCanonicalPathV010 $Path
    if(-not (Test-Path -LiteralPath $p -PathType Container)){[IO.Directory]::CreateDirectory($p)|Out-Null}
    $i=Get-Item -LiteralPath $p -Force -ErrorAction Stop
    if(($i.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw "$Label is a reparse point."}
    return $p
}

function New-CustomAppProductionAppRollbackBackupV010 {
    param([Parameter(Mandatory=$true)][string]$LivePath,[Parameter(Mandatory=$true)][string]$BackupRoot)
    $live=Get-CustomAppProductionPreApplyCanonicalPathV010 $LivePath
    if(-not (Test-Path -LiteralPath $live -PathType Container)){throw 'Live Custom App path is missing.'}
    $root=Assert-CustomAppProductionPreApplyBackupRootV010 -Path $BackupRoot -Label 'app rollback backup root'
    if(Test-CustomAppProductionPreApplyPathsOverlapV010 -A $live -B $root){throw 'App rollback backup root overlaps live Custom App path.'}
    $before=Get-CustomAppUpdateTreeSnapshotV010 -Root $live
    $container=Join-Path $root ([Guid]::NewGuid().ToString('N'));$dest=Join-Path $container 'app-code'
    [IO.Directory]::CreateDirectory($dest)|Out-Null
    foreach($entry in @($before.entries)){
        $rel=([string]$entry.path).Replace('/',[IO.Path]::DirectorySeparatorChar);$target=Join-Path $dest $rel
        if([string]$entry.type -ceq 'dir'){[IO.Directory]::CreateDirectory($target)|Out-Null;continue}
        $parent=[IO.Path]::GetDirectoryName($target);if(-not [string]::IsNullOrWhiteSpace($parent)){[IO.Directory]::CreateDirectory($parent)|Out-Null}
        [IO.File]::Copy((Join-Path $live $rel),$target,$false)
    }
    $after=Get-CustomAppUpdateTreeSnapshotV010 -Root $dest
    if([string]$after.tree_sha256 -cne [string]$before.tree_sha256 -or [int]$after.file_count -ne [int]$before.file_count -or [int64]$after.total_bytes -ne [int64]$before.total_bytes){throw 'App rollback backup verification failed.'}
    return [pscustomobject]@{schema=1;path=$dest;container_path=$container;source_path=$live;tree_sha256=[string]$before.tree_sha256;file_count=[int]$before.file_count;total_bytes=[int64]$before.total_bytes}
}

function Test-CustomAppProductionPersistenceBackupV010 {
    param([Parameter(Mandatory=$true)][string]$BackupPath,[Parameter(Mandatory=$true)][string]$ExpectedFingerprint)
    if(-not (Test-CustomAppProductionPreApplySha256V010 $ExpectedFingerprint)){return [pscustomobject]@{ok=$false;reason='persistence-expected-fingerprint-invalid'}}
    if(-not (Test-Path -LiteralPath $BackupPath -PathType Container)){return [pscustomobject]@{ok=$false;reason='persistence-backup-missing'}}
    $manifestPath=Join-Path $BackupPath 'guard-manifest.json'
    if(-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)){return [pscustomobject]@{ok=$false;reason='persistence-backup-manifest-missing'}}
    try{$m=Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop|ConvertFrom-Json}catch{return [pscustomobject]@{ok=$false;reason=('persistence-backup-manifest-read-failed:'+[string]$_.Exception.Message)}}
    if([int]$m.schema -ne 1 -or $null -eq $m.before -or [string]$m.before.fingerprint -cne $ExpectedFingerprint){return [pscustomobject]@{ok=$false;reason='persistence-backup-manifest-fingerprint-mismatch'}}
    foreach($surface in @($m.before.surfaces)){
        $target=Join-Path (Join-Path $BackupPath 'surfaces') ([string]$surface.id)
        if(-not [bool]$surface.exists){if(Test-Path -LiteralPath $target){return [pscustomobject]@{ok=$false;reason=('persistence-absent-surface-materialized-'+[string]$surface.id)}};continue}
        if([string]$surface.kind -notin @('Directory','File')){return [pscustomobject]@{ok=$false;reason=('persistence-surface-kind-invalid-'+[string]$surface.id)}}
        try{$fp=Get-PathContentFingerprint -Path $target -Kind ([string]$surface.kind)}catch{return [pscustomobject]@{ok=$false;reason=('persistence-backup-surface-read-failed-'+[string]$surface.id+':' + [string]$_.Exception.Message)}}
        if(-not [bool]$fp.exists -or [string]$fp.fingerprint -cne [string]$surface.fingerprint){return [pscustomobject]@{ok=$false;reason=('persistence-backup-surface-mismatch-'+[string]$surface.id)}}
    }
    return [pscustomobject]@{ok=$true;reason='persistence-backup-byte-verified';fingerprint=$ExpectedFingerprint;manifest=$m}
}

function Get-CustomAppProductionPreApplyResultMaterialV010 {
    param([Parameter(Mandatory=$true)]$Result)
    return @(
        [string]$Result.schema,[string]$Result.managed_by,[string]$Result.qualified_stage_executor_head,[string]$Result.qualified_admission_head,[string]$Result.qualified_persistence_head,[string]$Result.qualified_transaction_head,
        [string]$Result.status,[string]$Result.name,[string]$Result.source_identity,[string]$Result.github_repo_id,[string]$Result.surface_kind,[string]$Result.remote_commit_sha,
        [string]$Result.consumption_id,[string]$Result.stage_result_fingerprint,[string]$Result.pre_apply_admission_fingerprint,[string]$Result.persistence_envelope_sha256,
        [string]$Result.live_tree_sha256,[string]$Result.stage_tree_sha256,[string]$Result.binding_fingerprint,[string]$Result.stage_path,[string]$Result.stage_workspace_path,
        [string]$Result.app_backup_path,[string]$Result.app_backup_tree_sha256,[string]$Result.app_backup_file_count,[string]$Result.app_backup_total_bytes,
        [string]$Result.persistence_backup_path,[string]$Result.persistence_fingerprint,[string]$Result.prepared_at,
        [string]$Result.preparation_is_authority,[string]$Result.backups_are_authority,[string]$Result.requires_atomic_apply_rollback_executor,[string]$Result.requires_fresh_revalidation_before_apply,
        [string]$Result.requires_cleanup_if_not_applied,[string]$Result.apply_authorized,[string]$Result.live_destination_authorized,[string]$Result.production_execution_authorized,[string]$Result.production_mutation_authorized
    ) -join "`n"
}

function Test-CustomAppProductionPreApplyPreparedResultV010 {
    param([AllowNull()]$Result)
    if($null -eq $Result){return [pscustomobject]@{ok=$false;reason='pre-apply-result-null'}}
    foreach($required in @('schema','managed_by','qualified_stage_executor_head','qualified_admission_head','qualified_persistence_head','qualified_transaction_head','status','name','source_identity','github_repo_id','surface_kind','remote_commit_sha','consumption_id','stage_result_fingerprint','pre_apply_admission_fingerprint','persistence_envelope_sha256','live_tree_sha256','stage_tree_sha256','binding_fingerprint','stage_path','stage_workspace_path','app_backup_path','app_backup_tree_sha256','app_backup_file_count','app_backup_total_bytes','persistence_backup_path','persistence_fingerprint','prepared_at','preparation_fingerprint','preparation_is_authority','backups_are_authority','requires_atomic_apply_rollback_executor','requires_fresh_revalidation_before_apply','requires_cleanup_if_not_applied','apply_authorized','live_destination_authorized','production_execution_authorized','production_mutation_authorized')){if(-not $Result.PSObject.Properties[$required]){return [pscustomobject]@{ok=$false;reason=('pre-apply-result-required-field-missing-'+$required)}}}
    if([int]$Result.schema -ne $CustomAppProductionPreApplyPreparationSchema -or [string]$Result.managed_by -cne $CustomAppProductionPreApplyPreparationManagedBy -or [string]$Result.qualified_stage_executor_head -cne $CustomAppProductionPreApplyPreparationQualifiedStageHead -or [string]$Result.qualified_admission_head -cne $CustomAppProductionPreApplyPreparationQualifiedAdmissionHead -or [string]$Result.qualified_persistence_head -cne $CustomAppProductionPreApplyPreparationQualifiedPersistenceHead -or [string]$Result.qualified_transaction_head -cne $CustomAppProductionPreApplyPreparationQualifiedTransactionHead -or [string]$Result.status -cne 'pre-apply-backups-prepared-verified'){return [pscustomobject]@{ok=$false;reason='pre-apply-result-owner-schema-parent-or-status-invalid'}}
    if([bool]$Result.preparation_is_authority -or [bool]$Result.backups_are_authority -or -not [bool]$Result.requires_atomic_apply_rollback_executor -or -not [bool]$Result.requires_fresh_revalidation_before_apply -or -not [bool]$Result.requires_cleanup_if_not_applied){return [pscustomobject]@{ok=$false;reason='pre-apply-result-separation-contract-invalid'}}
    foreach($field in @('apply_authorized','live_destination_authorized','production_execution_authorized','production_mutation_authorized')){if([bool]$Result.$field){return [pscustomobject]@{ok=$false;reason=('pre-apply-result-'+$field+'-true')}}}
    foreach($field in @('consumption_id','stage_result_fingerprint','pre_apply_admission_fingerprint','persistence_envelope_sha256','live_tree_sha256','stage_tree_sha256','binding_fingerprint','app_backup_tree_sha256','persistence_fingerprint','preparation_fingerprint')){if(-not (Test-CustomAppProductionPreApplySha256V010 (([string]$Result.$field).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('pre-apply-result-invalid-'+$field)}}}
    if(([string]$Result.remote_commit_sha).Trim().ToLowerInvariant() -notmatch '^[0-9a-f]{40}$'){return [pscustomobject]@{ok=$false;reason='pre-apply-result-remote-commit-invalid'}}
    try{if([int64]$Result.github_repo_id -le 0 -or [int]$Result.app_backup_file_count -lt 1 -or [int64]$Result.app_backup_total_bytes -lt 1){return [pscustomobject]@{ok=$false;reason='pre-apply-result-count-or-repo-invalid'}}}catch{return [pscustomobject]@{ok=$false;reason='pre-apply-result-count-or-repo-invalid'}}
    if(-not (Test-Path -LiteralPath ([string]$Result.app_backup_path) -PathType Container)){return [pscustomobject]@{ok=$false;reason='pre-apply-result-app-backup-missing'}}
    try{$app=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$Result.app_backup_path)}catch{return [pscustomobject]@{ok=$false;reason=('pre-apply-result-app-backup-read-failed:'+[string]$_.Exception.Message)}}
    if([string]$app.tree_sha256 -cne [string]$Result.app_backup_tree_sha256 -or [int]$app.file_count -ne [int]$Result.app_backup_file_count -or [int64]$app.total_bytes -ne [int64]$Result.app_backup_total_bytes){return [pscustomobject]@{ok=$false;reason='pre-apply-result-app-backup-integrity-mismatch'}}
    if(-not (Test-Path -LiteralPath ([string]$Result.stage_path) -PathType Container) -or -not (Test-Path -LiteralPath ([string]$Result.stage_workspace_path) -PathType Container)){return [pscustomobject]@{ok=$false;reason='pre-apply-result-retained-stage-missing'}}
    try{$stage=Get-CustomAppLocalRuntimeBaseline -Name ([string]$Result.name) -AppPath ([string]$Result.stage_path)}catch{return [pscustomobject]@{ok=$false;reason=('pre-apply-result-stage-read-failed:'+[string]$_.Exception.Message)}}
    if(-not [bool]$stage.safe -or -not [bool]$stage.installable -or (Test-CustomAppLocalRuntimeBaselineMutationAuthority $stage) -or [string]$stage.tree_sha256 -cne [string]$Result.stage_tree_sha256){return [pscustomobject]@{ok=$false;reason='pre-apply-result-stage-integrity-mismatch'}}
    $persist=Test-CustomAppProductionPersistenceBackupV010 -BackupPath ([string]$Result.persistence_backup_path) -ExpectedFingerprint ([string]$Result.persistence_fingerprint)
    if(-not [bool]$persist.ok){return [pscustomobject]@{ok=$false;reason=('pre-apply-result-'+[string]$persist.reason)}}
    $expected=Get-CustomAppProductionPreApplySha256V010 (Get-CustomAppProductionPreApplyResultMaterialV010 -Result $Result)
    if(([string]$Result.preparation_fingerprint).Trim().ToLowerInvariant() -cne $expected){return [pscustomobject]@{ok=$false;reason='pre-apply-result-fingerprint-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='pre-apply-result-valid-no-apply-authority';preparation_fingerprint=$expected}
}

function Invoke-CustomAppProductionPreApplyPreparationV010 {
    param(
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory,[Parameter(Mandatory=$true)][string]$ExpectedConsumptionId,
        [AllowNull()]$StageExecutorResult,[AllowNull()]$Permit,[Parameter(Mandatory=$true)][string]$Name,[AllowNull()]$LifecycleRow,[AllowNull()]$ProvenanceRow,[AllowNull()]$BindingRow,[AllowNull()]$ShadowProtocolQualification,[AllowNull()]$LiveAttestedQualification,
        [Parameter(Mandatory=$true)][byte[]]$SessionKey,[Parameter(Mandatory=$true)][string]$RollbackBackupRoot,[Parameter(Mandatory=$true)][string]$PersistenceBackupRoot,
        [Parameter(Mandatory=$true)][string]$LocalAppDataRoot,[Parameter(Mandatory=$true)][string]$AppDataRoot,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow,[int]$MaxRemoteObservationAgeHours=36
    )
    $deny={param([string]$Reason)[pscustomobject]@{ok=$false;reason=$Reason;preparation_is_authority=$false;backups_are_authority=$false;requires_atomic_apply_rollback_executor=$true;requires_fresh_revalidation_before_apply=$true;apply_authorized=$false;live_destination_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false}}
    if([string]::IsNullOrWhiteSpace($Name)){return & $deny 'name-empty'}
    $stageCheck=Test-CustomAppProductionStageExecutorResultV010 -Result $StageExecutorResult
    if(-not [bool]$stageCheck.ok){return & $deny ('stage-result-invalid:'+[string]$stageCheck.reason)}
    if(([string]$StageExecutorResult.name).Trim().ToLowerInvariant() -cne $Name.Trim().ToLowerInvariant()){return & $deny 'stage-result-name-mismatch'}
    if(([string]$StageExecutorResult.consumption_id).Trim().ToLowerInvariant() -cne $ExpectedConsumptionId.Trim().ToLowerInvariant()){return & $deny 'stage-result-consumption-mismatch'}
    if($null -eq $Permit -or $null -eq $BindingRow -or $null -eq $LifecycleRow){return & $deny 'current-input-null'}
    if(([string]$StageExecutorResult.source_identity).Trim().ToLowerInvariant() -cne ([string]$Permit.source_identity).Trim().ToLowerInvariant()){return & $deny 'stage-permit-source-mismatch'}
    if(([string]$StageExecutorResult.remote_tree_sha256).Trim().ToLowerInvariant() -cne ([string]$Permit.remote_tree_sha256).Trim().ToLowerInvariant() -or ([string]$StageExecutorResult.local_tree_sha256).Trim().ToLowerInvariant() -cne ([string]$Permit.current_tree_sha256).Trim().ToLowerInvariant()){return & $deny 'stage-permit-tree-mismatch'}
    if(([string]$StageExecutorResult.remote_commit_sha).Trim().ToLowerInvariant() -cne ([string]$Permit.remote_commit_sha).Trim().ToLowerInvariant()){return & $deny 'stage-permit-commit-mismatch'}
    try{if([int64]$StageExecutorResult.github_repo_id -ne [int64]$Permit.github_repo_id){return & $deny 'stage-permit-repo-id-mismatch'}}catch{return & $deny 'stage-permit-repo-id-invalid'}
    if(([string]$StageExecutorResult.binding_fingerprint).Trim().ToLowerInvariant() -cne ([string]$BindingRow.binding.binding_fingerprint).Trim().ToLowerInvariant()){return & $deny 'stage-binding-fingerprint-mismatch'}

    $freshLive=Test-CustomAppProductionStageExecutorLiveBaselineV010 -LifecycleRow $LifecycleRow -Permit $Permit -BindingRow $BindingRow -Name $Name
    if(-not [bool]$freshLive.ok){return & $deny ('pre-apply-live-revalidation-denied:'+[string]$freshLive.reason)}
    $admission=Resolve-CustomAppProductionStageAdmissionV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedConsumptionId $ExpectedConsumptionId -Permit $Permit -Name $Name -LifecycleRow $LifecycleRow -ProvenanceRow $ProvenanceRow -BindingRow $BindingRow -CurrentBaseline $freshLive.baseline -ShadowProtocolQualification $ShadowProtocolQualification -LiveAttestedQualification $LiveAttestedQualification -SessionKey $SessionKey -Now $Now -MaxRemoteObservationAgeHours $MaxRemoteObservationAgeHours
    if($null -eq $admission -or -not [bool]$admission.ok){return & $deny ('pre-apply-admission-denied:'+[string]$admission.reason)}
    $admissionCheck=Test-CustomAppProductionStageAdmissionDecisionV010 -Decision $admission.decision
    if(-not [bool]$admissionCheck.ok){return & $deny ('pre-apply-admission-invalid:'+[string]$admissionCheck.reason)}
    $ad=$admission.decision
    foreach($pair in @(@('source_identity','source_identity'),@('surface_kind','surface_kind'),@('remote_tree_sha256','remote_tree_sha256'),@('remote_commit_sha','remote_commit_sha'),@('binding_fingerprint','binding_fingerprint'))){if(([string]$StageExecutorResult.($pair[0])).Trim().ToLowerInvariant() -cne ([string]$ad.($pair[1])).Trim().ToLowerInvariant()){return & $deny ('pre-apply-admission-continuity-mismatch-'+$pair[0])}}
    if(([string]$StageExecutorResult.local_tree_sha256).Trim().ToLowerInvariant() -cne ([string]$ad.current_tree_sha256).Trim().ToLowerInvariant()){return & $deny 'pre-apply-admission-current-tree-mismatch'}
    try{if([int64]$StageExecutorResult.github_repo_id -ne [int64]$ad.github_repo_id){return & $deny 'pre-apply-admission-repo-id-mismatch'}}catch{return & $deny 'pre-apply-admission-repo-id-invalid'}

    try{$freshStage=Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath ([string]$StageExecutorResult.stage_path)}catch{return & $deny ('pre-apply-stage-read-failed:'+[string]$_.Exception.Message)}
    if(-not [bool]$freshStage.safe -or -not [bool]$freshStage.installable -or (Test-CustomAppLocalRuntimeBaselineMutationAuthority $freshStage)){return & $deny 'pre-apply-stage-not-safe-installable-denied'}
    if(([string]$freshStage.tree_sha256).Trim().ToLowerInvariant() -cne ([string]$StageExecutorResult.remote_tree_sha256).Trim().ToLowerInvariant()){return & $deny 'pre-apply-stage-tree-mismatch'}
    if([string]$freshStage.manifest_name -cne [string]$BindingRow.binding.manifest_name){return & $deny 'pre-apply-stage-manifest-mismatch'}

    try{$persistenceBefore=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot}catch{return & $deny ('pre-apply-persistence-snapshot-failed:'+[string]$_.Exception.Message)}
    if(-not (Test-CustomAppProductionPreApplySha256V010 ([string]$persistenceBefore.fingerprint)){return & $deny 'pre-apply-persistence-fingerprint-invalid'}
    $livePath=[string]$freshLive.path
    try{
        $rollbackRoot=Assert-CustomAppProductionPreApplyBackupRootV010 -Path $RollbackBackupRoot -Label 'rollback backup root'
        $persistenceRoot=Assert-CustomAppProductionPreApplyBackupRootV010 -Path $PersistenceBackupRoot -Label 'persistence backup root'
        if(Test-CustomAppProductionPreApplyPathsOverlapV010 -A $livePath -B $rollbackRoot){return & $deny 'rollback-backup-root-overlaps-live'}
        if(Test-CustomAppProductionPreApplyPathsOverlapV010 -A ([string]$StageExecutorResult.stage_workspace_path) -B $rollbackRoot){return & $deny 'rollback-backup-root-overlaps-stage'}
        if(Test-CustomAppProductionPreApplyPathsOverlapV010 -A $livePath -B $persistenceRoot){return & $deny 'persistence-backup-root-overlaps-live'}
        if(Test-CustomAppProductionPreApplyPathsOverlapV010 -A ([string]$StageExecutorResult.stage_workspace_path) -B $persistenceRoot){return & $deny 'persistence-backup-root-overlaps-stage'}
        if(Test-CustomAppProductionPreApplyPathsOverlapV010 -A $rollbackRoot -B $persistenceRoot){return & $deny 'backup-roots-overlap'}
        $appBackup=New-CustomAppProductionAppRollbackBackupV010 -LivePath $livePath -BackupRoot $rollbackRoot
    }catch{return & $deny ('pre-apply-app-backup-failed:'+[string]$_.Exception.Message)}

    $liveAfterApp=Test-CustomAppProductionStageExecutorLiveBaselineV010 -LifecycleRow $LifecycleRow -Permit $Permit -BindingRow $BindingRow -Name $Name
    if(-not [bool]$liveAfterApp.ok){return & $deny ('post-app-backup-live-revalidation-denied:'+[string]$liveAfterApp.reason)}
    try{$stageAfterApp=Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath ([string]$StageExecutorResult.stage_path)}catch{return & $deny ('post-app-backup-stage-read-failed:'+[string]$_.Exception.Message)}
    if([string]$stageAfterApp.tree_sha256 -cne [string]$freshStage.tree_sha256){return & $deny 'post-app-backup-stage-tree-changed'}

    try{$persistenceBackup=New-RequiredSpotifyPersistenceBackup -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -BackupRootOverride $persistenceRoot}catch{return & $deny ('pre-apply-persistence-backup-failed:'+[string]$_.Exception.Message)}
    if([string]$persistenceBackup.fingerprint -cne [string]$persistenceBefore.fingerprint){return & $deny 'pre-apply-persistence-backup-fingerprint-mismatch'}
    $persistCheck=Test-CustomAppProductionPersistenceBackupV010 -BackupPath ([string]$persistenceBackup.path) -ExpectedFingerprint ([string]$persistenceBefore.fingerprint)
    if(-not [bool]$persistCheck.ok){return & $deny ('pre-apply-persistence-backup-invalid:'+[string]$persistCheck.reason)}
    try{$persistenceAfter=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot}catch{return & $deny ('post-persistence-backup-snapshot-failed:'+[string]$_.Exception.Message)}
    if([string]$persistenceAfter.fingerprint -cne [string]$persistenceBefore.fingerprint){return & $deny 'persistence-changed-during-pre-apply-backup'}
    $liveFinal=Test-CustomAppProductionStageExecutorLiveBaselineV010 -LifecycleRow $LifecycleRow -Permit $Permit -BindingRow $BindingRow -Name $Name
    if(-not [bool]$liveFinal.ok){return & $deny ('post-persistence-backup-live-revalidation-denied:'+[string]$liveFinal.reason)}
    try{$stageFinal=Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath ([string]$StageExecutorResult.stage_path)}catch{return & $deny ('post-persistence-backup-stage-read-failed:'+[string]$_.Exception.Message)}
    if([string]$stageFinal.tree_sha256 -cne [string]$freshStage.tree_sha256){return & $deny 'stage-changed-during-pre-apply-backup'}

    $result=[pscustomobject]@{
        schema=$CustomAppProductionPreApplyPreparationSchema;managed_by=$CustomAppProductionPreApplyPreparationManagedBy;qualified_stage_executor_head=$CustomAppProductionPreApplyPreparationQualifiedStageHead;qualified_admission_head=$CustomAppProductionPreApplyPreparationQualifiedAdmissionHead;qualified_persistence_head=$CustomAppProductionPreApplyPreparationQualifiedPersistenceHead;qualified_transaction_head=$CustomAppProductionPreApplyPreparationQualifiedTransactionHead
        status='pre-apply-backups-prepared-verified';name=$Name;source_identity=([string]$StageExecutorResult.source_identity).Trim().ToLowerInvariant();github_repo_id=[int64]$StageExecutorResult.github_repo_id;surface_kind=([string]$StageExecutorResult.surface_kind).Trim().ToLowerInvariant();remote_commit_sha=([string]$StageExecutorResult.remote_commit_sha).Trim().ToLowerInvariant()
        consumption_id=([string]$ExpectedConsumptionId).Trim().ToLowerInvariant();stage_result_fingerprint=([string]$StageExecutorResult.result_fingerprint).Trim().ToLowerInvariant();pre_apply_admission_fingerprint=([string]$admission.decision.admission_fingerprint).Trim().ToLowerInvariant();persistence_envelope_sha256=([string]$StageExecutorResult.persistence_envelope_sha256).Trim().ToLowerInvariant()
        live_tree_sha256=([string]$liveFinal.tree_sha256).Trim().ToLowerInvariant();stage_tree_sha256=([string]$stageFinal.tree_sha256).Trim().ToLowerInvariant();binding_fingerprint=([string]$StageExecutorResult.binding_fingerprint).Trim().ToLowerInvariant();stage_path=[string]$StageExecutorResult.stage_path;stage_workspace_path=[string]$StageExecutorResult.workspace_path
        app_backup_path=[string]$appBackup.path;app_backup_tree_sha256=([string]$appBackup.tree_sha256).Trim().ToLowerInvariant();app_backup_file_count=[int]$appBackup.file_count;app_backup_total_bytes=[int64]$appBackup.total_bytes
        persistence_backup_path=[string]$persistenceBackup.path;persistence_fingerprint=([string]$persistenceBefore.fingerprint).Trim().ToLowerInvariant();prepared_at=$Now.ToUniversalTime().ToString('o');preparation_fingerprint=$null
        preparation_is_authority=$false;backups_are_authority=$false;requires_atomic_apply_rollback_executor=$true;requires_fresh_revalidation_before_apply=$true;requires_cleanup_if_not_applied=$true;apply_authorized=$false;live_destination_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false
    }
    $result.preparation_fingerprint=Get-CustomAppProductionPreApplySha256V010 (Get-CustomAppProductionPreApplyResultMaterialV010 -Result $result)
    $check=Test-CustomAppProductionPreApplyPreparedResultV010 -Result $result
    if(-not [bool]$check.ok){return & $deny ('pre-apply-result-self-validation-failed:'+[string]$check.reason)}
    return [pscustomobject]@{ok=$true;reason='pre-apply-backups-prepared-verified-no-apply-authority';result=$result;preparation_fingerprint=[string]$result.preparation_fingerprint;preparation_is_authority=$false;backups_are_authority=$false;requires_atomic_apply_rollback_executor=$true;requires_fresh_revalidation_before_apply=$true;requires_cleanup_if_not_applied=$true;apply_authorized=$false;live_destination_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false}
}
