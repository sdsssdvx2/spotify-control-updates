$CustomAppProductionRecoveryPreflightSchema = 1
$CustomAppProductionRecoveryPreflightManagedBy = 'custom-app-production-recovery-preflight-v1'
$CustomAppProductionRecoveryPreflightQualifiedPlanHead = 'b266bad660d4b7bc87e7093c5b12f0cff1dc466f'

function Get-CustomAppProductionRecoveryPreflightSha256V010 {
    param([AllowNull()][string]$Text)
    if($null -eq $Text){$Text=''}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}
    finally{$sha.Dispose()}
}
function Test-CustomAppProductionRecoveryPreflightSha256V010 {param([AllowNull()][string]$Value)return (-not [string]::IsNullOrWhiteSpace($Value) -and $Value -cmatch '^[0-9a-f]{64}$')}

function Get-CustomAppProductionRecoveryPreflightFileSha256V010 {
    param([Parameter(Mandatory=$true)][string]$Path)
    $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try{$sha=[Security.Cryptography.SHA256]::Create();try{return ([BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','').ToLowerInvariant())}finally{$sha.Dispose()}}
    finally{$stream.Dispose()}
}

function Get-CustomAppProductionRecoveryPreflightDirectoryEvidenceV010 {
    param([Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][string]$Label)
    $root=Get-CustomAppProductionCrashJournalCanonicalPathV010 $AllowedRoot
    $target=Assert-CustomAppProductionCrashJournalPathV010 -AllowedRoot $root -Path $Path -Label $Label -RequireExisting:$true
    if(-not (Test-Path -LiteralPath $target -PathType Container)){throw "$Label is not a directory"}
    $entries=New-Object Collections.Generic.List[object]
    $dirs=@(Get-ChildItem -LiteralPath $target -Force -Directory -Recurse -ErrorAction Stop | Sort-Object FullName)
    $files=@(Get-ChildItem -LiteralPath $target -Force -File -Recurse -ErrorAction Stop | Sort-Object FullName)
    foreach($d in $dirs){if(($d.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw "$Label contains reparse point"};$rel=$d.FullName.Substring($target.Length).TrimStart('\','/').Replace('\','/');$entries.Add([pscustomobject]@{kind='dir';path=$rel;bytes=0;sha256=''})}
    $total=[int64]0
    foreach($f in $files){if(($f.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw "$Label contains reparse point"};$rel=$f.FullName.Substring($target.Length).TrimStart('\','/').Replace('\','/');$hash=Get-CustomAppProductionRecoveryPreflightFileSha256V010 $f.FullName;$total+=[int64]$f.Length;$entries.Add([pscustomobject]@{kind='file';path=$rel;bytes=[int64]$f.Length;sha256=$hash})}
    $material=(@($entries|ForEach-Object{"$($_.kind)`t$($_.path)`t$($_.bytes)`t$($_.sha256)"}) -join "`n")
    return [pscustomobject]@{label=$Label;path=$target;exists=$true;file_count=$files.Count;directory_count=$dirs.Count;total_bytes=$total;tree_fingerprint=(Get-CustomAppProductionRecoveryPreflightSha256V010 $material)}
}

function Get-CustomAppProductionRecoveryPreflightExecutableEvidenceV010 {
    param([Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)][string]$ExpectedSha256)
    if(-not (Test-CustomAppProductionRecoveryPreflightSha256V010 $ExpectedSha256)){throw 'spicetify expected sha256 invalid'}
    $target=Assert-CustomAppProductionCrashJournalPathV010 -AllowedRoot $AllowedRoot -Path $Path -Label 'spicetify executable' -RequireExisting:$true
    if(-not (Test-Path -LiteralPath $target -PathType Leaf)){throw 'spicetify executable is not a file'}
    $item=Get-Item -LiteralPath $target -Force -ErrorAction Stop
    if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw 'spicetify executable reparse point'}
    if([IO.Path]::GetFileName($target) -ine 'spicetify.exe'){throw 'spicetify executable name mismatch'}
    $actual=Get-CustomAppProductionRecoveryPreflightFileSha256V010 $target
    if($actual -cne $ExpectedSha256.Trim().ToLowerInvariant()){throw 'spicetify executable sha256 mismatch'}
    return [pscustomobject]@{path=$target;sha256=$actual;bytes=[int64]$item.Length;verified=$true}
}

function Get-CustomAppProductionRecoveryPreflightMaterialV010 {
    param([Parameter(Mandatory=$true)]$Receipt)
    return @(
        [string]$Receipt.schema,[string]$Receipt.managed_by,[string]$Receipt.qualified_plan_head,[string]$Receipt.transaction_id,[string]$Receipt.phase,[string]$Receipt.classification,[string]$Receipt.recovery_verb,[string]$Receipt.plan_fingerprint,
        [string]$Receipt.journal_revision,[string]$Receipt.journal_entry_sha256,[string]$Receipt.live_evidence_fingerprint,[string]$Receipt.transaction_evidence_fingerprint,[string]$Receipt.stage_evidence_fingerprint,[string]$Receipt.app_backup_evidence_fingerprint,[string]$Receipt.persistence_backup_evidence_fingerprint,[string]$Receipt.spicetify_executable_sha256,
        [string]$Receipt.prerequisites_complete,[string]$Receipt.manual_inspection_required,[string]$Receipt.recovery_executor_required,[string]$Receipt.recovery_apply_required,[string]$Receipt.housekeeping_only,[string]$Receipt.no_action,[string]$Receipt.requires_new_permit,
        [string]$Receipt.preflight_is_authority,[string]$Receipt.execution_authorized,[string]$Receipt.restore_authorized,[string]$Receipt.apply_authorized,[string]$Receipt.cleanup_authorized,[string]$Receipt.production_mutation_authorized
    ) -join "`n"
}

function Resolve-CustomAppProductionRecoveryPreflightV010 {
    param(
        [Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory,[Parameter(Mandatory=$true)][string]$ExpectedTransactionId,
        [AllowNull()]$Plan=$null,[AllowNull()][string]$SpicetifyAllowedRoot=$null,[AllowNull()][string]$SpicetifyPath=$null,[AllowNull()][string]$ExpectedSpicetifySha256=$null
    )
    $deny={param([string]$Reason)[pscustomobject]@{ok=$false;reason=$Reason;preflight_is_authority=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false}}
    if($null -eq $Plan){try{$Plan=Resolve-CustomAppProductionRecoveryPlanV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $ExpectedTransactionId}catch{return & $deny ('recovery-plan-resolution-failed:'+[string]$_.Exception.Message)}}
    $pc=Test-CustomAppProductionRecoveryPlanV010 $Plan;if(-not [bool]$pc.ok){return & $deny ('recovery-plan-invalid:'+[string]$pc.reason)}
    $tx=$ExpectedTransactionId.Trim().ToLowerInvariant();if(([string]$Plan.transaction_id).Trim().ToLowerInvariant() -cne $tx){return & $deny 'recovery-plan-transaction-mismatch'}
    try{$read=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory}catch{return & $deny ('recovery-journal-read-failed:'+[string]$_.Exception.Message)}
    if($null -eq $read -or -not [bool]$read.ok -or $null -eq $read.entry){return & $deny 'recovery-journal-current-entry-invalid'}
    if(([string]$read.transaction_id).Trim().ToLowerInvariant() -cne $tx -or ([string]$read.entry.transaction_id).Trim().ToLowerInvariant() -cne $tx){return & $deny 'recovery-journal-transaction-mismatch'}
    if([string]$read.entry.phase -cne [string]$Plan.phase){return & $deny 'recovery-journal-phase-changed-since-plan'}

    $live=$null;$txn=$null;$stage=$null;$app=$null;$persist=$null;$exe=$null
    try{
        if([bool]$Plan.requires_live_path){$live=Get-CustomAppProductionRecoveryPreflightDirectoryEvidenceV010 -AllowedRoot $AllowedRoot -Path ([string]$read.entry.live_path) -Label 'live'}
        if([bool]$Plan.requires_transaction_root){$txn=Get-CustomAppProductionRecoveryPreflightDirectoryEvidenceV010 -AllowedRoot $AllowedRoot -Path ([string]$read.entry.transaction_root) -Label 'transaction-root'}
        if([bool]$Plan.requires_stage_workspace){$stage=Get-CustomAppProductionRecoveryPreflightDirectoryEvidenceV010 -AllowedRoot $AllowedRoot -Path ([string]$read.entry.stage_workspace_path) -Label 'stage-workspace'}
        if([bool]$Plan.requires_app_backup){$app=Get-CustomAppProductionRecoveryPreflightDirectoryEvidenceV010 -AllowedRoot $AllowedRoot -Path ([string]$read.entry.app_backup_path) -Label 'app-backup'}
        if([bool]$Plan.requires_persistence_backup){$persist=Get-CustomAppProductionRecoveryPreflightDirectoryEvidenceV010 -AllowedRoot $AllowedRoot -Path ([string]$read.entry.persistence_backup_path) -Label 'persistence-backup'}
        if([bool]$Plan.requires_exact_spicetify_executable_pin){
            if([string]::IsNullOrWhiteSpace($SpicetifyAllowedRoot) -or [string]::IsNullOrWhiteSpace($SpicetifyPath) -or [string]::IsNullOrWhiteSpace($ExpectedSpicetifySha256)){throw 'spicetify exact pin inputs missing'}
            $exe=Get-CustomAppProductionRecoveryPreflightExecutableEvidenceV010 -AllowedRoot $SpicetifyAllowedRoot -Path $SpicetifyPath -ExpectedSha256 $ExpectedSpicetifySha256
        }
    } catch {return & $deny ('recovery-preflight-prerequisite-failed:'+[string]$_.Exception.Message)}

    $receipt=[pscustomobject]@{
        schema=$CustomAppProductionRecoveryPreflightSchema;managed_by=$CustomAppProductionRecoveryPreflightManagedBy;qualified_plan_head=$CustomAppProductionRecoveryPreflightQualifiedPlanHead
        transaction_id=$tx;phase=[string]$Plan.phase;classification=[string]$Plan.classification;recovery_verb=[string]$Plan.recovery_verb;plan_fingerprint=([string]$Plan.plan_fingerprint).Trim().ToLowerInvariant()
        journal_revision=[int64]$read.revision;journal_entry_sha256=([string]$read.entry.entry_sha256).Trim().ToLowerInvariant()
        live_evidence_fingerprint=$(if($null -ne $live){[string]$live.tree_fingerprint}else{''});transaction_evidence_fingerprint=$(if($null -ne $txn){[string]$txn.tree_fingerprint}else{''});stage_evidence_fingerprint=$(if($null -ne $stage){[string]$stage.tree_fingerprint}else{''});app_backup_evidence_fingerprint=$(if($null -ne $app){[string]$app.tree_fingerprint}else{''});persistence_backup_evidence_fingerprint=$(if($null -ne $persist){[string]$persist.tree_fingerprint}else{''});spicetify_executable_sha256=$(if($null -ne $exe){[string]$exe.sha256}else{''})
        prerequisites_complete=$true;manual_inspection_required=[bool]$Plan.requires_manual_inspection;recovery_executor_required=[bool]$Plan.requires_recovery_executor;recovery_apply_required=[bool]$Plan.requires_recovery_apply;housekeeping_only=[bool]$Plan.housekeeping_only;no_action=[bool]$Plan.no_action;requires_new_permit=[bool]$Plan.requires_new_permit
        preflight_is_authority=$false;execution_authorized=$false;restore_authorized=$false;apply_authorized=$false;cleanup_authorized=$false;production_mutation_authorized=$false;preflight_fingerprint=$null
    }
    $receipt.preflight_fingerprint=Get-CustomAppProductionRecoveryPreflightSha256V010 (Get-CustomAppProductionRecoveryPreflightMaterialV010 $receipt)
    return [pscustomobject]@{ok=$true;reason='recovery-preflight-read-only-evidence-complete';receipt=$receipt;evidence=[pscustomobject]@{live=$live;transaction=$txn;stage=$stage;app_backup=$app;persistence_backup=$persist;spicetify=$exe}}
}

function Test-CustomAppProductionRecoveryPreflightReceiptV010 {
    param([AllowNull()]$Receipt)
    if($null -eq $Receipt){return [pscustomobject]@{ok=$false;reason='recovery-preflight-receipt-null'}}
    foreach($f in @('schema','managed_by','qualified_plan_head','transaction_id','phase','classification','recovery_verb','plan_fingerprint','journal_revision','journal_entry_sha256','live_evidence_fingerprint','transaction_evidence_fingerprint','stage_evidence_fingerprint','app_backup_evidence_fingerprint','persistence_backup_evidence_fingerprint','spicetify_executable_sha256','prerequisites_complete','manual_inspection_required','recovery_executor_required','recovery_apply_required','housekeeping_only','no_action','requires_new_permit','preflight_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized','preflight_fingerprint')){if(-not $Receipt.PSObject.Properties[$f]){return [pscustomobject]@{ok=$false;reason=('recovery-preflight-required-field-missing-'+$f)}}}
    if([int]$Receipt.schema -ne 1 -or [string]$Receipt.managed_by -cne $CustomAppProductionRecoveryPreflightManagedBy -or [string]$Receipt.qualified_plan_head -cne $CustomAppProductionRecoveryPreflightQualifiedPlanHead){return [pscustomobject]@{ok=$false;reason='recovery-preflight-owner-schema-parent-mismatch'}}
    foreach($f in @('transaction_id','plan_fingerprint','journal_entry_sha256','preflight_fingerprint')){if(-not (Test-CustomAppProductionRecoveryPreflightSha256V010 (([string]$Receipt.$f).Trim().ToLowerInvariant()))){return [pscustomobject]@{ok=$false;reason=('recovery-preflight-invalid-'+$f)}}}
    foreach($f in @('preflight_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){if([bool]$Receipt.$f){return [pscustomobject]@{ok=$false;reason=('recovery-preflight-authority-escaped-'+$f)}}}
    if(-not [bool]$Receipt.prerequisites_complete){return [pscustomobject]@{ok=$false;reason='recovery-preflight-prerequisites-not-complete'}}
    $expected=Get-CustomAppProductionRecoveryPreflightSha256V010 (Get-CustomAppProductionRecoveryPreflightMaterialV010 $Receipt)
    if(([string]$Receipt.preflight_fingerprint).Trim().ToLowerInvariant() -cne $expected){return [pscustomobject]@{ok=$false;reason='recovery-preflight-fingerprint-mismatch'}}
    return [pscustomobject]@{ok=$true;reason='recovery-preflight-valid-zero-authority-evidence';transaction_id=([string]$Receipt.transaction_id).Trim().ToLowerInvariant();phase=[string]$Receipt.phase;classification=[string]$Receipt.classification}
}
