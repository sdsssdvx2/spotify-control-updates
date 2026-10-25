# BEGIN SPOTIFY CONTROL PERFORMANCE OVERLAY v0.1.0 / r8
$Script:PerformanceOverlayApplyBase64 = "@@APPLY_B64@@"
$Script:PerformanceOverlayApplySha256 = "@@APPLY_SHA@@"
$Script:PerformanceOverlayLoaderBase64 = "@@LOADER_B64@@"
$Script:PerformanceOverlayLoaderSha256 = "@@LOADER_SHA@@"
$Script:PerformanceOverlayTargetsBase64 = "@@TARGETS_B64@@"
$Script:PerformanceOverlayTargetsSha256 = "@@TARGETS_SHA@@"

function Get-PerformanceOverlayBytesSha256([byte[]]$Bytes) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-PerformanceOverlayFileSha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-PerformanceOverlaySpotifyRunning {
    return [bool](Get-Process Spotify -ErrorAction SilentlyContinue | Select-Object -First 1)
}

function Write-PerformanceOverlayEmbeddedFile([string]$Path,[string]$Base64,[string]$ExpectedSha256) {
    $bytes=[Convert]::FromBase64String($Base64)
    $embeddedSha=Get-PerformanceOverlayBytesSha256 $bytes
    if ($embeddedSha -cne $ExpectedSha256) { throw "Embedded performance overlay payload hash mismatch for $Path" }
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $existingSha=Get-PerformanceOverlayFileSha256 $Path
        if ($existingSha -cne $ExpectedSha256) { throw "Performance overlay engine path is owned by different bytes; preserving it: $Path" }
        return
    }
    $parent=Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $created=$false
    try {
        $stream=New-Object IO.FileStream($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try { $stream.Write($bytes,0,$bytes.Length); $stream.Flush() } finally { $stream.Dispose() }
        $created=$true
        if ((Get-PerformanceOverlayFileSha256 $Path) -cne $ExpectedSha256) { throw "Performance overlay engine materialization verification failed: $Path" }
    } catch {
        if ($created -and (Test-Path -LiteralPath $Path -PathType Leaf)) {
            try { if ((Get-PerformanceOverlayFileSha256 $Path) -cne $ExpectedSha256) { Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue } } catch {}
        }
        throw
    }
}

function Ensure-PerformanceOverlayEngine {
    if (-not $env:LOCALAPPDATA) { throw 'LOCALAPPDATA is unavailable.' }
    $root=Join-Path $env:LOCALAPPDATA 'SpotifyControl\performance-overlay\engine-v010-r8'
    $targetsDir=Join-Path $root 'targets'
    if (-not (Test-Path -LiteralPath $targetsDir -PathType Container)) { New-Item -ItemType Directory -Force -Path $targetsDir | Out-Null }
    $apply=Join-Path $root 'apply-overlay.ps1'
    $loader=Join-Path $root 'lazy-custom-app-loader.js'
    $targets=Join-Path $targetsDir 'pithaya-optional-custom-apps.json'
    Write-PerformanceOverlayEmbeddedFile $apply $Script:PerformanceOverlayApplyBase64 $Script:PerformanceOverlayApplySha256
    Write-PerformanceOverlayEmbeddedFile $loader $Script:PerformanceOverlayLoaderBase64 $Script:PerformanceOverlayLoaderSha256
    Write-PerformanceOverlayEmbeddedFile $targets $Script:PerformanceOverlayTargetsBase64 $Script:PerformanceOverlayTargetsSha256
    return [pscustomobject]@{ Root=$root; Apply=$apply; Loader=$loader; Targets=$targets }
}

