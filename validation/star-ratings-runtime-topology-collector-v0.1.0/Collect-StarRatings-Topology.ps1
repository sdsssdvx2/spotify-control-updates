param(
    [string]$AppDataRoot = $env:APPDATA,
    [string]$LocalAppDataRoot = $env:LOCALAPPDATA,
    [string]$OutputPath = (Join-Path $PSScriptRoot 'star-ratings-topology-latest.json')
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$CollectorVersion = '0.1.0'
$ReaderPath = Join-Path $PSScriptRoot 'LevelDbReadOnly.cs'
$InstalledListKey = 'marketplace:installed-extensions'
$StarRecordKey = 'marketplace:installed:brimell/spicetify-star-ratings/dist/star-ratings.js'
$MigrationMarkerKey = 'internal:local-storage-migrated'
$KnownOriginalSha = '198fd7c3307de8f2efc36f40df4e79846188cf35a1d5b550ed3d8ab85e8139b1'
$KnownTransformedSha = '6e0d1c84408294a619d91191eec83a6d10794ef31093d31ccf1f1bd39ea8c8a3'
$PerformanceId = 'star-ratings-observer-debounce-v1'

function New-Utf8NoBom {
    return New-Object System.Text.UTF8Encoding($false)
}

function Write-JsonFile([string]$Path, [object]$Value) {
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $json = $Value | ConvertTo-Json -Depth 20
    [IO.File]::WriteAllBytes($Path, (New-Utf8NoBom).GetBytes($json + "`n"))
}

function Get-FileIdentity([string]$Path, [string]$Label) {
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{ label=$Label; exists=$false; size=$null; sha256=$null; reparse=$false }
    }
    $item = Get-Item -LiteralPath $Path -Force
    $reparse = (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
    if ($reparse) {
        return [pscustomobject]@{ label=$Label; exists=$true; size=[int64]$item.Length; sha256=$null; reparse=$true }
    }
    $sha = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    return [pscustomobject]@{ label=$Label; exists=$true; size=[int64]$item.Length; sha256=$sha; reparse=$false }
}

function Get-ConfigEvidence {
    $candidates = @(
        [pscustomobject]@{ label='roaming'; path=(Join-Path $AppDataRoot 'spicetify\config-xpui.ini') },
        [pscustomobject]@{ label='local'; path=(Join-Path $LocalAppDataRoot 'spicetify\config-xpui.ini') }
    )
    $details = @()
    $configured = $false
    $tokensSeen = @()
    foreach ($candidate in $candidates) {
        if (-not (Test-Path -LiteralPath $candidate.path -PathType Leaf)) {
            $details += [pscustomobject]@{ label=$candidate.label; exists=$false; star_configured=$false; tokens=@() }
            continue
        }
        $text = [IO.File]::ReadAllText($candidate.path)
        $tokens = @()
        foreach ($line in ($text -split "`r?`n")) {
            if ($line -match '^\s*extensions\s*=\s*(.*?)\s*$') {
                $raw = [string]$matches[1]
                $tokens = @($raw -split '\|' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            }
        }
        $stars = @($tokens | Where-Object { $_ -ieq 'sc-star-ratings.js' -or $_ -ieq 'star-ratings.js' })
        if ($stars.Count -gt 0) { $configured = $true; $tokensSeen += $stars }
        $details += [pscustomobject]@{ label=$candidate.label; exists=$true; star_configured=($stars.Count -gt 0); tokens=@($stars) }
    }
    return [pscustomobject]@{
        configured=$configured
        matched_tokens=@($tokensSeen | Sort-Object -Unique)
        sources=$details
    }
}

function Get-SourceFileEvidence {
    $files = @(
        [pscustomobject]@{ label='roaming-sc'; path=(Join-Path $AppDataRoot 'spicetify\Extensions\sc-star-ratings.js') },
        [pscustomobject]@{ label='local-sc'; path=(Join-Path $LocalAppDataRoot 'spicetify\Extensions\sc-star-ratings.js') },
        [pscustomobject]@{ label='roaming-plain'; path=(Join-Path $AppDataRoot 'spicetify\Extensions\star-ratings.js') },
        [pscustomobject]@{ label='local-plain'; path=(Join-Path $LocalAppDataRoot 'spicetify\Extensions\star-ratings.js') }
    )
    return @($files | ForEach-Object { Get-FileIdentity $_.path $_.label })
}

function Get-ActiveFileEvidence {
    $files = @(
        [pscustomobject]@{ label='roaming-sc'; path=(Join-Path $AppDataRoot 'Spotify\Apps\xpui\extensions\sc-star-ratings.js') },
        [pscustomobject]@{ label='local-sc'; path=(Join-Path $LocalAppDataRoot 'Spotify\Apps\xpui\extensions\sc-star-ratings.js') },
        [pscustomobject]@{ label='roaming-plain'; path=(Join-Path $AppDataRoot 'Spotify\Apps\xpui\extensions\star-ratings.js') },
        [pscustomobject]@{ label='local-plain'; path=(Join-Path $LocalAppDataRoot 'Spotify\Apps\xpui\extensions\star-ratings.js') }
    )
    return @($files | ForEach-Object { Get-FileIdentity $_.path $_.label })
}

function Test-ChildPath([string]$Parent, [string]$Child) {
    try {
        $p = [IO.Path]::GetFullPath($Parent).TrimEnd('\') + '\'
        $c = [IO.Path]::GetFullPath($Child)
        return $c.StartsWith($p, [StringComparison]::OrdinalIgnoreCase)
    } catch { return $false }
}

function Get-PerformanceEvidence {
    $stateRoot = Join-Path $LocalAppDataRoot 'SpotifyControl\star-ratings-performance\runtime-v1'
    $statePath = Join-Path $stateRoot 'active-state.json'
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
        return [pscustomobject]@{ state_exists=$false; contract_valid=$false; original_backup=$null; reason='state-missing' }
    }
    try {
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        if ([string]$state.id -cne $PerformanceId) { throw 'performance-id-mismatch' }
        if ([string]$state.original_sha256 -cne $KnownOriginalSha) { throw 'original-sha-contract-mismatch' }
        if ([string]$state.transformed_sha256 -cne $KnownTransformedSha) { throw 'transformed-sha-contract-mismatch' }
        $backupPath = [string]$state.backup_path
        if ([string]::IsNullOrWhiteSpace($backupPath) -or -not (Test-ChildPath $stateRoot $backupPath)) { throw 'backup-path-outside-state-root' }
        if ([IO.Path]::GetFileName($backupPath) -cne 'original.bin') { throw 'backup-name-mismatch' }
        $backup = Get-FileIdentity $backupPath 'performance-original'
        $valid = $backup.exists -and -not $backup.reparse -and $backup.sha256 -ceq $KnownOriginalSha
        return [pscustomobject]@{ state_exists=$true; contract_valid=$valid; original_backup=$backup; reason=($(if($valid){'exact-performance-state'}else{'backup-unproven'})) }
    } catch {
        return [pscustomobject]@{ state_exists=$true; contract_valid=$false; original_backup=$null; reason=('state-invalid:' + $_.Exception.Message) }
    }
}

function Get-LevelDbFileFingerprint([string]$Directory) {
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) { return $null }
    $parts = @()
    foreach ($pattern in @('*.ldb','*.sst','*.log')) {
        $items = @(Get-ChildItem -LiteralPath $Directory -Filter $pattern -File -Force -ErrorAction Stop | Sort-Object Name)
        foreach ($item in $items) {
            $parts += ('{0}|{1}|{2}' -f $item.Name,[int64]$item.Length,$item.LastWriteTimeUtc.Ticks)
        }
    }
    return ($parts -join ';')
}

function Read-LevelDbStable([string]$Directory) {
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        return [pscustomobject]@{ exists=$false; stable=$true; complete=$false; records=@(); errors=@('leveldb-directory-missing'); attempts=0 }
    }
    for ($attempt=1; $attempt -le 3; $attempt++) {
        try {
            $before = Get-LevelDbFileFingerprint $Directory
            $read = [SpotifyControlValidation.LevelDbReadOnly]::ReadDirectory($Directory)
            $after = Get-LevelDbFileFingerprint $Directory
            if ($before -ceq $after) {
                return [pscustomobject]@{
                    exists=$true
                    stable=$true
                    complete=[bool]$read.Complete
                    records=@($read.Records)
                    errors=@($read.Errors)
                    attempts=$attempt
                }
            }
        } catch {
            if ($attempt -eq 3) {
                return [pscustomobject]@{ exists=$true; stable=$false; complete=$false; records=@(); errors=@(('read-exception:' + $_.Exception.Message)); attempts=$attempt }
            }
        }
        Start-Sleep -Milliseconds (150 * $attempt)
    }
    return [pscustomobject]@{ exists=$true; stable=$false; complete=$false; records=@(); errors=@('leveldb-files-changed-during-read'); attempts=3 }
}

