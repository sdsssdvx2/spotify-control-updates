$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$source=Join-Path $root 'validation/custom-app-production-recovery-aware-permit-transaction-finalization-v0.1.0/test_custom_app_production_recovery_aware_permit_transaction_finalization_integration.ps1'
$text=[IO.File]::ReadAllText($source,[Text.UTF8Encoding]::new($false))

function Get-RAPSAIUniqueIndexV010 {
    param([string]$Text,[string]$Marker,[string]$Label)
    $i=$Text.IndexOf($Marker,[StringComparison]::Ordinal);if($i-lt0){throw "integration marker missing: $Label"};if($Text.IndexOf($Marker,$i+$Marker.Length,[StringComparison]::Ordinal)-ge0){throw "integration marker not unique: $Label"};return $i
}

$importOld=@'
$importNew=$importOld+"`n    . (Join-Path `$root 'validation/custom-app-production-recovery-aware-permit-transaction-finalization-v0.1.0/custom-app-production-recovery-aware-permit-transaction-finalization.ps1')"
'@.TrimEnd("`r","`n")
$importNew=@'
$importNew=$importOld+"`n    . (Join-Path `$root 'validation/custom-app-production-recovery-aware-permit-transaction-finalization-v0.1.0/custom-app-production-recovery-aware-permit-transaction-finalization.ps1')`n    . (Join-Path `$root 'validation/custom-app-production-transaction-finalization-v0.1.0/custom-app-production-transaction-finalization.ps1')`n    . (Join-Path `$root 'validation/custom-app-production-post-swap-apply-admission-v0.1.0/custom-app-production-post-swap-apply-admission.ps1')`n    . (Join-Path `$root 'validation/custom-app-production-recovery-aware-permit-post-swap-apply-admission-v0.1.0/custom-app-production-recovery-aware-permit-post-swap-apply-admission.ps1')"
'@.TrimEnd("`r","`n")
$i=Get-RAPSAIUniqueIndexV010 -Text $text -Marker $importOld -Label 'generated-import-chain';$patched=$text.Substring(0,$i)+$importNew+$text.Substring($i+$importOld.Length)

