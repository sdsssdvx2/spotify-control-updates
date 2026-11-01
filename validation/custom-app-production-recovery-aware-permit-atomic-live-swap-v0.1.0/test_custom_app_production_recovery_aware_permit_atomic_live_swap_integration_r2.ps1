$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$source=Join-Path $PSScriptRoot 'test_custom_app_production_recovery_aware_permit_atomic_live_swap_integration.ps1'
$text=[IO.File]::ReadAllText($source,[Text.UTF8Encoding]::new($false))

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
$first=$text.IndexOf($old,[StringComparison]::Ordinal)
if($first-lt0){throw 'r2 target assertion not found'}
if($text.IndexOf($old,$first+$old.Length,[StringComparison]::Ordinal)-ge0){throw 'r2 target assertion not unique'}
$patched=$text.Substring(0,$first)+$new.TrimEnd("`r","`n")+$text.Substring($first+$old.Length)
$oldMarker='stable_and_byte_real_views_separate=true'
$newMarker='recovery_stable_full_tree_equals_byte_real_full_tree=true byte_real_backup_exact=true optional_vcs_provenance_parity=true runtime_view_verified_independently=true'
if($patched.IndexOf($oldMarker,[StringComparison]::Ordinal)-lt0){throw 'r2 output marker not found'}
$patched=$patched.Replace($oldMarker,$newMarker)
if($patched.IndexOf('valid fixture collapsed stable and byte-real trees',[StringComparison]::Ordinal)-ge0){throw 'r2 obsolete assertion survived patch'}
foreach($m in @('valid recovery-stable full tree no longer equals byte-real full tree before atomic','valid byte-real live/rollback backup full tree mismatch before atomic','valid byte-real live/rollback backup file count mismatch before atomic','valid byte-real live/rollback backup byte count mismatch before atomic','valid byte-real runtime view drifted before atomic','valid live/rollback backup VCS presence mismatch','valid live/rollback backup VCS tree mismatch','recovery_stable_full_tree_equals_byte_real_full_tree=true','byte_real_backup_exact=true','optional_vcs_provenance_parity=true','runtime_view_verified_independently=true')){if($patched.IndexOf($m,[StringComparison]::Ordinal)-lt0){throw "r2 semantic marker missing $m"}}
foreach($bad in @('valid live .git provenance missing before atomic','valid rollback backup .git provenance missing before atomic','valid fixture collapsed runtime view and byte-real full tree','recovery-closed no-VCS fixture unexpectedly split runtime and full tree','r2 fixture unexpectedly reintroduced post-recovery VCS metadata')){if($patched.IndexOf($bad,[StringComparison]::OrdinalIgnoreCase)-ge0){throw "obsolete cross-domain/VCS assumption survived: $bad"}}
$temp=Join-Path $PSScriptRoot ('test_custom_app_production_recovery_aware_permit_atomic_live_swap_integration_r2_generated_'+[Guid]::NewGuid().ToString('N')+'.ps1')
try{
    [IO.File]::WriteAllText($temp,$patched,[Text.UTF8Encoding]::new($false))
    $tokens=$null;$errors=$null;[Management.Automation.Language.Parser]::ParseFile($temp,[ref]$tokens,[ref]$errors)|Out-Null
    if($errors.Count){$errors|ForEach-Object{Write-Error ("r2 generated line=$($_.Extent.StartLineNumber) text=<$($_.Extent.Text)> $($_.Message)")};throw 'r2 generated integration PS5.1 parse failed'}
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $temp
    if($LASTEXITCODE){throw "r2 generated integration failed exit=$LASTEXITCODE"}
} finally {
    if(Test-Path -LiteralPath $temp){[IO.File]::Delete($temp)}
}
Write-Host 'CUSTOM_APP_PRODUCTION_RECOVERY_AWARE_PERMIT_ATOMIC_INTEGRATION_R2_PATCH_HARNESS_PASS recovery_stable_full_tree_equals_byte_real_full_tree=true byte_real_backup_exact=true optional_vcs_provenance_parity=true runtime_view_verified_independently=true recovery_closed_live_bytes_unchanged=true'