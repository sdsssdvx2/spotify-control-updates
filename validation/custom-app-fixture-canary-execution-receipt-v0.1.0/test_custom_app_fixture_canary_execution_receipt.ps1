$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot 'custom-app-fixture-canary-execution-receipt-v012.ps1')

function Assert-True { param([bool]$Condition,[string]$Message) if(-not $Condition){throw $Message} }
function Assert-False { param([bool]$Condition,[string]$Message) if($Condition){throw $Message} }
function Copy-ReceiptFixture { param([Parameter(Mandatory=$true)]$Object) return ($Object|ConvertTo-Json -Depth 40|ConvertFrom-Json) }
function Assert-ThrowsLike {
    param([scriptblock]$Action,[string]$Pattern,[string]$Label)
    $threw=$false
    try{& $Action}catch{$threw=$true;if([string]$_.Exception.Message -notlike $Pattern){throw "$Label wrong exception: $($_.Exception.Message)"}}
    if(-not $threw){throw "$Label did not throw"}
}
function Assert-ReceiptNoAuthority {
    param([Parameter(Mandatory=$true)]$Object,[string]$Label)
    if($Object.PSObject.Properties['receipt_is_authority']){Assert-False ([bool]$Object.receipt_is_authority) "$Label receipt became authority"}
    foreach($n in @('mutation_authorized','auto_update_authorized','auto_install_authorized','canary_execution_authorized','production_mutation_authorized')){
        if($Object.PSObject.Properties[$n]){Assert-False ([bool]$Object.$n) "$Label granted $n"}
    }
    if($Object.PSObject.Properties['mutation_mode']){Assert-True ([string]$Object.mutation_mode -ceq 'deny') "$Label mutation_mode drifted"}
}

$OldTree='5805e73fa144c748ea25cbb3524a1c35a7d76eae1c33777693490b58812dbead'
$NewTree='f5866aeeb439d53756e0e25c772b8a232a547697d92976a7749708bff28bce06'
$RemoteCommit='bacd80f76c621a3acc06965bb3160ce1056fad7b'
$Token='5f31a3761f53982ba2e66b77d82b80979f3bfd53fdec337d5f298ac4c8801600'
$PermitHmac=('9'*64)
$EligibilityFingerprint=('a'*64)
$PersistenceFingerprint=('5'*64)
$GitConfigSha=('6'*64)
$BeforeProvenanceFingerprint=('7'*64)
$AfterProvenanceFingerprint=('8'*64)
$ReceiptKey=[byte[]](64..95)
$WrongReceiptKey=[byte[]](96..127)
$ReceiptNonce='0123456789abcdef0123456789abcdef'
$ObservedAt=[DateTimeOffset]::Parse('2026-10-28T12:30:00+00:00')