function Get-IndexedDbMarketplaceEvidence([string]$Directory, [string]$Label) {
    $read = Read-LevelDbStable $Directory
    if (-not $read.exists) {
        return [pscustomobject]@{ label=$Label; source='indexeddb'; status='unavailable'; installed=$null; authoritative=$false; complete=$false; stable=$true; migration_marker=$false; database_found=$false; settings_store_found=$false; installed_list_present=$false; star_record_present=$false; list_contains_star=$false; errors=@($read.errors) }
    }
    if (-not $read.stable -or -not $read.complete) {
        return [pscustomobject]@{ label=$Label; source='indexeddb'; status='inconclusive'; installed=$null; authoritative=$false; complete=$read.complete; stable=$read.stable; migration_marker=$false; database_found=$false; settings_store_found=$false; installed_list_present=$false; star_record_present=$false; list_contains_star=$false; errors=@($read.errors) }
    }

    $records = @($read.records | Where-Object { -not $_.Deleted })
    $databaseIds = @()
    foreach ($entry in $records) {
        $info = [SpotifyControlValidation.ChromiumIndexedDb]::DecodeDatabaseName($entry)
        if ($info.Success -and [string]$info.Name -ceq 'spicetify-marketplace') { $databaseIds += [uint64]$info.DatabaseId }
    }
    $databaseIds = @($databaseIds | Sort-Object -Unique)
    if ($databaseIds.Count -eq 0) {
        return [pscustomobject]@{ label=$Label; source='indexeddb'; status='clean-no-marketplace-db'; installed=$false; authoritative=$false; complete=$true; stable=$true; migration_marker=$false; database_found=$false; settings_store_found=$false; installed_list_present=$false; star_record_present=$false; list_contains_star=$false; errors=@() }
    }

    $candidateResults = @()
    foreach ($dbId in $databaseIds) {
        $storeIds = @()
        foreach ($entry in $records) {
            $info = [SpotifyControlValidation.ChromiumIndexedDb]::DecodeObjectStoreName($entry, [uint64]$dbId)
            if ($info.Success -and [string]$info.Name -ceq 'settings') { $storeIds += [uint64]$info.ObjectStoreId }
        }
        $storeIds = @($storeIds | Sort-Object -Unique)
        foreach ($storeId in $storeIds) {
            $listEntry = $null; $starEntry = $null; $migrationEntry = $null
            foreach ($entry in $records) {
                $keyInfo = [SpotifyControlValidation.ChromiumIndexedDb]::DecodeObjectStoreStringKey($entry, [uint64]$dbId, [uint64]$storeId)
                if (-not $keyInfo.Success) { continue }
                $primary = [string]$keyInfo.PrimaryKey
                if ($primary -ceq $InstalledListKey) { $listEntry = $entry }
                elseif ($primary -ceq $StarRecordKey) { $starEntry = $entry }
                elseif ($primary -ceq $MigrationMarkerKey) { $migrationEntry = $entry }
            }
            $listPresent = $null -ne $listEntry
            $starPresent = $null -ne $starEntry
            $markerPresent = $null -ne $migrationEntry
            $contains = $false
            if ($listPresent) { $contains = [SpotifyControlValidation.ChromiumIndexedDb]::ContainsEncodedText($listEntry.Value, $StarRecordKey) }
            $installed = $listPresent -and $starPresent -and $contains
            $candidateResults += [pscustomobject]@{ installed=$installed; marker=$markerPresent; list=$listPresent; star=$starPresent; contains=$contains }
        }
    }

    if ($candidateResults.Count -eq 0) {
        return [pscustomobject]@{ label=$Label; source='indexeddb'; status='inconclusive-no-settings-store'; installed=$null; authoritative=$false; complete=$true; stable=$true; migration_marker=$false; database_found=$true; settings_store_found=$false; installed_list_present=$false; star_record_present=$false; list_contains_star=$false; errors=@() }
    }
    if (@($candidateResults | Where-Object { $_.installed }).Count -gt 0) {
        $winning = @($candidateResults | Where-Object { $_.installed })[0]
        return [pscustomobject]@{ label=$Label; source='indexeddb'; status='installed'; installed=$true; authoritative=[bool]$winning.marker; complete=$true; stable=$true; migration_marker=[bool]$winning.marker; database_found=$true; settings_store_found=$true; installed_list_present=$true; star_record_present=$true; list_contains_star=$true; errors=@() }
    }
    $marker = @($candidateResults | Where-Object { $_.marker }).Count -gt 0
    $anyList = @($candidateResults | Where-Object { $_.list }).Count -gt 0
    $anyStar = @($candidateResults | Where-Object { $_.star }).Count -gt 0
    $anyContains = @($candidateResults | Where-Object { $_.contains }).Count -gt 0
    return [pscustomobject]@{ label=$Label; source='indexeddb'; status='not-installed'; installed=$false; authoritative=$marker; complete=$true; stable=$true; migration_marker=$marker; database_found=$true; settings_store_found=$true; installed_list_present=$anyList; star_record_present=$anyStar; list_contains_star=$anyContains; errors=@() }
}

