$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$source=Join-Path $root 'validation/custom-app-production-recovery-aware-permit-spicetify-apply-executor-v0.1.0/test_custom_app_production_recovery_aware_permit_spicetify_apply_executor_integration.ps1'
$text=[IO.File]::ReadAllText($source,[Text.UTF8Encoding]::new($false))

function Get-RACLIUniqueIndexV010 {
    param([string]$Text,[string]$Marker,[string]$Label)
    $i=$Text.IndexOf($Marker,[StringComparison]::Ordinal)
    if($i-lt0){throw "cleanup integration marker missing: $Label"}
    if($Text.IndexOf($Marker,$i+$Marker.Length,[StringComparison]::Ordinal)-ge0){throw "cleanup integration marker not unique: $Label"}
    return $i
}

$importOld="custom-app-production-recovery-aware-permit-spicetify-apply-executor-v0.1.0/custom-app-production-recovery-aware-permit-spicetify-apply-executor.ps1')`""
$importNew="custom-app-production-recovery-aware-permit-spicetify-apply-executor-v0.1.0/custom-app-production-recovery-aware-permit-spicetify-apply-executor.ps1')``n    . (Join-Path ``$root 'validation/custom-app-production-post-apply-commit-cleanup-v0.1.0/custom-app-production-post-apply-commit-cleanup.ps1')``n    . (Join-Path ``$root 'validation/custom-app-production-post-apply-commit-cleanup-v0.1.0/custom-app-production-post-apply-commit-cleanup-finalization-receipt-v011.ps1')``n    . (Join-Path ``$root 'validation/custom-app-production-recovery-aware-permit-post-apply-commit-cleanup-v0.1.0/custom-app-production-recovery-aware-permit-post-apply-commit-cleanup.ps1')`""
$i=Get-RACLIUniqueIndexV010 -Text $text -Marker $importOld -Label 'apply-generated-import-tail'
$patched=$text.Substring(0,$i)+$importNew+$text.Substring($i+$importOld.Length)

