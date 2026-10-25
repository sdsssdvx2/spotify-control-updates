Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$OverlayRoot = Split-Path -Parent $Here
$ApplyScript = Join-Path $OverlayRoot 'apply-overlay.ps1'
$LoaderSource = Join-Path $OverlayRoot 'lazy-custom-app-loader.js'

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
}

function Write-Utf8NoBom([string]$Path, [string]$Text) {
    $bytes = (New-Object Text.UTF8Encoding($false)).GetBytes($Text)
    [IO.File]::WriteAllBytes($Path, $bytes)
}

function New-Fixture([string]$Root, [string]$IndexText, [object]$Provenance) {
    $xpui = Join-Path $Root 'xpui'
    $ext = Join-Path $xpui 'extensions'
    $state = Join-Path $Root 'state'
    New-Item -ItemType Directory -Force -Path $ext, $state | Out-Null
    $index = Join-Path $xpui 'index.html'
    $prov = Join-Path $Root 'provenance.json'
    Write-Utf8NoBom $index $IndexText
    Write-Utf8NoBom $prov ($Provenance | ConvertTo-Json -Depth 12)
    return [pscustomobject]@{ Xpui = $xpui; Index = $index; Provenance = $prov; State = $state }
}

function Invoke-OverlayJson([string]$Mode, [object]$Fixture) {
    $lines = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ApplyScript -Mode $Mode -XpuiRoot $Fixture.Xpui -ProvenancePath $Fixture.Provenance -StateRoot $Fixture.State 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Overlay $Mode failed: $($lines -join [Environment]::NewLine)" }
    return (($lines -join [Environment]::NewLine) | ConvertFrom-Json)
}

$exactProvenance = [ordered]@{
    schema = 1
    targets = [ordered]@{
        'better-local-files' = [ordered]@{ trust = 'exact-local-tree'; trusted_revision = 'bf467fab93e6c1f8b8d4189dc1054bd1cafb3f3a'; source = 'Pithaya/spicetify-apps-dist' }
        'playlist-maker' = [ordered]@{ trust = 'exact-local-tree'; trusted_revision = '9fd89fb40a53e4cfbf0953d34f806f4a8a36fc64'; source = 'Pithaya/spicetify-apps-dist' }
    }
}

