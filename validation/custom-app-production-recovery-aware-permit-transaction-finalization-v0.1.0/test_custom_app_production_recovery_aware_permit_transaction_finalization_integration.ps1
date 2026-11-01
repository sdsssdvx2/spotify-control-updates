$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$source=Join-Path $root 'validation/custom-app-production-recovery-aware-permit-atomic-live-swap-v0.1.0/test_custom_app_production_recovery_aware_permit_atomic_live_swap_integration.ps1'
$text=[IO.File]::ReadAllText($source,[Text.UTF8Encoding]::new($false))

function Get-RAFTIUniqueIndexV010 {
    param([string]$Text,[string]$Marker,[string]$Label)
    $i=$Text.IndexOf($Marker,[StringComparison]::Ordinal);if($i-lt0){throw "integration marker missing: $Label"};if($Text.IndexOf($Marker,$i+$Marker.Length,[StringComparison]::Ordinal)-ge0){throw "integration marker not unique: $Label"};return $i
}

# Reapply the exact semantic corrections from the validated atomic r2 harness so this
# integration consumes the final atomic fixture contract, not the superseded base assumptions.
$old="Assert-RAALIFalse (([string]`$valid.stable_tree).Trim().ToLowerInvariant() -ceq ([string]`$before.tree_sha256).Trim().ToLowerInvariant()) 'valid fixture collapsed stable and byte-real trees'"
$new=@'
        Assert-RAALIEq ([string]$valid.stable_tree).Trim().ToLowerInvariant() ([string]$before.tree_sha256).Trim().ToLowerInvariant() 'valid recovery-stable full tree no longer equals byte-real full tree before atomic'
        Assert-RAALIEq ([string]$before.tree_sha256).Trim().ToLowerInvariant() ([string]$prep.result.app_backup_tree_sha256).Trim().ToLowerInvariant() 'valid byte-real live/rollback backup full tree mismatch before atomic'
        Assert-RAALITrue ([int]$before.file_count -eq [int]$prep.result.app_backup_file_count) 'valid byte-real live/rollback backup file count mismatch before atomic'
        Assert-RAALITrue ([int64]$before.total_bytes -eq [int64]$prep.result.app_backup_total_bytes) 'valid byte-real live/rollback backup byte count mismatch before atomic'
        $runtimeBefore=& $script:RASEOriginalLocalBaseline -Name ([string]$valid.bundle.lifecycle.name) -AppPath ([string]$valid.live_path)
        Assert-RAALIEq ([string]$runtimeBefore.tree_sha256).Trim().ToLowerInvariant() ([string]$valid.actual_live_tree).Trim().ToLowerInvariant() 'valid byte-real runtime view drifted before atomic'
        $liveGit=Join-Path ([string]$valid.live_path) '.git';$backupGit=Join-Path ([string]$prep.result.app_backup_path) '.git'
        $liveGitPresent=Test-Path -LiteralPath $liveGit -PathType Container;$backupGitPresent=Test-Path -LiteralPath $backupGit -PathType Container
        Assert-RAALITrue ($liveGitPresent -eq $backupGitPresent) 'valid live/rollback backup VCS presence mismatch'
        if($liveGitPresent){
            $liveGitSnapshot=Get-CustomAppUpdateTreeSnapshotV010 -Root $liveGit;$backupGitSnapshot=Get-CustomAppUpdateTreeSnapshotV010 -Root $backupGit
            Assert-RAALIEq ([string]$liveGitSnapshot.tree_sha256).Trim().ToLowerInvariant() ([string]$backupGitSnapshot.tree_sha256).Trim().ToLowerInvariant() 'valid live/rollback backup VCS tree mismatch'
            Assert-RAALITrue ([int]$liveGitSnapshot.file_count -eq [int]$backupGitSnapshot.file_count) 'valid live/rollback backup VCS file count mismatch'
            Assert-RAALITrue ([int64]$liveGitSnapshot.total_bytes -eq [int64]$backupGitSnapshot.total_bytes) 'valid live/rollback backup VCS byte count mismatch'
        }
'@
$i=Get-RAFTIUniqueIndexV010 -Text $text -Marker $old -Label 'atomic-r2-valid-tree-contract';$patched=$text.Substring(0,$i)+$new.TrimEnd("`r","`n")+$text.Substring($i+$old.Length)