$restoreOld="        Restore-RAALIValidV010 `$valid `$prep `$r 'valid';`$integrationCount++"
$restoreNew=@'
        $raxCleanupSentinel=Join-Path ([string]$prep.result.app_backup_root) ('recovery-aware-cleanup-sentinel-'+[Guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($raxCleanupSentinel)|Out-Null
        $raxCleanup=Invoke-CustomAppProductionRecoveryAwarePermitPostApplyCommitCleanupV010 -RecoveryAwareApplyResult $apply.result -RecoveryAwareFinalizationResult $final.result -RecoveryAwareAtomicResult $r.result -RecoveryAwarePreparedResult $prep.result -RecoveryAwareStageExecutorResult $valid.stage -ConsumptionPersistenceResult $valid.f.persisted -Permit $valid.f.p.f.p.r.issuer.permit -Name ([string]$valid.bundle.lifecycle.name) -LifecycleRow $valid.bundle.lifecycle -ProvenanceRow $valid.bundle.provenance -BindingRow $valid.bundle.binding -AllowedRoot $valid.q.f.ce.q.f.f.allowed -ConsumptionStoreDirectory $valid.f.p.store -SessionKey $script:RAIssuerKey -LocalAppDataRoot $valid.q.f.ce.q.f.f.q.persistence.local -AppDataRoot $valid.q.f.ce.q.f.f.q.persistence.roaming -Now $applyNow.AddSeconds(1)
        Assert-RAALITrue ([bool]$raxCleanup.ok) ('real recovery-aware post-apply cleanup denied: '+[string]$raxCleanup.reason)
        Assert-RAALITrue ([bool]$raxCleanup.requires_new_permit_for_future_update) 'real cleanup missing new-permit requirement'
        Assert-RAALIFalse ([bool]$raxCleanup.rollback_attempted) 'real cleanup attempted rollback'
        Assert-RAALIFalse ([bool]$raxCleanup.spicetify_apply_executed) 'real cleanup reported extra apply execution'
        $raxCleanupCheck=Test-CustomAppProductionRecoveryAwarePermitPostApplyCleanupResultV010 -Result $raxCleanup.result;Assert-RAALITrue ([bool]$raxCleanupCheck.ok) ('real cleanup result validator denied: '+[string]$raxCleanupCheck.reason)
        Assert-RAALITrue ([bool]$raxCleanup.result.update_commit_complete -and [bool]$raxCleanup.result.all_transaction_artifacts_clean -and [bool]$raxCleanup.result.requires_new_permit_for_future_update) 'real cleanup completion flags missing'
        Assert-RAALIEq ([string]$raxCleanup.result.historical_consumption_envelope_sha256).Trim().ToLowerInvariant() ([string]$apply.result.historical_consumption_envelope_sha256).Trim().ToLowerInvariant() 'real cleanup historical ledger drifted'
        Assert-RAALITrue ([int64]$raxCleanup.result.current_consumption_revision -ge [int64]$apply.result.current_consumption_revision) 'real cleanup current ledger revision regressed'
        foreach($field in @('result_is_authority','spicetify_apply_authorized','additional_mutation_authorized','live_destination_authorized','production_execution_authorized','production_mutation_authorized','session_key_persisted','session_key_exposed')){Assert-RAALIFalse ([bool]$raxCleanup.result.$field) ('real cleanup authority/key escaped '+$field)}
        foreach($path in @([string]$prep.result.stage_workspace_path,[string]$prep.result.stage_path,[string]$prep.result.app_backup_path,[string]$prep.result.persistence_backup_path)){Assert-RAALIFalse (Test-Path -LiteralPath $path) ('real cleanup left transaction evidence '+$path)}
        $raxCleanupAppContainer=[IO.Path]::GetDirectoryName([string]$prep.result.app_backup_path);Assert-RAALIFalse (Test-Path -LiteralPath $raxCleanupAppContainer) 'real cleanup left app backup container'
        Assert-RAALITrue (Test-Path -LiteralPath $raxCleanupSentinel -PathType Container) 'real cleanup deleted unrelated sibling sentinel'
        $raxCleanupApplyCount=0;if(Test-Path -LiteralPath $raxApplyFakeCount -PathType Leaf){[void][int]::TryParse(([IO.File]::ReadAllText($raxApplyFakeCount)).Trim(),[ref]$raxCleanupApplyCount)}
        Assert-RAALITrue ($raxCleanupApplyCount -eq 1) ('real cleanup launched another apply process count='+$raxCleanupApplyCount)
        $raxCleanupLive=& $script:RASEOriginalLocalBaseline -Name ([string]$valid.bundle.lifecycle.name) -AppPath ([string]$valid.live_path);Assert-RAALIEq ([string]$raxCleanupLive.tree_sha256).Trim().ToLowerInvariant() ([string]$valid.remote_tree).Trim().ToLowerInvariant() 'real cleanup changed live CustomApp runtime'
        $raxCleanupPersistence=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $valid.q.f.ce.q.f.f.q.persistence.local -AppDataRoot $valid.q.f.ce.q.f.f.q.persistence.roaming;Assert-RAALIEq ([string]$raxCleanupPersistence.fingerprint).Trim().ToLowerInvariant() ([string]$apply.result.persistence_fingerprint).Trim().ToLowerInvariant() 'real cleanup changed protected persistence'
        $integrationCount++
'@
$i=Get-RACLIUniqueIndexV010 -Text $patched -Marker $restoreOld -Label 'apply-valid-restore-anchor'
$patched=$patched.Substring(0,$i)+$restoreNew.TrimEnd("`r","`n")+$patched.Substring($i+$restoreOld.Length)

foreach($m in @('custom-app-production-post-apply-commit-cleanup.ps1','custom-app-production-post-apply-commit-cleanup-finalization-receipt-v011.ps1','custom-app-production-recovery-aware-permit-post-apply-commit-cleanup.ps1','Invoke-CustomAppProductionRecoveryAwarePermitPostApplyCommitCleanupV010','real recovery-aware post-apply cleanup denied','real cleanup left transaction evidence','real cleanup launched another apply process','real cleanup deleted unrelated sibling sentinel')){if($patched.IndexOf($m,[StringComparison]::Ordinal)-lt0){throw "cleanup integration coverage marker missing $m"}}
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($patched,[ref]$tokens,[ref]$errors);if($errors.Count){$errors|ForEach-Object{Write-Error ("patched cleanup generator line=$($_.Extent.StartLineNumber) text=<$($_.Extent.Text)> $($_.Message)")};throw 'patched cleanup generator PS5.1 parse failed'}
$iex=@($ast.FindAll({param($n)$n-is[Management.Automation.Language.CommandAst]-and$n.GetCommandName()-ceq'Invoke-Expression'},$true));if($iex.Count){throw 'cleanup integration gained executable Invoke-Expression'}
$temp=Join-Path $PSScriptRoot ('test_recovery_aware_cleanup_generated_'+[Guid]::NewGuid().ToString('N')+'.ps1')
try{
    [IO.File]::WriteAllText($temp,$patched,[Text.UTF8Encoding]::new($false));$pt=$null;$pe=$null;[Management.Automation.Language.Parser]::ParseFile($temp,[ref]$pt,[ref]$pe)|Out-Null
    if($pe.Count){$pe|ForEach-Object{Write-Error ("generated recovery-aware cleanup integration line=$($_.Extent.StartLineNumber) text=<$($_.Extent.Text)> $($_.Message)")};throw 'generated recovery-aware cleanup integration PS5.1 parse failed'}
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $temp
    if($LASTEXITCODE){throw "generated recovery-aware cleanup integration failed exit=$LASTEXITCODE"}
} finally {if(Test-Path -LiteralPath $temp){[IO.File]::Delete($temp)}}
Write-Host 'CUSTOM_APP_PRODUCTION_RECOVERY_AWARE_PERMIT_POST_APPLY_COMMIT_CLEANUP_BYTE_REAL_INTEGRATION_PASS real_preapply=true real_atomic=true real_finalization=true real_postswap_admission=true real_spicetify_apply=true generic_bounded_cleanup=true exact_fake_spicetify_apply_count=1 stage_workspace_removed=true app_backup_removed=true persistence_backup_removed=true unrelated_sibling_preserved=true recovery_ledger_reverified=true live_runtime_unchanged=true protected_persistence_unchanged=true requires_new_permit=true zero_authority=true'
