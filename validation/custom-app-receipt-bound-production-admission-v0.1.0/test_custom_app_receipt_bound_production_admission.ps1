$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-promotion-eligibility-gate-v0.1.0/custom-app-promotion-eligibility.ps1')
. (Join-Path $root 'validation/custom-app-fixture-canary-execution-receipt-v0.1.1/custom-app-fixture-canary-execution-receipt-v013.ps1')
. (Join-Path $PSScriptRoot 'custom-app-receipt-bound-production-admission.ps1')

function Assert-True { param([bool]$Condition,[string]$Message) if(-not $Condition){throw $Message} }
function Copy-Deep { param($Object) return ($Object|ConvertTo-Json -Depth 20|ConvertFrom-Json) }
function New-DeniedAuthorityFields {
    return [ordered]@{mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;canary_execution_authorized=$false;production_mutation_authorized=$false}
}
function Add-DeniedAuthorityFields { param($Object) foreach($p in (New-DeniedAuthorityFields).GetEnumerator()){$Object|Add-Member -NotePropertyName $p.Key -NotePropertyValue $p.Value -Force};return $Object }

function New-FixtureContext {
    param([int]$ReceiptAgeHours=1,[switch]$DeniedReceipt)
    $now=[DateTimeOffset]'2026-10-28T12:00:00Z'
    $source='alexk218/tagify';$name='tagify';$manifest='Tagify';$livePath='C:\fixture\CustomApps\tagify'
    $current=Get-CustomAppReceiptBoundAdmissionSha256V010 'current-runtime-tree'
    $remote=Get-CustomAppReceiptBoundAdmissionSha256V010 'remote-runtime-tree'
    $prov=Get-CustomAppReceiptBoundAdmissionSha256V010 'current-provenance-evidence'
    $git=Get-CustomAppReceiptBoundAdmissionSha256V010 'git-config-bytes'
    $persist=Get-CustomAppReceiptBoundAdmissionSha256V010 'persistence-fingerprint'
    $assetDigest=Get-CustomAppReceiptBoundAdmissionSha256V010 'release-asset'
    $commit='bacd80f76c621a3acc06965bb3160ce1056fad7b'

    $protocol=[pscustomobject]@{
        schema=1;managed_by='custom-app-shadow-protocol-qualification-v1';validated_shadow_head='22eb3561843fbe4016023d527186aa629512b67d';validated_stage_parent='c420a1df6f306c7ba74772b91241cb14abd04738';production_main='d38e88d9ae99f6a4983e2ad64f74f6fce7e6cde2'
        addon_manager_sha256='b2cec989ef399aed4a8763105121b21181ffb493ed9e3e884baa1d62a634f94b';spotify_control_sha256='69ef7fb3ca57b4d5faac6873ac06dffc38f6e5b0d1ad8fc31fcbe2bb236f5c99'
        push_success=$true;pull_request_success=$true;offline_matrix_passed=$true;live_tagify_331_to_332_passed=$true;parent_selftest_passed=$true
        push_run_id=[int64]40673331603;pull_request_run_id=[int64]40673541954;push_artifact_id=[int64]12808363735;pull_request_artifact_id=[int64]12809940304
        push_artifact_digest='sha256:ab1d0b651e89c19670d75fc07082cdadde81f5082a791554ed4861b02b8740dd';pull_request_artifact_digest='sha256:9ce022e987f6522b767aa330f2e1338210b13ceb5c34617377b548949dcc6c0c'
        mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;canary_execution_authorized=$false;production_mutation_authorized=$false
    }
    $lifecycle=[pscustomobject]@{managed_by='dynamic-spicetify-v1';kind='custom-app';name=$name;present=$true;user_removed=$false;ambiguous=$false;safe_local_identity=$true;locations=@($livePath);mutation_mode='deny'}
    $provenance=[pscustomobject]@{schema=1;managed_by='custom-app-provenance-v1';name=$name;source_identity=$source;last_proven_source=$source;source_changed=$false;requires_reenrollment=$false;evidence_fingerprint=$prov;mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;canary_execution_authorized=$false;production_mutation_authorized=$false}
    $binding=[pscustomobject]@{
        schema=1;managed_by='custom-app-remote-source-v1';source_identity=$source;github_repo_id=[int64]987654321;surface_kind='release-asset';layout_root='.';manifest_name=$manifest
        last_verified_local_tree_sha256=$current;last_verified_remote_tree_sha256=$remote;last_verified_commit_sha=$commit;release_asset_selector='unique-zip-asset';asset_name='tagify-v3.3.2.zip';last_observed_asset_id=[int64]418974188;last_observed_asset_digest_sha256=$assetDigest
        mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;canary_execution_authorized=$false;production_mutation_authorized=$false
    }
    $bindingRow=[pscustomobject]@{
        schema=1;managed_by='custom-app-remote-binding-observer-v1';name=$name;active=$true;user_removed=$false;requires_reenrollment=$false;update_observed=$true;last_status='remote-change-observed';source_identity=$source
        last_success=$now.AddHours(-1).ToString('o');last_local_tree_sha256=$current;last_remote_tree_sha256=$remote;last_remote_commit_sha=$commit;last_local_manifest_name=$manifest;binding=$binding
        mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;canary_execution_authorized=$false;production_mutation_authorized=$false
    }
    $baseline=[pscustomobject]@{safe=$true;installable=$true;tree_sha256=$current;manifest_name=$manifest;path=$livePath}
    $eligibility=Resolve-CustomAppPromotionEligibilityV010 -Name $name -LifecycleRow $lifecycle -ProvenanceRow $provenance -BindingRow $bindingRow -CurrentBaseline $baseline -ProtocolQualification $protocol -Now $now -MaxRemoteObservationAgeHours 36
    Assert-True ([bool]$eligibility.promotion_candidate_eligible) ('fixture current eligibility failed: '+[string]$eligibility.reason)

    $permit=[pscustomobject]@{
        schema=1;managed_by='custom-app-fixture-canary-permit-v1';qualified_eligibility_head='979e9d6362ead31016b9532f98629d6bcc2bbb56';name=$name;source_identity=$source;github_repo_id=[int64]987654321;surface_kind='release-asset'
        token_id=(Get-CustomAppReceiptBoundAdmissionSha256V010 'permit-token');hmac_sha256=(Get-CustomAppReceiptBoundAdmissionSha256V010 'permit-hmac');eligibility_fingerprint=[string]$eligibility.eligibility_fingerprint;current_tree_sha256=$current;remote_tree_sha256=$remote;remote_commit_sha=$commit
        mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;canary_execution_authorized=$false;production_mutation_authorized=$false
    }
    $before=New-CustomAppFixtureCanaryEvidenceV013 -RuntimeTreeSha256 $current -ManifestName $manifest -PersistenceFingerprint $persist -ProvenanceSourceIdentity $source -ProvenanceGitConfigSha256 $git -ProvenanceEvidenceFingerprint $prov
    if($DeniedReceipt){$after=$before}else{$after=New-CustomAppFixtureCanaryEvidenceV013 -RuntimeTreeSha256 $remote -ManifestName $manifest -PersistenceFingerprint $persist -ProvenanceSourceIdentity $source -ProvenanceGitConfigSha256 $git -ProvenanceEvidenceFingerprint (Get-CustomAppReceiptBoundAdmissionSha256V010 'after-provenance-evidence')}
    $executor=[pscustomobject]@{
        schema=1;managed_by='custom-app-fixture-canary-executor-v1';qualified_permit_head='79c7ef064a216ee3ff34328be282d742f0f7abc0';name=$name;status=$(if($DeniedReceipt){'denied-before-consumption'}else{'committed-fixture-canary'});reason=$(if($DeniedReceipt){'fixture-denial'}else{'fixture-commit'});committed=(-not $DeniedReceipt);rolled_back=$false
        token_id=[string]$permit.token_id;eligibility_fingerprint=[string]$permit.eligibility_fingerprint;fixture_canary_execution_authorized=(-not $DeniedReceipt)
        mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;canary_execution_authorized=$false;production_mutation_authorized=$false
    }
    $qualification=New-CustomAppFixtureCanaryExecutorQualificationV013
    $key=[byte[]](1..32)
    $receipt=New-CustomAppFixtureCanaryExecutionReceiptV013 -ExecutorResult $executor -Permit $permit -EligibilityDecision $eligibility -BeforeEvidence $before -AfterEvidence $after -ExecutorQualification $qualification -ReceiptKey $key -Nonce '0123456789abcdef0123456789abcdef' -ObservedAt $now.AddHours(-$ReceiptAgeHours)
    return [pscustomobject]@{Now=$now;Name=$name;Lifecycle=$lifecycle;Provenance=$provenance;Binding=$bindingRow;Baseline=$baseline;Protocol=$protocol;Receipt=$receipt;ReceiptKey=$key;ExecutorQualification=$qualification}
}