function New-PermitFixture {
    return [pscustomobject]@{
        schema=1;managed_by='custom-app-fixture-canary-permit-v1';qualified_eligibility_head=$CustomAppFixtureCanaryReceiptQualifiedEligibilityHead;scope='fixture-canary-only'
        name='tagify';source_identity='alexk218/tagify';github_repo_id=[int64]1021838879;surface_kind='release-asset'
        current_tree_sha256=$OldTree;remote_tree_sha256=$NewTree;remote_commit_sha=$RemoteCommit;token_id=$Token;hmac_sha256=$PermitHmac;eligibility_fingerprint=$EligibilityFingerprint
        mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;canary_execution_authorized=$false;production_mutation_authorized=$false
    }
}
function New-EligibilityFixture {
    return [pscustomobject]@{
        schema=1;managed_by='custom-app-promotion-eligibility-v1';promotion_candidate_eligible=$true;requires_revalidation_before_any_mutation=$true
        name='tagify';source_identity='alexk218/tagify';github_repo_id=[int64]1021838879;surface_kind='release-asset';eligibility_fingerprint=$EligibilityFingerprint
        current_tree_sha256=$OldTree;remote_tree_sha256=$NewTree;remote_commit_sha=$RemoteCommit
        mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;canary_execution_authorized=$false;production_mutation_authorized=$false
    }
}
function New-BeforeEvidenceFixture {
    return New-CustomAppFixtureCanaryEvidenceV012 -RuntimeTreeSha256 $OldTree -ManifestName 'Tagify' -PersistenceFingerprint $PersistenceFingerprint -ProvenanceSourceIdentity 'alexk218/tagify' -ProvenanceGitConfigSha256 $GitConfigSha -ProvenanceEvidenceFingerprint $BeforeProvenanceFingerprint
}
function New-CommittedAfterEvidenceFixture {
    return New-CustomAppFixtureCanaryEvidenceV012 -RuntimeTreeSha256 $NewTree -ManifestName 'Tagify' -PersistenceFingerprint $PersistenceFingerprint -ProvenanceSourceIdentity 'alexk218/tagify' -ProvenanceGitConfigSha256 $GitConfigSha -ProvenanceEvidenceFingerprint $AfterProvenanceFingerprint
}
function New-ExecutorResultFixture {
    param([string]$Status='committed-fixture-canary',[bool]$Committed=$true,[bool]$RolledBack=$false,[bool]$FixtureAuthorized=$true,[AllowNull()][string]$TokenId=$Token,[AllowNull()][string]$EligibilityFp=$EligibilityFingerprint)
    return [pscustomobject]@{
        schema=1;managed_by='custom-app-fixture-canary-executor-v1';qualified_permit_head=$CustomAppFixtureCanaryReceiptQualifiedPermitImplementationHead
        name='tagify';status=$Status;reason=('fixture-'+$Status);committed=$Committed;rolled_back=$RolledBack;token_id=$TokenId;eligibility_fingerprint=$EligibilityFp
        fixture_canary_execution_authorized=$FixtureAuthorized;mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;canary_execution_authorized=$false;production_mutation_authorized=$false
    }
}
function New-ReceiptFromFixtures {
    param([Parameter(Mandatory=$true)]$ExecutorResult,[Parameter(Mandatory=$true)]$Before,[Parameter(Mandatory=$true)]$After,[AllowNull()]$Permit=$null,[AllowNull()]$Eligibility=$null,[AllowNull()]$Qualification=$null,[AllowNull()][byte[]]$Key=$null,[string]$Nonce=$ReceiptNonce)
    if($null -eq $Permit){$Permit=New-PermitFixture};if($null -eq $Eligibility){$Eligibility=New-EligibilityFixture};if($null -eq $Qualification){$Qualification=New-CustomAppFixtureCanaryExecutorQualificationV012};if($null -eq $Key){$Key=$ReceiptKey}
    return New-CustomAppFixtureCanaryExecutionReceiptV012 -ExecutorResult $ExecutorResult -Permit $Permit -EligibilityDecision $Eligibility -BeforeEvidence $Before -AfterEvidence $After -ExecutorQualification $Qualification -ReceiptKey $Key -Nonce $Nonce -ObservedAt $ObservedAt
}
function Assert-ReceiptClass {
    param([Parameter(Mandatory=$true)]$Receipt,[string]$Classification,[bool]$Safe,[bool]$Qualified,[string]$Label)
    Assert-True ([string]$Receipt.outcome_classification -ceq $Classification) "$Label classification drifted: $($Receipt.outcome_classification)"
    Assert-True ([bool]$Receipt.outcome_safe -eq $Safe) "$Label safe flag drifted"
    Assert-True ([bool]$Receipt.outcome_evidence_qualified -eq $Qualified) "$Label qualified flag drifted"
    Assert-ReceiptNoAuthority -Object $Receipt -Label $Label
    $verified=Test-CustomAppFixtureCanaryExecutionReceiptV012 -Receipt $Receipt -ReceiptKey $ReceiptKey -ExecutorQualification (New-CustomAppFixtureCanaryExecutorQualificationV012)
    Assert-True ([bool]$verified.ok) "$Label receipt verification failed: $($verified.reason)"
    Assert-ReceiptNoAuthority -Object $verified -Label ($Label+'-verified')
}

