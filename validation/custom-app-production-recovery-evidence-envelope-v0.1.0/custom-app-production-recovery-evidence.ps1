$CustomAppProductionRecoveryEvidenceSchema = 1
$CustomAppProductionRecoveryEvidenceManagedBy = 'custom-app-production-recovery-evidence-v1'
$CustomAppProductionRecoveryEvidenceQualifiedRecoveryPlanHead = 'b266bad660d4b7bc87e7093c5b12f0cff1dc466f'
$CustomAppProductionRecoveryEvidenceFileName = 'recovery-evidence.json'

function Get-CustomAppProductionRecoveryEvidenceSha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}
function Test-CustomAppProductionRecoveryEvidenceSha256V010 {param([AllowNull()][string]$Value)return (-not [string]::IsNullOrWhiteSpace($Value)-and$Value-cmatch'^[0-9a-f]{64}$')}
function Test-CustomAppProductionRecoveryEvidenceCommitV010 {param([AllowNull()][string]$Value)return (-not [string]::IsNullOrWhiteSpace($Value)-and$Value-cmatch'^[0-9a-f]{40}$')}

function Get-CustomAppProductionRecoveryEvidencePreparedMaterialShaV010 {
    param([Parameter(Mandatory=$true)]$PreparedResult)
    return Get-CustomAppProductionRecoveryEvidenceSha256V010 (Get-CustomAppProductionPreApplyResultMaterialV010 -Result $PreparedResult)
}

function Test-CustomAppProductionRecoveryEvidencePreparedAnchorV010 {
    param([AllowNull()]$PreparedResult,[Parameter(Mandatory=$true)]$JournalEntry)
    if($null -eq $PreparedResult){return [pscustomobject]@{ok=$false;reason='prepared-result-null'}}
    $required=@('schema','managed_by','status','name','source_identity','remote_commit_sha','consumption_id','stage_result_fingerprint','preparation_fingerprint','stage_workspace_path','app_backup_path','persistence_backup_path','app_backup_tree_sha256','app_backup_file_count','app_backup_total_bytes','persistence_fingerprint','stage_tree_sha256','live_tree_sha256','preparation_is_authority','backups_are_authority','apply_authorized','live_destination_authorized','production_execution_authorized','production_mutation_authorized')
    foreach($f in $required){if(-not $PreparedResult.PSObject.Properties[$f]){return [pscustomobject]@{ok=$false;reason=('prepared-result-field-missing-'+$f)}}}
    if([int]$PreparedResult.schema-ne1-or[string]$PreparedResult.managed_by-cne'custom-app-production-pre-apply-preparation-v1'-or[string]$PreparedResult.status-cne'pre-apply-backups-prepared-verified'){return [pscustomobject]@{ok=$false;reason='prepared-result-owner-schema-or-status-invalid'}}
    foreach($f in @('preparation_is_authority','backups_are_authority','apply_authorized','live_destination_authorized','production_execution_authorized','production_mutation_authorized')){if([bool]$PreparedResult.$f){return [pscustomobject]@{ok=$false;reason=('prepared-result-authority-escaped-'+$f)}}}
    foreach($f in @('consumption_id','stage_result_fingerprint','preparation_fingerprint','app_backup_tree_sha256','persistence_fingerprint','stage_tree_sha256','live_tree_sha256')){if(-not(Test-CustomAppProductionRecoveryEvidenceSha256V010(([string]$PreparedResult.$f).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('prepared-result-invalid-'+$f)}}}
    if(-not(Test-CustomAppProductionRecoveryEvidenceCommitV010(([string]$PreparedResult.remote_commit_sha).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason='prepared-result-remote-commit-invalid'}}
    try{if([int]$PreparedResult.app_backup_file_count-lt1-or[int64]$PreparedResult.app_backup_total_bytes-lt1){return [pscustomobject]@{ok=$false;reason='prepared-result-backup-count-invalid'}}}catch{return [pscustomobject]@{ok=$false;reason='prepared-result-backup-count-invalid'}}
    $materialSha=Get-CustomAppProductionRecoveryEvidencePreparedMaterialShaV010 -PreparedResult $PreparedResult
    if($materialSha-cne([string]$PreparedResult.preparation_fingerprint).Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason='prepared-result-material-fingerprint-mismatch'}}
    $pairs=@(
        @('name',[string]$JournalEntry.name),@('source_identity',[string]$JournalEntry.source_identity),@('remote_commit_sha',[string]$JournalEntry.remote_commit_sha),
        @('consumption_id',[string]$JournalEntry.consumption_id),@('stage_result_fingerprint',[string]$JournalEntry.stage_result_fingerprint),@('preparation_fingerprint',[string]$JournalEntry.preparation_fingerprint),
        @('stage_workspace_path',[string]$JournalEntry.stage_workspace_path),@('app_backup_path',[string]$JournalEntry.app_backup_path),@('persistence_backup_path',[string]$JournalEntry.persistence_backup_path)
    )
    foreach($p in $pairs){
        if($p[0]-like'*_path'){
            try{$a=[IO.Path]::GetFullPath([string]$PreparedResult.($p[0])).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar);$b=[IO.Path]::GetFullPath([string]$p[1]).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)}catch{return [pscustomobject]@{ok=$false;reason=('prepared-journal-path-invalid-'+$p[0])}}
            if(-not$a.Equals($b,[StringComparison]::OrdinalIgnoreCase)){return [pscustomobject]@{ok=$false;reason=('prepared-journal-mismatch-'+$p[0])}}
            continue
        }
        if(([string]$PreparedResult.($p[0])).Trim().ToLowerInvariant()-cne([string]$p[1]).Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason=('prepared-journal-mismatch-'+$p[0])}}
    }
    return [pscustomobject]@{ok=$true;reason='prepared-result-anchored-to-durable-journal';prepared_material_sha256=$materialSha}
}