function Get-LocalStorageMarketplaceEvidence([string]$Directory, [string]$Label) {
    $read = Read-LevelDbStable $Directory
    if (-not $read.exists) {
        return [pscustomobject]@{ label=$Label; source='local-storage'; status='unavailable'; installed=$null; complete=$false; stable=$true; installed_list_present=$false; star_record_present=$false; list_contains_star=$false; errors=@($read.errors) }
    }
    if (-not $read.stable -or -not $read.complete) {
        return [pscustomobject]@{ label=$Label; source='local-storage'; status='inconclusive'; installed=$null; complete=$read.complete; stable=$read.stable; installed_list_present=$false; star_record_present=$false; list_contains_star=$false; errors=@($read.errors) }
    }
    $records = @($read.records | Where-Object { -not $_.Deleted })
    $listMatches = @($records | Where-Object { [SpotifyControlValidation.ChromiumIndexedDb]::ContainsEncodedText($_.Key, $InstalledListKey) })
    $starMatches = @($records | Where-Object { [SpotifyControlValidation.ChromiumIndexedDb]::ContainsEncodedText($_.Key, $StarRecordKey) })
    if ($listMatches.Count -gt 1 -or $starMatches.Count -gt 1) {
        return [pscustomobject]@{ label=$Label; source='local-storage'; status='inconclusive-ambiguous-live-records'; installed=$null; complete=$true; stable=$true; installed_list_present=($listMatches.Count -gt 0); star_record_present=($starMatches.Count -gt 0); list_contains_star=$false; errors=@() }
    }
    $contains = $false
    if ($listMatches.Count -eq 1) { $contains = [SpotifyControlValidation.ChromiumIndexedDb]::ContainsEncodedText($listMatches[0].Value, $StarRecordKey) }
    $installed = ($listMatches.Count -eq 1 -and $starMatches.Count -eq 1 -and $contains)
    return [pscustomobject]@{ label=$Label; source='local-storage'; status=($(if($installed){'installed'}else{'not-installed'})); installed=$installed; complete=$true; stable=$true; installed_list_present=($listMatches.Count -eq 1); star_record_present=($starMatches.Count -eq 1); list_contains_star=$contains; errors=@() }
}

