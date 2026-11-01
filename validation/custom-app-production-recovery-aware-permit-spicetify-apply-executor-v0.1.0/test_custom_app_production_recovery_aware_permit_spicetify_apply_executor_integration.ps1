$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$source=Join-Path $root 'validation/custom-app-production-recovery-aware-permit-post-swap-apply-admission-v0.1.0/test_custom_app_production_recovery_aware_permit_post_swap_apply_admission_integration.ps1'
$text=[IO.File]::ReadAllText($source,[Text.UTF8Encoding]::new($false))

function Get-RAXIUniqueIndexV010 {
    param([string]$Text,[string]$Marker,[string]$Label)
    $i=$Text.IndexOf($Marker,[StringComparison]::Ordinal)
    if($i-lt0){throw "apply integration marker missing: $Label"}
    if($Text.IndexOf($Marker,$i+$Marker.Length,[StringComparison]::Ordinal)-ge0){throw "apply integration marker not unique: $Label"}
    return $i
}

$importOld=@'
custom-app-production-recovery-aware-permit-post-swap-apply-admission-v0.1.0/custom-app-production-recovery-aware-permit-post-swap-apply-admission.ps1')"
'@.TrimEnd("`r","`n")
$importNew=@'
custom-app-production-recovery-aware-permit-post-swap-apply-admission-v0.1.0/custom-app-production-recovery-aware-permit-post-swap-apply-admission.ps1')`n    . (Join-Path `$root 'validation/custom-app-production-spicetify-apply-executor-v0.1.0/custom-app-production-spicetify-apply-executor.ps1')`n    . (Join-Path `$root 'validation/custom-app-production-recovery-aware-permit-spicetify-apply-executor-v0.1.0/custom-app-production-recovery-aware-permit-spicetify-apply-executor.ps1')"
'@.TrimEnd("`r","`n")
$i=Get-RAXIUniqueIndexV010 -Text $text -Marker $importOld -Label 'post-swap-generated-import-tail'
$patched=$text.Substring(0,$i)+$importNew+$text.Substring($i+$importOld.Length)

$restoreOld="        Restore-RAALIValidV010 `$valid `$prep `$r 'valid';`$integrationCount++"
$restoreNew=@'
        $raxApplyFakeDir=Join-Path ([string]$valid.base) 'recovery-aware-apply-fake';[IO.Directory]::CreateDirectory($raxApplyFakeDir)|Out-Null
        $raxApplyFakeExe=Join-Path $raxApplyFakeDir 'spicetify.exe';$raxApplyFakeCount=Join-Path $raxApplyFakeDir 'apply-count.txt'
        $raxApplyFakeSource=@"
