$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-recovery-aware-permit-stage-acquisition-admission-v0.1.0/test_custom_app_production_recovery_aware_permit_stage_acquisition_admission.ps1')
. (Join-Path $root 'validation/custom-app-production-stage-executor-v0.1.0/custom-app-production-stage-executor.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-recovery-aware-permit-stage-executor.ps1')

function Assert-RASETrue([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Assert-RASEFalse([bool]$Value,[string]$Message){if($Value){throw $Message}}
function Assert-RASEEq($Actual,$Expected,[string]$Message){if([string]$Actual -cne [string]$Expected){throw "$Message actual=<$Actual> expected=<$Expected>"}}
function Copy-RASE($Object){return (($Object|ConvertTo-Json -Depth 100)|ConvertFrom-Json)}

# The recovery-aware fixture family deliberately carries attested local-baseline data
# without requiring a real Spotify CustomApps directory. Keep the generic live-baseline
# validator intact, but give its underlying observer a fixture-scoped offline source.
$script:RASEOriginalLocalBaseline=(Get-Command Get-CustomAppLocalRuntimeBaseline -CommandType Function).ScriptBlock
$script:RASELiveBaselineOverride=$null
function Get-CustomAppLocalRuntimeBaseline {
    param([Parameter(Mandatory=$true)][string]$Name,[Parameter(Mandatory=$true)][string]$AppPath,[int]$MaxFiles=20000,[int64]$MaxFileBytes=67108864,[int64]$MaxTotalBytes=268435456,[int64]$MaxManifestBytes=1048576)
    if($null -eq $script:RASELiveBaselineOverride){return & $script:RASEOriginalLocalBaseline -Name $Name -AppPath $AppPath -MaxFiles $MaxFiles -MaxFileBytes $MaxFileBytes -MaxTotalBytes $MaxTotalBytes -MaxManifestBytes $MaxManifestBytes}
    $x=$script:RASELiveBaselineOverride
    return [pscustomobject]@{schema=1;name=$Name;path=$AppPath;safe=$true;installable=$true;reason='fixture-attested-local-runtime';file_count=2;total_bytes=2;tree_sha256=[string]$x.tree_sha256;files=@();manifest_valid=$true;manifest_name=[string]$x.manifest_name;layout_root='.';app_root_count=1;vcs_metadata_excluded=$true;mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false}
}

$script:RASEStageMode='valid'
$script:RASEStageInvocationCount=0
$script:RASEStageAllowedRoot=$null
$script:RASEStageConsumptionStore=$null
$script:RASELiveTreeAfterStage=$null
function Invoke-CustomAppStageAcquisitionV010 {
    param([Parameter(Mandatory=$true)][string]$Name,[Parameter(Mandatory=$true)]$BindingRow)
    $script:RASEStageInvocationCount++
    if($script:RASEStageMode -ceq 'throw'){throw 'fixture-recovery-aware-stage-acquisition-throw'}
    $check=Test-CustomAppStageBindingRowV010 -BindingRow $BindingRow -ExpectedName $Name
    if(-not [bool]$check.ok){throw ('fixture-recovery-aware-stage-binding-denied:'+[string]$check.reason)}
    $workspace=New-CustomAppStageWorkspaceV010
    $stage=Join-Path $workspace 'stage';[IO.Directory]::CreateDirectory($stage)|Out-Null
    $baseline=[pscustomobject]@{schema=1;name=$Name;path=$stage;safe=$true;installable=$true;reason='fixture-staged-runtime';file_count=2;total_bytes=2;tree_sha256=([string]$check.remote_tree_sha256).Trim().ToLowerInvariant();files=@();manifest_valid=$true;manifest_name=[string]$check.manifest_name;layout_root='.';app_root_count=1;vcs_metadata_excluded=$true;mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false}
    $result=[pscustomobject]@{schema=$CustomAppStageAcquisitionSchema;managed_by=$CustomAppStageWorkspaceManagedBy;status='staged-verified';name=$Name;source_identity=[string]$check.source;github_repo_id=[int64]$check.repo_id;surface_kind=[string]$check.surface;commit_sha=[string]$check.commit_sha;remote_tree_sha256=[string]$check.remote_tree_sha256;binding_fingerprint=[string]$check.binding_fingerprint;binding_last_success=[string]$check.last_success;workspace_path=$workspace;stage_path=$stage;archive_sha256=(Get-CustomAppProductionStageExecutorSha256V010 ('recovery-aware-fixture-archive|'+[string]$check.source+'|'+[string]$check.commit_sha));stage_baseline=$baseline;mutation_mode='deny';mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false;production_mutation_authorized=$false}
    switch($script:RASEStageMode){
        'authority' {$result.mutation_authorized=$true}
        'result-tree-drift' {$result.remote_tree_sha256=('9'*64)}
        'stage-missing' {[IO.Directory]::Delete($stage,$true)}
        'mutate-live' {$script:RASELiveTreeAfterStage=('8'*64)}
        'mutate-binding' {$BindingRow.source_identity='other/repo'}
        'tamper-store' {if([string]::IsNullOrWhiteSpace($script:RASEStageConsumptionStore)){throw 'fixture-consumption-store-null'};[IO.File]::WriteAllText((Join-Path $script:RASEStageConsumptionStore 'current.json'),'{not-json',[Text.UTF8Encoding]::new($false))}
    }
    return $result
}

function Invoke-RASEFixtureV010 {
    param(
        [Parameter(Mandatory=$true)]$F,[string]$Mode='valid',[AllowNull()]$PersistenceResult=$null,[AllowNull()]$Bundle=$null,[AllowNull()]$Permit=$null,[AllowNull()][byte[]]$Key=$null,
        [AllowNull()]$Baseline=$null,[AllowNull()]$ShadowQualification=$null,[AllowNull()]$LiveQualification=$null,[AllowNull()][string]$ConsumptionStore=$null,
        [DateTimeOffset]$At=[DateTimeOffset]::MinValue,[Nullable[DateTimeOffset]]$PostAt=$null
    )
    $Q=$F.p.f.p.r.ready
    if($null -eq $PersistenceResult){$PersistenceResult=$F.persisted};if($null -eq $Bundle){$Bundle=$Q.bundle};if($null -eq $Permit){$Permit=$F.p.f.p.r.issuer.permit};if($null -eq $Key){$Key=$script:RAIssuerKey};if([string]::IsNullOrWhiteSpace($ConsumptionStore)){$ConsumptionStore=[string]$F.p.store};if($At -eq [DateTimeOffset]::MinValue){$At=$Q.at.AddSeconds(12)};if($null -eq $PostAt){$PostAt=$At.AddSeconds(1)}
    $ctx=New-RAIssueLiveContextV010 -Bundle $Bundle
    if($null -eq $Baseline){$Baseline=$ctx.baseline};if($null -eq $ShadowQualification){$ShadowQualification=$ctx.shadow};if($null -eq $LiveQualification){$LiveQualification=$ctx.live}
    $script:RASEStageMode=$Mode;$script:RASEStageInvocationCount=0;$script:RASEStageAllowedRoot=[string]$Q.f.ce.q.f.f.allowed;$script:RASEStageConsumptionStore=$ConsumptionStore;$script:RASELiveTreeAfterStage=$null
    $script:RASELiveBaselineOverride=[pscustomobject]@{tree_sha256=[string]$Bundle.binding.last_local_tree_sha256;manifest_name=[string]$Bundle.binding.last_local_manifest_name}
    try{
        if($Mode -ceq 'mutate-live'){
            # The stage mock flips RASELiveTreeAfterStage. The observer reads it after acquisition.
            $original=(Get-Command Invoke-CustomAppStageAcquisitionV010 -CommandType Function).ScriptBlock
        }
        $result=Invoke-CustomAppProductionRecoveryAwarePermitStageExecutorV010 -Name ([string]$Bundle.lifecycle.name) -LifecycleRow $Bundle.lifecycle -ProvenanceRow $Bundle.provenance -BindingRow $Bundle.binding -StageResult $Bundle.stage -ShadowResult $Bundle.shadow -RetirementResumeResult $Q.resume.result -CurrentBaseline $Baseline -ShadowProtocolQualification $ShadowQualification -LiveAttestedQualification $LiveQualification -AllowedRoot $Q.f.ce.q.f.f.allowed -RecoveryStoreDirectory $Q.f.ce.q.f.f.store -ConsumptionStoreDirectory $ConsumptionStore -ExpectedTransactionId ([string]$Q.f.ce.q.f.f.identity.transaction_id) -LocalAppDataRoot $Q.f.ce.q.f.f.q.persistence.local -AppDataRoot $Q.f.ce.q.f.f.q.persistence.roaming -ConsumptionPersistenceResult $PersistenceResult -Permit $Permit -SessionKey $Key -Now $At -PostStageNow $PostAt
        return $result
    } finally {
        $script:RASELiveBaselineOverride=$null;$script:RASEStageConsumptionStore=$null;$script:RASEStageAllowedRoot=$null;$script:RASEStageMode='valid';$script:RASELiveTreeAfterStage=$null
    }
}

# Teach the fixture observer to expose a stage-time live drift only after acquisition.
$script:RASEObserverBase=(Get-Command Get-CustomAppLocalRuntimeBaseline -CommandType Function).ScriptBlock
function Get-CustomAppLocalRuntimeBaseline {
    param([Parameter(Mandatory=$true)][string]$Name,[Parameter(Mandatory=$true)][string]$AppPath,[int]$MaxFiles=20000,[int64]$MaxFileBytes=67108864,[int64]$MaxTotalBytes=268435456,[int64]$MaxManifestBytes=1048576)
    if($null -eq $script:RASELiveBaselineOverride){return & $script:RASEOriginalLocalBaseline -Name $Name -AppPath $AppPath -MaxFiles $MaxFiles -MaxFileBytes $MaxFileBytes -MaxTotalBytes $MaxTotalBytes -MaxManifestBytes $MaxManifestBytes}
    $tree=$(if(-not [string]::IsNullOrWhiteSpace([string]$script:RASELiveTreeAfterStage)){$script:RASELiveTreeAfterStage}else{[string]$script:RASELiveBaselineOverride.tree_sha256})
    return [pscustomobject]@{schema=1;name=$Name;path=$AppPath;safe=$true;installable=$true;reason='fixture-attested-local-runtime';file_count=2;total_bytes=2;tree_sha256=$tree;files=@();manifest_valid=$true;manifest_name=[string]$script:RASELiveBaselineOverride.manifest_name;layout_root='.';app_root_count=1;vcs_metadata_excluded=$true;mutation_authorized=$false;auto_update_authorized=$false;auto_install_authorized=$false}
}

function Assert-RASENoAuthorityV010($Result,[string]$Label){
    $x=if($Result.PSObject.Properties['result'] -and $null -ne $Result.result){$Result.result}else{$Result}
    foreach($f in @('session_key_persisted','session_key_exposed','result_is_authority','apply_authorized','live_destination_authorized','production_execution_authorized','production_mutation_authorized')){Assert-RASEFalse ([bool]$x.$f) "$Label escaped $f"}
    Assert-RASETrue ([bool]$x.requires_fresh_revalidation_before_apply) "$Label missing pre-apply revalidation"
}
function Assert-RASEDeniedV010($Result,[string]$Label,[int]$ExpectedStageCalls=-1){Assert-RASEFalse ([bool]$Result.ok) "$Label unexpectedly succeeded";Assert-RASENoAuthorityV010 $Result $Label;if($ExpectedStageCalls -ge 0){Assert-RASETrue ($script:RASEStageInvocationCount -eq $ExpectedStageCalls) "$Label stage invocation count $($script:RASEStageInvocationCount) != $ExpectedStageCalls"}}

$count=0
$valid=New-RAESFixtureV010 -Label 'rase-valid' -Nonce ('1'*32)
$at=$valid.p.f.p.r.ready.at.AddSeconds(12)
$r=Invoke-RASEFixtureV010 -F $valid -At $at -PostAt $at.AddSeconds(1)
Assert-RASETrue ([bool]$r.ok) ('valid recovery-aware stage executor denied: '+[string]$r.reason)
Assert-RASEEq $r.reason 'recovery-aware-isolated-stage-complete-post-stage-revalidated-zero-authority' 'valid reason'
Assert-RASETrue ([bool]$r.stage_performed -and [bool]$r.isolated_stage_only -and [bool]$r.live_runtime_unchanged -and [bool]$r.post_stage_recovery_revalidated) 'valid stage/revalidation flags missing'
Assert-RASETrue ([bool]$r.stage_workspace_retained_for_pre_apply -and [bool]$r.requires_cleanup_if_not_promoted) 'valid retained-stage contract missing'
Assert-RASETrue ($script:RASEStageInvocationCount -eq 1) 'valid stage acquisition not exactly once'
Assert-RASENoAuthorityV010 $r 'valid'
$rc=Test-CustomAppProductionRecoveryAwarePermitStageExecutorResultV010 -Result $r.result
Assert-RASETrue ([bool]$rc.ok) ('valid stage result denied: '+[string]$rc.reason)
Assert-RASEFalse ([bool]$r.result.PSObject.Properties['session_key']) 'raw session key leaked into stage result'
$count++

$authTamper=Copy-RASE $r.result;$authTamper.apply_authorized=$true;$authTamper.result_fingerprint=Get-CustomAppProductionRecoveryAwarePermitStageExecutorSha256V010 (Get-CustomAppProductionRecoveryAwarePermitStageExecutorResultMaterialV010 -Result $authTamper)
$authCheck=Test-CustomAppProductionRecoveryAwarePermitStageExecutorResultV010 -Result $authTamper
Assert-RASEFalse ([bool]$authCheck.ok) 'rehashed apply-authorized stage result accepted';Assert-RASETrue ([string]$authCheck.reason -like '*authority-escaped-apply_authorized*') ('apply authority tamper reason '+[string]$authCheck.reason);$count++
$fpTamper=Copy-RASE $r.result;$fpTamper.result_fingerprint=('0'*64);$fpCheck=Test-CustomAppProductionRecoveryAwarePermitStageExecutorResultV010 -Result $fpTamper
Assert-RASEFalse ([bool]$fpCheck.ok) 'stage result fingerprint tamper accepted';Assert-RASEEq $fpCheck.reason 'recovery-aware-stage-executor-result-fingerprint-mismatch' 'fingerprint tamper reason';$count++
$clean=Invoke-CustomAppProductionRecoveryAwarePermitStageExecutorCleanupV010 -WorkspacePath ([string]$r.workspace_path);Assert-RASETrue ([bool]$clean.ok) 'valid retained workspace cleanup failed';Assert-RASEFalse (Test-Path -LiteralPath ([string]$r.workspace_path)) 'valid retained workspace remained after cleanup';$count++

$future=New-RAESFixtureV010 -Label 'rase-future' -Name 'future-app' -Source 'owner/future-app' -Manifest 'Future App' -Nonce ('2'*32)
$futureR=Invoke-RASEFixtureV010 -F $future
Assert-RASETrue ([bool]$futureR.ok) ('future app recovery-aware stage executor denied: '+[string]$futureR.reason);Assert-RASEEq $futureR.result.name 'future-app' 'future app result name';Assert-RASENoAuthorityV010 $futureR 'future app';[void](Invoke-CustomAppProductionRecoveryAwarePermitStageExecutorCleanupV010 -WorkspacePath $futureR.workspace_path);$count++

# Historical consumption rev1 remains stageable after unrelated app consumption rev2 is appended.
$histA=New-RAESFixtureV010 -Label 'rase-historical-a' -Nonce ('3'*32)
$histB=New-RAPCFixtureV010 -Label 'rase-historical-b' -Name 'future-app' -Source 'owner/future-app' -Manifest 'Future App' -Nonce ('4'*32)
$bCandidate=Invoke-RAPCFixtureV010 -F $histB -ConsumptionState $histA.persisted.persisted_snapshot.state -ExpectedConsumptionRevision 1 -At $histA.p.f.p.r.ready.at.AddSeconds(13)
Assert-RASETrue ([bool]$bCandidate.ok) ('historical B candidate failed: '+[string]$bCandidate.reason)
$bCarrier=[pscustomobject]@{f=$histB;candidate=$bCandidate;store=$histA.p.store};$bPersist=Invoke-RAPCPFixtureV010 -F $bCarrier -At $histA.p.f.p.r.ready.at.AddSeconds(14)
Assert-RASETrue ([bool]$bPersist.ok) ('historical B persistence failed: '+[string]$bPersist.reason);Assert-RASEEq $bPersist.receipt.persisted_revision 2 'historical B revision'
$histR=Invoke-RASEFixtureV010 -F $histA -At $histA.p.f.p.r.ready.at.AddSeconds(15) -PostAt $histA.p.f.p.r.ready.at.AddSeconds(16)
Assert-RASETrue ([bool]$histR.ok) ('historical rev1 stage executor denied after rev2 append: '+[string]$histR.reason);Assert-RASEEq $histR.result.historical_consumption_envelope_sha256 $histA.persisted.receipt.persistence_envelope_sha256 'historical envelope continuity';Assert-RASENoAuthorityV010 $histR 'historical rev1';[void](Invoke-CustomAppProductionRecoveryAwarePermitStageExecutorCleanupV010 -WorkspacePath $histR.workspace_path);$count++

$wrong=Invoke-RASEFixtureV010 -F $valid -Key ([byte[]](33..64));Assert-RASEDeniedV010 $wrong 'wrong key' 0;Assert-RASETrue ([string]$wrong.reason -like '*pre-stage-admission-denied:*permit-hmac-mismatch*') ('wrong key reason '+[string]$wrong.reason);$count++
$expired=Invoke-RASEFixtureV010 -F $valid -At $valid.p.f.p.r.ready.at.AddMinutes(2) -PostAt $valid.p.f.p.r.ready.at.AddMinutes(2).AddSeconds(1);Assert-RASEDeniedV010 $expired 'expired permit' 0;Assert-RASETrue ([string]$expired.reason -like '*pre-stage-admission-denied:*permit-expired*') ('expired reason '+[string]$expired.reason);$count++

$removed=New-RAESFixtureV010 -Label 'rase-removed' -Nonce ('5'*32);$removedBundle=Copy-RASE $removed.p.f.p.r.ready.bundle;$removedBundle.lifecycle.user_removed=$true;$removedBundle.lifecycle.present=$false
$removedR=Invoke-RASEFixtureV010 -F $removed -Bundle $removedBundle;Assert-RASEDeniedV010 $removedR 'user removal before stage' 0;Assert-RASETrue ([string]$removedR.reason -like '*pre-stage-admission-denied:*') ('user removal reason '+[string]$removedR.reason);$count++

$baselineFx=New-RAESFixtureV010 -Label 'rase-baseline-drift' -Nonce ('6'*32);$baseCtx=New-RAIssueLiveContextV010 -Bundle $baselineFx.p.f.p.r.ready.bundle;$badBaseline=Copy-RASE $baseCtx.baseline;$badBaseline.tree_sha256=('7'*64)
$baselineR=Invoke-RASEFixtureV010 -F $baselineFx -Baseline $badBaseline;Assert-RASEDeniedV010 $baselineR 'baseline drift before stage' 0;Assert-RASETrue ([string]$baselineR.reason -like '*pre-stage-admission-denied:*') ('baseline drift reason '+[string]$baselineR.reason);$count++

$throwFx=New-RAESFixtureV010 -Label 'rase-throw' -Nonce ('7'*32);$throwR=Invoke-RASEFixtureV010 -F $throwFx -Mode 'throw';Assert-RASEDeniedV010 $throwR 'stage acquisition throw' 1;Assert-RASETrue ([string]$throwR.reason -like '*stage-acquisition-failed:*fixture-recovery-aware-stage-acquisition-throw*') ('stage throw reason '+[string]$throwR.reason);$count++
$treeFx=New-RAESFixtureV010 -Label 'rase-tree-drift' -Nonce ('8'*32);$treeR=Invoke-RASEFixtureV010 -F $treeFx -Mode 'result-tree-drift';Assert-RASEDeniedV010 $treeR 'stage result tree drift' 1;Assert-RASETrue ([bool]$treeR.cleanup_attempted -and [bool]$treeR.cleanup_ok) 'tree drift cleanup failed';Assert-RASEFalse (Test-Path -LiteralPath ([string]$treeR.workspace_path)) 'tree drift workspace remained';$count++
$authorityFx=New-RAESFixtureV010 -Label 'rase-authority' -Nonce ('9'*32);$authorityR=Invoke-RASEFixtureV010 -F $authorityFx -Mode 'authority';Assert-RASEDeniedV010 $authorityR 'stage result authority' 1;Assert-RASETrue ([bool]$authorityR.cleanup_ok) 'authority stage cleanup failed';$count++
$missingFx=New-RAESFixtureV010 -Label 'rase-stage-missing' -Nonce ('a'*32);$missingR=Invoke-RASEFixtureV010 -F $missingFx -Mode 'stage-missing';Assert-RASEDeniedV010 $missingR 'stage directory missing' 1;Assert-RASETrue ([bool]$missingR.cleanup_ok) 'missing-stage cleanup failed';$count++
$liveFx=New-RAESFixtureV010 -Label 'rase-live-drift' -Nonce ('b'*32);$liveR=Invoke-RASEFixtureV010 -F $liveFx -Mode 'mutate-live';Assert-RASEDeniedV010 $liveR 'live drift during stage' 1;Assert-RASETrue ([string]$liveR.reason -like '*post-stage-live-revalidation-denied:*fresh-live-tree-changed-during-staging*') ('live drift reason '+[string]$liveR.reason);Assert-RASETrue ([bool]$liveR.cleanup_ok) 'live drift cleanup failed';$count++

$bindingFx=New-RAESFixtureV010 -Label 'rase-binding-drift' -Nonce ('c'*32);$bindingBundle=Copy-RASE $bindingFx.p.f.p.r.ready.bundle;$bindingR=Invoke-RASEFixtureV010 -F $bindingFx -Bundle $bindingBundle -Mode 'mutate-binding';Assert-RASEDeniedV010 $bindingR 'binding drift during stage' 1;Assert-RASETrue ([string]$bindingR.reason -like '*post-stage-admission-denied:*' -or [string]$bindingR.reason -like '*post-stage-live-revalidation-denied:*') ('binding drift reason '+[string]$bindingR.reason);Assert-RASETrue ([bool]$bindingR.cleanup_ok) 'binding drift cleanup failed';$count++

$storeFx=New-RAESFixtureV010 -Label 'rase-store-tamper' -Nonce ('d'*32);$storeR=Invoke-RASEFixtureV010 -F $storeFx -Mode 'tamper-store';Assert-RASEDeniedV010 $storeR 'consumption store tamper during stage' 1;Assert-RASETrue ([string]$storeR.reason -like '*post-stage-admission-denied:*' -or [string]$storeR.reason -like '*post-stage-admission-invalid:*') ('store tamper reason '+[string]$storeR.reason);Assert-RASETrue ([bool]$storeR.cleanup_ok) 'store tamper cleanup failed';$count++

$expiryFx=New-RAESFixtureV010 -Label 'rase-post-expiry' -Nonce ('e'*32);$expiryAt=$expiryFx.p.f.p.r.ready.at.AddSeconds(12);$expiryR=Invoke-RASEFixtureV010 -F $expiryFx -At $expiryAt -PostAt $expiryFx.p.f.p.r.ready.at.AddMinutes(2);Assert-RASEDeniedV010 $expiryR 'permit expired after stage' 1;Assert-RASETrue ([string]$expiryR.reason -like '*post-stage-admission-denied:*permit-expired*') ('post-stage expiry reason '+[string]$expiryR.reason);Assert-RASETrue ([bool]$expiryR.cleanup_ok) 'post-stage expiry cleanup failed';$count++
$timeFx=New-RAESFixtureV010 -Label 'rase-time-backwards' -Nonce ('f'*32);$timeAt=$timeFx.p.f.p.r.ready.at.AddSeconds(12);$timeR=Invoke-RASEFixtureV010 -F $timeFx -At $timeAt -PostAt $timeAt.AddSeconds(-1);Assert-RASEDeniedV010 $timeR 'post-stage time backwards' 1;Assert-RASEEq $timeR.reason 'recovery-aware-post-stage-time-before-pre-stage-time' 'post-stage backwards reason';Assert-RASETrue ([bool]$timeR.cleanup_ok) 'backwards-time cleanup failed';$count++

Write-Host ('CUSTOM_APP_PRODUCTION_RECOVERY_AWARE_PERMIT_STAGE_EXECUTOR_MATRIX_PASS total='+$count)
