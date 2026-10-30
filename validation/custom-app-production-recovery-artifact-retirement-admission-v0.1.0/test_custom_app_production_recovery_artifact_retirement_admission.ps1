$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-recovery-restore-executor-v0.1.0/test_custom_app_production_recovery_restore_executor.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-recovery-artifact-retirement-admission.ps1')

function Assert-ARTrue([bool]$v,[string]$m){if(-not$v){throw $m}}
function Assert-ARFalse([bool]$v,[string]$m){if($v){throw $m}}
function Assert-AREq($a,$b,[string]$m){if([string]$a-cne[string]$b){throw "$m actual=<$a> expected=<$b>"}}
function Copy-AR($x){return (($x|ConvertTo-Json -Depth 60)|ConvertFrom-Json)}
function Remove-ARPath([string]$Path){if(Test-Path -LiteralPath $Path){[IO.Directory]::Delete($Path,$true)}}

function New-ARFixtureV010 {
    param([string]$Label,[string]$Phase='transaction-finalized',[string]$State='finalized',[string]$Name='tagify',[string]$Source='alexk218/tagify',[string]$Manifest='Tagify',[string]$Nonce=('1'*32))
    $q=New-RXFixtureV010 -Label ('retire-'+$Label) -Phase $Phase -State $State -Name $Name -Source $Source -Manifest $Manifest -Nonce $Nonce
    $r=Invoke-RXFixtureV010 $q
    if(-not[bool]$r.ok){throw ('retirement fixture restore failed: '+[string]$r.reason)}
    Assert-RXSuccessV010 $q $r $Phase ($Phase-cne'rollback-required') ('retirement-'+$Label)
    return [pscustomobject]@{q=$q;restore=$r.result}
}
function Invoke-ARFixtureV010 {
    param($Q,[AllowNull()]$Restore=$null,[AllowNull()][string]$Tx=$null,[DateTimeOffset]$At=[DateTimeOffset]::UtcNow)
    if($null-eq$Restore){$Restore=$Q.restore};if([string]::IsNullOrWhiteSpace($Tx)){$Tx=[string]$Q.q.f.f.identity.transaction_id}
    return Resolve-CustomAppProductionRecoveryArtifactRetirementAdmissionV010 -AllowedRoot $Q.q.f.f.allowed -StoreDirectory $Q.q.f.f.store -ExpectedTransactionId $Tx -RestoreExecutorResult $Restore -LocalAppDataRoot $Q.q.f.f.q.persistence.local -AppDataRoot $Q.q.f.f.q.persistence.roaming -Now $At
}
function Assert-ARNoAuthorityV010($R,[string]$Label){$x=if($R.PSObject.Properties['receipt']){$R.receipt}else{$R};foreach($f in @('admission_is_authority','execution_authorized','restore_authorized','apply_authorized','cleanup_authorized','production_mutation_authorized')){Assert-ARFalse ([bool]$x.$f) "$Label authority escaped $f"}}
function Assert-ARValidV010($R,[DateTimeOffset]$At,[string]$Label){Assert-ARTrue ([bool]$R.ok) "$Label denied: $([string]$R.reason)";Assert-ARNoAuthorityV010 $R $Label;$c=Test-CustomAppProductionRecoveryArtifactRetirementAdmissionReceiptV010 -Receipt $R.receipt -Now $At.AddSeconds(1);Assert-ARTrue ([bool]$c.ok) "$Label receipt invalid: $([string]$c.reason)";Assert-AREq $R.receipt.phase 'rollback-complete' "$Label phase"}

$count=0
$present=New-ARFixtureV010 -Label 'txn-present' -Phase 'live-moved-to-old' -State 'live-moved-before-candidate' -Nonce ('1'*32);$at=[DateTimeOffset]::UtcNow;$r=Invoke-ARFixtureV010 -Q $present -At $at;Assert-ARValidV010 $r $at 'txn-present';Assert-AREq $r.receipt.transaction_status 'present-verified' 'txn present status';Assert-AREq $r.receipt.stage_status 'present-verified' 'stage present';Assert-AREq $r.receipt.app_backup_status 'present-verified' 'app backup present';Assert-AREq $r.receipt.persistence_backup_status 'present-verified' 'persistence backup present';Assert-ARTrue ([bool]$r.receipt.retirement_needed) 'retirement unexpectedly not needed';Assert-ARTrue ([bool]$r.receipt.retirement_eligible) 'retirement not eligible';$count++

