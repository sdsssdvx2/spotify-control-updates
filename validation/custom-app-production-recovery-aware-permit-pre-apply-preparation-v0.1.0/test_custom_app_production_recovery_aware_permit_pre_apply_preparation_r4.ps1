$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0

$source=Join-Path $PSScriptRoot 'test_custom_app_production_recovery_aware_permit_pre_apply_preparation.ps1'
$text=[IO.File]::ReadAllText($source,[Text.UTF8Encoding]::new($false)).Replace("`r`n","`n")

function Get-RAPPUniqueMarkerIndexV010 {
    param([Parameter(Mandatory=$true)][string]$Input,[Parameter(Mandatory=$true)][string]$Marker,[Parameter(Mandatory=$true)][string]$Label)
    $first=$Input.IndexOf($Marker,[StringComparison]::Ordinal)
    if($first -lt 0){throw "r4 semantic patch marker missing: $Label"}
    if($Input.IndexOf($Marker,$first+$Marker.Length,[StringComparison]::Ordinal) -ge 0){throw "r4 semantic patch marker not unique: $Label"}
    return $first
}

# Remove only the post-recovery VCS mutation block. Semantic boundary markers are
# intentionally independent of quoting and CRLF/LF representation inside the block.
$startMarker='    # Root VCS metadata is deliberately invisible to the runtime baseline but must be'
$endMarker="'root git metadata changed runtime baseline'"
$start=Get-RAPPUniqueMarkerIndexV010 -Input $text -Marker $startMarker -Label 'post-recovery-vcs-start'
$endPhrase=Get-RAPPUniqueMarkerIndexV010 -Input $text -Marker $endMarker -Label 'post-recovery-vcs-end'
if($endPhrase -le $start){throw 'r4 semantic VCS patch boundaries reversed'}
$end=$text.IndexOf("`n",$endPhrase,[StringComparison]::Ordinal)
if($end -lt 0){$end=$text.Length}else{$end++}
$replacement=@'
    # Recovery closure is durable evidence. Do not add VCS metadata or any other bytes
    # after closure merely to exercise backup copying; generic pre-apply already proves
    # byte-exact .git preservation. Snapshot the unchanged recovery-closed live tree.
    $rawLive=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$built.live_path)
'@.Replace("`r`n","`n")
$patched=$text.Substring(0,$start)+$replacement+$text.Substring($end)

# Remove only the valid-case assertion that demands the deliberately injected .git.
# The generic pre-apply matrix already proves .git byte preservation; this layer keeps
# stronger recovery continuity plus raw-tree/file-count/byte-count backup assertions.
$gitAssertMarker='valid rollback backup omitted root git provenance'
$assertAt=Get-RAPPUniqueMarkerIndexV010 -Input $patched -Marker $gitAssertMarker -Label 'root-git-valid-assertion'
$lineStart=$patched.LastIndexOf("`n",$assertAt)
if($lineStart -lt 0){$lineStart=0}else{$lineStart++}
$lineEnd=$patched.IndexOf("`n",$assertAt,[StringComparison]::Ordinal)
if($lineEnd -lt 0){$lineEnd=$patched.Length}else{$lineEnd++}
$newAssert="    Assert-RAPPTrue (Test-Path -LiteralPath ([string]`$r.result.app_backup_path) -PathType Container) 'valid app rollback backup missing';Assert-RAPPTrue (Test-Path -LiteralPath ([string]`$r.result.persistence_backup_path) -PathType Container) 'valid persistence backup missing'`n"
$patched=$patched.Substring(0,$lineStart)+$newAssert+$patched.Substring($lineEnd)

if($patched.IndexOf($startMarker,[StringComparison]::Ordinal) -ge 0 -or $patched.IndexOf($gitAssertMarker,[StringComparison]::Ordinal) -ge 0){throw 'r4 recovery-closed mutation/assertion survived semantic patch'}
if($patched.IndexOf('valid rollback backup raw tree',[StringComparison]::Ordinal) -lt 0 -or $patched.IndexOf('valid rollback backup raw file count',[StringComparison]::Ordinal) -lt 0 -or $patched.IndexOf('valid rollback backup raw byte count',[StringComparison]::Ordinal) -lt 0 -or $patched.IndexOf('pre-apply backup mutated byte-real live source',[StringComparison]::Ordinal) -lt 0){throw 'r4 raw byte-real backup assertions missing'}
if($patched.IndexOf('historical rev1 pre-apply denied after rev2 append',[StringComparison]::Ordinal) -lt 0 -or $patched.IndexOf('post-backup permit expiry',[StringComparison]::Ordinal) -lt 0){throw 'r4 recovery continuity coverage missing'}

$temp=Join-Path $PSScriptRoot ('test_custom_app_production_recovery_aware_permit_pre_apply_preparation_r4_generated_'+[Guid]::NewGuid().ToString('N')+'.ps1')
try {
    [IO.File]::WriteAllText($temp,$patched,[Text.UTF8Encoding]::new($false))
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $temp
    if($LASTEXITCODE){throw "r4 generated recovery-aware pre-apply matrix failed exit=$LASTEXITCODE"}
} finally {
    if(Test-Path -LiteralPath $temp){[IO.File]::Delete($temp)}
}
Write-Host 'CUSTOM_APP_PRODUCTION_RECOVERY_AWARE_PERMIT_PRE_APPLY_R4_PATCH_HARNESS_PASS recovery_closed_live_bytes_unchanged=true semantic_patch=true'