$baseIndex = @'
<!doctype html>
<html><head>
<script src="extensions/sc-cover-ambience.js"></script>
<script data-protected="ivLyrics" src="extensions/ivLyrics/extension.js"></script>
<script data-x="1" src="./extensions/better-local-files/extension.js"></script>
<script defer src='extensions/playlist-maker/extension.js'></script>
<link rel="stylesheet" href="user.css">
<script src="extensions/tagify/extension.js"></script>
<script src="extensions/splitify/extension.js"></script>
<script src="extensions/marketplace/extension.js"></script>
</head><body></body></html>
'@

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('spotify-control-overlay-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
try {
    # Exact provenance: audit, apply, idempotence, protected-hook preservation, exact restore.
    $f1 = New-Fixture (Join-Path $tempRoot 'exact') $baseIndex $exactProvenance
    $originalBytes = [IO.File]::ReadAllBytes($f1.Index)
    $audit = Invoke-OverlayJson 'Audit' $f1
    Assert-True ($audit.status -eq 'audited') 'Audit status'
    Assert-True ((@($audit.targets | Where-Object { $_.eligible })).Count -eq 2) 'Both exact targets must be eligible'

    $apply = Invoke-OverlayJson 'Apply' $f1
    Assert-True ($apply.status -eq 'applied') 'Apply status'
    Assert-True ((@($apply.optimized_targets)).Count -eq 2) 'Two targets optimized'
    $patched = [IO.File]::ReadAllText($f1.Index)
    Assert-True ($patched.Contains('spotify-control-performance-overlay:lazy:better-local-files')) 'Better Local Files marker inserted'
    Assert-True ($patched.Contains('spotify-control-performance-overlay:lazy:playlist-maker')) 'Playlist Maker marker inserted'
    Assert-True ($patched.Contains('extensions/sc-cover-ambience.js')) 'SC Cover Ambience preserved'
    Assert-True ($patched.Contains('extensions/ivLyrics/extension.js')) 'ivLyrics preserved'
    Assert-True ($patched.Contains('extensions/tagify/extension.js')) 'Tagify preserved'
    Assert-True ($patched.Contains('extensions/splitify/extension.js')) 'Splitify preserved'
    Assert-True ($patched.Contains('extensions/marketplace/extension.js')) 'Marketplace preserved'
    Assert-True ($patched.Contains('href="user.css"')) 'user.css untouched'
    Assert-True ($patched.Contains('spotify-control-performance-overlay.v010.js')) 'Loader tag inserted'
    $loaderDest = Join-Path $f1.Xpui 'extensions\spotify-control-performance-overlay.v010.js'
    Assert-True (Test-Path -LiteralPath $loaderDest) 'Loader file created'
    Assert-True ((Get-FileHash $loaderDest -Algorithm SHA256).Hash -eq (Get-FileHash $LoaderSource -Algorithm SHA256).Hash) 'Loader exact copy'

    $patchedHash = (Get-FileHash $f1.Index -Algorithm SHA256).Hash
    $applyAgain = Invoke-OverlayJson 'Apply' $f1
    Assert-True ($applyAgain.status -eq 'already-applied') 'Second apply is idempotent'
    Assert-True ((Get-FileHash $f1.Index -Algorithm SHA256).Hash -eq $patchedHash) 'Idempotent apply leaves bytes unchanged'

    $restore = Invoke-OverlayJson 'Restore' $f1
    Assert-True ($restore.status -eq 'restored') 'Restore status'
    Assert-True (-not (Test-Path -LiteralPath $loaderDest)) 'Loader removed on exact restore'
    $restoredBytes = [IO.File]::ReadAllBytes($f1.Index)
    Assert-True ($restoredBytes.Length -eq $originalBytes.Length) 'Restored length exact'
    Assert-True (([BitConverter]::ToString($restoredBytes)) -eq ([BitConverter]::ToString($originalBytes))) 'Restored bytes exact'

    # Revision changed: optimize only the still-exact target, never block upstream content.
    $mixed = ($exactProvenance | ConvertTo-Json -Depth 12 | ConvertFrom-Json)
    $mixed.targets.'playlist-maker'.trusted_revision = 'new-upstream-revision'
    $f2 = New-Fixture (Join-Path $tempRoot 'mixed') $baseIndex $mixed
    $mixedApply = Invoke-OverlayJson 'Apply' $f2
    Assert-True ($mixedApply.status -eq 'applied') 'Mixed provenance still applies safe target'
    Assert-True ((@($mixedApply.optimized_targets)).Count -eq 1 -and $mixedApply.optimized_targets[0] -eq 'better-local-files') 'Changed Playlist Maker revision skipped'
    $mixedText = [IO.File]::ReadAllText($f2.Index)
    Assert-True ($mixedText.Contains('spotify-control-performance-overlay:lazy:better-local-files')) 'Exact target optimized'
    Assert-True ($mixedText.Contains("src='extensions/playlist-maker/extension.js'")) 'Changed target remains eager/original'
    Invoke-OverlayJson 'Restore' $f2 | Out-Null

    # No exact local provenance: pure no-op.
    $none = [ordered]@{ schema = 1; targets = [ordered]@{} }
    $f3 = New-Fixture (Join-Path $tempRoot 'none') $baseIndex $none
    $beforeNoop = [IO.File]::ReadAllBytes($f3.Index)
    $noop = Invoke-OverlayJson 'Apply' $f3
    Assert-True ($noop.status -eq 'no-op') 'Missing provenance is no-op'
    Assert-True (-not (Test-Path (Join-Path $f3.Xpui 'extensions\spotify-control-performance-overlay.v010.js'))) 'No loader on no-op'
    Assert-True (([BitConverter]::ToString([IO.File]::ReadAllBytes($f3.Index))) -eq ([BitConverter]::ToString($beforeNoop))) 'No-op index byte exact'

    # Ambiguous duplicate hook: skip only ambiguous target.
    $duplicateIndex = $baseIndex.Replace('</head>', '<script src="extensions/better-local-files/extension.js"></script></head>')
    $f4 = New-Fixture (Join-Path $tempRoot 'duplicate') $duplicateIndex $exactProvenance
    $dup = Invoke-OverlayJson 'Apply' $f4
    Assert-True ($dup.status -eq 'applied') 'Other exact target still applies when one hook is ambiguous'
    Assert-True ((@($dup.optimized_targets)).Count -eq 1 -and $dup.optimized_targets[0] -eq 'playlist-maker') 'Ambiguous Better Local Files skipped'
    Invoke-OverlayJson 'Restore' $f4 | Out-Null

    # Reserved loader conflict: never overwrite unknown file, never touch index.
    $f5 = New-Fixture (Join-Path $tempRoot 'loader-conflict') $baseIndex $exactProvenance
    $conflictLoader = Join-Path $f5.Xpui 'extensions\spotify-control-performance-overlay.v010.js'
    Write-Utf8NoBom $conflictLoader 'unknown-owned-file'
    $conflictBefore = [IO.File]::ReadAllBytes($f5.Index)
    $conflict = Invoke-OverlayJson 'Apply' $f5
    Assert-True ($conflict.status -eq 'no-op' -and $conflict.reason -eq 'reserved-loader-path-conflict') 'Unknown loader path conflict is no-op'
    Assert-True (([BitConverter]::ToString([IO.File]::ReadAllBytes($f5.Index))) -eq ([BitConverter]::ToString($conflictBefore))) 'Loader conflict leaves index exact'

    # Upstream rewrites index after an overlay: stale state must not restore/clobber old bytes.
    $f6 = New-Fixture (Join-Path $tempRoot 'upstream-rewrite') $baseIndex $exactProvenance
    Invoke-OverlayJson 'Apply' $f6 | Out-Null
    $newUpstream = $baseIndex.Replace('<body>', '<!-- new-upstream-index -->`n<body>')
    Write-Utf8NoBom $f6.Index $newUpstream
    $reapply = Invoke-OverlayJson 'Apply' $f6
    Assert-True ($reapply.status -eq 'applied') 'New upstream index re-evaluated rather than overwritten by old backup'
    $reappliedText = [IO.File]::ReadAllText($f6.Index)
    Assert-True ($reappliedText.Contains('new-upstream-index')) 'New upstream content preserved through re-evaluation'
    Invoke-OverlayJson 'Restore' $f6 | Out-Null
    Assert-True ([IO.File]::ReadAllText($f6.Index) -eq $newUpstream) 'Restore returns to newest upstream bytes, not pre-update bytes'

    # If index changes after current overlay, restore must refuse to overwrite it.
    $f7 = New-Fixture (Join-Path $tempRoot 'restore-refusal') $baseIndex $exactProvenance
    Invoke-OverlayJson 'Apply' $f7 | Out-Null
    [IO.File]::AppendAllText($f7.Index, '<!-- external-change -->', (New-Object Text.UTF8Encoding($false)))
    $restoreFailed = $false
    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ApplyScript -Mode Restore -StateRoot $f7.State 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { $restoreFailed = $true }
    } catch { $restoreFailed = $true }
    Assert-True $restoreFailed 'Restore refuses changed active index'
    Assert-True ([IO.File]::ReadAllText($f7.Index).Contains('external-change')) 'Restore refusal preserves external/newer change'

    Write-Host 'PERFORMANCE OVERLAY POWERSHELL TESTS PASS'
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
