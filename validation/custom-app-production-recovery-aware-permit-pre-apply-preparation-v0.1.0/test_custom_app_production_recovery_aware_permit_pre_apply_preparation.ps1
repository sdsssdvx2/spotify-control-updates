$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-recovery-aware-permit-stage-executor-v0.1.0/test_custom_app_production_recovery_aware_permit_stage_executor.ps1')
. (Join-Path $root 'validation/custom-app-production-pre-apply-preparation-v0.1.0/custom-app-production-pre-apply-preparation.ps1')
. (Join-Path $PSScriptRoot 'custom-app-production-recovery-aware-permit-pre-apply-preparation.ps1')

function Assert-RAPPTrue([bool]$Value,[string]$Message){if(-not $Value){throw $Message}}
function Assert-RAPPFalse([bool]$Value,[string]$Message){if($Value){throw $Message}}
function Assert-RAPPEq($Actual,$Expected,[string]$Message){if([string]$Actual -cne [string]$Expected){throw "$Message actual=<$Actual> expected=<$Expected>"}}
function Copy-RAPP($Object){return (($Object|ConvertTo-Json -Depth 100)|ConvertFrom-Json)}

function New-RAPPFixtureV010 {
    param([Parameter(Mandatory=$true)][string]$Label,[Parameter(Mandatory=$true)][string]$Nonce)
    $f=New-RAESFixtureV010 -Label $Label -Nonce $Nonce
    $q=$f.p.f.p.r.ready
    $at=$q.at.AddSeconds(12)
    $stage=Invoke-RASEFixtureV010 -F $f -At $at -PostAt $at.AddSeconds(1)
    if(-not [bool]$stage.ok){throw ('fixture recovery-aware stage failed: '+[string]$stage.reason)}
    $bundle=$q.bundle
    $binding=Test-CustomAppStageBindingRowV010 -BindingRow $bundle.binding -ExpectedName ([string]$bundle.lifecycle.name)
    if(-not [bool]$binding.ok){throw ('fixture binding denied: '+[string]$binding.reason)}
    Write-ProductionStageRuntimeV010 ([string]$stage.result.stage_path) ([string]$binding.manifest_name) (([string]$bundle.lifecycle.name)+'-remote-v2')
    $stageBaseline=& $script:RASEOriginalLocalBaseline -Name ([string]$bundle.lifecycle.name) -AppPath ([string]$stage.result.stage_path)
    if(([string]$stageBaseline.tree_sha256).Trim().ToLowerInvariant() -cne ([string]$stage.result.remote_tree_sha256).Trim().ToLowerInvariant()){throw "fixture byte-real stage tree mismatch $($stageBaseline.tree_sha256) != $($stage.result.remote_tree_sha256)"}
    $livePath=[string]@($bundle.lifecycle.locations)[0]
    $liveBaseline=& $script:RASEOriginalLocalBaseline -Name ([string]$bundle.lifecycle.name) -AppPath $livePath
    if(([string]$liveBaseline.tree_sha256).Trim().ToLowerInvariant() -cne ([string]$stage.result.local_tree_sha256).Trim().ToLowerInvariant()){throw "fixture byte-real live tree mismatch $($liveBaseline.tree_sha256) != $($stage.result.local_tree_sha256)"}
    $base=Join-Path $env:TEMP ('rapp-'+$Label+'-'+[Guid]::NewGuid().ToString('N'))
    return [pscustomobject]@{f=$f;q=$q;bundle=$bundle;stage=$stage.result;at=([DateTimeOffset]::Parse([string]$stage.result.post_stage_revalidated_at).AddSeconds(1));rollback=(Join-Path $base 'rollback');persistence=(Join-Path $base 'persistence');base=$base;live_path=$livePath}
}

