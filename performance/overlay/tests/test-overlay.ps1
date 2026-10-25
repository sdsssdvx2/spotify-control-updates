Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$OverlayRoot = Split-Path -Parent $Here
$ApplyScript = Join-Path $OverlayRoot 'apply-overlay.ps1'
$CollectorScript = Join-Path $OverlayRoot 'collect-active-provenance.ps1'
$LoaderSource = Join-Path $OverlayRoot 'lazy-custom-app-loader.js'
$script:SyntheticTargetsPath = $null
$script:BetterLocalBytes = $null
$script:PlaylistMakerBytes = $null

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "ASSERT FAILED: $Message" }
}

function ConvertTo-Utf8Bytes([string]$Text) {
    return (New-Object Text.UTF8Encoding($false)).GetBytes($Text)
}

function Get-BytesSha256([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Write-Utf8NoBom([string]$Path, [string]$Text) {
    [IO.File]::WriteAllBytes($Path, (ConvertTo-Utf8Bytes $Text))
}

function Get-FileSha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function New-Fixture([string]$Root, [string]$IndexText, [object]$Provenance = $null) {
    $xpui = Join-Path $Root 'xpui'
    $extensions = Join-Path $xpui 'extensions'
    $betterLocalDir = Join-Path $extensions 'better-local-files'
    $playlistMakerDir = Join-Path $extensions 'playlist-maker'
    $state = Join-Path $Root 'state'
    New-Item -ItemType Directory -Force -Path $betterLocalDir, $playlistMakerDir, $state | Out-Null

    $index = Join-Path $xpui 'index.html'
    $prov = Join-Path $Root 'provenance.json'
    $betterLocalPath = Join-Path $betterLocalDir 'extension.js'
    $playlistMakerPath = Join-Path $playlistMakerDir 'extension.js'

    Write-Utf8NoBom $index $IndexText
    [IO.File]::WriteAllBytes($betterLocalPath, $script:BetterLocalBytes)
    [IO.File]::WriteAllBytes($playlistMakerPath, $script:PlaylistMakerBytes)
    if ($null -ne $Provenance) {
        Write-Utf8NoBom $prov ($Provenance | ConvertTo-Json -Depth 16)
    }

    return [pscustomobject]@{
        Root = $Root
        Xpui = $xpui
        Index = $index
        Provenance = $prov
        State = $state
        BetterLocalExtension = $betterLocalPath
        PlaylistMakerExtension = $playlistMakerPath
    }
}

function Invoke-CollectorJson([object]$Fixture, [string]$OutputPath = $null) {
    $args = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $CollectorScript,
        '-XpuiRoot', $Fixture.Xpui,
        '-TargetMetadataPath', $script:SyntheticTargetsPath
    )
    if ($OutputPath) { $args += @('-OutputPath', $OutputPath) }
    $lines = & powershell.exe @args 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Collector failed: $($lines -join [Environment]::NewLine)" }
    return (($lines -join [Environment]::NewLine) | ConvertFrom-Json)
}

function Set-ExactProvenance([object]$Fixture) {
    $report = Invoke-CollectorJson $Fixture $Fixture.Provenance
    return $report
}

function Invoke-OverlayJson([string]$Mode, [object]$Fixture) {
    $args = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ApplyScript,
        '-Mode', $Mode,
        '-StateRoot', $Fixture.State,
        '-TargetMetadataPath', $script:SyntheticTargetsPath
    )
    if ($Mode -ne 'Restore') {
        $args += @('-XpuiRoot', $Fixture.Xpui, '-ProvenancePath', $Fixture.Provenance)
    }
    $lines = & powershell.exe @args 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Overlay $Mode failed: $($lines -join [Environment]::NewLine)" }
    return (($lines -join [Environment]::NewLine) | ConvertFrom-Json)
}

