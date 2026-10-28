$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$here=Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot=Split-Path -Parent (Split-Path -Parent $here)
$depRoot=Join-Path $env:TEMP ('custom-app-live-attested-deps-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $depRoot|Out-Null

function Get-PinnedDependencyFile {
    param([Parameter(Mandatory=$true)][string]$Commit,[Parameter(Mandatory=$true)][string]$RepoPath,[Parameter(Mandatory=$true)][string]$Name)
    $lines=@(& git -C $repoRoot show "$Commit`:$RepoPath")
    if($LASTEXITCODE -ne 0){throw "Could not materialize pinned dependency: $Commit`:$RepoPath"}
    $out=Join-Path $depRoot $Name
    [IO.File]::WriteAllText($out,(($lines -join "`n")+"`n"),[Text.UTF8Encoding]::new($false))
    return $out
}

. (Get-PinnedDependencyFile '57be1dcd10e339e9da2b8f15b9910a2ae1b79c1b' 'validation/marketplace-lifecycle-settings-core-v0.1.0/lifecycle-settings-core.ps1' 'lifecycle-settings-core.ps1')
. (Get-PinnedDependencyFile 'b339f2b79a267c13cf3c5974aea2fff3786d3093' 'validation/custom-app-provenance-enrollment-v0.1.0/custom-app-provenance.ps1' 'custom-app-provenance.ps1')
. (Get-PinnedDependencyFile '7d22b55c58c6e85a8a3ec9396800e65d81b0e7d2' 'validation/custom-app-remote-observation-collector-v0.1.0/custom-app-remote-observer.ps1' 'custom-app-remote-observer.ps1')
. (Get-PinnedDependencyFile '7d22b55c58c6e85a8a3ec9396800e65d81b0e7d2' 'validation/custom-app-remote-observation-collector-v0.1.1/release-id-fix-v011.ps1' 'release-id-fix-v011.ps1')
. (Get-PinnedDependencyFile '19109205bd2e61e862c3b9acd61946568397ecb5' 'validation/custom-app-remote-source-contract-v0.1.0/custom-app-remote-source-contract.ps1' 'custom-app-remote-source-contract.ps1')
. (Get-PinnedDependencyFile '19109205bd2e61e862c3b9acd61946568397ecb5' 'validation/custom-app-remote-source-contract-v0.1.1/release-continuity-v011.ps1' 'release-continuity-v011.ps1')
. (Get-PinnedDependencyFile '7402ea5c77e58cd072f0166411d40e7726093f3c' 'validation/custom-app-local-runtime-baseline-v0.1.0/custom-app-local-runtime-baseline.ps1' 'custom-app-local-runtime-baseline.ps1')
. (Get-PinnedDependencyFile 'c420a1df6f306c7ba74772b91241cb14abd04738' 'validation/custom-app-stage-acquisition-contract-v0.1.0/custom-app-stage-acquisition.ps1' 'custom-app-stage-acquisition.ps1')
. (Get-PinnedDependencyFile '1a2461a6929e9cabd50d27f95e0744f83443b9e8' 'validation/custom-app-update-transaction-protocol-v0.1.0/custom-app-update-transaction.ps1' 'custom-app-update-transaction.ps1')
. (Get-PinnedDependencyFile '979e9d6362ead31016b9532f98629d6bcc2bbb56' 'validation/custom-app-promotion-eligibility-gate-v0.1.0/custom-app-promotion-eligibility.ps1' 'custom-app-promotion-eligibility.ps1')
. (Get-PinnedDependencyFile '79c7ef064a216ee3ff34328be282d742f0f7abc0' 'validation/custom-app-fixture-canary-permit-v0.1.0/custom-app-fixture-canary-permit.ps1' 'custom-app-fixture-canary-permit.ps1')
. (Get-PinnedDependencyFile '22eb3561843fbe4016023d527186aa629512b67d' 'validation/custom-app-shadow-executor-v0.1.0/custom-app-shadow-executor.ps1' 'custom-app-shadow-executor.ps1')
. (Get-PinnedDependencyFile '22eb3561843fbe4016023d527186aa629512b67d' 'validation/custom-app-shadow-executor-v0.1.0/shadow-executor-safety-overlay.ps1' 'shadow-executor-safety-overlay.ps1')
. (Get-PinnedDependencyFile 'a5d5839a9d6c1dd01c1fced6e9e1f5f76d16b5ca' 'validation/custom-app-fixture-canary-executor-v0.1.0/custom-app-fixture-canary-executor-v011.ps1' 'custom-app-fixture-canary-executor-v011.ps1')
. (Get-PinnedDependencyFile '635e25a4a06320cd103e07b1506f0ba8787e5c3a' 'validation/custom-app-fixture-canary-execution-receipt-v0.1.1/custom-app-fixture-canary-execution-receipt-v013.ps1' 'custom-app-fixture-canary-execution-receipt-v013.ps1')
. (Join-Path $here 'custom-app-live-attested-fixture-canary.ps1')

function Assert-True {param([bool]$Condition,[string]$Message)if(-not $Condition){throw $Message}}
function Assert-False {param([bool]$Condition,[string]$Message)if($Condition){throw $Message}}
function Assert-AuthorityClosed {
    param([Parameter(Mandatory=$true)]$Object,[string]$Label)
    if($Object.PSObject.Properties['mutation_mode']){Assert-True ([string]$Object.mutation_mode -ceq 'deny') "$Label mutation mode drifted"}
    foreach($n in @('mutation_authorized','auto_update_authorized','auto_install_authorized','canary_execution_authorized','production_mutation_authorized')){if($Object.PSObject.Properties[$n]){Assert-False ([bool]$Object.$n) "$Label unexpectedly granted $n"}}
    if($Object.PSObject.Properties['receipt_is_authority']){Assert-False ([bool]$Object.receipt_is_authority) "$Label receipt became authority"}
}
function Copy-TreeSafeV010 {
    param([Parameter(Mandatory=$true)][string]$Source,[Parameter(Mandatory=$true)][string]$Destination)
    $src=[IO.Path]::GetFullPath($Source).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    if(-not(Test-Path -LiteralPath $src -PathType Container)){throw 'Copy source missing.'}
    $rootItem=Get-Item -LiteralPath $src -Force -ErrorAction Stop;if(($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Copy source root is reparse point.'}
    if(Test-Path -LiteralPath $Destination){throw 'Copy destination already exists.'}
    [IO.Directory]::CreateDirectory([IO.Path]::GetFullPath($Destination))|Out-Null
    foreach($entry in @(Get-ChildItem -LiteralPath $src -Recurse -Force -ErrorAction Stop)){
        if(($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw ('Copy source contains reparse point: '+$entry.FullName)}
        $rel=$entry.FullName.Substring($src.Length).TrimStart([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar);$target=Join-Path $Destination $rel
        if($entry.PSIsContainer){[IO.Directory]::CreateDirectory($target)|Out-Null}else{$parent=Split-Path -Parent $target;if(-not(Test-Path $parent)){[IO.Directory]::CreateDirectory($parent)|Out-Null};[IO.File]::Copy($entry.FullName,$target,$false)}
    }
    return [IO.Path]::GetFullPath($Destination)
}
function New-TagifyBindingRowAttestedV010 {
    param([Parameter(Mandatory=$true)]$Observation,[Parameter(Mandatory=$true)][string]$LocalTree,[Parameter(Mandatory=$true)][string]$LocalManifest)
    $inner=[pscustomobject]@{schema=1;managed_by='custom-app-remote-source-v1';source_identity='alexk218/tagify';github_repo_id=[int64]$Observation.github_repo_id;surface_kind='release-asset';layout_root='.';manifest_name=[string]$Observation.manifest_name;last_verified_local_tree_sha256=$LocalTree;last_verified_remote_tree_sha256=[string]$Observation.tree_sha256;last_verified_commit_sha=[string]$Observation.commit_sha;release_asset_selector='unique-zip-asset';asset_name=[string]$Observation.asset_name;last_observed_asset_id=[int64]$Observation.asset_id;last_observed_asset_digest_sha256=[string]$Observation.asset_digest_sha256;mutation_mode='deny';auto_update_authorized=$false;auto_install_authorized=$false}
    return [pscustomobject]@{schema=1;managed_by='custom-app-remote-binding-observer-v1';name='tagify';active=$true;source_identity='alexk218/tagify';binding=$inner;last_success='2026-10-28T12:00:00+00:00';last_status='remote-change-observed';last_reason='verified-remote-runtime-change';last_error=$null;last_local_tree_sha256=$LocalTree;last_local_manifest_name=$LocalManifest;last_remote_tree_sha256=[string]$Observation.tree_sha256;last_remote_commit_sha=[string]$Observation.commit_sha;update_observed=$true;requires_reenrollment=$false;user_removed=$false;mutation_mode='deny';auto_update_authorized=$false;auto_install_authorized=$false}
}
function New-ProtocolQualificationAttestedV010 {
    return [pscustomobject]@{schema=1;managed_by='custom-app-shadow-protocol-qualification-v1';validated_shadow_head=$CustomAppPromotionQualifiedShadowHead;validated_stage_parent=$CustomAppPromotionQualifiedStageHead;production_main=$CustomAppPromotionQualifiedProductionMain;addon_manager_sha256=$CustomAppPromotionQualifiedAddonSha256;spotify_control_sha256=$CustomAppPromotionQualifiedSpotifySha256;push_success=$true;pull_request_success=$true;offline_matrix_passed=$true;live_tagify_331_to_332_passed=$true;parent_selftest_passed=$true;push_run_id=$CustomAppPromotionQualifiedPushRunId;pull_request_run_id=$CustomAppPromotionQualifiedPrRunId;push_artifact_id=$CustomAppPromotionQualifiedPushArtifactId;pull_request_artifact_id=$CustomAppPromotionQualifiedPrArtifactId;push_artifact_digest=$CustomAppPromotionQualifiedPushArtifactDigest;pull_request_artifact_digest=$CustomAppPromotionQualifiedPrArtifactDigest;mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;canary_execution_authorized=$false;production_mutation_authorized=$false}
}
function New-AttestedScenarioV010 {
    param([Parameter(Mandatory=$true)][string]$Id,[Parameter(Mandatory=$true)][string]$Template,[Parameter(Mandatory=$true)]$NewObservation)
    $root=Get-CustomAppFixtureCanaryRootV010;$scenario=Join-Path $root ('attested-'+$Id);[IO.Directory]::CreateDirectory($scenario)|Out-Null
    $live=Join-Path $scenario 'live';[void](Copy-TreeSafeV010 -Source $Template -Destination $live)
    $current=Get-CustomAppLocalRuntimeBaseline -Name 'tagify' -AppPath $live;Assert-True ([bool]$current.safe -and [bool]$current.installable) "$Id current baseline unsafe"
    $lifecycle=[pscustomobject]@{managed_by='dynamic-spicetify-v1';kind='custom-app';name='tagify';present=$true;user_removed=$false;ambiguous=$false;safe_local_identity=$true;locations=@($live);mutation_mode='deny';auto_update_authorized=$false;auto_install_authorized=$false}
    $lifeRoot=[pscustomobject]@{};$lifeRoot|Add-Member -NotePropertyName 'custom-app:tagify' -NotePropertyValue $lifecycle;$state=[pscustomobject]@{lifecycle=$lifeRoot}
    $provEvidence=Get-CustomAppLocalProvenanceEvidence -Name 'tagify' -AppPath $live;$provenance=Update-CustomAppProvenanceEnrollment -State $state -Evidence $provEvidence -ObservedAt '2026-10-28T12:01:00+00:00'
    Assert-True ([string]$provenance.source_identity -ceq 'alexk218/tagify') "$Id provenance enrollment failed"
    $binding=New-TagifyBindingRowAttestedV010 -Observation $NewObservation -LocalTree ([string]$current.tree_sha256) -LocalManifest ([string]$current.manifest_name)
    $localRoot=Join-Path $scenario 'persistence\Local';$appRoot=Join-Path $scenario 'persistence\Roaming';$backupRoot=Join-Path $scenario 'persistence\Backups'
    $ldb=Join-Path $localRoot 'Spotify\Browser\Local Storage\leveldb\000001.ldb';[IO.Directory]::CreateDirectory((Split-Path -Parent $ldb))|Out-Null;[IO.File]::WriteAllText($ldb,('attested-'+$Id),[Text.UTF8Encoding]::new($false))
    $config=Join-Path $appRoot 'spicetify\config-xpui.ini';[IO.Directory]::CreateDirectory((Split-Path -Parent $config))|Out-Null;[IO.File]::WriteAllText($config,"[AdditionalOptions]`ncustom_apps = tagify`n",[Text.UTF8Encoding]::new($false))
    $persist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $localRoot -AppDataRoot $appRoot
    return [pscustomobject]@{id=$Id;live=$live;current=$current;lifecycle=$lifecycle;provenance=$provenance;binding=$binding;local_root=$localRoot;app_root=$appRoot;backup_root=$backupRoot;persistence_before=$persist;provenance_before=$provEvidence}
}
function New-AttestedPermitV010 {
    param([Parameter(Mandatory=$true)]$Scenario,[Parameter(Mandatory=$true)]$Protocol,[Parameter(Mandatory=$true)][byte[]]$Key,[Parameter(Mandatory=$true)][string]$Nonce,[Parameter(Mandatory=$true)][DateTimeOffset]$IssuedAt)
    $baseline=Get-CustomAppLocalRuntimeBaseline -Name 'tagify' -AppPath ([string]$Scenario.live);$baseline|Add-Member -NotePropertyName path -NotePropertyValue ([string]$Scenario.live) -Force
    $decision=Resolve-CustomAppPromotionEligibilityV010 -Name 'tagify' -LifecycleRow $Scenario.lifecycle -ProvenanceRow $Scenario.provenance -BindingRow $Scenario.binding -CurrentBaseline $baseline -ProtocolQualification $Protocol -Now $IssuedAt
    Assert-True ([bool]$decision.promotion_candidate_eligible) ($Scenario.id+' promotion eligibility denied: '+[string]$decision.reason)
    $permit=New-CustomAppFixtureCanaryPermitV010 -EligibilityDecision $decision -FixtureRoot (Get-CustomAppFixtureCanaryRootV010) -SessionKey $Key -Nonce $Nonce -IssuedAt $IssuedAt -TtlMinutes 5
    return [pscustomobject]@{decision=$decision;permit=$permit}
}
function Get-AttestedEvidenceV010 {
    param([Parameter(Mandatory=$true)]$Scenario)
    $baseline=Get-CustomAppLocalRuntimeBaseline -Name 'tagify' -AppPath ([string]$Scenario.live)
    $persist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $Scenario.local_root -AppDataRoot $Scenario.app_root
    $prov=Get-CustomAppLocalProvenanceEvidence -Name 'tagify' -AppPath ([string]$Scenario.live)
    Assert-True ([bool]$baseline.safe -and [bool]$baseline.installable) ($Scenario.id+' evidence baseline unsafe')
    Assert-True ([bool]$prov.source_proven -and ([string]$prov.source_candidate).Trim().ToLowerInvariant() -ceq 'alexk218/tagify') ($Scenario.id+' evidence provenance not strong/current')
    return [pscustomobject]@{baseline=$baseline;persistence=$persist;provenance=$prov;receipt_evidence=(New-CustomAppFixtureCanaryEvidenceV013 -RuntimeTreeSha256 ([string]$baseline.tree_sha256) -ManifestName ([string]$baseline.manifest_name) -PersistenceFingerprint ([string]$persist.fingerprint) -ProvenanceSourceIdentity ([string]$prov.source_candidate) -ProvenanceGitConfigSha256 ([string]$prov.git.file_sha256) -ProvenanceEvidenceFingerprint ([string]$prov.evidence_fingerprint))}
}
function New-LiveAttestationV010 {
    param([Parameter(Mandatory=$true)]$Scenario,[Parameter(Mandatory=$true)]$PermitBundle,[Parameter(Mandatory=$true)]$ExecutorResult,[Parameter(Mandatory=$true)]$Before,[Parameter(Mandatory=$true)]$After,[Parameter(Mandatory=$true)][string]$Nonce,[Parameter(Mandatory=$true)][byte[]]$ReceiptKey)
    $qualification=New-CustomAppFixtureCanaryExecutorQualificationV013
    $attested=New-CustomAppLiveAttestedFixtureCanaryResultV010 -ExecutorResult $ExecutorResult -Permit $PermitBundle.permit -EligibilityDecision $PermitBundle.decision -BeforeEvidence $Before.receipt_evidence -AfterEvidence $After.receipt_evidence -ExecutorQualification $qualification -ReceiptKey $ReceiptKey -ReceiptNonce $Nonce -ObservedAt ([DateTimeOffset]::Parse('2026-10-28T12:10:00+00:00'))
    $verify=Test-CustomAppLiveAttestedFixtureCanaryResultV010 -Result $attested -ReceiptKey $ReceiptKey -ExecutorQualification $qualification
    Assert-True ([bool]$verify.ok) ($Scenario.id+' live attestation verification failed: '+[string]$verify.reason);Assert-AuthorityClosed -Object $attested -Label ($Scenario.id+'-attested');Assert-AuthorityClosed -Object $attested.receipt -Label ($Scenario.id+'-receipt')
    return $attested
}

$root=Get-CustomAppFixtureCanaryRootV010;$oldStage=$null
try {
    if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction Stop}
    [IO.Directory]::CreateDirectory($root)|Out-Null;[IO.Directory]::CreateDirectory((Get-CustomAppFixtureCanaryConsumptionDirectoryV011))|Out-Null
    $old=Get-CustomAppObserverReleaseObservation -Source 'alexk218/tagify' -ReleaseId 416245914
    $new=Get-CustomAppObserverReleaseObservation -Source 'alexk218/tagify' -ReleaseId 418974188
    Assert-True ([int64]$old.github_repo_id -eq 1021838879 -and [string]$old.commit_sha -ceq '0be36dced09c5b5b7fef14726a69b99148bee432' -and [int64]$old.asset_id -eq 652536027 -and [string]$old.asset_digest_sha256 -ceq 'b7510e525297c297d6007305acef947c35bf2df34e0fae492c41a31f555db957') 'Pinned Tagify v3.3.1 identity drift.'
    Assert-True ([int64]$new.github_repo_id -eq 1021838879 -and [string]$new.commit_sha -ceq 'bacd80f76c621a3acc06965bb3160ce1056fad7b' -and [int64]$new.asset_id -eq 660754674 -and [string]$new.asset_digest_sha256 -ceq '5261538c8f596cf179b1f6efd20e0a0a60c73b4cd765115fc6bc25c6a6b3b76b') 'Pinned Tagify v3.3.2 identity drift.'
    $oldBinding=New-TagifyBindingRowAttestedV010 -Observation $old -LocalTree ([string]$old.tree_sha256) -LocalManifest ([string]$old.manifest_name)
    $oldStage=Invoke-CustomAppStageAcquisitionV010 -Name 'tagify' -BindingRow $oldBinding;Assert-True ([string]$oldStage.status -ceq 'staged-verified') 'Could not stage Tagify v3.3.1 template.'
    $template=Join-Path $root 'attested-tagify-v331-template';[void](Copy-TreeSafeV010 -Source ([string]$oldStage.stage_path) -Destination $template);Remove-CustomAppStageWorkspaceV010 -Path ([string]$oldStage.workspace_path);$oldStage=$null
    $gitDir=Join-Path $template '.git';[IO.Directory]::CreateDirectory($gitDir)|Out-Null;$gitConfig=((@('[core]','    repositoryformatversion = 0','[remote "origin"]','    url = https://github.com/alexk218/tagify.git') -join "`n")+"`n");[IO.File]::WriteAllText((Join-Path $gitDir 'config'),$gitConfig,[Text.UTF8Encoding]::new($false))
    $templateBase=Get-CustomAppLocalRuntimeBaseline -Name 'tagify' -AppPath $template;Assert-True ([string]$templateBase.tree_sha256 -ceq [string]$old.tree_sha256) 'Template runtime tree drifted.'

    $protocol=New-ProtocolQualificationAttestedV010;$sessionKey=[byte[]](0..31);$wrongSessionKey=[byte[]](32..63);$receiptKey=[byte[]](64..95);$issued=[DateTimeOffset]::Parse('2026-10-28T12:05:00+00:00')

    $commitScenario=New-AttestedScenarioV010 -Id 'commit' -Template $template -NewObservation $new;$commitPermit=New-AttestedPermitV010 -Scenario $commitScenario -Protocol $protocol -Key $sessionKey -Nonce '10000000000000000000000000000001' -IssuedAt $issued;$commitBefore=Get-AttestedEvidenceV010 -Scenario $commitScenario
    $commitResult=Invoke-CustomAppFixtureCanaryExecutorV011 -Name 'tagify' -LifecycleRow $commitScenario.lifecycle -ProvenanceRow $commitScenario.provenance -BindingRow $commitScenario.binding -ProtocolQualification $protocol -Permit $commitPermit.permit -SessionKey $sessionKey -ConsumptionState (New-CustomAppFixtureCanaryConsumptionStateV010) -LocalAppDataRoot $commitScenario.local_root -AppDataRoot $commitScenario.app_root -PersistenceBackupRoot $commitScenario.backup_root -PreStageNow $issued.AddSeconds(15) -PreApplyNow $issued.AddSeconds(35)
    $commitAfter=Get-AttestedEvidenceV010 -Scenario $commitScenario;$commitAttested=New-LiveAttestationV010 -Scenario $commitScenario -PermitBundle $commitPermit -ExecutorResult $commitResult -Before $commitBefore -After $commitAfter -Nonce '20000000000000000000000000000001' -ReceiptKey $receiptKey
    Assert-True ([string]$commitAttested.outcome_classification -ceq 'committed-preserved') 'Committed live attestation classification drifted.';Assert-True ([string]$commitAfter.baseline.tree_sha256 -ceq [string]$new.tree_sha256) 'Committed live runtime did not reach exact remote tree.';Assert-True ([string]$commitBefore.persistence.fingerprint -ceq [string]$commitAfter.persistence.fingerprint) 'Committed live persistence changed.';Assert-True ([string]$commitBefore.provenance.git.file_sha256 -ceq [string]$commitAfter.provenance.git.file_sha256) 'Committed live git provenance bytes changed.'

    $denyScenario=New-AttestedScenarioV010 -Id 'deny' -Template $template -NewObservation $new;$denyPermit=New-AttestedPermitV010 -Scenario $denyScenario -Protocol $protocol -Key $sessionKey -Nonce '10000000000000000000000000000002' -IssuedAt $issued;$denyBefore=Get-AttestedEvidenceV010 -Scenario $denyScenario
    $denyResult=Invoke-CustomAppFixtureCanaryExecutorV011 -Name 'tagify' -LifecycleRow $denyScenario.lifecycle -ProvenanceRow $denyScenario.provenance -BindingRow $denyScenario.binding -ProtocolQualification $protocol -Permit $denyPermit.permit -SessionKey $wrongSessionKey -ConsumptionState (New-CustomAppFixtureCanaryConsumptionStateV010) -LocalAppDataRoot $denyScenario.local_root -AppDataRoot $denyScenario.app_root -PersistenceBackupRoot $denyScenario.backup_root -PreStageNow $issued.AddSeconds(15) -PreApplyNow $issued.AddSeconds(35)
    $denyAfter=Get-AttestedEvidenceV010 -Scenario $denyScenario;$denyAttested=New-LiveAttestationV010 -Scenario $denyScenario -PermitBundle $denyPermit -ExecutorResult $denyResult -Before $denyBefore -After $denyAfter -Nonce '20000000000000000000000000000002' -ReceiptKey $receiptKey
    Assert-True ([string]$denyResult.status -ceq 'denied-before-consumption' -and [string]$denyAttested.outcome_classification -ceq 'denied-no-mutation') 'Denied live attestation classification drifted.';Assert-True ([string]$denyBefore.receipt_evidence.evidence_fingerprint -ceq [string]$denyAfter.receipt_evidence.evidence_fingerprint) 'Denied live execution changed evidence.'

    $rollbackScenario=New-AttestedScenarioV010 -Id 'rollback' -Template $template -NewObservation $new;$rollbackPermit=New-AttestedPermitV010 -Scenario $rollbackScenario -Protocol $protocol -Key $sessionKey -Nonce '10000000000000000000000000000003' -IssuedAt $issued;$rollbackBefore=Get-AttestedEvidenceV010 -Scenario $rollbackScenario
    $rollbackResult=Invoke-CustomAppFixtureCanaryExecutorV011 -Name 'tagify' -LifecycleRow $rollbackScenario.lifecycle -ProvenanceRow $rollbackScenario.provenance -BindingRow $rollbackScenario.binding -ProtocolQualification $protocol -Permit $rollbackPermit.permit -SessionKey $sessionKey -ConsumptionState (New-CustomAppFixtureCanaryConsumptionStateV010) -LocalAppDataRoot $rollbackScenario.local_root -AppDataRoot $rollbackScenario.app_root -PersistenceBackupRoot $rollbackScenario.backup_root -PreStageNow $issued.AddSeconds(15) -PreApplyNow $issued.AddSeconds(35) -InjectTransactionPostApplyFailure
    $rollbackAfter=Get-AttestedEvidenceV010 -Scenario $rollbackScenario;$rollbackAttested=New-LiveAttestationV010 -Scenario $rollbackScenario -PermitBundle $rollbackPermit -ExecutorResult $rollbackResult -Before $rollbackBefore -After $rollbackAfter -Nonce '20000000000000000000000000000003' -ReceiptKey $receiptKey
    Assert-True ([bool]$rollbackResult.rolled_back -and -not [bool]$rollbackResult.committed -and [string]$rollbackAttested.outcome_classification -ceq 'rolled-back-restored') 'Rollback live attestation classification drifted.';Assert-True ([string]$rollbackBefore.receipt_evidence.evidence_fingerprint -ceq [string]$rollbackAfter.receipt_evidence.evidence_fingerprint) 'Rollback did not restore complete evidence.'

    $qualification=New-CustomAppFixtureCanaryExecutorQualificationV013;$tampered=$commitAttested|ConvertTo-Json -Depth 40|ConvertFrom-Json;$tampered.receipt.after_persistence_fingerprint=('f'*64);$bad=Test-CustomAppLiveAttestedFixtureCanaryResultV010 -Result $tampered -ReceiptKey $receiptKey -ExecutorQualification $qualification;Assert-False ([bool]$bad.ok) 'Tampered live receipt unexpectedly verified.'
    $wrongReceiptKey=[byte[]](96..127);$bad=Test-CustomAppLiveAttestedFixtureCanaryResultV010 -Result $commitAttested -ReceiptKey $wrongReceiptKey -ExecutorQualification $qualification;Assert-False ([bool]$bad.ok) 'Wrong receipt key unexpectedly verified.'

    Write-Host ('CUSTOM_APP_LIVE_ATTESTED_FIXTURE_CANARY_PASS commit='+$commitAttested.receipt_id+' deny='+$denyAttested.receipt_id+' rollback='+$rollbackAttested.receipt_id+' old='+$old.tree_sha256+' new='+$new.tree_sha256+' persistence='+$commitAfter.persistence.fingerprint)
} finally {
    if($null -ne $oldStage -and $oldStage.PSObject.Properties['workspace_path']){try{Remove-CustomAppStageWorkspaceV010 -Path ([string]$oldStage.workspace_path)}catch{}}
    if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue}
    if(Test-Path -LiteralPath $depRoot){Remove-Item -LiteralPath $depRoot -Recurse -Force -ErrorAction SilentlyContinue}
}