$stageOld="Assert-RAALITrue ([string]`$r.reason -like '*atomic-mutation-stage-runtime-mismatch*') ('stage drift reason '+[string]`$r.reason)"
$stageNew="Assert-RAALITrue ([string]`$r.reason -ceq 'recovery-aware-atomic-prepared-result-invalid:recovery-aware-pre-apply-generic-result-invalid:pre-apply-result-stage-integrity-mismatch') ('stage drift reason '+[string]`$r.reason)"
$i=Get-RAFTIUniqueIndexV010 -Text $patched -Marker $stageOld -Label 'atomic-r2-stage-drift-contract';$patched=$patched.Substring(0,$i)+$stageNew+$patched.Substring($i+$stageOld.Length)

$clockOld=@'
        $histB=New-RAPCFixtureV010 -Label 'bounded-atomic-unrelated-rev2-future' -Name 'future-app' -Source 'owner/future-app' -Manifest 'Future App' -Nonce ('3'*32);$bAt=$historical.q.at.AddSeconds(16)
'@.TrimEnd("`r","`n")
$clockNew=@'
        $histB=New-RAPCFixtureV010 -Label 'bounded-atomic-unrelated-rev2-future' -Name 'future-app' -Source 'owner/future-app' -Manifest 'Future App' -Nonce ('3'*32);$bAt=$histB.p.r.ready.at.AddSeconds(10)
        $historicalPermitExpires=[DateTimeOffset]::Parse([string]$historical.f.p.f.p.r.issuer.permit.expires_at)
        Assert-RAALITrue ($bAt.AddSeconds(2) -lt $historicalPermitExpires) 'unrelated rev2 fixture-local clock no longer overlaps historical permit'
'@.TrimEnd("`r","`n")
$i=Get-RAFTIUniqueIndexV010 -Text $patched -Marker $clockOld -Label 'atomic-r2-unrelated-clock';$patched=$patched.Substring(0,$i)+$clockNew+$patched.Substring($i+$clockOld.Length)

$oldMarker='stable_and_byte_real_views_separate=true';$newMarker='recovery_stable_full_tree_equals_byte_real_full_tree=true byte_real_backup_exact=true optional_vcs_provenance_parity=true runtime_view_verified_independently=true stage_drift_rejected_at_prepared_integrity_gate=true unrelated_rev2_fixture_local_clock=true'
if($patched.IndexOf($oldMarker,[StringComparison]::Ordinal)-lt0){throw 'atomic r2 output marker missing'};$patched=$patched.Replace($oldMarker,$newMarker)

# Load the recovery-aware finalizer into the generated byte-real atomic integration process.
$importOld="    . (Join-Path `$root 'validation/custom-app-production-recovery-aware-permit-atomic-live-swap-v0.1.0/custom-app-production-recovery-aware-permit-atomic-live-swap.ps1')"
$importNew=$importOld+"`n    . (Join-Path `$root 'validation/custom-app-production-recovery-aware-permit-transaction-finalization-v0.1.0/custom-app-production-recovery-aware-permit-transaction-finalization.ps1')"
$i=Get-RAFTIUniqueIndexV010 -Text $patched -Marker $importOld -Label 'finalization-import-anchor';$patched=$patched.Substring(0,$i)+$importNew+$patched.Substring($i+$importOld.Length)

