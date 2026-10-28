$CustomAppLiveAttestedFixtureCanarySchema = 1
$CustomAppLiveAttestedFixtureCanaryManagedBy = 'custom-app-live-attested-fixture-canary-v1'
$CustomAppLiveAttestedFixtureCanaryReceiptHead = '635e25a4a06320cd103e07b1506f0ba8787e5c3a'
$CustomAppLiveAttestedFixtureCanaryExecutorHead = 'a5d5839a9d6c1dd01c1fced6e9e1f5f76d16b5ca'

function Test-CustomAppLiveAttestedAuthorityDeniedV010 {
    param([AllowNull()]$Object,[string]$Label='object')
    if($null -eq $Object){return [pscustomobject]@{ok=$false;reason=($Label+'-null')}}
    if(-not $Object.PSObject.Properties['mutation_mode'] -or [string]$Object.mutation_mode -cne 'deny'){return [pscustomobject]@{ok=$false;reason=($Label+'-mutation-mode-not-deny')}}
    foreach($name in @('mutation_authorized','auto_update_authorized','auto_install_authorized','canary_execution_authorized','production_mutation_authorized')){
        if(-not $Object.PSObject.Properties[$name]){return [pscustomobject]@{ok=$false;reason=($Label+'-authority-schema-missing-'+$name)}}
        if([bool]$Object.$name){return [pscustomobject]@{ok=$false;reason=($Label+'-'+$name+'-true')}}
    }
    return [pscustomobject]@{ok=$true;reason=($Label+'-authority-denied')}
}

function New-CustomAppLiveAttestedFixtureCanaryResultV010 {
    param(
        [Parameter(Mandatory=$true)]$ExecutorResult,
        [Parameter(Mandatory=$true)]$Permit,
        [Parameter(Mandatory=$true)]$EligibilityDecision,
        [Parameter(Mandatory=$true)]$BeforeEvidence,
        [Parameter(Mandatory=$true)]$AfterEvidence,
        [Parameter(Mandatory=$true)]$ExecutorQualification,
        [Parameter(Mandatory=$true)][byte[]]$ReceiptKey,
        [Parameter(Mandatory=$true)][string]$ReceiptNonce,
        [DateTimeOffset]$ObservedAt=[DateTimeOffset]::UtcNow
    )
    if($ReceiptKey.Length -lt 32){throw 'Live-attested fixture receipt key must be at least 32 bytes.'}
    $executorAuthority=Test-CustomAppLiveAttestedAuthorityDeniedV010 -Object $ExecutorResult -Label 'executor-result'
    if(-not [bool]$executorAuthority.ok){throw ('Live-attested executor authority denied: '+[string]$executorAuthority.reason)}
    if([int]$ExecutorResult.schema -ne 1 -or [string]$ExecutorResult.managed_by -cne 'custom-app-fixture-canary-executor-v1' -or [string]$ExecutorResult.qualified_permit_head -cne '79c7ef064a216ee3ff34328be282d742f0f7abc0'){
        throw 'Live-attested executor owner/schema/permit lineage mismatch.'
    }
    $qualification=Test-CustomAppFixtureCanaryExecutorQualificationV013 -Qualification $ExecutorQualification
    if(-not [bool]$qualification.ok){throw ('Live-attested executor qualification denied: '+[string]$qualification.reason)}

    $receipt=New-CustomAppFixtureCanaryExecutionReceiptV013 -ExecutorResult $ExecutorResult -Permit $Permit -EligibilityDecision $EligibilityDecision -BeforeEvidence $BeforeEvidence -AfterEvidence $AfterEvidence -ExecutorQualification $ExecutorQualification -ReceiptKey $ReceiptKey -Nonce $ReceiptNonce -ObservedAt $ObservedAt
    $verify=Test-CustomAppFixtureCanaryExecutionReceiptV013 -Receipt $receipt -ReceiptKey $ReceiptKey -ExecutorQualification $ExecutorQualification
    if(-not [bool]$verify.ok){throw ('Live-attested receipt self-verification failed: '+[string]$verify.reason)}
    if([bool]$receipt.receipt_is_authority -or -not [bool]$receipt.requires_fresh_revalidation_before_any_future_action){throw 'Live-attested receipt authority separation failed.'}
    if([bool]$receipt.mutation_authorized -or [bool]$receipt.auto_update_authorized -or [bool]$receipt.auto_install_authorized -or [bool]$receipt.canary_execution_authorized -or [bool]$receipt.production_mutation_authorized){throw 'Live-attested receipt granted forbidden authority.'}

    $executorStatus=[string]$ExecutorResult.status
    if($executorStatus -ceq 'committed-fixture-canary'){
        if(-not [bool]$ExecutorResult.committed -or [bool]$ExecutorResult.rolled_back){throw 'Committed live-attested executor flags are inconsistent.'}
        if([string]$receipt.outcome_classification -cne 'committed-preserved' -or -not [bool]$receipt.outcome_safe -or -not [bool]$receipt.outcome_evidence_qualified){throw 'Committed live-attested execution was not receipt-qualified as committed-preserved.'}
    } elseif([bool]$ExecutorResult.committed) {
        throw 'Non-committed executor status carried committed=true.'
    }

    return [pscustomobject]@{
        schema=$CustomAppLiveAttestedFixtureCanarySchema
        managed_by=$CustomAppLiveAttestedFixtureCanaryManagedBy
        qualified_receipt_head=$CustomAppLiveAttestedFixtureCanaryReceiptHead
        qualified_executor_head=$CustomAppLiveAttestedFixtureCanaryExecutorHead
        name=[string]$receipt.name
        source_identity=[string]$receipt.source_identity
        executor_status=$executorStatus
        executor_committed=[bool]$ExecutorResult.committed
        executor_rolled_back=[bool]$ExecutorResult.rolled_back
        outcome_classification=[string]$receipt.outcome_classification
        outcome_safe=[bool]$receipt.outcome_safe
        outcome_evidence_qualified=[bool]$receipt.outcome_evidence_qualified
        receipt_id=[string]$receipt.receipt_id
        receipt_hmac_sha256=[string]$receipt.hmac_sha256
        receipt=$receipt
        attestation_verified=$true
        evidence_source='caller-supplied-pre-post-observation'
        live_fixture_only=$true
        receipt_is_authority=$false
        requires_fresh_revalidation_before_any_future_action=$true
        mutation_mode='deny'
        mutation_authorized=$false
        auto_update_authorized=$false
        auto_install_authorized=$false
        canary_execution_authorized=$false
        production_mutation_authorized=$false
    }
}