$absentTxn=New-ARFixtureV010 -Label 'txn-absent' -Phase 'transaction-finalized' -State 'finalized' -Nonce ('2'*32);$at=[DateTimeOffset]::UtcNow;$r=Invoke-ARFixtureV010 -Q $absentTxn -At $at;Assert-ARValidV010 $r $at 'txn-absent';Assert-AREq $r.receipt.transaction_status 'already-absent' 'txn absent status';Assert-ARTrue ([bool]$r.receipt.retirement_needed) 'retirement needed lost with absent txn';$count++

$future=New-ARFixtureV010 -Label 'future-app' -Phase 'live-moved-to-old' -State 'live-moved-before-candidate' -Name 'future-app' -Source 'owner/future-app' -Manifest 'Future App' -Nonce ('3'*32);$at=[DateTimeOffset]::UtcNow;$r=Invoke-ARFixtureV010 -Q $future -At $at;Assert-ARValidV010 $r $at 'future-app';Assert-AREq $r.receipt.name 'future-app' 'future identity';$count++

$partial=New-ARFixtureV010 -Label 'partial-retired' -Phase 'live-moved-to-old' -State 'live-moved-before-candidate' -Nonce ('4'*32);Remove-ARPath ([string]$partial.q.f.f.txn);Remove-ARPath ([string]$partial.q.f.f.prepared.stage_workspace_path);$at=[DateTimeOffset]::UtcNow;$r=Invoke-ARFixtureV010 -Q $partial -At $at;Assert-ARValidV010 $r $at 'partial-retired';Assert-AREq $r.receipt.transaction_status 'already-absent' 'partial txn';Assert-AREq $r.receipt.stage_status 'already-absent' 'partial stage';Assert-ARTrue ([bool]$r.receipt.retirement_needed) 'partial retirement incorrectly complete';$count++

$complete=New-ARFixtureV010 -Label 'already-complete' -Nonce ('5'*32);Remove-ARPath ([string]$complete.q.f.f.txn);Remove-ARPath ([string]$complete.q.f.f.prepared.stage_workspace_path);Remove-ARPath ([IO.Path]::GetDirectoryName([string]$complete.q.f.f.prepared.app_backup_path));Remove-ARPath ([string]$complete.q.f.f.prepared.persistence_backup_path);$at=[DateTimeOffset]::UtcNow;$r=Invoke-ARFixtureV010 -Q $complete -At $at;Assert-ARValidV010 $r $at 'already-complete';Assert-ARFalse ([bool]$r.receipt.retirement_needed) 'already complete still needs retirement';Assert-ARFalse ([bool]$r.receipt.retirement_eligible) 'already complete eligible for deletion';Assert-ARTrue ([bool]$r.receipt.retirement_already_complete) 'already complete marker missing';$count++

$liveDrift=New-ARFixtureV010 -Label 'live-drift' -Nonce ('6'*32);[IO.File]::AppendAllText((Join-Path ([string]$liveDrift.q.f.f.q.x.live) 'index.js'),"// retirement live drift`n",[Text.UTF8Encoding]::new($false));$r=Invoke-ARFixtureV010 $liveDrift;Assert-ARFalse ([bool]$r.ok) 'live drift accepted';Assert-ARTrue ([string]$r.reason-like'recovery-artifact-retirement-admission-live-*') 'live drift reason';$count++

$persistDrift=New-ARFixtureV010 -Label 'persistence-drift' -Nonce ('7'*32);[IO.File]::AppendAllText((Join-Path ([string]$persistDrift.q.f.f.q.persistence.roaming) 'spicetify\config-xpui.ini'),"# retirement persistence drift`n",[Text.UTF8Encoding]::new($false));$r=Invoke-ARFixtureV010 $persistDrift;Assert-ARFalse ([bool]$r.ok) 'protected persistence drift accepted';Assert-AREq $r.reason 'recovery-artifact-retirement-admission-protected-persistence-mismatch' 'persistence drift reason';$count++

$stageDrift=New-ARFixtureV010 -Label 'stage-drift' -Nonce ('8'*32);[IO.File]::AppendAllText((Join-Path ([string]$stageDrift.q.f.f.prepared.stage_path) 'index.js'),"// retirement stage drift`n",[Text.UTF8Encoding]::new($false));$r=Invoke-ARFixtureV010 $stageDrift;Assert-ARFalse ([bool]$r.ok) 'stage drift accepted';Assert-ARTrue ([string]$r.reason-like'recovery-artifact-retirement-admission-stage-state-invalid:*') 'stage drift reason';$count++