function Get-CustomAppProductionRecoveryEvidenceMaterialV010 {
    param([Parameter(Mandatory=$true)]$Envelope)
    return @(
        [string]$Envelope.schema,[string]$Envelope.managed_by,[string]$Envelope.qualified_recovery_plan_head,[string]$Envelope.transaction_id,
        [string]$Envelope.captured_journal_revision,[string]$Envelope.captured_journal_entry_sha256,[string]$Envelope.captured_phase,
        [string]$Envelope.name,[string]$Envelope.source_identity,[string]$Envelope.remote_commit_sha,[string]$Envelope.consumption_id,[string]$Envelope.stage_result_fingerprint,[string]$Envelope.preparation_fingerprint,
        [string]$Envelope.live_path,[string]$Envelope.transaction_root,[string]$Envelope.stage_workspace_path,[string]$Envelope.app_backup_path,[string]$Envelope.persistence_backup_path,
        [string]$Envelope.app_backup_tree_sha256,[string]$Envelope.app_backup_file_count,[string]$Envelope.app_backup_total_bytes,[string]$Envelope.persistence_fingerprint,[string]$Envelope.stage_tree_sha256,[string]$Envelope.live_tree_sha256,
        [string]$Envelope.prepared_result_material_sha256,[string]$Envelope.created_at,[string]$Envelope.immutable_create_new,[string]$Envelope.read_after_write_verified,
        [string]$Envelope.evidence_is_authority,[string]$Envelope.execution_authorized,[string]$Envelope.restore_authorized,[string]$Envelope.apply_authorized,[string]$Envelope.cleanup_authorized,[string]$Envelope.production_mutation_authorized
    )-join"`n"
}

