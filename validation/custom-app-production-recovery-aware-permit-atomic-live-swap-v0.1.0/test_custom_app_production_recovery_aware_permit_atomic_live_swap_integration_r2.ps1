$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$source=Join-Path $PSScriptRoot 'test_custom_app_production_recovery_aware_permit_atomic_live_swap_integration.ps1'
$text=[IO.File]::ReadAllText($source,[Text.UTF8Encoding]::new($false))

$old="Assert-RAALIFalse (([string]`$valid.stable_tree).Trim().ToLowerInvariant() -ceq ([string]`$before.tree_sha256).Trim().ToLowerInvariant()) 'valid fixture collapsed stable and byte-real trees'"
$new=@'
        Assert-RAALIEq ([string]$valid.stable_tree).Trim().ToLowerInvariant() ([string]$before.tree_sha256).Trim().ToLowerInvariant() 'valid recovery-stable full tree no longer equals byte-real full tree before atomic'
        $liveGit=Join-Path ([string]$valid.live_path) '.git\config';$backupGit=Join-Path ([string]$prep.result.app_backup_path) '.git\config'
        Assert-RAALITrue (Test-Path -LiteralPath $liveGit -PathType Leaf) 'valid live .git provenance missing before atomic'
        Assert-RAALITrue (Test-Path -LiteralPath $backupGit -PathType Leaf) 'valid rollback backup .git provenance missing before atomic'
        Assert-RAALIEq ([Convert]::ToBase64String([IO.File]::ReadAllBytes($liveGit))) ([Convert]::ToBase64String([IO.File]::ReadAllBytes($backupGit))) 'valid live/backup .git provenance bytes differ'
        $runtimeBefore=& $script:RASEOriginalLocalBaseline -Name ([string]$valid.bundle.lifecycle.name) -AppPath ([string]$valid.live_path)
        Assert-RAALIEq ([string]$runtimeBefore.tree_sha256).Trim().ToLowerInvariant() ([string]$valid.actual_live_tree).Trim().ToLowerInvariant() 'valid byte-real runtime view drifted before atomic'
        Assert-RAALIFalse (([string]$runtimeBefore.tree_sha256).Trim().ToLowerInvariant() -ceq ([string]$before.tree_sha256).Trim().ToLowerInvariant()) 'valid fixture collapsed runtime view and byte-real full tree'
'@
$first=$text.IndexOf($old,[StringComparison]::Ordinal)
if($first-lt0){throw 'r2 target assertion not found'}
if($text.IndexOf($old,$first+$old.Length,[StringComparison]::Ordinal)-ge0){throw 'r2 target assertion not unique'}
$patched=$text.Substring(0,$first)+$new.TrimEnd("`r","`n")+$text.Substring($first+$old.Length)
$oldMarker='stable_and_byte_real_views_separate=true'
$newMarker='stable_full_tree_equals_recovery_stable=true runtime_and_full_tree_views_separate=true byte_real_git_provenance_preserved=true'
if($patched.IndexOf($oldMarker,[StringComparison]::Ordinal)-lt0){throw 'r2 output marker not found'}
$patched=$patched.Replace($oldMarker,$newMarker)
if($patched.IndexOf('valid fixture collapsed stable and byte-real trees',[StringComparison]::Ordinal)-ge0){throw 'r2 obsolete assertion survived patch'}
foreach($m in @('valid recovery-stable full tree no longer equals byte-real full tree before atomic','valid live .git provenance missing before atomic','valid rollback backup .git provenance missing before atomic','valid live/backup .git provenance bytes differ','valid byte-real runtime view drifted before atomic','valid fixture collapsed runtime view and byte-real full tree','stable_full_tree_equals_recovery_stable=true','runtime_and_full_tree_views_separate=true','byte_real_git_provenance_preserved=true')){if($patched.IndexOf($m,[StringComparison]::Ordinal)-lt0){throw "r2 semantic marker missing $m"}}
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
Write-Host 'CUSTOM_APP_PRODUCTION_RECOVERY_AWARE_PERMIT_ATOMIC_INTEGRATION_R2_PATCH_HARNESS_PASS stable_full_tree_equals_recovery_stable=true runtime_and_full_tree_views_separate=true byte_real_git_provenance_preserved=true recovery_closed_live_bytes_unchanged=true'