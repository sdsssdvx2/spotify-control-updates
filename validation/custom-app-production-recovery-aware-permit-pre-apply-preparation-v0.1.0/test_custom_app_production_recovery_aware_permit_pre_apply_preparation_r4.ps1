$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0

$source=Join-Path $PSScriptRoot 'test_custom_app_production_recovery_aware_permit_pre_apply_preparation.ps1'
$text=[IO.File]::ReadAllText($source,[Text.UTF8Encoding]::new($false)).Replace("`r`n","`n")

$oldVcs=@'
    # Root VCS metadata is deliberately invisible to the runtime baseline but must be
    # copied byte-for-byte into the rollback backup.
    $git=Join-Path ([string]$built.live_path) '.git';[IO.Directory]::CreateDirectory($git)|Out-Null
    [IO.File]::WriteAllText((Join-Path $git 'config'),("[remote `"origin`"]`nurl = https://github.com/$Source.git`n"),[Text.UTF8Encoding]::new($false))
    $rawLive=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$built.live_path)
    $runtimeAfterGit=& $script:RASEOriginalLocalBaseline -Name ([string]$built.bundle.lifecycle.name) -AppPath ([string]$built.live_path)
    Assert-RAPPEq ([string]$runtimeAfterGit.tree_sha256).Trim().ToLowerInvariant() ([string]$built.actual_live_tree).Trim().ToLowerInvariant() 'root git metadata changed runtime baseline'
'@.Replace("`r`n","`n")
$newVcs=@'
    # Recovery closure is durable evidence. Do not add VCS metadata or any other bytes
    # after closure merely to exercise backup copying; generic pre-apply already proves
    # byte-exact .git preservation. Snapshot the unchanged recovery-closed live tree.
    $rawLive=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$built.live_path)
'@.Replace("`r`n","`n")
$oldAssert=@'
    Assert-RAPPTrue (Test-Path -LiteralPath ([string]$r.result.app_backup_path) -PathType Container) 'valid app rollback backup missing';Assert-RAPPTrue (Test-Path -LiteralPath ([string]$r.result.persistence_backup_path) -PathType Container) 'valid persistence backup missing';Assert-RAPPTrue (Test-Path -LiteralPath (Join-Path ([string]$r.result.app_backup_path) '.git\config') -PathType Leaf) 'valid rollback backup omitted root git provenance'
'@.Replace("`r`n","`n")
$newAssert=@'
    Assert-RAPPTrue (Test-Path -LiteralPath ([string]$r.result.app_backup_path) -PathType Container) 'valid app rollback backup missing';Assert-RAPPTrue (Test-Path -LiteralPath ([string]$r.result.persistence_backup_path) -PathType Container) 'valid persistence backup missing'
'@.Replace("`r`n","`n")

function Replace-RAPPExactOnceV010([string]$Input,[string]$Old,[string]$New,[string]$Label){
    $first=$Input.IndexOf($Old,[StringComparison]::Ordinal)
    if($first -lt 0){throw "r4 patch target missing: $Label"}
    if($Input.IndexOf($Old,$first+$Old.Length,[StringComparison]::Ordinal) -ge 0){throw "r4 patch target not unique: $Label"}
    return $Input.Substring(0,$first)+$New+$Input.Substring($first+$Old.Length)
}

$patched=Replace-RAPPExactOnceV010 -Input $text -Old $oldVcs -New $newVcs -Label 'post-recovery-vcs-mutation'
$patched=Replace-RAPPExactOnceV010 -Input $patched -Old $oldAssert -New $newAssert -Label 'root-git-valid-assertion'
if($patched.IndexOf("[IO.Directory]::CreateDirectory(`$git)",[StringComparison]::Ordinal) -ge 0){throw 'r4 recovery-closed live mutation survived patch'}
if($patched.IndexOf('valid rollback backup raw tree',[StringComparison]::Ordinal) -lt 0 -or $patched.IndexOf('pre-apply backup mutated byte-real live source',[StringComparison]::Ordinal) -lt 0){throw 'r4 raw byte-real backup assertions missing'}

$temp=Join-Path $PSScriptRoot ('test_custom_app_production_recovery_aware_permit_pre_apply_preparation_r4_generated_'+[Guid]::NewGuid().ToString('N')+'.ps1')
try{
    [IO.File]::WriteAllText($temp,$patched,[Text.UTF8Encoding]::new($false))
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $temp
    if($LASTEXITCODE){throw "r4 generated recovery-aware pre-apply matrix failed exit=$LASTEXITCODE"}
} finally {
    if(Test-Path -LiteralPath $temp){[IO.File]::Delete($temp)}
}
Write-Host 'CUSTOM_APP_PRODUCTION_RECOVERY_AWARE_PERMIT_PRE_APPLY_R4_PATCH_HARNESS_PASS recovery_closed_live_bytes_unchanged=true'