$before=New-BeforeEvidenceFixture
$afterCommitted=New-CommittedAfterEvidenceFixture
$qualification=New-CustomAppFixtureCanaryExecutorQualificationV012
$qCheck=Test-CustomAppFixtureCanaryExecutorQualificationV012 -Qualification $qualification
Assert-True ([bool]$qCheck.ok) ('qualified executor fixture rejected: '+[string]$qCheck.reason)
Assert-True (Test-CustomAppFixtureCanaryReceiptSha256V012 ([string]$qCheck.fingerprint)) 'executor qualification fingerprint invalid'

$committed=New-ReceiptFromFixtures -ExecutorResult (New-ExecutorResultFixture) -Before $before -After $afterCommitted
Assert-ReceiptClass -Receipt $committed -Classification 'committed-preserved' -Safe $true -Qualified $true -Label 'committed'
Assert-True ([string]$committed.before_runtime_tree_sha256 -ceq $OldTree -and [string]$committed.after_runtime_tree_sha256 -ceq $NewTree) 'committed receipt tree transition drifted'
Assert-True ([string]$committed.before_persistence_fingerprint -ceq [string]$committed.after_persistence_fingerprint) 'committed receipt did not attest persistence preservation'
Assert-True ([string]$committed.before_provenance_git_config_sha256 -ceq [string]$committed.after_provenance_git_config_sha256) 'committed receipt did not attest git provenance preservation'
Assert-True ([string]$committed.before_provenance_evidence_fingerprint -cne [string]$committed.after_provenance_evidence_fingerprint) 'committed receipt incorrectly required aggregate provenance evidence equality'

$committed2=New-ReceiptFromFixtures -ExecutorResult (New-ExecutorResultFixture) -Before $before -After $afterCommitted
Assert-True ([string]$committed.receipt_id -ceq [string]$committed2.receipt_id -and [string]$committed.hmac_sha256 -ceq [string]$committed2.hmac_sha256) 'receipt was not deterministic for identical inputs'

$deniedPre=New-ExecutorResultFixture -Status 'denied-before-consumption' -Committed $false -RolledBack $false -FixtureAuthorized $false -TokenId $null -EligibilityFp $null
$deniedPreReceipt=New-ReceiptFromFixtures -ExecutorResult $deniedPre -Before $before -After $before
Assert-ReceiptClass -Receipt $deniedPreReceipt -Classification 'denied-no-mutation' -Safe $true -Qualified $true -Label 'denied-pre-consumption'

$deniedAfter=New-ExecutorResultFixture -Status 'denied-after-staging' -Committed $false -RolledBack $false -FixtureAuthorized $false
$deniedAfterReceipt=New-ReceiptFromFixtures -ExecutorResult $deniedAfter -Before $before -After $before
Assert-ReceiptClass -Receipt $deniedAfterReceipt -Classification 'denied-no-mutation' -Safe $true -Qualified $true -Label 'denied-after-staging'

$rolled=New-ExecutorResultFixture -Status 'denied-or-rolled-back-fixture-canary' -Committed $false -RolledBack $true -FixtureAuthorized $false
$rolledReceipt=New-ReceiptFromFixtures -ExecutorResult $rolled -Before $before -After $before
Assert-ReceiptClass -Receipt $rolledReceipt -Classification 'rolled-back-restored' -Safe $true -Qualified $true -Label 'rolled-back'

$driftAfter=New-CustomAppFixtureCanaryEvidenceV012 -RuntimeTreeSha256 ('b'*64) -ManifestName 'Tagify' -PersistenceFingerprint $PersistenceFingerprint -ProvenanceSourceIdentity 'alexk218/tagify' -ProvenanceGitConfigSha256 $GitConfigSha -ProvenanceEvidenceFingerprint $BeforeProvenanceFingerprint
$rolledDriftReceipt=New-ReceiptFromFixtures -ExecutorResult $rolled -Before $before -After $driftAfter
Assert-ReceiptClass -Receipt $rolledDriftReceipt -Classification 'failure-unqualified' -Safe $false -Qualified $false -Label 'rollback-drift'

