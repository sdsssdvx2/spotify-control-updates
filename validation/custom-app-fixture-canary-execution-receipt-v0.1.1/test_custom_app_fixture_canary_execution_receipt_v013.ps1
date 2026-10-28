$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot 'custom-app-fixture-canary-execution-receipt-v013.ps1')

function Assert-True {param([bool]$Condition,[string]$Message)if(-not $Condition){throw $Message}}
function Assert-False {param([bool]$Condition,[string]$Message)if($Condition){throw $Message}}
function Copy-Fixture {param([Parameter(Mandatory=$true)]$Object)return ($Object|ConvertTo-Json -Depth 40|ConvertFrom-Json)}
function Assert-ThrowsLike {
    param([scriptblock]$Action,[string]$Pattern,[string]$Label)
    $threw=$false
    try{& $Action}catch{$threw=$true;if([string]$_.Exception.Message -notlike $Pattern){throw "$Label wrong exception: $($_.Exception.Message)"}}
    if(-not $threw){throw "$Label did not throw"}
}
function Assert-NoAuthority {
    param([Parameter(Mandatory=$true)]$Object,[string]$Label)
    if($Object.PSObject.Properties['receipt_is_authority']){Assert-False ([bool]$Object.receipt_is_authority) "$Label receipt became authority"}
    foreach($n in @('mutation_authorized','auto_update_authorized','auto_install_authorized','canary_execution_authorized','production_mutation_authorized')){if($Object.PSObject.Properties[$n]){Assert-False ([bool]$Object.$n) "$Label granted $n"}}
    if($Object.PSObject.Properties['mutation_mode']){Assert-True ([string]$Object.mutation_mode -ceq 'deny') "$Label mutation mode drifted"}
}

$OldTree='5805e73fa144c748ea25cbb3524a1c35a7d76eae1c33777693490b58812dbead'
$NewTree='f5866aeeb439d53756e0e25c772b8a232a547697d92976a7749708bff28bce06'
$RemoteCommit='bacd80f76c621a3acc06965bb3160ce1056fad7b'
$Token='5f31a3761f53982ba2e66b77d82b80979f3bfd53fdec337d5f298ac4c8801600'
$PermitHmac=('9'*64);$EligibilityFingerprint=('a'*64);$PersistenceFingerprint=('5'*64);$GitConfigSha=('6'*64);$BeforeProvenanceFingerprint=('7'*64);$AfterProvenanceFingerprint=('8'*64)
$ReceiptKey=[byte[]](64..95);$WrongReceiptKey=[byte[]](96..127);$ReceiptNonce='0123456789abcdef0123456789abcdef';$ObservedAt=[DateTimeOffset]::Parse('2026-10-28T12:30:00+00:00')