$appDrift=New-ARFixtureV010 -Label 'app-backup-drift' -Nonce ('9'*32);[IO.File]::AppendAllText((Join-Path ([string]$appDrift.q.f.f.prepared.app_backup_path) 'index.js'),"// retirement app backup drift`n",[Text.UTF8Encoding]::new($false));$r=Invoke-ARFixtureV010 $appDrift;Assert-ARFalse ([bool]$r.ok) 'app backup drift accepted';Assert-ARTrue ([string]$r.reason-like'recovery-artifact-retirement-admission-app-backup-state-invalid:*') 'app backup drift reason';$count++

$pbDrift=New-ARFixtureV010 -Label 'persistence-backup-drift' -Nonce ('a'*32);[IO.File]::AppendAllText((Join-Path ([string]$pbDrift.q.f.f.prepared.persistence_backup_path) 'guard-manifest.json')," `n",[Text.UTF8Encoding]::new($false));$r=Invoke-ARFixtureV010 $pbDrift;Assert-ARFalse ([bool]$r.ok) 'persistence backup drift accepted';Assert-ARTrue ([string]$r.reason-like'recovery-artifact-retirement-admission-persistence-backup-state-invalid:*') 'persistence backup drift reason';$count++

$txnExtra=New-ARFixtureV010 -Label 'transaction-extra' -Phase 'live-moved-to-old' -State 'live-moved-before-candidate' -Nonce ('b'*32);[IO.Directory]::CreateDirectory((Join-Path ([string]$txnExtra.q.f.f.txn) 'unexpected'))|Out-Null;$r=Invoke-ARFixtureV010 $txnExtra;Assert-ARFalse ([bool]$r.ok) 'transaction extra child accepted';Assert-ARTrue ([string]$r.reason-like'recovery-artifact-retirement-admission-transaction-state-invalid:*contents-invalid') 'transaction extra reason';$count++

$oldDrift=New-ARFixtureV010 -Label 'old-live-drift' -Phase 'live-moved-to-old' -State 'live-moved-before-candidate' -Nonce ('c'*32);[IO.File]::AppendAllText((Join-Path ([string]$oldDrift.q.f.f.txn) 'old-live\index.js'),"// retirement old-live drift`n",[Text.UTF8Encoding]::new($false));$r=Invoke-ARFixtureV010 $oldDrift;Assert-ARFalse ([bool]$r.ok) 'transaction old-live drift accepted';Assert-ARTrue ([string]$r.reason-like'recovery-artifact-retirement-admission-transaction-state-invalid:*old-live-tree-mismatch') 'old-live drift reason';$count++

$candidateDrift=New-ARFixtureV010 -Label 'candidate-drift' -Phase 'live-moved-to-old' -State 'live-moved-before-candidate' -Nonce ('d'*32);[IO.File]::AppendAllText((Join-Path ([string]$candidateDrift.q.f.f.txn) 'candidate\index.js'),"// retirement candidate drift`n",[Text.UTF8Encoding]::new($false));$r=Invoke-ARFixtureV010 $candidateDrift;Assert-ARFalse ([bool]$r.ok) 'transaction candidate drift accepted';Assert-ARTrue ([string]$r.reason-like'recovery-artifact-retirement-admission-transaction-state-invalid:*candidate-tree-mismatch') 'candidate drift reason';$count++

$resultAuth=New-ARFixtureV010 -Label 'result-authority' -Nonce ('e'*32);$bad=Copy-AR $resultAuth.restore;$bad.cleanup_authorized=$true;$bad.result_fingerprint=Get-CustomAppProductionRecoveryRestoreExecutorSha256V010 (Get-CustomAppProductionRecoveryRestoreExecutorResultMaterialV010 -Result $bad);$r=Invoke-ARFixtureV010 -Q $resultAuth -Restore $bad;Assert-ARFalse ([bool]$r.ok) 'authority-tampered restore result accepted';Assert-ARTrue ([string]$r.reason-like'*authority-escaped-cleanup_authorized*') 'restore authority reason';$count++

$resultFp=New-ARFixtureV010 -Label 'result-fingerprint' -Nonce ('f'*32);$bad=Copy-AR $resultFp.restore;$bad.result_fingerprint=('0'*64);$r=Invoke-ARFixtureV010 -Q $resultFp -Restore $bad;Assert-ARFalse ([bool]$r.ok) 'fingerprint-tampered restore result accepted';Assert-ARTrue ([string]$r.reason-like'*fingerprint-mismatch') 'restore fingerprint reason';$count++