function Invoke-RAPPFixtureV010 {
    param(
        [Parameter(Mandatory=$true)]$X,[AllowNull()]$Stage=$null,[AllowNull()]$Lifecycle=$null,[AllowNull()]$Binding=$null,[AllowNull()]$Permit=$null,[AllowNull()][byte[]]$Key=$null,
        [AllowNull()][string]$ExpectedTransactionId=$null,[AllowNull()][string]$RollbackRoot=$null,[AllowNull()][string]$PersistenceRoot=$null,[Nullable[DateTimeOffset]]$At=$null,[Nullable[DateTimeOffset]]$PostAt=$null
    )
    if($null -eq $Stage){$Stage=$X.stage};if($null -eq $Lifecycle){$Lifecycle=$X.bundle.lifecycle};if($null -eq $Binding){$Binding=$X.bundle.binding};if($null -eq $Permit){$Permit=$X.f.p.f.p.r.issuer.permit};if($null -eq $Key){$Key=$script:RAIssuerKey}
    if([string]::IsNullOrWhiteSpace($ExpectedTransactionId)){$ExpectedTransactionId=[string]$X.q.f.ce.q.f.f.identity.transaction_id};if([string]::IsNullOrWhiteSpace($RollbackRoot)){$RollbackRoot=[string]$X.rollback};if([string]::IsNullOrWhiteSpace($PersistenceRoot)){$PersistenceRoot=[string]$X.persistence}
    $when=$(if($null -ne $At){[DateTimeOffset]$At}else{[DateTimeOffset]$X.at});$post=$(if($null -ne $PostAt){[DateTimeOffset]$PostAt}else{$when.AddSeconds(1)})
    $ctx=New-RAIssueLiveContextV010 -Bundle $X.bundle
    return Invoke-CustomAppProductionRecoveryAwarePermitPreApplyPreparationV010 -RecoveryAwareStageExecutorResult $Stage -Name ([string]$X.bundle.lifecycle.name) -LifecycleRow $Lifecycle -ProvenanceRow $X.bundle.provenance -BindingRow $Binding -LifecycleStageResult $X.bundle.stage -ShadowResult $X.bundle.shadow -RetirementResumeResult $X.q.resume.result -ShadowProtocolQualification $ctx.shadow -LiveAttestedQualification $ctx.live -AllowedRoot $X.q.f.ce.q.f.f.allowed -RecoveryStoreDirectory $X.q.f.ce.q.f.f.store -ConsumptionStoreDirectory $X.f.p.store -ExpectedTransactionId $ExpectedTransactionId -LocalAppDataRoot $X.q.f.ce.q.f.f.q.persistence.local -AppDataRoot $X.q.f.ce.q.f.f.q.persistence.roaming -ConsumptionPersistenceResult $X.f.persisted -Permit $Permit -SessionKey $Key -RollbackBackupRoot $RollbackRoot -PersistenceBackupRoot $PersistenceRoot -Now $when -PostBackupNow $post
}

function Assert-RAPPNoAuthorityV010($Result,[string]$Label){
    $x=if($Result.PSObject.Properties['result'] -and $null -ne $Result.result){$Result.result}else{$Result}
    foreach($f in @('session_key_persisted','session_key_exposed','preparation_is_authority','backups_are_authority','apply_authorized','live_destination_authorized','production_execution_authorized','production_mutation_authorized')){Assert-RAPPFalse ([bool]$x.$f) "$Label escaped $f"}
    Assert-RAPPTrue ([bool]$x.requires_atomic_apply_rollback_executor) "$Label missing atomic apply requirement"
    Assert-RAPPTrue ([bool]$x.requires_fresh_revalidation_before_apply) "$Label missing fresh apply revalidation"
}
function Assert-RAPPDeniedV010($Result,[string]$Label){Assert-RAPPFalse ([bool]$Result.ok) "$Label unexpectedly succeeded";Assert-RAPPNoAuthorityV010 $Result $Label}
function Remove-RAPPFixtureV010($X){
    try{Invoke-CustomAppProductionRecoveryAwarePermitStageExecutorCleanupV010 -WorkspacePath ([string]$X.stage.workspace_path)|Out-Null}catch{}
    try{if(Test-Path -LiteralPath $X.base){Remove-Item -LiteralPath $X.base -Recurse -Force -ErrorAction SilentlyContinue}}catch{}
}

