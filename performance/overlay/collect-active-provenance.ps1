param(
    [Parameter(Mandatory = $true)]
    [string]$XpuiRoot,
    [string]$OutputPath,
    [string]$TargetMetadataPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $TargetMetadataPath) {
    $TargetMetadataPath = Join-Path $ScriptRoot 'targets\pithaya-optional-custom-apps.json'
}

function Get-FileSha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Write-Utf8NoBom([string]$Path, [string]$Text) {
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    [IO.File]::WriteAllBytes($Path, (New-Object Text.UTF8Encoding($false)).GetBytes($Text))
}

if (-not (Test-Path -LiteralPath $XpuiRoot)) { throw "xpui root missing: $XpuiRoot" }
if (-not (Test-Path -LiteralPath $TargetMetadataPath)) { throw "target metadata missing: $TargetMetadataPath" }

$targetsDoc = Get-Content -LiteralPath $TargetMetadataPath -Raw | ConvertFrom-Json
$results = [ordered]@{}

foreach ($target in @($targetsDoc.targets)) {
    $activePath = Join-Path $XpuiRoot ([string]$target.extension_path -replace '/', '\')
    $exists = Test-Path -LiteralPath $activePath -PathType Leaf
    $observedSize = $null
    $observedSha = $null
    $exact = $false
    $reason = 'active-extension-absent'

    if ($exists) {
        $item = Get-Item -LiteralPath $activePath
        $observedSize = [int64]$item.Length
        $observedSha = Get-FileSha256 $activePath
        if ($observedSize -ne [int64]$target.extension_size) {
            $reason = 'active-extension-size-mismatch'
        } elseif ($observedSha -ne [string]$target.extension_sha256) {
            $reason = 'active-extension-sha256-mismatch'
        } else {
            $exact = $true
            $reason = 'exact-active-extension'
        }
    }

    $results[[string]$target.id] = [ordered]@{
        trust = $(if ($exact) { 'exact-active-extension' } else { 'unproven' })
        reason = $reason
        trusted_revision = $(if ($exact) { [string]$target.dist_revision } else { $null })
        source = [string]$targetsDoc.distribution_repository
        active_extension_path = $activePath
        expected_size = [int64]$target.extension_size
        observed_size = $observedSize
        expected_sha256 = [string]$target.extension_sha256
        observed_sha256 = $observedSha
    }
}

$report = [ordered]@{
    schema = 1
    generated_at = (Get-Date).ToString('o')
    mode = 'read-only-active-xpui-extension-provenance'
    xpui_root = (Resolve-Path -LiteralPath $XpuiRoot).Path
    source_repository = [string]$targetsDoc.distribution_repository
    source_commit = [string]$targetsDoc.source_commit
    targets = $results
}

$json = $report | ConvertTo-Json -Depth 12
if ($OutputPath) {
    Write-Utf8NoBom $OutputPath $json
}
$json