function Get-IndexedDbDirectories([string]$ProfileRoot) {
    $root = Join-Path $ProfileRoot 'IndexedDB'
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { return @() }
    $dirs = @(Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '*.leveldb' })
    if ($dirs.Count -gt 32) { return @() }
    return @($dirs | ForEach-Object { $_.FullName })
}

function Combine-ProfileMarketplaceEvidence([string]$ProfileLabel, [string]$ProfileRoot) {
    if (-not (Test-Path -LiteralPath $ProfileRoot -PathType Container)) {
        return [pscustomobject]@{ profile=$ProfileLabel; exists=$false; status='not-present'; installed=$null; indexeddb=@(); local_storage=$null }
    }
    $idbResults = @()
    foreach ($dir in (Get-IndexedDbDirectories $ProfileRoot)) {
        $idbResults += Get-IndexedDbMarketplaceEvidence $dir ($ProfileLabel + ':indexeddb')
    }
    $localDir = Join-Path $ProfileRoot 'Local Storage\leveldb'
    $local = Get-LocalStorageMarketplaceEvidence $localDir ($ProfileLabel + ':local-storage')

    $authoritative = @($idbResults | Where-Object { $_.authoritative })
    if ($authoritative.Count -gt 0) {
        if (@($authoritative | Where-Object { $_.installed -eq $true }).Count -gt 0) {
            return [pscustomobject]@{ profile=$ProfileLabel; exists=$true; status='installed-indexeddb-authoritative'; installed=$true; indexeddb=$idbResults; local_storage=$local }
        }
        if (@($authoritative | Where-Object { $_.installed -eq $null }).Count -gt 0) {
            return [pscustomobject]@{ profile=$ProfileLabel; exists=$true; status='inconclusive-indexeddb-authoritative'; installed=$null; indexeddb=$idbResults; local_storage=$local }
        }
        return [pscustomobject]@{ profile=$ProfileLabel; exists=$true; status='not-installed-indexeddb-authoritative'; installed=$false; indexeddb=$idbResults; local_storage=$local }
    }

    $signals = @($idbResults) + @($local)
    if (@($signals | Where-Object { $_.installed -eq $true }).Count -gt 0) {
        return [pscustomobject]@{ profile=$ProfileLabel; exists=$true; status='installed-fallback-union'; installed=$true; indexeddb=$idbResults; local_storage=$local }
    }
    $decisive = @($signals | Where-Object { $_.installed -ne $null })
    $inconclusive = @($signals | Where-Object { $_.installed -eq $null -and $_.status -notin @('unavailable','clean-no-marketplace-db') })
    if ($inconclusive.Count -gt 0 -or $decisive.Count -eq 0) {
        return [pscustomobject]@{ profile=$ProfileLabel; exists=$true; status='inconclusive'; installed=$null; indexeddb=$idbResults; local_storage=$local }
    }
    return [pscustomobject]@{ profile=$ProfileLabel; exists=$true; status='not-installed'; installed=$false; indexeddb=$idbResults; local_storage=$local }
}