function Get-PerformanceOverlayExactProvenance([string]$XpuiRoot,[string]$TargetMetadataPath) {
    $doc=Get-Content -LiteralPath $TargetMetadataPath -Raw | ConvertFrom-Json
    $roots=@(Get-SpicetifyAssetRoots -Kind 'CustomApp')
    $trusted=[ordered]@{}
    foreach ($target in @($doc.targets)) {
        $id=[string]$target.id
        try {
            $known=Get-PithayaKnownBaseline $id
            if (-not $known) { Write-AddonLog "Performance overlay skip ${id}: no authoritative known baseline." 'WARN'; continue }
            if ([string]$known.revision -cne [string]$target.dist_revision) { Write-AddonLog "Performance overlay skip ${id}: authoritative revision differs from pinned optimization revision." 'WARN'; continue }
            $resolved=Resolve-SpicetifyAsset -Name $id -Kind 'CustomApp' -Roots $roots
            if (-not $resolved -or [string]$resolved.status -ne 'resolved' -or [string]::IsNullOrWhiteSpace([string]$resolved.selected_path)) { Write-AddonLog "Performance overlay skip ${id}: CustomApp path is not uniquely resolved." 'WARN'; continue }
            $snapshot=Get-DirectoryGitSnapshot ([string]$resolved.selected_path)
            if ([string]$snapshot.fingerprint -cne [string]$known.fingerprint) { Write-AddonLog "Performance overlay skip ${id}: installed CustomApp tree is not the exact authoritative baseline." 'WARN'; continue }
            $activePath=Join-Path $XpuiRoot (([string]$target.extension_path) -replace '/','\')
            if (-not (Test-Path -LiteralPath $activePath -PathType Leaf)) { Write-AddonLog "Performance overlay skip ${id}: active xpui extension is absent." 'WARN'; continue }
            $size=[int64](Get-Item -LiteralPath $activePath).Length
            if ($size -ne [int64]$target.extension_size) { Write-AddonLog "Performance overlay skip ${id}: active extension size differs from pinned bytes." 'WARN'; continue }
            $hash=Get-PerformanceOverlayFileSha256 $activePath
            if ($hash -cne [string]$target.extension_sha256) { Write-AddonLog "Performance overlay skip ${id}: active extension SHA-256 differs from pinned bytes." 'WARN'; continue }
            $trusted[$id]=[ordered]@{
                trust='exact-active-extension'
                trusted_revision=[string]$target.dist_revision
                source=[string]$doc.distribution_repository
                observed_sha256=$hash
                observed_size=$size
                full_tree_fingerprint=[string]$snapshot.fingerprint
            }
        } catch {
            Write-AddonLog "Performance overlay skip ${id}: provenance check failed: $($_.Exception.Message)" 'WARN'
        }
    }
    return [pscustomobject]@{ schema=1; generated_at=(Get-Date).ToString('o'); targets=[pscustomobject]$trusted }
}

function Invoke-PerformanceOverlayBestEffort([string]$Reason) {
    try {
        if (Test-PerformanceOverlaySpotifyRunning) { Write-AddonLog "Performance overlay skipped ($Reason): Spotify is running."; return }
        if (-not $env:APPDATA -or -not $env:LOCALAPPDATA) { Write-AddonLog "Performance overlay skipped ($Reason): APPDATA/LOCALAPPDATA unavailable." 'WARN'; return }
        $xpui=Join-Path $env:APPDATA 'Spotify\Apps\xpui'
        $index=Join-Path $xpui 'index.html'
        if (-not (Test-Path -LiteralPath $index -PathType Leaf)) { Write-AddonLog "Performance overlay skipped ($Reason): active xpui index is absent." 'WARN'; return }
        $engine=Ensure-PerformanceOverlayEngine
        $provenance=Get-PerformanceOverlayExactProvenance -XpuiRoot $xpui -TargetMetadataPath $engine.Targets
        if (@($provenance.targets.PSObject.Properties.Name).Count -eq 0) { Write-AddonLog "Performance overlay safe no-op ($Reason): no exactly-proven target."; return }
        $stateRoot=Join-Path $env:LOCALAPPDATA 'SpotifyControl\performance-overlay\runtime-v010'
        if (-not (Test-Path -LiteralPath $stateRoot -PathType Container)) { New-Item -ItemType Directory -Force -Path $stateRoot | Out-Null }
        $provenancePath=Join-Path $stateRoot 'active-provenance.json'
        $json=$provenance | ConvertTo-Json -Depth 12
        [IO.File]::WriteAllBytes($provenancePath,(New-Object Text.UTF8Encoding($false)).GetBytes($json))
        $powershell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if (-not (Test-Path -LiteralPath $powershell -PathType Leaf)) { $powershell='powershell.exe' }
        $output=@(& $powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $engine.Apply -Mode Apply -XpuiRoot $xpui -ProvenancePath $provenancePath -StateRoot $stateRoot -TargetMetadataPath $engine.Targets 2>&1)
        $exitCode=$LASTEXITCODE
        if ($exitCode -ne 0) { Write-AddonLog "Performance overlay skipped ($Reason): engine exit=$exitCode; upstream/original hooks remain authoritative." 'WARN'; return }
        $tail=[string](@($output | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Last 1) -join '')
        if ($tail.Length -gt 600) { $tail=$tail.Substring(0,600) }
        Write-AddonLog "Performance overlay evaluated ($Reason), exit=0 $tail"
    } catch {
        Write-AddonLog "Performance overlay best-effort skip ($Reason): $($_.Exception.Message)" 'WARN'
    }
}
# END SPOTIFY CONTROL PERFORMANCE OVERLAY v0.1.0 / r8