$deniedDriftReceipt=New-ReceiptFromFixtures -ExecutorResult $deniedAfter -Before $before -After $driftAfter
Assert-ReceiptClass -Receipt $deniedDriftReceipt -Classification 'failure-unqualified' -Safe $false -Qualified $false -Label 'denial-drift'

$wrongTreeAfter=New-CustomAppFixtureCanaryEvidenceV012 -RuntimeTreeSha256 ('c'*64) -ManifestName 'Tagify' -PersistenceFingerprint $PersistenceFingerprint -ProvenanceSourceIdentity 'alexk218/tagify' -ProvenanceGitConfigSha256 $GitConfigSha -ProvenanceEvidenceFingerprint $AfterProvenanceFingerprint
$wrongTreeReceipt=New-ReceiptFromFixtures -ExecutorResult (New-ExecutorResultFixture) -Before $before -After $wrongTreeAfter
Assert-ReceiptClass -Receipt $wrongTreeReceipt -Classification 'failure-unqualified' -Safe $false -Qualified $false -Label 'commit-wrong-tree'

$persistenceDriftAfter=New-CustomAppFixtureCanaryEvidenceV012 -RuntimeTreeSha256 $NewTree -ManifestName 'Tagify' -PersistenceFingerprint ('d'*64) -ProvenanceSourceIdentity 'alexk218/tagify' -ProvenanceGitConfigSha256 $GitConfigSha -ProvenanceEvidenceFingerprint $AfterProvenanceFingerprint
$persistenceDriftReceipt=New-ReceiptFromFixtures -ExecutorResult (New-ExecutorResultFixture) -Before $before -After $persistenceDriftAfter
Assert-ReceiptClass -Receipt $persistenceDriftReceipt -Classification 'failure-unqualified' -Safe $false -Qualified $false -Label 'commit-persistence-drift'

$provenanceDriftAfter=New-CustomAppFixtureCanaryEvidenceV012 -RuntimeTreeSha256 $NewTree -ManifestName 'Tagify' -PersistenceFingerprint $PersistenceFingerprint -ProvenanceSourceIdentity 'alexk218/tagify' -ProvenanceGitConfigSha256 ('e'*64) -ProvenanceEvidenceFingerprint $AfterProvenanceFingerprint
$provenanceDriftReceipt=New-ReceiptFromFixtures -ExecutorResult (New-ExecutorResultFixture) -Before $before -After $provenanceDriftAfter
Assert-ReceiptClass -Receipt $provenanceDriftReceipt -Classification 'failure-unqualified' -Safe $false -Qualified $false -Label 'commit-provenance-drift'

$genericFailure=New-ExecutorResultFixture -Status 'failed-fixture-canary' -Committed $false -RolledBack $false -FixtureAuthorized $false
$genericFailureReceipt=New-ReceiptFromFixtures -ExecutorResult $genericFailure -Before $before -After $before
Assert-ReceiptClass -Receipt $genericFailureReceipt -Classification 'failure-unqualified' -Safe $false -Qualified $false -Label 'generic-failure'