# In the already validated real valid path, finalize the transaction before restoring the fixture.
$restoreOld="Restore-RAALIValidV010 `$valid `$prep `$r 'valid';`$integrationCount++"
$restoreNew=@'
        $finalSentinel=Join-Path ([IO.Path]::GetDirectoryName([string]$valid.live_path)) ('.spotify-control-finalization-sentinel-'+[Guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($finalSentinel)|Out-Null
        $final=Invoke-CustomAppProductionRecoveryAwarePermitTransactionFinalizationV010 -RecoveryAwareAtomicResult $r.result -RecoveryAwarePreparedResult $prep.result -RecoveryAwareStageExecutorResult $valid.stage -Name ([string]$valid.bundle.lifecycle.name) -LifecycleRow $valid.bundle.lifecycle -AllowedRoot $valid.q.f.ce.q.f.f.allowed -ConsumptionStoreDirectory $valid.f.p.store -ConsumptionPersistenceResult $valid.f.persisted -LocalAppDataRoot $valid.q.f.ce.q.f.f.q.persistence.local -AppDataRoot $valid.q.f.ce.q.f.f.q.persistence.roaming -Now ([DateTimeOffset]::Parse([string]$prep.result.post_backup_revalidated_at).AddSeconds(2))
        Assert-RAALITrue ([bool]$final.ok) ('real recovery-aware transaction finalization denied: '+[string]$final.reason)
        Assert-RAALITrue ([bool]$final.transaction_workspace_deleted -and [bool]$final.stage_workspace_preserved -and [bool]$final.app_backup_preserved -and [bool]$final.persistence_backup_preserved) 'real finalization preservation flags missing'
        Assert-RAALITrue ([bool]$final.historical_consumption_reverified_before_cleanup -and [bool]$final.historical_consumption_reverified_after_cleanup -and [bool]$final.same_app_newer_consumption_absent) 'real finalization consumption flags missing'
        Assert-RAALITrue ([bool]$final.requires_spicetify_apply_phase -and [bool]$final.requires_fresh_post_swap_apply_admission -and [bool]$final.requires_recovery_if_post_cleanup_validation_fails) 'real finalization downstream boundary flags missing'
        foreach($field in @('result_is_authority','apply_execution_authorized','spicetify_apply_authorized','additional_mutation_authorized','live_destination_authorized','production_execution_authorized','production_mutation_authorized')){Assert-RAALIFalse ([bool]$final.result.$field) ('real finalization authority escaped '+$field)}
        Assert-RAALIFalse (Test-Path -LiteralPath ([string]$r.result.transaction_root)) 'real finalization left transaction workspace'
        Assert-RAALITrue (Test-Path -LiteralPath $finalSentinel -PathType Container) 'real finalization deleted unrelated sibling'
        foreach($path in @([string]$prep.result.stage_workspace_path,[string]$prep.result.stage_path,[string]$prep.result.app_backup_path,[string]$prep.result.persistence_backup_path)){Assert-RAALITrue (Test-Path -LiteralPath $path -PathType Container) ('real finalization failed to preserve evidence '+$path)}
        $fc=Test-CustomAppProductionRecoveryAwarePermitTransactionFinalizationResultV010 -Result $final.result;Assert-RAALITrue ([bool]$fc.ok) ('real finalization result validator denied: '+[string]$fc.reason)
        $liveAfterFinal=& $script:RASEOriginalLocalBaseline -Name ([string]$valid.bundle.lifecycle.name) -AppPath ([string]$valid.live_path);Assert-RAALIEq ([string]$liveAfterFinal.tree_sha256).Trim().ToLowerInvariant() ([string]$valid.remote_tree).Trim().ToLowerInvariant() 'real finalization changed swapped live runtime'
        $persistAfterFinal=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $valid.q.f.ce.q.f.f.q.persistence.local -AppDataRoot $valid.q.f.ce.q.f.f.q.persistence.roaming;Assert-RAALIEq ([string]$persistAfterFinal.fingerprint).Trim().ToLowerInvariant() ([string]$prep.result.persistence_fingerprint).Trim().ToLowerInvariant() 'real finalization changed protected persistence'
        Restore-RAALIValidV010 $valid $prep $r 'valid';$integrationCount++
'@
$i=Get-RAFTIUniqueIndexV010 -Text $patched -Marker $restoreOld -Label 'valid-restore-anchor';$patched=$patched.Substring(0,$i)+$restoreNew.TrimEnd("`r","`n")+$patched.Substring($i+$restoreOld.Length)

foreach($m in @('Invoke-CustomAppProductionRecoveryAwarePermitTransactionFinalizationV010','real recovery-aware transaction finalization denied','real finalization deleted unrelated sibling','real finalization result validator denied','real finalization changed swapped live runtime','real finalization changed protected persistence')){if($patched.IndexOf($m,[StringComparison]::Ordinal)-lt0){throw "finalization integration marker missing $m"}}
$temp=Join-Path $PSScriptRoot ('test_recovery_aware_finalization_generated_'+[Guid]::NewGuid().ToString('N')+'.ps1')
try{
    [IO.File]::WriteAllText($temp,$patched,[Text.UTF8Encoding]::new($false));$tokens=$null;$errors=$null;[Management.Automation.Language.Parser]::ParseFile($temp,[ref]$tokens,[ref]$errors)|Out-Null
    if($errors.Count){$errors|ForEach-Object{Write-Error ("generated finalization integration line=$($_.Extent.StartLineNumber) text=<$($_.Extent.Text)> $($_.Message)")};throw 'generated finalization integration PS5.1 parse failed'}
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $temp
    if($LASTEXITCODE){throw "generated recovery-aware finalization integration failed exit=$LASTEXITCODE"}
} finally {if(Test-Path -LiteralPath $temp){[IO.File]::Delete($temp)}}
Write-Host 'CUSTOM_APP_PRODUCTION_RECOVERY_AWARE_PERMIT_TRANSACTION_FINALIZATION_BYTE_REAL_INTEGRATION_PASS real_preapply=true real_atomic=true bounded_transaction_cleanup=true live_runtime_unchanged=true persistence_unchanged=true evidence_preserved=true unrelated_sibling_preserved=true zero_apply_authority=true'