function New-CustomAppProductionRecoveryEvidenceEnvelopeV010 {
    param([Parameter(Mandatory=$true)]$PreparedResult,[Parameter(Mandatory=$true)]$JournalEntry,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow)
    $anchor=Test-CustomAppProductionRecoveryEvidencePreparedAnchorV010 -PreparedResult $PreparedResult -JournalEntry $JournalEntry
    if(-not[bool]$anchor.ok){throw ('recovery-evidence prepared anchor denied: '+[string]$anchor.reason)}
    $e=[pscustomobject]@{
        schema=$CustomAppProductionRecoveryEvidenceSchema;managed_by=$CustomAppProductionRecoveryEvidenceManagedBy;qualified_recovery_plan_head=$CustomAppProductionRecoveryEvidenceQualifiedRecoveryPlanHead
        transaction_id=([string]$JournalEntry.transaction_id).Trim().ToLowerInvariant();captured_journal_revision=[int64]$JournalEntry.revision;captured_journal_entry_sha256=([string]$JournalEntry.entry_sha256).Trim().ToLowerInvariant();captured_phase=[string]$JournalEntry.phase
        name=([string]$PreparedResult.name).Trim().ToLowerInvariant();source_identity=([string]$PreparedResult.source_identity).Trim().ToLowerInvariant();remote_commit_sha=([string]$PreparedResult.remote_commit_sha).Trim().ToLowerInvariant();consumption_id=([string]$PreparedResult.consumption_id).Trim().ToLowerInvariant();stage_result_fingerprint=([string]$PreparedResult.stage_result_fingerprint).Trim().ToLowerInvariant();preparation_fingerprint=([string]$PreparedResult.preparation_fingerprint).Trim().ToLowerInvariant()
        live_path=[string]$JournalEntry.live_path;transaction_root=[string]$JournalEntry.transaction_root;stage_workspace_path=[string]$PreparedResult.stage_workspace_path;app_backup_path=[string]$PreparedResult.app_backup_path;persistence_backup_path=[string]$PreparedResult.persistence_backup_path
        app_backup_tree_sha256=([string]$PreparedResult.app_backup_tree_sha256).Trim().ToLowerInvariant();app_backup_file_count=[int]$PreparedResult.app_backup_file_count;app_backup_total_bytes=[int64]$PreparedResult.app_backup_total_bytes;persistence_fingerprint=([string]$PreparedResult.persistence_fingerprint).Trim().ToLowerInvariant();stage_tree_sha256=([string]$PreparedResult.stage_tree_sha256).Trim().ToLowerInvariant();live_tree_sha256=([string]$PreparedResult.live_tree_sha256).Trim().ToLowerInvariant()
        prepared_result_material_sha256=[string]$anchor.prepared_material_sha256;prepared_result=$PreparedResult;created_at=$Now.ToUniversalTime().ToString('o');immutable_create_new=$true;read_after_write_verified=$true
        evidence_is_authority=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false;evidence_fingerprint=$null
    }
    $e.evidence_fingerprint=Get-CustomAppProductionRecoveryEvidenceSha256V010 (Get-CustomAppProductionRecoveryEvidenceMaterialV010 $e)
    return $e
}