$throws=0
$badQualification=New-CustomAppFixtureCanaryExecutorQualificationV012;$badQualification.executor_head=('1'*40)
Assert-ThrowsLike -Action {New-ReceiptFromFixtures -ExecutorResult (New-ExecutorResultFixture) -Before $before -After $afterCommitted -Qualification $badQualification|Out-Null} -Pattern '*executor-qualification-lineage-mismatch*' -Label 'qualification-head-drift';$throws++
$badQualification2=New-CustomAppFixtureCanaryExecutorQualificationV012;$badQualification2.push_run_id=[int64]1
Assert-ThrowsLike -Action {New-ReceiptFromFixtures -ExecutorResult (New-ExecutorResultFixture) -Before $before -After $afterCommitted -Qualification $badQualification2|Out-Null} -Pattern '*executor-qualification-run-or-artifact-mismatch*' -Label 'qualification-run-drift';$throws++
$badQualification3=New-CustomAppFixtureCanaryExecutorQualificationV012;$badQualification3.push_artifact_digest=('sha256:'+('1'*64))
Assert-ThrowsLike -Action {New-ReceiptFromFixtures -ExecutorResult (New-ExecutorResultFixture) -Before $before -After $afterCommitted -Qualification $badQualification3|Out-Null} -Pattern '*executor-qualification-artifact-digest-mismatch*' -Label 'qualification-digest-drift';$throws++
$badQualification4=New-CustomAppFixtureCanaryExecutorQualificationV012;$badQualification4.production_mutation_authorized=$true
Assert-ThrowsLike -Action {New-ReceiptFromFixtures -ExecutorResult (New-ExecutorResultFixture) -Before $before -After $afterCommitted -Qualification $badQualification4|Out-Null} -Pattern '*production_mutation_authorized-true*' -Label 'qualification-authority-drift';$throws++
$badPermit=New-PermitFixture;$badPermit.production_mutation_authorized=$true
Assert-ThrowsLike -Action {New-ReceiptFromFixtures -ExecutorResult (New-ExecutorResultFixture) -Before $before -After $afterCommitted -Permit $badPermit|Out-Null} -Pattern '*Permit authority denied*' -Label 'permit-authority-drift';$throws++
$badPermit2=New-PermitFixture;$badPermit.qualified_eligibility_head=('2'*40)
Assert-ThrowsLike -Action {New-ReceiptFromFixtures -ExecutorResult (New-ExecutorResultFixture) -Before $before -After $afterCommitted -Permit $badPermit2|Out-Null} -Pattern '*Permit owner/schema/eligibility lineage mismatch*' -Label 'permit-lineage-drift';$throws++
$badEligibility=New-EligibilityFixture;$badEligibility.auto_update_authorized=$true
Assert-ThrowsLike -Action {New-ReceiptFromFixtures -ExecutorResult (New-ExecutorResultFixture) -Before $before -After $afterCommitted -Eligibility $badEligibility|Out-Null} -Pattern '*Eligibility authority denied*' -Label 'eligibility-authority-drift';$throws++
$badEligibility2=New-EligibilityFixture;$badEligibility2.remote_tree_sha256=('3'*64)
Assert-ThrowsLike -Action {New-ReceiptFromFixtures -ExecutorResult (New-ExecutorResultFixture) -Before $before -After $afterCommitted -Eligibility $badEligibility2|Out-Null} -Pattern '*Eligibility decision does not match permit execution identity*' -Label 'eligibility-identity-drift';$throws++
$badEvidence=Copy-ReceiptFixture $before;$badEvidence.evidence_fingerprint=('4'*64)
Assert-ThrowsLike -Action {New-ReceiptFromFixtures -ExecutorResult (New-ExecutorResultFixture) -Before $badEvidence -After $afterCommitted|Out-Null} -Pattern '*before-evidence-fingerprint-mismatch*' -Label 'before-evidence-fingerprint-drift';$throws++
$shortKey=[byte[]](0..15)
Assert-ThrowsLike -Action {New-ReceiptFromFixtures -ExecutorResult (New-ExecutorResultFixture) -Before $before -After $afterCommitted -Key $shortKey|Out-Null} -Pattern '*at least 32 bytes*' -Label 'short-receipt-key';$throws++
Assert-ThrowsLike -Action {New-ReceiptFromFixtures -ExecutorResult (New-ExecutorResultFixture) -Before $before -After $afterCommitted -Nonce 'bad'|Out-Null} -Pattern '*32 lowercase hex*' -Label 'bad-receipt-nonce';$throws++