$resultEvidence=New-ARFixtureV010 -Label 'result-evidence' -Nonce ('1'*32);$bad=Copy-AR $resultEvidence.restore;$bad.evidence_fingerprint=('f'*64);$bad.result_fingerprint=Get-CustomAppProductionRecoveryRestoreExecutorSha256V010 (Get-CustomAppProductionRecoveryRestoreExecutorResultMaterialV010 -Result $bad);$r=Invoke-ARFixtureV010 -Q $resultEvidence -Restore $bad;Assert-ARFalse ([bool]$r.ok) 'restore result evidence substitution accepted';Assert-AREq $r.reason 'recovery-artifact-retirement-admission-restore-result-evidence-fingerprint-mismatch' 'result evidence reason';$count++

$resultJournal=New-ARFixtureV010 -Label 'result-journal' -Nonce ('2'*32);$bad=Copy-AR $resultJournal.restore;$bad.rollback_complete_entry_sha256=('e'*64);$bad.result_fingerprint=Get-CustomAppProductionRecoveryRestoreExecutorSha256V010 (Get-CustomAppProductionRecoveryRestoreExecutorResultMaterialV010 -Result $bad);$r=Invoke-ARFixtureV010 -Q $resultJournal -Restore $bad;Assert-ARFalse ([bool]$r.ok) 'restore result journal substitution accepted';Assert-AREq $r.reason 'recovery-artifact-retirement-admission-restore-result-journal-completion-mismatch' 'result journal reason';$count++

$wrongTx=New-ARFixtureV010 -Label 'wrong-transaction' -Nonce ('3'*32);$r=Invoke-ARFixtureV010 -Q $wrongTx -Tx ('9'*64);Assert-ARFalse ([bool]$r.ok) 'wrong transaction accepted';Assert-AREq $r.reason 'recovery-artifact-retirement-admission-restore-result-transaction-mismatch' 'wrong transaction reason';$count++

$expiry=New-ARFixtureV010 -Label 'expiry' -Nonce ('4'*32);$at=[DateTimeOffset]::UtcNow;$good=Invoke-ARFixtureV010 -Q $expiry -At $at;Assert-ARTrue ([bool]$good.ok) 'expiry setup failed';$ck=Test-CustomAppProductionRecoveryArtifactRetirementAdmissionReceiptV010 -Receipt $good.receipt -Now $at.AddSeconds(16);Assert-ARFalse ([bool]$ck.ok) 'expired retirement admission accepted';Assert-AREq $ck.reason 'recovery-artifact-retirement-admission-expired' 'expiry reason';$count++

$receiptTamper=New-ARFixtureV010 -Label 'receipt-tamper' -Nonce ('5'*32);$at=[DateTimeOffset]::UtcNow;$good=Invoke-ARFixtureV010 -Q $receiptTamper -At $at;$bad=Copy-AR $good.receipt;$bad.cleanup_authorized=$true;$bad.receipt_fingerprint=Get-CustomAppProductionRecoveryArtifactRetirementAdmissionSha256V010 (Get-CustomAppProductionRecoveryArtifactRetirementAdmissionMaterialV010 -Receipt $bad);$ck=Test-CustomAppProductionRecoveryArtifactRetirementAdmissionReceiptV010 -Receipt $bad -Now $at.AddSeconds(1);Assert-ARFalse ([bool]$ck.ok) 'authority-tampered retirement receipt accepted';Assert-ARTrue ([string]$ck.reason-like'*authority-escaped-cleanup_authorized') 'retirement receipt authority reason';$bad=Copy-AR $good.receipt;$bad.retirement_needed=$false;$bad.retirement_eligible=$false;$bad.retirement_already_complete=$true;$bad.requires_bounded_artifact_retirement=$false;$bad.receipt_fingerprint=Get-CustomAppProductionRecoveryArtifactRetirementAdmissionSha256V010 (Get-CustomAppProductionRecoveryArtifactRetirementAdmissionMaterialV010 -Receipt $bad);$ck=Test-CustomAppProductionRecoveryArtifactRetirementAdmissionReceiptV010 -Receipt $bad -Now $at.AddSeconds(1);Assert-ARFalse ([bool]$ck.ok) 'semantic retirement status tamper+rehash accepted';$count++

Write-Host "CUSTOM_APP_PRODUCTION_RECOVERY_ARTIFACT_RETIREMENT_ADMISSION_MATRIX_PASS total=$count"