function Test-CustomAppProductionRecoveryEvidenceEnvelopeV010 {
    param([AllowNull()]$Envelope,[Parameter(Mandatory=$true)]$JournalEntry,[Parameter(Mandatory=$true)][string]$AllowedRoot)
    if($null-eq$Envelope){return [pscustomobject]@{ok=$false;reason='recovery-evidence-null'}}
    foreach($f in @('schema','managed_by','qualified_recovery_plan_head','transaction_id','captured_journal_revision','captured_journal_entry_sha256','captured_phase','name','source_identity','remote_commit_sha','consumption_id','stage_result_fingerprint','preparation_fingerprint','live_path','transaction_root','stage_workspace_path','app_backup_path','persistence_backup_path','app_backup_tree_sha256','app_backup_file_count','app_backup_total_bytes','persistence_fingerprint','stage_tree_sha256','live_tree_sha256','prepared_result_material_sha256','prepared_result','created_at','immutable_create_new','read_after_write_verified','evidence_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized','evidence_fingerprint')){if(-not$Envelope.PSObject.Properties[$f]){return [pscustomobject]@{ok=$false;reason=('recovery-evidence-field-missing-'+$f)}}}
    if([int]$Envelope.schema-ne1-or[string]$Envelope.managed_by-cne$CustomAppProductionRecoveryEvidenceManagedBy-or[string]$Envelope.qualified_recovery_plan_head-cne$CustomAppProductionRecoveryEvidenceQualifiedRecoveryPlanHead){return [pscustomobject]@{ok=$false;reason='recovery-evidence-owner-schema-parent-invalid'}}
    if(-not[bool]$Envelope.immutable_create_new-or-not[bool]$Envelope.read_after_write_verified){return [pscustomobject]@{ok=$false;reason='recovery-evidence-durability-contract-invalid'}}
    foreach($f in @('evidence_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){if([bool]$Envelope.$f){return [pscustomobject]@{ok=$false;reason=('recovery-evidence-authority-escaped-'+$f)}}}
    foreach($f in @('transaction_id','captured_journal_entry_sha256','consumption_id','stage_result_fingerprint','preparation_fingerprint','app_backup_tree_sha256','persistence_fingerprint','stage_tree_sha256','live_tree_sha256','prepared_result_material_sha256','evidence_fingerprint')){if(-not(Test-CustomAppProductionRecoveryEvidenceSha256V010(([string]$Envelope.$f).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('recovery-evidence-invalid-'+$f)}}}
    if(-not(Test-CustomAppProductionRecoveryEvidenceCommitV010(([string]$Envelope.remote_commit_sha).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason='recovery-evidence-commit-invalid'}}
    if([string]$Envelope.captured_phase-cne'prepared'-or[int64]$Envelope.captured_journal_revision-ne0){return [pscustomobject]@{ok=$false;reason='recovery-evidence-not-captured-at-prepared-revision-zero'}}
    try{foreach($f in @('live_path','transaction_root','stage_workspace_path','app_backup_path','persistence_backup_path')){[void](Assert-CustomAppProductionCrashJournalPathV010 -AllowedRoot $AllowedRoot -Path ([string]$Envelope.$f) -Label ('recovery evidence '+$f))}}catch{return [pscustomobject]@{ok=$false;reason=('recovery-evidence-path-invalid:'+[string]$_.Exception.Message)}}
    $anchor=Test-CustomAppProductionRecoveryEvidencePreparedAnchorV010 -PreparedResult $Envelope.prepared_result -JournalEntry $JournalEntry;if(-not[bool]$anchor.ok){return [pscustomobject]@{ok=$false;reason=('recovery-evidence-anchor-invalid:'+[string]$anchor.reason)}}
    foreach($f in @('transaction_id','name','source_identity','remote_commit_sha','consumption_id','stage_result_fingerprint','preparation_fingerprint','live_path','transaction_root','stage_workspace_path','app_backup_path','persistence_backup_path')){
        $journalValue=[string]$JournalEntry.$f
        if($f -ceq 'stage_workspace_path'){$journalValue=[string]$JournalEntry.stage_workspace_path}
        if($f -ceq 'app_backup_path'){$journalValue=[string]$JournalEntry.app_backup_path}
        if($f -ceq 'persistence_backup_path'){$journalValue=[string]$JournalEntry.persistence_backup_path}
        if($f-like'*_path'){
            try{$a=[IO.Path]::GetFullPath([string]$Envelope.$f).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar);$b=[IO.Path]::GetFullPath($journalValue).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)}catch{return [pscustomobject]@{ok=$false;reason=('recovery-evidence-journal-path-invalid-'+$f)}}
            if(-not$a.Equals($b,[StringComparison]::OrdinalIgnoreCase)){return [pscustomobject]@{ok=$false;reason=('recovery-evidence-journal-mismatch-'+$f)}}
            continue
        }
        if(([string]$Envelope.$f).Trim().ToLowerInvariant()-cne$journalValue.Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason=('recovery-evidence-journal-mismatch-'+$f)}}
    }
    if(([string]$Envelope.prepared_result_material_sha256).Trim().ToLowerInvariant()-cne([string]$anchor.prepared_material_sha256)){return [pscustomobject]@{ok=$false;reason='recovery-evidence-prepared-material-sha-mismatch'}}
    foreach($f in @('app_backup_tree_sha256','persistence_fingerprint','stage_tree_sha256','live_tree_sha256')){if(([string]$Envelope.$f).Trim().ToLowerInvariant()-cne([string]$Envelope.prepared_result.$f).Trim().ToLowerInvariant()){return [pscustomobject]@{ok=$false;reason=('recovery-evidence-prepared-mismatch-'+$f)}}}
    try{if([int]$Envelope.app_backup_file_count-ne[int]$Envelope.prepared_result.app_backup_file_count-or[int64]$Envelope.app_backup_total_bytes-ne[int64]$Envelope.prepared_result.app_backup_total_bytes){return [pscustomobject]@{ok=$false;reason='recovery-evidence-backup-count-mismatch'}}}catch{return [pscustomobject]@{ok=$false;reason='recovery-evidence-backup-count-invalid'}}
    if(([string]$Envelope.captured_journal_entry_sha256).Trim().ToLowerInvariant()-cne([string]$JournalEntry.PSObject.Properties['entry_sha256'].Value).Trim().ToLowerInvariant()-and[int64]$JournalEntry.revision-eq0){return [pscustomobject]@{ok=$false;reason='recovery-evidence-captured-entry-mismatch'}}
    $expected=Get-CustomAppProductionRecoveryEvidenceSha256V010 (Get-CustomAppProductionRecoveryEvidenceMaterialV010 $Envelope);if(([string]$Envelope.evidence_fingerprint).Trim().ToLowerInvariant()-cne$expected){return [pscustomobject]@{ok=$false;reason='recovery-evidence-fingerprint-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='recovery-evidence-valid-journal-anchored-zero-authority';transaction_id=([string]$Envelope.transaction_id).Trim().ToLowerInvariant();preparation_fingerprint=([string]$Envelope.preparation_fingerprint).Trim().ToLowerInvariant();evidence_fingerprint=$expected}
}

function Get-CustomAppProductionRecoveryEvidencePathV010 {
    param([Parameter(Mandatory=$true)]$JournalPaths)
    return Join-Path ([string]$JournalPaths.store) $CustomAppProductionRecoveryEvidenceFileName
}

function ConvertFrom-CustomAppProductionRecoveryEvidenceFileV010 {
    param([Parameter(Mandatory=$true)][string]$Path)
    $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop;if(($item.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'recovery-evidence-file-reparse-point'};if($item.Length-gt4194304){throw 'recovery-evidence-file-exceeds-4-MiB'}
    $raw=[IO.File]::ReadAllText($Path,(New-Object Text.UTF8Encoding($false)));try{return $raw|ConvertFrom-Json}catch{throw 'recovery-evidence-JSON-invalid'}
}

function Write-CustomAppProductionRecoveryEvidenceV010 {
    param([Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory,[Parameter(Mandatory=$true)]$PreparedResult,[DateTimeOffset]$Now=[DateTimeOffset]::UtcNow)
    $deny={param([string]$Reason)[pscustomobject]@{ok=$false;reason=$Reason;persisted=$false;read_after_write_verified=$false;evidence_is_authority=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false}}
    try{$paths=Get-CustomAppProductionCrashJournalPathsV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory}catch{return & $deny('recovery-evidence-store-path-denied:'+[string]$_.Exception.Message)};$lock=$null
    try{
        try{$lock=Open-CustomAppProductionCrashJournalLockV010 $paths}catch{return & $deny([string]$_.Exception.Message)}
        try{$read=Read-CustomAppProductionCrashJournalUnlockedV010 -Paths $paths}catch{return & $deny('recovery-evidence-journal-read-denied:'+[string]$_.Exception.Message)}
        if(-not[bool]$read.ok){return & $deny('recovery-evidence-journal-not-ready:'+[string]$read.reason)}
        if([int64]$read.revision-ne0-or[string]$read.entry.phase-cne'prepared'){return & $deny('recovery-evidence-must-be-created-at-prepared-revision-zero')}
        $path=Get-CustomAppProductionRecoveryEvidencePathV010 -JournalPaths $paths;if(Test-Path -LiteralPath $path){return & $deny 'recovery-evidence-already-exists-replay-denied'}
        try{$envelope=New-CustomAppProductionRecoveryEvidenceEnvelopeV010 -PreparedResult $PreparedResult -JournalEntry $read.entry -Now $Now}catch{return & $deny([string]$_.Exception.Message)}
        $check=Test-CustomAppProductionRecoveryEvidenceEnvelopeV010 -Envelope $envelope -JournalEntry $read.entry -AllowedRoot $AllowedRoot;if(-not[bool]$check.ok){return & $deny('recovery-evidence-prewrite-invalid:'+[string]$check.reason)}
        $json=$envelope|ConvertTo-Json -Depth 40 -Compress;try{Write-CustomAppProductionCrashJournalDurableFileV010 -Path $path -Text $json -Mode ([IO.FileMode]::CreateNew)}catch{return & $deny('recovery-evidence-durable-write-failed:'+[string]$_.Exception.Message)}
        try{$reloaded=ConvertFrom-CustomAppProductionRecoveryEvidenceFileV010 -Path $path}catch{return & $deny('recovery-evidence-readback-failed:'+[string]$_.Exception.Message)}
        $verify=Test-CustomAppProductionRecoveryEvidenceEnvelopeV010 -Envelope $reloaded -JournalEntry $read.entry -AllowedRoot $AllowedRoot;if(-not[bool]$verify.ok){return & $deny('recovery-evidence-readback-invalid:'+[string]$verify.reason)}
        return [pscustomobject]@{ok=$true;reason='recovery-evidence-durable-create-new-readback-verified';persisted=$true;read_after_write_verified=$true;path=$path;transaction_id=[string]$verify.transaction_id;preparation_fingerprint=[string]$verify.preparation_fingerprint;evidence_fingerprint=[string]$verify.evidence_fingerprint;envelope=$reloaded;evidence_is_authority=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false}
    }finally{if($null-ne$lock){$lock.Dispose()}}
}

function Read-CustomAppProductionRecoveryEvidenceV010 {
    param([Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory,[Parameter(Mandatory=$true)][string]$ExpectedTransactionId)
    $deny={param([string]$Reason)[pscustomobject]@{ok=$false;reason=$Reason;reloaded_from_persistent_store=$false;evidence_is_authority=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false}}
    if(-not(Test-CustomAppProductionRecoveryEvidenceSha256V010 $ExpectedTransactionId)){return & $deny 'recovery-evidence-expected-transaction-invalid'}
    try{$paths=Get-CustomAppProductionCrashJournalPathsV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory}catch{return & $deny('recovery-evidence-store-path-denied:'+[string]$_.Exception.Message)};$lock=$null
    try{
        try{$lock=Open-CustomAppProductionCrashJournalLockV010 $paths}catch{return & $deny([string]$_.Exception.Message)}
        try{$read=Read-CustomAppProductionCrashJournalUnlockedV010 -Paths $paths}catch{return & $deny('recovery-evidence-journal-read-denied:'+[string]$_.Exception.Message)}
        if(-not[bool]$read.ok){return & $deny('recovery-evidence-journal-not-ready:'+[string]$read.reason)}
        if(([string]$read.transaction_id).Trim().ToLowerInvariant()-cne$ExpectedTransactionId.Trim().ToLowerInvariant()){return & $deny 'recovery-evidence-transaction-mismatch'}
        $path=Get-CustomAppProductionRecoveryEvidencePathV010 -JournalPaths $paths;if(-not(Test-Path -LiteralPath $path -PathType Leaf)){return & $deny 'recovery-evidence-file-missing'}
        try{$e=ConvertFrom-CustomAppProductionRecoveryEvidenceFileV010 -Path $path}catch{return & $deny([string]$_.Exception.Message)}
        $check=Test-CustomAppProductionRecoveryEvidenceEnvelopeV010 -Envelope $e -JournalEntry $read.entry -AllowedRoot $AllowedRoot;if(-not[bool]$check.ok){return & $deny('recovery-evidence-invalid:'+[string]$check.reason)}
        return [pscustomobject]@{ok=$true;reason='recovery-evidence-reloaded-journal-anchored-zero-authority';reloaded_from_persistent_store=$true;path=$path;transaction_id=[string]$check.transaction_id;preparation_fingerprint=[string]$check.preparation_fingerprint;evidence_fingerprint=[string]$check.evidence_fingerprint;envelope=$e;journal_phase=[string]$read.entry.phase;journal_revision=[int64]$read.revision;evidence_is_authority=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false}
    }finally{if($null-ne$lock){$lock.Dispose()}}
}
