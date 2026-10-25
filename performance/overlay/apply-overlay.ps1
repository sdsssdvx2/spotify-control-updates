param(
    [ValidateSet('Audit','Apply','Restore')]
    [string]$Mode = 'Audit',
    [string]$XpuiRoot,
    [string]$ProvenancePath,
    [string]$StateRoot,
    [string]$TargetMetadataPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $TargetMetadataPath) {
    $TargetMetadataPath = Join-Path $ScriptRoot 'targets\pithaya-optional-custom-apps.json'
}
$LoaderSource = Join-Path $ScriptRoot 'lazy-custom-app-loader.js'
$LoaderRelativePath = 'extensions/spotify-control-performance-overlay.v010.js'
$OverlayMarkerPrefix = 'spotify-control-performance-overlay:lazy:'

if (-not $StateRoot) {
    if (-not $env:LOCALAPPDATA) { throw 'StateRoot is required when LOCALAPPDATA is unavailable.' }
    $StateRoot = Join-Path $env:LOCALAPPDATA 'SpotifyControl\performance-overlay'
}

function Get-FileSha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-BytesSha256([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Read-Utf8Exact([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $offset = 0
    $count = $bytes.Length
    if ($hasBom) { $offset = 3; $count -= 3 }
    $encoding = New-Object Text.UTF8Encoding($false, $true)
    try {
        $text = $encoding.GetString($bytes, $offset, $count)
    } catch {
        throw "Refusing optimization because $Path is not strict UTF-8: $($_.Exception.Message)"
    }
    return [pscustomobject]@{ Bytes = $bytes; Text = $text; HasBom = $hasBom }
}

function ConvertTo-Utf8ExactBytes([string]$Text, [bool]$HasBom) {
    $encoding = New-Object Text.UTF8Encoding($false)
    $body = $encoding.GetBytes($Text)
    if (-not $HasBom) { return $body }
    $result = New-Object byte[] ($body.Length + 3)
    $result[0] = 0xEF; $result[1] = 0xBB; $result[2] = 0xBF
    [Array]::Copy($body, 0, $result, 3, $body.Length)
    return $result
}

function Write-BytesAtomic([string]$Path, [byte[]]$Bytes) {
    $dir = Split-Path -Parent $Path
    $leaf = [IO.Path]::GetFileName($Path)
    $nonce = [Guid]::NewGuid().ToString('N')
    $tmp = Join-Path $dir ($leaf + '.scperf.' + $nonce + '.tmp')
    $replaceBackup = Join-Path $dir ($leaf + '.scperf.' + $nonce + '.replace-backup')
    try {
        [IO.File]::WriteAllBytes($tmp, $Bytes)
        if (Test-Path -LiteralPath $Path) {
            [IO.File]::Replace($tmp, $Path, $replaceBackup)
        } else {
            [IO.File]::Move($tmp, $Path)
        }
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $replaceBackup) { Remove-Item -LiteralPath $replaceBackup -Force -ErrorAction SilentlyContinue }
    }
}

function Get-TrustedTarget([object]$Provenance, [string]$Id) {
    if (-not $Provenance -or -not $Provenance.targets) { return $null }
    $property = $Provenance.targets.PSObject.Properties[$Id]
    if (-not $property) { return $null }
    return $property.Value
}

function Get-OptionalProperty([object]$Object, [string]$Name) {
    if (-not $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if (-not $property) { return $null }
    return $property.Value
}

function Get-TagPattern([string]$ExtensionPath) {
    $escaped = [Text.RegularExpressions.Regex]::Escape($ExtensionPath)
    return '<script\b(?=[^>]*\bsrc\s*=\s*["''](?:\./)?' + $escaped + '["''])[^>]*>\s*</script\s*>'
}

function Get-Plan([string]$IndexText, [object]$TargetsDoc, [object]$Provenance, [string]$XpuiRoot) {
    $results = New-Object Collections.Generic.List[object]
    $options = [Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [Text.RegularExpressions.RegexOptions]::Singleline
    foreach ($target in @($TargetsDoc.targets)) {
        $trusted = Get-TrustedTarget $Provenance $target.id
        $reason = $null
        $eligible = $true
        $activeExtensionPath = Join-Path $XpuiRoot ([string]$target.extension_path -replace '/', '\')
        $activeSize = $null
        $activeSha = $null

        if (-not $trusted) {
            $eligible = $false; $reason = 'missing-active-extension-provenance'
        } elseif ((Get-OptionalProperty $trusted 'trust') -ne 'exact-active-extension') {
            $eligible = $false; $reason = 'active-extension-provenance-not-exact'
        } elseif ((Get-OptionalProperty $trusted 'trusted_revision') -ne $target.dist_revision) {
            $eligible = $false; $reason = 'revision-changed-skip-optimization'
        } elseif ((Get-OptionalProperty $trusted 'source') -ne $TargetsDoc.distribution_repository) {
            $eligible = $false; $reason = 'source-changed-skip-optimization'
        } elseif ((Get-OptionalProperty $trusted 'observed_sha256') -ne $target.extension_sha256) {
            $eligible = $false; $reason = 'provenance-extension-sha256-mismatch'
        } elseif ([int64](Get-OptionalProperty $trusted 'observed_size') -ne [int64]$target.extension_size) {
            $eligible = $false; $reason = 'provenance-extension-size-mismatch'
        } elseif (-not (Test-Path -LiteralPath $activeExtensionPath -PathType Leaf)) {
            $eligible = $false; $reason = 'active-extension-absent-after-provenance'
        } else {
            $activeSize = [int64](Get-Item -LiteralPath $activeExtensionPath).Length
            $activeSha = Get-FileSha256 $activeExtensionPath
            if ($activeSize -ne [int64]$target.extension_size) {
                $eligible = $false; $reason = 'active-extension-size-changed-after-provenance'
            } elseif ($activeSha -ne [string]$target.extension_sha256) {
                $eligible = $false; $reason = 'active-extension-sha256-changed-after-provenance'
            }
        }

        $pattern = Get-TagPattern $target.extension_path
        $matches = [Text.RegularExpressions.Regex]::Matches($IndexText, $pattern, $options)
        if ($eligible -and $matches.Count -eq 0) { $eligible = $false; $reason = 'hook-absent' }
        elseif ($eligible -and $matches.Count -ne 1) { $eligible = $false; $reason = 'hook-ambiguous' }

        $results.Add([pscustomobject]@{
            id = $target.id
            eligible = $eligible
            reason = $(if ($eligible) { 'exact-active-extension-and-hook' } else { $reason })
            match_count = $matches.Count
            pattern = $pattern
            extension_path = $target.extension_path
            dist_revision = $target.dist_revision
            expected_extension_size = [int64]$target.extension_size
            active_extension_size = $activeSize
            expected_extension_sha256 = [string]$target.extension_sha256
            active_extension_sha256 = $activeSha
            route_prefixes = @($target.route_prefixes)
            readiness = $target.readiness
        })
    }
    return $results.ToArray()
}

function Build-TransformedIndex([string]$IndexText, [object[]]$Plan) {
    $eligible = @($Plan | Where-Object { $_.eligible })
    if ($eligible.Count -eq 0) { return $null }
    $text = $IndexText
    $options = [Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [Text.RegularExpressions.RegexOptions]::Singleline
    foreach ($item in $eligible) {
        $marker = '<!-- ' + $OverlayMarkerPrefix + $item.id + ' -->'
        $regex = New-Object Text.RegularExpressions.Regex($item.pattern, $options)
        $text = $regex.Replace($text, $marker, 1)
    }

    $runtimeTargets = @()
    foreach ($item in $eligible) {
        $runtimeTargets += [ordered]@{
            id = $item.id
            src = $item.extension_path
            routePrefixes = @($item.route_prefixes)
            readiness = $item.readiness
        }
    }
    $config = [ordered]@{ schema = 1; targets = $runtimeTargets }
    $json = $config | ConvertTo-Json -Depth 12 -Compress
    if ($json.Contains('<') -or $json.Contains('>')) { throw 'Unexpected unsafe character in generated overlay config.' }
    $bootstrap = '<script data-spotify-control-performance-overlay-config>window.__spotifyControlPerformanceOverlayConfig=' + $json + ';</script>' +
        '<script src="' + $LoaderRelativePath + '" data-spotify-control-performance-overlay-loader></script>'

    $firstMarker = $text.IndexOf('<!-- ' + $OverlayMarkerPrefix, [StringComparison]::Ordinal)
    if ($firstMarker -lt 0) { throw 'Internal transform error: no overlay marker after replacement.' }
    return $text.Insert($firstMarker, $bootstrap)
}

function Write-JsonUtf8([string]$Path, [object]$Value) {
    $json = $Value | ConvertTo-Json -Depth 16
    $bytes = (New-Object Text.UTF8Encoding($false)).GetBytes($json)
    [IO.File]::WriteAllBytes($Path, $bytes)
}

if (-not (Test-Path -LiteralPath $TargetMetadataPath)) { throw "Target metadata missing: $TargetMetadataPath" }
if (-not (Test-Path -LiteralPath $LoaderSource)) { throw "Loader missing: $LoaderSource" }
$targetsDoc = Get-Content -LiteralPath $TargetMetadataPath -Raw | ConvertFrom-Json
$loaderSha = Get-FileSha256 $LoaderSource

if ($Mode -eq 'Restore') {
    $activeStatePath = Join-Path $StateRoot 'active-state.json'
    if (-not (Test-Path -LiteralPath $activeStatePath)) {
        [pscustomobject]@{ status = 'no-active-overlay'; mode = 'Restore' } | ConvertTo-Json -Depth 8
        exit 0
    }
    $state = Get-Content -LiteralPath $activeStatePath -Raw | ConvertFrom-Json
    $indexPath = [string]$state.index_path
    if (-not (Test-Path -LiteralPath $indexPath)) { throw "Active overlay index missing: $indexPath" }
    $currentSha = Get-FileSha256 $indexPath
    if ($currentSha -ne [string]$state.transformed_index_sha256) {
        throw 'Refusing restore because active index changed after overlay application; upstream/newer content will not be overwritten.'
    }
    $backupPath = [string]$state.backup_index_path
    if (-not (Test-Path -LiteralPath $backupPath)) { throw "Original index backup missing: $backupPath" }
    $originalBytes = [IO.File]::ReadAllBytes($backupPath)
    Write-BytesAtomic $indexPath $originalBytes
    $restoredSha = Get-FileSha256 $indexPath
    if ($restoredSha -ne [string]$state.original_index_sha256) { throw 'Original index SHA-256 restore verification failed.' }

    $loaderRetained = $false
    $loaderPath = [string]$state.loader_path
    if (Test-Path -LiteralPath $loaderPath) {
        if ((Get-FileSha256 $loaderPath) -eq [string]$state.loader_sha256) {
            Remove-Item -LiteralPath $loaderPath -Force
        } else {
            $loaderRetained = $true
        }
    }
    $restoredStatePath = Join-Path (Split-Path -Parent $backupPath) 'restored-state.json'
    Write-JsonUtf8 $restoredStatePath $state
    Remove-Item -LiteralPath $activeStatePath -Force
    [pscustomobject]@{ status = 'restored'; exact_index_restore = $true; loader_retained_conflict = $loaderRetained; original_index_sha256 = $restoredSha } | ConvertTo-Json -Depth 8
    exit 0
}

if (-not $XpuiRoot) { throw 'XpuiRoot is required for Audit/Apply.' }
$indexPath = Join-Path $XpuiRoot 'index.html'
if (-not (Test-Path -LiteralPath $indexPath)) { throw "xpui index missing: $indexPath" }
if (-not $ProvenancePath -or -not (Test-Path -LiteralPath $ProvenancePath)) { throw 'ProvenancePath is required and must exist for Audit/Apply.' }
$provenance = Get-Content -LiteralPath $ProvenancePath -Raw | ConvertFrom-Json
$index = Read-Utf8Exact $indexPath
$plan = Get-Plan $index.Text $targetsDoc $provenance $XpuiRoot

if ($Mode -eq 'Audit') {
    [pscustomobject]@{ status = 'audited'; mode = 'Audit'; index_sha256 = Get-BytesSha256 $index.Bytes; targets = $plan } | ConvertTo-Json -Depth 16
    exit 0
}

New-Item -ItemType Directory -Force -Path $StateRoot | Out-Null
$activeStatePath = Join-Path $StateRoot 'active-state.json'
if (Test-Path -LiteralPath $activeStatePath) {
    $oldState = Get-Content -LiteralPath $activeStatePath -Raw | ConvertFrom-Json
    $currentSha = Get-BytesSha256 $index.Bytes
    if ($currentSha -eq [string]$oldState.transformed_index_sha256) {
        $oldLoaderPath = [string]$oldState.loader_path
        if ((Test-Path -LiteralPath $oldLoaderPath) -and (Get-FileSha256 $oldLoaderPath) -eq [string]$oldState.loader_sha256) {
            [pscustomobject]@{ status = 'already-applied'; mode = 'Apply'; index_sha256 = $currentSha } | ConvertTo-Json -Depth 8
            exit 0
        }
        throw 'Active overlay state matches index but loader is missing or changed; refusing implicit repair.'
    }
    $staleName = 'stale-state-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.json'
    Move-Item -LiteralPath $activeStatePath -Destination (Join-Path $StateRoot $staleName) -Force
}

if ($index.Text.Contains($OverlayMarkerPrefix)) { throw 'Orphaned overlay marker found without matching active state; refusing mutation.' }
$eligible = @($plan | Where-Object { $_.eligible })
if ($eligible.Count -eq 0) {
    [pscustomobject]@{ status = 'no-op'; mode = 'Apply'; reason = 'no-exactly-proven-targets'; targets = $plan } | ConvertTo-Json -Depth 16
    exit 0
}

$loaderPath = Join-Path $XpuiRoot ($LoaderRelativePath -replace '/', '\')
$loaderDir = Split-Path -Parent $loaderPath
if (-not (Test-Path -LiteralPath $loaderDir)) { throw "xpui extensions directory missing: $loaderDir" }
$loaderPreExisted = Test-Path -LiteralPath $loaderPath
if ($loaderPreExisted -and (Get-FileSha256 $loaderPath) -ne $loaderSha) {
    [pscustomobject]@{ status = 'no-op'; mode = 'Apply'; reason = 'reserved-loader-path-conflict'; targets = $plan } | ConvertTo-Json -Depth 16
    exit 0
}

$transformedText = Build-TransformedIndex $index.Text $plan
if (-not $transformedText) { throw 'Internal transform error: eligible targets produced no transformed index.' }
$transformedBytes = ConvertTo-Utf8ExactBytes $transformedText $index.HasBom
$originalSha = Get-BytesSha256 $index.Bytes
$transformedSha = Get-BytesSha256 $transformedBytes
if ($originalSha -eq $transformedSha) { throw 'Transform produced identical index bytes unexpectedly.' }

$sessionDir = Join-Path $StateRoot ((Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $sessionDir | Out-Null
$backupPath = Join-Path $sessionDir 'index.original.bin'
[IO.File]::WriteAllBytes($backupPath, $index.Bytes)
if ((Get-FileSha256 $backupPath) -ne $originalSha) { throw 'Original index backup verification failed before mutation.' }

$loaderCreated = $false
try {
    if (-not $loaderPreExisted) {
        [IO.File]::Copy($LoaderSource, $loaderPath, $false)
        $loaderCreated = $true
    }
    if ((Get-FileSha256 $loaderPath) -ne $loaderSha) { throw 'Loader copy verification failed.' }
    Write-BytesAtomic $indexPath $transformedBytes
    if ((Get-FileSha256 $indexPath) -ne $transformedSha) { throw 'Transformed index verification failed.' }

    $state = [ordered]@{
        schema = 1
        applied_at = (Get-Date).ToString('o')
        index_path = $indexPath
        original_index_sha256 = $originalSha
        transformed_index_sha256 = $transformedSha
        backup_index_path = $backupPath
        loader_path = $loaderPath
        loader_sha256 = $loaderSha
        targets = @($eligible | ForEach-Object { $_.id })
    }
    Write-JsonUtf8 (Join-Path $sessionDir 'state.json') $state
    Write-JsonUtf8 $activeStatePath $state
} catch {
    if ((Test-Path -LiteralPath $indexPath) -and (Get-FileSha256 $indexPath) -eq $transformedSha) {
        Write-BytesAtomic $indexPath $index.Bytes
    }
    if ($loaderCreated -and (Test-Path -LiteralPath $loaderPath) -and (Get-FileSha256 $loaderPath) -eq $loaderSha) {
        Remove-Item -LiteralPath $loaderPath -Force -ErrorAction SilentlyContinue
    }
    throw
}

[pscustomobject]@{
    status = 'applied'
    mode = 'Apply'
    original_index_sha256 = $originalSha
    transformed_index_sha256 = $transformedSha
    loader_sha256 = $loaderSha
    optimized_targets = @($eligible | ForEach-Object { $_.id })
    skipped_targets = @($plan | Where-Object { -not $_.eligible } | Select-Object id, reason)
    state_path = $activeStatePath
} | ConvertTo-Json -Depth 16