function Get-MarketplaceEvidence {
    $profiles = @()
    $profiles += Combine-ProfileMarketplaceEvidence -ProfileLabel 'Browser' -ProfileRoot (Join-Path $LocalAppDataRoot 'Spotify\Browser')
    $profiles += Combine-ProfileMarketplaceEvidence -ProfileLabel 'Default' -ProfileRoot (Join-Path $LocalAppDataRoot 'Spotify\Default')
    $present = @($profiles | Where-Object { $_.exists })
    if (@($present | Where-Object { $_.installed -eq $true }).Count -gt 0) {
        $installed = $true; $status = 'installed'
    } elseif ($present.Count -gt 0 -and @($present | Where-Object { $_.installed -eq $null }).Count -eq 0) {
        $installed = $false; $status = 'not-installed'
    } else {
        $installed = $null; $status = 'inconclusive'
    }
    return [pscustomobject]@{ status=$status; installed=$installed; profiles=$profiles }
}

if (-not (Test-Path -LiteralPath $ReaderPath -PathType Leaf)) { throw "Reader source missing: $ReaderPath" }
Add-Type -Path $ReaderPath -ErrorAction Stop

$config = Get-ConfigEvidence
$sourceFiles = @(Get-SourceFileEvidence)
$activeFiles = @(Get-ActiveFileEvidence)
$performance = Get-PerformanceEvidence
$marketplace = Get-MarketplaceEvidence

