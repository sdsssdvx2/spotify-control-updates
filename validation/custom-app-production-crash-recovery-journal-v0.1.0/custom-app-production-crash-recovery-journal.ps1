$CustomAppProductionCrashRecoveryJournalSchema = 1
$CustomAppProductionCrashRecoveryJournalManagedBy = 'custom-app-production-crash-recovery-journal-v1'
$CustomAppProductionCrashRecoveryJournalQualifiedCleanupHead = '67458cbb96b5d1ed92e26c2b81debd6894044749'
$CustomAppProductionCrashRecoveryJournalZeroHash = ('0' * 64)
$CustomAppProductionCrashRecoveryJournalPhases = @(
    'prepared','atomic-mutation-starting','live-moved-to-old','candidate-live','transaction-finalized',
    'apply-starting','apply-returned-success-pending-verification','apply-verified','cleanup-starting','committed-clean',
    'rollback-required','rollback-complete'
)

function Get-CustomAppProductionCrashJournalSha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}
function Test-CustomAppProductionCrashJournalSha256V010 { param([AllowNull()][string]$Value) return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$') }
function Test-CustomAppProductionCrashJournalCommitV010 { param([AllowNull()][string]$Value) return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{40}$') }
function Test-CustomAppProductionCrashJournalSourceV010 { param([AllowNull()][string]$Value) return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value.Trim().ToLowerInvariant() -cmatch '^[a-z0-9_.-]+/[a-z0-9_.-]+$') }

function Get-CustomAppProductionCrashJournalCanonicalPathV010 {
    param([Parameter(Mandatory=$true)][string]$Path)
    if([string]::IsNullOrWhiteSpace($Path)){throw 'crash-journal-path-empty'}
    return [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
}
function Test-CustomAppProductionCrashJournalWithinV010 {
    param([Parameter(Mandatory=$true)][string]$Root,[Parameter(Mandatory=$true)][string]$Path,[bool]$AllowRoot=$false)
    $r=Get-CustomAppProductionCrashJournalCanonicalPathV010 $Root;$p=Get-CustomAppProductionCrashJournalCanonicalPathV010 $Path
    if($p.Equals($r,[StringComparison]::OrdinalIgnoreCase)){return $AllowRoot}
    return $p.StartsWith($r+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)
}
function Assert-CustomAppProductionCrashJournalPathV010 {
    param([Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$Path,[string]$Label='path',[bool]$AllowRoot=$false,[bool]$RequireExisting=$false)
    $root=Get-CustomAppProductionCrashJournalCanonicalPathV010 $AllowedRoot;$target=Get-CustomAppProductionCrashJournalCanonicalPathV010 $Path
    if(-not (Test-Path -LiteralPath $root -PathType Container)){throw "$Label allowed root missing"}
    $ri=Get-Item -LiteralPath $root -Force -ErrorAction Stop;if(($ri.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw "$Label allowed root reparse point"}
    if(-not (Test-CustomAppProductionCrashJournalWithinV010 -Root $root -Path $target -AllowRoot:$AllowRoot)){throw "$Label escaped allowed root"}
    $probe=$target
    while(-not $probe.Equals($root,[StringComparison]::OrdinalIgnoreCase)){
        if(Test-Path -LiteralPath $probe){$item=Get-Item -LiteralPath $probe -Force -ErrorAction Stop;if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw "$Label contains reparse-point ancestor"}}
        $parent=[IO.Directory]::GetParent($probe);if($null -eq $parent){throw "$Label parent chain escaped allowed root"};$probe=$parent.FullName
        if(-not ($probe.Equals($root,[StringComparison]::OrdinalIgnoreCase) -or $probe.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase))){throw "$Label parent chain escaped allowed root"}
    }
    if($RequireExisting -and -not (Test-Path -LiteralPath $target)){throw "$Label missing"}
    return $target
}

function Get-CustomAppProductionCrashJournalIdentityMaterialV010 {
    param([Parameter(Mandatory=$true)]$Identity)
    return @(
        [string]$Identity.name,[string]$Identity.consumption_id,[string]$Identity.source_identity,[string]$Identity.remote_commit_sha,
        [string]$Identity.stage_result_fingerprint,[string]$Identity.preparation_fingerprint,[string]$Identity.live_path,[string]$Identity.transaction_root,
        [string]$Identity.stage_workspace_path,[string]$Identity.app_backup_path,[string]$Identity.persistence_backup_path
    ) -join "`n"
}
function New-CustomAppProductionCrashJournalIdentityV010 {
    param(
        [Parameter(Mandatory=$true)][string]$Name,[Parameter(Mandatory=$true)][string]$ConsumptionId,[Parameter(Mandatory=$true)][string]$SourceIdentity,
        [Parameter(Mandatory=$true)][string]$RemoteCommitSha,[Parameter(Mandatory=$true)][string]$StageResultFingerprint,[Parameter(Mandatory=$true)][string]$PreparationFingerprint,
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$LivePath,[Parameter(Mandatory=$true)][string]$TransactionRoot,
        [Parameter(Mandatory=$true)][string]$StageWorkspacePath,[Parameter(Mandatory=$true)][string]$AppBackupPath,[Parameter(Mandatory=$true)][string]$PersistenceBackupPath
    )
    $nameKey=$Name.Trim().ToLowerInvariant();$source=$SourceIdentity.Trim().ToLowerInvariant();$commit=$RemoteCommitSha.Trim().ToLowerInvariant();$cid=$ConsumptionId.Trim().ToLowerInvariant();$stage=$StageResultFingerprint.Trim().ToLowerInvariant();$prep=$PreparationFingerprint.Trim().ToLowerInvariant()
    if([string]::IsNullOrWhiteSpace($nameKey) -or -not (Test-CustomAppProductionCrashJournalSourceV010 $source) -or -not (Test-CustomAppProductionCrashJournalCommitV010 $commit)){throw 'crash-journal identity name/source/commit invalid'}
    foreach($v in @($cid,$stage,$prep)){if(-not (Test-CustomAppProductionCrashJournalSha256V010 $v)){throw 'crash-journal identity sha256 invalid'}}
    $live=Assert-CustomAppProductionCrashJournalPathV010 -AllowedRoot $AllowedRoot -Path $LivePath -Label 'live path'
    $txn=Assert-CustomAppProductionCrashJournalPathV010 -AllowedRoot $AllowedRoot -Path $TransactionRoot -Label 'transaction root'
    $stagePath=Assert-CustomAppProductionCrashJournalPathV010 -AllowedRoot $AllowedRoot -Path $StageWorkspacePath -Label 'stage workspace'
    $app=Assert-CustomAppProductionCrashJournalPathV010 -AllowedRoot $AllowedRoot -Path $AppBackupPath -Label 'app backup'
    $persist=Assert-CustomAppProductionCrashJournalPathV010 -AllowedRoot $AllowedRoot -Path $PersistenceBackupPath -Label 'persistence backup'
    $identity=[pscustomobject]@{name=$nameKey;consumption_id=$cid;source_identity=$source;remote_commit_sha=$commit;stage_result_fingerprint=$stage;preparation_fingerprint=$prep;live_path=$live;transaction_root=$txn;stage_workspace_path=$stagePath;app_backup_path=$app;persistence_backup_path=$persist;transaction_id=$null}
    $identity.transaction_id=Get-CustomAppProductionCrashJournalSha256V010 (Get-CustomAppProductionCrashJournalIdentityMaterialV010 $identity)
    return $identity
}
function Test-CustomAppProductionCrashJournalIdentityV010 {
    param([AllowNull()]$Identity,[Parameter(Mandatory=$true)][string]$AllowedRoot)
    if($null -eq $Identity){return [pscustomobject]@{ok=$false;reason='identity-null'}}
    foreach($f in @('name','consumption_id','source_identity','remote_commit_sha','stage_result_fingerprint','preparation_fingerprint','live_path','transaction_root','stage_workspace_path','app_backup_path','persistence_backup_path','transaction_id')){if(-not $Identity.PSObject.Properties[$f]){return [pscustomobject]@{ok=$false;reason=('identity-required-field-missing-'+$f)}}}
    if([string]::IsNullOrWhiteSpace([string]$Identity.name) -or -not (Test-CustomAppProductionCrashJournalSourceV010 ([string]$Identity.source_identity)) -or -not (Test-CustomAppProductionCrashJournalCommitV010 ([string]$Identity.remote_commit_sha))){return [pscustomobject]@{ok=$false;reason='identity-name-source-or-commit-invalid'}}
    foreach($f in @('consumption_id','stage_result_fingerprint','preparation_fingerprint','transaction_id')){if(-not (Test-CustomAppProductionCrashJournalSha256V010 (([string]$Identity.$f).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('identity-invalid-'+$f)}}}
    try{foreach($f in @('live_path','transaction_root','stage_workspace_path','app_backup_path','persistence_backup_path')){[void](Assert-CustomAppProductionCrashJournalPathV010 -AllowedRoot $AllowedRoot -Path ([string]$Identity.$f) -Label ('identity '+$f))}}catch{return [pscustomobject]@{ok=$false;reason=('identity-path-invalid:'+[string]$_.Exception.Message)}}
    $copy=[pscustomobject]@{name=([string]$Identity.name).Trim().ToLowerInvariant();consumption_id=([string]$Identity.consumption_id).Trim().ToLowerInvariant();source_identity=([string]$Identity.source_identity).Trim().ToLowerInvariant();remote_commit_sha=([string]$Identity.remote_commit_sha).Trim().ToLowerInvariant();stage_result_fingerprint=([string]$Identity.stage_result_fingerprint).Trim().ToLowerInvariant();preparation_fingerprint=([string]$Identity.preparation_fingerprint).Trim().ToLowerInvariant();live_path=(Get-CustomAppProductionCrashJournalCanonicalPathV010 ([string]$Identity.live_path));transaction_root=(Get-CustomAppProductionCrashJournalCanonicalPathV010 ([string]$Identity.transaction_root));stage_workspace_path=(Get-CustomAppProductionCrashJournalCanonicalPathV010 ([string]$Identity.stage_workspace_path));app_backup_path=(Get-CustomAppProductionCrashJournalCanonicalPathV010 ([string]$Identity.app_backup_path));persistence_backup_path=(Get-CustomAppProductionCrashJournalCanonicalPathV010 ([string]$Identity.persistence_backup_path));transaction_id=$null}
    $expected=Get-CustomAppProductionCrashJournalSha256V010 (Get-CustomAppProductionCrashJournalIdentityMaterialV010 $copy)
    if(([string]$Identity.transaction_id).Trim().ToLowerInvariant() -cne $expected){return [pscustomobject]@{ok=$false;reason='identity-transaction-id-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='identity-valid';transaction_id=$expected;identity=$copy}
}

function Get-CustomAppProductionCrashJournalEntryMaterialV010 {
    param([Parameter(Mandatory=$true)]$Entry)
    return @(
        [string]$Entry.schema,[string]$Entry.managed_by,[string]$Entry.qualified_cleanup_head,[string]$Entry.transaction_id,[string]$Entry.revision,[string]$Entry.previous_entry_sha256,
        [string]$Entry.phase,[string]$Entry.name,[string]$Entry.consumption_id,[string]$Entry.source_identity,[string]$Entry.remote_commit_sha,[string]$Entry.stage_result_fingerprint,[string]$Entry.preparation_fingerprint,
        [string]$Entry.finalization_fingerprint,[string]$Entry.apply_result_fingerprint,[string]$Entry.cleanup_result_fingerprint,[string]$Entry.live_path,[string]$Entry.transaction_root,[string]$Entry.stage_workspace_path,[string]$Entry.app_backup_path,[string]$Entry.persistence_backup_path,
        [string]$Entry.recorded_at,[string]$Entry.append_only,[string]$Entry.requires_journal_phase_before_side_effect,[string]$Entry.journal_is_authority,[string]$Entry.production_execution_authorized,[string]$Entry.production_mutation_authorized
    ) -join "`n"
}
function New-CustomAppProductionCrashJournalEntryV010 {
    param(
        [Parameter(Mandatory=$true)]$Identity,[Parameter(Mandatory=$true)][int64]$Revision,[Parameter(Mandatory=$true)][string]$PreviousEntrySha256,
        [Parameter(Mandatory=$true)][ValidateSet('prepared','atomic-mutation-starting','live-moved-to-old','candidate-live','transaction-finalized','apply-starting','apply-returned-success-pending-verification','apply-verified','cleanup-starting','committed-clean','rollback-required','rollback-complete')][string]$Phase,
        [AllowNull()][string]$FinalizationFingerprint=$null,[AllowNull()][string]$ApplyResultFingerprint=$null,[AllowNull()][string]$CleanupResultFingerprint=$null,[DateTimeOffset]$RecordedAt=[DateTimeOffset]::UtcNow
    )
    $zero=$CustomAppProductionCrashRecoveryJournalZeroHash
    $final=if([string]::IsNullOrWhiteSpace($FinalizationFingerprint)){$zero}else{$FinalizationFingerprint.Trim().ToLowerInvariant()}
    $apply=if([string]::IsNullOrWhiteSpace($ApplyResultFingerprint)){$zero}else{$ApplyResultFingerprint.Trim().ToLowerInvariant()}
    $cleanup=if([string]::IsNullOrWhiteSpace($CleanupResultFingerprint)){$zero}else{$CleanupResultFingerprint.Trim().ToLowerInvariant()}
    foreach($v in @($PreviousEntrySha256.Trim().ToLowerInvariant(),$final,$apply,$cleanup)){if(-not (Test-CustomAppProductionCrashJournalSha256V010 $v)){throw 'crash-journal entry sha256 field invalid'}}
    $e=[pscustomobject]@{schema=$CustomAppProductionCrashRecoveryJournalSchema;managed_by=$CustomAppProductionCrashRecoveryJournalManagedBy;qualified_cleanup_head=$CustomAppProductionCrashRecoveryJournalQualifiedCleanupHead;transaction_id=[string]$Identity.transaction_id;revision=$Revision;previous_entry_sha256=$PreviousEntrySha256.Trim().ToLowerInvariant();phase=$Phase;name=[string]$Identity.name;consumption_id=[string]$Identity.consumption_id;source_identity=[string]$Identity.source_identity;remote_commit_sha=[string]$Identity.remote_commit_sha;stage_result_fingerprint=[string]$Identity.stage_result_fingerprint;preparation_fingerprint=[string]$Identity.preparation_fingerprint;finalization_fingerprint=$final;apply_result_fingerprint=$apply;cleanup_result_fingerprint=$cleanup;live_path=[string]$Identity.live_path;transaction_root=[string]$Identity.transaction_root;stage_workspace_path=[string]$Identity.stage_workspace_path;app_backup_path=[string]$Identity.app_backup_path;persistence_backup_path=[string]$Identity.persistence_backup_path;recorded_at=$RecordedAt.ToUniversalTime().ToString('o');append_only=$true;requires_journal_phase_before_side_effect=$true;journal_is_authority=$false;production_execution_authorized=$false;production_mutation_authorized=$false;entry_sha256=$null}
    $e.entry_sha256=Get-CustomAppProductionCrashJournalSha256V010 (Get-CustomAppProductionCrashJournalEntryMaterialV010 $e)
    return $e
}
function Test-CustomAppProductionCrashJournalEntryV010 {
    param([AllowNull()]$Entry,[Parameter(Mandatory=$true)][string]$AllowedRoot)
    if($null -eq $Entry){return [pscustomobject]@{ok=$false;reason='entry-null'}}
    $required=@('schema','managed_by','qualified_cleanup_head','transaction_id','revision','previous_entry_sha256','phase','name','consumption_id','source_identity','remote_commit_sha','stage_result_fingerprint','preparation_fingerprint','finalization_fingerprint','apply_result_fingerprint','cleanup_result_fingerprint','live_path','transaction_root','stage_workspace_path','app_backup_path','persistence_backup_path','recorded_at','append_only','requires_journal_phase_before_side_effect','journal_is_authority','production_execution_authorized','production_mutation_authorized','entry_sha256')
    foreach($f in $required){if(-not $Entry.PSObject.Properties[$f]){return [pscustomobject]@{ok=$false;reason=('entry-required-field-missing-'+$f)}}}
    if([int]$Entry.schema -ne $CustomAppProductionCrashRecoveryJournalSchema -or [string]$Entry.managed_by -cne $CustomAppProductionCrashRecoveryJournalManagedBy -or [string]$Entry.qualified_cleanup_head -cne $CustomAppProductionCrashRecoveryJournalQualifiedCleanupHead){return [pscustomobject]@{ok=$false;reason='entry-owner-schema-parent-mismatch'}}
    if([string]$Entry.phase -notin $CustomAppProductionCrashRecoveryJournalPhases){return [pscustomobject]@{ok=$false;reason='entry-phase-invalid'}}
    if(-not [bool]$Entry.append_only -or -not [bool]$Entry.requires_journal_phase_before_side_effect -or [bool]$Entry.journal_is_authority -or [bool]$Entry.production_execution_authorized -or [bool]$Entry.production_mutation_authorized){return [pscustomobject]@{ok=$false;reason='entry-authority-or-ordering-contract-invalid'}}
    foreach($f in @('transaction_id','consumption_id','stage_result_fingerprint','preparation_fingerprint','finalization_fingerprint','apply_result_fingerprint','cleanup_result_fingerprint','previous_entry_sha256','entry_sha256')){if(-not (Test-CustomAppProductionCrashJournalSha256V010 (([string]$Entry.$f).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('entry-invalid-'+$f)}}}
    if(-not (Test-CustomAppProductionCrashJournalSourceV010 ([string]$Entry.source_identity)) -or -not (Test-CustomAppProductionCrashJournalCommitV010 ([string]$Entry.remote_commit_sha))){return [pscustomobject]@{ok=$false;reason='entry-source-or-commit-invalid'}}
    try{$rev=[int64]$Entry.revision}catch{return [pscustomobject]@{ok=$false;reason='entry-revision-invalid'}};if($rev -lt 0){return [pscustomobject]@{ok=$false;reason='entry-revision-negative'}}
    $when=[DateTimeOffset]::MinValue;if(-not [DateTimeOffset]::TryParse([string]$Entry.recorded_at,[ref]$when)){return [pscustomobject]@{ok=$false;reason='entry-time-invalid'}}
    try{foreach($f in @('live_path','transaction_root','stage_workspace_path','app_backup_path','persistence_backup_path')){[void](Assert-CustomAppProductionCrashJournalPathV010 -AllowedRoot $AllowedRoot -Path ([string]$Entry.$f) -Label ('entry '+$f))}}catch{return [pscustomobject]@{ok=$false;reason=('entry-path-invalid:'+[string]$_.Exception.Message)}}
    $identity=[pscustomobject]@{name=([string]$Entry.name).Trim().ToLowerInvariant();consumption_id=([string]$Entry.consumption_id).Trim().ToLowerInvariant();source_identity=([string]$Entry.source_identity).Trim().ToLowerInvariant();remote_commit_sha=([string]$Entry.remote_commit_sha).Trim().ToLowerInvariant();stage_result_fingerprint=([string]$Entry.stage_result_fingerprint).Trim().ToLowerInvariant();preparation_fingerprint=([string]$Entry.preparation_fingerprint).Trim().ToLowerInvariant();live_path=(Get-CustomAppProductionCrashJournalCanonicalPathV010 ([string]$Entry.live_path));transaction_root=(Get-CustomAppProductionCrashJournalCanonicalPathV010 ([string]$Entry.transaction_root));stage_workspace_path=(Get-CustomAppProductionCrashJournalCanonicalPathV010 ([string]$Entry.stage_workspace_path));app_backup_path=(Get-CustomAppProductionCrashJournalCanonicalPathV010 ([string]$Entry.app_backup_path));persistence_backup_path=(Get-CustomAppProductionCrashJournalCanonicalPathV010 ([string]$Entry.persistence_backup_path));transaction_id=$null}
    $tx=Get-CustomAppProductionCrashJournalSha256V010 (Get-CustomAppProductionCrashJournalIdentityMaterialV010 $identity);if(([string]$Entry.transaction_id).Trim().ToLowerInvariant() -cne $tx){return [pscustomobject]@{ok=$false;reason='entry-transaction-identity-mismatch'}}
    $zero=$CustomAppProductionCrashRecoveryJournalZeroHash
    if([string]$Entry.phase -in @('transaction-finalized','apply-starting','apply-returned-success-pending-verification','apply-verified','cleanup-starting','committed-clean') -and [string]$Entry.finalization_fingerprint -ceq $zero){return [pscustomobject]@{ok=$false;reason='entry-finalization-evidence-required'}}
    if([string]$Entry.phase -in @('apply-verified','cleanup-starting','committed-clean') -and [string]$Entry.apply_result_fingerprint -ceq $zero){return [pscustomobject]@{ok=$false;reason='entry-apply-evidence-required'}}
    if([string]$Entry.phase -ceq 'committed-clean' -and [string]$Entry.cleanup_result_fingerprint -ceq $zero){return [pscustomobject]@{ok=$false;reason='entry-cleanup-evidence-required'}}
    $expected=Get-CustomAppProductionCrashJournalSha256V010 (Get-CustomAppProductionCrashJournalEntryMaterialV010 $Entry);if(([string]$Entry.entry_sha256).Trim().ToLowerInvariant() -cne $expected){return [pscustomobject]@{ok=$false;reason='entry-sha256-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='entry-valid-non-authoritative';revision=$rev;entry_sha256=$expected;recorded_at=$when;transaction_id=$tx}
}

function Test-CustomAppProductionCrashJournalTransitionV010 {
    param([Parameter(Mandatory=$true)][string]$From,[Parameter(Mandatory=$true)][string]$To)
    $allowed=@{
        'prepared'=@('atomic-mutation-starting','rollback-required');
        'atomic-mutation-starting'=@('live-moved-to-old','rollback-required');
        'live-moved-to-old'=@('candidate-live','rollback-required');
        'candidate-live'=@('transaction-finalized','rollback-required');
        'transaction-finalized'=@('apply-starting','rollback-required');
        'apply-starting'=@('apply-returned-success-pending-verification','rollback-required');
        'apply-returned-success-pending-verification'=@('apply-verified','rollback-required');
        'apply-verified'=@('cleanup-starting');
        'cleanup-starting'=@('committed-clean');
        'rollback-required'=@('rollback-complete');
        'committed-clean'=@();'rollback-complete'=@()
    }
    return ($allowed.ContainsKey($From) -and $To -in @($allowed[$From]))
}

function Get-CustomAppProductionCrashJournalPathsV010 {
    param([Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory,[bool]$Create=$false)
    $root=Get-CustomAppProductionCrashJournalCanonicalPathV010 $AllowedRoot;if(-not (Test-Path -LiteralPath $root -PathType Container)){throw 'journal allowed root missing'}
    $store=Assert-CustomAppProductionCrashJournalPathV010 -AllowedRoot $root -Path $StoreDirectory -Label 'journal store'
    if($Create -and -not (Test-Path -LiteralPath $store)){[IO.Directory]::CreateDirectory($store)|Out-Null}
    $store=Assert-CustomAppProductionCrashJournalPathV010 -AllowedRoot $root -Path $store -Label 'journal store' -RequireExisting:$true
    if(-not (Test-Path -LiteralPath $store -PathType Container)){throw 'journal store not directory'}
    $history=Join-Path $store 'history';if($Create -and -not (Test-Path -LiteralPath $history)){[IO.Directory]::CreateDirectory($history)|Out-Null}
    $history=Assert-CustomAppProductionCrashJournalPathV010 -AllowedRoot $root -Path $history -Label 'journal history' -RequireExisting:$true;if(-not (Test-Path -LiteralPath $history -PathType Container)){throw 'journal history not directory'}
    return [pscustomobject]@{allowed_root=$root;store=$store;history=$history;current=(Join-Path $store 'current.json');lock=(Join-Path $store '.journal.lock')}
}
function Open-CustomAppProductionCrashJournalLockV010 { param([Parameter(Mandatory=$true)]$Paths) try{return [IO.File]::Open([string]$Paths.lock,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch [IO.IOException]{throw 'crash-journal-lock-busy'} }
function Write-CustomAppProductionCrashJournalDurableFileV010 {
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][string]$Text,[Parameter(Mandatory=$true)][IO.FileMode]$Mode)
    $bytes=(New-Object Text.UTF8Encoding($false)).GetBytes($Text);$s=$null
    try{$s=[IO.File]::Open($Path,$Mode,[IO.FileAccess]::Write,[IO.FileShare]::None);$s.Write($bytes,0,$bytes.Length);$s.Flush($true)}finally{if($null -ne $s){$s.Dispose()}}
}
function ConvertFrom-CustomAppProductionCrashJournalFileV010 {
    param([Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$Path)
    $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop;if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw 'journal file reparse point'};if($item.Length -gt 4194304){throw 'journal file exceeds 4 MiB'}
    $raw=[IO.File]::ReadAllText($Path,(New-Object Text.UTF8Encoding($false)));try{$e=$raw|ConvertFrom-Json}catch{throw 'journal JSON invalid'};$check=Test-CustomAppProductionCrashJournalEntryV010 -Entry $e -AllowedRoot $AllowedRoot;if(-not [bool]$check.ok){throw ('journal entry invalid: '+[string]$check.reason)}
    return [pscustomobject]@{entry=$e;check=$check;raw=$raw}
}
function Read-CustomAppProductionCrashJournalUnlockedV010 {
    param([Parameter(Mandatory=$true)]$Paths)
    $files=@(Get-ChildItem -LiteralPath ([string]$Paths.history) -File -Filter '*.json' -Force | Sort-Object Name)
    if($files.Count -eq 0){if(Test-Path -LiteralPath ([string]$Paths.current)){throw 'journal-current-without-history'};return [pscustomobject]@{ok=$false;reason='journal-uninitialized';revision=[int64]-1;entry=$null;history_count=0}}
    $rev=[int64]0;$prev=$CustomAppProductionCrashRecoveryJournalZeroHash;$latest=$null;$tx=$null;$lastTime=[DateTimeOffset]::MinValue
    foreach($file in $files){if(($file.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw 'journal history entry reparse point'};$r=ConvertFrom-CustomAppProductionCrashJournalFileV010 -AllowedRoot ([string]$Paths.allowed_root) -Path $file.FullName;$e=$r.entry
        if([int64]$e.revision -ne $rev){throw 'journal history revision chain invalid'};if(([string]$e.previous_entry_sha256).Trim().ToLowerInvariant() -cne $prev){throw 'journal history hash chain invalid'}
        $expectedName=('{0:D20}-{1}.json' -f $rev,([string]$e.entry_sha256).Trim().ToLowerInvariant());if([string]$file.Name -cne $expectedName){throw 'journal history filename identity invalid'}
        if($null -eq $tx){$tx=([string]$e.transaction_id).Trim().ToLowerInvariant()}elseif(([string]$e.transaction_id).Trim().ToLowerInvariant() -cne $tx){throw 'journal transaction identity changed'}
        $t=[DateTimeOffset]::Parse([string]$e.recorded_at);if($rev -gt 0 -and $t -lt $lastTime){throw 'journal time moved backward'}
        if($rev -gt 0 -and -not (Test-CustomAppProductionCrashJournalTransitionV010 -From ([string]$latest.phase) -To ([string]$e.phase))){throw 'journal illegal phase transition in history'}
        $prev=([string]$e.entry_sha256).Trim().ToLowerInvariant();$latest=$e;$lastTime=$t;$rev++
    }
    if(-not (Test-Path -LiteralPath ([string]$Paths.current) -PathType Leaf)){throw 'journal-current-missing'};$cur=ConvertFrom-CustomAppProductionCrashJournalFileV010 -AllowedRoot ([string]$Paths.allowed_root) -Path ([string]$Paths.current)
    if([int64]$cur.entry.revision -ne [int64]$latest.revision -or ([string]$cur.entry.entry_sha256).Trim().ToLowerInvariant() -cne ([string]$latest.entry_sha256).Trim().ToLowerInvariant()){throw 'journal-current-history-mismatch'}
    return [pscustomobject]@{ok=$true;reason='crash-journal-valid';revision=[int64]$latest.revision;entry=$latest;history_count=$files.Count;transaction_id=$tx;reloaded_from_persistent_store=$true;journal_is_authority=$false;production_execution_authorized=$false;production_mutation_authorized=$false}
}
function Read-CustomAppProductionCrashJournalV010 {
    param([Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory)
    $paths=Get-CustomAppProductionCrashJournalPathsV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory;$lock=$null
    try{$lock=Open-CustomAppProductionCrashJournalLockV010 $paths;return Read-CustomAppProductionCrashJournalUnlockedV010 -Paths $paths}finally{if($null -ne $lock){$lock.Dispose()}}
}
function Initialize-CustomAppProductionCrashJournalV010 {
    param([Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory,[Parameter(Mandatory=$true)]$Identity,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow)
    $deny={param([string]$Reason)[pscustomobject]@{ok=$false;reason=$Reason;persisted=$false;journal_is_authority=$false;production_execution_authorized=$false;production_mutation_authorized=$false}}
    $id=Test-CustomAppProductionCrashJournalIdentityV010 -Identity $Identity -AllowedRoot $AllowedRoot;if(-not [bool]$id.ok){return & $deny ('identity-denied:'+[string]$id.reason)}
    if($Now -gt [DateTimeOffset]::UtcNow.AddMinutes(5)){return & $deny 'journal-future-timestamp-denied'}
    try{$paths=Get-CustomAppProductionCrashJournalPathsV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -Create:$true}catch{return & $deny ('journal-store-path-denied:'+[string]$_.Exception.Message)};$lock=$null
    try{$lock=Open-CustomAppProductionCrashJournalLockV010 $paths;try{$existing=Read-CustomAppProductionCrashJournalUnlockedV010 -Paths $paths}catch{return & $deny ('journal-store-read-denied:'+[string]$_.Exception.Message)};if([bool]$existing.ok){return & $deny 'journal-store-already-initialized'};if([string]$existing.reason -cne 'journal-uninitialized'){return & $deny ([string]$existing.reason)}
        $entry=New-CustomAppProductionCrashJournalEntryV010 -Identity $Identity -Revision 0 -PreviousEntrySha256 $CustomAppProductionCrashRecoveryJournalZeroHash -Phase 'prepared' -RecordedAt $Now;$json=$entry|ConvertTo-Json -Depth 30 -Compress;$history=Join-Path ([string]$paths.history) ('{0:D20}-{1}.json' -f 0,[string]$entry.entry_sha256)
        Write-CustomAppProductionCrashJournalDurableFileV010 -Path $history -Text $json -Mode ([IO.FileMode]::CreateNew);Write-CustomAppProductionCrashJournalDurableFileV010 -Path ([string]$paths.current) -Text $json -Mode ([IO.FileMode]::CreateNew);$verify=Read-CustomAppProductionCrashJournalUnlockedV010 $paths;if(-not [bool]$verify.ok){throw 'journal initialization readback failed'}
        return [pscustomobject]@{ok=$true;reason='crash-journal-initialized-durable-readback-verified';persisted=$true;revision=0;entry=$verify.entry;transaction_id=[string]$verify.transaction_id;read_after_write_verified=$true;journal_is_authority=$false;production_execution_authorized=$false;production_mutation_authorized=$false}
    }finally{if($null -ne $lock){$lock.Dispose()}}
}
function Append-CustomAppProductionCrashJournalPhaseV010 {
    param(
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory,[Parameter(Mandatory=$true)][int64]$ExpectedRevision,[Parameter(Mandatory=$true)][string]$ExpectedEntrySha256,
        [Parameter(Mandatory=$true)][ValidateSet('atomic-mutation-starting','live-moved-to-old','candidate-live','transaction-finalized','apply-starting','apply-returned-success-pending-verification','apply-verified','cleanup-starting','committed-clean','rollback-required','rollback-complete')][string]$Phase,
        [AllowNull()][string]$FinalizationFingerprint=$null,[AllowNull()][string]$ApplyResultFingerprint=$null,[AllowNull()][string]$CleanupResultFingerprint=$null,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow,
        [ValidateSet('none','after-history-before-current')][string]$FailurePoint='none'
    )
    $deny={param([string]$Reason)[pscustomobject]@{ok=$false;reason=$Reason;persisted=$false;journal_is_authority=$false;production_execution_authorized=$false;production_mutation_authorized=$false}}
    if(-not (Test-CustomAppProductionCrashJournalSha256V010 $ExpectedEntrySha256)){return & $deny 'expected-entry-sha256-invalid'};if($Now -gt [DateTimeOffset]::UtcNow.AddMinutes(5)){return & $deny 'journal-future-timestamp-denied'}
    try{$paths=Get-CustomAppProductionCrashJournalPathsV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory}catch{return & $deny ('journal-store-path-denied:'+[string]$_.Exception.Message)};$lock=$null;$temp=$null;$backup=$null
    try{try{$lock=Open-CustomAppProductionCrashJournalLockV010 $paths}catch{return & $deny ([string]$_.Exception.Message)};try{$current=Read-CustomAppProductionCrashJournalUnlockedV010 $paths}catch{return & $deny ('journal-store-read-denied:'+[string]$_.Exception.Message)};if(-not [bool]$current.ok){return & $deny ([string]$current.reason)}
        if([int64]$current.revision -ne $ExpectedRevision){return & $deny 'journal-revision-conflict'};if(([string]$current.entry.entry_sha256).Trim().ToLowerInvariant() -cne $ExpectedEntrySha256.Trim().ToLowerInvariant()){return & $deny 'journal-head-sha256-conflict'};if(-not (Test-CustomAppProductionCrashJournalTransitionV010 -From ([string]$current.entry.phase) -To $Phase)){return & $deny 'journal-illegal-phase-transition'}
        $prevTime=[DateTimeOffset]::Parse([string]$current.entry.recorded_at);if($Now -lt $prevTime){return & $deny 'journal-time-reversal-denied'}
        $identity=[pscustomobject]@{name=[string]$current.entry.name;consumption_id=[string]$current.entry.consumption_id;source_identity=[string]$current.entry.source_identity;remote_commit_sha=[string]$current.entry.remote_commit_sha;stage_result_fingerprint=[string]$current.entry.stage_result_fingerprint;preparation_fingerprint=[string]$current.entry.preparation_fingerprint;live_path=[string]$current.entry.live_path;transaction_root=[string]$current.entry.transaction_root;stage_workspace_path=[string]$current.entry.stage_workspace_path;app_backup_path=[string]$current.entry.app_backup_path;persistence_backup_path=[string]$current.entry.persistence_backup_path;transaction_id=[string]$current.entry.transaction_id}
        $final=if([string]::IsNullOrWhiteSpace($FinalizationFingerprint)){[string]$current.entry.finalization_fingerprint}else{$FinalizationFingerprint};$apply=if([string]::IsNullOrWhiteSpace($ApplyResultFingerprint)){[string]$current.entry.apply_result_fingerprint}else{$ApplyResultFingerprint};$cleanup=if([string]::IsNullOrWhiteSpace($CleanupResultFingerprint)){[string]$current.entry.cleanup_result_fingerprint}else{$CleanupResultFingerprint}
        $next=New-CustomAppProductionCrashJournalEntryV010 -Identity $identity -Revision ($ExpectedRevision+1) -PreviousEntrySha256 ([string]$current.entry.entry_sha256) -Phase $Phase -FinalizationFingerprint $final -ApplyResultFingerprint $apply -CleanupResultFingerprint $cleanup -RecordedAt $Now
        $check=Test-CustomAppProductionCrashJournalEntryV010 -Entry $next -AllowedRoot $AllowedRoot;if(-not [bool]$check.ok){return & $deny ('next-entry-invalid:'+[string]$check.reason)};$json=$next|ConvertTo-Json -Depth 30 -Compress;$history=Join-Path ([string]$paths.history) ('{0:D20}-{1}.json' -f [int64]$next.revision,[string]$next.entry_sha256)
        try{Write-CustomAppProductionCrashJournalDurableFileV010 -Path $history -Text $json -Mode ([IO.FileMode]::CreateNew)}catch{return & $deny ('journal-history-create-failed:'+[string]$_.Exception.Message)};if($FailurePoint -ceq 'after-history-before-current'){return & $deny 'simulated-crash-after-history-before-current'}
        $temp=Join-Path ([string]$paths.store) ('current.tmp.'+[Guid]::NewGuid().ToString('N'));$backup=Join-Path ([string]$paths.store) ('current.backup.'+[Guid]::NewGuid().ToString('N'));Write-CustomAppProductionCrashJournalDurableFileV010 -Path $temp -Text $json -Mode ([IO.FileMode]::CreateNew);[IO.File]::Replace($temp,[string]$paths.current,$backup,$true);$temp=$null
        try{$verify=Read-CustomAppProductionCrashJournalUnlockedV010 $paths}catch{return & $deny ('journal-readback-denied:'+[string]$_.Exception.Message)};if(-not [bool]$verify.ok -or [int64]$verify.revision -ne [int64]$next.revision -or ([string]$verify.entry.entry_sha256).Trim().ToLowerInvariant() -cne ([string]$next.entry_sha256).Trim().ToLowerInvariant()){return & $deny 'journal-readback-mismatch'}
        if($null -ne $backup -and (Test-Path -LiteralPath $backup)){[IO.File]::Delete($backup);$backup=$null}
        return [pscustomobject]@{ok=$true;reason='crash-journal-phase-durably-appended-readback-verified';persisted=$true;revision=[int64]$verify.revision;entry=$verify.entry;transaction_id=[string]$verify.transaction_id;read_after_write_verified=$true;journal_is_authority=$false;production_execution_authorized=$false;production_mutation_authorized=$false}
    }finally{if($null -ne $temp -and (Test-Path -LiteralPath $temp)){[IO.File]::Delete($temp)};if($null -ne $lock){$lock.Dispose()}}
}

function Resolve-CustomAppProductionCrashRecoveryClassificationV010 {
    param([AllowNull()]$StoreRead,[AllowNull()][string]$ExpectedTransactionId=$null)
    $deny={param([string]$Reason)[pscustomobject]@{ok=$false;reason=$Reason;classification='fail-closed';requires_fresh_filesystem_revalidation=$true;requires_recovery_executor=$true;housekeeping_only=$false;no_action=$false;journal_is_authority=$false;production_execution_authorized=$false;production_mutation_authorized=$false}}
    if($null -eq $StoreRead -or -not [bool]$StoreRead.ok -or -not [bool]$StoreRead.reloaded_from_persistent_store){return & $deny 'journal-not-durably-reloaded'}
    $e=$StoreRead.entry;if($null -eq $e){return & $deny 'journal-entry-missing'};if(-not [string]::IsNullOrWhiteSpace($ExpectedTransactionId) -and ([string]$e.transaction_id).Trim().ToLowerInvariant() -cne $ExpectedTransactionId.Trim().ToLowerInvariant()){return & $deny 'journal-transaction-id-mismatch'}
    switch([string]$e.phase){
        'prepared' {return [pscustomobject]@{ok=$true;reason='prepared-no-live-side-effect-recorded';classification='safe-abandon-or-restart-only-after-fresh-admission';requires_fresh_filesystem_revalidation=$true;requires_recovery_executor=$false;housekeeping_only=$false;no_action=$true;journal_is_authority=$false;production_execution_authorized=$false;production_mutation_authorized=$false}}
        'atomic-mutation-starting' {return [pscustomobject]@{ok=$true;reason='atomic-side-effect-window-ambiguous';classification='filesystem-recovery-inspection-required';requires_fresh_filesystem_revalidation=$true;requires_recovery_executor=$true;housekeeping_only=$false;no_action=$false;journal_is_authority=$false;production_execution_authorized=$false;production_mutation_authorized=$false}}
        'live-moved-to-old' {return [pscustomobject]@{ok=$true;reason='live-rename-window-incomplete-or-ambiguous';classification='exact-app-and-persistence-recovery-required';requires_fresh_filesystem_revalidation=$true;requires_recovery_executor=$true;housekeeping_only=$false;no_action=$false;journal_is_authority=$false;production_execution_authorized=$false;production_mutation_authorized=$false}}
        'candidate-live' {return [pscustomobject]@{ok=$true;reason='candidate-live-not-finalized';classification='exact-app-and-persistence-recovery-required';requires_fresh_filesystem_revalidation=$true;requires_recovery_executor=$true;housekeeping_only=$false;no_action=$false;journal_is_authority=$false;production_execution_authorized=$false;production_mutation_authorized=$false}}
        'transaction-finalized' {return [pscustomobject]@{ok=$true;reason='new-live-present-apply-not-started';classification='exact-app-and-persistence-recovery-required';requires_fresh_filesystem_revalidation=$true;requires_recovery_executor=$true;housekeeping_only=$false;no_action=$false;journal_is_authority=$false;production_execution_authorized=$false;production_mutation_authorized=$false}}
        'apply-starting' {return [pscustomobject]@{ok=$true;reason='apply-outcome-ambiguous-after-crash';classification='rollback-and-recovery-apply-required';requires_fresh_filesystem_revalidation=$true;requires_recovery_executor=$true;housekeeping_only=$false;no_action=$false;journal_is_authority=$false;production_execution_authorized=$false;production_mutation_authorized=$false}}
        'apply-returned-success-pending-verification' {return [pscustomobject]@{ok=$true;reason='apply-returned-but-postconditions-unverified';classification='rollback-and-recovery-apply-required';requires_fresh_filesystem_revalidation=$true;requires_recovery_executor=$true;housekeeping_only=$false;no_action=$false;journal_is_authority=$false;production_execution_authorized=$false;production_mutation_authorized=$false}}
        'apply-verified' {return [pscustomobject]@{ok=$true;reason='apply-verified-before-housekeeping';classification='fresh-revalidate-then-housekeeping-only';requires_fresh_filesystem_revalidation=$true;requires_recovery_executor=$false;housekeeping_only=$true;no_action=$false;journal_is_authority=$false;production_execution_authorized=$false;production_mutation_authorized=$false}}
        'cleanup-starting' {return [pscustomobject]@{ok=$true;reason='cleanup-may-be-partial';classification='fresh-revalidate-then-idempotent-housekeeping-only';requires_fresh_filesystem_revalidation=$true;requires_recovery_executor=$false;housekeeping_only=$true;no_action=$false;journal_is_authority=$false;production_execution_authorized=$false;production_mutation_authorized=$false}}
        'committed-clean' {return [pscustomobject]@{ok=$true;reason='transaction-committed-clean';classification='no-action-new-permit-required-for-future-update';requires_fresh_filesystem_revalidation=$false;requires_recovery_executor=$false;housekeeping_only=$false;no_action=$true;journal_is_authority=$false;production_execution_authorized=$false;production_mutation_authorized=$false}}
        'rollback-required' {return [pscustomobject]@{ok=$true;reason='rollback-explicitly-required';classification='rollback-and-recovery-apply-required';requires_fresh_filesystem_revalidation=$true;requires_recovery_executor=$true;housekeeping_only=$false;no_action=$false;journal_is_authority=$false;production_execution_authorized=$false;production_mutation_authorized=$false}}
        'rollback-complete' {return [pscustomobject]@{ok=$true;reason='rollback-complete';classification='no-action-fresh-permit-required';requires_fresh_filesystem_revalidation=$true;requires_recovery_executor=$false;housekeeping_only=$false;no_action=$true;journal_is_authority=$false;production_execution_authorized=$false;production_mutation_authorized=$false}}
        default {return & $deny 'journal-phase-unrecognized'}
    }
}