$restoreOld="        Restore-RAALIValidV010 `$valid `$prep `$r 'valid';`$integrationCount++"
$restoreNew=@'
        $postAt=[DateTimeOffset]::Parse([string]$prep.result.post_backup_revalidated_at).AddSeconds(3)
        $post=Resolve-CustomAppProductionRecoveryAwarePermitPostSwapApplyAdmissionV010 -RecoveryAwareFinalizationResult $final.result -RecoveryAwareAtomicResult $r.result -RecoveryAwarePreparedResult $prep.result -RecoveryAwareStageExecutorResult $valid.stage -ConsumptionPersistenceResult $valid.f.persisted -Permit $valid.f.p.f.p.r.issuer.permit -Name ([string]$valid.bundle.lifecycle.name) -LifecycleRow $valid.bundle.lifecycle -ProvenanceRow $valid.bundle.provenance -BindingRow $valid.bundle.binding -AllowedRoot $valid.q.f.ce.q.f.f.allowed -ConsumptionStoreDirectory $valid.f.p.store -SessionKey $script:RAIssuerKey -LocalAppDataRoot $valid.q.f.ce.q.f.f.q.persistence.local -AppDataRoot $valid.q.f.ce.q.f.f.q.persistence.roaming -Now $postAt
        Assert-RAALITrue ([bool]$post.ok) ('real recovery-aware post-swap admission denied: '+[string]$post.reason)
        Assert-RAALITrue ([bool]$post.apply_eligible -and [bool]$post.session_key_accepted) 'real post-swap eligibility/session-key flags missing'
        Assert-RAALITrue ([bool]$post.requires_immediate_rerun_by_apply_executor -and [bool]$post.requires_exact_spicetify_apply_executor -and [bool]$post.requires_exact_rollback_on_apply_failure) 'real post-swap downstream boundary flags missing'
        foreach($field in @('session_key_persisted','session_key_exposed','admission_is_authority','apply_execution_authorized','spicetify_apply_authorized','additional_mutation_authorized','live_destination_authorized','production_execution_authorized','production_mutation_authorized')){Assert-RAALIFalse ([bool]$post.decision.$field) ('real post-swap authority/key escaped '+$field)}
        $postCheck=Test-CustomAppProductionRecoveryAwarePermitPostSwapApplyAdmissionDecisionV010 -Decision $post.decision;Assert-RAALITrue ([bool]$postCheck.ok) ('real post-swap decision validator denied: '+[string]$postCheck.reason)
        Assert-RAALIEq ([string]$post.decision.historical_consumption_envelope_sha256).Trim().ToLowerInvariant() ([string]$final.result.historical_consumption_envelope_sha256).Trim().ToLowerInvariant() 'real post-swap historical envelope continuity'
        Assert-RAALIEq ([string]$post.decision.current_consumption_envelope_sha256).Trim().ToLowerInvariant() ([string]$final.result.current_consumption_envelope_sha256).Trim().ToLowerInvariant() 'real post-swap current envelope continuity'
        Assert-RAALITrue ([int64]$post.decision.current_consumption_revision -eq [int64]$final.result.current_consumption_revision) 'real post-swap current revision drifted'
        Assert-RAALIEq ([string]$post.decision.live_tree_sha256).Trim().ToLowerInvariant() ([string]$valid.remote_tree).Trim().ToLowerInvariant() 'real post-swap live tree not remote stage'
        Assert-RAALIEq ([string]$post.decision.remote_tree_sha256).Trim().ToLowerInvariant() ([string]$valid.remote_tree).Trim().ToLowerInvariant() 'real post-swap remote tree drifted'
        $liveAfterAdmission=& $script:RASEOriginalLocalBaseline -Name ([string]$valid.bundle.lifecycle.name) -AppPath ([string]$valid.live_path);Assert-RAALIEq ([string]$liveAfterAdmission.tree_sha256).Trim().ToLowerInvariant() ([string]$valid.remote_tree).Trim().ToLowerInvariant() 'real post-swap admission mutated live runtime'
        $persistAfterAdmission=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $valid.q.f.ce.q.f.f.q.persistence.local -AppDataRoot $valid.q.f.ce.q.f.f.q.persistence.roaming;Assert-RAALIEq ([string]$persistAfterAdmission.fingerprint).Trim().ToLowerInvariant() ([string]$prep.result.persistence_fingerprint).Trim().ToLowerInvariant() 'real post-swap admission mutated protected persistence'
        foreach($path in @([string]$prep.result.stage_workspace_path,[string]$prep.result.stage_path,[string]$prep.result.app_backup_path,[string]$prep.result.persistence_backup_path)){Assert-RAALITrue (Test-Path -LiteralPath $path -PathType Container) ('real post-swap admission lost retained evidence '+$path)}
        Restore-RAALIValidV010 $valid $prep $r 'valid';$integrationCount++
'@
$i=Get-RAPSAIUniqueIndexV010 -Text $patched -Marker $restoreOld -Label 'valid-restore-anchor';$patched=$patched.Substring(0,$i)+$restoreNew.TrimEnd("`r","`n")+$patched.Substring($i+$restoreOld.Length)

foreach($m in @('Resolve-CustomAppProductionRecoveryAwarePermitPostSwapApplyAdmissionV010','real recovery-aware post-swap admission denied','real post-swap decision validator denied','real post-swap admission mutated live runtime','real post-swap admission mutated protected persistence','real post-swap admission lost retained evidence')){if($patched.IndexOf($m,[StringComparison]::Ordinal)-lt0){throw "post-swap integration marker missing $m"}}
$temp=Join-Path $PSScriptRoot ('test_recovery_aware_post_swap_generated_'+[Guid]::NewGuid().ToString('N')+'.ps1')
try{
    [IO.File]::WriteAllText($temp,$patched,[Text.UTF8Encoding]::new($false));$tokens=$null;$errors=$null;[Management.Automation.Language.Parser]::ParseFile($temp,[ref]$tokens,[ref]$errors)|Out-Null
    if($errors.Count){$errors|ForEach-Object{Write-Error ("generated post-swap integration line=$($_.Extent.StartLineNumber) text=<$($_.Extent.Text)> $($_.Message)")};throw 'generated post-swap integration PS5.1 parse failed'}
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $temp
    if($LASTEXITCODE){throw "generated recovery-aware post-swap integration failed exit=$LASTEXITCODE"}
} finally {if(Test-Path -LiteralPath $temp){[IO.File]::Delete($temp)}}
Write-Host 'CUSTOM_APP_PRODUCTION_RECOVERY_AWARE_PERMIT_POST_SWAP_APPLY_ADMISSION_BYTE_REAL_INTEGRATION_PASS real_preapply=true real_atomic=true real_finalization=true generic_postswap_reused=true ledger_double_read=true live_runtime_unchanged=true persistence_unchanged=true evidence_preserved=true zero_authority=true'