function New-PermitFixture {
    return [pscustomobject]@{schema=1;managed_by='custom-app-fixture-canary-permit-v1';qualified_eligibility_head=$CustomAppFixtureCanaryReceiptQualifiedEligibilityHead;scope='fixture-canary-only';name='tagify';source_identity='alexk218/tagify';github_repo_id=[int64]1021838879;surface_kind='release-asset';current_tree_sha256=$OldTree;remote_tree_sha256=$NewTree;remote_commit_sha=$RemoteCommit;token_id=$Token;hmac_sha256=$PermitHmac;eligibility_fingerprint=$EligibilityFingerprint;mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;canary_execution_authorized=$false;production_mutation_authorized=$false}
}
function New-EligibilityFixture {
    param([bool]$Eligible=$true)
    return [pscustomobject]@{schema=1;managed_by='custom-app-promotion-eligibility-v1';promotion_candidate_eligible=$Eligible;requires_revalidation_before_any_mutation=$true;name='tagify';source_identity='alexk218/tagify';github_repo_id=[int64]1021838879;surface_kind='release-asset';eligibility_fingerprint=$EligibilityFingerprint;current_tree_sha256=$OldTree;remote_tree_sha256=$NewTree;remote_commit_sha=$RemoteCommit;mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;canary_execution_authorized=$false;production_mutation_authorized=$false}
}
function New-Evidence {
    param([string]$Tree,[string]$Manifest='Tagify',[string]$Persistence=$PersistenceFingerprint,[string]$Source='alexk218/tagify',[string]$Git=$GitConfigSha,[string]$Provenance=$BeforeProvenanceFingerprint)
    return New-CustomAppFixtureCanaryEvidenceV013 -RuntimeTreeSha256 $Tree -ManifestName $Manifest -PersistenceFingerprint $Persistence -ProvenanceSourceIdentity $Source -ProvenanceGitConfigSha256 $Git -ProvenanceEvidenceFingerprint $Provenance
}
function New-ExecutorResult {
    param([string]$Status='committed-fixture-canary',[bool]$Committed=$true,[bool]$RolledBack=$false,[bool]$FixtureAuthorized=$true,[AllowNull()][string]$TokenId=$Token,[AllowNull()][string]$EligibilityFp=$EligibilityFingerprint)
    return [pscustomobject]@{schema=1;managed_by='custom-app-fixture-canary-executor-v1';qualified_permit_head=$CustomAppFixtureCanaryReceiptQualifiedPermitImplementationHead;name='tagify';status=$Status;reason=('fixture-'+$Status);committed=$Committed;rolled_back=$RolledBack;token_id=$TokenId;eligibility_fingerprint=$EligibilityFp;fixture_canary_execution_authorized=$FixtureAuthorized;mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;canary_execution_authorized=$false;production_mutation_authorized=$false}
}
function New-ReceiptFixture {
    param([Parameter(Mandatory=$true)]$Executor,[Parameter(Mandatory=$true)]$Before,[Parameter(Mandatory=$true)]$After,[AllowNull()]$Permit=$null,[AllowNull()]$Eligibility=$null,[AllowNull()]$Qualification=$null,[AllowNull()][byte[]]$Key=$null,[string]$Nonce=$ReceiptNonce)
    if($null -eq $Permit){$Permit=New-PermitFixture};if($null -eq $Eligibility){$Eligibility=New-EligibilityFixture};if($null -eq $Qualification){$Qualification=New-CustomAppFixtureCanaryExecutorQualificationV013};if($null -eq $Key){$Key=$ReceiptKey}
    return New-CustomAppFixtureCanaryExecutionReceiptV013 -ExecutorResult $Executor -Permit $Permit -EligibilityDecision $Eligibility -BeforeEvidence $Before -AfterEvidence $After -ExecutorQualification $Qualification -ReceiptKey $Key -Nonce $Nonce -ObservedAt $ObservedAt
}
function Assert-ReceiptClass {
    param([Parameter(Mandatory=$true)]$Receipt,[string]$Class,[bool]$Safe,[bool]$Qualified,[string]$Label)
    Assert-True ([string]$Receipt.outcome_classification -ceq $Class) "$Label class drifted: $($Receipt.outcome_classification)"
    Assert-True ([bool]$Receipt.outcome_safe -eq $Safe) "$Label safe drifted";Assert-True ([bool]$Receipt.outcome_evidence_qualified -eq $Qualified) "$Label qualified drifted";Assert-NoAuthority -Object $Receipt -Label $Label
    $v=Test-CustomAppFixtureCanaryExecutionReceiptV013 -Receipt $Receipt -ReceiptKey $ReceiptKey -ExecutorQualification (New-CustomAppFixtureCanaryExecutorQualificationV013)
    Assert-True ([bool]$v.ok) "$Label verification failed: $($v.reason)";Assert-NoAuthority -Object $v -Label ($Label+'-verify')
}
function Resign-ReceiptFixture {
    param([Parameter(Mandatory=$true)]$Receipt)
    $Receipt.receipt_id=$null;$Receipt.hmac_sha256=$null;$material=Get-CustomAppFixtureCanaryReceiptMaterialV013 -Receipt $Receipt;$Receipt.receipt_id=Get-CustomAppFixtureCanaryReceiptSha256V013 -Text $material;$Receipt.hmac_sha256=Get-CustomAppFixtureCanaryReceiptHmacV013 -Text $material -ReceiptKey $ReceiptKey;return $Receipt
}

