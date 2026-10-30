$CustomAppProductionBoundedRecoveryExecutorSchema = 1
$CustomAppProductionBoundedRecoveryExecutorManagedBy = 'custom-app-production-bounded-recovery-executor-v1'
$CustomAppProductionBoundedRecoveryExecutorQualifiedIntegrationHead = '5232e5adeb13e6942acb210b3cd13058e1eaaf05'
$CustomAppProductionBoundedRecoveryExecutorZeroHash = ('0' * 64)

function Get-CustomAppProductionBoundedRecoveryExecutorSha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}
function Test-CustomAppProductionBoundedRecoveryExecutorSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}
function Get-CustomAppProductionBoundedRecoveryExecutorCanonicalPathV010 {
    param([Parameter(Mandatory=$true)][string]$Path)
    if([string]::IsNullOrWhiteSpace($Path)){throw 'recovery-executor-path-empty'}
    return [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
}
function Test-CustomAppProductionBoundedRecoveryExecutorWithinV010 {
    param([Parameter(Mandatory=$true)][string]$Root,[Parameter(Mandatory=$true)][string]$Path,[bool]$AllowRoot=$false)
    $r=Get-CustomAppProductionBoundedRecoveryExecutorCanonicalPathV010 $Root
    $p=Get-CustomAppProductionBoundedRecoveryExecutorCanonicalPathV010 $Path
    if($p.Equals($r,[StringComparison]::OrdinalIgnoreCase)){return $AllowRoot}
    return $p.StartsWith($r+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)
}
function Test-CustomAppProductionBoundedRecoveryExecutorTreeNoReparseV010 {
    param([Parameter(Mandatory=$true)][string]$Path)
    if(-not (Test-Path -LiteralPath $Path)){return [pscustomobject]@{ok=$true;reason='owned-artifact-already-absent';present=$false}}
    try{
        $root=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if(($root.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){return [pscustomobject]@{ok=$false;reason='owned-artifact-root-reparse-point';present=$true}}
        foreach($item in @(Get-ChildItem -LiteralPath $Path -Force -Recurse -ErrorAction Stop)){
            if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){return [pscustomobject]@{ok=$false;reason='owned-artifact-descendant-reparse-point';present=$true}}
        }
        return [pscustomobject]@{ok=$true;reason='owned-artifact-tree-no-reparse';present=$true}
    }catch{return [pscustomobject]@{ok=$false;reason=('owned-artifact-read-failed:'+[string]$_.Exception.Message);present=$true}}
}
function Invoke-CustomAppProductionBoundedRecoveryExecutorValidationHookV010 {
    param([Parameter(Mandatory=$true)][string]$Checkpoint,[Parameter(Mandatory=$true)]$Context)
    # Deliberate no-op. Validation harness may replace this function to inject fixture-only faults/races.
}

function Resolve-CustomAppProductionBoundedRecoveryFreshIntegrationV010 {
    param(
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory,[Parameter(Mandatory=$true)][string]$ExpectedTransactionId,
        [AllowNull()][string]$SpicetifyAllowedRoot=$null,[AllowNull()][string]$SpicetifyPath=$null,[AllowNull()][string]$ExpectedSpicetifySha256=$null,
        [DateTimeOffset]$Now=[DateTimeOffset]::UtcNow
    )
    $deny={param([string]$Reason)[pscustomobject]@{ok=$false;reason=$Reason;plan=$null;preflight=$null;integration=$null;execution_authorized=$false;production_mutation_authorized=$false}}
    try{$plan=Resolve-CustomAppProductionRecoveryPlanV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $ExpectedTransactionId}catch{return & $deny ('recovery-executor-plan-resolution-failed:'+[string]$_.Exception.Message)}
    $pc=Test-CustomAppProductionRecoveryPlanV010 -Plan $plan
    if(-not [bool]$pc.ok){return & $deny ('recovery-executor-plan-invalid:'+[string]$pc.reason)}
    $pre=Resolve-CustomAppProductionRecoveryPreflightV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $ExpectedTransactionId -Plan $plan -SpicetifyAllowedRoot $SpicetifyAllowedRoot -SpicetifyPath $SpicetifyPath -ExpectedSpicetifySha256 $ExpectedSpicetifySha256
    if($null-eq$pre -or -not [bool]$pre.ok){return & $deny ('recovery-executor-preflight-denied:'+[string]$pre.reason)}
    $prc=Test-CustomAppProductionRecoveryPreflightReceiptV010 -Receipt $pre.receipt
    if(-not [bool]$prc.ok){return & $deny ('recovery-executor-preflight-invalid:'+[string]$prc.reason)}
    $integration=Resolve-CustomAppProductionRecoveryEvidenceAdmissionIntegrationV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $ExpectedTransactionId -Plan $plan -PreflightReceipt $pre.receipt -SpicetifyAllowedRoot $SpicetifyAllowedRoot -SpicetifyPath $SpicetifyPath -ExpectedSpicetifySha256 $ExpectedSpicetifySha256 -Now $Now
    if($null-eq$integration -or -not [bool]$integration.ok){return & $deny ('recovery-executor-integration-denied:'+[string]$integration.reason)}
    $ic=Test-CustomAppProductionRecoveryEvidenceAdmissionIntegrationReceiptV010 -Receipt $integration.receipt -Now $Now
    if(-not [bool]$ic.ok){return & $deny ('recovery-executor-integration-invalid:'+[string]$ic.reason)}
    return [pscustomobject]@{ok=$true;reason='recovery-executor-fresh-integration-valid';plan=$plan;preflight=$pre.receipt;integration=$integration.receipt;evidence=$integration.evidence;execution_authorized=$false;production_mutation_authorized=$false}
}

function Test-CustomAppProductionBoundedRecoveryStageOwnedArtifactV010 {
    param([Parameter(Mandatory=$true)]$Prepared,[Parameter(Mandatory=$true)][string]$Name,[bool]$AllowPartial=$false)
    try{
        $root=Get-CustomAppProductionBoundedRecoveryExecutorCanonicalPathV010 (Get-CustomAppStageWorkspaceRootV010)
        $workspace=Get-CustomAppProductionBoundedRecoveryExecutorCanonicalPathV010 ([string]$Prepared.stage_workspace_path)
        if(-not ([IO.Path]::GetDirectoryName($workspace)).Equals($root,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($workspace)-notmatch'^[0-9a-fA-F]{32}$'){return [pscustomobject]@{ok=$false;reason='recovery-stage-workspace-path-shape-invalid'}}
        if(-not(Test-Path -LiteralPath $workspace)){return [pscustomobject]@{ok=$true;reason='recovery-stage-workspace-already-absent';status='already-absent';path=$workspace;root=$root}}
        $safe=Test-CustomAppProductionBoundedRecoveryExecutorTreeNoReparseV010 -Path $workspace;if(-not[bool]$safe.ok){return [pscustomobject]@{ok=$false;reason=('recovery-stage-workspace-unsafe:'+[string]$safe.reason)}}
        $children=@(Get-ChildItem -LiteralPath $workspace -Force -ErrorAction Stop)
        $bad=@($children|Where-Object{[string]$_.Name -notin @('stage','remote.zip')});if($bad.Count){return [pscustomobject]@{ok=$false;reason='recovery-stage-workspace-unexpected-entry'}}
        $stage=@($children|Where-Object{[string]$_.Name -ceq 'stage'});if($stage.Count -gt 1){return [pscustomobject]@{ok=$false;reason='recovery-stage-workspace-stage-ambiguous'}}
        if($stage.Count -eq 1){
            if(-not$stage[0].PSIsContainer -or ($stage[0].Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){return [pscustomobject]@{ok=$false;reason='recovery-stage-workspace-stage-unsafe'}}
            try{$baseline=Get-CustomAppLocalRuntimeBaseline -Name $Name -AppPath $stage[0].FullName}
            catch{if(-not$AllowPartial){return [pscustomobject]@{ok=$false;reason=('recovery-stage-runtime-read-failed:'+[string]$_.Exception.Message)}};$baseline=$null}
            if($null-ne$baseline -and (-not[bool]$baseline.safe -or -not[bool]$baseline.installable -or (Test-CustomAppLocalRuntimeBaselineMutationAuthority $baseline) -or [string]$baseline.tree_sha256-cne[string]$Prepared.stage_tree_sha256)){
                if(-not$AllowPartial){return [pscustomobject]@{ok=$false;reason='recovery-stage-runtime-drift'}}
            }
        }elseif(-not$AllowPartial){return [pscustomobject]@{ok=$false;reason='recovery-stage-workspace-stage-missing'}}
        $zip=@($children|Where-Object{[string]$_.Name -ceq 'remote.zip'});if($zip.Count -gt 1){return [pscustomobject]@{ok=$false;reason='recovery-stage-workspace-remote-zip-ambiguous'}}
        if($zip.Count -eq 1 -and ($zip[0].PSIsContainer -or ($zip[0].Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0)){return [pscustomobject]@{ok=$false;reason='recovery-stage-workspace-remote-zip-unsafe'}}
        return [pscustomobject]@{ok=$true;reason=$(if($AllowPartial){'recovery-stage-owned-partial-or-exact-safe'}else{'recovery-stage-owned-exact-safe'});status='present-verified';path=$workspace;root=$root}
    }catch{return [pscustomobject]@{ok=$false;reason=('recovery-stage-workspace-read-failed:'+[string]$_.Exception.Message)}}
}

function Test-CustomAppProductionBoundedRecoveryAppOwnedArtifactV010 {
    param([Parameter(Mandatory=$true)]$Prepared,[bool]$AllowPartial=$false)
    try{
        $root=Get-CustomAppProductionBoundedRecoveryExecutorCanonicalPathV010 ([string]$Prepared.app_backup_root)
        $app=Get-CustomAppProductionBoundedRecoveryExecutorCanonicalPathV010 ([string]$Prepared.app_backup_path)
        $container=Get-CustomAppProductionBoundedRecoveryExecutorCanonicalPathV010 ([IO.Path]::GetDirectoryName($app))
        if(-not([IO.Path]::GetDirectoryName($container)).Equals($root,[StringComparison]::OrdinalIgnoreCase)-or[IO.Path]::GetFileName($container)-notmatch'^[0-9a-fA-F]{32}$'-or[IO.Path]::GetFileName($app)-cne'app-code'){return [pscustomobject]@{ok=$false;reason='recovery-app-backup-path-shape-invalid'}}
        if(-not(Test-Path -LiteralPath $container)){return [pscustomobject]@{ok=$true;reason='recovery-app-backup-already-absent';status='already-absent';path=$container;root=$root}}
        $safe=Test-CustomAppProductionBoundedRecoveryExecutorTreeNoReparseV010 -Path $container;if(-not[bool]$safe.ok){return [pscustomobject]@{ok=$false;reason=('recovery-app-backup-unsafe:'+[string]$safe.reason)}}
        $children=@(Get-ChildItem -LiteralPath $container -Force -ErrorAction Stop);$bad=@($children|Where-Object{[string]$_.Name-cne'app-code'});if($bad.Count){return [pscustomobject]@{ok=$false;reason='recovery-app-backup-unexpected-entry'}}
        $code=@($children|Where-Object{[string]$_.Name-ceq'app-code'});if($code.Count -gt 1){return [pscustomobject]@{ok=$false;reason='recovery-app-backup-app-code-ambiguous'}}
        if($code.Count -eq 1){
            if(-not$code[0].PSIsContainer -or ($code[0].Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){return [pscustomobject]@{ok=$false;reason='recovery-app-backup-app-code-unsafe'}}
            if(-not$AllowPartial){$snap=Get-CustomAppUpdateTreeSnapshotV010 -Root $code[0].FullName;if([string]$snap.tree_sha256-cne[string]$Prepared.app_backup_tree_sha256-or[int]$snap.file_count-ne[int]$Prepared.app_backup_file_count-or[int64]$snap.total_bytes-ne[int64]$Prepared.app_backup_total_bytes){return [pscustomobject]@{ok=$false;reason='recovery-app-backup-tree-drift'}}}
        }elseif(-not$AllowPartial){return [pscustomobject]@{ok=$false;reason='recovery-app-backup-app-code-missing'}}
        return [pscustomobject]@{ok=$true;reason=$(if($AllowPartial){'recovery-app-backup-owned-partial-or-exact-safe'}else{'recovery-app-backup-owned-exact-safe'});status='present-verified';path=$container;root=$root}
    }catch{return [pscustomobject]@{ok=$false;reason=('recovery-app-backup-read-failed:'+[string]$_.Exception.Message)}}
}

function Test-CustomAppProductionBoundedRecoveryPersistenceOwnedArtifactV010 {
    param([Parameter(Mandatory=$true)]$Prepared,[bool]$AllowPartial=$false)
    try{
        $root=Get-CustomAppProductionBoundedRecoveryExecutorCanonicalPathV010 ([string]$Prepared.persistence_backup_root)
        $path=Get-CustomAppProductionBoundedRecoveryExecutorCanonicalPathV010 ([string]$Prepared.persistence_backup_path)
        if(-not([IO.Path]::GetDirectoryName($path)).Equals($root,[StringComparison]::OrdinalIgnoreCase)-or[IO.Path]::GetFileName($path)-notmatch'^txn-\d{8}-\d{6}-[0-9a-fA-F]{8}$'){return [pscustomobject]@{ok=$false;reason='recovery-persistence-backup-path-shape-invalid'}}
        if(-not(Test-Path -LiteralPath $path)){return [pscustomobject]@{ok=$true;reason='recovery-persistence-backup-already-absent';status='already-absent';path=$path;root=$root}}
        $safe=Test-CustomAppProductionBoundedRecoveryExecutorTreeNoReparseV010 -Path $path;if(-not[bool]$safe.ok){return [pscustomobject]@{ok=$false;reason=('recovery-persistence-backup-unsafe:'+[string]$safe.reason)}}
        $children=@(Get-ChildItem -LiteralPath $path -Force -ErrorAction Stop);$bad=@($children|Where-Object{[string]$_.Name-notin@('surfaces','guard-manifest.json')});if($bad.Count){return [pscustomobject]@{ok=$false;reason='recovery-persistence-backup-unexpected-entry'}}
        $surfaces=@($children|Where-Object{[string]$_.Name-ceq'surfaces'});if($surfaces.Count-gt1-or($surfaces.Count-eq1-and(-not$surfaces[0].PSIsContainer-or($surfaces[0].Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0))){return [pscustomobject]@{ok=$false;reason='recovery-persistence-surfaces-entry-unsafe'}}
        $manifest=@($children|Where-Object{[string]$_.Name-ceq'guard-manifest.json'});if($manifest.Count-gt1-or($manifest.Count-eq1-and($manifest[0].PSIsContainer-or($manifest[0].Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0))){return [pscustomobject]@{ok=$false;reason='recovery-persistence-manifest-entry-unsafe'}}
        if(-not$AllowPartial){$check=Test-CustomAppProductionPersistenceBackupV010 -BackupPath $path -ExpectedFingerprint ([string]$Prepared.persistence_fingerprint);if(-not[bool]$check.ok){return [pscustomobject]@{ok=$false;reason=('recovery-persistence-backup-integrity-invalid:'+[string]$check.reason)}}}
        return [pscustomobject]@{ok=$true;reason=$(if($AllowPartial){'recovery-persistence-owned-partial-or-exact-safe'}else{'recovery-persistence-owned-exact-safe'});status='present-verified';path=$path;root=$root}
    }catch{return [pscustomobject]@{ok=$false;reason=('recovery-persistence-backup-read-failed:'+[string]$_.Exception.Message)}}
}

function Resolve-CustomAppProductionBoundedRecoveryCleanupResumeGateV010 {
    param(
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory,[Parameter(Mandatory=$true)][string]$ExpectedTransactionId,
        [Parameter(Mandatory=$true)][string]$LocalAppDataRoot,[Parameter(Mandatory=$true)][string]$AppDataRoot,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow
    )
    $deny={param([string]$Reason)[pscustomobject]@{ok=$false;reason=$Reason;resume_is_authority=$false;execution_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false}}
    try{$read=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory}catch{return & $deny ('cleanup-resume-journal-read-failed:'+[string]$_.Exception.Message)}
    if($null-eq$read-or-not[bool]$read.ok-or[string]$read.entry.phase-cne'cleanup-starting'){return & $deny 'cleanup-resume-phase-not-cleanup-starting'}
    $tx=$ExpectedTransactionId.Trim().ToLowerInvariant();if(([string]$read.transaction_id).Trim().ToLowerInvariant()-cne$tx){return & $deny 'cleanup-resume-transaction-mismatch'}
    $evidence=Read-CustomAppProductionRecoveryEvidenceV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $tx
    if($null-eq$evidence-or-not[bool]$evidence.ok){return & $deny ('cleanup-resume-evidence-read-denied:'+[string]$evidence.reason)}
    $e=$evidence.envelope;$prepared=$e.prepared_result
    foreach($f in @('evidence_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){if([bool]$e.$f){return & $deny ('cleanup-resume-evidence-authority-escaped-'+$f)}}
    if([string]$e.live_path-cne[string]$read.entry.live_path-or[string]$e.stage_workspace_path-cne[string]$read.entry.stage_workspace_path-or[string]$e.app_backup_path-cne[string]$read.entry.app_backup_path-or[string]$e.persistence_backup_path-cne[string]$read.entry.persistence_backup_path){return & $deny 'cleanup-resume-journal-evidence-path-mismatch'}
    try{$live=Get-CustomAppLocalRuntimeBaseline -Name ([string]$e.name) -AppPath ([string]$e.live_path)}catch{return & $deny ('cleanup-resume-live-read-failed:'+[string]$_.Exception.Message)}
    if(-not[bool]$live.safe-or-not[bool]$live.installable-or(Test-CustomAppLocalRuntimeBaselineMutationAuthority $live)-or[string]$live.tree_sha256-cne[string]$prepared.stage_tree_sha256){return & $deny 'cleanup-resume-live-runtime-drift'}
    $git=Join-Path ([string]$e.live_path) '.git';if(Test-Path -LiteralPath $git){if(-not(Test-Path -LiteralPath $git -PathType Container)){return & $deny 'cleanup-resume-live-git-not-directory'};$gs=Test-CustomAppProductionBoundedRecoveryExecutorTreeNoReparseV010 -Path $git;if(-not[bool]$gs.ok){return & $deny ('cleanup-resume-live-git-unsafe:'+[string]$gs.reason)}}
    try{$persist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot}catch{return & $deny ('cleanup-resume-persistence-read-failed:'+[string]$_.Exception.Message)}
    if([string]$persist.fingerprint-cne[string]$e.persistence_fingerprint){return & $deny 'cleanup-resume-protected-persistence-drift'}
    $stage=Test-CustomAppProductionBoundedRecoveryStageOwnedArtifactV010 -Prepared $prepared -Name ([string]$e.name) -AllowPartial:$true;if(-not[bool]$stage.ok){return & $deny ([string]$stage.reason)}
    $app=Test-CustomAppProductionBoundedRecoveryAppOwnedArtifactV010 -Prepared $prepared -AllowPartial:$true;if(-not[bool]$app.ok){return & $deny ([string]$app.reason)}
    $pb=Test-CustomAppProductionBoundedRecoveryPersistenceOwnedArtifactV010 -Prepared $prepared -AllowPartial:$true;if(-not[bool]$pb.ok){return & $deny ([string]$pb.reason)}
    $material=@($tx,[string]$read.revision,[string]$read.entry.entry_sha256,[string]$e.evidence_fingerprint,[string]$live.tree_sha256,[string]$persist.fingerprint,[string]$stage.status,[string]$app.status,[string]$pb.status,$Now.ToUniversalTime().ToString('o'))-join"`n"
    $fp=Get-CustomAppProductionBoundedRecoveryExecutorSha256V010 $material
    return [pscustomobject]@{ok=$true;reason='cleanup-resume-read-only-gate-valid';transaction_id=$tx;journal=$read;evidence=$e;prepared=$prepared;live=$live;persistence=$persist;stage=$stage;app=$app;persistence_backup=$pb;resume_fingerprint=$fp;resume_is_authority=$false;execution_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false}
}

function Test-CustomAppProductionBoundedRecoveryExecutorMissingCleanupArtifactFailureV010 {
    param([AllowNull()][string]$Reason)
    if([string]::IsNullOrWhiteSpace($Reason)){return $false}
    $r=$Reason.ToLowerInvariant()
    if($r -notlike '*preflight*'){return $false}
    return (($r -like '*stage-workspace*' -or $r -like '*app-backup*' -or $r -like '*persistence-backup*') -and ($r -like '*missing*' -or $r -like '*not a directory*'))
}

function Get-CustomAppProductionBoundedRecoveryExecutorResultMaterialV010 {
    param([Parameter(Mandatory=$true)]$Result)
    return @(
        [string]$Result.schema,[string]$Result.managed_by,[string]$Result.qualified_integration_head,[string]$Result.status,[string]$Result.reason,
        [string]$Result.transaction_id,[string]$Result.name,[string]$Result.initial_phase,[string]$Result.executor_class,[string]$Result.final_phase,
        [string]$Result.evidence_fingerprint,[string]$Result.integration_or_resume_fingerprint,[string]$Result.journal_start_revision,[string]$Result.journal_end_revision,[string]$Result.journal_end_sha256,
        [string]$Result.rollback_required_recorded,[string]$Result.exact_restore_executed,[string]$Result.recovery_apply_executed,[string]$Result.housekeeping_executed,
        [string]$Result.stage_cleanup_status,[string]$Result.app_cleanup_status,[string]$Result.persistence_cleanup_status,[string]$Result.live_runtime_tree_sha256,[string]$Result.persistence_fingerprint,[string]$Result.cleanup_evidence_fingerprint,
        [string]$Result.fixture_only_contract,[string]$Result.result_is_authority,[string]$Result.execution_authorized,[string]$Result.restore_authorized,[string]$Result.apply_authorized,[string]$Result.cleanup_authorized,[string]$Result.production_mutation_authorized
    )-join"`n"
}
function Test-CustomAppProductionBoundedRecoveryExecutorResultV010 {
    param([AllowNull()]$Result)
    if($null-eq$Result){return [pscustomobject]@{ok=$false;reason='recovery-executor-result-null'}}
    foreach($f in @('schema','managed_by','qualified_integration_head','status','reason','transaction_id','name','initial_phase','executor_class','final_phase','evidence_fingerprint','integration_or_resume_fingerprint','journal_start_revision','journal_end_revision','journal_end_sha256','rollback_required_recorded','exact_restore_executed','recovery_apply_executed','housekeeping_executed','stage_cleanup_status','app_cleanup_status','persistence_cleanup_status','live_runtime_tree_sha256','persistence_fingerprint','cleanup_evidence_fingerprint','fixture_only_contract','result_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized','result_fingerprint')){if(-not$Result.PSObject.Properties[$f]){return [pscustomobject]@{ok=$false;reason=('recovery-executor-result-required-field-missing-'+$f)}}}
    if([int]$Result.schema-ne1-or[string]$Result.managed_by-cne$CustomAppProductionBoundedRecoveryExecutorManagedBy-or[string]$Result.qualified_integration_head-cne$CustomAppProductionBoundedRecoveryExecutorQualifiedIntegrationHead){return [pscustomobject]@{ok=$false;reason='recovery-executor-result-owner-schema-parent-invalid'}}
    if([string]$Result.status-notin@('rollback-complete','housekeeping-committed-clean')){return [pscustomobject]@{ok=$false;reason='recovery-executor-result-status-invalid'}}
    foreach($f in @('transaction_id','evidence_fingerprint','integration_or_resume_fingerprint','journal_end_sha256','live_runtime_tree_sha256','persistence_fingerprint','cleanup_evidence_fingerprint','result_fingerprint')){if(-not(Test-CustomAppProductionBoundedRecoveryExecutorSha256V010(([string]$Result.$f).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('recovery-executor-result-invalid-'+$f)}}}
    foreach($f in @('result_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){if([bool]$Result.$f){return [pscustomobject]@{ok=$false;reason=('recovery-executor-result-authority-escaped-'+$f)}}}
    if(-not[bool]$Result.fixture_only_contract){return [pscustomobject]@{ok=$false;reason='recovery-executor-result-fixture-only-contract-missing'}}
    try{if([int64]$Result.journal_end_revision-lt[int64]$Result.journal_start_revision){return [pscustomobject]@{ok=$false;reason='recovery-executor-result-journal-revision-regressed'}}}catch{return [pscustomobject]@{ok=$false;reason='recovery-executor-result-journal-revision-invalid'}}
    if([string]$Result.status-ceq'rollback-complete'){
        if([string]$Result.final_phase-cne'rollback-complete'-or-not[bool]$Result.rollback_required_recorded-or-not[bool]$Result.exact_restore_executed-or-not[bool]$Result.recovery_apply_executed-or[bool]$Result.housekeeping_executed){return [pscustomobject]@{ok=$false;reason='recovery-executor-result-rollback-contract-invalid'}}
    }else{
        if([string]$Result.final_phase-cne'committed-clean'-or[bool]$Result.exact_restore_executed-or[bool]$Result.recovery_apply_executed-or-not[bool]$Result.housekeeping_executed){return [pscustomobject]@{ok=$false;reason='recovery-executor-result-housekeeping-contract-invalid'}}
    }
    $expected=Get-CustomAppProductionBoundedRecoveryExecutorSha256V010 (Get-CustomAppProductionBoundedRecoveryExecutorResultMaterialV010 $Result)
    if(([string]$Result.result_fingerprint).Trim().ToLowerInvariant()-cne$expected){return [pscustomobject]@{ok=$false;reason='recovery-executor-result-fingerprint-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='recovery-executor-result-valid-non-authoritative';result_fingerprint=$expected}
}

function Invoke-CustomAppProductionBoundedRecoveryExecutorV010 {
    param(
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory,[Parameter(Mandatory=$true)][string]$ExpectedTransactionId,
        [Parameter(Mandatory=$true)][string]$LocalAppDataRoot,[Parameter(Mandatory=$true)][string]$AppDataRoot,
        [AllowNull()][string]$SpicetifyAllowedRoot=$null,[AllowNull()][string]$SpicetifyPath=$null,[AllowNull()][string]$ExpectedSpicetifySha256=$null,
        [int]$TimeoutSeconds=180,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow
    )
    $deny={param([string]$Reason)[pscustomobject]@{ok=$false;reason=$Reason;result_is_authority=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false}}
    if($TimeoutSeconds-lt1-or$TimeoutSeconds-gt600){return & $deny 'recovery-executor-timeout-policy-invalid'}
    try{$initialJournal=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory}catch{return & $deny ('recovery-executor-journal-read-failed:'+[string]$_.Exception.Message)}
    if($null-eq$initialJournal-or-not[bool]$initialJournal.ok-or([string]$initialJournal.transaction_id).Trim().ToLowerInvariant()-cne$ExpectedTransactionId.Trim().ToLowerInvariant()){return & $deny 'recovery-executor-journal-or-transaction-invalid'}
    $initialPhase=[string]$initialJournal.entry.phase
    $fresh=Resolve-CustomAppProductionBoundedRecoveryFreshIntegrationV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $ExpectedTransactionId -SpicetifyAllowedRoot $SpicetifyAllowedRoot -SpicetifyPath $SpicetifyPath -ExpectedSpicetifySha256 $ExpectedSpicetifySha256 -Now $Now

    $resume=$null
    if(-not[bool]$fresh.ok){
        if($initialPhase-cne'cleanup-starting'-or-not(Test-CustomAppProductionBoundedRecoveryExecutorMissingCleanupArtifactFailureV010 -Reason ([string]$fresh.reason))){return & $deny ([string]$fresh.reason)}
        $resume=Resolve-CustomAppProductionBoundedRecoveryCleanupResumeGateV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $ExpectedTransactionId -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -Now $Now
        if(-not[bool]$resume.ok){return & $deny ('recovery-executor-cleanup-resume-denied:'+[string]$resume.reason)}
    }

    $executorClass=$(if($null-ne$resume){'idempotent-housekeeping'}else{[string]$fresh.integration.executor_class})
    if($executorClass-in@('manual-inspection','no-action')){return & $deny ('recovery-executor-class-refused-'+$executorClass)}

    if($executorClass-in@('exact-app-persistence-restore','exact-app-persistence-restore-and-recovery-apply')){
        if([string]::IsNullOrWhiteSpace($SpicetifyAllowedRoot)-or[string]::IsNullOrWhiteSpace($SpicetifyPath)-or[string]::IsNullOrWhiteSpace($ExpectedSpicetifySha256)){return & $deny 'recovery-executor-restore-requires-exact-spicetify-pin'}
        try{[void](Assert-CustomAppProductionCrashJournalPathV010 -AllowedRoot $SpicetifyAllowedRoot -Path $SpicetifyPath -Label 'recovery spicetify executable' -RequireExisting:$true);$probe=Open-CustomAppProductionSpicetifyExecutableV010 -ExecutablePath $SpicetifyPath -ExpectedSha256 $ExpectedSpicetifySha256;$probe.stream.Dispose()}catch{return & $deny ('recovery-executor-spicetify-pin-denied-before-journal:'+[string]$_.Exception.Message)}
        $integration=$fresh.integration;$e=$fresh.evidence;$prepared=$e.prepared_result
        $current=$initialJournal;$rollbackRecorded=($initialPhase-ceq'rollback-required')
        if(-not$rollbackRecorded){
            Invoke-CustomAppProductionBoundedRecoveryExecutorValidationHookV010 -Checkpoint 'before-rollback-required-journal' -Context ([pscustomobject]@{journal=$current;integration=$integration})
            $next=Append-CustomAppProductionCrashJournalPhaseV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedRevision ([int64]$integration.journal_revision) -ExpectedEntrySha256 ([string]$integration.journal_entry_sha256) -Phase 'rollback-required' -Now $Now.AddMilliseconds(1)
            if($null-eq$next-or-not[bool]$next.ok){return & $deny ('recovery-executor-rollback-required-journal-denied:'+[string]$next.reason)}
            $rollbackRecorded=$true;$current=$next
        }
        Invoke-CustomAppProductionBoundedRecoveryExecutorValidationHookV010 -Checkpoint 'after-rollback-required-before-fresh-integration' -Context ([pscustomobject]@{journal=$current})
        $rf=Resolve-CustomAppProductionBoundedRecoveryFreshIntegrationV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $ExpectedTransactionId -SpicetifyAllowedRoot $SpicetifyAllowedRoot -SpicetifyPath $SpicetifyPath -ExpectedSpicetifySha256 $ExpectedSpicetifySha256 -Now $Now.AddMilliseconds(2)
        if(-not[bool]$rf.ok){return & $deny ('recovery-executor-post-journal-fresh-integration-denied:'+[string]$rf.reason)}
        if([string]$rf.integration.executor_class-cne'exact-app-persistence-restore-and-recovery-apply'-or-not[bool]$rf.integration.requires_exact_restore-or-not[bool]$rf.integration.requires_recovery_apply-or-not[bool]$rf.integration.backup_integrity_verified){return & $deny 'recovery-executor-post-journal-integration-contract-invalid'}
        $e=$rf.evidence;$prepared=$e.prepared_result
        Invoke-CustomAppProductionBoundedRecoveryExecutorValidationHookV010 -Checkpoint 'before-restore' -Context ([pscustomobject]@{integration=$rf.integration;evidence=$e})
        $restore=Restore-CustomAppProductionAtomicLiveSwapV010 -LivePath ([string]$e.live_path) -AppBackupPath ([string]$e.app_backup_path) -ExpectedAppBackupTreeSha256 ([string]$e.app_backup_tree_sha256) -PersistenceBackupPath ([string]$e.persistence_backup_path) -ExpectedPersistenceFingerprint ([string]$e.persistence_fingerprint) -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot
        if($null-eq$restore-or-not[bool]$restore.ok){return & $deny ('recovery-executor-exact-restore-failed:'+[string]$restore.reason)}
        Invoke-CustomAppProductionBoundedRecoveryExecutorValidationHookV010 -Checkpoint 'after-restore-before-recovery-apply' -Context ([pscustomobject]@{restore=$restore})
        $lock=$null
        try{$lock=Open-CustomAppProductionSpicetifyExecutableV010 -ExecutablePath $SpicetifyPath -ExpectedSha256 $ExpectedSpicetifySha256;$apply=Invoke-CustomAppProductionExactSpicetifyApplyProcessV010 -ExecutablePath ([string]$lock.path) -TimeoutSeconds $TimeoutSeconds}
        catch{return & $deny ('recovery-executor-recovery-apply-executable-denied:'+[string]$_.Exception.Message)}
        finally{if($null-ne$lock-and$null-ne$lock.stream){$lock.stream.Dispose()}}
        if($null-eq$apply-or-not[bool]$apply.ok){return & $deny ('recovery-executor-recovery-apply-failed:'+[string]$apply.reason)}
        Invoke-CustomAppProductionBoundedRecoveryExecutorValidationHookV010 -Checkpoint 'after-recovery-apply-before-postcheck' -Context ([pscustomobject]@{apply=$apply})
        try{$full=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$e.live_path);$persist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot}catch{return & $deny ('recovery-executor-post-rollback-read-failed:'+[string]$_.Exception.Message)}
        if([string]$full.tree_sha256-cne[string]$e.app_backup_tree_sha256){return & $deny 'recovery-executor-post-rollback-app-tree-mismatch'}
        if([string]$persist.fingerprint-cne[string]$e.persistence_fingerprint){return & $deny 'recovery-executor-post-rollback-persistence-mismatch'}
        $head=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory
        if($null-eq$head-or-not[bool]$head.ok-or[string]$head.entry.phase-cne'rollback-required'){return & $deny 'recovery-executor-rollback-head-drift-before-complete'}
        Invoke-CustomAppProductionBoundedRecoveryExecutorValidationHookV010 -Checkpoint 'before-rollback-complete-journal' -Context ([pscustomobject]@{journal=$head;apply=$apply})
        $done=Append-CustomAppProductionCrashJournalPhaseV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedRevision ([int64]$head.revision) -ExpectedEntrySha256 ([string]$head.entry.entry_sha256) -Phase 'rollback-complete' -Now $Now.AddMilliseconds(3)
        if($null-eq$done-or-not[bool]$done.ok){return & $deny ('recovery-executor-rollback-complete-journal-denied:'+[string]$done.reason)}
        $result=[pscustomobject]@{schema=1;managed_by=$CustomAppProductionBoundedRecoveryExecutorManagedBy;qualified_integration_head=$CustomAppProductionBoundedRecoveryExecutorQualifiedIntegrationHead;status='rollback-complete';reason='exact-rollback-and-recovery-apply-complete';transaction_id=$ExpectedTransactionId.Trim().ToLowerInvariant();name=[string]$e.name;initial_phase=$initialPhase;executor_class=$executorClass;final_phase='rollback-complete';evidence_fingerprint=[string]$e.evidence_fingerprint;integration_or_resume_fingerprint=[string]$rf.integration.integration_fingerprint;journal_start_revision=[int64]$initialJournal.revision;journal_end_revision=[int64]$done.revision;journal_end_sha256=[string]$done.entry.entry_sha256;rollback_required_recorded=$rollbackRecorded;exact_restore_executed=$true;recovery_apply_executed=$true;housekeeping_executed=$false;stage_cleanup_status='preserved';app_cleanup_status='preserved';persistence_cleanup_status='preserved';live_runtime_tree_sha256=[string]$full.tree_sha256;persistence_fingerprint=[string]$persist.fingerprint;cleanup_evidence_fingerprint=$CustomAppProductionBoundedRecoveryExecutorZeroHash;fixture_only_contract=$true;result_is_authority=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false;result_fingerprint=$null}
        $result.result_fingerprint=Get-CustomAppProductionBoundedRecoveryExecutorSha256V010 (Get-CustomAppProductionBoundedRecoveryExecutorResultMaterialV010 $result)
        return [pscustomobject]@{ok=$true;reason=[string]$result.reason;result=$result}
    }

    if($executorClass-ceq'idempotent-housekeeping'){
        $prepared=$(if($null-ne$resume){$resume.prepared}else{$fresh.evidence.prepared_result})
        $name=$(if($null-ne$resume){[string]$resume.evidence.name}else{[string]$fresh.evidence.name})
        if($initialPhase-ceq'apply-verified'){
            $stageStrict=Test-CustomAppProductionBoundedRecoveryStageOwnedArtifactV010 -Prepared $prepared -Name $name -AllowPartial:$false;if(-not[bool]$stageStrict.ok){return & $deny ([string]$stageStrict.reason)}
            $appStrict=Test-CustomAppProductionPostApplyAppBackupCleanupArtifactV010 -PreparedResult $prepared;if(-not[bool]$appStrict.ok){return & $deny ('recovery-executor-app-cleanup-precheck-denied:'+[string]$appStrict.reason)}
            $persistStrict=Test-CustomAppProductionPostApplyPersistenceCleanupArtifactV010 -PreparedResult $prepared;if(-not[bool]$persistStrict.ok){return & $deny ('recovery-executor-persistence-cleanup-precheck-denied:'+[string]$persistStrict.reason)}
            Invoke-CustomAppProductionBoundedRecoveryExecutorValidationHookV010 -Checkpoint 'before-cleanup-starting-journal' -Context ([pscustomobject]@{journal=$initialJournal;integration=$fresh.integration})
            $cs=Append-CustomAppProductionCrashJournalPhaseV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedRevision ([int64]$fresh.integration.journal_revision) -ExpectedEntrySha256 ([string]$fresh.integration.journal_entry_sha256) -Phase 'cleanup-starting' -Now $Now.AddMilliseconds(1)
            if($null-eq$cs-or-not[bool]$cs.ok){return & $deny ('recovery-executor-cleanup-starting-journal-denied:'+[string]$cs.reason)}
            Invoke-CustomAppProductionBoundedRecoveryExecutorValidationHookV010 -Checkpoint 'after-cleanup-starting-before-fresh-integration' -Context ([pscustomobject]@{journal=$cs})
            $fresh=Resolve-CustomAppProductionBoundedRecoveryFreshIntegrationV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $ExpectedTransactionId -SpicetifyAllowedRoot $SpicetifyAllowedRoot -SpicetifyPath $SpicetifyPath -ExpectedSpicetifySha256 $ExpectedSpicetifySha256 -Now $Now.AddMilliseconds(2)
            if(-not[bool]$fresh.ok){return & $deny ('recovery-executor-cleanup-starting-fresh-integration-denied:'+[string]$fresh.reason)}
            $resume=Resolve-CustomAppProductionBoundedRecoveryCleanupResumeGateV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $ExpectedTransactionId -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -Now $Now.AddMilliseconds(2)
            if(-not[bool]$resume.ok){return & $deny ('recovery-executor-cleanup-starting-resume-gate-denied:'+[string]$resume.reason)}
        }elseif($initialPhase-ceq'cleanup-starting'){
            if($null-eq$resume){$resume=Resolve-CustomAppProductionBoundedRecoveryCleanupResumeGateV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $ExpectedTransactionId -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -Now $Now;if(-not[bool]$resume.ok){return & $deny ('recovery-executor-cleanup-resume-denied:'+[string]$resume.reason)}}
        }else{return & $deny 'recovery-executor-housekeeping-phase-invalid'}
        $prepared=$resume.prepared;$name=[string]$resume.evidence.name
        $stage=Test-CustomAppProductionBoundedRecoveryStageOwnedArtifactV010 -Prepared $prepared -Name $name -AllowPartial:$true;if(-not[bool]$stage.ok){return & $deny ([string]$stage.reason)}
        $app=Test-CustomAppProductionBoundedRecoveryAppOwnedArtifactV010 -Prepared $prepared -AllowPartial:$true;if(-not[bool]$app.ok){return & $deny ([string]$app.reason)}
        $pb=Test-CustomAppProductionBoundedRecoveryPersistenceOwnedArtifactV010 -Prepared $prepared -AllowPartial:$true;if(-not[bool]$pb.ok){return & $deny ([string]$pb.reason)}
        $stageStatus=[string]$stage.status;$appStatus=[string]$app.status;$persistenceStatus=[string]$pb.status
        try{if($stageStatus-cne'already-absent'){$stageStatus=Remove-CustomAppProductionPostApplyBoundedArtifactV010 -Path ([string]$stage.path) -ExpectedRoot ([string]$stage.root) -ExpectedNamePattern '^[0-9a-fA-F]{32}$' -Label 'recovery-stage-workspace'}}catch{return & $deny ('recovery-executor-stage-cleanup-failed:'+[string]$_.Exception.Message)}
        Invoke-CustomAppProductionBoundedRecoveryExecutorValidationHookV010 -Checkpoint 'after-stage-cleanup' -Context ([pscustomobject]@{stage_status=$stageStatus;app_status=$appStatus;persistence_status=$persistenceStatus})
        try{if($appStatus-cne'already-absent'){$appStatus=Remove-CustomAppProductionPostApplyBoundedArtifactV010 -Path ([string]$app.path) -ExpectedRoot ([string]$app.root) -ExpectedNamePattern '^[0-9a-fA-F]{32}$' -Label 'recovery-app-backup'}}catch{return & $deny ('recovery-executor-app-cleanup-failed:'+[string]$_.Exception.Message)}
        Invoke-CustomAppProductionBoundedRecoveryExecutorValidationHookV010 -Checkpoint 'after-app-cleanup' -Context ([pscustomobject]@{stage_status=$stageStatus;app_status=$appStatus;persistence_status=$persistenceStatus})
        try{if($persistenceStatus-cne'already-absent'){$persistenceStatus=Remove-CustomAppProductionPostApplyBoundedArtifactV010 -Path ([string]$pb.path) -ExpectedRoot ([string]$pb.root) -ExpectedNamePattern '^txn-\d{8}-\d{6}-[0-9a-fA-F]{8}$' -Label 'recovery-persistence-backup'}}catch{return & $deny ('recovery-executor-persistence-cleanup-failed:'+[string]$_.Exception.Message)}
        Invoke-CustomAppProductionBoundedRecoveryExecutorValidationHookV010 -Checkpoint 'after-persistence-cleanup' -Context ([pscustomobject]@{stage_status=$stageStatus;app_status=$appStatus;persistence_status=$persistenceStatus})
        if(Test-Path -LiteralPath ([string]$prepared.stage_workspace_path)){return & $deny 'recovery-executor-stage-workspace-remained-after-cleanup'}
        if(Test-Path -LiteralPath ([IO.Path]::GetDirectoryName([string]$prepared.app_backup_path))){return & $deny 'recovery-executor-app-backup-remained-after-cleanup'}
        if(Test-Path -LiteralPath ([string]$prepared.persistence_backup_path)){return & $deny 'recovery-executor-persistence-backup-remained-after-cleanup'}
        try{$live=Get-CustomAppLocalRuntimeBaseline -Name $name -AppPath ([string]$resume.evidence.live_path);$persist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot}catch{return & $deny ('recovery-executor-post-cleanup-read-failed:'+[string]$_.Exception.Message)}
        if(-not[bool]$live.safe-or-not[bool]$live.installable-or(Test-CustomAppLocalRuntimeBaselineMutationAuthority $live)-or[string]$live.tree_sha256-cne[string]$prepared.stage_tree_sha256){return & $deny 'recovery-executor-post-cleanup-live-runtime-drift'}
        if([string]$persist.fingerprint-cne[string]$resume.evidence.persistence_fingerprint){return & $deny 'recovery-executor-post-cleanup-protected-persistence-drift'}
        $cleanupMaterial=@($ExpectedTransactionId.Trim().ToLowerInvariant(),[string]$resume.evidence.evidence_fingerprint,[string]$live.tree_sha256,[string]$persist.fingerprint,$stageStatus,$appStatus,$persistenceStatus)-join"`n"
        $cleanupFp=Get-CustomAppProductionBoundedRecoveryExecutorSha256V010 $cleanupMaterial
        $head=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory;if($null-eq$head-or-not[bool]$head.ok-or[string]$head.entry.phase-cne'cleanup-starting'){return & $deny 'recovery-executor-cleanup-head-drift-before-commit'}
        Invoke-CustomAppProductionBoundedRecoveryExecutorValidationHookV010 -Checkpoint 'before-committed-clean-journal' -Context ([pscustomobject]@{journal=$head;cleanup_fingerprint=$cleanupFp})
        $done=Append-CustomAppProductionCrashJournalPhaseV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedRevision ([int64]$head.revision) -ExpectedEntrySha256 ([string]$head.entry.entry_sha256) -Phase 'committed-clean' -CleanupResultFingerprint $cleanupFp -Now $Now.AddMilliseconds(3)
        if($null-eq$done-or-not[bool]$done.ok){return & $deny ('recovery-executor-committed-clean-journal-denied:'+[string]$done.reason)}
        $ioFp=$(if($null-ne$fresh-and[bool]$fresh.ok){[string]$fresh.integration.integration_fingerprint}else{[string]$resume.resume_fingerprint})
        $result=[pscustomobject]@{schema=1;managed_by=$CustomAppProductionBoundedRecoveryExecutorManagedBy;qualified_integration_head=$CustomAppProductionBoundedRecoveryExecutorQualifiedIntegrationHead;status='housekeeping-committed-clean';reason='bounded-idempotent-housekeeping-complete';transaction_id=$ExpectedTransactionId.Trim().ToLowerInvariant();name=$name;initial_phase=$initialPhase;executor_class='idempotent-housekeeping';final_phase='committed-clean';evidence_fingerprint=[string]$resume.evidence.evidence_fingerprint;integration_or_resume_fingerprint=$ioFp;journal_start_revision=[int64]$initialJournal.revision;journal_end_revision=[int64]$done.revision;journal_end_sha256=[string]$done.entry.entry_sha256;rollback_required_recorded=$false;exact_restore_executed=$false;recovery_apply_executed=$false;housekeeping_executed=$true;stage_cleanup_status=$stageStatus;app_cleanup_status=$appStatus;persistence_cleanup_status=$persistenceStatus;live_runtime_tree_sha256=[string]$live.tree_sha256;persistence_fingerprint=[string]$persist.fingerprint;cleanup_evidence_fingerprint=$cleanupFp;fixture_only_contract=$true;result_is_authority=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false;result_fingerprint=$null}
        $result.result_fingerprint=Get-CustomAppProductionBoundedRecoveryExecutorSha256V010 (Get-CustomAppProductionBoundedRecoveryExecutorResultMaterialV010 $result)
        return [pscustomobject]@{ok=$true;reason=[string]$result.reason;result=$result}
    }
    return & $deny ('recovery-executor-class-unsupported-'+$executorClass)
}