$count=0
$valid=New-RAPPFixtureV010 -Label 'valid' -Nonce ('1'*32)
try{
    $r=Invoke-RAPPFixtureV010 -X $valid
    Assert-RAPPTrue ([bool]$r.ok) ('valid recovery-aware pre-apply denied: '+[string]$r.reason)
    Assert-RAPPEq $r.reason 'recovery-aware-pre-apply-backups-prepared-verified-zero-apply-authority' 'valid reason'
    Assert-RAPPTrue ([bool]$r.backups_prepared -and [bool]$r.recovery_revalidated_before_backups -and [bool]$r.recovery_revalidated_after_backups) 'valid backup/revalidation flags missing'
    Assert-RAPPNoAuthorityV010 $r 'valid'
    $check=Test-CustomAppProductionRecoveryAwarePermitPreApplyPreparedResultV010 -Result $r.result
    Assert-RAPPTrue ([bool]$check.ok) ('valid prepared result denied: '+[string]$check.reason)
    Assert-RAPPTrue (Test-Path -LiteralPath ([string]$r.result.app_backup_path) -PathType Container) 'valid app rollback backup missing'
    Assert-RAPPTrue (Test-Path -LiteralPath ([string]$r.result.persistence_backup_path) -PathType Container) 'valid persistence backup missing'
    Assert-RAPPFalse ([bool]$r.result.PSObject.Properties['session_key']) 'raw session key leaked into result'
    $count++

    $auth=Copy-RAPP $r.result;$auth.apply_authorized=$true;$auth.result_fingerprint=Get-CustomAppProductionRecoveryAwarePermitPreApplySha256V010 (Get-CustomAppProductionRecoveryAwarePermitPreApplyResultMaterialV010 -Result $auth)
    $authCheck=Test-CustomAppProductionRecoveryAwarePermitPreApplyPreparedResultV010 -Result $auth
    Assert-RAPPFalse ([bool]$authCheck.ok) 'rehashed apply-authorized prepared result accepted';Assert-RAPPTrue ([string]$authCheck.reason -like '*authority-escaped-apply_authorized*') ('authority tamper reason '+[string]$authCheck.reason);$count++

    $finger=Copy-RAPP $r.result;$finger.result_fingerprint=('0'*64)
    $fingerCheck=Test-CustomAppProductionRecoveryAwarePermitPreApplyPreparedResultV010 -Result $finger
    Assert-RAPPFalse ([bool]$fingerCheck.ok) 'prepared result fingerprint tamper accepted';$count++
} finally {Remove-RAPPFixtureV010 $valid}

$stageTamper=New-RAPPFixtureV010 -Label 'stage-result-tamper' -Nonce ('2'*32)
try{
    $s=Copy-RAPP $stageTamper.stage;$s.result_fingerprint=('0'*64)
    $r=Invoke-RAPPFixtureV010 -X $stageTamper -Stage $s
    Assert-RAPPDeniedV010 $r 'stage result fingerprint tamper';Assert-RAPPTrue ([string]$r.reason -like 'recovery-aware-pre-apply-stage-result-invalid:*') ('stage tamper reason '+[string]$r.reason);$count++

    $s=Copy-RAPP $stageTamper.stage;$s.apply_authorized=$true;$s.result_fingerprint=Get-CustomAppProductionRecoveryAwarePermitStageExecutorSha256V010 (Get-CustomAppProductionRecoveryAwarePermitStageExecutorResultMaterialV010 -Result $s)
    $r=Invoke-RAPPFixtureV010 -X $stageTamper -Stage $s
    Assert-RAPPDeniedV010 $r 'rehashed stage apply authority';Assert-RAPPTrue ([string]$r.reason -like '*authority-escaped-apply_authorized*') ('stage authority reason '+[string]$r.reason);$count++

    $r=Invoke-RAPPFixtureV010 -X $stageTamper -ExpectedTransactionId ('f'*64)
    Assert-RAPPDeniedV010 $r 'transaction mismatch';Assert-RAPPEq $r.reason 'recovery-aware-pre-apply-transaction-mismatch' 'transaction mismatch reason';$count++

    $badKey=New-Object byte[] 32;[Array]::Copy($script:RAIssuerKey,$badKey,32);$badKey[0]=$badKey[0] -bxor 0x5a
    $r=Invoke-RAPPFixtureV010 -X $stageTamper -Key $badKey
    Assert-RAPPDeniedV010 $r 'wrong key';Assert-RAPPTrue ([string]$r.reason -like 'recovery-aware-pre-apply-pre-backup-admission-denied:*') ('wrong key reason '+[string]$r.reason);$count++
} finally {Remove-RAPPFixtureV010 $stageTamper}