$before=New-Evidence -Tree $OldTree
$afterCommitted=New-Evidence -Tree $NewTree -Provenance $AfterProvenanceFingerprint
$q=New-CustomAppFixtureCanaryExecutorQualificationV013;$qCheck=Test-CustomAppFixtureCanaryExecutorQualificationV013 -Qualification $q
Assert-True ([bool]$qCheck.ok) ('executor qualification rejected: '+[string]$qCheck.reason);Assert-True (Test-CustomAppFixtureCanaryReceiptSha256V013 ([string]$qCheck.fingerprint)) 'executor qualification fingerprint invalid'

$committed=New-ReceiptFixture -Executor (New-ExecutorResult) -Before $before -After $afterCommitted
Assert-ReceiptClass -Receipt $committed -Class 'committed-preserved' -Safe $true -Qualified $true -Label 'committed'
Assert-True ([string]$committed.current_tree_sha256 -ceq $OldTree -and [string]$committed.remote_tree_sha256 -ceq $NewTree) 'permit current/remote tree not bound into receipt'
Assert-True ([string]$committed.before_manifest_name -ceq [string]$committed.after_manifest_name) 'committed manifest continuity missing'
Assert-True ([string]$committed.before_persistence_fingerprint -ceq [string]$committed.after_persistence_fingerprint) 'committed persistence preservation missing'
Assert-True ([string]$committed.before_provenance_git_config_sha256 -ceq [string]$committed.after_provenance_git_config_sha256) 'committed git provenance preservation missing'
Assert-True ([string]$committed.before_provenance_evidence_fingerprint -cne [string]$committed.after_provenance_evidence_fingerprint) 'committed receipt incorrectly requires aggregate provenance evidence equality'
$committed2=New-ReceiptFixture -Executor (New-ExecutorResult) -Before $before -After $afterCommitted
Assert-True ([string]$committed.receipt_id -ceq [string]$committed2.receipt_id -and [string]$committed.hmac_sha256 -ceq [string]$committed2.hmac_sha256) 'identical receipt inputs were not deterministic'

$deniedPre=New-ExecutorResult -Status 'denied-before-consumption' -Committed $false -RolledBack $false -FixtureAuthorized $false -TokenId $null -EligibilityFp $null
$deniedPreReceipt=New-ReceiptFixture -Executor $deniedPre -Before $before -After $before;Assert-ReceiptClass -Receipt $deniedPreReceipt -Class 'denied-no-mutation' -Safe $true -Qualified $true -Label 'denied-before-consumption'
$deniedAfter=New-ExecutorResult -Status 'denied-after-staging' -Committed $false -RolledBack $false -FixtureAuthorized $false
$deniedAfterReceipt=New-ReceiptFixture -Executor $deniedAfter -Before $before -After $before;Assert-ReceiptClass -Receipt $deniedAfterReceipt -Class 'denied-no-mutation' -Safe $true -Qualified $true -Label 'denied-after-staging'
$rolled=New-ExecutorResult -Status 'denied-or-rolled-back-fixture-canary' -Committed $false -RolledBack $true -FixtureAuthorized $false
$rolledReceipt=New-ReceiptFixture -Executor $rolled -Before $before -After $before;Assert-ReceiptClass -Receipt $rolledReceipt -Class 'rolled-back-restored' -Safe $true -Qualified $true -Label 'rolled-back'

