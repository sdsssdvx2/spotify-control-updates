param(
    [Parameter(Mandatory=$true)][string]$PopupFixture,
    [Parameter(Mandatory=$true)][string]$StarFixture
)

Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$Root=Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$Patch=Join-Path $Root 'apply-direct-extension-patches.ps1'
$Targets=Join-Path $Root 'targets.json'
$Temp=Join-Path $env:RUNNER_TEMP ('direct-extension-patch-test-'+[Guid]::NewGuid().ToString('N'))
$Xpui=Join-Path $Temp 'xpui';$Ext=Join-Path $Xpui 'extensions';$State=Join-Path $Temp 'state'
New-Item -ItemType Directory -Force -Path $Ext|Out-Null
$popup=Join-Path $Ext 'popupLyrics.js';$star=Join-Path $Ext 'sc-star-ratings.js'
Copy-Item -LiteralPath $PopupFixture -Destination $popup
Copy-Item -LiteralPath $StarFixture -Destination $star
$popupOriginal=(Get-FileHash $popup -Algorithm SHA256).Hash.ToLowerInvariant()
$starOriginal=(Get-FileHash $star -Algorithm SHA256).Hash.ToLowerInvariant()
$fixturePopupBefore=(Get-FileHash $PopupFixture -Algorithm SHA256).Hash.ToLowerInvariant()
$fixtureStarBefore=(Get-FileHash $StarFixture -Algorithm SHA256).Hash.ToLowerInvariant()

function Invoke-Patch([string]$Mode,[string]$Metadata=$Targets,[switch]$AllowConflict) {
    $raw=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Patch -Mode $Mode -XpuiRoot $Xpui -StateRoot $State -TargetMetadataPath $Metadata 2>&1
    $code=$LASTEXITCODE
    $raw|ForEach-Object{Write-Host $_}
    if(-not $AllowConflict -and $code -ne 0){throw "$Mode failed with exit $code"}
    if($AllowConflict -and $code -notin @(0,2)){throw "$Mode unexpected exit $code"}
    $json=@($raw|Where-Object{[string]$_ -match '^\s*\{'})|Select-Object -Last 1
    if(-not $json){throw "$Mode emitted no JSON"}
    return [pscustomobject]@{Code=$code;Value=($json|ConvertFrom-Json)}
}

