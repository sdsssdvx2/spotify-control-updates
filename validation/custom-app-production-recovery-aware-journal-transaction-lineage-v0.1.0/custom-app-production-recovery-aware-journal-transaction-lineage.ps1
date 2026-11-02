$CustomAppProductionRecoveryAwareJournalTransactionLineageSchema = 1
$CustomAppProductionRecoveryAwareJournalTransactionLineageManagedBy = 'custom-app-production-recovery-aware-journal-transaction-lineage-v1'
$CustomAppProductionRecoveryAwareJournalTransactionLineageQualifiedPreApplyHead = '43f9a433354f56e2db19f4edfa1ffa8f4a245088'
$CustomAppProductionRecoveryAwareJournalTransactionLineageQualifiedPreApplyCoreBlob = 'eaad8a5f161f831bbbada1c1c0957a3dfc80edaa'
$CustomAppProductionRecoveryAwareJournalTransactionLineageQualifiedAtomicHead = 'c21a8c72dd8920df8e1faa59eb6aedee76a15e06'
$CustomAppProductionRecoveryAwareJournalTransactionLineageQualifiedAtomicCoreBlob = '55ca1e3c8d56b2e86a98d8b47e8ac1cc4ccbb6d0'
$CustomAppProductionRecoveryAwareJournalTransactionLineageQualifiedJournalHead = '7e26187e2360089024e9d72d0701be6f1577a1ef'
$CustomAppProductionRecoveryAwareJournalTransactionLineageFileName = 'transaction-lineage-v1.json'

