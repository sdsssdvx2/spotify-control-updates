# BEGIN SPOTIFY CONTROL STAR RATINGS PERFORMANCE v1 / r9
$Script:StarRatingsPerformanceEngineBase64 = "@@STAR_ENGINE_B64@@"
$Script:StarRatingsPerformanceEngineSha256 = "@@STAR_ENGINE_SHA@@"
$Script:StarRatingsPerformanceTargetBase64 = "@@STAR_TARGET_B64@@"
$Script:StarRatingsPerformanceTargetSha256 = "@@STAR_TARGET_SHA@@"

function Get-StarRatingsPerformanceBytesSha256([byte[]]$Bytes) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Get-StarRatingsPerformanceFileSha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-StarRatingsPerformanceSpotifyRunning {
    return [bool](Get-Process Spotify -ErrorAction SilentlyContinue | Select-Object -First 1)
}

function Write-StarRatingsPerformanceEmbeddedFile([string]$Path,[string]$Base64,[string]$ExpectedSha256) {
    $bytes=[Convert]::FromBase64String($Base64)
    if((Get-StarRatingsPerformanceBytesSha256 $bytes) -cne $ExpectedSha256){throw "Embedded Star Ratings performance payload hash mismatch: $Path"}
    if(Test-Path -LiteralPath $Path -PathType Leaf){
        if((Get-StarRatingsPerformanceFileSha256 $Path) -cne $ExpectedSha256){throw "Star Ratings performance engine path contains different bytes; preserving it: $Path"}
        return
    }
    $parent=Split-Path -Parent $Path
    if(-not (Test-Path -LiteralPath $parent -PathType Container)){New-Item -ItemType Directory -Force -Path $parent|Out-Null}
    $created=$false
    try {
        $stream=New-Object IO.FileStream($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try {$stream.Write($bytes,0,$bytes.Length);$stream.Flush()} finally {$stream.Dispose()}
        $created=$true
        if((Get-StarRatingsPerformanceFileSha256 $Path) -cne $ExpectedSha256){throw "Star Ratings performance payload materialization verification failed: $Path"}
    } catch {
        if($created -and (Test-Path -LiteralPath $Path -PathType Leaf)){
            try {if((Get-StarRatingsPerformanceFileSha256 $Path) -cne $ExpectedSha256){Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue}} catch {}
        }
        throw
    }
}

function Ensure-StarRatingsPerformanceEngine {
    if(-not $env:LOCALAPPDATA){throw 'LOCALAPPDATA is unavailable.'}
    $root=Join-Path $env:LOCALAPPDATA 'SpotifyControl\star-ratings-performance\engine-v1-r9'
    if(-not (Test-Path -LiteralPath $root -PathType Container)){New-Item -ItemType Directory -Force -Path $root|Out-Null}
    $engine=Join-Path $root 'apply-star-ratings-patch.ps1'
    $target=Join-Path $root 'target.json'
    Write-StarRatingsPerformanceEmbeddedFile $engine $Script:StarRatingsPerformanceEngineBase64 $Script:StarRatingsPerformanceEngineSha256
    Write-StarRatingsPerformanceEmbeddedFile $target $Script:StarRatingsPerformanceTargetBase64 $Script:StarRatingsPerformanceTargetSha256
    return [pscustomobject]@{Root=$root;Engine=$engine;Target=$target}
}

function Invoke-StarRatingsPerformanceBestEffort([string]$Reason) {
    try {
        if(Test-StarRatingsPerformanceSpotifyRunning){Write-AddonLog "Star Ratings performance optimization skipped ($Reason): Spotify is running.";return}
        if(-not $env:APPDATA -or -not $env:LOCALAPPDATA){Write-AddonLog "Star Ratings performance optimization skipped ($Reason): APPDATA/LOCALAPPDATA unavailable." 'WARN';return}
        $xpui=Join-Path $env:APPDATA 'Spotify\Apps\xpui'
        if(-not (Test-Path -LiteralPath $xpui -PathType Container)){Write-AddonLog "Star Ratings performance optimization skipped ($Reason): active xpui is absent." 'WARN';return}
        $engine=Ensure-StarRatingsPerformanceEngine
        $stateRoot=Join-Path $env:LOCALAPPDATA 'SpotifyControl\star-ratings-performance\runtime-v1'
        $powershell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if(-not (Test-Path -LiteralPath $powershell -PathType Leaf)){$powershell='powershell.exe'}
        $output=@(& $powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $engine.Engine -Mode Apply -XpuiRoot $xpui -StateRoot $stateRoot -TargetMetadataPath $engine.Target 2>&1)
        $exitCode=$LASTEXITCODE
        if($exitCode -ne 0){Write-AddonLog "Star Ratings performance optimization skipped ($Reason): engine exit=$exitCode; active upstream bytes remain authoritative." 'WARN';return}
        $tail=[string](@($output|Where-Object{-not [string]::IsNullOrWhiteSpace([string]$_)}|Select-Object -Last 1)-join '')
        if($tail.Length -gt 600){$tail=$tail.Substring(0,600)}
        Write-AddonLog "Star Ratings performance optimization evaluated ($Reason), exit=0 $tail"
    } catch {
        Write-AddonLog "Star Ratings performance optimization best-effort skip ($Reason): $($_.Exception.Message)" 'WARN'
    }
}
# END SPOTIFY CONTROL STAR RATINGS PERFORMANCE v1 / r9