$activeExisting = @($activeFiles | Where-Object { $_.exists -and -not $_.reparse })
$activeKnown = @($activeExisting | Where-Object { $_.sha256 -ceq $KnownOriginalSha -or $_.sha256 -ceq $KnownTransformedSha })
$sourceExisting = @($sourceFiles | Where-Object { $_.exists -and -not $_.reparse })
$localConfiguredActive = [bool]($config.configured -and $activeExisting.Count -gt 0)
$localResidual = [bool]((-not $config.configured) -and ($sourceExisting.Count -gt 0 -or $activeExisting.Count -gt 0))
$localDrift = [bool]($config.configured -and $activeExisting.Count -eq 0)

$topology = 'inconclusive'
if ($marketplace.installed -eq $true -and $localConfiguredActive) {
    $topology = 'dual-owned-risk'
} elseif ($marketplace.installed -eq $true -and -not $localConfiguredActive -and -not $localResidual -and -not $localDrift) {
    $topology = 'marketplace-only-likely'
} elseif ($marketplace.installed -eq $false -and $localConfiguredActive) {
    $topology = 'configured-only-likely'
} elseif ($marketplace.installed -eq $true -and $localResidual) {
    $topology = 'inconclusive-marketplace-plus-residual-local-bytes'
} elseif ($marketplace.installed -eq $false -and -not $localConfiguredActive -and -not $localResidual -and -not $localDrift) {
    $topology = 'neither-path-proven'
}

$report = [ordered]@{
    schema = 1
    collector_version = $CollectorVersion
    generated_utc = [DateTime]::UtcNow.ToString('o')
    read_only = $true
    spotify_process_action = 'none'
    mutation_performed = $false
    exact_keys = [ordered]@{
        installed_list = $InstalledListKey
        star_ratings_record = $StarRecordKey
    }
    marketplace = $marketplace
    spicetify_config = $config
    local_source_files = $sourceFiles
    active_xpui_files = $activeFiles
    performance_state = $performance
    derived = [ordered]@{
        local_configured_active = $localConfiguredActive
        local_residual_bytes = $localResidual
        local_config_drift = $localDrift
        active_known_release_or_transform_count = $activeKnown.Count
        topology = $topology
        safe_to_expand_mutation_authority = $false
        next_decision = 'review-topology-evidence-only'
    }
}

Write-JsonFile $OutputPath $report
Write-Host ''
Write-Host ('Star Ratings ownership topology: {0}' -f $topology)
Write-Host ('Marketplace installed evidence: {0}' -f $marketplace.status)
Write-Host ('Persistent local config: {0}' -f $config.configured)
Write-Host ('No Spotify/Spicetify/Marketplace data was modified.')
Write-Host ('Report: {0}' -f $OutputPath)