function Invoke-FixtureAdmission { param($Context,[string]$Name=$null) if($null -eq $Name){$Name=[string]$Context.Name};return Resolve-CustomAppReceiptBoundProductionAdmissionV010 -Name $Name -LifecycleRow $Context.Lifecycle -ProvenanceRow $Context.Provenance -BindingRow $Context.Binding -CurrentBaseline $Context.Baseline -ProtocolQualification $Context.Protocol -Receipt $Context.Receipt -ReceiptKey $Context.ReceiptKey -ExecutorQualification $Context.ExecutorQualification -Now $Context.Now -MaxRemoteObservationAgeHours 36 -MaxReceiptAgeHours 24 }
function Assert-Denied {param($Decision,[string]$Label) Assert-True (-not [bool]$Decision.production_admission_eligible) ($Label+' unexpectedly eligible');Assert-True (-not [bool]$Decision.production_permit_issued) ($Label+' issued permit');Assert-True (-not [bool]$Decision.production_mutation_authorized) ($Label+' granted production authority')}
function Resign-Receipt {param($Receipt,[byte[]]$Key) $Receipt.receipt_id=$null;$Receipt.hmac_sha256=$null;$m=Get-CustomAppFixtureCanaryReceiptMaterialV013 -Receipt $Receipt;$Receipt.receipt_id=Get-CustomAppFixtureCanaryReceiptSha256V013 -Text $m;$Receipt.hmac_sha256=Get-CustomAppFixtureCanaryReceiptHmacV013 -Text $m -ReceiptKey $Key;return $Receipt}

