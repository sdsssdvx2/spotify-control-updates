$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-recovery-restore-executor-v0.1.0/test_custom_app_production_recovery_restore_executor.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-recovery-artifact-retirement-admission.ps1')

function T([bool]$v,[string]$m){if(-not$v){throw $m}}
function F([bool]$v,[string]$m){if($v){throw $m}}
function E($a,$b,[string]$m){if([string]$a-cne[string]$b){throw "$m actual=<$a> expected=<$b>"}}
function C($x){(($x|ConvertTo-Json -Depth 60)|ConvertFrom-Json)}
function D([string]$p){if(Test-Path -LiteralPath $p){[IO.Directory]::Delete($p,$true)}}
function New-AR([string]$l,[string]$phase='transaction-finalized',[string]$state='finalized',[string]$name='tagify',[string]$source='alexk218/tagify',[string]$manifest='Tagify',[string]$nonce=('1'*32)){
    $q=New-RXFixtureV010 -Label ('retire-'+$l) -Phase $phase -State $state -Name $name -Source $source -Manifest $manifest -Nonce $nonce
    $r=Invoke-RXFixtureV010 $q;if(-not[bool]$r.ok){throw ('restore setup failed '+$l+': '+[string]$r.reason)}
    Assert-RXSuccessV010 $q $r $phase ($phase-cne'rollback-required') ('retire-'+$l)
    [pscustomobject]@{q=$q;restore=$r.result}
}
function Invoke-AR($x,[AllowNull()]$restore=$null,[AllowNull()][string]$tx=$null,[DateTimeOffset]$at=[DateTimeOffset]::UtcNow){
    if($null-eq$restore){$restore=$x.restore};if([string]::IsNullOrWhiteSpace($tx)){$tx=[string]$x.q.f.f.identity.transaction_id}
    Resolve-CustomAppProductionRecoveryArtifactRetirementAdmissionV010 -AllowedRoot $x.q.f.f.allowed -StoreDirectory $x.q.f.f.store -ExpectedTransactionId $tx -RestoreExecutorResult $restore -LocalAppDataRoot $x.q.f.f.q.persistence.local -AppDataRoot $x.q.f.f.q.persistence.roaming -Now $at
}
function Z($r,[string]$m){$x=if($r.PSObject.Properties['receipt']){$r.receipt}else{$r};foreach($f in @('admission_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){F ([bool]$x.$f) "$m authority escaped $f"}}
function V($r,[DateTimeOffset]$at,[string]$m){T ([bool]$r.ok) "$m denied: $([string]$r.reason)";Z $r $m;$c=Test-CustomAppProductionRecoveryArtifactRetirementAdmissionReceiptV010 -Receipt $r.receipt -Now $at.AddSeconds(1);T ([bool]$c.ok) "$m receipt invalid: $([string]$c.reason)";E $r.receipt.phase 'rollback-complete' "$m phase"}
function Deny($r,[string]$pattern,[string]$m){F ([bool]$r.ok) "$m accepted";T ([string]$r.reason-like$pattern) "$m reason: $([string]$r.reason)";Z $r $m}

$count=0
$x=New-AR 'present' 'live-moved-to-old' 'live-moved-before-candidate' -nonce ('1'*32);$at=[DateTimeOffset]::UtcNow;$r=Invoke-AR $x -at $at;V $r $at 'present';E $r.receipt.transaction_status 'present-verified' 'present txn';foreach($f in @('stage_status','app_backup_status','persistence_backup_status')){E $r.receipt.$f 'present-verified' "present $f"};T ([bool]$r.receipt.retirement_needed) 'present retirement needed';$count++
$x=New-AR 'absent-txn' -nonce ('2'*32);$at=[DateTimeOffset]::UtcNow;$r=Invoke-AR $x -at $at;V $r $at 'absent-txn';E $r.receipt.transaction_status 'already-absent' 'absent txn';T ([bool]$r.receipt.retirement_needed) 'absent txn still has retained artifacts';$count++
$x=New-AR 'future' 'live-moved-to-old' 'live-moved-before-candidate' 'future-app' 'owner/future-app' 'Future App' ('3'*32);$at=[DateTimeOffset]::UtcNow;$r=Invoke-AR $x -at $at;V $r $at 'future';E $r.receipt.name 'future-app' 'future app';$count++
$x=New-AR 'partial' 'live-moved-to-old' 'live-moved-before-candidate' -nonce ('4'*32);D ([string]$x.q.f.f.txn);D ([string]$x.q.f.f.prepared.stage_workspace_path);$at=[DateTimeOffset]::UtcNow;$r=Invoke-AR $x -at $at;V $r $at 'partial';E $r.receipt.transaction_status 'already-absent' 'partial txn';E $r.receipt.stage_status 'already-absent' 'partial stage';T ([bool]$r.receipt.retirement_needed) 'partial incorrectly complete';$count++
$x=New-AR 'complete' -nonce ('5'*32);D ([string]$x.q.f.f.txn);D ([string]$x.q.f.f.prepared.stage_workspace_path);D ([IO.Path]::GetDirectoryName([string]$x.q.f.f.prepared.app_backup_path));D ([string]$x.q.f.f.prepared.persistence_backup_path);$at=[DateTimeOffset]::UtcNow;$r=Invoke-AR $x -at $at;V $r $at 'complete';F ([bool]$r.receipt.retirement_needed) 'complete still needed';F ([bool]$r.receipt.retirement_eligible) 'complete still eligible';T ([bool]$r.receipt.retirement_already_complete) 'complete marker missing';$count++

$x=New-AR 'live-drift' -nonce ('6'*32);[IO.File]::AppendAllText((Join-Path $x.q.f.f.q.x.live 'index.js'),"// drift`n",[Text.UTF8Encoding]::new($false));Deny (Invoke-AR $x) 'recovery-artifact-retirement-admission-live-*' 'live drift';$count++
$x=New-AR 'persist-drift' -nonce ('7'*32);[IO.File]::AppendAllText((Join-Path $x.q.f.f.q.persistence.roaming 'spicetify\config-xpui.ini'),"# drift`n",[Text.UTF8Encoding]::new($false));Deny (Invoke-AR $x) 'recovery-artifact-retirement-admission-protected-persistence-mismatch' 'protected persistence drift';$count++
$x=New-AR 'stage-drift' -nonce ('8'*32);[IO.File]::AppendAllText((Join-Path $x.q.f.f.prepared.stage_path 'index.js'),"// drift`n",[Text.UTF8Encoding]::new($false));Deny (Invoke-AR $x) 'recovery-artifact-retirement-admission-stage-state-invalid:*' 'stage drift';$count++
$x=New-AR 'app-backup-drift' -nonce ('9'*32);[IO.File]::AppendAllText((Join-Path $x.q.f.f.prepared.app_backup_path 'index.js'),"// drift`n",[Text.UTF8Encoding]::new($false));Deny (Invoke-AR $x) 'recovery-artifact-retirement-admission-app-backup-state-invalid:*' 'app backup drift';$count++
$x=New-AR 'persistence-backup-drift' -nonce ('a'*32);$p=Join-Path $x.q.f.f.prepared.persistence_backup_path 'surfaces\spicetify-config';[IO.File]::AppendAllText($p,"# backup surface drift`n",[Text.UTF8Encoding]::new($false));Deny (Invoke-AR $x) 'recovery-artifact-retirement-admission-persistence-backup-state-invalid:*' 'persistence backup drift';$count++

$x=New-AR 'txn-extra' 'live-moved-to-old' 'live-moved-before-candidate' -nonce ('b'*32);[IO.Directory]::CreateDirectory((Join-Path $x.q.f.f.txn 'unexpected'))|Out-Null;Deny (Invoke-AR $x) 'recovery-artifact-retirement-admission-transaction-state-invalid:*contents-invalid' 'transaction extra';$count++
$x=New-AR 'old-drift' 'live-moved-to-old' 'live-moved-before-candidate' -nonce ('c'*32);[IO.File]::AppendAllText((Join-Path $x.q.f.f.txn 'old-live\index.js'),"// drift`n",[Text.UTF8Encoding]::new($false));Deny (Invoke-AR $x) 'recovery-artifact-retirement-admission-transaction-state-invalid:*old-live-tree-mismatch' 'old-live drift';$count++
$x=New-AR 'candidate-drift' 'live-moved-to-old' 'live-moved-before-candidate' -nonce ('d'*32);[IO.File]::AppendAllText((Join-Path $x.q.f.f.txn 'candidate\index.js'),"// drift`n",[Text.UTF8Encoding]::new($false));Deny (Invoke-AR $x) 'recovery-artifact-retirement-admission-transaction-state-invalid:*candidate-tree-mismatch' 'candidate drift';$count++

$x=New-AR 'result-auth' -nonce ('e'*32);$bad=C $x.restore;$bad.cleanup_authorized=$true;$bad.result_fingerprint=Get-CustomAppProductionRecoveryRestoreExecutorSha256V010 (Get-CustomAppProductionRecoveryRestoreExecutorResultMaterialV010 $bad);Deny (Invoke-AR $x $bad) '*authority-escaped-cleanup_authorized*' 'restore result authority';$count++
$x=New-AR 'result-fp' -nonce ('f'*32);$bad=C $x.restore;$bad.result_fingerprint=('0'*64);Deny (Invoke-AR $x $bad) '*fingerprint-mismatch*' 'restore result fingerprint';$count++
$x=New-AR 'result-evidence' -nonce ('1'*32);$bad=C $x.restore;$bad.evidence_fingerprint=('f'*64);$bad.result_fingerprint=Get-CustomAppProductionRecoveryRestoreExecutorSha256V010 (Get-CustomAppProductionRecoveryRestoreExecutorResultMaterialV010 $bad);Deny (Invoke-AR $x $bad) 'recovery-artifact-retirement-admission-restore-result-evidence-fingerprint-mismatch' 'restore result evidence substitution';$count++
$x=New-AR 'result-journal' -nonce ('2'*32);$bad=C $x.restore;$bad.rollback_complete_entry_sha256=('e'*64);$bad.result_fingerprint=Get-CustomAppProductionRecoveryRestoreExecutorSha256V010 (Get-CustomAppProductionRecoveryRestoreExecutorResultMaterialV010 $bad);Deny (Invoke-AR $x $bad) 'recovery-artifact-retirement-admission-restore-result-journal-completion-mismatch' 'restore result journal substitution';$count++
$x=New-AR 'wrong-tx' -nonce ('3'*32);Deny (Invoke-AR $x $null ('9'*64)) 'recovery-artifact-retirement-admission-restore-result-transaction-mismatch' 'wrong transaction';$count++

$x=New-AR 'receipt' -nonce ('4'*32);$at=[DateTimeOffset]::UtcNow;$good=Invoke-AR $x -at $at;T ([bool]$good.ok) 'receipt setup failed';$ck=Test-CustomAppProductionRecoveryArtifactRetirementAdmissionReceiptV010 $good.receipt $at.AddSeconds(16);F ([bool]$ck.ok) 'expired receipt accepted';E $ck.reason 'recovery-artifact-retirement-admission-expired' 'expiry reason'
$bad=C $good.receipt;$bad.cleanup_authorized=$true;$bad.receipt_fingerprint=Get-CustomAppProductionRecoveryArtifactRetirementAdmissionSha256V010 (Get-CustomAppProductionRecoveryArtifactRetirementAdmissionMaterialV010 $bad);$ck=Test-CustomAppProductionRecoveryArtifactRetirementAdmissionReceiptV010 $bad $at.AddSeconds(1);F ([bool]$ck.ok) 'receipt authority tamper accepted';T ([string]$ck.reason-like'*authority-escaped-cleanup_authorized') 'receipt authority reason'
$bad=C $good.receipt;$bad.retirement_needed=$false;$bad.retirement_eligible=$false;$bad.retirement_already_complete=$true;$bad.requires_bounded_artifact_retirement=$false;$bad.receipt_fingerprint=Get-CustomAppProductionRecoveryArtifactRetirementAdmissionSha256V010 (Get-CustomAppProductionRecoveryArtifactRetirementAdmissionMaterialV010 $bad);$ck=Test-CustomAppProductionRecoveryArtifactRetirementAdmissionReceiptV010 $bad $at.AddSeconds(1);F ([bool]$ck.ok) 'semantic retirement status tamper+rehash accepted';E $ck.reason 'recovery-artifact-retirement-admission-semantic-status-drift' 'semantic status reason'
$bad=C $good.receipt;$bad.transaction_status='already-absent';$bad.transaction_old_status='present-verified';$bad.transaction_candidate_status='absent';$bad.receipt_fingerprint=Get-CustomAppProductionRecoveryArtifactRetirementAdmissionSha256V010 (Get-CustomAppProductionRecoveryArtifactRetirementAdmissionMaterialV010 $bad);$ck=Test-CustomAppProductionRecoveryArtifactRetirementAdmissionReceiptV010 $bad $at.AddSeconds(1);F ([bool]$ck.ok) 'transaction child status tamper+rehash accepted';E $ck.reason 'recovery-artifact-retirement-admission-transaction-child-status-drift' 'transaction child status reason';$count++

Write-Host "CUSTOM_APP_PRODUCTION_RECOVERY_ARTIFACT_RETIREMENT_ADMISSION_V011_MATRIX_PASS total=$count"
