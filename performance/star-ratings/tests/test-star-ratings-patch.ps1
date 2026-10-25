param(
    [Parameter(Mandatory=$true)][string]$FixturePath
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$Here=Split-Path -Parent $MyInvocation.MyCommand.Path
$Root=Split-Path -Parent $Here
$Engine=Join-Path $Root 'apply-star-ratings-patch.ps1'
$Target=Join-Path $Root 'target.json'
$ExpectedOriginal='198fd7c3307de8f2efc36f40df4e79846188cf35a1d5b550ed3d8ab85e8139b1'
$ExpectedTransformed='6e0d1c84408294a619d91191eec83a6d10794ef31093d31ccf1f1bd39ea8c8a3'
if((Get-Item -LiteralPath $FixturePath).Length -ne 43396 -or (Get-FileHash -LiteralPath $FixturePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $ExpectedOriginal){throw 'Fixture identity mismatch.'}

function Invoke-Engine([string]$Mode,[string]$Xpui,[string]$State){
    $raw=@(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Engine -Mode $Mode -XpuiRoot $Xpui -StateRoot $State -TargetMetadataPath $Target 2>&1)
    if($LASTEXITCODE -ne 0){throw "Engine $Mode failed exit=$LASTEXITCODE output=$($raw -join ' | ')"}
    $json=[string](@($raw | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) -join "`n")
    return ($json | ConvertFrom-Json)
}

$temp=Join-Path $env:RUNNER_TEMP ('star-ratings-patch-test-'+[Guid]::NewGuid().ToString('N'))
$xpui=Join-Path $temp 'xpui';$ext=Join-Path $xpui 'extensions';$state=Join-Path $temp 'state';$active=Join-Path $ext 'sc-star-ratings.js'
New-Item -ItemType Directory -Force -Path $ext | Out-Null
try {
    Copy-Item -LiteralPath $FixturePath -Destination $active
    $audit=Invoke-Engine 'Audit' $xpui $state
    if(-not $audit.eligible -or $audit.reason -ne 'exact-active-bytes' -or $audit.transformed_sha256 -ne $ExpectedTransformed){throw 'Eligible audit contract failed.'}

    $apply=Invoke-Engine 'Apply' $xpui $state
    if($apply.status -ne 'applied' -or (Get-FileHash $active -Algorithm SHA256).Hash.ToLowerInvariant() -ne $ExpectedTransformed){throw 'Apply contract failed.'}
    $again=Invoke-Engine 'Apply' $xpui $state
    if($again.status -ne 'already-applied'){throw 'Idempotent Apply contract failed.'}
    $restore=Invoke-Engine 'Restore' $xpui $state
    if($restore.status -ne 'restored-exact-original' -or (Get-FileHash $active -Algorithm SHA256).Hash.ToLowerInvariant() -ne $ExpectedOriginal){throw 'Exact Restore contract failed.'}

    [IO.File]::WriteAllText($active,'newer unknown Star Ratings bytes',(New-Object Text.UTF8Encoding($false)))
    $unknownBefore=(Get-FileHash $active -Algorithm SHA256).Hash.ToLowerInvariant()
    $skip=Invoke-Engine 'Apply' $xpui $state
    if($skip.status -ne 'skipped' -or $skip.reason -ne 'active-bytes-not-exact-pinned-upstream'){throw 'Unknown-upstream Apply must fail open.'}
    if((Get-FileHash $active -Algorithm SHA256).Hash.ToLowerInvariant() -ne $unknownBefore){throw 'Unknown upstream bytes were mutated.'}

    Copy-Item -LiteralPath $FixturePath -Destination $active -Force
    $apply=Invoke-Engine 'Apply' $xpui $state
    if($apply.status -ne 'applied'){throw 'Second exact Apply failed.'}
    [IO.File]::WriteAllText($active,'newer bytes after our transformed version',(New-Object Text.UTF8Encoding($false)))
    $conflictBefore=(Get-FileHash $active -Algorithm SHA256).Hash.ToLowerInvariant()
    $restoreConflict=Invoke-Engine 'Restore' $xpui $state
    if($restoreConflict.status -ne 'conflict-newer-or-unknown-active-bytes'){throw 'Restore conflict was not preserved.'}
    if((Get-FileHash $active -Algorithm SHA256).Hash.ToLowerInvariant() -ne $conflictBefore){throw 'Restore overwrote newer/unknown bytes.'}

    $engineText=Get-Content -LiteralPath $Engine -Raw
    foreach($forbidden in @('popupLyrics','ivLyrics','tagify','splitify','sc-cover-ambience','spicetify apply','spicetify backup','spicetify restore','config-xpui.ini','\Browser\','\Default\')){
        if($engineText.IndexOf($forbidden,[StringComparison]::OrdinalIgnoreCase) -ge 0){throw "Forbidden mutation/target surface in Star Ratings engine: $forbidden"}
    }
    Write-Host 'STAR_RATINGS_PATCH_REGRESSION_PASS'
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