$passed=0
$c=New-FixtureContext;$d=Invoke-FixtureAdmission $c;Assert-True ([bool]$d.production_admission_eligible) ('positive admission denied: '+[string]$d.reason);Assert-True ([string]$d.status -ceq 'eligible-to-propose-production-permit') 'positive status drift';Assert-True (-not [bool]$d.production_permit_issued -and -not [bool]$d.receipt_is_authority -and -not [bool]$d.production_mutation_authorized) 'positive decision escaped authority';$passed++

$c=New-FixtureContext;$c.Receipt=Copy-Deep $c.Receipt;$c.Receipt.remote_tree_sha256=Get-CustomAppReceiptBoundAdmissionSha256V010 'tampered-tree';$d=Invoke-FixtureAdmission $c;Assert-Denied $d 'cryptographic tamper';Assert-True ([string]$d.reason -like 'receipt-verification-denied:*') 'tamper did not fail at receipt verification';$passed++

$c=New-FixtureContext;$c.Receipt=Copy-Deep $c.Receipt;$c.Receipt.committed=$false;$c.Receipt=Resign-Receipt $c.Receipt $c.ReceiptKey;$d=Invoke-FixtureAdmission $c;Assert-Denied $d 'resigned semantic forgery';Assert-True ([string]$d.reason -like 'receipt-verification-denied:*') 'semantic forgery was not rejected by receipt semantics';$passed++

$c=New-FixtureContext -ReceiptAgeHours 25;$d=Invoke-FixtureAdmission $c;Assert-Denied $d 'stale receipt';Assert-True ([string]$d.reason -ceq 'receipt-stale-for-production-admission') 'stale receipt reason drift';$passed++