using System;
using System.IO;
public static class RecoveryAwareSpicetifyFake {
    public static int Main(string[] args) {
        if (args == null || args.Length != 1 || !String.Equals(args[0], "apply", StringComparison.Ordinal)) return 91;
        var p=Environment.GetEnvironmentVariable("RAX_REAL_COUNT");
        if (String.IsNullOrWhiteSpace(p)) return 92;
        int n=0;
        if (File.Exists(p)) Int32.TryParse(File.ReadAllText(p).Trim(), out n);
        File.WriteAllText(p,(n+1).ToString());
        return 0;
    }
}
"@
        Add-Type -TypeDefinition $raxApplyFakeSource -Language CSharp -OutputAssembly $raxApplyFakeExe -OutputType ConsoleApplication
        Assert-RAALITrue (Test-Path -LiteralPath $raxApplyFakeExe -PathType Leaf) 'real recovery-aware apply fake spicetify.exe missing'
        $raxApplyFakeSha=(Get-FileHash -LiteralPath $raxApplyFakeExe -Algorithm SHA256).Hash.ToLowerInvariant();$env:RAX_REAL_COUNT=$raxApplyFakeCount
        try {
            $applyNow=$postAt.AddSeconds(1)
            $apply=Invoke-CustomAppProductionRecoveryAwarePermitSpicetifyApplyExecutorV010 -PriorRecoveryAwareAdmissionDecision $post.decision -RecoveryAwareFinalizationResult $final.result -RecoveryAwareAtomicResult $r.result -RecoveryAwarePreparedResult $prep.result -RecoveryAwareStageExecutorResult $valid.stage -ConsumptionPersistenceResult $valid.f.persisted -Permit $valid.f.p.f.p.r.issuer.permit -Name ([string]$valid.bundle.lifecycle.name) -LifecycleRow $valid.bundle.lifecycle -ProvenanceRow $valid.bundle.provenance -BindingRow $valid.bundle.binding -AllowedRoot $valid.q.f.ce.q.f.f.allowed -ConsumptionStoreDirectory $valid.f.p.store -SessionKey $script:RAIssuerKey -LocalAppDataRoot $valid.q.f.ce.q.f.f.q.persistence.local -AppDataRoot $valid.q.f.ce.q.f.f.q.persistence.roaming -SpicetifyExecutablePath $raxApplyFakeExe -ExpectedSpicetifySha256 $raxApplyFakeSha -Now $applyNow -TimeoutSeconds 10
        } finally {Remove-Item Env:RAX_REAL_COUNT -ErrorAction SilentlyContinue}
        Assert-RAALITrue ([bool]$apply.ok) ('real recovery-aware Spicetify apply denied: '+[string]$apply.reason)
        Assert-RAALITrue ([bool]$apply.spicetify_apply_executed) 'real recovery-aware apply did not report execution'
        Assert-RAALIFalse ([bool]$apply.rollback_attempted) 'real recovery-aware apply unexpectedly rolled back'
        Assert-RAALITrue ([bool]$apply.requires_post_apply_commit_cleanup) 'real recovery-aware apply missing post-apply cleanup requirement'
        $applyCount=0;if(Test-Path -LiteralPath $raxApplyFakeCount -PathType Leaf){[void][int]::TryParse(([IO.File]::ReadAllText($raxApplyFakeCount)).Trim(),[ref]$applyCount)}
        Assert-RAALITrue ($applyCount -eq 1) ('real recovery-aware apply process count drifted: '+$applyCount)
        $applyCheck=Test-CustomAppProductionRecoveryAwarePermitSpicetifyApplyResultV010 -Result $apply.result;Assert-RAALITrue ([bool]$applyCheck.ok) ('real recovery-aware apply result validator denied: '+[string]$applyCheck.reason)
        Assert-RAALIEq ([string]$apply.result.historical_consumption_envelope_sha256).Trim().ToLowerInvariant() ([string]$post.decision.historical_consumption_envelope_sha256).Trim().ToLowerInvariant() 'real recovery-aware apply historical envelope continuity'
        Assert-RAALITrue ([int64]$apply.result.current_consumption_revision -ge [int64]$post.decision.current_consumption_revision) 'real recovery-aware apply consumption revision regressed'
        Assert-RAALIEq ([string]$apply.result.live_tree_sha256).Trim().ToLowerInvariant() ([string]$valid.remote_tree).Trim().ToLowerInvariant() 'real recovery-aware apply live tree not staged remote tree'
        Assert-RAALIEq ([string]$apply.result.remote_tree_sha256).Trim().ToLowerInvariant() ([string]$valid.remote_tree).Trim().ToLowerInvariant() 'real recovery-aware apply remote tree drifted'
        Assert-RAALIEq ([string]$apply.result.spicetify_executable_sha256).Trim().ToLowerInvariant() $raxApplyFakeSha 'real recovery-aware apply executable hash drifted'
        foreach($field in @('session_key_persisted','session_key_exposed','result_is_authority','spicetify_apply_authorized','additional_mutation_authorized','live_destination_authorized','production_execution_authorized','production_mutation_authorized')){Assert-RAALIFalse ([bool]$apply.result.$field) ('real recovery-aware apply authority/key escaped '+$field)}
        $liveAfterApply=& $script:RASEOriginalLocalBaseline -Name ([string]$valid.bundle.lifecycle.name) -AppPath ([string]$valid.live_path);Assert-RAALIEq ([string]$liveAfterApply.tree_sha256).Trim().ToLowerInvariant() ([string]$valid.remote_tree).Trim().ToLowerInvariant() 'real recovery-aware apply mutated CustomApp live tree'
        $persistAfterApply=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $valid.q.f.ce.q.f.f.q.persistence.local -AppDataRoot $valid.q.f.ce.q.f.f.q.persistence.roaming;Assert-RAALIEq ([string]$persistAfterApply.fingerprint).Trim().ToLowerInvariant() ([string]$prep.result.persistence_fingerprint).Trim().ToLowerInvariant() 'real recovery-aware apply mutated protected persistence in fake success path'
        foreach($path in @([string]$prep.result.stage_workspace_path,[string]$prep.result.stage_path,[string]$prep.result.app_backup_path,[string]$prep.result.persistence_backup_path)){Assert-RAALITrue (Test-Path -LiteralPath $path -PathType Container) ('real recovery-aware apply lost retained evidence '+$path)}
        Restore-RAALIValidV010 $valid $prep $r 'valid';$integrationCount++
