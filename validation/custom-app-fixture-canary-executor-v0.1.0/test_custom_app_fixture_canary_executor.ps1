$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$Version='fixture-canary-executor-validation-v0.1.0'
$here=Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot=Split-Path -Parent (Split-Path -Parent $here)
$depRoot=Join-Path $env:TEMP ('custom-app-fixture-canary-executor-deps-'+[guid]::NewGuid().ToString('N'))
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
. (Join-Path $here 'custom-app-fixture-canary-executor-v011.ps1')

function Assert-True {param([bool]$Condition,[string]$Message)if(-not $Condition){throw $Message}}
function Assert-False {param([bool]$Condition,[string]$Message)if($Condition){throw $Message}}
function Assert-ProductionAuthorityDenied {
    param([Parameter(Mandatory=$true)]$Object,[string]$Label)
    foreach($n in @('mutation_authorized','auto_update_authorized','auto_install_authorized','canary_execution_authorized','production_mutation_authorized')){if($Object.PSObject.Properties[$n] -and [bool]$Object.$n){throw "$Label unexpectedly granted $n"}}
    if($Object.PSObject.Properties['mutation_mode'] -and [string]$Object.mutation_mode -cne 'deny'){throw "$Label mutation mode drifted"}
}

function Test-PathSafe {
    param([AllowNull()][string]$Path,[ValidateSet('Leaf','Container')][string]$Kind)
    if([string]::IsNullOrWhiteSpace($Path)){return $false}
    try{return [bool](Test-Path -LiteralPath $Path -PathType $Kind -ErrorAction Stop)}catch{return $false}
}
function Copy-TreeSafe {
    param([Parameter(Mandatory=$true)][string]$Source,[Parameter(Mandatory=$true)][string]$Destination)
    if(-not(Test-PathSafe $Source 'Container')){throw 'Copy-TreeSafe source is missing.'}
    $src=[IO.Path]::GetFullPath($Source).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    $rootItem=Get-Item -LiteralPath $src -Force -ErrorAction Stop
    if(($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'Copy-TreeSafe source root is a reparse point.'}
    if(Test-Path -LiteralPath $Destination){throw 'Copy-TreeSafe destination already exists.'}
    [IO.Directory]::CreateDirectory([IO.Path]::GetFullPath($Destination))|Out-Null
    foreach($entry in @(Get-ChildItem -LiteralPath $src -Recurse -Force -ErrorAction Stop)){
        if(($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw "Copy-TreeSafe source contains reparse point: $($entry.FullName)"}
        $rel=$entry.FullName.Substring($src.Length).TrimStart([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
        $target=Join-Path $Destination $rel
        if($entry.PSIsContainer){[IO.Directory]::CreateDirectory($target)|Out-Null}else{$parent=Split-Path -Parent $target;if(-not(Test-Path $parent)){[IO.Directory]::CreateDirectory($parent)|Out-Null};[IO.File]::Copy($entry.FullName,$target,$false)}
    }
    return [IO.Path]::GetFullPath($Destination)
}

function New-TagifyBindingRowV011 {
    param([Parameter(Mandatory=$true)]$Observation,[Parameter(Mandatory=$true)][string]$LocalTree,[Parameter(Mandatory=$true)][string]$LocalManifest)
    $inner=[pscustomobject]@{
        schema=1;managed_by='custom-app-remote-source-v1';source_identity='alexk218/tagify';github_repo_id=[int64]$Observation.github_repo_id
        surface_kind='release-asset';layout_root='.';manifest_name=[string]$Observation.manifest_name;last_verified_local_tree_sha256=$LocalTree
        last_verified_remote_tree_sha256=[string]$Observation.tree_sha256;last_verified_commit_sha=[string]$Observation.commit_sha;release_asset_selector='unique-zip-asset'
        asset_name=[string]$Observation.asset_name;last_observed_asset_id=[int64]$Observation.asset_id;last_observed_asset_digest_sha256=[string]$Observation.asset_digest_sha256
        mutation_mode='deny';auto_update_authorized=$false;auto_install_authorized=$false
    }
    return [pscustomobject]@{
        schema=1;managed_by='custom-app-remote-binding-observer-v1';name='tagify';active=$true;source_identity='alexk218/tagify';binding=$inner
        last_success='2026-10-28T12:00:00+00:00';last_status='remote-change-observed';last_reason='verified-remote-runtime-change';last_error=$null
        last_local_tree_sha256=$LocalTree;last_local_manifest_name=$LocalManifest;last_remote_tree_sha256=[string]$Observation.tree_sha256;last_remote_commit_sha=[string]$Observation.commit_sha
        update_observed=$true;requires_reenrollment=$false;user_removed=$false;mutation_mode='deny';auto_update_authorized=$false;auto_install_authorized=$false
    }
}

function New-ProtocolQualificationV011 {
    return [pscustomobject]@{
        schema=1;managed_by='custom-app-shadow-protocol-qualification-v1';validated_shadow_head=$CustomAppPromotionQualifiedShadowHead;validated_stage_parent=$CustomAppPromotionQualifiedStageHead
        production_main=$CustomAppPromotionQualifiedProductionMain;addon_manager_sha256=$CustomAppPromotionQualifiedAddonSha256;spotify_control_sha256=$CustomAppPromotionQualifiedSpotifySha256
        push_success=$true;pull_request_success=$true;offline_matrix_passed=$true;live_tagify_331_to_332_passed=$true;parent_selftest_passed=$true
        push_run_id=$CustomAppPromotionQualifiedPushRunId;pull_request_run_id=$CustomAppPromotionQualifiedPrRunId;push_artifact_id=$CustomAppPromotionQualifiedPushArtifactId;pull_request_artifact_id=$CustomAppPromotionQualifiedPrArtifactId
        push_artifact_digest=$CustomAppPromotionQualifiedPushArtifactDigest;pull_request_artifact_digest=$CustomAppPromotionQualifiedPrArtifactDigest
        mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;canary_execution_authorized=$false;production_mutation_authorized=$false
    }
}

function New-ScenarioV011 {
    param([Parameter(Mandatory=$true)][string]$Id,[Parameter(Mandatory=$true)][string]$Template,[Parameter(Mandatory=$true)]$NewObservation)
    $root=Get-CustomAppFixtureCanaryRootV010;$scenario=Join-Path $root ('scenario-'+$Id);[IO.Directory]::CreateDirectory($scenario)|Out-Null
    $live=Join-Path $scenario 'live';[void](Copy-TreeSafe -Source $Template -Destination $live)
    $current=Get-CustomAppLocalRuntimeBaseline -Name 'tagify' -AppPath $live
    Assert-True ([bool]$current.safe -and [bool]$current.installable) "$Id current baseline unsafe"
    $lifecycle=[pscustomobject]@{managed_by='dynamic-spicetify-v1';kind='custom-app';name='tagify';present=$true;user_removed=$false;ambiguous=$false;safe_local_identity=$true;locations=@($live);mutation_mode='deny';auto_update_authorized=$false;auto_install_authorized=$false}
    $lifeRoot=[pscustomobject]@{};$lifeRoot|Add-Member -NotePropertyName 'custom-app:tagify' -NotePropertyValue $lifecycle;$state=[pscustomobject]@{lifecycle=$lifeRoot}
    $evidence=Get-CustomAppLocalProvenanceEvidence -Name 'tagify' -AppPath $live
    $provenance=Update-CustomAppProvenanceEnrollment -State $state -Evidence $evidence -ObservedAt '2026-10-28T12:01:00+00:00'
    Assert-True ([string]$provenance.source_identity -ceq 'alexk218/tagify') "$Id provenance enrollment failed"
    $binding=New-TagifyBindingRowV011 -Observation $NewObservation -LocalTree ([string]$current.tree_sha256) -LocalManifest ([string]$current.manifest_name)
    $localRoot=Join-Path $scenario 'persistence\Local';$appRoot=Join-Path $scenario 'persistence\Roaming';$backupRoot=Join-Path $scenario 'persistence\Backups'
    $ldb=Join-Path $localRoot 'Spotify\Browser\Local Storage\leveldb\000001.ldb';[IO.Directory]::CreateDirectory((Split-Path -Parent $ldb))|Out-Null;[IO.File]::WriteAllText($ldb,('fixture-'+$Id),[Text.UTF8Encoding]::new($false))
    $config=Join-Path $appRoot 'spicetify\config-xpui.ini';[IO.Directory]::CreateDirectory((Split-Path -Parent $config))|Out-Null;[IO.File]::WriteAllText($config,"[AdditionalOptions]`ncustom_apps = tagify`n",[Text.UTF8Encoding]::new($false))
    $before=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $localRoot -AppDataRoot $appRoot
    return [pscustomobject]@{id=$Id;scenario=$scenario;live=$live;current=$current;lifecycle=$lifecycle;provenance=$provenance;binding=$binding;local_root=$localRoot;app_root=$appRoot;backup_root=$backupRoot;persistence_before=$before;git_config_sha=[string]$evidence.git.file_sha256}
}

function New-PermitForScenarioV011 {
    param([Parameter(Mandatory=$true)]$Scenario,[Parameter(Mandatory=$true)]$Protocol,[Parameter(Mandatory=$true)][byte[]]$Key,[Parameter(Mandatory=$true)][string]$Nonce,[Parameter(Mandatory=$true)][DateTimeOffset]$IssuedAt,[int]$TtlMinutes=5)
    $baseline=Get-CustomAppLocalRuntimeBaseline -Name 'tagify' -AppPath ([string]$Scenario.live);$baseline|Add-Member -NotePropertyName path -NotePropertyValue ([string]$Scenario.live) -Force
    $decision=Resolve-CustomAppPromotionEligibilityV010 -Name 'tagify' -LifecycleRow $Scenario.lifecycle -ProvenanceRow $Scenario.provenance -BindingRow $Scenario.binding -CurrentBaseline $baseline -ProtocolQualification $Protocol -Now $IssuedAt
    Assert-True ([bool]$decision.promotion_candidate_eligible) ($Scenario.id+' promotion eligibility denied: '+[string]$decision.reason)
    $permit=New-CustomAppFixtureCanaryPermitV010 -EligibilityDecision $decision -FixtureRoot (Get-CustomAppFixtureCanaryRootV010) -SessionKey $Key -Nonce $Nonce -IssuedAt $IssuedAt -TtlMinutes $TtlMinutes
    return [pscustomobject]@{decision=$decision;permit=$permit}
}

$old=$null;$new=$null;$oldStage=$null;$root=Get-CustomAppFixtureCanaryRootV010
try {
    if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction Stop}
    [IO.Directory]::CreateDirectory($root)|Out-Null;[IO.Directory]::CreateDirectory((Get-CustomAppFixtureCanaryConsumptionDirectoryV011))|Out-Null
    $old=Get-CustomAppObserverReleaseObservation -Source 'alexk218/tagify' -ReleaseId 416245914
    $new=Get-CustomAppObserverReleaseObservation -Source 'alexk218/tagify' -ReleaseId 418974188
    if([int64]$old.github_repo_id -ne 1021838879 -or [string]$old.commit_sha -cne '0be36dced09c5b5b7fef14726a69b99148bee432' -or [int64]$old.asset_id -ne 652536027 -or [string]$old.asset_digest_sha256 -cne 'b7510e525297c297d6007305acef947c35bf2df34e0fae492c41a31f555db957'){throw 'Pinned Tagify v3.3.1 identity drift.'}
    if([int64]$new.github_repo_id -ne 1021838879 -or [string]$new.commit_sha -cne 'bacd80f76c621a3acc06965bb3160ce1056fad7b' -or [int64]$new.asset_id -ne 660754674 -or [string]$new.asset_digest_sha256 -cne '5261538c8f596cf179b1f6efd20e0a0a60c73b4cd765115fc6bc25c6a6b3b76b'){throw 'Pinned Tagify v3.3.2 identity drift.'}

    $oldBinding=New-TagifyBindingRowV011 -Observation $old -LocalTree ([string]$old.tree_sha256) -LocalManifest ([string]$old.manifest_name)
    $oldStage=Invoke-CustomAppStageAcquisitionV010 -Name 'tagify' -BindingRow $oldBinding
    Assert-True ([string]$oldStage.status -ceq 'staged-verified') 'Could not stage pinned Tagify v3.3.1 template.'
    $template=Join-Path $root 'tagify-v331-template';[void](Copy-TreeSafe -Source ([string]$oldStage.stage_path) -Destination $template)
    Remove-CustomAppStageWorkspaceV010 -Path ([string]$oldStage.workspace_path);$oldStage=$null
    $gitDir=Join-Path $template '.git';[IO.Directory]::CreateDirectory($gitDir)|Out-Null
    $gitConfig=((@('[core]','    repositoryformatversion = 0','[remote "origin"]','    url = https://github.com/alexk218/tagify.git') -join "`n")+"`n");[IO.File]::WriteAllText((Join-Path $gitDir 'config'),$gitConfig,[Text.UTF8Encoding]::new($false))
    $templateBase=Get-CustomAppLocalRuntimeBaseline -Name 'tagify' -AppPath $template
    Assert-True ([string]$templateBase.tree_sha256 -ceq [string]$old.tree_sha256) 'Template runtime tree drifted after local provenance metadata.'

    $protocol=New-ProtocolQualificationV011;$key=[byte[]](0..31);$wrongKey=[byte[]](32..63)
    $issued=[DateTimeOffset]::Parse('2026-10-28T12:05:00+00:00')

    $wrong=New-ScenarioV011 -Id 'wrong-key' -Template $template -NewObservation $new
    $wrongPermit=New-PermitForScenarioV011 -Scenario $wrong -Protocol $protocol -Key $key -Nonce '00000000000000000000000000000001' -IssuedAt $issued
    $wrongGate=Test-CustomAppFixtureCanaryExecutorGateV011 -Name 'tagify' -LifecycleRow $wrong.lifecycle -ProvenanceRow $wrong.provenance -BindingRow $wrong.binding -ProtocolQualification $protocol -Permit $wrongPermit.permit -SessionKey $wrongKey -Now $issued.AddSeconds(20) -Phase 'pre-stage'
    Assert-False ([bool]$wrongGate.ok) 'Wrong-key gate unexpectedly passed.'
    Assert-True ([string]$wrongGate.reason -like '*permit-hmac-mismatch') ('Wrong-key reason drifted: '+[string]$wrongGate.reason)

    $durable=New-ScenarioV011 -Id 'durable-replay' -Template $template -NewObservation $new
    $durablePermit=New-PermitForScenarioV011 -Scenario $durable -Protocol $protocol -Key $key -Nonce '00000000000000000000000000000002' -IssuedAt $issued
    $state0=New-CustomAppFixtureCanaryConsumptionStateV010
    $firstUse=Use-CustomAppFixtureCanaryPermitDurablyV011 -Permit $durablePermit.permit -EligibilityDecision $durablePermit.decision -SessionKey $key -ConsumptionState $state0 -Now $issued.AddSeconds(20)
    Assert-True ([bool]$firstUse.ok) ('First durable permit consumption failed: '+[string]$firstUse.reason)
    $secondUse=Use-CustomAppFixtureCanaryPermitDurablyV011 -Permit $durablePermit.permit -EligibilityDecision $durablePermit.decision -SessionKey $key -ConsumptionState (New-CustomAppFixtureCanaryConsumptionStateV010) -Now $issued.AddSeconds(25)
    Assert-False ([bool]$secondUse.ok) 'Durable permit replay unexpectedly passed with fresh memory state.'
    Assert-True ([string]$secondUse.reason -ceq 'durable-permit-replay-detected') ('Durable replay reason drifted: '+[string]$secondUse.reason)

    $expired=New-ScenarioV011 -Id 'expires-after-stage' -Template $template -NewObservation $new
    $expiredPermit=New-PermitForScenarioV011 -Scenario $expired -Protocol $protocol -Key $key -Nonce '00000000000000000000000000000003' -IssuedAt $issued -TtlMinutes 1
    $expiredResult=Invoke-CustomAppFixtureCanaryExecutorV011 -Name 'tagify' -LifecycleRow $expired.lifecycle -ProvenanceRow $expired.provenance -BindingRow $expired.binding -ProtocolQualification $protocol -Permit $expiredPermit.permit -SessionKey $key -ConsumptionState (New-CustomAppFixtureCanaryConsumptionStateV010) -LocalAppDataRoot $expired.local_root -AppDataRoot $expired.app_root -PersistenceBackupRoot $expired.backup_root -PreStageNow $issued.AddSeconds(15) -PreApplyNow $issued.AddMinutes(2)
    Assert-True ([string]$expiredResult.status -ceq 'denied-after-staging') ('Expiry scenario status drifted: '+[string]$expiredResult.status+' / '+[string]$expiredResult.reason)
    Assert-True ([string]$expiredResult.reason -like '*permit-expired') ('Expiry scenario reason drifted: '+[string]$expiredResult.reason)
    Assert-ProductionAuthorityDenied -Object $expiredResult -Label 'expiry-result'
    $expiredAfter=Get-CustomAppLocalRuntimeBaseline -Name 'tagify' -AppPath $expired.live;Assert-True ([string]$expiredAfter.tree_sha256 -ceq [string]$old.tree_sha256) 'Expiry scenario mutated live runtime.'
    $expiredPersistence=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $expired.local_root -AppDataRoot $expired.app_root;Assert-True ([string]$expiredPersistence.fingerprint -ceq [string]$expired.persistence_before.fingerprint) 'Expiry scenario changed persistence.'

    $marker=New-ScenarioV011 -Id 'marker-barrier' -Template $template -NewObservation $new
    $markerPermit=New-PermitForScenarioV011 -Scenario $marker -Protocol $protocol -Key $key -Nonce '00000000000000000000000000000004' -IssuedAt $issued
    $markerResult=Invoke-CustomAppFixtureCanaryExecutorV011 -Name 'tagify' -LifecycleRow $marker.lifecycle -ProvenanceRow $marker.provenance -BindingRow $marker.binding -ProtocolQualification $protocol -Permit $markerPermit.permit -SessionKey $key -ConsumptionState (New-CustomAppFixtureCanaryConsumptionStateV010) -LocalAppDataRoot $marker.local_root -AppDataRoot $marker.app_root -PersistenceBackupRoot $marker.backup_root -PreStageNow $issued.AddSeconds(15) -PreApplyNow $issued.AddSeconds(35) -InjectRemoveConsumptionMarkerBeforeApply
    Assert-False ([bool]$markerResult.committed) 'Marker-barrier scenario unexpectedly committed.'
    Assert-True ([string]$markerResult.reason -like '*consumption-marker*') ('Marker barrier reason drifted: '+[string]$markerResult.reason)
    Assert-ProductionAuthorityDenied -Object $markerResult -Label 'marker-result'
    $markerAfter=Get-CustomAppLocalRuntimeBaseline -Name 'tagify' -AppPath $marker.live;Assert-True ([string]$markerAfter.tree_sha256 -ceq [string]$old.tree_sha256) 'Marker-barrier scenario mutated live runtime.'
    $markerPersistence=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $marker.local_root -AppDataRoot $marker.app_root;Assert-True ([string]$markerPersistence.fingerprint -ceq [string]$marker.persistence_before.fingerprint) 'Marker-barrier scenario changed persistence.'

    $valid=New-ScenarioV011 -Id 'valid' -Template $template -NewObservation $new
    $validPermit=New-PermitForScenarioV011 -Scenario $valid -Protocol $protocol -Key $key -Nonce '00000000000000000000000000000005' -IssuedAt $issued
    $validResult=Invoke-CustomAppFixtureCanaryExecutorV011 -Name 'tagify' -LifecycleRow $valid.lifecycle -ProvenanceRow $valid.provenance -BindingRow $valid.binding -ProtocolQualification $protocol -Permit $validPermit.permit -SessionKey $key -ConsumptionState (New-CustomAppFixtureCanaryConsumptionStateV010) -LocalAppDataRoot $valid.local_root -AppDataRoot $valid.app_root -PersistenceBackupRoot $valid.backup_root -PreStageNow $issued.AddSeconds(15) -PreApplyNow $issued.AddSeconds(35)
    Assert-True ([string]$validResult.status -ceq 'committed-fixture-canary' -and [bool]$validResult.committed) ('Valid canary did not commit: '+[string]$validResult.status+' / '+[string]$validResult.reason)
    Assert-True ([bool]$validResult.fixture_canary_execution_authorized) 'Valid canary result did not expose fixture-only execution evidence.'
    Assert-ProductionAuthorityDenied -Object $validResult -Label 'valid-result'
    $validAfter=Get-CustomAppLocalRuntimeBaseline -Name 'tagify' -AppPath $valid.live
    Assert-True ([string]$validAfter.tree_sha256 -ceq [string]$new.tree_sha256 -and [string]$validAfter.manifest_name -ceq [string]$new.manifest_name) 'Valid canary did not install exact Tagify v3.3.2 runtime.'
    $validPersistence=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $valid.local_root -AppDataRoot $valid.app_root;Assert-True ([string]$validPersistence.fingerprint -ceq [string]$valid.persistence_before.fingerprint) 'Valid canary changed Spotify/Spicetify persistence.'
    $postProv=Get-CustomAppLocalProvenanceEvidence -Name 'tagify' -AppPath $valid.live;Assert-True ([bool]$postProv.source_proven -and ([string]$postProv.source_candidate).Trim().ToLowerInvariant() -ceq 'alexk218/tagify') 'Valid canary lost strong provenance.'
    Assert-True ([string]$postProv.git.file_sha256 -ceq [string]$valid.git_config_sha) 'Valid canary changed .git/config provenance bytes.'
    Assert-True (Test-Path -LiteralPath ([string]$validResult.marker_path) -PathType Leaf) 'Valid canary durable permit marker is missing.'
    Assert-True (@($validResult.next_consumption_state.consumed_token_ids).Count -eq 1) 'Valid canary did not return consumed-token state.'
    $markerCheck=Test-CustomAppFixtureCanaryConsumptionMarkerV011 -MarkerPath ([string]$validResult.marker_path) -TokenId ([string]$validResult.token_id) -EligibilityFingerprint ([string]$validResult.eligibility_fingerprint);Assert-True ([bool]$markerCheck.ok) ('Valid canary marker verification failed: '+[string]$markerCheck.reason)

    Write-Host "CUSTOM_APP_FIXTURE_CANARY_EXECUTOR_LIVE_PASS old=$($old.tree_sha256) new=$($new.tree_sha256) valid_token=$($validResult.token_id) durable_replay=$($secondUse.reason) expiry=$($expiredResult.status) marker_barrier=$($markerResult.status) persistence=$($validPersistence.fingerprint)"
}finally{
    if($null -ne $oldStage -and $oldStage.PSObject.Properties['workspace_path']){try{Remove-CustomAppStageWorkspaceV010 -Path ([string]$oldStage.workspace_path)}catch{}}
    if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue}
    if(Test-Path -LiteralPath $depRoot){Remove-Item -LiteralPath $depRoot -Recurse -Force -ErrorAction SilentlyContinue}
}
