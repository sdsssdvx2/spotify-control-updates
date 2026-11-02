$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot 'custom-app-production-dual-transaction-id-bridge.ps1')

function Assert-DTIBTrue([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Assert-DTIBFalse([bool]$Value,[string]$Message){if($Value){throw $Message}}
function Assert-DTIBEq($Actual,$Expected,[string]$Message){if([string]$Actual -cne [string]$Expected){throw "$Message actual=<$Actual> expected=<$Expected>"}}
function Copy-DTIB($Object){return (($Object|ConvertTo-Json -Depth 80)|ConvertFrom-Json)}

$script:DTIBMode='valid'
$script:PermitId=('a'*64)
$script:JournalId=('b'*64)
$script:JournalEntrySha=('c'*64)
$script:EvidenceFp=('d'*64)
$script:Commit=('e'*40)
$script:Consumption=('f'*64)
$script:GenericStageFp=('1'*64)
$script:GenericPreparationFp=('2'*64)
$script:LiveTree=('3'*64)
$script:StageTree=('4'*64)
$script:BackupTree=('5'*64)
$script:PersistenceFp=('6'*64)
$script:BindingFp=('7'*64)
$script:RecoveryStageFp=('8'*64)
$script:PreparedFp=('9'*64)
$script:AtomicFp=('0'*64)
$script:PreparedMaterialFp=('ab'*32)
$script:LivePath='C:\fixture\live'
$script:TransactionRoot='C:\fixture\.spotify-control-txn-11111111111111111111111111111111'
$script:StageWorkspace='C:\fixture\stage-workspace'
$script:StagePath='C:\fixture\stage-workspace\stage'
$script:AppBackup='C:\fixture\backup\app'
$script:PersistenceBackup='C:\fixture\backup\persistence'

function New-DTIBPreparedV010 {
    [pscustomobject]@{
        name='tagify';source_identity='alexk218/tagify';transaction_id=$script:PermitId;github_repo_id=12345;surface_kind='github';remote_commit_sha=$script:Commit;binding_fingerprint=$script:BindingFp;consumption_id=$script:Consumption
        recovery_stage_result_fingerprint=$script:RecoveryStageFp;generic_stage_result_fingerprint=$script:GenericStageFp;generic_preparation_fingerprint=$script:GenericPreparationFp
        live_tree_sha256=$script:LiveTree;stage_tree_sha256=$script:StageTree;stage_workspace_path=$script:StageWorkspace;stage_path=$script:StagePath;app_backup_path=$script:AppBackup;app_backup_tree_sha256=$script:BackupTree;app_backup_file_count=4;app_backup_total_bytes=1234;persistence_backup_path=$script:PersistenceBackup;persistence_fingerprint=$script:PersistenceFp;result_fingerprint=$script:PreparedFp
    }
}
function New-DTIBStageV010 {[pscustomobject]@{transaction_id=$script:PermitId;result_fingerprint=$script:RecoveryStageFp}}
function New-DTIBAtomicV010 {
    [pscustomobject]@{transaction_id=$script:JournalId;journal_entry_sha256=$script:JournalEntrySha;journal_revision=3;recovery_evidence_fingerprint=$script:EvidenceFp;result_fingerprint=$script:AtomicFp;live_path=$script:LivePath;transaction_root=$script:TransactionRoot;stage_path=$script:StagePath}
}
function New-DTIBJournalV010 {
    $tx=$(if($script:DTIBMode -ceq 'journal-tx-drift'){('cc'*32)}else{$script:JournalId})
    $phase=$(if($script:DTIBMode -ceq 'journal-phase-drift'){'atomic-mutation-starting'}else{'candidate-live'})
    [pscustomobject]@{ok=$true;reason='fixture-journal';transaction_id=$tx;revision=3;entry=[pscustomobject]@{phase=$phase;entry_sha256=$script:JournalEntrySha}}
}
function New-DTIBEvidenceV010 {
    $fp=$(if($script:DTIBMode -ceq 'evidence-fingerprint-drift'){('dd'*32)}else{$script:EvidenceFp})
    $commit=$(if($script:DTIBMode -ceq 'prepared-evidence-drift'){('f'*40)}else{$script:Commit})
    $app=$(if($script:DTIBMode -ceq 'path-drift'){'C:\fixture\other-app-backup'}else{$script:AppBackup})
    [pscustomobject]@{
        ok=$true;reason='fixture-evidence';transaction_id=$script:JournalId;evidence_fingerprint=$fp
        envelope=[pscustomobject]@{
            name='tagify';source_identity='alexk218/tagify';remote_commit_sha=$commit;consumption_id=$script:Consumption;stage_result_fingerprint=$script:GenericStageFp;preparation_fingerprint=$script:GenericPreparationFp
            live_path=$script:LivePath;transaction_root=$script:TransactionRoot;stage_workspace_path=$script:StageWorkspace;app_backup_path=$app;persistence_backup_path=$script:PersistenceBackup
            live_tree_sha256=$script:LiveTree;stage_tree_sha256=$script:StageTree;app_backup_tree_sha256=$script:BackupTree;app_backup_file_count=4;app_backup_total_bytes=1234;persistence_fingerprint=$script:PersistenceFp;prepared_result_material_sha256=$script:PreparedMaterialFp
        }
    }
}

function Test-CustomAppProductionRecoveryAwarePermitPreApplyPreparedResultV010 {param($Result) if($script:DTIBMode-ceq'prepared-invalid'){[pscustomobject]@{ok=$false;reason='fixture-prepared-invalid'}}else{[pscustomobject]@{ok=$true;reason='fixture-prepared-valid'}}}
function Test-CustomAppProductionRecoveryAwarePermitStageExecutorResultV010 {param($Result) if($script:DTIBMode-ceq'stage-invalid'){[pscustomobject]@{ok=$false;reason='fixture-stage-invalid'}}else{[pscustomobject]@{ok=$true;reason='fixture-stage-valid'}}}
function Test-CustomAppProductionEvidenceBoundJournalAtomicResultV010 {param($Result) if($script:DTIBMode-ceq'atomic-invalid'){[pscustomobject]@{ok=$false;reason='fixture-atomic-invalid'}}else{[pscustomobject]@{ok=$true;reason='fixture-atomic-valid'}}}
function ConvertTo-CustomAppProductionRecoveryAwarePermitGenericPreparedResultV010 {param($Result) [pscustomobject]@{fixture=$true}}
function Test-CustomAppProductionPreApplyPreparedResultV010 {param($Result) [pscustomobject]@{ok=$true;reason='fixture-generic-valid'}}
function Read-CustomAppProductionCrashJournalV010 {param($AllowedRoot,$StoreDirectory) New-DTIBJournalV010}
function Read-CustomAppProductionRecoveryEvidenceV010 {param($AllowedRoot,$StoreDirectory,$ExpectedTransactionId) New-DTIBEvidenceV010}
function Test-CustomAppProductionRecoveryEvidencePreparedAnchorV010 {param($PreparedResult,$JournalEntry) if($script:DTIBMode-ceq'anchor-invalid'){[pscustomobject]@{ok=$false;reason='fixture-anchor-invalid'}}else{[pscustomobject]@{ok=$true;reason='fixture-anchor-valid';prepared_material_sha256=$script:PreparedMaterialFp}}}

function Reset-DTIBV010([string]$Mode){$script:DTIBMode=$Mode}
function Invoke-DTIBV010 {
    param([AllowNull()]$Prepared=$null,[AllowNull()]$Stage=$null,[AllowNull()]$Atomic=$null,[AllowNull()][string]$PermitId=$null)
    if($null-eq$Prepared){$Prepared=New-DTIBPreparedV010};if($null-eq$Stage){$Stage=New-DTIBStageV010};if($null-eq$Atomic){$Atomic=New-DTIBAtomicV010};if([string]::IsNullOrWhiteSpace($PermitId)){$PermitId=$script:PermitId}
    Resolve-CustomAppProductionDualTransactionIdBridgeV010 -RecoveryAwarePreparedResult $Prepared -RecoveryAwareStageExecutorResult $Stage -EvidenceBoundAtomicResult $Atomic -ExpectedPermitTransactionId $PermitId -AllowedRoot 'C:\fixture\allowed' -JournalStoreDirectory 'C:\fixture\journal'
}
function Assert-DTIBDeniedV010($R,[string]$Label){Assert-DTIBFalse ([bool]$R.ok) "$Label unexpectedly succeeded";foreach($f in @('bridge_is_authority','execution_authorized','finalization_authorized','spicetify_apply_authorized','cleanup_authorized','production_mutation_authorized')){Assert-DTIBFalse ([bool]$R.$f) "$Label escaped $f"}}

$count=0
Reset-DTIBV010 'valid';$valid=Invoke-DTIBV010
Assert-DTIBTrue ([bool]$valid.ok) ('valid bridge denied: '+[string]$valid.reason)
Assert-DTIBEq ([string]$valid.receipt.permit_transaction_id) $script:PermitId 'permit id'
Assert-DTIBEq ([string]$valid.receipt.journal_transaction_id) $script:JournalId 'journal id'
Assert-DTIBTrue ([bool]$valid.receipt.transaction_id_namespaces_distinct) 'namespace distinction missing'
Assert-DTIBTrue ([bool]$valid.receipt.requires_bridge_aware_finalization -and [bool]$valid.receipt.requires_crash_recovery_by_journal_id -and [bool]$valid.receipt.requires_forward_continuity_by_permit_id) 'routing requirements missing'
$vc=Test-CustomAppProductionDualTransactionIdBridgeReceiptV010 -Receipt $valid.receipt;Assert-DTIBTrue ([bool]$vc.ok) ('valid receipt invalid: '+[string]$vc.reason);$count++

$auth=Copy-DTIB $valid.receipt;$auth.production_mutation_authorized=$true;$auth.bridge_fingerprint=Get-CustomAppProductionDualTransactionIdBridgeSha256V010 (Get-CustomAppProductionDualTransactionIdBridgeReceiptMaterialV010 $auth);$c=Test-CustomAppProductionDualTransactionIdBridgeReceiptV010 $auth;Assert-DTIBFalse ([bool]$c.ok) 'rehashed authority escape accepted';$count++
$ns=Copy-DTIB $valid.receipt;$ns.transaction_id_namespaces_distinct=$false;$ns.bridge_fingerprint=Get-CustomAppProductionDualTransactionIdBridgeSha256V010 (Get-CustomAppProductionDualTransactionIdBridgeReceiptMaterialV010 $ns);$c=Test-CustomAppProductionDualTransactionIdBridgeReceiptV010 $ns;Assert-DTIBFalse ([bool]$c.ok) 'rehashed namespace conflation accepted';$count++
$fp=Copy-DTIB $valid.receipt;$fp.bridge_fingerprint=('ef'*32);$c=Test-CustomAppProductionDualTransactionIdBridgeReceiptV010 $fp;Assert-DTIBFalse ([bool]$c.ok) 'bridge fingerprint tamper accepted';$count++

$atomic=New-DTIBAtomicV010;$atomic.transaction_id=$script:PermitId;Reset-DTIBV010 'valid';$r=Invoke-DTIBV010 -Atomic $atomic;Assert-DTIBDeniedV010 $r 'conflated ids';Assert-DTIBEq ([string]$r.reason) 'dual-id-bridge-transaction-namespaces-conflated' 'conflated reason';$count++
$stage=New-DTIBStageV010;$stage.transaction_id=('ac'*32);$r=Invoke-DTIBV010 -Stage $stage;Assert-DTIBDeniedV010 $r 'stage transaction drift';$count++
$prepared=New-DTIBPreparedV010;$prepared.recovery_stage_result_fingerprint=('ad'*32);$r=Invoke-DTIBV010 -Prepared $prepared;Assert-DTIBDeniedV010 $r 'stage fingerprint drift';$count++

foreach($mode in @('journal-tx-drift','journal-phase-drift','evidence-fingerprint-drift','prepared-evidence-drift','path-drift','anchor-invalid','atomic-invalid','prepared-invalid','stage-invalid')){
    Reset-DTIBV010 $mode;$r=Invoke-DTIBV010;Assert-DTIBDeniedV010 $r $mode;$count++
}
Reset-DTIBV010 'valid'
Assert-DTIBEq $count 16 'matrix count'
Write-Output "CUSTOM_APP_PRODUCTION_DUAL_TRANSACTION_ID_BRIDGE_MATRIX_PASS total=$count"