function Get-CustomAppProductionRecoveryAwareJournalTransactionLineageSha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}
function Test-CustomAppProductionRecoveryAwareJournalTransactionLineageSha256V010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')
}
function Test-CustomAppProductionRecoveryAwareJournalTransactionLineageNonceV010 {
    param([AllowNull()][string]$Value)
    return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{32}$')
}
function Invoke-CustomAppProductionRecoveryAwareJournalTransactionLineageValidationHookV010 {
    param([Parameter(Mandatory=$true)][string]$Checkpoint,[Parameter(Mandatory=$true)]$Context)
    # Deliberate no-op. Validation harness may replace this function for bounded crash windows.
}
function New-CustomAppProductionRecoveryAwareJournalTransactionLineageDeniedV010 {
    param([Parameter(Mandatory=$true)][string]$Reason,[AllowNull()]$Lineage=$null,[AllowNull()]$Atomic=$null)
    return [pscustomobject]@{
        ok=$false;reason=$Reason;result=$null;lineage=$Lineage;atomic=$Atomic
        lineage_persisted=($null -ne $Lineage);requires_recovery=($null -ne $Atomic -and $Atomic.PSObject.Properties['requires_recovery'] -and [bool]$Atomic.requires_recovery)
        result_is_authority=$false;spicetify_apply_authorized=$false;additional_mutation_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false
    }
}
function Get-CustomAppProductionRecoveryAwareJournalTransactionLineageMaterialV010 {
    param([Parameter(Mandatory=$true)]$Envelope)
    return @(
        [string]$Envelope.schema,[string]$Envelope.managed_by,
        [string]$Envelope.qualified_recovery_aware_pre_apply_head,[string]$Envelope.qualified_recovery_aware_pre_apply_core_blob,
        [string]$Envelope.qualified_evidence_bound_atomic_head,[string]$Envelope.qualified_evidence_bound_atomic_core_blob,[string]$Envelope.qualified_crash_journal_head,
        [string]$Envelope.name,[string]$Envelope.source_identity,[string]$Envelope.remote_commit_sha,[string]$Envelope.consumption_id,
        [string]$Envelope.upstream_transaction_id,[string]$Envelope.crash_transaction_id,[string]$Envelope.transaction_nonce,[string]$Envelope.transaction_root,
        [string]$Envelope.recovery_aware_pre_apply_result_fingerprint,[string]$Envelope.generic_preparation_fingerprint,[string]$Envelope.generic_pre_apply_admission_fingerprint,[string]$Envelope.stage_result_fingerprint,
        [string]$Envelope.live_path,[string]$Envelope.stage_workspace_path,[string]$Envelope.stage_path,[string]$Envelope.app_backup_path,[string]$Envelope.app_backup_tree_sha256,[string]$Envelope.persistence_backup_path,[string]$Envelope.persistence_fingerprint,
        [string]$Envelope.source_prepared_at,[string]$Envelope.source_post_backup_revalidated_at,
        [string]$Envelope.append_only,[string]$Envelope.lineage_is_authority,[string]$Envelope.execution_authorized,[string]$Envelope.restore_authorized,[string]$Envelope.apply_authorized,[string]$Envelope.cleanup_authorized,[string]$Envelope.production_mutation_authorized
    ) -join "`n"
}
function Test-CustomAppProductionRecoveryAwareJournalTransactionLineageEnvelopeV010 {
    param([AllowNull()]$Envelope,[Parameter(Mandatory=$true)][string]$AllowedRoot)
    if($null -eq $Envelope){return [pscustomobject]@{ok=$false;reason='transaction-lineage-envelope-null'}}
    foreach($f in @(
        'schema','managed_by','qualified_recovery_aware_pre_apply_head','qualified_recovery_aware_pre_apply_core_blob','qualified_evidence_bound_atomic_head','qualified_evidence_bound_atomic_core_blob','qualified_crash_journal_head',
        'name','source_identity','remote_commit_sha','consumption_id','upstream_transaction_id','crash_transaction_id','transaction_nonce','transaction_root','recovery_aware_pre_apply_result_fingerprint','generic_preparation_fingerprint','generic_pre_apply_admission_fingerprint','stage_result_fingerprint',
        'live_path','stage_workspace_path','stage_path','app_backup_path','app_backup_tree_sha256','persistence_backup_path','persistence_fingerprint','source_prepared_at','source_post_backup_revalidated_at',
        'append_only','lineage_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized','lineage_fingerprint'
    )){if(-not $Envelope.PSObject.Properties[$f]){return [pscustomobject]@{ok=$false;reason=('transaction-lineage-field-missing-'+$f)}}}
    if([int]$Envelope.schema -ne $CustomAppProductionRecoveryAwareJournalTransactionLineageSchema -or [string]$Envelope.managed_by -cne $CustomAppProductionRecoveryAwareJournalTransactionLineageManagedBy){return [pscustomobject]@{ok=$false;reason='transaction-lineage-owner-schema-invalid'}}
    if([string]$Envelope.qualified_recovery_aware_pre_apply_head -cne $CustomAppProductionRecoveryAwareJournalTransactionLineageQualifiedPreApplyHead -or [string]$Envelope.qualified_recovery_aware_pre_apply_core_blob -cne $CustomAppProductionRecoveryAwareJournalTransactionLineageQualifiedPreApplyCoreBlob -or [string]$Envelope.qualified_evidence_bound_atomic_head -cne $CustomAppProductionRecoveryAwareJournalTransactionLineageQualifiedAtomicHead -or [string]$Envelope.qualified_evidence_bound_atomic_core_blob -cne $CustomAppProductionRecoveryAwareJournalTransactionLineageQualifiedAtomicCoreBlob -or [string]$Envelope.qualified_crash_journal_head -cne $CustomAppProductionRecoveryAwareJournalTransactionLineageQualifiedJournalHead){return [pscustomobject]@{ok=$false;reason='transaction-lineage-qualified-parent-invalid'}}
    if([string]::IsNullOrWhiteSpace([string]$Envelope.name) -or [string]$Envelope.source_identity -notmatch '^[a-z0-9_.-]+/[a-z0-9_.-]+$' -or [string]$Envelope.remote_commit_sha -notmatch '^[0-9a-f]{40}$'){return [pscustomobject]@{ok=$false;reason='transaction-lineage-identity-invalid'}}
    foreach($f in @('consumption_id','upstream_transaction_id','crash_transaction_id','recovery_aware_pre_apply_result_fingerprint','generic_preparation_fingerprint','generic_pre_apply_admission_fingerprint','stage_result_fingerprint','app_backup_tree_sha256','persistence_fingerprint','lineage_fingerprint')){if(-not(Test-CustomAppProductionRecoveryAwareJournalTransactionLineageSha256V010(([string]$Envelope.$f).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('transaction-lineage-sha-invalid-'+$f)}}}
    if(-not(Test-CustomAppProductionRecoveryAwareJournalTransactionLineageNonceV010 ([string]$Envelope.transaction_nonce))){return [pscustomobject]@{ok=$false;reason='transaction-lineage-nonce-invalid'}}
    foreach($f in @('transaction_root','live_path','stage_workspace_path','stage_path','app_backup_path','persistence_backup_path')){try{[void](Assert-CustomAppProductionCrashJournalPathV010 -AllowedRoot $AllowedRoot -Path ([string]$Envelope.$f) -Label ('transaction lineage '+$f))}catch{return [pscustomobject]@{ok=$false;reason=('transaction-lineage-path-invalid-'+$f+':' + [string]$_.Exception.Message)}}}
    $live=[IO.Path]::GetFullPath([string]$Envelope.live_path).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    $txn=[IO.Path]::GetFullPath([string]$Envelope.transaction_root).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    if(-not ([IO.Path]::GetDirectoryName($txn)).Equals([IO.Path]::GetDirectoryName($live),[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($txn) -notmatch '^\.spotify-control-txn-[0-9a-f]{32}$'){return [pscustomobject]@{ok=$false;reason='transaction-lineage-transaction-root-shape-invalid'}}
    $prepared=[DateTimeOffset]::MinValue;$post=[DateTimeOffset]::MinValue
    if(-not[DateTimeOffset]::TryParse([string]$Envelope.source_prepared_at,[ref]$prepared) -or -not[DateTimeOffset]::TryParse([string]$Envelope.source_post_backup_revalidated_at,[ref]$post) -or $post -lt $prepared){return [pscustomobject]@{ok=$false;reason='transaction-lineage-source-time-invalid'}}
    if(-not [bool]$Envelope.append_only){return [pscustomobject]@{ok=$false;reason='transaction-lineage-not-append-only'}}
    foreach($f in @('lineage_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){if([bool]$Envelope.$f){return [pscustomobject]@{ok=$false;reason=('transaction-lineage-authority-escaped-'+$f)}}}
    $expected=Get-CustomAppProductionRecoveryAwareJournalTransactionLineageSha256V010 (Get-CustomAppProductionRecoveryAwareJournalTransactionLineageMaterialV010 -Envelope $Envelope)
    if(([string]$Envelope.lineage_fingerprint).Trim().ToLowerInvariant() -cne $expected){return [pscustomobject]@{ok=$false;reason='transaction-lineage-fingerprint-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='transaction-lineage-envelope-valid-zero-authority';lineage_fingerprint=$expected;upstream_transaction_id=([string]$Envelope.upstream_transaction_id).Trim().ToLowerInvariant();crash_transaction_id=([string]$Envelope.crash_transaction_id).Trim().ToLowerInvariant()}
}
function New-CustomAppProductionRecoveryAwareJournalTransactionLineageEnvelopeV010 {
    param(
        [Parameter(Mandatory=$true)]$RecoveryAwarePreparedResult,[Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$LivePath,[Parameter(Mandatory=$true)][string]$TransactionNonce
    )
    $check=Test-CustomAppProductionRecoveryAwarePermitPreApplyPreparedResultV010 -Result $RecoveryAwarePreparedResult
    if(-not [bool]$check.ok){throw ('transaction-lineage-recovery-aware-prepared-invalid:'+[string]$check.reason)}
    $nameKey=$Name.Trim().ToLowerInvariant();if([string]::IsNullOrWhiteSpace($nameKey) -or ([string]$RecoveryAwarePreparedResult.name).Trim().ToLowerInvariant() -cne $nameKey){throw 'transaction-lineage-name-mismatch'}
    if(-not(Test-CustomAppProductionRecoveryAwareJournalTransactionLineageNonceV010 $TransactionNonce)){throw 'transaction-lineage-transaction-nonce-invalid'}
    $generic=ConvertTo-CustomAppProductionRecoveryAwarePermitGenericPreparedResultV010 -Result $RecoveryAwarePreparedResult
    $gc=Test-CustomAppProductionPreApplyPreparedResultV010 -Result $generic;if(-not [bool]$gc.ok){throw ('transaction-lineage-generic-prepared-invalid:'+[string]$gc.reason)}
    $txn=Get-CustomAppProductionJournalAwareAtomicTransactionRootV010 -LivePath $LivePath -TransactionNonce $TransactionNonce
    $identity=New-CustomAppProductionCrashJournalIdentityV010 -Name $Name -ConsumptionId ([string]$generic.consumption_id) -SourceIdentity ([string]$generic.source_identity) -RemoteCommitSha ([string]$generic.remote_commit_sha) -StageResultFingerprint ([string]$generic.stage_result_fingerprint) -PreparationFingerprint ([string]$generic.preparation_fingerprint) -AllowedRoot $AllowedRoot -LivePath $LivePath -TransactionRoot $txn -StageWorkspacePath ([string]$generic.stage_workspace_path) -AppBackupPath ([string]$generic.app_backup_path) -PersistenceBackupPath ([string]$generic.persistence_backup_path)
    $e=[pscustomobject]@{
        schema=$CustomAppProductionRecoveryAwareJournalTransactionLineageSchema;managed_by=$CustomAppProductionRecoveryAwareJournalTransactionLineageManagedBy
        qualified_recovery_aware_pre_apply_head=$CustomAppProductionRecoveryAwareJournalTransactionLineageQualifiedPreApplyHead;qualified_recovery_aware_pre_apply_core_blob=$CustomAppProductionRecoveryAwareJournalTransactionLineageQualifiedPreApplyCoreBlob
        qualified_evidence_bound_atomic_head=$CustomAppProductionRecoveryAwareJournalTransactionLineageQualifiedAtomicHead;qualified_evidence_bound_atomic_core_blob=$CustomAppProductionRecoveryAwareJournalTransactionLineageQualifiedAtomicCoreBlob;qualified_crash_journal_head=$CustomAppProductionRecoveryAwareJournalTransactionLineageQualifiedJournalHead
        name=$nameKey;source_identity=([string]$generic.source_identity).Trim().ToLowerInvariant();remote_commit_sha=([string]$generic.remote_commit_sha).Trim().ToLowerInvariant();consumption_id=([string]$generic.consumption_id).Trim().ToLowerInvariant()
        upstream_transaction_id=([string]$RecoveryAwarePreparedResult.transaction_id).Trim().ToLowerInvariant();crash_transaction_id=([string]$identity.transaction_id).Trim().ToLowerInvariant();transaction_nonce=$TransactionNonce.Trim().ToLowerInvariant();transaction_root=[string]$identity.transaction_root
        recovery_aware_pre_apply_result_fingerprint=([string]$RecoveryAwarePreparedResult.result_fingerprint).Trim().ToLowerInvariant();generic_preparation_fingerprint=([string]$generic.preparation_fingerprint).Trim().ToLowerInvariant();generic_pre_apply_admission_fingerprint=([string]$generic.pre_apply_admission_fingerprint).Trim().ToLowerInvariant();stage_result_fingerprint=([string]$generic.stage_result_fingerprint).Trim().ToLowerInvariant()
        live_path=[string]$identity.live_path;stage_workspace_path=[string]$identity.stage_workspace_path;stage_path=[string]$generic.stage_path;app_backup_path=[string]$identity.app_backup_path;app_backup_tree_sha256=([string]$generic.app_backup_tree_sha256).Trim().ToLowerInvariant();persistence_backup_path=[string]$identity.persistence_backup_path;persistence_fingerprint=([string]$generic.persistence_fingerprint).Trim().ToLowerInvariant()
        source_prepared_at=[string]$RecoveryAwarePreparedResult.prepared_at;source_post_backup_revalidated_at=[string]$RecoveryAwarePreparedResult.post_backup_revalidated_at
        append_only=$true;lineage_is_authority=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false;lineage_fingerprint=$null
    }
    $e.lineage_fingerprint=Get-CustomAppProductionRecoveryAwareJournalTransactionLineageSha256V010 (Get-CustomAppProductionRecoveryAwareJournalTransactionLineageMaterialV010 -Envelope $e)
    $ec=Test-CustomAppProductionRecoveryAwareJournalTransactionLineageEnvelopeV010 -Envelope $e -AllowedRoot $AllowedRoot;if(-not [bool]$ec.ok){throw ('transaction-lineage-envelope-self-check-failed:'+[string]$ec.reason)}
    return [pscustomobject]@{envelope=$e;generic_prepared=$generic;crash_identity=$identity}
}
function Get-CustomAppProductionRecoveryAwareJournalTransactionLineagePathV010 {
    param([Parameter(Mandatory=$true)]$Paths)
    return Join-Path ([string]$Paths.store) $CustomAppProductionRecoveryAwareJournalTransactionLineageFileName
}
function Read-CustomAppProductionRecoveryAwareJournalTransactionLineageFileUnlockedV010 {
    param([Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$Path)
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return [pscustomobject]@{ok=$false;reason='transaction-lineage-not-found';envelope=$null}}
    $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop;if(($item.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'transaction-lineage-file-reparse-point'};if($item.Length -gt 1048576){throw 'transaction-lineage-file-exceeds-1MiB'}
    $raw=[IO.File]::ReadAllText($Path,(New-Object Text.UTF8Encoding($false)));try{$e=$raw|ConvertFrom-Json}catch{throw 'transaction-lineage-json-invalid'}
    $c=Test-CustomAppProductionRecoveryAwareJournalTransactionLineageEnvelopeV010 -Envelope $e -AllowedRoot $AllowedRoot;if(-not[bool]$c.ok){throw ('transaction-lineage-envelope-invalid:'+[string]$c.reason)}
    return [pscustomobject]@{ok=$true;reason='transaction-lineage-read-valid';envelope=$e;lineage_fingerprint=[string]$c.lineage_fingerprint;path=$Path}
}
function Read-CustomAppProductionRecoveryAwareJournalTransactionLineageV010 {
    param([Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory)
    try{$paths=Get-CustomAppProductionCrashJournalPathsV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory}catch{return [pscustomobject]@{ok=$false;reason=('transaction-lineage-store-read-denied:'+[string]$_.Exception.Message);envelope=$null}}
    $lock=$null
    try{$lock=Open-CustomAppProductionCrashJournalLockV010 $paths;return Read-CustomAppProductionRecoveryAwareJournalTransactionLineageFileUnlockedV010 -AllowedRoot ([string]$paths.allowed_root) -Path (Get-CustomAppProductionRecoveryAwareJournalTransactionLineagePathV010 $paths)}catch{return [pscustomobject]@{ok=$false;reason=('transaction-lineage-read-denied:'+[string]$_.Exception.Message);envelope=$null}}finally{if($null-ne$lock){$lock.Dispose()}}
}
function Write-CustomAppProductionRecoveryAwareJournalTransactionLineageV010 {
    param([Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory,[Parameter(Mandatory=$true)]$Envelope)
    $deny={param([string]$Reason)[pscustomobject]@{ok=$false;reason=$Reason;persisted=$false;replayed=$false;envelope=$null;lineage_is_authority=$false;production_execution_authorized=$false;production_mutation_authorized=$false}}
    $check=Test-CustomAppProductionRecoveryAwareJournalTransactionLineageEnvelopeV010 -Envelope $Envelope -AllowedRoot $AllowedRoot;if(-not[bool]$check.ok){return & $deny ('transaction-lineage-write-envelope-denied:'+[string]$check.reason)}
    try{$paths=Get-CustomAppProductionCrashJournalPathsV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -Create:$true}catch{return & $deny ('transaction-lineage-store-create-denied:'+[string]$_.Exception.Message)}
    $path=Get-CustomAppProductionRecoveryAwareJournalTransactionLineagePathV010 $paths;$lock=$null
    try{
        $lock=Open-CustomAppProductionCrashJournalLockV010 $paths
        $journal=Read-CustomAppProductionCrashJournalUnlockedV010 -Paths $paths
        if([bool]$journal.ok){return & $deny 'transaction-lineage-journal-already-initialized-recovery-required'}
        if([string]$journal.reason -cne 'journal-uninitialized'){return & $deny ('transaction-lineage-journal-state-invalid:'+[string]$journal.reason)}
        if(Test-Path -LiteralPath $path){
            $existing=Read-CustomAppProductionRecoveryAwareJournalTransactionLineageFileUnlockedV010 -AllowedRoot ([string]$paths.allowed_root) -Path $path
            if(-not[bool]$existing.ok){return & $deny ([string]$existing.reason)}
            if(([string]$existing.lineage_fingerprint).Trim().ToLowerInvariant() -cne ([string]$Envelope.lineage_fingerprint).Trim().ToLowerInvariant()){return & $deny 'transaction-lineage-existing-binding-mismatch'}
            return [pscustomobject]@{ok=$true;reason='transaction-lineage-existing-exact-replay';persisted=$true;replayed=$true;envelope=$existing.envelope;lineage_fingerprint=[string]$existing.lineage_fingerprint;path=$path;lineage_is_authority=$false;production_execution_authorized=$false;production_mutation_authorized=$false}
        }
        $json=$Envelope|ConvertTo-Json -Depth 30 -Compress
        Write-CustomAppProductionCrashJournalDurableFileV010 -Path $path -Text $json -Mode ([IO.FileMode]::CreateNew)
        $verify=Read-CustomAppProductionRecoveryAwareJournalTransactionLineageFileUnlockedV010 -AllowedRoot ([string]$paths.allowed_root) -Path $path
        if(-not[bool]$verify.ok -or ([string]$verify.lineage_fingerprint).Trim().ToLowerInvariant() -cne ([string]$Envelope.lineage_fingerprint).Trim().ToLowerInvariant()){throw 'transaction-lineage-write-readback-mismatch'}
        return [pscustomobject]@{ok=$true;reason='transaction-lineage-created-durable-readback-verified';persisted=$true;replayed=$false;envelope=$verify.envelope;lineage_fingerprint=[string]$verify.lineage_fingerprint;path=$path;lineage_is_authority=$false;production_execution_authorized=$false;production_mutation_authorized=$false}
    }catch{return & $deny ('transaction-lineage-write-failed:'+[string]$_.Exception.Message)}finally{if($null-ne$lock){$lock.Dispose()}}
}
function Resolve-CustomAppProductionRecoveryAwareJournalTransactionLineageV010 {
    param(
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory,
        [Parameter(Mandatory=$true)][string]$ExpectedUpstreamTransactionId,[Parameter(Mandatory=$true)][string]$ExpectedCrashTransactionId,
        [AllowNull()][string]$ExpectedRecoveryAwarePreApplyResultFingerprint=$null
    )
    $r=Read-CustomAppProductionRecoveryAwareJournalTransactionLineageV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory
    if($null-eq$r -or -not[bool]$r.ok){return [pscustomobject]@{ok=$false;reason=('transaction-lineage-resolve-read-denied:'+[string]$r.reason);lineage_is_authority=$false;production_execution_authorized=$false;production_mutation_authorized=$false}}
    $e=$r.envelope
    if(([string]$e.upstream_transaction_id).Trim().ToLowerInvariant() -cne $ExpectedUpstreamTransactionId.Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason='transaction-lineage-upstream-transaction-mismatch';lineage_is_authority=$false;production_execution_authorized=$false;production_mutation_authorized=$false}}
    if(([string]$e.crash_transaction_id).Trim().ToLowerInvariant() -cne $ExpectedCrashTransactionId.Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason='transaction-lineage-crash-transaction-mismatch';lineage_is_authority=$false;production_execution_authorized=$false;production_mutation_authorized=$false}}
    if(-not[string]::IsNullOrWhiteSpace($ExpectedRecoveryAwarePreApplyResultFingerprint) -and ([string]$e.recovery_aware_pre_apply_result_fingerprint).Trim().ToLowerInvariant() -cne $ExpectedRecoveryAwarePreApplyResultFingerprint.Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason='transaction-lineage-recovery-aware-pre-apply-fingerprint-mismatch';lineage_is_authority=$false;production_execution_authorized=$false;production_mutation_authorized=$false}}
    return [pscustomobject]@{ok=$true;reason='transaction-lineage-exact-generation-transition-bound-zero-authority';envelope=$e;lineage_fingerprint=[string]$e.lineage_fingerprint;upstream_transaction_id=[string]$e.upstream_transaction_id;crash_transaction_id=[string]$e.crash_transaction_id;lineage_is_authority=$false;production_execution_authorized=$false;production_mutation_authorized=$false}
}
function Get-CustomAppProductionRecoveryAwareJournalTransactionLineageResultMaterialV010 {
    param([Parameter(Mandatory=$true)]$Result)
    return @(
        [string]$Result.schema,[string]$Result.managed_by,[string]$Result.status,[string]$Result.name,[string]$Result.upstream_transaction_id,[string]$Result.crash_transaction_id,[string]$Result.lineage_fingerprint,
        [string]$Result.recovery_aware_pre_apply_result_fingerprint,[string]$Result.generic_preparation_fingerprint,[string]$Result.atomic_result_fingerprint,[string]$Result.recovery_evidence_fingerprint,
        [string]$Result.lineage_persisted_before_journal,[string]$Result.crash_journal_initialized,[string]$Result.live_code_swap_performed,[string]$Result.requires_transaction_finalization,[string]$Result.requires_spicetify_apply_phase,
        [string]$Result.result_is_authority,[string]$Result.spicetify_apply_authorized,[string]$Result.additional_mutation_authorized,[string]$Result.production_execution_authorized,[string]$Result.production_mutation_authorized
    ) -join "`n"
}
function Test-CustomAppProductionRecoveryAwareJournalTransactionLineageResultV010 {
    param([AllowNull()]$Result)
    if($null-eq$Result){return [pscustomobject]@{ok=$false;reason='transaction-lineage-result-null'}}
    foreach($f in @('schema','managed_by','status','name','upstream_transaction_id','crash_transaction_id','lineage_fingerprint','recovery_aware_pre_apply_result_fingerprint','generic_preparation_fingerprint','atomic_result_fingerprint','recovery_evidence_fingerprint','lineage_persisted_before_journal','crash_journal_initialized','live_code_swap_performed','requires_transaction_finalization','requires_spicetify_apply_phase','result_is_authority','spicetify_apply_authorized','additional_mutation_authorized','production_execution_authorized','production_mutation_authorized','result_fingerprint')){if(-not$Result.PSObject.Properties[$f]){return [pscustomobject]@{ok=$false;reason=('transaction-lineage-result-field-missing-'+$f)}}}
    if([int]$Result.schema-ne1 -or [string]$Result.managed_by-cne$CustomAppProductionRecoveryAwareJournalTransactionLineageManagedBy -or [string]$Result.status-cne'recovery-aware-generation-lineage-bound-candidate-live'){return [pscustomobject]@{ok=$false;reason='transaction-lineage-result-owner-status-invalid'}}
    foreach($f in @('upstream_transaction_id','crash_transaction_id','lineage_fingerprint','recovery_aware_pre_apply_result_fingerprint','generic_preparation_fingerprint','atomic_result_fingerprint','recovery_evidence_fingerprint','result_fingerprint')){if(-not(Test-CustomAppProductionRecoveryAwareJournalTransactionLineageSha256V010(([string]$Result.$f).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('transaction-lineage-result-sha-invalid-'+$f)}}}
    foreach($f in @('lineage_persisted_before_journal','crash_journal_initialized','live_code_swap_performed','requires_transaction_finalization','requires_spicetify_apply_phase')){if(-not[bool]$Result.$f){return [pscustomobject]@{ok=$false;reason=('transaction-lineage-result-required-flag-false-'+$f)}}}
    foreach($f in @('result_is_authority','spicetify_apply_authorized','additional_mutation_authorized','production_execution_authorized','production_mutation_authorized')){if([bool]$Result.$f){return [pscustomobject]@{ok=$false;reason=('transaction-lineage-result-authority-escaped-'+$f)}}}
    $expected=Get-CustomAppProductionRecoveryAwareJournalTransactionLineageSha256V010 (Get-CustomAppProductionRecoveryAwareJournalTransactionLineageResultMaterialV010 -Result $Result)
    if(([string]$Result.result_fingerprint).Trim().ToLowerInvariant()-cne$expected){return [pscustomobject]@{ok=$false;reason='transaction-lineage-result-fingerprint-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='transaction-lineage-result-valid-zero-authority';result_fingerprint=$expected}
}
function Invoke-CustomAppProductionRecoveryAwareJournalTransactionLineageAtomicV010 {
    param(
        [Parameter(Mandatory=$true)]$RecoveryAwarePreparedResult,[Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$JournalStoreDirectory,[Parameter(Mandatory=$true)][string]$TransactionNonce,
        [Parameter(Mandatory=$true)][string]$LivePath,[Parameter(Mandatory=$true)][string]$ExpectedLiveFullTreeSha256,[Parameter(Mandatory=$true)][int]$ExpectedLiveFullFileCount,[Parameter(Mandatory=$true)][int64]$ExpectedLiveFullTotalBytes,
        [Parameter(Mandatory=$true)][string]$LocalAppDataRoot,[Parameter(Mandatory=$true)][string]$AppDataRoot,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow
    )
    $deny={param([string]$Reason,$Lineage=$null,$Atomic=$null) New-CustomAppProductionRecoveryAwareJournalTransactionLineageDeniedV010 -Reason $Reason -Lineage $Lineage -Atomic $Atomic}
    try{$built=New-CustomAppProductionRecoveryAwareJournalTransactionLineageEnvelopeV010 -RecoveryAwarePreparedResult $RecoveryAwarePreparedResult -Name $Name -AllowedRoot $AllowedRoot -LivePath $LivePath -TransactionNonce $TransactionNonce}catch{return & $deny ([string]$_.Exception.Message)}
    $e=$built.envelope;$g=$built.generic_prepared
    $write=Write-CustomAppProductionRecoveryAwareJournalTransactionLineageV010 -AllowedRoot $AllowedRoot -StoreDirectory $JournalStoreDirectory -Envelope $e
    if($null-eq$write -or -not[bool]$write.ok){return & $deny ('transaction-lineage-persistence-denied:'+[string]$write.reason)}
    $lineage=$write.envelope
    try{Invoke-CustomAppProductionRecoveryAwareJournalTransactionLineageValidationHookV010 -Checkpoint 'after-lineage-binding-before-journal-init' -Context ([pscustomobject]@{allowed_root=$AllowedRoot;store_directory=$JournalStoreDirectory;lineage=$lineage})}catch{return & $deny ('transaction-lineage-validation-hook-fault:'+[string]$_.Exception.Message) $lineage}
    $fresh=Read-CustomAppProductionRecoveryAwareJournalTransactionLineageV010 -AllowedRoot $AllowedRoot -StoreDirectory $JournalStoreDirectory
    if($null-eq$fresh -or -not[bool]$fresh.ok -or ([string]$fresh.lineage_fingerprint).Trim().ToLowerInvariant()-cne([string]$lineage.lineage_fingerprint).Trim().ToLowerInvariant()){return & $deny 'transaction-lineage-pre-journal-readback-drift' $lineage}
    $atomic=Invoke-CustomAppProductionEvidenceBoundJournalAtomicMutationV010 -GenericPreparedResult $g -Name $Name -CallerAdmissionManagedBy $CustomAppProductionRecoveryAwareJournalTransactionLineageManagedBy -CallerAdmissionFingerprint ([string]$lineage.lineage_fingerprint) -AllowedRoot $AllowedRoot -JournalStoreDirectory $JournalStoreDirectory -TransactionNonce $TransactionNonce -ConsumptionId ([string]$g.consumption_id) -SourceIdentity ([string]$g.source_identity) -RemoteCommitSha ([string]$g.remote_commit_sha) -StageResultFingerprint ([string]$g.stage_result_fingerprint) -PreparationFingerprint ([string]$g.preparation_fingerprint) -StageWorkspacePath ([string]$g.stage_workspace_path) -LivePath $LivePath -StagePath ([string]$g.stage_path) -ExpectedLiveRuntimeTreeSha256 ([string]$g.live_tree_sha256) -ExpectedLiveFullTreeSha256 $ExpectedLiveFullTreeSha256 -ExpectedLiveFullFileCount $ExpectedLiveFullFileCount -ExpectedLiveFullTotalBytes $ExpectedLiveFullTotalBytes -ExpectedStageRuntimeTreeSha256 ([string]$g.stage_tree_sha256) -AppBackupPath ([string]$g.app_backup_path) -ExpectedAppBackupTreeSha256 ([string]$g.app_backup_tree_sha256) -ExpectedAppBackupFileCount ([int]$g.app_backup_file_count) -ExpectedAppBackupTotalBytes ([int64]$g.app_backup_total_bytes) -PersistenceBackupPath ([string]$g.persistence_backup_path) -ExpectedPersistenceFingerprint ([string]$g.persistence_fingerprint) -LocalAppDataRoot $LocalAppDataRoot -AppDataRoot $AppDataRoot -Now $Now.AddMilliseconds(2)
    if($null-eq$atomic -or -not[bool]$atomic.ok){return & $deny ('transaction-lineage-qualified-atomic-denied:'+[string]$atomic.reason) $lineage $atomic}
    if(([string]$atomic.result.transaction_id).Trim().ToLowerInvariant()-cne([string]$lineage.crash_transaction_id).Trim().ToLowerInvariant()){return & $deny 'transaction-lineage-post-atomic-crash-transaction-drift' $lineage $atomic}
    $journal=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $AllowedRoot -StoreDirectory $JournalStoreDirectory
    if($null-eq$journal -or -not[bool]$journal.ok -or [string]$journal.entry.phase-cne'candidate-live' -or ([string]$journal.transaction_id).Trim().ToLowerInvariant()-cne([string]$lineage.crash_transaction_id).Trim().ToLowerInvariant()){return & $deny 'transaction-lineage-post-atomic-journal-drift' $lineage $atomic}
    $post=Resolve-CustomAppProductionRecoveryAwareJournalTransactionLineageV010 -AllowedRoot $AllowedRoot -StoreDirectory $JournalStoreDirectory -ExpectedUpstreamTransactionId ([string]$lineage.upstream_transaction_id) -ExpectedCrashTransactionId ([string]$journal.transaction_id) -ExpectedRecoveryAwarePreApplyResultFingerprint ([string]$RecoveryAwarePreparedResult.result_fingerprint)
    if($null-eq$post -or -not[bool]$post.ok){return & $deny ('transaction-lineage-post-atomic-binding-denied:'+[string]$post.reason) $lineage $atomic}
    $r=[pscustomobject]@{
        schema=$CustomAppProductionRecoveryAwareJournalTransactionLineageSchema;managed_by=$CustomAppProductionRecoveryAwareJournalTransactionLineageManagedBy;status='recovery-aware-generation-lineage-bound-candidate-live';name=$Name.Trim().ToLowerInvariant()
        upstream_transaction_id=[string]$lineage.upstream_transaction_id;crash_transaction_id=[string]$lineage.crash_transaction_id;lineage_fingerprint=[string]$lineage.lineage_fingerprint;recovery_aware_pre_apply_result_fingerprint=([string]$RecoveryAwarePreparedResult.result_fingerprint).Trim().ToLowerInvariant();generic_preparation_fingerprint=([string]$g.preparation_fingerprint).Trim().ToLowerInvariant();atomic_result_fingerprint=([string]$atomic.result.result_fingerprint).Trim().ToLowerInvariant();recovery_evidence_fingerprint=([string]$atomic.result.recovery_evidence_fingerprint).Trim().ToLowerInvariant()
        lineage_persisted_before_journal=$true;crash_journal_initialized=$true;live_code_swap_performed=$true;requires_transaction_finalization=$true;requires_spicetify_apply_phase=$true
        result_is_authority=$false;spicetify_apply_authorized=$false;additional_mutation_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false;result_fingerprint=$null
    }
    $r.result_fingerprint=Get-CustomAppProductionRecoveryAwareJournalTransactionLineageSha256V010 (Get-CustomAppProductionRecoveryAwareJournalTransactionLineageResultMaterialV010 -Result $r)
    $rc=Test-CustomAppProductionRecoveryAwareJournalTransactionLineageResultV010 -Result $r;if(-not[bool]$rc.ok){return & $deny ('transaction-lineage-result-self-check-denied:'+[string]$rc.reason) $lineage $atomic}
    return [pscustomobject]@{ok=$true;reason='recovery-aware-upstream-to-crash-transaction-lineage-bound-before-live-mutation';result=$r;lineage=$lineage;atomic=$atomic;lineage_persisted=$true;requires_recovery=$false;result_is_authority=$false;spicetify_apply_authorized=$false;additional_mutation_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false}
}