$tamperCases=New-Object System.Collections.Generic.List[object]
function Add-TamperCase { param([string]$Label,[scriptblock]$Mutate,[string]$ExpectedReason) $r=Copy-ReceiptFixture $committed;& $Mutate $r;$tamperCases.Add([pscustomobject]@{label=$Label;receipt=$r;reason=$ExpectedReason}) }
Add-TamperCase 'classification' {param($r)$r.outcome_classification='denied-no-mutation'} 'receipt-id-mismatch'
Add-TamperCase 'executor-reason' {param($r)$r.executor_reason='tampered'} 'receipt-id-mismatch'
Add-TamperCase 'before-manifest' {param($r)$r.before_manifest_name='Wrong'} 'receipt-id-mismatch'
Add-TamperCase 'after-provenance-evidence' {param($r)$r.after_provenance_evidence_fingerprint=('1'*64)} 'receipt-id-mismatch'
Add-TamperCase 'receipt-authority' {param($r)$r.receipt_is_authority=$true} 'receipt-authority-separation-flags-invalid'
Add-TamperCase 'production-authority' {param($r)$r.production_mutation_authorized=$true} 'receipt-production_mutation_authorized-true'
Add-TamperCase 'nonce' {param($r)$r.nonce='fedcba9876543210fedcba9876543210'} 'receipt-id-mismatch'
Add-TamperCase 'remote-commit' {param($r)$r.remote_commit_sha=('b'*40)} 'receipt-id-mismatch'
Add-TamperCase 'qualification-fingerprint' {param($r)$r.executor_qualification_fingerprint=('2'*64)} 'receipt-executor-qualification-fingerprint-mismatch'
Add-TamperCase 'receipt-id' {param($r)$r.receipt_id=('3'*64)} 'receipt-id-mismatch'
Add-TamperCase 'hmac' {param($r)$r.hmac_sha256=('4'*64)} 'receipt-hmac-mismatch'

$tampered=0
foreach($case in $tamperCases){
    $v=Test-CustomAppFixtureCanaryExecutionReceiptV012 -Receipt $case.receipt -ReceiptKey $ReceiptKey -ExecutorQualification (New-CustomAppFixtureCanaryExecutorQualificationV012)
    Assert-False ([bool]$v.ok) ($case.label+' tamper unexpectedly verified')
    Assert-True ([string]$v.reason -ceq [string]$case.reason) ($case.label+' tamper reason drifted: '+[string]$v.reason+' != '+[string]$case.reason)
    Assert-ReceiptNoAuthority -Object $v -Label ($case.label+'-tamper-result')
    $tampered++
}

$wrongKeyResult=Test-CustomAppFixtureCanaryExecutionReceiptV012 -Receipt $committed -ReceiptKey $WrongReceiptKey -ExecutorQualification (New-CustomAppFixtureCanaryExecutorQualificationV012)
Assert-False ([bool]$wrongKeyResult.ok) 'wrong receipt key unexpectedly verified'
Assert-True ([string]$wrongKeyResult.reason -ceq 'receipt-hmac-mismatch') ('wrong key reason drifted: '+[string]$wrongKeyResult.reason)
$tampered++
$wrongVerifyQualification=New-CustomAppFixtureCanaryExecutorQualificationV012;$wrongVerifyQualification.pull_request_run_id=[int64]1
$wrongQResult=Test-CustomAppFixtureCanaryExecutionReceiptV012 -Receipt $committed -ReceiptKey $ReceiptKey -ExecutorQualification $wrongVerifyQualification
Assert-False ([bool]$wrongQResult.ok) 'wrong executor qualification unexpectedly verified receipt'
Assert-True ([string]$wrongQResult.reason -like 'receipt-executor-qualification-denied:*') ('wrong qualification verify reason drifted: '+[string]$wrongQResult.reason)
$tampered++

Write-Host ('CUSTOM_APP_FIXTURE_CANARY_RECEIPT_MATRIX_PASS committed=1 denied=2 rollback=1 unsafe_failure_receipts=4 throws='+$throws+' tamper_denied='+$tampered+' total='+ (1+2+1+4+$throws+$tampered))