$unsafe=0
$driftAfter=New-Evidence -Tree ('b'*64)
$r=New-ReceiptFixture -Executor $rolled -Before $before -After $driftAfter;Assert-ReceiptClass -Receipt $r -Class 'failure-unqualified' -Safe $false -Qualified $false -Label 'rollback-drift';$unsafe++
$r=New-ReceiptFixture -Executor $deniedAfter -Before $before -After $driftAfter;Assert-ReceiptClass -Receipt $r -Class 'failure-unqualified' -Safe $false -Qualified $false -Label 'denial-drift';$unsafe++
$r=New-ReceiptFixture -Executor (New-ExecutorResult) -Before $before -After (New-Evidence -Tree ('c'*64) -Provenance $AfterProvenanceFingerprint);Assert-ReceiptClass -Receipt $r -Class 'failure-unqualified' -Safe $false -Qualified $false -Label 'commit-wrong-tree';$unsafe++
$r=New-ReceiptFixture -Executor (New-ExecutorResult) -Before $before -After (New-Evidence -Tree $NewTree -Persistence ('d'*64) -Provenance $AfterProvenanceFingerprint);Assert-ReceiptClass -Receipt $r -Class 'failure-unqualified' -Safe $false -Qualified $false -Label 'commit-persistence-drift';$unsafe++
$r=New-ReceiptFixture -Executor (New-ExecutorResult) -Before $before -After (New-Evidence -Tree $NewTree -Git ('e'*64) -Provenance $AfterProvenanceFingerprint);Assert-ReceiptClass -Receipt $r -Class 'failure-unqualified' -Safe $false -Qualified $false -Label 'commit-provenance-drift';$unsafe++
$r=New-ReceiptFixture -Executor (New-ExecutorResult) -Before $before -After (New-Evidence -Tree $NewTree -Manifest 'Tagify-Renamed' -Provenance $AfterProvenanceFingerprint);Assert-ReceiptClass -Receipt $r -Class 'failure-unqualified' -Safe $false -Qualified $false -Label 'commit-manifest-drift';$unsafe++
$r=New-ReceiptFixture -Executor (New-ExecutorResult -Status 'failed-fixture-canary' -Committed $false -RolledBack $false -FixtureAuthorized $false) -Before $before -After $before;Assert-ReceiptClass -Receipt $r -Class 'failure-unqualified' -Safe $false -Qualified $false -Label 'generic-failure';$unsafe++
$r=New-ReceiptFixture -Executor (New-ExecutorResult) -Before $before -After $afterCommitted -Eligibility (New-EligibilityFixture -Eligible $false);Assert-ReceiptClass -Receipt $r -Class 'failure-unqualified' -Safe $false -Qualified $false -Label 'commit-noneligible-snapshot';$unsafe++
Assert-True ($unsafe -eq 8) 'unsafe receipt case count drifted'

$throws=0
$bad=New-CustomAppFixtureCanaryExecutorQualificationV013;$bad.executor_head=('1'*40);Assert-ThrowsLike {New-ReceiptFixture -Executor (New-ExecutorResult) -Before $before -After $afterCommitted -Qualification $bad|Out-Null} '*executor-qualification-lineage-mismatch*' 'qualification-head';$throws++
$bad=New-CustomAppFixtureCanaryExecutorQualificationV013;$bad.push_run_id=[int64]1;Assert-ThrowsLike {New-ReceiptFixture -Executor (New-ExecutorResult) -Before $before -After $afterCommitted -Qualification $bad|Out-Null} '*executor-qualification-run-or-artifact-mismatch*' 'qualification-run';$throws++
$bad=New-CustomAppFixtureCanaryExecutorQualificationV013;$bad.push_artifact_digest=('sha256:'+('1'*64));Assert-ThrowsLike {New-ReceiptFixture -Executor (New-ExecutorResult) -Before $before -After $afterCommitted -Qualification $bad|Out-Null} '*executor-qualification-artifact-digest-mismatch*' 'qualification-digest';$throws++
$bad=New-CustomAppFixtureCanaryExecutorQualificationV013;$bad.production_mutation_authorized=$true;Assert-ThrowsLike {New-ReceiptFixture -Executor (New-ExecutorResult) -Before $before -After $afterCommitted -Qualification $bad|Out-Null} '*production_mutation_authorized-true*' 'qualification-authority';$throws++
$badPermit=New-PermitFixture;$badPermit.production_mutation_authorized=$true;Assert-ThrowsLike {New-ReceiptFixture -Executor (New-ExecutorResult) -Before $before -After $afterCommitted -Permit $badPermit|Out-Null} '*Permit authority denied*' 'permit-authority';$throws++
$badPermit=New-PermitFixture;$badPermit.qualified_eligibility_head=('2'*40);Assert-ThrowsLike {New-ReceiptFixture -Executor (New-ExecutorResult) -Before $before -After $afterCommitted -Permit $badPermit|Out-Null} '*Permit owner/schema/eligibility lineage mismatch*' 'permit-lineage';$throws++
$badElig=New-EligibilityFixture;$badElig.auto_update_authorized=$true;Assert-ThrowsLike {New-ReceiptFixture -Executor (New-ExecutorResult) -Before $before -After $afterCommitted -Eligibility $badElig|Out-Null} '*Eligibility authority denied*' 'eligibility-authority';$throws++
$badElig=New-EligibilityFixture;$badElig.current_tree_sha256=('3'*64);Assert-ThrowsLike {New-ReceiptFixture -Executor (New-ExecutorResult) -Before $before -After $afterCommitted -Eligibility $badElig|Out-Null} '*Eligibility decision does not match permit execution identity*' 'eligibility-identity';$throws++
$badEvidence=Copy-Fixture $before;$badEvidence.evidence_fingerprint=('4'*64);Assert-ThrowsLike {New-ReceiptFixture -Executor (New-ExecutorResult) -Before $badEvidence -After $afterCommitted|Out-Null} '*before-evidence-fingerprint-mismatch*' 'before-evidence';$throws++
$short=[byte[]](0..15);Assert-ThrowsLike {New-ReceiptFixture -Executor (New-ExecutorResult) -Before $before -After $afterCommitted -Key $short|Out-Null} '*at least 32 bytes*' 'short-key';$throws++
Assert-ThrowsLike {New-ReceiptFixture -Executor (New-ExecutorResult) -Before $before -After $afterCommitted -Nonce 'bad'|Out-Null} '*32 lowercase hex*' 'bad-nonce';$throws++
Assert-True ($throws -eq 11) 'throw case count drifted'