function Test-CustomAppLiveAttestedFixtureCanaryResultV010 {
    param(
        [AllowNull()]$Result,
        [Parameter(Mandatory=$true)][byte[]]$ReceiptKey,
        [Parameter(Mandatory=$true)]$ExecutorQualification
    )
    if($null -eq $Result){return [pscustomobject]@{ok=$false;reason='live-attested-result-null'}}
    if([int]$Result.schema -ne 1 -or [string]$Result.managed_by -cne $CustomAppLiveAttestedFixtureCanaryManagedBy){return [pscustomobject]@{ok=$false;reason='live-attested-owner-or-schema-mismatch'}}
    if([string]$Result.qualified_receipt_head -cne $CustomAppLiveAttestedFixtureCanaryReceiptHead -or [string]$Result.qualified_executor_head -cne $CustomAppLiveAttestedFixtureCanaryExecutorHead){return [pscustomobject]@{ok=$false;reason='live-attested-lineage-mismatch'}}
    $authority=Test-CustomAppLiveAttestedAuthorityDeniedV010 -Object $Result -Label 'live-attested-result'
    if(-not [bool]$authority.ok){return [pscustomobject]@{ok=$false;reason=[string]$authority.reason}}
    if([bool]$Result.receipt_is_authority -or -not [bool]$Result.requires_fresh_revalidation_before_any_future_action -or -not [bool]$Result.live_fixture_only -or -not [bool]$Result.attestation_verified){return [pscustomobject]@{ok=$false;reason='live-attested-separation-flags-invalid'}}
    if($null -eq $Result.receipt){return [pscustomobject]@{ok=$false;reason='live-attested-receipt-missing'}}
    $verify=Test-CustomAppFixtureCanaryExecutionReceiptV013 -Receipt $Result.receipt -ReceiptKey $ReceiptKey -ExecutorQualification $ExecutorQualification
    if(-not [bool]$verify.ok){return [pscustomobject]@{ok=$false;reason=('live-attested-receipt-invalid:'+[string]$verify.reason)}}
    if([string]$Result.receipt_id -cne [string]$Result.receipt.receipt_id -or [string]$Result.receipt_hmac_sha256 -cne [string]$Result.receipt.hmac_sha256){return [pscustomobject]@{ok=$false;reason='live-attested-receipt-identity-mismatch'}}
    if([string]$Result.outcome_classification -cne [string]$Result.receipt.outcome_classification -or [bool]$Result.outcome_safe -ne [bool]$Result.receipt.outcome_safe -or [bool]$Result.outcome_evidence_qualified -ne [bool]$Result.receipt.outcome_evidence_qualified){return [pscustomobject]@{ok=$false;reason='live-attested-outcome-mismatch'}}
    if([bool]$Result.executor_committed){
        if([string]$Result.executor_status -cne 'committed-fixture-canary' -or [string]$Result.outcome_classification -cne 'committed-preserved' -or -not [bool]$Result.outcome_safe -or -not [bool]$Result.outcome_evidence_qualified){return [pscustomobject]@{ok=$false;reason='live-attested-committed-semantics-invalid'}}
    }
    return [pscustomobject]@{ok=$true;reason='live-attested-fixture-canary-receipt-valid';receipt_id=[string]$Result.receipt_id;outcome_classification=[string]$Result.outcome_classification;receipt_is_authority=$false;production_mutation_authorized=$false}
}