function Assert-PayloadUnchanged([object]$Fixture, [string]$BetterLocalSha, [string]$PlaylistMakerSha, [string]$Context) {
    Assert-True ((Get-FileSha256 $Fixture.BetterLocalExtension) -eq $BetterLocalSha) "$Context Better Local Files payload unchanged"
    Assert-True ((Get-FileSha256 $Fixture.PlaylistMakerExtension) -eq $PlaylistMakerSha) "$Context Playlist Maker payload unchanged"
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
    $script:BetterLocalBytes = ConvertTo-Utf8Bytes 'window.localTracksService=window.localTracksService||{};'
    $script:PlaylistMakerBytes = ConvertTo-Utf8Bytes 'window.__playlistMakerSynthetic=true;'
    $betterLocalSha = Get-BytesSha256 $script:BetterLocalBytes
    $playlistMakerSha = Get-BytesSha256 $script:PlaylistMakerBytes
    $script:SyntheticTargetsPath = Join-Path $tempRoot 'targets.json'

    $syntheticTargets = [ordered]@{
        schema = 1
        source_repository = 'Pithaya/spicetify-apps'
        source_commit = 'synthetic-source-commit'
        distribution_repository = 'Pithaya/spicetify-apps-dist'
        targets = @(
            [ordered]@{
                id = 'better-local-files'
                dist_revision = 'bf467fab93e6c1f8b8d4189dc1054bd1cafb3f3a'
                extension_path = 'extensions/better-local-files/extension.js'
                extension_size = $script:BetterLocalBytes.Length
                extension_sha256 = $betterLocalSha
                route_prefixes = @('/better-local-files')
                readiness = [ordered]@{ kind = 'global-property'; property = 'localTracksService'; timeoutMs = 10000 }
            },
            [ordered]@{
                id = 'playlist-maker'
                dist_revision = '9fd89fb40a53e4cfbf0953d34f806f4a8a36fc64'
                extension_path = 'extensions/playlist-maker/extension.js'
                extension_size = $script:PlaylistMakerBytes.Length
                extension_sha256 = $playlistMakerSha
                route_prefixes = @('/playlist-maker')
                readiness = [ordered]@{ kind = 'playlist-maker-migrations'; timeoutMs = 10000 }
            }
        )
    }
    Write-Utf8NoBom $script:SyntheticTargetsPath ($syntheticTargets | ConvertTo-Json -Depth 16)

    # Collector -> provenance -> apply: collector must be read-only and both exact active payloads must be trusted.
    $f0 = New-Fixture (Join-Path $tempRoot 'collector') $baseIndex
    $collectorIndexSha = Get-FileSha256 $f0.Index
    $collectorBetterSha = Get-FileSha256 $f0.BetterLocalExtension
    $collectorPlaylistSha = Get-FileSha256 $f0.PlaylistMakerExtension
    $collector = Set-ExactProvenance $f0
    Assert-True ($collector.mode -eq 'read-only-active-xpui-extension-provenance') 'Collector mode is read-only provenance'
    Assert-True ($collector.targets.'better-local-files'.trust -eq 'exact-active-extension') 'Collector trusts exact Better Local Files bytes'
    Assert-True ($collector.targets.'playlist-maker'.trust -eq 'exact-active-extension') 'Collector trusts exact Playlist Maker bytes'
    Assert-True ($collector.targets.'better-local-files'.observed_sha256 -eq $betterLocalSha) 'Collector Better Local Files SHA exact'
    Assert-True ($collector.targets.'playlist-maker'.observed_sha256 -eq $playlistMakerSha) 'Collector Playlist Maker SHA exact'
    Assert-True ((Get-FileSha256 $f0.Index) -eq $collectorIndexSha) 'Collector leaves index byte-identical'
    Assert-PayloadUnchanged $f0 $collectorBetterSha $collectorPlaylistSha 'Collector'

    # Exact provenance: audit, apply, idempotence, protected-hook preservation, payload immutability, exact restore.
    $f1 = New-Fixture (Join-Path $tempRoot 'exact') $baseIndex
    Set-ExactProvenance $f1 | Out-Null
    $originalBytes = [IO.File]::ReadAllBytes($f1.Index)
    $payloadBetterBefore = Get-FileSha256 $f1.BetterLocalExtension
    $payloadPlaylistBefore = Get-FileSha256 $f1.PlaylistMakerExtension
    $audit = Invoke-OverlayJson 'Audit' $f1
    Assert-True ($audit.status -eq 'audited') 'Audit status'
    Assert-True ((@($audit.targets | Where-Object { $_.eligible })).Count -eq 2) 'Both exact active targets must be eligible'

    $apply = Invoke-OverlayJson 'Apply' $f1
    Assert-True ($apply.status -eq 'applied') 'Apply status'
    Assert-True ((@($apply.optimized_targets)).Count -eq 2) 'Two targets optimized'
    Assert-PayloadUnchanged $f1 $payloadBetterBefore $payloadPlaylistBefore 'Apply'
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
    Assert-True ((Get-FileHash $f1.Index -Algorithm SHA256).Hash -eq $patchedHash) 'Idempotent apply leaves index bytes unchanged'
    Assert-PayloadUnchanged $f1 $payloadBetterBefore $payloadPlaylistBefore 'Idempotent apply'

    $restore = Invoke-OverlayJson 'Restore' $f1
    Assert-True ($restore.status -eq 'restored') 'Restore status'
    Assert-True (-not (Test-Path -LiteralPath $loaderDest)) 'Loader removed on exact restore'
    $restoredBytes = [IO.File]::ReadAllBytes($f1.Index)
    Assert-True ($restoredBytes.Length -eq $originalBytes.Length) 'Restored length exact'
    Assert-True (([BitConverter]::ToString($restoredBytes)) -eq ([BitConverter]::ToString($originalBytes))) 'Restored index bytes exact'
    Assert-PayloadUnchanged $f1 $payloadBetterBefore $payloadPlaylistBefore 'Restore'

    # Revision changed: optimize only the still-exact target, never block upstream content.
    $f2 = New-Fixture (Join-Path $tempRoot 'mixed') $baseIndex
    $mixedReport = Set-ExactProvenance $f2
    $mixedReport.targets.'playlist-maker'.trusted_revision = 'new-upstream-revision'
    Write-Utf8NoBom $f2.Provenance ($mixedReport | ConvertTo-Json -Depth 16)
    $mixedApply = Invoke-OverlayJson 'Apply' $f2
    Assert-True ($mixedApply.status -eq 'applied') 'Mixed provenance still applies safe target'
    Assert-True ((@($mixedApply.optimized_targets)).Count -eq 1 -and @($mixedApply.optimized_targets)[0] -eq 'better-local-files') 'Changed Playlist Maker revision skipped'
    $mixedText = [IO.File]::ReadAllText($f2.Index)
    Assert-True ($mixedText.Contains('spotify-control-performance-overlay:lazy:better-local-files')) 'Exact target optimized'
    Assert-True ($mixedText.Contains("src='extensions/playlist-maker/extension.js'")) 'Changed target remains eager/original'
    Invoke-OverlayJson 'Restore' $f2 | Out-Null

    # No active-extension provenance: pure no-op.
    $none = [ordered]@{ schema = 1; targets = [ordered]@{} }
    $f3 = New-Fixture (Join-Path $tempRoot 'none') $baseIndex $none
    $beforeNoop = [IO.File]::ReadAllBytes($f3.Index)
    $noop = Invoke-OverlayJson 'Apply' $f3
    Assert-True ($noop.status -eq 'no-op') 'Missing provenance is no-op'
    Assert-True (-not (Test-Path (Join-Path $f3.Xpui 'extensions\spotify-control-performance-overlay.v010.js'))) 'No loader on no-op'
    Assert-True (([BitConverter]::ToString([IO.File]::ReadAllBytes($f3.Index))) -eq ([BitConverter]::ToString($beforeNoop))) 'No-op index byte exact'

    # Ambiguous duplicate hook: skip only ambiguous target.
    $duplicateIndex = $baseIndex.Replace('</head>', '<script src="extensions/better-local-files/extension.js"></script></head>')
    $f4 = New-Fixture (Join-Path $tempRoot 'duplicate') $duplicateIndex
    Set-ExactProvenance $f4 | Out-Null
    $dup = Invoke-OverlayJson 'Apply' $f4
    Assert-True ($dup.status -eq 'applied') 'Other exact target still applies when one hook is ambiguous'
    Assert-True ((@($dup.optimized_targets)).Count -eq 1 -and @($dup.optimized_targets)[0] -eq 'playlist-maker') 'Ambiguous Better Local Files skipped'
    Invoke-OverlayJson 'Restore' $f4 | Out-Null

    # Reserved loader conflict: never overwrite unknown file, never touch index.
    $f5 = New-Fixture (Join-Path $tempRoot 'loader-conflict') $baseIndex
    Set-ExactProvenance $f5 | Out-Null
    $conflictLoader = Join-Path $f5.Xpui 'extensions\spotify-control-performance-overlay.v010.js'
    Write-Utf8NoBom $conflictLoader 'unknown-owned-file'
    $conflictBefore = [IO.File]::ReadAllBytes($f5.Index)
    $conflict = Invoke-OverlayJson 'Apply' $f5
    Assert-True ($conflict.status -eq 'no-op' -and $conflict.reason -eq 'reserved-loader-path-conflict') 'Unknown loader path conflict is no-op'
    Assert-True (([BitConverter]::ToString([IO.File]::ReadAllBytes($f5.Index))) -eq ([BitConverter]::ToString($conflictBefore))) 'Loader conflict leaves index exact'

    # Upstream rewrites index after an overlay: stale state must not restore/clobber old bytes.
    $f6 = New-Fixture (Join-Path $tempRoot 'upstream-rewrite') $baseIndex
    Set-ExactProvenance $f6 | Out-Null
    Invoke-OverlayJson 'Apply' $f6 | Out-Null
    $newUpstream = $baseIndex.Replace('<body>', "<!-- new-upstream-index -->`n<body>")
    Write-Utf8NoBom $f6.Index $newUpstream
    $reapply = Invoke-OverlayJson 'Apply' $f6
    Assert-True ($reapply.status -eq 'applied') 'New upstream index re-evaluated rather than overwritten by old backup'
    $reappliedText = [IO.File]::ReadAllText($f6.Index)
    Assert-True ($reappliedText.Contains('new-upstream-index')) 'New upstream content preserved through re-evaluation'
    Invoke-OverlayJson 'Restore' $f6 | Out-Null
    Assert-True ([IO.File]::ReadAllText($f6.Index) -eq $newUpstream) 'Restore returns to newest upstream bytes, not pre-update bytes'

    # If index changes after current overlay, restore must refuse to overwrite it.
    $f7 = New-Fixture (Join-Path $tempRoot 'restore-refusal') $baseIndex
    Set-ExactProvenance $f7 | Out-Null
    Invoke-OverlayJson 'Apply' $f7 | Out-Null
    [IO.File]::AppendAllText($f7.Index, '<!-- external-change -->', (New-Object Text.UTF8Encoding($false)))
    $restoreFailed = $false
    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ApplyScript -Mode Restore -StateRoot $f7.State -TargetMetadataPath $script:SyntheticTargetsPath 2>$null | Out-Null
        if ($LASTEXITCODE -ne 0) { $restoreFailed = $true }
    } catch { $restoreFailed = $true }
    Assert-True $restoreFailed 'Restore refuses changed active index'
    Assert-True ([IO.File]::ReadAllText($f7.Index).Contains('external-change')) 'Restore refusal preserves external/newer change'

    # TOCTOU: provenance was exact, then active Playlist Maker bytes changed without changing size.
    $f8 = New-Fixture (Join-Path $tempRoot 'toctou') $baseIndex
    Set-ExactProvenance $f8 | Out-Null
    $pmChanged = [IO.File]::ReadAllBytes($f8.PlaylistMakerExtension)
    $pmChanged[0] = $pmChanged[0] -bxor 1
    [IO.File]::WriteAllBytes($f8.PlaylistMakerExtension, $pmChanged)
    $changedPmSha = Get-FileSha256 $f8.PlaylistMakerExtension
    Assert-True ($changedPmSha -ne $playlistMakerSha) 'TOCTOU fixture changed Playlist Maker SHA'
    Assert-True ((Get-Item -LiteralPath $f8.PlaylistMakerExtension).Length -eq $script:PlaylistMakerBytes.Length) 'TOCTOU fixture preserves Playlist Maker size'
    $toctou = Invoke-OverlayJson 'Apply' $f8
    Assert-True ($toctou.status -eq 'applied') 'TOCTOU still allows unaffected exact target'
    Assert-True ((@($toctou.optimized_targets)).Count -eq 1 -and @($toctou.optimized_targets)[0] -eq 'better-local-files') 'TOCTOU changed Playlist Maker skipped'
    $pmSkip = @($toctou.skipped_targets | Where-Object { $_.id -eq 'playlist-maker' })
    Assert-True ($pmSkip.Count -eq 1 -and $pmSkip[0].reason -eq 'active-extension-sha256-changed-after-provenance') 'TOCTOU skip reason is exact'
    Assert-True ((Get-FileSha256 $f8.PlaylistMakerExtension) -eq $changedPmSha) 'Overlay never repairs or overwrites changed upstream payload'
    Invoke-OverlayJson 'Restore' $f8 | Out-Null
    Assert-True ((Get-FileSha256 $f8.PlaylistMakerExtension) -eq $changedPmSha) 'Restore leaves changed upstream payload untouched'

    Write-Host 'PERFORMANCE OVERLAY POWERSHELL TESTS PASS'
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