$tamper=New-Object System.Collections.Generic.List[object]
function Add-Tamper {param([string]$Label,[scriptblock]$Mutate,[string]$Reason)$x=Copy-Fixture $committed;& $Mutate $x;$tamper.Add([pscustomobject]@{label=$Label;receipt=$x;reason=$Reason})}
Add-Tamper 'classification' {param($x)$x.outcome_classification='denied-no-mutation'} 'receipt-id-mismatch'
Add-Tamper 'executor-reason' {param($x)$x.executor_reason='tampered'} 'receipt-id-mismatch'
Add-Tamper 'current-tree' {param($x)$x.current_tree_sha256=('1'*64)} 'receipt-id-mismatch'
Add-Tamper 'before-manifest' {param($x)$x.before_manifest_name='Wrong'} 'receipt-id-mismatch'
Add-Tamper 'after-provenance-evidence' {param($x)$x.after_provenance_evidence_fingerprint=('1'*64)} 'receipt-id-mismatch'
Add-Tamper 'receipt-authority' {param($x)$x.receipt_is_authority=$true} 'receipt-authority-separation-flags-invalid'
Add-Tamper 'production-authority' {param($x)$x.production_mutation_authorized=$true} 'receipt-production_mutation_authorized-true'
Add-Tamper 'nonce' {param($x)$x.nonce='fedcba9876543210fedcba9876543210'} 'receipt-id-mismatch'
Add-Tamper 'remote-commit' {param($x)$x.remote_commit_sha=('b'*40)} 'receipt-id-mismatch'
Add-Tamper 'qualification-fingerprint' {param($x)$x.executor_qualification_fingerprint=('2'*64)} 'receipt-executor-qualification-fingerprint-mismatch'
Add-Tamper 'receipt-id' {param($x)$x.receipt_id=('3'*64)} 'receipt-id-mismatch'
Add-Tamper 'hmac' {param($x)$x.hmac_sha256=('4'*64)} 'receipt-hmac-mismatch'
$tampered=0
foreach($case in $tamper){$v=Test-CustomAppFixtureCanaryExecutionReceiptV013 -Receipt $case.receipt -ReceiptKey $ReceiptKey -ExecutorQualification (New-CustomAppFixtureCanaryExecutorQualificationV013);Assert-False ([bool]$v.ok) ($case.label+' tamper unexpectedly verified');Assert-True ([string]$v.reason -ceq [string]$case.reason) ($case.label+' reason drifted: '+[string]$v.reason+' != '+[string]$case.reason);$tampered++}
$v=Test-CustomAppFixtureCanaryExecutionReceiptV013 -Receipt $committed -ReceiptKey $WrongReceiptKey -ExecutorQualification (New-CustomAppFixtureCanaryExecutorQualificationV013);Assert-False ([bool]$v.ok) 'wrong key verified';Assert-True ([string]$v.reason -ceq 'receipt-hmac-mismatch') ('wrong-key reason drifted: '+[string]$v.reason);$tampered++
$badQ=New-CustomAppFixtureCanaryExecutorQualificationV013;$badQ.pull_request_run_id=[int64]1;$v=Test-CustomAppFixtureCanaryExecutionReceiptV013 -Receipt $committed -ReceiptKey $ReceiptKey -ExecutorQualification $badQ;Assert-False ([bool]$v.ok) 'wrong qualification verified';Assert-True ([string]$v.reason -like 'receipt-executor-qualification-denied:*') ('wrong-q reason drifted: '+[string]$v.reason);$tampered++
Assert-True ($tampered -eq 14) 'tamper case count drifted'