try {
    $audit=Invoke-Patch Audit
    if(@($audit.Value.targets|Where-Object eligible -eq $true).Count -ne 2){throw 'Audit did not prove both exact fixtures.'}

    $apply=Invoke-Patch Apply
    if(@($apply.Value.targets|Where-Object status -eq 'applied').Count -ne 2){throw 'Apply did not patch both exact fixtures.'}
    $popupPatched=(Get-FileHash $popup -Algorithm SHA256).Hash.ToLowerInvariant()
    $starPatched=(Get-FileHash $star -Algorithm SHA256).Hash.ToLowerInvariant()
    if($popupPatched -eq $popupOriginal -or $starPatched -eq $starOriginal){throw 'Patched identity did not change.'}
    if((Get-FileHash $PopupFixture -Algorithm SHA256).Hash.ToLowerInvariant() -ne $fixturePopupBefore -or (Get-FileHash $StarFixture -Algorithm SHA256).Hash.ToLowerInvariant() -ne $fixtureStarBefore){throw 'Immutable source fixture changed.'}

    node --check $popup
    if($LASTEXITCODE -ne 0){throw 'Patched PopupLyrics failed Node parse.'}
    node --check $star
    if($LASTEXITCODE -ne 0){throw 'Patched Star Ratings failed Node parse.'}

    $popupText=Get-Content $popup -Raw
    foreach($needle in @('if (e.target.hidden && lyricVideoIsOpen) {','if (document.hidden && !workerIsRunning) {','lyricVideoIsOpen = false;','worker.postMessage("popup-lyric-stop-update");')){
        if($popupText.IndexOf($needle,[StringComparison]::Ordinal) -lt 0){throw "Popup patch marker missing: $needle"}
    }
    if($popupText.IndexOf('if (e.target.hidden) {',[StringComparison]::Ordinal) -ge 0){throw 'Ungated PopupLyrics hidden worker start remains.'}
    $starText=Get-Content $star -Raw
    foreach($needle in @('c.__spotifyControlPerfTimer=setTimeout(()=>De(),75)','a.__spotifyControlPerfTimer=setTimeout(()=>{Be(e)},75)','f[e]!==y[e]&&(t=!0)','(l=document.querySelector("main"))&&l!==a&&')){
        if($starText.IndexOf($needle,[StringComparison]::Ordinal) -lt 0){throw "Star Ratings patch marker missing: $needle"}
    }
    foreach($forbidden in @('c=new MutationObserver(()=>{De()})','var a=new MutationObserver(async()=>{await Be(e)})')){
        if($starText.IndexOf($forbidden,[StringComparison]::Ordinal) -ge 0){throw "Unoptimized Star Ratings anchor remains: $forbidden"}
    }

    $again=Invoke-Patch Apply
    if(@($again.Value.targets|Where-Object status -eq 'already-applied').Count -ne 2){throw 'Idempotent Apply did not report already-applied.'}

    $restore=Invoke-Patch Restore
    if($restore.Value.status -ne 'restored'){throw 'Exact restore did not complete.'}
    if((Get-FileHash $popup -Algorithm SHA256).Hash.ToLowerInvariant() -ne $popupOriginal){throw 'Popup exact restore mismatch.'}
    if((Get-FileHash $star -Algorithm SHA256).Hash.ToLowerInvariant() -ne $starOriginal){throw 'Star exact restore mismatch.'}

    # Unknown/new upstream bytes must be preserved and skipped, while another exact target may still apply.
    Add-Content -LiteralPath $star -Value '// synthetic-future-upstream' -Encoding UTF8
    $futureStar=[IO.File]::ReadAllBytes($star)
    $mixed=Invoke-Patch Apply
    $popupRow=@($mixed.Value.targets|Where-Object id -eq 'popup-lyrics-worker-gate')[0]
    $starRow=@($mixed.Value.targets|Where-Object id -eq 'star-ratings-observer-debounce')[0]
    if($popupRow.status -ne 'applied'){throw 'Exact Popup target should still apply independently.'}
    if($starRow.status -ne 'skipped' -or $starRow.reason -ne 'active-bytes-not-exact-pinned-upstream'){throw 'Unknown Star upstream was not fail-open skipped.'}
    if(-not ([Linq.Enumerable]::SequenceEqual([byte[]]$futureStar,[byte[]][IO.File]::ReadAllBytes($star)))){throw 'Skipped future Star bytes were changed.'}

    # Restore must not overwrite a newer/unknown active file.
    [IO.File]::WriteAllBytes($popup,(New-Object Text.UTF8Encoding($false)).GetBytes('// synthetic-new-popup-upstream'))
    $futurePopup=[IO.File]::ReadAllBytes($popup)
    $conflict=Invoke-Patch Restore -AllowConflict
    if($conflict.Code -ne 2 -or $conflict.Value.status -ne 'restore-conflict-preserved'){throw 'Restore conflict was not reported fail-closed.'}
    if(-not ([Linq.Enumerable]::SequenceEqual([byte[]]$futurePopup,[byte[]][IO.File]::ReadAllBytes($popup)))){throw 'Restore overwrote newer Popup bytes.'}
    if(-not ([Linq.Enumerable]::SequenceEqual([byte[]]$futureStar,[byte[]][IO.File]::ReadAllBytes($star)))){throw 'Restore changed skipped future Star bytes.'}

    Write-Host 'DIRECT_EXTENSION_PATCH_REGRESSION_PASS'
} finally {
    Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue
}