$c=New-FixtureContext -ReceiptAgeHours -1;$d=Invoke-FixtureAdmission $c;Assert-Denied $d 'future receipt';Assert-True ([string]$d.reason -ceq 'receipt-observed-in-future') 'future receipt reason drift';$passed++

$c=New-FixtureContext;$c.Lifecycle.user_removed=$true;$d=Invoke-FixtureAdmission $c;Assert-Denied $d 'user removal';Assert-True ([string]$d.reason -like 'current-eligibility-denied:*') 'user removal did not fail current revalidation';$passed++

$c=New-FixtureContext;$c.Provenance.source_changed=$true;$c.Provenance.requires_reenrollment=$true;$d=Invoke-FixtureAdmission $c;Assert-Denied $d 'source change';$passed++

$c=New-FixtureContext;$newCommit='0be36dced09c5b5b7fef14726a69b99148bee432';$c.Binding.last_remote_commit_sha=$newCommit;$c.Binding.binding.last_verified_commit_sha=$newCommit;$d=Invoke-FixtureAdmission $c;Assert-Denied $d 'remote commit drift';Assert-True ([string]$d.reason -like 'receipt-current-*mismatch') 'remote commit drift did not break receipt/current binding';$passed++

$c=New-FixtureContext;$c.Baseline.tree_sha256=Get-CustomAppReceiptBoundAdmissionSha256V010 'local-drift';$d=Invoke-FixtureAdmission $c;Assert-Denied $d 'current runtime drift';Assert-True ([string]$d.reason -like 'current-eligibility-denied:*') 'runtime drift did not fail current eligibility';$passed++

$c=New-FixtureContext;$c.Provenance.evidence_fingerprint=Get-CustomAppReceiptBoundAdmissionSha256V010 'new-provenance';$d=Invoke-FixtureAdmission $c;Assert-Denied $d 'provenance fingerprint drift';Assert-True ([string]$d.reason -like 'receipt-current-*mismatch' -or [string]$d.reason -ceq 'receipt-current-provenance-fingerprint-mismatch') 'provenance drift did not bind current evidence';$passed++

$c=New-FixtureContext;$c.Provenance.auto_update_authorized=$true;$d=Invoke-FixtureAdmission $c;Assert-Denied $d 'authority corruption';Assert-True ([string]$d.reason -like 'current-eligibility-denied:*') 'authority corruption did not fail closed';$passed++

$c=New-FixtureContext -DeniedReceipt;$d=Invoke-FixtureAdmission $c;Assert-Denied $d 'non-commit receipt';Assert-True ([string]$d.reason -ceq 'receipt-is-not-qualified-committed-preserved-canary-evidence') 'non-commit receipt reason drift';$passed++

$c=New-FixtureContext;$c.ExecutorQualification=Copy-Deep $c.ExecutorQualification;$c.ExecutorQualification.push_artifact_id=[int64]1;$d=Invoke-FixtureAdmission $c;Assert-Denied $d 'executor qualification mismatch';Assert-True ([string]$d.reason -like 'receipt-verification-denied:*') 'qualification mismatch did not invalidate receipt';$passed++

$c=New-FixtureContext;$d=Invoke-FixtureAdmission $c '';Assert-Denied $d 'empty name';Assert-True ([string]$d.reason -ceq 'name-empty') 'empty name reason drift';$passed++

$c=New-FixtureContext;$d1=Invoke-FixtureAdmission $c;$d2=Invoke-FixtureAdmission $c;Assert-True ([bool]$d1.production_admission_eligible -and [bool]$d2.production_admission_eligible) 'determinism fixture not eligible';Assert-True ([string]$d1.admission_fingerprint -ceq [string]$d2.admission_fingerprint) 'admission fingerprint is nondeterministic';$passed++

Write-Host ("CUSTOM_APP_RECEIPT_BOUND_PRODUCTION_ADMISSION_MATRIX_PASS total={0}" -f $passed)