'@
$i=Get-RAXIUniqueIndexV010 -Text $patched -Marker $restoreOld -Label 'post-swap-valid-restore-anchor'
$patched=$patched.Substring(0,$i)+$restoreNew.TrimEnd("`r","`n")+$patched.Substring($i+$restoreOld.Length)

foreach($m in @('custom-app-production-spicetify-apply-executor.ps1','custom-app-production-recovery-aware-permit-spicetify-apply-executor.ps1','Invoke-CustomAppProductionRecoveryAwarePermitSpicetifyApplyExecutorV010','RecoveryAwareSpicetifyFake','raxApplyFakeExe','real recovery-aware apply process count drifted','real recovery-aware apply result validator denied','real recovery-aware apply lost retained evidence')){if($patched.IndexOf($m,[StringComparison]::Ordinal)-lt0){throw "apply integration coverage marker missing $m"}}
$pt=$null;$pe=$null;$past=[Management.Automation.Language.Parser]::ParseInput($patched,[ref]$pt,[ref]$pe);if($pe.Count){$pe|ForEach-Object{Write-Error ("patched post-swap generator line=$($_.Extent.StartLineNumber) text=<$($_.Extent.Text)> $($_.Message)")};throw 'patched post-swap generator PS5.1 parse failed'}
$pex=@($past.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'Invoke-Expression'},$true));if($pex.Count){throw 'patched post-swap generator gained executable Invoke-Expression command'}
$temp=Join-Path $PSScriptRoot ('test_recovery_aware_apply_generated_'+[Guid]::NewGuid().ToString('N')+'.ps1')
try{
    [IO.File]::WriteAllText($temp,$patched,[Text.UTF8Encoding]::new($false));$tokens=$null;$errors=$null;[Management.Automation.Language.Parser]::ParseFile($temp,[ref]$tokens,[ref]$errors)|Out-Null
    if($errors.Count){$errors|ForEach-Object{Write-Error ("generated recovery-aware apply integration line=$($_.Extent.StartLineNumber) text=<$($_.Extent.Text)> $($_.Message)")};throw 'generated recovery-aware apply integration PS5.1 parse failed'}
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $temp
    if($LASTEXITCODE){throw "generated recovery-aware apply integration failed exit=$LASTEXITCODE"}
} finally {if(Test-Path -LiteralPath $temp){[IO.File]::Delete($temp)}}
Write-Host 'CUSTOM_APP_PRODUCTION_RECOVERY_AWARE_PERMIT_SPICETIFY_APPLY_EXECUTOR_BYTE_REAL_INTEGRATION_PASS real_preapply=true real_atomic=true real_finalization=true real_postswap_admission=true exact_fake_spicetify_apply_count=1 recovery_ledger_reverified=true live_customapp_unchanged_by_fake_apply=true protected_persistence_unchanged=true evidence_preserved=true zero_authority=true'