$semanticForgery=0
$x=Copy-Fixture $committed;$x.committed=$false;$x=Resign-ReceiptFixture $x;$v=Test-CustomAppFixtureCanaryExecutionReceiptV013 -Receipt $x -ReceiptKey $ReceiptKey -ExecutorQualification (New-CustomAppFixtureCanaryExecutorQualificationV013);Assert-False ([bool]$v.ok) 'resigned committed flag forgery verified';Assert-True ([string]$v.reason -ceq 'receipt-committed-flags-invalid') ('committed semantic reason drifted: '+[string]$v.reason);$semanticForgery++
$x=Copy-Fixture $deniedAfterReceipt;$x.after_evidence_fingerprint=('1'*64);$x=Resign-ReceiptFixture $x;$v=Test-CustomAppFixtureCanaryExecutionReceiptV013 -Receipt $x -ReceiptKey $ReceiptKey -ExecutorQualification (New-CustomAppFixtureCanaryExecutorQualificationV013);Assert-False ([bool]$v.ok) 'resigned denial evidence forgery verified';Assert-True ([string]$v.reason -ceq 'receipt-denied-semantics-invalid') ('denial semantic reason drifted: '+[string]$v.reason);$semanticForgery++
$x=Copy-Fixture $rolledReceipt;$x.after_evidence_fingerprint=('2'*64);$x=Resign-ReceiptFixture $x;$v=Test-CustomAppFixtureCanaryExecutionReceiptV013 -Receipt $x -ReceiptKey $ReceiptKey -ExecutorQualification (New-CustomAppFixtureCanaryExecutorQualificationV013);Assert-False ([bool]$v.ok) 'resigned rollback evidence forgery verified';Assert-True ([string]$v.reason -ceq 'receipt-rollback-semantics-invalid') ('rollback semantic reason drifted: '+[string]$v.reason);$semanticForgery++
$x=Copy-Fixture $genericFailureReceipt;$x.outcome_safe=$true;$x=Resign-ReceiptFixture $x;$v=Test-CustomAppFixtureCanaryExecutionReceiptV013 -Receipt $x -ReceiptKey $ReceiptKey -ExecutorQualification (New-CustomAppFixtureCanaryExecutorQualificationV013);Assert-False ([bool]$v.ok) 'resigned failure-safe forgery verified';Assert-True ([string]$v.reason -ceq 'receipt-failure-flags-invalid') ('failure semantic reason drifted: '+[string]$v.reason);$semanticForgery++
Assert-True ($semanticForgery -eq 4) 'semantic forgery case count drifted'

Write-Host ('CUSTOM_APP_FIXTURE_CANARY_RECEIPT_V013_MATRIX_PASS committed=1 denied=2 rollback=1 unsafe_failure_receipts='+$unsafe+' throws='+$throws+' crypto_tamper_denied='+$tampered+' resigned_semantic_forgery_denied='+$semanticForgery+' total='+(1+2+1+$unsafe+$throws+$tampered+$semanticForgery))