$userRemoved=New-RAPPFixtureV010 -Label 'user-removed' -Nonce ('3'*32)
try{
    $life=Copy-RAPP $userRemoved.bundle.lifecycle;$life.present=$false;$life.user_removed=$true
    $r=Invoke-RAPPFixtureV010 -X $userRemoved -Lifecycle $life
    Assert-RAPPDeniedV010 $r 'user removal';Assert-RAPPTrue ([string]$r.reason -like 'recovery-aware-pre-apply-live-revalidation-denied:*') ('user removal reason '+[string]$r.reason);$count++
} finally {Remove-RAPPFixtureV010 $userRemoved}

$liveDrift=New-RAPPFixtureV010 -Label 'live-drift' -Nonce ('4'*32)
try{
    [IO.File]::WriteAllText((Join-Path $liveDrift.live_path 'rapp-live-drift.txt'),'drift',[Text.UTF8Encoding]::new($false))
    $r=Invoke-RAPPFixtureV010 -X $liveDrift
    Assert-RAPPDeniedV010 $r 'live tree drift';Assert-RAPPTrue ([string]$r.reason -like 'recovery-aware-pre-apply-live-revalidation-denied:*') ('live drift reason '+[string]$r.reason);$count++
} finally {Remove-RAPPFixtureV010 $liveDrift}

$stageDrift=New-RAPPFixtureV010 -Label 'stage-drift' -Nonce ('5'*32)
try{
    [IO.File]::WriteAllText((Join-Path ([string]$stageDrift.stage.stage_path) 'rapp-stage-drift.txt'),'drift',[Text.UTF8Encoding]::new($false))
    $r=Invoke-RAPPFixtureV010 -X $stageDrift
    Assert-RAPPDeniedV010 $r 'stage tree drift';Assert-RAPPTrue ([string]$r.reason -like 'recovery-aware-pre-apply-generic-preparation-denied:*') ('stage drift reason '+[string]$r.reason);$count++
} finally {Remove-RAPPFixtureV010 $stageDrift}

$bindingDrift=New-RAPPFixtureV010 -Label 'binding-drift' -Nonce ('6'*32)
try{
    $binding=Copy-RAPP $bindingDrift.bundle.binding;$binding.source_identity='other/repository'
    $r=Invoke-RAPPFixtureV010 -X $bindingDrift -Binding $binding
    Assert-RAPPDeniedV010 $r 'binding drift';Assert-RAPPTrue ([string]$r.reason -like 'recovery-aware-pre-apply-binding-denied:*' -or [string]$r.reason -like 'recovery-aware-pre-apply-stage-binding-mismatch-*') ('binding drift reason '+[string]$r.reason);$count++
} finally {Remove-RAPPFixtureV010 $bindingDrift}

$rootOverlap=New-RAPPFixtureV010 -Label 'root-overlap' -Nonce ('7'*32)
try{
    $same=Join-Path $rootOverlap.base 'same-root'
    $r=Invoke-RAPPFixtureV010 -X $rootOverlap -RollbackRoot $same -PersistenceRoot $same
    Assert-RAPPDeniedV010 $r 'backup roots overlap';Assert-RAPPTrue ([string]$r.reason -like 'recovery-aware-pre-apply-generic-preparation-denied:*') ('backup overlap reason '+[string]$r.reason);$count++
} finally {Remove-RAPPFixtureV010 $rootOverlap}

Write-Host ("CUSTOM_APP_PRODUCTION_RECOVERY_AWARE_PERMIT_PRE_APPLY_PREPARATION_MATRIX_PASS total={0}" -f $count)
