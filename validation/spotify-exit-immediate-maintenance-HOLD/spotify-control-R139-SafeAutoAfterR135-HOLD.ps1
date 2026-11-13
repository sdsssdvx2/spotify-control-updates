# Spotify Control v0.6.28 SC Cover Ambience Commit Provenance r17
# Safe launcher/maintenance wrapper for Spotify + Spicetify on Windows.
[CmdletBinding()]
param(
    [ValidateSet("Launch","Maintain","CheckOnly","AgentTick","Audit","UpdateMarketplace","MarketplacePreflight","SpicetifyPreflight","UpdateSpicetify","SpicetifyRollbackTest","RollbackSpicetify","SpotifyPreflight","UpdateSpotify","SpotifyRollbackTest","RollbackSpotify","InstallTasks","SelfTest","SelfUpdateCheck","SelfUpdate","SelfUpdateRollbackTest","RollbackSelfUpdate","GuardUpdates","Status","OwnerSpicetifyOnce","OwnerEnableSafeAuto")]
    [string]$Action = "Launch",
    [ValidateSet("Startup","Periodic","SpotifyExit","Manual","InstallVerify")]
    [string]$AgentEvent = "Manual",
    [string]$OwnerOnceApproval = "",
    [string]$OwnerSafeAutoApproval = "",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$ScriptVersion = "0.6.30"
$ScriptFile = $PSCommandPath
$Root = Join-Path $env:LOCALAPPDATA "SpotifyControl"
$LogDir = Join-Path $Root "logs"
$BackupDir = Join-Path $Root "backups"
$StatePath = Join-Path $Root "state.json"
$BinDir = Split-Path -Parent $ScriptFile
# When a candidate main script is exercised directly from an update package before
# installation, keep candidate-owned dependencies (Addon Manager) beside that script,
# but resolve long-lived auxiliary helpers from the already installed SpotifyControl bin.
# This lets pre-install SelfTest validate the real installed helper set without bundling
# stale copies of performance/health tooling into every transaction patch.
$InstalledBinDir = Join-Path $Root "bin"
$AuxBinDir = if (Test-Path -LiteralPath $InstalledBinDir -PathType Container) { $InstalledBinDir } else { $BinDir }
$AuditScript = Join-Path $AuxBinDir "collect-spotify-diagnostics.ps1"
$AddonManager = Join-Path $BinDir "addon-manager.ps1"
$PerformanceProfiler = Join-Path $AuxBinDir "performance-profiler.ps1"
$HealthReporter = Join-Path $AuxBinDir "health-report.ps1"
$ReportDir = Join-Path $Root "reports"
$SelfUpdater = Join-Path $Root "bootstrap\spotify-control-self-updater.ps1"
$SelfUpdateReport = Join-Path $ReportDir "self-update-latest.json"
$SelfUpdateCheckIntervalHours = 12
$MaintenanceCheckReport = Join-Path $ReportDir "maintenance-check-latest.json"
$AgentReport = Join-Path $ReportDir "resident-agent-latest.json"
$MarketplacePreflightReport = Join-Path $ReportDir "marketplace-preflight-latest.json"
$MarketplaceTransactionReport = Join-Path $ReportDir "marketplace-transaction-latest.json"
$SpicetifyPreflightReport = Join-Path $ReportDir "spicetify-preflight-latest.json"
$SpicetifyTransactionReport = Join-Path $ReportDir "spicetify-transaction-latest.json"
$SpicetifyTransactionPath = Join-Path $Root "spicetify-last-transaction.json"
$SpotifyPreflightReport = Join-Path $ReportDir "spotify-preflight-latest.json"
$SpotifyTransactionReport = Join-Path $ReportDir "spotify-transaction-latest.json"
$SpotifyTransactionPath = Join-Path $Root "spotify-last-transaction.json"
$SpotifyInstallerCacheDir = Join-Path $Root "cache\spotify-installers"
$SpotifyBackupRoot = Join-Path $BackupDir "spotify-transactions"
$SpotifyTransactionalUpdatesReady = $true
$AgentMutationDefault = $false
$script:R135ActiveOwnerAttempt = $false
$script:R135AttemptCalls = 0
$script:R135ClaimSHA = $null
$script:R135OwnerId = $null
$AgentDiscoveryIntervalHours = 12

New-Item -ItemType Directory -Force -Path $Root,$LogDir,$BackupDir,$ReportDir | Out-Null
$LogPath = Join-Path $LogDir ("spotify-control-{0}.log" -f (Get-Date -Format "yyyy-MM-dd"))

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO","WARN","ERROR")] [string]$Level = "INFO"
    )
    $line = "{0} [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
    if ($Host.Name -ne "Default Host") { Write-Host $line }
}

function Write-ActionError {
    param([string]$ActionName, $ErrorRecord)
    $safeName = ($ActionName.ToLower() -replace '[^a-z0-9_-]','')
    $path = Join-Path $LogDir ($safeName + "-error.log")
    $body = @(
        "Spotify Control v$ScriptVersion action '$ActionName' failed."
        "Time: $(Get-Date -Format o)"
        ""
        "Error:"
        ($ErrorRecord | Out-String)
        ""
        "Main log:"
        $LogPath
    ) -join [Environment]::NewLine
    $body | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function Enter-SpotifyControlMutex {
    param([ValidateSet("Maintenance","AgentTick")][string]$Purpose)
    try {
        $sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $safeSid = ([string]$sid -replace '[^A-Za-z0-9]','_')
        $name = "Local\SpotifyControl-{0}-{1}" -f $Purpose,$safeSid
        $mutex = New-Object System.Threading.Mutex($false,$name)
        $acquired = $false
        try {
            $acquired = $mutex.WaitOne(0,$false)
        } catch [System.Threading.AbandonedMutexException] {
            $acquired = $true
        }
        if (-not $acquired) {
            $mutex.Dispose()
            return $null
        }
        return $mutex
    } catch {
        Write-Log "Could not acquire $Purpose single-instance mutex: $($_.Exception.Message)" "WARN"
        return $null
    }
}

function Exit-SpotifyControlMutex {
    param($Mutex)
    if ($null -eq $Mutex) { return }
    try { $Mutex.ReleaseMutex() } catch {}
    try { $Mutex.Dispose() } catch {}
}

function Load-State {
    if (Test-UsablePath -Path $StatePath -PathType "Leaf") {
        try { return (Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json) }
        catch { throw "Spotify Control state file is unreadable; refusing to replace it with an empty state: $($_.Exception.Message)" }
    }
    return [pscustomobject]@{
        schema = 20
        last_spicetify_upgrade_check = $null
        spicetify_installed_version = $null
        spicetify_compat_tag = $null
        spicetify_compat_min_windows = $null
        spicetify_latest_tag = $null
        pending_spicetify_tag = $null
        pending_spicetify_digest = $null
        spicetify_last_digest = $null
        spicetify_last_transaction_id = $null
        spicetify_last_transaction_status = $null
        spicetify_last_transaction_utc = $null
        spicetify_install_mode = $null
        last_marketplace_check = $null
        last_marketplace_discovery_check = $null
        last_spotify_version = $null
        last_config_hash = $null
        marketplace_remote_tag = $null
        last_success_utc = $null
        pending_auto_repair = $false
        last_guard_check = $null
        guard_blocked = $null
        guard_reason = $null
        current_spotify_supported = $null
        spicetify_max_windows = $null
        spotify_candidate_version = $null
        spotify_candidate_fullversion = $null
        spotify_candidate_etag = $null
        spotify_candidate_sha256 = $null
        spotify_candidate_size = $null
        pending_spotify_update = $false
        spotify_last_installer_sha256 = $null
        spotify_last_transaction_id = $null
        spotify_last_transaction_status = $null
        spotify_last_transaction_utc = $null
        guard_desired = $null
        guard_enforced = $null
        guard_enforcement_ok = $null
        guard_method = $null
        update_patch_state = $null
        update_acl_state = $null
        last_check_only_utc = $null
        last_check_only_while_running = $null
        maintenance_check_healthy = $null
        pending_maintenance = $false
        pending_reasons = @()
        pending_spicetify_upgrade = $false
        pending_spicetify_repair = $false
        pending_direct_extension_repair_count = 0
        pending_direct_extension_blocked_count = 0
        pending_direct_extension_unknown_count = 0
        pending_marketplace_update = $false
        pending_marketplace_tag = $null
        pending_marketplace_digest = $null
        marketplace_last_digest = $null
        marketplace_last_transaction_id = $null
        marketplace_last_transaction_status = $null
        marketplace_last_transaction_utc = $null
        pending_addon_updates = 0
        pending_guard_desired = $null
        pending_guard_reason = $null
        pending_addon_auto_ambiguous = 0
        pending_addon_nonauto_ambiguous = 0
        last_self_update_check = $null
        self_update_bootstrap_version = $null
        self_update_latest_version = $null
        self_update_source_commit = $null
        self_update_payload_set_sha256 = $null
        pending_self_update = $false
        self_update_last_transaction_id = $null
        self_update_last_transaction_status = $null
        self_update_last_transaction_utc = $null
        agent_mutation_enabled = $AgentMutationDefault
        last_agent_tick_utc = $null
        last_agent_event = $null
        last_agent_decision = $null
        agent_version = "0.1.1"
    }
}

function Ensure-StateShape {
    param($State)
    $defaults = [ordered]@{
        schema = 20
        last_spicetify_upgrade_check = $null
        spicetify_installed_version = $null
        spicetify_compat_tag = $null
        spicetify_compat_min_windows = $null
        spicetify_latest_tag = $null
        pending_spicetify_tag = $null
        pending_spicetify_digest = $null
        spicetify_last_digest = $null
        spicetify_last_transaction_id = $null
        spicetify_last_transaction_status = $null
        spicetify_last_transaction_utc = $null
        spicetify_install_mode = $null
        last_marketplace_check = $null
        last_marketplace_discovery_check = $null
        last_spotify_version = $null
        last_config_hash = $null
        marketplace_remote_tag = $null
        last_success_utc = $null
        pending_auto_repair = $false
        last_guard_check = $null
        guard_blocked = $null
        guard_reason = $null
        current_spotify_supported = $null
        spicetify_max_windows = $null
        spotify_candidate_version = $null
        spotify_candidate_fullversion = $null
        spotify_candidate_etag = $null
        spotify_candidate_sha256 = $null
        spotify_candidate_size = $null
        pending_spotify_update = $false
        spotify_last_installer_sha256 = $null
        spotify_last_transaction_id = $null
        spotify_last_transaction_status = $null
        spotify_last_transaction_utc = $null
        guard_desired = $null
        guard_enforced = $null
        guard_enforcement_ok = $null
        guard_method = $null
        update_patch_state = $null
        update_acl_state = $null
        last_check_only_utc = $null
        last_check_only_while_running = $null
        maintenance_check_healthy = $null
        pending_maintenance = $false
        pending_reasons = @()
        pending_spicetify_upgrade = $false
        pending_spicetify_repair = $false
        pending_direct_extension_repair_count = 0
        pending_direct_extension_blocked_count = 0
        pending_direct_extension_unknown_count = 0
        pending_marketplace_update = $false
        pending_marketplace_tag = $null
        pending_marketplace_digest = $null
        marketplace_last_digest = $null
        marketplace_last_transaction_id = $null
        marketplace_last_transaction_status = $null
        marketplace_last_transaction_utc = $null
        pending_addon_updates = 0
        pending_guard_desired = $null
        pending_guard_reason = $null
        pending_addon_auto_ambiguous = 0
        pending_addon_nonauto_ambiguous = 0
        last_self_update_check = $null
        self_update_bootstrap_version = $null
        self_update_latest_version = $null
        self_update_source_commit = $null
        self_update_payload_set_sha256 = $null
        pending_self_update = $false
        self_update_last_transaction_id = $null
        self_update_last_transaction_status = $null
        self_update_last_transaction_utc = $null
        agent_mutation_enabled = $AgentMutationDefault
        last_agent_tick_utc = $null
        last_agent_event = $null
        last_agent_decision = $null
        agent_version = "0.1.1"
    }
    foreach ($name in $defaults.Keys) {
        if (-not $State.PSObject.Properties[$name]) {
            $State | Add-Member -NotePropertyName $name -NotePropertyValue $defaults[$name]
        }
    }
    $State.schema = 20
    if ($null -eq $State.pending_reasons) { $State.pending_reasons = @() }
    return $State
}

function Save-State {
    param($State)
    $State = Ensure-StateShape $State
    $State | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $StatePath -Encoding UTF8
}

function Migrate-StateFromLog {
    param($State)
    $State = Ensure-StateShape $State
    if (-not (Test-UsablePath -Path $LogPath -PathType "Leaf")) { return $State }

    try {
        $log = Get-Content -LiteralPath $LogPath -Raw

        if (-not $State.marketplace_remote_tag) {
            $matches = [regex]::Matches($log, 'Marketplace updated to (v[0-9][0-9A-Za-z.\-_]*)')
            if ($matches.Count -gt 0) {
                $State.marketplace_remote_tag = $matches[$matches.Count - 1].Groups[1].Value
                $State.last_marketplace_check = [DateTimeOffset]::UtcNow.ToString("o")
                Write-Log "Recovered Marketplace state from previous successful update log: $($State.marketplace_remote_tag)"
            }
        }

        if (-not $State.last_spicetify_upgrade_check -and $log -match 'Spicetify is up-to-date') {
            $State.last_spicetify_upgrade_check = [DateTimeOffset]::UtcNow.ToString("o")
            Write-Log "Recovered recent Spicetify upgrade-check state from log."
        }
    } catch {
        Write-Log "Could not migrate previous state from log; continuing safely." "WARN"
    }
    return $State
}

function Test-Due {
    param([object]$Value, [int]$Days)
    if ($Force -or -not $Value) { return $true }
    try {
        $last = [DateTimeOffset]::Parse([string]$Value)
        return (([DateTimeOffset]::UtcNow - $last).TotalDays -ge $Days)
    } catch { return $true }
}

function Test-DueHours {
    param([object]$Value, [int]$Hours)
    if ($Force -or -not $Value) { return $true }
    try {
        $last = [DateTimeOffset]::Parse([string]$Value)
        return (([DateTimeOffset]::UtcNow - $last).TotalHours -ge $Hours)
    } catch { return $true }
}

function Get-SpicetifyCommand {
    $cmd = Get-Command spicetify -ErrorAction SilentlyContinue
    if (-not $cmd) { return $null }
    return $cmd.Source
}
$script:Spicetify = Get-SpicetifyCommand
$script:LastGuardResult = $null

function ConvertTo-NativeQuotedArgument {
    param([AllowEmptyString()][string]$Value)

    if ($null -eq $Value -or $Value.Length -eq 0) { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }

    # Windows CommandLineToArgvW-compatible quoting.
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    $slashes = 0
    foreach ($ch in $Value.ToCharArray()) {
        if ($ch -eq '\') {
            $slashes++
            continue
        }
        if ($ch -eq '"') {
            if ($slashes -gt 0) { [void]$sb.Append(('\' * ($slashes * 2))) }
            [void]$sb.Append('\"')
            $slashes = 0
            continue
        }
        if ($slashes -gt 0) {
            [void]$sb.Append(('\' * $slashes))
            $slashes = 0
        }
        [void]$sb.Append($ch)
    }
    if ($slashes -gt 0) { [void]$sb.Append(('\' * ($slashes * 2))) }
    [void]$sb.Append('"')
    return $sb.ToString()
}

function Invoke-NativeCapture {
    param(
        [Parameter(Mandatory=$true)][string]$FilePath,
        [string[]]$Arguments = @()
    )

    # Do NOT invoke native programs through PowerShell's error stream.
    # Windows PowerShell 5.1 can turn native stderr into NativeCommandError when
    # $ErrorActionPreference='Stop', even when the native process itself is fine.
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.Arguments = (($Arguments | ForEach-Object { ConvertTo-NativeQuotedArgument ([string]$_) }) -join ' ')

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi

    try {
        if (-not $proc.Start()) {
            return [pscustomobject]@{
                ExitCode = 126
                StdOut = ""
                StdErr = "Failed to start native process."
                Output = "Failed to start native process."
            }
        }

        # Async ReadToEnd prevents stdout/stderr pipe deadlocks.
        $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
        $stderrTask = $proc.StandardError.ReadToEndAsync()
        $proc.WaitForExit()
        $stdout = $stdoutTask.Result
        $stderr = $stderrTask.Result
        $code = $proc.ExitCode

        $parts = @()
        if (-not [string]::IsNullOrWhiteSpace($stdout)) { $parts += $stdout.Trim() }
        if (-not [string]::IsNullOrWhiteSpace($stderr)) { $parts += $stderr.Trim() }

        return [pscustomobject]@{
            ExitCode = $code
            StdOut = $stdout
            StdErr = $stderr
            Output = ($parts -join [Environment]::NewLine)
        }
    } catch {
        return [pscustomobject]@{
            ExitCode = 126
            StdOut = ""
            StdErr = $_.Exception.Message
            Output = $_.Exception.Message
        }
    } finally {
        if ($proc) { $proc.Dispose() }
    }
}

function Invoke-SelfUpdaterJsonAction {
    param(
        [ValidateSet("Check","Update","RollbackTest","Rollback","SelfTest","Status")][string]$SelfAction,
        [switch]$ForceSelf
    )
    if (-not (Test-UsablePath -Path $SelfUpdater -PathType "Leaf")) {
        return [pscustomobject]@{ ExitCode=127; Report=$null; Output="Self-updater bootstrap missing: $SelfUpdater" }
    }
    $ps = Join-Path $PSHOME "powershell.exe"
    if (-not (Test-UsablePath -Path $ps -PathType "Leaf")) { $ps=(Get-Command powershell.exe -ErrorAction Stop).Path }
    $args=@("-NoProfile","-ExecutionPolicy","Bypass","-File",$SelfUpdater,"-Action",$SelfAction,"-Json")
    if ($ForceSelf) { $args += "-Force" }
    $r=Invoke-NativeCapture -FilePath $ps -Arguments $args
    $report=$null
    if (-not [string]::IsNullOrWhiteSpace($r.Output)) {
        $lines=@($r.Output -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        foreach($line in @($lines | Select-Object -Last 5)) {
            try { $report=$line | ConvertFrom-Json; if($report){break} } catch {}
        }
    }
    return [pscustomobject]@{ ExitCode=[int]$r.ExitCode; Report=$report; Output=[string]$r.Output }
}

function Get-SelfUpdateCheckResult {
    $r=Invoke-SelfUpdaterJsonAction -SelfAction "Check"
    # The official v1.0.6 bootstrap authenticated the stable manifest and
    # then refused a forward-only plan because a private, exact version is
    # already ahead of published stable. This is NOT a failed Spicetify check.
    # Never treat an arbitrary bootstrap/network/integrity error as benign.
    $privateAhead=$false
    if ($r.ExitCode -eq 1 -and $null -ne $r.Report -and
        $r.Report.success -eq $false -and
        [string]$r.Report.action -ceq "Check" -and
        [string]$r.Report.bootstrap_version -ceq "1.0.6" -and
        [string]$r.Report.installed_version -ceq "0.6.30" -and
        [string]$ScriptVersion -ceq "0.6.30" -and
        [string]$r.Report.manifest_url -ceq
          "https://raw.githubusercontent.com/sdsssdvx2/spotify-control-updates/main/manifest.json" -and
        [string]$r.Report.error -ceq
          "Automatic Spotify Control downgrade refused: installed=0.6.30 latest=0.6.28" -and
        [string]$r.Report.transaction_status -cin @("","committed")) {
        try {
            $boot=(Get-Item -LiteralPath $SelfUpdater -Force -ErrorAction Stop)
            if (-not $boot.PSIsContainer -and
                ($boot.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -and
                [long]$boot.Length -eq 42963 -and
                (Get-FileHash -LiteralPath $SelfUpdater -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant() -ceq
                "d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6") {
                $privateAhead=$true
            }
        } catch { $privateAhead=$false }
    }
    if ($privateAhead) {
        return [pscustomobject]@{
            Verified=$false;TrustedStableBehindPrivate=$true;
            UpdateAvailable=$false;InstalledVersion=$ScriptVersion;
            LatestVersion="0.6.28";BootstrapVersion="1.0.6";
            SourceCommit=$null;PayloadSetSha256=$null;
            TransactionId=[string]$r.Report.transaction_id;
            TransactionStatus=[string]$r.Report.transaction_status;
            Error="trusted-private-version-ahead-of-public-stable-self-update-disabled"
        }
    }
    if ($r.ExitCode -ne 0 -or $null -eq $r.Report -or -not [bool]$r.Report.success) {
        $detail=if($r.Report -and $r.Report.error){[string]$r.Report.error}else{[string]$r.Output}
        return [pscustomobject]@{ Verified=$false; TrustedStableBehindPrivate=$false; UpdateAvailable=$false; InstalledVersion=$ScriptVersion; LatestVersion=$null; BootstrapVersion=$null; SourceCommit=$null; PayloadSetSha256=$null; TransactionId=$null; TransactionStatus=$null; Error=$detail }
    }
    $x=$r.Report.result
    return [pscustomobject]@{
        Verified=$true
        TrustedStableBehindPrivate=$false
        UpdateAvailable=[bool]$x.update_available
        InstalledVersion=[string]$x.installed_version
        LatestVersion=[string]$x.latest_version
        BootstrapVersion=[string]$x.bootstrap_version
        SourceCommit=[string]$x.source_commit
        PayloadSetSha256=[string]$x.payload_set_sha256
        TransactionId=[string]$r.Report.transaction_id
        TransactionStatus=[string]$r.Report.transaction_status
        Error=$null
    }
}

function Invoke-SelfUpdateMutation {
    param([ValidateSet("Update","RollbackTest","Rollback")][string]$SelfAction,[switch]$ForceSelf)
    if (Test-SpotifyRunning) { throw "Spotify Control self-update mutation requires Spotify to be fully closed." }
    $r=Invoke-SelfUpdaterJsonAction -SelfAction $SelfAction -ForceSelf:$ForceSelf
    if ($r.ExitCode -ne 0 -or $null -eq $r.Report -or -not [bool]$r.Report.success) {
        $detail=if($r.Report -and $r.Report.error){[string]$r.Report.error}else{[string]$r.Output}
        throw "Spotify Control self-update bootstrap failed: $detail"
    }
    return $r.Report
}

function Invoke-SpiceCapture {
    param([string[]]$Arguments)
    if (-not $script:Spicetify) {
        return [pscustomobject]@{
            ExitCode = 127
            StdOut = ""
            StdErr = "spicetify not found"
            Output = "spicetify not found"
        }
    }
    return Invoke-NativeCapture -FilePath $script:Spicetify -Arguments $Arguments
}

function Invoke-Spice {
    param([string[]]$Arguments, [switch]$AllowFailure)
    $r = Invoke-SpiceCapture -Arguments $Arguments

    if ($r.Output) {
        $clean = $r.Output -replace "`e\[[\d;]*[A-Za-z]", "" -replace "`r?`n"," | "
        $level = if ($r.ExitCode -eq 0) { "INFO" } else { "WARN" }
        Write-Log ("spicetify {0} [exit={1}]: {2}" -f ($Arguments -join " "), $r.ExitCode, $clean) $level
    } else {
        Write-Log ("spicetify {0} [exit={1}]" -f ($Arguments -join " "), $r.ExitCode)
    }

    if ($r.ExitCode -ne 0 -and -not $AllowFailure) {
        throw "spicetify failed ($($r.ExitCode)): $($Arguments -join ' ')`n$($r.Output)"
    }
    return $r
}

function Get-InstalledSpicetifyVersion {
    if (-not $script:Spicetify) { return $null }
    $r = Invoke-SpiceCapture -Arguments @("--version")
    if ($r.ExitCode -ne 0) { return $null }
    $m = [regex]::Match([string]$r.Output, '(?<!\d)(?<v>\d+\.\d+\.\d+(?:\.\d+)?)(?!\d)')
    if (-not $m.Success) { return $null }
    return $m.Groups["v"].Value
}

function Get-MaintenanceMode {
    param([bool]$SpotifyRunning)
    if ($SpotifyRunning) { return "check-only" }
    return "check+mutation"
}

function Normalize-MarketplaceTag {
    param([AllowNull()][AllowEmptyString()][string]$Tag)
    if ([string]::IsNullOrWhiteSpace($Tag)) { return $null }
    return $Tag.Trim().TrimEnd('.')
}

function Get-MarketplaceLatestReleaseInfo {
    $result = [ordered]@{
        Verified=$false; Tag=$null; AssetUrl=$null; AssetDigest=$null; AssetSize=$null
        AssetId=$null; PublishedAt=$null; Error=$null
    }
    try {
        $release = Invoke-RestMethod `
            -Uri "https://api.github.com/repos/spicetify/marketplace/releases/latest" `
            -Headers @{ "User-Agent"="SpotifyControl/$ScriptVersion"; "Accept"="application/vnd.github+json" }
        $tag = Normalize-MarketplaceTag ([string]$release.tag_name)
        if ([string]::IsNullOrWhiteSpace($tag)) { throw "Latest Marketplace release has no tag." }
        if ([bool]$release.draft -or [bool]$release.prerelease) { throw "Latest Marketplace response is draft/prerelease; refusing automatic update." }

        $assets = @($release.assets | Where-Object { [string]$_.name -eq "marketplace.zip" -and [string]$_.state -eq "uploaded" })
        if ($assets.Count -ne 1) { throw "Expected exactly one uploaded marketplace.zip release asset; found $($assets.Count)." }
        $asset = $assets[0]
        $digest = ([string]$asset.digest).Trim().ToLowerInvariant()
        if ($digest -notmatch '^sha256:[0-9a-f]{64}$') { throw "Marketplace release asset is missing a valid published SHA-256 digest." }
        $url = [string]$asset.browser_download_url
        if ($url -notmatch '^https://github\.com/spicetify/marketplace/releases/download/') { throw "Marketplace release asset URL is not the official GitHub release path." }
        if ([int64]$asset.size -le 0) { throw "Marketplace release asset has an invalid size." }

        $result.Tag = $tag
        $result.AssetUrl = $url
        $result.AssetDigest = $digest
        $result.AssetSize = [int64]$asset.size
        $result.AssetId = [string]$asset.id
        $result.PublishedAt = [string]$release.published_at
        $result.Verified = $true
    } catch {
        $result.Error = $_.Exception.Message
    }
    return [pscustomobject]$result
}

function Get-MarketplaceInstallResolution {
    $roots = New-Object System.Collections.Generic.List[string]
    foreach ($rootCandidate in @(
        (Join-Path $env:LOCALAPPDATA "spicetify"),
        (Join-Path $env:APPDATA "spicetify")
    )) {
        if (-not [string]::IsNullOrWhiteSpace($rootCandidate) -and -not $roots.Contains($rootCandidate)) { $roots.Add($rootCandidate) }
    }
    $config = Get-ConfigPath
    if ($config) {
        $configRoot = Split-Path -Parent $config
        if ($configRoot -and -not $roots.Contains($configRoot)) { $roots.Add($configRoot) }
    }
    $locations = @()
    foreach ($rootCandidate in @($roots)) {
        $candidate = Join-Path $rootCandidate "CustomApps\marketplace"
        if (Test-UsablePath -Path $candidate -PathType "Container") { $locations += $candidate }
    }
    return [pscustomobject]@{
        Status=$(if($locations.Count -eq 1){"resolved"}elseif($locations.Count -eq 0){"absent"}else{"ambiguous"})
        Path=$(if($locations.Count -eq 1){$locations[0]}else{$null})
        Locations=@($locations)
        ConfigPath=$config
    }
}

function Get-DirectoryTreeSha256 {
    param([string]$Path)
    if (-not (Test-UsablePath -Path $Path -PathType "Container")) { return $null }
    $lines = New-Object System.Collections.Generic.List[string]
    $sep = [System.IO.Path]::DirectorySeparatorChar
    $base = (Get-Item -LiteralPath $Path).FullName.TrimEnd($sep)
    foreach ($file in @(Get-ChildItem -LiteralPath $Path -File -Recurse -Force | Sort-Object FullName)) {
        $relative = $file.FullName.Substring($base.Length).TrimStart($sep).Replace($sep,[char]'/')
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $lines.Add(($relative + "`t" + $file.Length + "`t" + $hash))
    }
    $text = [string]::Join("`n", @($lines))
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','') } finally { $sha.Dispose() }
}

function Test-MarketplacePayload {
    param([string]$Path)
    $result = [ordered]@{ Valid=$false; Error=$null; TreeSha256=$null; FileCount=0 }
    try {
        if (-not (Test-UsablePath -Path $Path -PathType "Container")) { throw "payload directory missing" }
        $required = @("index.js","extension.js","style.css","manifest.json")
        foreach ($name in $required) {
            $f = Join-Path $Path $name
            if (-not (Test-UsablePath -Path $f -PathType "Leaf")) { throw "required file missing: $name" }
            if ((Get-Item -LiteralPath $f).Length -le 0) { throw "required file is empty: $name" }
        }
        $manifest = Get-Content -LiteralPath (Join-Path $Path "manifest.json") -Raw | ConvertFrom-Json
        $manifestName = ""
        if ($manifest.name -is [string]) { $manifestName = [string]$manifest.name }
        elseif ($manifest.name -and $manifest.name.PSObject.Properties['en']) { $manifestName = [string]$manifest.name.en }
        if ($manifestName -notmatch '(?i)marketplace') { throw "manifest does not identify Marketplace" }
        $result.TreeSha256 = Get-DirectoryTreeSha256 -Path $Path
        if ([string]::IsNullOrWhiteSpace($result.TreeSha256)) { throw "could not compute staged tree hash" }
        $result.FileCount = @(Get-ChildItem -LiteralPath $Path -File -Recurse -Force).Count
        if ($result.FileCount -lt 4) { throw "payload contains too few files" }
        $result.Valid = $true
    } catch { $result.Error = $_.Exception.Message }
    return [pscustomobject]$result
}

function Test-SpotifyControlZipArchiveSafety {
    param(
        [string]$ZipPath,
        [string]$Label='Archive',
        [int]$MaxEntries=16384,
        [int64]$MaxEntryBytes=134217728,
        [int64]$MaxExpandedBytes=536870912
    )
    if (-not (Test-Path -LiteralPath $ZipPath -PathType Leaf)) { throw "$Label ZIP is missing." }
    if ($MaxEntries -lt 1 -or $MaxEntryBytes -lt 1 -or $MaxExpandedBytes -lt 1) { throw "$Label ZIP safety limits are invalid." }
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    $archive=[System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try {
        [int]$count=0
        [int64]$expanded=0
        $seen=New-Object -TypeName 'System.Collections.Generic.HashSet[string]' -ArgumentList ([System.StringComparer]::OrdinalIgnoreCase)
        foreach($entry in @($archive.Entries)) {
            $count++
            if($count -gt $MaxEntries){throw "$Label ZIP entry count exceeds the safety limit."}
            $raw=([string]$entry.FullName).Replace('\','/')
            if([string]::IsNullOrWhiteSpace($raw)){throw "$Label ZIP contains an empty entry path."}
            if($raw.StartsWith('/') -or $raw -match '^[A-Za-z]:' -or $raw.Contains(':')){throw "$Label ZIP contains an unsafe absolute/device path: $raw"}
            $isDirectory=$raw.EndsWith('/')
            $name=$raw.TrimEnd('/')
            if([string]::IsNullOrWhiteSpace($name)){throw "$Label ZIP contains an unsafe empty path: $raw"}
            $parts=$name.Split('/')
            if(@($parts | Where-Object { $_ -eq '' -or $_ -eq '.' -or $_ -eq '..' }).Count -gt 0){throw "$Label ZIP contains an unsafe path component: $raw"}
            if(-not $seen.Add($name)){throw "$Label ZIP contains a duplicate/case-colliding path: $name"}
            $unixMode=(($entry.ExternalAttributes -shr 16) -band 0xF000)
            if($unixMode -eq 0xA000){throw "$Label ZIP contains a symlink entry: $raw"}
            if(-not $isDirectory){
                $entryLength=[int64]$entry.Length
                if($entryLength -lt 0 -or $entryLength -gt $MaxEntryBytes){throw "$Label ZIP entry exceeds the per-entry safety limit: $raw"}
                $expanded += $entryLength
                if($expanded -gt $MaxExpandedBytes){throw "$Label ZIP expanded-byte total exceeds the safety limit."}
            }
        }
        if($count -lt 1){throw "$Label ZIP contains no entries."}
        return [pscustomobject]@{EntryCount=$count;ExpandedBytes=$expanded}
    } finally {
        $archive.Dispose()
    }
}

function Expand-AndValidateMarketplaceAsset {
    param($ReleaseInfo,[string]$WorkRoot)
    $zip = Join-Path $WorkRoot "marketplace.zip"
    $extract = Join-Path $WorkRoot "extract"
    New-Item -ItemType Directory -Force -Path $extract | Out-Null
    Invoke-WebRequest -Uri $ReleaseInfo.AssetUrl -Headers @{ "User-Agent"="SpotifyControl/$ScriptVersion" } -OutFile $zip -UseBasicParsing
    $actualDigest = "sha256:" + ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant())
    if ($actualDigest -cne ([string]$ReleaseInfo.AssetDigest).ToLowerInvariant()) {
        throw "Marketplace published digest mismatch. expected=$($ReleaseInfo.AssetDigest) actual=$actualDigest"
    }
    if ((Get-Item -LiteralPath $zip).Length -ne [int64]$ReleaseInfo.AssetSize) {
        throw "Marketplace asset size mismatch. expected=$($ReleaseInfo.AssetSize) actual=$((Get-Item -LiteralPath $zip).Length)"
    }
    $archiveSafety = Test-SpotifyControlZipArchiveSafety -ZipPath $zip -Label 'Marketplace' -MaxEntries 16384 -MaxEntryBytes 134217728 -MaxExpandedBytes 536870912
    Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force
    $source = Join-Path $extract "marketplace-dist"
    if (-not (Test-UsablePath -Path $source -PathType "Container")) {
        $candidates = @(Get-ChildItem -LiteralPath $extract -Directory -Recurse | Where-Object {
            Test-Path -LiteralPath (Join-Path $_.FullName "index.js") -PathType Leaf
        })
        if ($candidates.Count -ne 1) { throw "Marketplace archive layout is ambiguous; expected one app root, found $($candidates.Count)." }
        $source = $candidates[0].FullName
    }
    $validation = Test-MarketplacePayload -Path $source
    if (-not $validation.Valid) { throw "Marketplace staged payload validation failed: $($validation.Error)" }
    return [pscustomobject]@{ Zip=$zip; Source=$source; ActualDigest=$actualDigest; Validation=$validation }
}

function Test-MarketplaceSwapRollbackSandbox {
    $resolution = Get-MarketplaceInstallResolution
    if ($resolution.Status -ne "resolved") { return [pscustomobject]@{ Pass=$false; Detail="Marketplace not uniquely resolved: $($resolution.Status)" } }
    $baseValidation = Test-MarketplacePayload -Path $resolution.Path
    if (-not $baseValidation.Valid) { return [pscustomobject]@{ Pass=$false; Detail="Installed payload invalid: $($baseValidation.Error)" } }
    $testRoot = Join-Path $Root ("transaction-tests\marketplace-" + [guid]::NewGuid().ToString("N"))
    $target = Join-Path $testRoot "marketplace"
    $stage = Join-Path $testRoot ".stage"
    $old = Join-Path $testRoot ".old"
    try {
        New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
        Copy-Item -LiteralPath $resolution.Path -Destination $target -Recurse -Force
        Copy-Item -LiteralPath $resolution.Path -Destination $stage -Recurse -Force
        Add-Content -LiteralPath (Join-Path $stage "README.md") -Value "`n<!-- SpotifyControl transaction sandbox marker -->" -Encoding UTF8
        $before = Test-MarketplacePayload -Path $target
        $candidate = Test-MarketplacePayload -Path $stage
        if (-not $before.Valid -or -not $candidate.Valid -or $before.TreeSha256 -eq $candidate.TreeSha256) { throw "sandbox setup failed to produce two valid distinct trees" }
        Move-Item -LiteralPath $target -Destination $old
        Move-Item -LiteralPath $stage -Destination $target
        $during = Test-MarketplacePayload -Path $target
        if (-not $during.Valid -or $during.TreeSha256 -ne $candidate.TreeSha256) { throw "sandbox swap verification failed" }
        Remove-Item -LiteralPath $target -Recurse -Force
        Move-Item -LiteralPath $old -Destination $target
        $after = Test-MarketplacePayload -Path $target
        if (-not $after.Valid -or $after.TreeSha256 -ne $before.TreeSha256) { throw "sandbox rollback failed to restore original tree" }
        return [pscustomobject]@{ Pass=$true; Detail="same-volume swap+rollback restored tree $($after.TreeSha256)" }
    } catch {
        return [pscustomobject]@{ Pass=$false; Detail=$_.Exception.Message }
    } finally {
        Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-MarketplacePreflight {
    $work = Join-Path $env:TEMP ("SpotifyControl-Marketplace-Preflight-" + [guid]::NewGuid().ToString("N"))
    $report = [ordered]@{ schema=1; time_utc=[DateTimeOffset]::UtcNow.ToString("o"); verified=$false; tag=$null; published_digest=$null; actual_digest=$null; asset_size=$null; file_count=0; tree_sha256=$null; error=$null }
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    try {
        $info = Get-MarketplaceLatestReleaseInfo
        if (-not $info.Verified) { throw $info.Error }
        $report.tag=$info.Tag; $report.published_digest=$info.AssetDigest; $report.asset_size=$info.AssetSize
        $payload = Expand-AndValidateMarketplaceAsset -ReleaseInfo $info -WorkRoot $work
        $report.actual_digest=$payload.ActualDigest; $report.file_count=$payload.Validation.FileCount; $report.tree_sha256=$payload.Validation.TreeSha256; $report.verified=$true
        Write-Log "Marketplace preflight verified $($info.Tag): published digest matched; staged payload valid; files=$($payload.Validation.FileCount)."
    } catch {
        $report.error=$_.Exception.Message
        Write-Log "Marketplace preflight failed: $($report.error)" "WARN"
    } finally {
        $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $MarketplacePreflightReport -Encoding UTF8
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (-not $report.verified) { throw "Marketplace preflight failed: $($report.error)" }
    return [pscustomobject]$report
}
function Get-DirectExtensionPolicyCounts {
    param([object[]]$Items)
    $all=@($Items)
    $repair=@($all | Where-Object { $_.policy -eq 'spicetify-release-owned' -and [string]$_.status -like 'repair-needed-*' })
    $blocked=@($all | Where-Object { $_.policy -eq 'spicetify-release-owned' -and [string]$_.status -like 'repair-blocked-*' })
    $unknown=@($all | Where-Object { $_.policy -eq 'unknown-source' -and $_.kind -eq 'extension' })
    $rescue=@($all | Where-Object { $_.policy -eq 'rescue-copy-cleanup-only' -and $_.kind -eq 'extension' -and $_.installed -eq $true })
    return [pscustomobject]@{
        RepairCount=$repair.Count; BlockedCount=$blocked.Count; UnknownCount=$unknown.Count; RescueCount=$rescue.Count
        RepairItems=@($repair); BlockedItems=@($blocked); UnknownItems=@($unknown); RescueItems=@($rescue)
    }
}

function Get-AddonPendingSummary {
    $path = Join-Path $ReportDir "addons-latest.json"
    $result = [ordered]@{
        ReportPath=$path; ReportPresent=$false; AutoUpdateCount=0; CheckErrorCount=0; BlockedAutoCount=0
        AmbiguousCount=0; AutoAmbiguousCount=0; NonAutoAmbiguousCount=0
        DirectExtensionRepairCount=0; DirectExtensionBlockedCount=0; DirectExtensionUnknownCount=0; DirectExtensionRescueCount=0
        DirectExtensionRepairItems=@(); DirectExtensionBlockedItems=@(); DirectExtensionUnknownItems=@()
        AmbiguousItems=@(); BlockedAutoItems=@(); Error=$null
    }
    if (-not (Test-UsablePath -Path $path -PathType "Leaf")) { return [pscustomobject]$result }
    try {
        $report = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $items = @($report.items)
        $result.ReportPresent = $true
        $result.AutoUpdateCount = @($items | Where-Object { $_.policy -eq "auto" -and $_.status -eq "update-available" -and $_.installed -eq $true }).Count
        $result.CheckErrorCount = @($items | Where-Object { $_.status -eq "check-error" }).Count
        $blockedAuto = @($items | Where-Object { $_.policy -eq "auto" -and [string]$_.status -like "update-blocked-*" })
        $result.BlockedAutoCount = $blockedAuto.Count
        $result.BlockedAutoItems = @($blockedAuto | ForEach-Object { [pscustomobject]@{ name=[string]$_.name; status=[string]$_.status; local_safety=[string]$_.local_safety; install_path=[string]$_.install_path } })
        $ambiguous = @($items | Where-Object { [string]$_.status -match "ambiguous" })
        $result.AmbiguousCount = $ambiguous.Count
        $result.AutoAmbiguousCount = @($ambiguous | Where-Object { $_.policy -eq "auto" }).Count
        $result.NonAutoAmbiguousCount = @($ambiguous | Where-Object { $_.policy -ne "auto" }).Count
        $result.AmbiguousItems = @($ambiguous | ForEach-Object {
            [pscustomobject]@{
                name=[string]$_.name
                policy=[string]$_.policy
                status=[string]$_.status
                locations=@($_.locations)
            }
        })
        $direct = Get-DirectExtensionPolicyCounts -Items $items
        $result.DirectExtensionRepairCount = $direct.RepairCount
        $result.DirectExtensionBlockedCount = $direct.BlockedCount
        $result.DirectExtensionUnknownCount = $direct.UnknownCount
        $result.DirectExtensionRescueCount = $direct.RescueCount
        $result.DirectExtensionRepairItems = @($direct.RepairItems | ForEach-Object { [pscustomobject]@{name=[string]$_.name; status=[string]$_.status; local_safety=[string]$_.local_safety; install_path=[string]$_.install_path} })
        $result.DirectExtensionBlockedItems = @($direct.BlockedItems | ForEach-Object { [pscustomobject]@{name=[string]$_.name; status=[string]$_.status; local_safety=[string]$_.local_safety; install_path=[string]$_.install_path} })
        $result.DirectExtensionUnknownItems = @($direct.UnknownItems | ForEach-Object { [pscustomobject]@{name=[string]$_.name; status=[string]$_.status; install_path=[string]$_.install_path; locations=@($_.locations)} })
    } catch {
        $result.Error = $_.Exception.Message
    }
    return [pscustomobject]$result
}


function Test-UsablePath {
    param(
        [AllowNull()][AllowEmptyString()][string]$Path,
        [ValidateSet("Any","Leaf","Container")][string]$PathType = "Any"
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }

    try {
        switch ($PathType) {
            "Leaf"      { return [bool](Test-Path -LiteralPath $Path -PathType Leaf -ErrorAction SilentlyContinue) }
            "Container" { return [bool](Test-Path -LiteralPath $Path -PathType Container -ErrorAction SilentlyContinue) }
            default     { return [bool](Test-Path -LiteralPath $Path -ErrorAction SilentlyContinue) }
        }
    } catch {
        return $false
    }
}

function Get-LastNonEmptyLine {
    param([AllowNull()][AllowEmptyString()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }

    $lines = @(
        $Text -split "`r?`n" |
            ForEach-Object { if ($null -ne $_) { $_.Trim() } } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    if ($lines.Count -eq 0) { return $null }
    return [string]$lines[$lines.Count - 1]
}

function Get-FirstExistingPath {
    param(
        [string[]]$Candidates,
        [ValidateSet("Any","Leaf","Container")][string]$PathType = "Any"
    )

    foreach ($candidate in $Candidates) {
        if (Test-UsablePath -Path $candidate -PathType $PathType) {
            return $candidate
        }
    }
    return $null
}

function Test-SpotifyRunning {
    return [bool](Get-Process Spotify -ErrorAction SilentlyContinue | Select-Object -First 1)
}

function Get-SpotifyExecutable {
    $known = @(
        (Join-Path $env:APPDATA "Spotify\Spotify.exe"),
        (Join-Path $env:LOCALAPPDATA "Spotify\Spotify.exe")
    )

    $knownExe = Get-FirstExistingPath -Candidates $known -PathType "Leaf"
    if ($knownExe) { return $knownExe }

    if ($script:Spicetify) {
        $r = Invoke-SpiceCapture -Arguments @("path")

        foreach ($candidateText in @($r.StdOut, $r.Output, $r.StdErr)) {
            $p = Get-LastNonEmptyLine -Text $candidateText
            if (-not $p) { continue }

            if (Test-UsablePath -Path $p -PathType "Leaf") {
                if ([System.IO.Path]::GetFileName($p) -ieq "Spotify.exe") { return $p }
            }

            if (Test-UsablePath -Path $p -PathType "Container") {
                $exe = Join-Path $p "Spotify.exe"
                if (Test-UsablePath -Path $exe -PathType "Leaf") { return $exe }
            }
        }
    }

    return $null
}

function Get-SpotifyVersion {
    param([AllowNull()][AllowEmptyString()][string]$Exe)
    if (-not (Test-UsablePath -Path $Exe -PathType "Leaf")) { return $null }
    try { return (Get-Item -LiteralPath $Exe).VersionInfo.ProductVersion } catch { return $null }
}

function Get-ConfigPath {
    $fallback = Join-Path $env:APPDATA "spicetify\config-xpui.ini"
    if (Test-UsablePath -Path $fallback -PathType "Leaf") { return $fallback }

    if ($script:Spicetify) {
        $r = Invoke-SpiceCapture -Arguments @("-c")
        foreach ($candidateText in @($r.StdOut, $r.Output, $r.StdErr)) {
            $p = Get-LastNonEmptyLine -Text $candidateText
            if (Test-UsablePath -Path $p -PathType "Leaf") { return $p }
        }
    }

    return $null
}

function Get-IniValue {
    param([string]$Path, [string]$Key)
    if (-not (Test-UsablePath -Path $Path)) { return $null }
    try {
        $text = Get-Content -LiteralPath $Path -Raw
        $m = [regex]::Match($text, "(?im)^\s*" + [regex]::Escape($Key) + "\s*=\s*(.*?)\s*$")
        if ($m.Success) { return $m.Groups[1].Value.Trim() }
    } catch {}
    return $null
}

function Get-FileSha256 {
    param([string]$Path)
    if (-not (Test-UsablePath -Path $Path)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}


function ConvertTo-VersionParts {
    param(
        [AllowNull()][AllowEmptyString()][string]$Version,
        [int]$Count = 4
    )

    if ([string]::IsNullOrWhiteSpace($Version)) { return $null }

    $m = [regex]::Match($Version, '^\s*(\d+)\.(\d+)\.(\d+)(?:\.(\d+))?')
    if (-not $m.Success) { return $null }

    $parts = @(
        [int]$m.Groups[1].Value,
        [int]$m.Groups[2].Value,
        [int]$m.Groups[3].Value,
        $(if ($m.Groups[4].Success) { [int]$m.Groups[4].Value } else { 0 })
    )

    return @($parts | Select-Object -First $Count)
}

function Compare-VersionParts {
    param(
        [string]$A,
        [string]$B,
        [int]$Count = 4
    )

    $left = ConvertTo-VersionParts -Version $A -Count $Count
    $right = ConvertTo-VersionParts -Version $B -Count $Count
    if ($null -eq $left -or $null -eq $right) { return $null }

    for ($i = 0; $i -lt $Count; $i++) {
        if ($left[$i] -lt $right[$i]) { return -1 }
        if ($left[$i] -gt $right[$i]) { return 1 }
    }
    return 0
}

function Test-SpotifyVersionSupported {
    param(
        [string]$SpotifyVersion,
        [string]$MaxSupported
    )

    # Spicetify release notes publish compatibility at major.minor.patch granularity.
    $cmp = Compare-VersionParts -A $SpotifyVersion -B $MaxSupported -Count 3
    if ($null -eq $cmp) { return $false }
    return ($cmp -le 0)
}

function Normalize-Etag {
    param([AllowNull()][AllowEmptyString()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $v = $Value.Trim()
    if ($v.StartsWith("W/")) { $v = $v.Substring(2) }
    return $v.Trim()
}

function ConvertFrom-SpicetifyReleaseCompatibility {
    param($Release,[AllowNull()][AllowEmptyString()][string]$ExpectedTag)

    $result = [ordered]@{
        Verified = $false
        Tag = $null
        Version = $null
        Min = $null
        Max = $null
        PublishedAt = $null
        Error = $null
    }
    try {
        if ($null -eq $Release) { throw "Spicetify release metadata is empty." }
        if ([bool]$Release.draft -or [bool]$Release.prerelease) { throw "Spicetify release is draft/prerelease; refusing trust." }
        $tag = ([string]$Release.tag_name).Trim()
        $tagMatch = [regex]::Match($tag,'^v(?<v>\d+\.\d+\.\d+)$')
        if (-not $tagMatch.Success) { throw "Spicetify release tag is invalid: $tag" }
        if (-not [string]::IsNullOrWhiteSpace($ExpectedTag) -and $tag -cne $ExpectedTag) {
            throw "Spicetify release tag mismatch. expected=$ExpectedTag actual=$tag"
        }
        $body = [string]$Release.body
        if ([string]::IsNullOrWhiteSpace($body)) { throw "Spicetify release has no release body." }
        $compatLine = $body -split "`r?`n" |
            Where-Object { $_ -match 'Spotify\s+for\s+\*\*[^*]*Windows[^*]*\*\*' } |
            Select-Object -First 1
        if (-not $compatLine) { throw "Could not find the Windows compatibility line in Spicetify release $tag." }
        # Do not depend on arrow glyphs or source-file Unicode decoding here.
        # Windows PowerShell 5.1 may read UTF-8-without-BOM scripts through the
        # active ANSI code page.  The compatibility line is trusted only when it
        # contains exactly two major.minor.patch version tokens in ascending order.
        $versionMatches = [regex]::Matches([string]$compatLine,'(?<!\d)(?<v>\d+\.\d+\.\d+)(?!\d)')
        if ($versionMatches.Count -ne 2) {
            throw "Could not parse exactly two Windows compatibility versions: $compatLine"
        }
        $minVersion = $versionMatches[0].Groups['v'].Value
        $maxVersion = $versionMatches[1].Groups['v'].Value
        $rangeCmp = Compare-VersionParts -A $minVersion -B $maxVersion -Count 3
        if ($null -eq $rangeCmp -or $rangeCmp -gt 0) {
            throw "Windows compatibility range is invalid or reversed: $compatLine"
        }
        $result.Tag = $tag
        $result.Version = $tagMatch.Groups['v'].Value
        $result.Min = $minVersion
        $result.Max = $maxVersion
        $result.PublishedAt = [string]$Release.published_at
        $result.Verified = $true
    } catch {
        $result.Error = $_.Exception.Message
    }
    return [pscustomobject]$result
}

function Get-SpicetifyArchitecture {
    # PROCESSOR_ARCHITEW6432 exposes the native OS architecture when 32-bit
    # Windows PowerShell is running on 64-bit Windows. Prefer it when present.
    $arch = [string]$env:PROCESSOR_ARCHITEW6432
    if ([string]::IsNullOrWhiteSpace($arch)) { $arch = [string]$env:PROCESSOR_ARCHITECTURE }
    $arch = $arch.ToUpperInvariant()
    if ($arch -eq 'AMD64') { return 'x64' }
    if ($arch -eq 'ARM64') { return 'arm64' }
    if ($arch -eq 'X86') { return 'x32' }
    throw "Unsupported Windows architecture for Spicetify asset selection: $arch"
}

function Get-SpicetifyManagedInstallInfo {
    $actual = Get-SpicetifyCommand
    $expected = Join-Path $env:LOCALAPPDATA 'spicetify\spicetify.exe'
    $managed = $false
    if (-not [string]::IsNullOrWhiteSpace($actual)) {
        try {
            $managed = ([System.IO.Path]::GetFullPath($actual) -ieq [System.IO.Path]::GetFullPath($expected))
        } catch { $managed = $false }
    }
    return [pscustomobject]@{
        Path = $actual
        ExpectedPath = $expected
        Managed = $managed
        Mode = $(if($managed){'official-localappdata'}elseif($actual){'external-or-package-manager'}else{'missing'})
        Version = $(if($actual){Get-InstalledSpicetifyVersion}else{$null})
    }
}

function ConvertFrom-SpicetifyReleaseInfo {
    param($Release,[AllowNull()][AllowEmptyString()][string]$ExpectedTag)
    $result = [ordered]@{
        Verified=$false; Tag=$null; Version=$null; Min=$null; Max=$null; PublishedAt=$null
        Architecture=$null; AssetName=$null; AssetUrl=$null; AssetDigest=$null; AssetSize=$null; AssetId=$null; Error=$null
    }
    try {
        $parsed = ConvertFrom-SpicetifyReleaseCompatibility -Release $Release -ExpectedTag $ExpectedTag
        if (-not $parsed.Verified) { throw $parsed.Error }
        $arch = Get-SpicetifyArchitecture
        $assetName = 'spicetify-' + $parsed.Version + '-windows-' + $arch + '.zip'
        $assets = @($Release.assets | Where-Object { [string]$_.name -eq $assetName -and [string]$_.state -eq 'uploaded' })
        if ($assets.Count -ne 1) { throw "Expected exactly one uploaded $assetName asset; found $($assets.Count)." }
        $asset = $assets[0]
        $digest = ([string]$asset.digest).Trim().ToLowerInvariant()
        if ($digest -notmatch '^sha256:[0-9a-f]{64}$') { throw 'Spicetify release asset is missing a valid GitHub-published SHA-256 digest.' }
        $url = [string]$asset.browser_download_url
        $escapedVersion = [regex]::Escape([string]$parsed.Version)
        $escapedAssetName = [regex]::Escape($assetName)
        $expectedPattern = '^https://github\.com/spicetify/cli/releases/download/v' + $escapedVersion + '/' + $escapedAssetName + '$'
        if ($url -notmatch $expectedPattern) { throw "Spicetify release asset URL does not match the selected official architecture asset: $url" }
        if ([int64]$asset.size -le 0) { throw 'Spicetify release asset has an invalid size.' }
        $result.Verified=$true; $result.Tag=$parsed.Tag; $result.Version=$parsed.Version; $result.Min=$parsed.Min; $result.Max=$parsed.Max
        $result.PublishedAt=$parsed.PublishedAt; $result.Architecture=$arch; $result.AssetName=$assetName; $result.AssetUrl=$url
        $result.AssetDigest=$digest; $result.AssetSize=[int64]$asset.size; $result.AssetId=[string]$asset.id
    } catch { $result.Error=$_.Exception.Message }
    return [pscustomobject]$result
}

function Get-SpicetifyReleaseInfoForVersion {
    param([Parameter(Mandatory=$true)][string]$Version)
    $result = [ordered]@{
        Verified=$false; Tag=$null; Version=$Version; Min=$null; Max=$null; PublishedAt=$null
        Architecture=$null; AssetName=$null; AssetUrl=$null; AssetDigest=$null; AssetSize=$null; AssetId=$null; Error=$null
    }
    try {
        if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "Spicetify version is invalid: $Version" }
        $tag = 'v' + $Version
        $uri = 'https://api.github.com/repos/spicetify/cli/releases/tags/' + [uri]::EscapeDataString($tag)
        $release = Invoke-RestMethod -Uri $uri -Headers @{ 'User-Agent'="SpotifyControl/$ScriptVersion"; 'Accept'='application/vnd.github+json' }
        $parsed = ConvertFrom-SpicetifyReleaseInfo -Release $release -ExpectedTag $tag
        if (-not $parsed.Verified) { throw $parsed.Error }
        return $parsed
    } catch { $result.Error=$_.Exception.Message }
    return [pscustomobject]$result
}

function Get-SpicetifyReleaseCompatibilityForVersion {
    param([Parameter(Mandatory=$true)][string]$Version)
    $info = Get-SpicetifyReleaseInfoForVersion -Version $Version
    return [pscustomobject]@{
        Verified=[bool]$info.Verified; Tag=$info.Tag; Version=$Version; Min=$info.Min; Max=$info.Max; PublishedAt=$info.PublishedAt; Error=$info.Error
    }
}

function Get-SpicetifyLatestReleaseInfo {
    $result = [ordered]@{
        Verified=$false; Tag=$null; Version=$null; Min=$null; Max=$null; PublishedAt=$null
        Architecture=$null; AssetName=$null; AssetUrl=$null; AssetDigest=$null; AssetSize=$null; AssetId=$null; Error=$null
    }
    try {
        $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/spicetify/cli/releases/latest' -Headers @{ 'User-Agent'="SpotifyControl/$ScriptVersion"; 'Accept'='application/vnd.github+json' }
        $parsed = ConvertFrom-SpicetifyReleaseInfo -Release $release -ExpectedTag $null
        if (-not $parsed.Verified) { throw $parsed.Error }
        return $parsed
    } catch { $result.Error=$_.Exception.Message }
    return [pscustomobject]$result
}

function Get-SpicetifyWindowsCompatibility {
    $version = Get-InstalledSpicetifyVersion
    if ([string]::IsNullOrWhiteSpace($version)) {
        return [pscustomobject]@{ Verified=$false; Tag=$null; Version=$null; Min=$null; Max=$null; PublishedAt=$null; Error='Installed Spicetify version could not be determined.' }
    }
    return Get-SpicetifyReleaseCompatibilityForVersion -Version $version
}

function Test-SpotifyVersionInRange {
    param([string]$SpotifyVersion,[string]$MinSupported,[string]$MaxSupported)
    if ([string]::IsNullOrWhiteSpace($SpotifyVersion) -or [string]::IsNullOrWhiteSpace($MinSupported) -or [string]::IsNullOrWhiteSpace($MaxSupported)) { return $false }
    $minCmp = Compare-VersionParts -A $SpotifyVersion -B $MinSupported -Count 3
    $maxCmp = Compare-VersionParts -A $SpotifyVersion -B $MaxSupported -Count 3
    if ($null -eq $minCmp -or $null -eq $maxCmp) { return $false }
    return ($minCmp -ge 0 -and $maxCmp -le 0)
}

function Ensure-SpicetifyTransactionShape {
    param($Transaction)
    if ($null -eq $Transaction) { return $null }
    $defaults = [ordered]@{
        schema = 3
        root_transaction = $false
        target_root = $null
        target_path = $null
        backup_root = $null
        backup_path = $null
        same_dir_new_root = $null
        same_dir_old_root = $null
        same_dir_new = $null
        same_dir_old = $null
        before_tree_sha256 = $null
        after_tree_sha256 = $null
        before_file_count = $null
        after_file_count = $null
        payload_tree_sha256 = $null
        payload_file_count = $null
        apply_attempted = $false
        apply_succeeded = $false
        apply_at = $null
        post_apply_guard_succeeded = $false
        post_apply_guard_at = $null
        rollback_reapply_succeeded = $null
        rollback_reapply_at = $null
        swapped_at = $null
        committed_at = $null
        rolled_back_at = $null
        error = $null
        extras_preserved = $false
        extra_file_count = 0
        extras_before_tree_sha256 = $null
        extras_after_tree_sha256 = $null
    }
    foreach ($name in $defaults.Keys) {
        if (-not $Transaction.PSObject.Properties[$name]) {
            $Transaction | Add-Member -NotePropertyName $name -NotePropertyValue $defaults[$name]
        }
    }
    if ([int]$Transaction.schema -lt 3) {
        # Legacy schema-2 executable-only ledgers remain readable solely so an
        # interrupted pre-v0.6.8 transaction can be rolled back safely. New
        # transactions are always full-root schema 3.
        $Transaction.schema = 3
    }
    return $Transaction
}

function Get-SpicetifyTransaction {
    if (-not (Test-UsablePath -Path $SpicetifyTransactionPath -PathType 'Leaf')) { return $null }
    try {
        $txn = Get-Content -LiteralPath $SpicetifyTransactionPath -Raw | ConvertFrom-Json
        return (Ensure-SpicetifyTransactionShape $txn)
    }
    catch { throw "Spicetify transaction ledger is unreadable; refusing mutation: $($_.Exception.Message)" }
}

function Save-SpicetifyTransaction {
    param($Transaction)
    $Transaction = Ensure-SpicetifyTransactionShape $Transaction
    $json=$Transaction | ConvertTo-Json -Depth 8
    Write-SpicetifyJournalJsonAtomic -Path $SpicetifyTransactionPath -Json $json
    Write-SpicetifyJournalJsonAtomic -Path $SpicetifyTransactionReport -Json $json
}

function Get-ExactFileSha256 {
    param([string]$Path)
    if (-not (Test-UsablePath -Path $Path -PathType 'Leaf')) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-StringSha256 {
    param([AllowNull()][string]$Text)
    if ($null -eq $Text) { $Text = '' }
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $bytes = $utf8.GetBytes($Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Join-SpicetifyRelativePath {
    param([string]$RootPath,[string]$RelativePath)
    if ([string]::IsNullOrWhiteSpace($RelativePath)) { throw 'Empty relative path is not allowed.' }
    $native = $RelativePath.Replace('/',[string][System.IO.Path]::DirectorySeparatorChar)
    $rootFull = [System.IO.Path]::GetFullPath($RootPath).TrimEnd([char[]]@('\','/'))
    $candidate = [System.IO.Path]::GetFullPath((Join-Path $rootFull $native))
    $prefix = $rootFull + [System.IO.Path]::DirectorySeparatorChar
    if (-not $candidate.StartsWith($prefix,[System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escaped Spicetify root: $RelativePath"
    }
    return $candidate
}

function Get-SpicetifyRootManifest {
    param([string]$Path)
    if (-not (Test-UsablePath -Path $Path -PathType 'Container')) { throw "Spicetify root does not exist: $Path" }
    $rootItem = Get-Item -LiteralPath $Path -Force
    if (($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Reparse-point Spicetify root refused: $Path" }
    $rootFull = $rootItem.FullName.TrimEnd([char[]]@('\','/'))
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($item in @(Get-ChildItem -LiteralPath $Path -Force -Recurse | Sort-Object FullName)) {
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Reparse point refused in Spicetify root: $($item.FullName)" }
        $relative = $item.FullName.Substring($rootFull.Length).TrimStart([char[]]@('\','/')).Replace('\','/')
        if ([string]::IsNullOrWhiteSpace($relative)) { continue }
        if ($item.PSIsContainer) {
            $rows.Add([pscustomobject]@{ path=$relative; type='dir'; size=[int64]0; sha256=$null })
        } else {
            $rows.Add([pscustomobject]@{ path=$relative; type='file'; size=[int64]$item.Length; sha256=(Get-ExactFileSha256 -Path $item.FullName) })
        }
    }
    $ordered = @($rows.ToArray() | Sort-Object path,type)
    $json = $ordered | ConvertTo-Json -Depth 5 -Compress
    return [pscustomobject]@{
        Root=$rootFull
        Rows=$ordered
        TreeSha256=(Get-StringSha256 -Text $json)
        FileCount=@($ordered | Where-Object { $_.type -eq 'file' }).Count
        DirectoryCount=@($ordered | Where-Object { $_.type -eq 'dir' }).Count
    }
}

function Get-SpicetifyManifestMap {
    param($Manifest)
    $map = @{}
    foreach ($row in @($Manifest.Rows)) { $map[[string]$row.path] = $row }
    return $map
}


function Get-SpicetifyExtraManifest {
    param($LiveManifest,$PayloadManifest)
    $payloadMap = Get-SpicetifyManifestMap -Manifest $PayloadManifest
    $rows = @($LiveManifest.Rows | Where-Object {
        $_.type -eq 'file' -and -not $payloadMap.ContainsKey([string]$_.path)
    } | Sort-Object path | ForEach-Object {
        [pscustomobject]@{ path=[string]$_.path; size=[int64]$_.size; sha256=[string]$_.sha256 }
    })
    $json = $rows | ConvertTo-Json -Depth 4 -Compress
    return [pscustomobject]@{
        Rows=$rows
        FileCount=$rows.Count
        TreeSha256=(Get-StringSha256 -Text $json)
    }
}

function Remove-ObsoleteSpicetifyPayloadPaths {
    param([string]$DestinationRoot,$BeforePayloadManifest,$AfterPayloadManifest)
    $afterMap = Get-SpicetifyManifestMap -Manifest $AfterPayloadManifest
    foreach ($row in @($BeforePayloadManifest.Rows | Where-Object { $_.type -eq 'file' } | Sort-Object path)) {
        $path = [string]$row.path
        $keep = $false
        if ($afterMap.ContainsKey($path)) { $keep = ([string]$afterMap[$path].type -eq 'file') }
        if ($keep) { continue }
        $dest = Join-SpicetifyRelativePath -RootPath $DestinationRoot -RelativePath $path
        if (-not (Test-Path -LiteralPath $dest -PathType Leaf)) { continue }
        $actual = Get-ExactFileSha256 -Path $dest
        if ($actual -cne [string]$row.sha256) {
            throw "Obsolete official Spicetify file was locally modified; refusing automatic removal: $path"
        }
        Remove-Item -LiteralPath $dest -Force
    }
}

function Copy-SpicetifyRootExact {
    param([string]$Source,[string]$Destination,[string]$ExpectedTreeSha256)
    if (Test-Path -LiteralPath $Destination) { throw "Destination already exists; refusing ambiguous root copy: $Destination" }
    $parent = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination -Recurse -Force
    $manifest = Get-SpicetifyRootManifest -Path $Destination
    if (-not [string]::IsNullOrWhiteSpace($ExpectedTreeSha256) -and $manifest.TreeSha256 -cne $ExpectedTreeSha256) {
        throw "Copied Spicetify root manifest mismatch. expected=$ExpectedTreeSha256 actual=$($manifest.TreeSha256)"
    }
    return $manifest
}

function Test-SpicetifyLivePayloadBaseline {
    param([string]$LiveRoot,$Payload)
    $result = [ordered]@{ Verified=$false; Error=$null; LiveManifest=$null; OfficialFileCount=0; ExtraFileCount=0 }
    try {
        $live = Get-SpicetifyRootManifest -Path $LiveRoot
        $liveMap = Get-SpicetifyManifestMap -Manifest $live
        foreach ($row in @($Payload.Manifest.Rows)) {
            $path = [string]$row.path
            if (-not $liveMap.ContainsKey($path)) { throw "Installed Spicetify official payload path is missing: $path" }
            $actual = $liveMap[$path]
            if ([string]$actual.type -cne [string]$row.type) { throw "Installed Spicetify official payload type mismatch: $path" }
            if ([string]$row.type -eq 'file' -and [string]$actual.sha256 -cne [string]$row.sha256) {
                throw "Installed Spicetify official payload file differs from its exact release: $path"
            }
        }
        $payloadMap = Get-SpicetifyManifestMap -Manifest $Payload.Manifest
        $extraFiles = @($live.Rows | Where-Object { $_.type -eq 'file' -and -not $payloadMap.ContainsKey([string]$_.path) }).Count
        $result.Verified=$true; $result.LiveManifest=$live; $result.OfficialFileCount=[int]$Payload.Manifest.FileCount; $result.ExtraFileCount=[int]$extraFiles
    } catch { $result.Error=$_.Exception.Message }
    return [pscustomobject]$result
}

function Assert-SpicetifyOverlaySafe {
    param($LiveManifest,$BeforePayloadManifest,$AfterPayloadManifest)
    $liveMap = Get-SpicetifyManifestMap -Manifest $LiveManifest
    $beforeMap = Get-SpicetifyManifestMap -Manifest $BeforePayloadManifest
    foreach ($row in @($AfterPayloadManifest.Rows)) {
        $path=[string]$row.path
        if (-not $beforeMap.ContainsKey($path) -and $liveMap.ContainsKey($path)) {
            throw "New official Spicetify payload path collides with an existing non-official/user path: $path"
        }
        $parts=$path.Split('/')
        if ($parts.Count -gt 1) {
            for ($i=1; $i -lt $parts.Count; $i++) {
                $ancestor=($parts[0..($i-1)] -join '/')
                if (-not $beforeMap.ContainsKey($ancestor) -and $liveMap.ContainsKey($ancestor)) {
                    throw "New official Spicetify payload would enter an existing non-official/user directory: $ancestor"
                }
            }
        }
    }
}

function Overlay-SpicetifyPayload {
    param($Payload,[string]$DestinationRoot)
    $rows=@($Payload.Manifest.Rows)
    foreach ($row in @($rows | Where-Object { $_.type -eq 'dir' } | Sort-Object @{Expression={($_.path -split '/').Count}},path)) {
        $dest=Join-SpicetifyRelativePath -RootPath $DestinationRoot -RelativePath ([string]$row.path)
        if (Test-Path -LiteralPath $dest -PathType Leaf) { throw "Official Spicetify directory collides with a file in staging root: $($row.path)" }
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
    }
    foreach ($row in @($rows | Where-Object { $_.type -eq 'file' } | Sort-Object path)) {
        $rel=[string]$row.path
        $source=Join-SpicetifyRelativePath -RootPath ([string]$Payload.PayloadRoot) -RelativePath $rel
        $dest=Join-SpicetifyRelativePath -RootPath $DestinationRoot -RelativePath $rel
        $parent=Split-Path -Parent $dest
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
        if (Test-Path -LiteralPath $dest -PathType Container) { throw "Official Spicetify file collides with a directory in staging root: $rel" }
        Copy-Item -LiteralPath $source -Destination $dest -Force
        if ((Get-ExactFileSha256 -Path $dest) -cne [string]$row.sha256) { throw "Spicetify payload overlay hash mismatch: $rel" }
    }
}

function Assert-SpicetifyNonPayloadPreserved {
    param($BeforeManifest,$AfterManifest,$BeforePayloadManifest,$AfterPayloadManifest)
    $beforeMap=Get-SpicetifyManifestMap -Manifest $BeforeManifest
    $afterMap=Get-SpicetifyManifestMap -Manifest $AfterManifest
    $beforePayloadMap=Get-SpicetifyManifestMap -Manifest $BeforePayloadManifest
    $afterPayloadMap=Get-SpicetifyManifestMap -Manifest $AfterPayloadManifest
    foreach ($row in @($BeforeManifest.Rows | Where-Object { $_.type -eq 'file' })) {
        $path=[string]$row.path
        if ($beforePayloadMap.ContainsKey($path)) { continue }
        if (-not $afterMap.ContainsKey($path)) { throw "Non-payload Spicetify/user file disappeared from staged root: $path" }
        $other=$afterMap[$path]
        if ([string]$other.type -cne 'file' -or [string]$other.sha256 -cne [string]$row.sha256) { throw "Non-payload Spicetify/user file changed in staged root: $path" }
    }
    foreach ($row in @($AfterManifest.Rows | Where-Object { $_.type -eq 'file' })) {
        $path=[string]$row.path
        if ($afterPayloadMap.ContainsKey($path)) { continue }
        if (-not $beforeMap.ContainsKey($path)) { throw "Unexpected non-payload file appeared in staged Spicetify root: $path" }
        if ($beforePayloadMap.ContainsKey($path)) { throw "Obsolete official Spicetify file survived as an unexpected extra: $path" }
        if ([string]$beforeMap[$path].sha256 -cne [string]$row.sha256) { throw "Non-payload Spicetify/user file changed in staged root: $path" }
    }
    $beforeExtra=Get-SpicetifyExtraManifest -LiveManifest $BeforeManifest -PayloadManifest $BeforePayloadManifest
    $afterExtra=Get-SpicetifyExtraManifest -LiveManifest $AfterManifest -PayloadManifest $AfterPayloadManifest
    if ($beforeExtra.TreeSha256 -cne $afterExtra.TreeSha256 -or $beforeExtra.FileCount -ne $afterExtra.FileCount) {
        throw "Non-payload Spicetify/user-file manifest changed. before=$($beforeExtra.TreeSha256) after=$($afterExtra.TreeSha256)"
    }
    return [pscustomobject]@{ Before=$beforeExtra; After=$afterExtra }
}

function Assert-SpicetifyPayloadApplied {
    param([string]$RootPath,$PayloadManifest)
    $live=Get-SpicetifyRootManifest -Path $RootPath
    $map=Get-SpicetifyManifestMap -Manifest $live
    foreach($row in @($PayloadManifest.Rows)) {
        $path=[string]$row.path
        if(-not $map.ContainsKey($path)) { throw "Staged official payload path missing after overlay: $path" }
        $actual=$map[$path]
        if([string]$actual.type -cne [string]$row.type) { throw "Staged official payload path type mismatch after overlay: $path" }
        if([string]$row.type -eq 'file' -and [string]$actual.sha256 -cne [string]$row.sha256) { throw "Staged official payload file hash mismatch after overlay: $path" }
    }
    return $live
}


# R138 HOLD: verified background ZIP cache; never modify Spotify while playing.
function Get-R138AssetKey {
 param($Release)
 $v=[string]$Release.Version
 $digest=([string]$Release.AssetDigest).ToLowerInvariant()
 $asset=[string]$Release.AssetName
 if(-not [bool]$Release.Verified -or $v -cnotmatch '^\d+\.\d+\.\d+$' -or
    $digest -cnotmatch '^sha256:[a-f0-9]{64}$' -or
    [string]$Release.Tag -cne ('v'+$v) -or
    [string]$Release.Architecture -cne 'x64' -or
    $asset -cne ('spicetify-'+$v+'-windows-x64.zip') -or
    [string]$Release.AssetUrl -cne ('https://github.com/spicetify/cli/releases/download/v'+$v+'/'+$asset) -or
    [int64]$Release.AssetSize -le 0 -or [int64]$Release.AssetSize -gt 134217728){
    throw 'R138_UNTRUSTED_RELEASE'
 }
 $root=Join-Path $Root 'cache\spicetify-official-assets'
 return [pscustomobject]@{Root=$root;Path=(Join-Path $root ($asset.Substring(0,$asset.Length-4)+'-'+$digest.Substring(7)+'.zip'));Sha=$digest.Substring(7);Size=[int64]$Release.AssetSize}
}
function Get-R138AssetCache {
 param($Release)
 $key=Get-R138AssetKey -Release $Release
 if(-not (Test-Path -LiteralPath $key.Path -PathType Leaf)){return $null}
 $dir=Get-Item -LiteralPath $key.Root -Force -ErrorAction Stop
 $file=Get-Item -LiteralPath $key.Path -Force -ErrorAction Stop
 if(($dir.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
    ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
    [int64]$file.Length -ne $key.Size -or
    (Get-ExactFileSha256 -Path $key.Path) -cne $key.Sha){return $null}
 return $key.Path
}
function Save-R138AssetCache {
 param($Release)
 $key=Get-R138AssetKey -Release $Release
 if(Get-R138AssetCache -Release $Release){return 'verified-reuse'}
 if(Test-Path -LiteralPath $key.Path){throw 'R138_CACHE_COLLISION_HOLD'}
 if(-not (Test-Path -LiteralPath $key.Root -PathType Container)){
   [void](New-Item -ItemType Directory -Force -Path $key.Root)
 }
 $dir=Get-Item -LiteralPath $key.Root -Force -ErrorAction Stop
 if(($dir.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'R138_CACHE_ROOT_REPARSE'}
 $temp=Join-Path $key.Root ('.incoming-'+[guid]::NewGuid().ToString('N')+'.tmp')
 try{
   Invoke-WebRequest -Uri ([string]$Release.AssetUrl) -Headers @{'User-Agent'="SpotifyControl/$ScriptVersion"} -OutFile $temp -UseBasicParsing -TimeoutSec 120
   $file=Get-Item -LiteralPath $temp -Force -ErrorAction Stop
   if([int64]$file.Length -ne $key.Size -or (Get-ExactFileSha256 -Path $temp) -cne $key.Sha){throw 'R138_DOWNLOAD_UNTRUSTED'}
   [IO.File]::Move($temp,$key.Path)
   return 'verified-new'
 } finally {
   if(Test-Path -LiteralPath $temp -PathType Leaf){Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue}
 }
}
function Invoke-R138PlaybackWarm {
 param($Discovery)
 if(-not (Test-SpotifyRunning)){return 'not-playing'}
 if($null -eq $Discovery -or [string]$Discovery.Report.phase -cne 'check-only' -or
    -not [bool]$Discovery.Report.healthy -or
    -not [bool]$Discovery.Report.spicetify.upgrade_pending -or
    [string]$Discovery.Report.spicetify.install_mode -cne 'official-localappdata'){return 'no-trusted-upgrade'}
 $v=[string]$Discovery.Report.spicetify.installed_version
 $tag=[string]$Discovery.Report.spicetify.latest_tag
 $sha=([string]$Discovery.Report.spicetify.latest_digest).ToLowerInvariant()
 if($v -cnotmatch '^\d+\.\d+\.\d+$' -or $tag -cnotmatch '^v\d+\.\d+\.\d+$' -or
    $sha -cnotmatch '^sha256:[a-f0-9]{64}$'){throw 'R138_DISCOVERY_INVALID'}
 $target=Get-SpicetifyReleaseInfoForVersion -Version $tag.Substring(1)
 if(-not [bool]$target.Verified -or [string]$target.Tag -cne $tag -or
    ([string]$target.AssetDigest).ToLowerInvariant() -cne $sha){throw 'R138_RELEASE_CHANGED'}
 $before=Get-SpicetifyReleaseInfoForVersion -Version $v
 if(-not [bool]$before.Verified){throw 'R138_ROLLBACK_RELEASE_UNVERIFIED'}
 $a=Save-R138AssetCache -Release $before
 $b=Save-R138AssetCache -Release $target
 return ('rollback='+$a+';candidate='+$b)
}
function Expand-AndValidateSpicetifyAsset {
    param($ReleaseInfo,[string]$WorkRoot)
    $zip = Join-Path $WorkRoot 'spicetify.zip'
    $payloadRoot = Join-Path $WorkRoot 'payload'
    New-Item -ItemType Directory -Force -Path $payloadRoot | Out-Null
    $cached=Get-R138AssetCache -Release $ReleaseInfo
    if($cached){Copy-Item -LiteralPath $cached -Destination $zip -ErrorAction Stop}
    else{Invoke-WebRequest -Uri $ReleaseInfo.AssetUrl -Headers @{ 'User-Agent'="SpotifyControl/$ScriptVersion" } -OutFile $zip -UseBasicParsing}
    $actualDigest = 'sha256:' + ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant())
    if ($actualDigest -cne ([string]$ReleaseInfo.AssetDigest).ToLowerInvariant()) { throw "Spicetify published digest mismatch. expected=$($ReleaseInfo.AssetDigest) actual=$actualDigest" }
    $actualSize = (Get-Item -LiteralPath $zip).Length
    if ($actualSize -ne [int64]$ReleaseInfo.AssetSize) { throw "Spicetify asset size mismatch. expected=$($ReleaseInfo.AssetSize) actual=$actualSize" }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $allowedTop=@('spicetify.exe','CustomApps','Extensions','Themes','jsHelper','globals.d.ts','css-map.json')
    $requiredFiles=@('spicetify.exe','globals.d.ts','css-map.json')
    $requiredGroups=@('CustomApps','Extensions','Themes','jsHelper')
    $seen=New-Object -TypeName 'System.Collections.Generic.HashSet[string]' -ArgumentList ([System.StringComparer]::OrdinalIgnoreCase)
    [int]$rootExeCount=0
    $groups=New-Object -TypeName 'System.Collections.Generic.HashSet[string]' -ArgumentList ([System.StringComparer]::OrdinalIgnoreCase)
    [int64]$totalUncompressed=0
    $archive = [System.IO.Compression.ZipFile]::OpenRead($zip)
    try {
        foreach ($entry in $archive.Entries) {
            $raw=([string]$entry.FullName).Replace('\','/')
            if ([string]::IsNullOrWhiteSpace($raw)) { continue }
            if ($raw.StartsWith('/') -or $raw.Contains(':')) { throw "Unsafe path in Spicetify archive: $raw" }
            $isDirectory=$raw.EndsWith('/')
            $name=$raw.TrimEnd('/')
            if ([string]::IsNullOrWhiteSpace($name)) { throw "Unsafe empty path in Spicetify archive: $raw" }
            $parts=$name.Split('/')
            if (@($parts | Where-Object { $_ -eq '' -or $_ -eq '.' -or $_ -eq '..' }).Count -gt 0) { throw "Unsafe path component in Spicetify archive: $raw" }
            if ($allowedTop -notcontains $parts[0]) { throw "Unexpected top-level path in Spicetify archive: $raw" }
            if ($parts[0] -in $requiredFiles -and $parts.Count -ne 1) { throw "Official Spicetify top-level file unexpectedly has descendants: $raw" }
            if ($name -ieq 'spicetify.exe' -and -not $isDirectory -and $parts.Count -eq 1) { $rootExeCount++ }
            if (-not $seen.Add($name)) { throw "Duplicate/case-colliding path in Spicetify archive: $name" }
            [void]$groups.Add($parts[0])
            $unixMode=(($entry.ExternalAttributes -shr 16) -band 0xF000)
            if ($unixMode -eq 0xA000) { throw "Symlink entry refused in Spicetify archive: $raw" }
            if (-not $isDirectory) {
                if ([int64]$entry.Length -lt 0 -or [int64]$entry.Length -gt 134217728) { throw "Suspicious Spicetify archive entry size: $raw" }
                $totalUncompressed += [int64]$entry.Length
                if ($totalUncompressed -gt 268435456) { throw 'Spicetify archive uncompressed payload exceeds the safety limit.' }
            }
            $dest=Join-SpicetifyRelativePath -RootPath $payloadRoot -RelativePath $name
            if ($isDirectory) {
                New-Item -ItemType Directory -Force -Path $dest | Out-Null
            } else {
                New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
                $input=$entry.Open(); $output=[System.IO.File]::Create($dest)
                try { $input.CopyTo($output) } finally { $output.Dispose(); $input.Dispose() }
            }
        }
    } finally { $archive.Dispose() }

    if ($rootExeCount -ne 1) { throw "Expected exactly one root spicetify.exe in official archive; found $rootExeCount." }
    foreach($required in $requiredFiles) { if (-not $seen.Contains($required)) { throw "Required Spicetify archive file missing: $required" } }
    foreach($required in $requiredGroups) { if (-not $groups.Contains($required)) { throw "Required Spicetify archive group missing: $required" } }
    $manifest=Get-SpicetifyRootManifest -Path $payloadRoot
    $stageExe=Join-Path $payloadRoot 'spicetify.exe'
    if ((Get-Item -LiteralPath $stageExe).Length -lt 1048576) { throw 'Staged Spicetify executable is unexpectedly small.' }
    $r = Invoke-NativeCapture -FilePath $stageExe -Arguments @('--version')
    if ($r.ExitCode -ne 0) { throw "Staged Spicetify executable failed --version: $($r.Output)" }
    $m = [regex]::Match([string]$r.Output,'(?<!\d)(?<v>\d+\.\d+\.\d+)(?!\d)')
    if (-not $m.Success -or $m.Groups['v'].Value -cne [string]$ReleaseInfo.Version) { throw "Staged Spicetify version mismatch. expected=$($ReleaseInfo.Version) output=$($r.Output)" }
    return [pscustomobject]@{
        Zip=$zip; PayloadRoot=$payloadRoot; Manifest=$manifest; PayloadTreeSha256=$manifest.TreeSha256
        ActualDigest=$actualDigest; ExeSha256=(Get-ExactFileSha256 -Path $stageExe); Version=$m.Groups['v'].Value
    }
}

function Test-SpicetifySwapRollbackSandbox {
    $sandboxParent=Join-Path $Root ('transaction-tests\spicetify-root-' + [guid]::NewGuid().ToString('N'))
    $live=Join-Path $sandboxParent 'spicetify'
    $payloadRoot=Join-Path $sandboxParent 'payload'
    $newRoot=Join-Path $sandboxParent '.new'
    $oldRoot=Join-Path $sandboxParent '.old'
    $backupRoot=Join-Path $sandboxParent 'backup'
    try {
        New-Item -ItemType Directory -Force -Path (Join-Path $live 'Extensions'),(Join-Path $live 'CustomApps\user-app'),(Join-Path $payloadRoot 'Extensions') | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $live 'spicetify.exe'),'old-cli')
        [System.IO.File]::WriteAllText((Join-Path $live 'Extensions\official.js'),'old-official')
        [System.IO.File]::WriteAllText((Join-Path $live 'Extensions\removed-in-new.js'),'old-removed')
        [System.IO.File]::WriteAllText((Join-Path $live 'CustomApps\user-app\index.js'),'user-data')
        [System.IO.File]::WriteAllText((Join-Path $payloadRoot 'spicetify.exe'),'new-cli')
        [System.IO.File]::WriteAllText((Join-Path $payloadRoot 'Extensions\official.js'),'new-official')
        $before=Get-SpicetifyRootManifest -Path $live
        $payloadManifest=Get-SpicetifyRootManifest -Path $payloadRoot
        [void](Copy-SpicetifyRootExact -Source $live -Destination $backupRoot -ExpectedTreeSha256 $before.TreeSha256)
        [void](Copy-SpicetifyRootExact -Source $live -Destination $newRoot -ExpectedTreeSha256 $before.TreeSha256)
        $payload=[pscustomobject]@{PayloadRoot=$payloadRoot;Manifest=$payloadManifest}
        $beforePayloadRoot=Join-Path $sandboxParent 'before-payload'
        New-Item -ItemType Directory -Force -Path (Join-Path $beforePayloadRoot 'Extensions') | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $beforePayloadRoot 'spicetify.exe'),'old-cli')
        [System.IO.File]::WriteAllText((Join-Path $beforePayloadRoot 'Extensions\official.js'),'old-official')
        [System.IO.File]::WriteAllText((Join-Path $beforePayloadRoot 'Extensions\removed-in-new.js'),'old-removed')
        $beforePayloadManifest=Get-SpicetifyRootManifest -Path $beforePayloadRoot
        Remove-ObsoleteSpicetifyPayloadPaths -DestinationRoot $newRoot -BeforePayloadManifest $beforePayloadManifest -AfterPayloadManifest $payloadManifest
        Overlay-SpicetifyPayload -Payload $payload -DestinationRoot $newRoot
        $after=Assert-SpicetifyPayloadApplied -RootPath $newRoot -PayloadManifest $payloadManifest
        $extraProof=Assert-SpicetifyNonPayloadPreserved -BeforeManifest $before -AfterManifest $after -BeforePayloadManifest $beforePayloadManifest -AfterPayloadManifest $payloadManifest
        if (Test-Path -LiteralPath (Join-Path $newRoot 'Extensions\removed-in-new.js')) { throw 'sandbox obsolete official payload file was not removed' }
        $extraBefore=(Get-ExactFileSha256 -Path (Join-Path $live 'CustomApps\user-app\index.js'))
        Move-Item -LiteralPath $live -Destination $oldRoot
        Move-Item -LiteralPath $newRoot -Destination $live
        if ((Get-SpicetifyRootManifest -Path $live).TreeSha256 -cne $after.TreeSha256) { throw 'sandbox root swap did not reach staged tree' }
        $quarantine=Join-Path $sandboxParent '.after'
        Move-Item -LiteralPath $live -Destination $quarantine
        Move-Item -LiteralPath $oldRoot -Destination $live
        if ((Get-SpicetifyRootManifest -Path $live).TreeSha256 -cne $before.TreeSha256) { throw 'sandbox root rollback did not restore exact before tree' }
        if ((Get-ExactFileSha256 -Path (Join-Path $live 'CustomApps\user-app\index.js')) -cne $extraBefore) { throw 'sandbox user extra changed across transaction' }
        [System.IO.File]::WriteAllText((Join-Path $backupRoot 'spicetify.exe'),'corrupt')
        if ((Get-SpicetifyRootManifest -Path $backupRoot).TreeSha256 -ceq $before.TreeSha256) { throw 'sandbox corrupt-backup fixture failed' }
        return [pscustomobject]@{Pass=$true;Detail="full-root stage/overlay/swap/rollback preserved user extras and restored $($before.TreeSha256)"}
    } catch { return [pscustomobject]@{Pass=$false;Detail=$_.Exception.Message} }
    finally { Remove-Item -LiteralPath $sandboxParent -Recurse -Force -ErrorAction SilentlyContinue }
}

function Invoke-SpicetifyPreflight {
    $work = Join-Path $env:TEMP ('SpotifyControl-Spicetify-Preflight-' + [guid]::NewGuid().ToString('N'))
    $report = [ordered]@{
        schema=3; time_utc=[DateTimeOffset]::UtcNow.ToString('o'); verified=$false; install_mode=$null; installed_version=$null
        installed_compat_tag=$null; installed_min=$null; installed_max=$null; installed_exe_sha256=$null; installed_official_exe_sha256=$null
        installed_matches_official=$false; installed_payload_matches_official=$false; installed_payload_tree_sha256=$null
        installed_live_root_tree_sha256=$null; installed_official_file_count=0; installed_extra_file_count=0
        latest_tag=$null; latest_version=$null; published_digest=$null; actual_digest=$null; staged_exe_sha256=$null
        latest_payload_tree_sha256=$null; latest_payload_file_count=0; latest_overlay_safe=$false; error=$null
    }
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    try {
        $install = Get-SpicetifyManagedInstallInfo
        $report.install_mode=$install.Mode; $report.installed_version=$install.Version
        if (-not $install.Managed) { throw "Spicetify executable is not the official LOCALAPPDATA installation; automatic root mutation is disabled. path=$($install.Path)" }
        $liveRoot = Split-Path -Parent ([string]$install.Path)
        $installedRelease = Get-SpicetifyReleaseInfoForVersion -Version $install.Version
        if (-not $installedRelease.Verified) { throw $installedRelease.Error }
        $report.installed_compat_tag=$installedRelease.Tag; $report.installed_min=$installedRelease.Min; $report.installed_max=$installedRelease.Max
        $installedWork = Join-Path $work 'installed-release'
        New-Item -ItemType Directory -Force -Path $installedWork | Out-Null
        $installedPayload = Expand-AndValidateSpicetifyAsset -ReleaseInfo $installedRelease -WorkRoot $installedWork
        $installedLiveHash = Get-ExactFileSha256 -Path ([string]$install.Path)
        $report.installed_exe_sha256=$installedLiveHash; $report.installed_official_exe_sha256=$installedPayload.ExeSha256
        $report.installed_matches_official = ($installedLiveHash -and $installedLiveHash -ceq $installedPayload.ExeSha256)
        if (-not $report.installed_matches_official) { throw "Installed Spicetify executable does not match the exact official $($installedRelease.Tag) release asset; refusing to establish a mutation baseline." }
        $baseline = Test-SpicetifyLivePayloadBaseline -LiveRoot $liveRoot -Payload $installedPayload
        if (-not $baseline.Verified) { throw $baseline.Error }
        $report.installed_payload_matches_official=$true
        $report.installed_payload_tree_sha256=$installedPayload.Manifest.TreeSha256
        $report.installed_live_root_tree_sha256=$baseline.LiveManifest.TreeSha256
        $report.installed_official_file_count=$baseline.OfficialFileCount
        $report.installed_extra_file_count=$baseline.ExtraFileCount

        $latest = Get-SpicetifyLatestReleaseInfo
        if (-not $latest.Verified) { throw $latest.Error }
        $report.latest_tag=$latest.Tag; $report.latest_version=$latest.Version; $report.published_digest=$latest.AssetDigest
        if ([string]$latest.Version -ceq [string]$install.Version) {
            $payload = $installedPayload
        } else {
            $latestWork = Join-Path $work 'latest-release'
            New-Item -ItemType Directory -Force -Path $latestWork | Out-Null
            $payload = Expand-AndValidateSpicetifyAsset -ReleaseInfo $latest -WorkRoot $latestWork
        }
        Assert-SpicetifyOverlaySafe -LiveManifest $baseline.LiveManifest -BeforePayloadManifest $installedPayload.Manifest -AfterPayloadManifest $payload.Manifest
        $report.latest_overlay_safe=$true
        $report.actual_digest=$payload.ActualDigest; $report.staged_exe_sha256=$payload.ExeSha256
        $report.latest_payload_tree_sha256=$payload.Manifest.TreeSha256; $report.latest_payload_file_count=$payload.Manifest.FileCount
        $report.verified=$true
        Write-Log "Spicetify preflight verified full installed payload $($installedRelease.Tag), preserved $($baseline.ExtraFileCount) extra file(s), and verified latest $($latest.Tag) with GitHub-published digest."
    } catch { $report.error=$_.Exception.Message; Write-Log "Spicetify preflight failed: $($report.error)" 'ERROR' }
    finally { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue; $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $SpicetifyPreflightReport -Encoding UTF8 }
    if (-not $report.verified) { throw $report.error }
    return [pscustomobject]$report
}

function Get-SpicetifyBackupMigrationClass {
    param([string]$InstalledVersion,[string]$TargetVersion,[string]$BackupWith)
    if ([string]::IsNullOrWhiteSpace($InstalledVersion) -or
        [string]::IsNullOrWhiteSpace($TargetVersion)) {
        return 'VERSION_IDENTITY_UNVERIFIED'
    }
    if ([string]::IsNullOrWhiteSpace($BackupWith)) {
        return 'BACKUP_PREPROCESSOR_UNVERIFIED'
    }
    if ($BackupWith -cne $InstalledVersion) {
        return 'BACKUP_PREPROCESSOR_NOT_CURRENT_CLI'
    }
    if ($TargetVersion -cne $InstalledVersion) {
        return 'VERSION_CHANGE_REQUIRES_ATOMIC_BACKUP_REPROCESSING'
    }
    return 'BACKUP_PREPROCESSOR_CURRENT'
}

function New-SpicetifyMigrationPreimage {
  param([string]$TransactionBackupDir,[string]$InstalledCliVersion)
  $spice=Join-Path $env:APPDATA 'spicetify'
  $apps=Join-Path $env:APPDATA 'Spotify\Apps'
  $cfg=Join-Path $spice 'config-xpui.ini'
  $actual=Get-ConfigPath
  if(-not $actual -or
    -not [string]::Equals([IO.Path]::GetFullPath($actual),
       [IO.Path]::GetFullPath($cfg),
       [StringComparison]::OrdinalIgnoreCase)){
    throw 'R131_NONSTANDARD_SPICETIFY_CONFIG_HOLD'
  }
  $backupWith=Get-IniSectionValue -Path $cfg -Section 'Backup' -Key 'with'
  if([string]$backupWith -cne $InstalledCliVersion){
    throw 'R131_OLD_PREPROCESSOR_NOT_EXACT_CLI_HOLD'
  }
  if(Test-SpotifyRunning){throw 'R131_SPOTIFY_RUNNING_PREIMAGE_HOLD'}
  $sourceSpice=Get-SpicetifyRootManifest -Path $spice
  $sourceApps=Get-SpicetifyRootManifest -Path $apps
  $snapshotRoot=Join-Path $TransactionBackupDir 'preprocess-external-before'
  if(Test-Path -LiteralPath $snapshotRoot){
    throw 'R131_EXTERNAL_PREIMAGE_ALREADY_EXISTS'
  }
  # Capture both sources before any Spotify Apps or roaming Spicetify writes.
  $preSpice=Join-Path $snapshotRoot 'spicetify-roaming'
  $preApps=Join-Path $snapshotRoot 'spotify-apps'
  [void](Copy-SpicetifyRootExact -Source $spice -Destination $preSpice -ExpectedTreeSha256 $sourceSpice.TreeSha256)
  [void](Copy-SpicetifyRootExact -Source $apps -Destination $preApps -ExpectedTreeSha256 $sourceApps.TreeSha256)
  if((Get-SpicetifyRootManifest -Path $spice).TreeSha256 -cne $sourceSpice.TreeSha256 -or
     (Get-SpicetifyRootManifest -Path $apps).TreeSha256 -cne $sourceApps.TreeSha256){
    throw 'R131_EXTERNAL_SOURCES_CHANGED_DURING_SNAPSHOT'
  }
  $semantic=Get-SpicetifyConfigSemanticHash
  return [pscustomobject]@{
    BackupRoot=$snapshotRoot;Roaming=$spice;Apps=$apps
    RoamingBackup=$preSpice;AppsBackup=$preApps
    RoamingTreeSha256=$sourceSpice.TreeSha256
    AppsTreeSha256=$sourceApps.TreeSha256
    SemanticHash=$semantic
  }
}

function Restore-SpicetifyMigrationSurface {
  param([string]$Path,[string]$Backup,[string]$BeforeSha256,
        [string]$TransactionId,[string]$Suffix)
  $base=[IO.Path]::GetFullPath((Join-Path $env:APPDATA 'Spotify'))
  $allowedApps=[IO.Path]::GetFullPath((Join-Path $base 'Apps'))
  $allowedRoaming=[IO.Path]::GetFullPath((Join-Path $env:APPDATA 'spicetify'))
  $dest=[IO.Path]::GetFullPath($Path)
  if(-not ([string]::Equals($dest,$allowedApps,[StringComparison]::OrdinalIgnoreCase) -or
     [string]::Equals($dest,$allowedRoaming,[StringComparison]::OrdinalIgnoreCase))){
    throw 'R131_EXTERNAL_RESTORE_PATH_NOT_ALLOWED'
  }
  if($TransactionId -cnotmatch '^\d{8}-\d{6}-[a-f0-9]{8}$' -or
     $Suffix -cnotin @('apps','roaming')){
    throw 'R131_RESTORE_TRANSACTION_ID_INVALID'
  }
  $backupManifest=Get-SpicetifyRootManifest -Path $Backup
  if($backupManifest.TreeSha256 -cne $BeforeSha256){
    throw 'R131_EXTERNAL_BACKUP_SHA_MISMATCH'
  }
  $live=$null
  if(Test-Path -LiteralPath $dest -PathType Container){
    $live=Get-SpicetifyRootManifest -Path $dest
    if($live.TreeSha256 -ceq $BeforeSha256){
      return [pscustomobject]@{Restored=$true;AlreadyExact=$true}
    }
  }
  if(Test-SpotifyRunning){throw 'R131_SPOTIFY_ACTIVE_DURING_RESTORE'}
  if(@(Get-Process -Name 'spicetify' -ErrorAction SilentlyContinue).Count -gt 0){
    throw 'R131_SPICETIFY_PROCESS_ACTIVE_DURING_RESTORE'
  }
  $parent=Split-Path -Parent $dest
  $stage=Join-Path $parent ('.spotifycontrol-r131-staged-'+$Suffix+'-'+$TransactionId)
  $held=Join-Path $parent ('.spotifycontrol-r131-quarantine-'+$Suffix+'-'+$TransactionId)
  $stagePresent=Test-Path -LiteralPath $stage
  $heldPresent=Test-Path -LiteralPath $held
  # Resume ONLY the interrupted destination->quarantine rename, when the
  # original destination is absent and the exact transaction quarantine exists.
  # Never overwrite an occupied destination, even during restart recovery.
  if($heldPresent -and -not (Test-Path -LiteralPath $dest)){
    $heldItem=Get-Item -LiteralPath $held -Force -ErrorAction Stop
    if(-not $heldItem.PSIsContainer -or
       ($heldItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
      throw 'R131_INTERRUPTED_QUARANTINE_UNSAFE'
    }
    if($stagePresent){
      $stageItem=Get-Item -LiteralPath $stage -Force -ErrorAction Stop
      if(-not $stageItem.PSIsContainer -or
         ($stageItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
         (Get-SpicetifyRootManifest -Path $stage).TreeSha256 -cne $BeforeSha256){
        throw 'R131_INTERRUPTED_STAGE_INVALID'
      }
    }else{
      [void](Copy-SpicetifyRootExact -Source $Backup -Destination $stage -ExpectedTreeSha256 $BeforeSha256)
    }
    Move-Item -LiteralPath $stage -Destination $dest -ErrorAction Stop
    if((Get-SpicetifyRootManifest -Path $dest).TreeSha256 -cne $BeforeSha256){
      throw 'R131_INTERRUPTED_RESUME_SHA_MISMATCH'
    }
    # Retain the displaced modified tree for operator review.
    return [pscustomobject]@{Restored=$true;AlreadyExact=$false;Resumed=$true}
  }
  if($stagePresent -or $heldPresent){
    throw 'R131_RESTORE_RESERVED_PATH_ALREADY_EXISTS'
  }
  [void](Copy-SpicetifyRootExact -Source $Backup -Destination $stage -ExpectedTreeSha256 $BeforeSha256)
  if($live){Move-Item -LiteralPath $dest -Destination $held -ErrorAction Stop}
  try{
    Move-Item -LiteralPath $stage -Destination $dest -ErrorAction Stop
  }catch{
    if($live -and -not (Test-Path -LiteralPath $dest) -and
       (Test-Path -LiteralPath $held)){
      Move-Item -LiteralPath $held -Destination $dest -ErrorAction Stop
    }
    throw
  }
  if((Get-SpicetifyRootManifest -Path $dest).TreeSha256 -cne $BeforeSha256){
    throw 'R131_RESTORED_EXTERNAL_TREE_SHA_MISMATCH'
  }
  # The quarantine remains for operator review. Never delete unknown changed files.
  return [pscustomobject]@{Restored=$true;AlreadyExact=$false}
}

function Restore-SpicetifyMigrationPreimage {
  param($Txn)
  if(-not [bool]$Txn.migration_required){
    return [pscustomobject]@{Restored=$true;Status='NOT_REQUIRED'}
  }
  if(-not [bool]$Txn.migration_snapshot_ready){
    throw 'R131_EXTERNAL_PREIMAGE_NOT_CERTIFIED'
  }
  $spice=Join-Path $env:APPDATA 'spicetify'
  $apps=Join-Path $env:APPDATA 'Spotify\Apps'
  if(-not [string]::Equals([IO.Path]::GetFullPath([string]$Txn.migration_spicetify_root),
       [IO.Path]::GetFullPath($spice),[StringComparison]::OrdinalIgnoreCase) -or
     -not [string]::Equals([IO.Path]::GetFullPath([string]$Txn.migration_apps_root),
       [IO.Path]::GetFullPath($apps),[StringComparison]::OrdinalIgnoreCase)){
    throw 'R131_EXTERNAL_PREIMAGE_OWNER_PATH_MISMATCH'
  }
  $back=[string]$Txn.backup_root
  $backupBase=Split-Path -Parent $back
  $expectedSnapshot=Join-Path $backupBase 'preprocess-external-before'
  if(-not [string]::Equals([IO.Path]::GetFullPath([string]$Txn.migration_snapshot_root),
      [IO.Path]::GetFullPath($expectedSnapshot),[StringComparison]::OrdinalIgnoreCase)){
    throw 'R131_EXTERNAL_PREIMAGE_BACKUP_PATH_MISMATCH'
  }
  [void](Restore-SpicetifyMigrationSurface -Path $apps -Backup (Join-Path $expectedSnapshot 'spotify-apps') -BeforeSha256 ([string]$Txn.migration_apps_before_sha256) -TransactionId ([string]$Txn.id) -Suffix 'apps')
  [void](Restore-SpicetifyMigrationSurface -Path $spice -Backup (Join-Path $expectedSnapshot 'spicetify-roaming') -BeforeSha256 ([string]$Txn.migration_spicetify_before_sha256) -TransactionId ([string]$Txn.id) -Suffix 'roaming')
  if((Get-SpicetifyRootManifest -Path $apps).TreeSha256 -cne [string]$Txn.migration_apps_before_sha256 -or
     (Get-SpicetifyRootManifest -Path $spice).TreeSha256 -cne [string]$Txn.migration_spicetify_before_sha256){
    throw 'R131_EXTERNAL_PREIMAGE_FINAL_SHA_MISMATCH'
  }
  return [pscustomobject]@{Restored=$true;Status='EXACT_EXTERNAL_PREIMAGE_RESTORED'}
}

function Write-SpicetifyJournalJsonAtomic {
  param([string]$Path,[string]$Json)
  if([string]::IsNullOrWhiteSpace($Path) -or
     [string]::IsNullOrWhiteSpace($Json)){
    throw 'R131_JOURNAL_EMPTY_TARGET_OR_CONTENT'
  }
  $full=[IO.Path]::GetFullPath($Path)
  $dir=Split-Path -Parent $full
  $parent=Get-Item -LiteralPath $dir -Force -ErrorAction Stop
  if(-not $parent.PSIsContainer -or
     ($parent.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
    throw 'R131_JOURNAL_DIRECTORY_UNSAFE'
  }
  $present=Test-Path -LiteralPath $full
  $previous=$full+'.previous'
  foreach($check in @($full,$previous)){
    if(Test-Path -LiteralPath $check){
      $info=Get-Item -LiteralPath $check -Force -ErrorAction Stop
      if($info.PSIsContainer -or
         ($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
        throw 'R131_JOURNAL_TARGET_UNSAFE'
      }
    }
  }
  $stage=Join-Path $dir ('.spotifycontrol-journal-'+[guid]::NewGuid().ToString('N')+'.tmp')
  $bytes=[Text.UTF8Encoding]::new($false).GetBytes($Json)
  $hash=[Security.Cryptography.SHA256]::Create()
  try{$expected=[BitConverter]::ToString($hash.ComputeHash($bytes)).Replace('-','').ToLowerInvariant()}
  finally{$hash.Dispose()}
  $stream=$null
  try{
    $stream=[IO.FileStream]::new($stage,[IO.FileMode]::CreateNew,
         [IO.FileAccess]::Write,[IO.FileShare]::None)
    $stream.Write($bytes,0,$bytes.Length)
    $stream.Flush($true)
    $stream.Dispose();$stream=$null
    if((Get-ExactFileSha256 -Path $stage) -cne $expected){
      throw 'R131_JOURNAL_STAGE_READBACK_MISMATCH'
    }
    # The authoritative primary journal is replaced atomically before the
    # informational report. A crash can leave the report one revision behind,
    # but never silently truncate a previously committed primary JSON file.
    if($present){
      if(-not (Test-Path -LiteralPath $full -PathType Leaf)){
        throw 'R131_JOURNAL_TARGET_CHANGED_BEFORE_REPLACE'
      }
      [IO.File]::Replace($stage,$full,$previous,$true)
    }else{
      [IO.File]::Move($stage,$full)
    }
    if((Get-ExactFileSha256 -Path $full) -cne $expected){
      throw 'R131_JOURNAL_PUBLISHED_READBACK_MISMATCH'
    }
  }finally{
    if($null -ne $stream){$stream.Dispose()}
    if(Test-Path -LiteralPath $stage){
      Remove-Item -LiteralPath $stage -Force -ErrorAction SilentlyContinue
    }
  }
}

function Assert-SpicetifyOwnerPreimageAdoption {
    param($Txn)
    if([string]$Txn.status -cne 'owner-reviewed-preimage' -or
       -not [bool]$Txn.root_transaction){throw 'R132_ADOPTION_INVALID_STATUS'}
    $prop=$Txn.PSObject.Properties['owner_reconciliation']
    if($null -eq $prop -or $null -eq $prop.Value){throw 'R132_ADOPTION_RECEIPT_MISSING'}
    $a=$prop.Value
    if([string]$a.schema -cne '1' -or
       [string]$a.kind -cne 'OWNER_APPROVED_CURRENT_PREIMAGE_NOT_EXTERNAL_ROLLBACK' -or
       [string]$Txn.id -cnotmatch '^\d{8}-\d{6}-[a-f0-9]{8}$'){
       throw 'R132_ADOPTION_ID_INVALID'
    }
    $root=Join-Path $Root ('owner-recovery\R132-'+[string]$Txn.id)
    if(-not [string]::Equals([IO.Path]::GetFullPath([string]$a.snapshot_root),
         [IO.Path]::GetFullPath($root),[StringComparison]::OrdinalIgnoreCase)){
       throw 'R132_ADOPTION_SNAPSHOT_PATH_INVALID'
    }
    $evidence=Join-Path $root 'adoption-evidence.json'
    if([string]$a.evidence_sha256 -cnotmatch '^[a-f0-9]{64}$' -or
       (Get-ExactFileSha256 -Path $evidence) -cne [string]$a.evidence_sha256){
       throw 'R132_ADOPTION_EVIDENCE_SHA_INVALID'
    }
    $e=Get-Content -LiteralPath $evidence -Raw -ErrorAction Stop | ConvertFrom-Json
    if([string]$e.schema -cne '1' -or
       [string]$e.transaction_id -cne [string]$Txn.id -or
       [string]$e.evidence_kind -cne 'CURRENT_PREIMAGE_ADOPTED_NOT_HISTORICAL_EXTERNAL_ROLLBACK'){
       throw 'R132_ADOPTION_EVIDENCE_INVALID'
    }
    $orig=Join-Path $root 'original-ledger.json'
    if([string]$e.ledger_sha256 -cnotmatch '^[a-f0-9]{64}$' -or
       (Get-ExactFileSha256 -Path $orig) -cne [string]$e.ledger_sha256){
       throw 'R132_ADOPTION_ORIGINAL_LEDGER_SHA_INVALID'
    }
    $before=Get-Content -LiteralPath $orig -Raw -ErrorAction Stop | ConvertFrom-Json
    if([string]$before.status -cne 'awaiting-guard' -or
       [string]$before.id -cne [string]$Txn.id -or
       [string]$before.before_tree_sha256 -cne [string]$Txn.before_tree_sha256 -or
       [string]$before.before_sha256 -cne [string]$Txn.before_sha256){
       throw 'R132_ADOPTION_PARENT_MISMATCH'
    }
    foreach($pair in @(@('spicetify-roaming','roaming_tree_sha256'),
                        @('spotify-apps','apps_tree_sha256'))){
       $pin=[string]$e.([string]$pair[1])
       if($pin -cnotmatch '^[a-f0-9]{64}$' -or
          (Get-SpicetifyRootManifest -Path (Join-Path $root ([string]$pair[0]))).TreeSha256 -cne $pin){
          throw 'R132_ADOPTION_EXTERNAL_COPY_MISMATCH'
       }
    }
    if((Get-SpicetifyRootManifest -Path ([string]$Txn.target_root)).TreeSha256 -cne [string]$Txn.before_tree_sha256){
       throw 'R132_ADOPTION_LIVE_ROOT_DRIFT'
    }
    return $true
}

function Confirm-SpicetifyMigrationApplied {
  param($Txn)
  if(-not [bool]$Txn.migration_required){return $Txn}
  if(-not [bool]$Txn.migration_snapshot_ready -or
     -not [bool]$Txn.migration_started){
    throw 'R131_MIGRATION_NOT_PREPARED_OR_NOT_STARTED'
  }
  $config=Join-Path $env:APPDATA 'spicetify\config-xpui.ini'
  if([string](Get-IniSectionValue -Path $config -Section 'Backup' -Key 'with') -cne
     [string]$Txn.after_version){
    throw 'R131_NEW_CLI_BACKUP_WITH_NOT_MIGRATED'
  }
  if((Get-SpicetifyConfigSemanticHash) -cne [string]$Txn.migration_semantic_before_sha256){
    throw 'R131_USER_CONFIG_SEMANTICS_CHANGED'
  }
  $apps=Get-SpicetifyRootManifest -Path ([string]$Txn.migration_apps_root)
  $spice=Get-SpicetifyRootManifest -Path ([string]$Txn.migration_spicetify_root)
  $Txn.migration_apps_after_sha256=$apps.TreeSha256
  $Txn.migration_spicetify_after_sha256=$spice.TreeSha256
  $Txn.migration_finished=$true
  return $Txn
}

function Get-R135OwnerAttemptPath {
    return (Join-Path $Root 'owner-recovery\r135-v2467-owner-once-claim.v1.json')
}

function Read-R135OwnerAttempt {
    $path=Get-R135OwnerAttemptPath
    if(-not (Test-Path -LiteralPath $path)){return $null}
    $file=Get-Item -LiteralPath $path -Force -ErrorAction Stop
    if($file.PSIsContainer -or
       ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
       throw 'R135_ATTEMPT_RECORD_UNSAFE'
    }
    $claim=Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if([string]$claim.schema -cne '1' -or
       [string]$claim.kind -cne 'R135_ONE_OWNER_ATTEMPT_NO_REPLAY' -or
       [string]$claim.target_version -cne '2.46.7' -or
       [string]$claim.target_asset_sha256 -cne 'c5a723d31eae529ba13f6922a7a027124238c7f3da7edd182a73eab03c447e9e' -or
       [string]$claim.owner_transaction_id -cnotmatch '^\d{8}-\d{6}-[a-f0-9]{8}$' -or
       [string]$claim.owner_ledger_sha256 -cnotmatch '^[a-f0-9]{64}$' -or
       [string]$claim.owner_adoption_evidence_sha256 -cnotmatch '^[a-f0-9]{64}$'){
       throw 'R135_ATTEMPT_RECORD_NOT_TRUSTED'
    }
    return $claim
}

function Assert-R135ActiveOwnerAttempt {
    param($Txn)
    if($script:R135ActiveOwnerAttempt -ne $true -or
       $null -eq $script:R135ClaimSHA -or
       $script:R135AttemptCalls -ne 1){
       throw 'R135_NO_PROCESS_BOUND_APPROVAL'
    }
    $path=Get-R135OwnerAttemptPath
    if((Get-ExactFileSha256 -Path $path) -cne [string]$script:R135ClaimSHA){
       throw 'R135_OWNER_ATTEMPT_CLAIM_CHANGED'
    }
    $c=Read-R135OwnerAttempt
    if([string]$c.owner_transaction_id -cne [string]$script:R135OwnerId){
       throw 'R135_OWNER_ATTEMPT_NOT_SESSION_BOUND'
    }
    if([string]$Txn.status -ceq 'owner-reviewed-preimage'){
       [void](Assert-SpicetifyOwnerPreimageAdoption $Txn)
       if([string]$c.owner_transaction_id -cne [string]$Txn.id -or
          [string]$c.owner_ledger_sha256 -cne
             (Get-ExactFileSha256 -Path $SpicetifyTransactionPath) -or
          [string]$c.owner_adoption_evidence_sha256 -cne
             [string]$Txn.owner_reconciliation.evidence_sha256){
          throw 'R135_OWNER_ATTEMPT_LEDGER_NOT_IDENTICAL'
       }
    }
    return $true
}

function Assert-R137OfficialSpicetifyPairReady {
    # Perform read-only GitHub release checks before consuming the only
    # permitted R135 transaction attempt. A bad release cannot burn consent.
    foreach($version in @('2.46.4','2.46.7')){
        $r=Get-SpicetifyReleaseInfoForVersion -Version $version
        if($null -eq $r -or -not [bool]$r.Verified -or
           [string]$r.Tag -cne ('v'+$version) -or
           [string]$r.Version -cne $version -or
           [string]$r.Architecture -cne 'x64' -or
           [int64]$r.AssetSize -le 0 -or
           [string]$r.AssetName -cne ('spicetify-'+$version+'-windows-x64.zip') -or
           [string]$r.AssetUrl -cne ('https://github.com/spicetify/cli/releases/download/v'+
                $version+'/spicetify-'+$version+'-windows-x64.zip') -or
           [string]$r.AssetDigest -cnotmatch '^sha256:[a-f0-9]{64}$'){
            throw ('R137_OFFICIAL_RELEASE_NOT_READY_'+($version -replace '\.','_'))
        }
        if($version -ceq '2.46.4' -and
           [string]$r.AssetDigest -cne
             'sha256:0490380bf59e00c94cf6cb12bfac5152791b91bb8009aceef53c49815b45a56f'){
            throw 'R137_EXACT_ROLLBACK_ASSET_SHA_MISMATCH'
        }
        if($version -ceq '2.46.7' -and
           [string]$r.AssetDigest -cne
             'sha256:c5a723d31eae529ba13f6922a7a027124238c7f3da7edd182a73eab03c447e9e'){
            throw 'R137_EXACT_TARGET_ASSET_SHA_MISMATCH'
        }
    }
    return $true
}

function Invoke-R135OwnerSpicetifyOneShot {
    param([string]$OwnerApproval,[switch]$ForceReinstall)
    if($OwnerApproval -cne 'APPROVE_R135_SPICETIFY_2467_ONE_NATIVE_ATTEMPT'){
       throw 'R135_EXPLICIT_OWNER_APPROVAL_REQUIRED'
    }
    if($ForceReinstall){throw 'R135_FORCE_REINSTALL_NOT_AUTHORIZED'}
    if($script:R135ActiveOwnerAttempt -eq $true -or
       $script:R135AttemptCalls -ne 0){throw 'R135_ONE_PER_PROCESS_ONLY'}
    if(Test-SpotifyRunning){throw 'R135_SPOTIFY_MUST_BE_CLOSED'}
    $lease=Enter-SpotifyControlMutex -Purpose 'Maintenance'
    if($null -eq $lease){throw 'R135_PRODUCT_MAINTENANCE_LEASE_BUSY'}
    $agentLease=$null
    try{
       $agentLease=Enter-SpotifyControlMutex -Purpose 'AgentTick'
       if($null -eq $agentLease){throw 'R135_PRODUCT_AGENT_LEASE_BUSY'}
       if(Test-SpotifyRunning){throw 'R135_SPOTIFY_RESTARTED'}
       if($null -ne (Read-R135OwnerAttempt)){
          throw 'R135_PREVIOUS_ATTEMPT_EXISTS_NO_AUTO_RETRY'
       }
       $txn=Get-SpicetifyTransaction
       if($null -eq $txn -or [string]$txn.status -cne 'owner-reviewed-preimage' -or
          -not [bool]$txn.root_transaction){
          throw 'R135_OWNER_CURRENT_PREIMAGE_NOT_ADOPTED'
       }
       [void](Assert-SpicetifyOwnerPreimageAdoption $txn)
       $oldVersion='2.46.4'
       if([string]$txn.before_version -cne $oldVersion){
          throw 'R135_UNEXPECTED_OWNER_CLI_BASELINE'
       }
       $exe=Join-Path $env:LOCALAPPDATA 'spicetify\spicetify.exe'
       $actualExe=Get-ExactFileSha256 -Path $exe
       if($actualExe -cne '3563f26acd7527adc97e6c19272fa1b48ce976a913625d9804ac57d3c54fb4db'){
          throw 'R135_OFFICIAL_2464_EXECUTABLE_DRIFT'
       }
       $currentTree=Get-SpicetifyRootManifest -Path ([string]$txn.target_root)
       if([string]$currentTree.TreeSha256 -cne [string]$txn.before_tree_sha256){
          throw 'R135_OWNER_ROOT_DRIFT'
       }
       $config=Join-Path $env:APPDATA 'spicetify\config-xpui.ini'
       if([string](Get-IniSectionValue -Path $config -Section 'Backup' -Key 'with') -cne $oldVersion){
          throw 'R135_OLD_PREPROCESSOR_NOT_TRUSTED'
       }
       # Validate the official old-version rollback asset and exactly pinned
       # v2.46.7 before the durable one-use claim is created. No native calls.
       $managed=Get-SpicetifyManagedInstallInfo
       if($null -eq $managed -or -not [bool]$managed.Managed -or
          [string]$managed.Version -cne '2.46.4' -or
          [string]$managed.Path -cne $exe){
           throw 'R137_OFFICIAL_MANAGED_BASELINE_NOT_READY'
       }
       $migrationClass=Get-SpicetifyBackupMigrationClass -InstalledVersion '2.46.4' -TargetVersion '2.46.7' -BackupWith '2.46.4'
       if([string]$migrationClass -cne 'VERSION_CHANGE_REQUIRES_ATOMIC_BACKUP_REPROCESSING'){
           throw 'R137_BACKUP_PREPROCESSOR_MIGRATION_NOT_READY'
       }
       [void](Assert-R137OfficialSpicetifyPairReady)
       if(Test-SpotifyRunning){throw 'R137_SPOTIFY_RESTARTED_BEFORE_APPROVAL_CONSUMPTION'}
       $id=[string]$txn.id
       if($id -cnotmatch '^\d{8}-\d{6}-[a-f0-9]{8}$'){
          throw 'R135_INVALID_PARENT_TRANSACTION_ID'
       }
       $ledgerHash=Get-ExactFileSha256 -Path $SpicetifyTransactionPath
       $evidenceHash=[string]$txn.owner_reconciliation.evidence_sha256
       if($ledgerHash -cnotmatch '^[a-f0-9]{64}$' -or
          $evidenceHash -cnotmatch '^[a-f0-9]{64}$'){
          throw 'R135_MISSING_OWNER_PROVENANCE'
       }
       $claimPath=Get-R135OwnerAttemptPath
       $dir=Split-Path -Parent $claimPath
       if(-not (Test-Path -LiteralPath $dir -PathType Container)){
          throw 'R135_OWNER_RECOVERY_ROOT_MISSING'
       }
       $claim=[ordered]@{
          schema=1
          kind='R135_ONE_OWNER_ATTEMPT_NO_REPLAY'
          target_version='2.46.7'
          target_asset_sha256='c5a723d31eae529ba13f6922a7a027124238c7f3da7edd182a73eab03c447e9e'
          owner_transaction_id=$id
          owner_ledger_sha256=$ledgerHash
          owner_adoption_evidence_sha256=$evidenceHash
          old_executable_sha256=$actualExe
          issued_at=[DateTimeOffset]::UtcNow.ToString('o')
       }
       $bytes=[Text.UTF8Encoding]::new($false).GetBytes(
           ($claim | ConvertTo-Json -Depth 6))
       $sha=[Security.Cryptography.SHA256]::Create()
       try{$digest=[BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','').ToLowerInvariant()}
       finally{$sha.Dispose()}
       # FileMode.CreateNew is a durable no-overwrite global attempt budget.
       # Claim is committed before release discovery, native calls, or any swap.
       $stream=[IO.FileStream]::new($claimPath,[IO.FileMode]::CreateNew,
               [IO.FileAccess]::Write,[IO.FileShare]::None)
       try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}
       finally{$stream.Dispose()}
       $script:R135ClaimSHA=$digest
       $script:R135OwnerId=$id
       $script:R135AttemptCalls=1
       $script:R135ActiveOwnerAttempt=$true
       [void](Assert-R135ActiveOwnerAttempt $txn)
       Write-Log ('R135 owner-approved single target v2.46.7: attempt recorded BEFORE any target network/native call; no retry on uncertainty. original='+$id) 'WARN'
       $state=Ensure-StateShape (Load-State)
       $result=Invoke-SpicetifyTransactionalMaintenance -State $state
       if(-not [bool]$result.Success -or
          [string]$result.Status -cne 'committed' -or
          -not [bool]$result.Changed){
          throw 'R135_APPROVED_ATTEMPT_NOT_COMMITTED_NO_RETRY'
       }
       $installed=Get-SpicetifyTransaction
       if([string]$installed.status -cne 'committed' -or
          [string]$installed.after_version -cne '2.46.7' -or
          [string]$installed.before_version -cne '2.46.4'){
          throw 'R135_POST_COMMIT_VERSION_OR_JOURNAL_INVALID'
       }
       Write-Host 'R135_APPROVED_ONE_ATTEMPT_COMMITTED=YES'
       Write-Host 'R135_NEXT_AUTOMATIC_OR_MANUAL_MUTATION=HOLD_SEPARATE_APPROVAL'
       return $result
    }finally{
       $script:R135ActiveOwnerAttempt=$false
       if($null -ne $agentLease){Exit-SpotifyControlMutex -Mutex $agentLease}
       Exit-SpotifyControlMutex -Mutex $lease
    }
}


# R139 HOLD: settle the successfully committed R135 one-shot into a durable,
# owner-approved baseline before normal safe automation is re-enabled.
function Get-R139SafeAutoReceiptPath {
    return (Join-Path $Root 'owner-recovery\r139-safe-auto-baseline.v1.json')
}

function Read-R139SafeAutoReceipt {
    $path=Get-R139SafeAutoReceiptPath
    if(-not (Test-Path -LiteralPath $path -PathType Leaf)){return $null}
    $file=Get-Item -LiteralPath $path -Force -ErrorAction Stop
    if($file.PSIsContainer -or
       ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
       throw 'R139_SAFE_AUTO_RECEIPT_UNSAFE'
    }
    $r=Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if([string]$r.schema -cne '1' -or
       [string]$r.kind -cne 'R139_SAFE_AUTO_AFTER_VERIFIED_R135' -or
       [string]$r.r135_claim_sha256 -cnotmatch '^[a-f0-9]{64}$' -or
       [string]$r.r135_committed_ledger_sha256 -cnotmatch '^[a-f0-9]{64}$' -or
       [string]$r.r135_transaction_id -cnotmatch '^\d{8}-\d{6}-[a-f0-9]{8}$' -or
       [string]$r.spicetify_version -cne '2.46.7' -or
       [string]$r.spicetify_exe_sha256 -cnotmatch '^[a-f0-9]{64}$' -or
       [string]$r.r135_asset_digest -cne
          'sha256:c5a723d31eae529ba13f6922a7a027124238c7f3da7edd182a73eab03c447e9e'){
       throw 'R139_SAFE_AUTO_RECEIPT_NOT_TRUSTED'
    }
    $claimPath=Get-R135OwnerAttemptPath
    if((Get-ExactFileSha256 -Path $claimPath) -cne [string]$r.r135_claim_sha256){
       throw 'R139_R135_CLAIM_CHANGED'
    }
    [void](Read-R135OwnerAttempt)
    return $r
}

function Assert-R139ExactCommittedR135Baseline {
    $claim=Read-R135OwnerAttempt
    if($null -eq $claim){throw 'R139_R135_CLAIM_MISSING'}
    $txn=Get-SpicetifyTransaction
    if($null -eq $txn -or
       [string]$txn.status -cne 'committed' -or
       -not [bool]$txn.root_transaction -or
       [string]$txn.before_version -cne '2.46.4' -or
       [string]$txn.after_version -cne '2.46.7' -or
       [string]$txn.asset_digest -cne
          'sha256:c5a723d31eae529ba13f6922a7a027124238c7f3da7edd182a73eab03c447e9e' -or
       -not [bool]$txn.apply_attempted -or
       -not [bool]$txn.apply_succeeded -or
       -not [bool]$txn.migration_required -or
       -not [bool]$txn.migration_snapshot_ready -or
       -not [bool]$txn.migration_started -or
       -not [bool]$txn.migration_finished -or
       -not [bool]$txn.post_apply_guard_succeeded -or
       -not [bool]$txn.extras_preserved -or
       [string]$txn.extras_before_tree_sha256 -cne [string]$txn.extras_after_tree_sha256){
       throw 'R139_R135_COMMIT_NOT_EXACT'
    }
    $managed=Get-SpicetifyManagedInstallInfo
    if($null -eq $managed -or -not [bool]$managed.Managed -or
       [string]$managed.Version -cne '2.46.7'){
       throw 'R139_CURRENT_SPICETIFY_NOT_VERIFIED_2467'
    }
    $exeHash=Get-ExactFileSha256 -Path ([string]$managed.Path)
    if($exeHash -cne [string]$txn.after_sha256){
       throw 'R139_CURRENT_EXECUTABLE_NOT_R135_COMMIT'
    }
    $config=Join-Path $env:APPDATA 'spicetify\config-xpui.ini'
    if([string](Get-IniSectionValue -Path $config -Section 'Backup' -Key 'with') -cne '2.46.7'){
       throw 'R139_BACKUP_PREPROCESSOR_NOT_2467'
    }
    return [pscustomobject]@{
       Claim=$claim
       ClaimSha256=(Get-ExactFileSha256 -Path (Get-R135OwnerAttemptPath))
       Transaction=$txn
       LedgerSha256=(Get-ExactFileSha256 -Path $SpicetifyTransactionPath)
       ExeSha256=$exeHash
    }
}

function Invoke-R139EnableSafeAuto {
    param([string]$OwnerApproval)
    if($OwnerApproval -cne 'APPROVE_R139_SAFE_AUTOMATION_AFTER_VERIFIED_R135'){
       throw 'R139_EXPLICIT_OWNER_APPROVAL_REQUIRED'
    }
    if(-not (Test-SpotifyRunning)){
       throw 'R139_ENABLE_ONLY_WHILE_SPOTIFY_RUNNING'
    }
    $maintenance=Enter-SpotifyControlMutex -Purpose 'Maintenance'
    if($null -eq $maintenance){throw 'R139_MAINTENANCE_LEASE_BUSY'}
    $agent=$null
    try{
       $agent=Enter-SpotifyControlMutex -Purpose 'AgentTick'
       if($null -eq $agent){throw 'R139_AGENT_LEASE_BUSY'}
       if(-not (Test-SpotifyRunning)){throw 'R139_SPOTIFY_CLOSED_DURING_ENABLE'}
       $existing=Read-R139SafeAutoReceipt
       if($null -eq $existing){
          $proof=Assert-R139ExactCommittedR135Baseline
          $path=Get-R139SafeAutoReceiptPath
          $dir=Split-Path -Parent $path
          if(-not (Test-Path -LiteralPath $dir -PathType Container)){
             throw 'R139_OWNER_RECOVERY_ROOT_MISSING'
          }
          $receipt=[ordered]@{
             schema=1
             kind='R139_SAFE_AUTO_AFTER_VERIFIED_R135'
             r135_claim_sha256=[string]$proof.ClaimSha256
             r135_committed_ledger_sha256=[string]$proof.LedgerSha256
             r135_transaction_id=[string]$proof.Transaction.id
             spicetify_version='2.46.7'
             spicetify_exe_sha256=[string]$proof.ExeSha256
             r135_asset_digest=[string]$proof.Transaction.asset_digest
             issued_at=[DateTimeOffset]::UtcNow.ToString('o')
          }
          $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($receipt|ConvertTo-Json -Depth 5))
          $stream=[IO.FileStream]::new($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
          try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}
          finally{$stream.Dispose()}
          $existing=Read-R139SafeAutoReceipt
       }
       if($null -eq $existing){throw 'R139_RECEIPT_NOT_DURABLE'}
       $state=Ensure-StateShape (Load-State)
       $state.agent_mutation_enabled=$true
       $state.last_agent_decision='r139-safe-auto-enabled-after-verified-r135'
       Save-State $state
       $readback=Ensure-StateShape (Load-State)
       if(-not [bool]$readback.agent_mutation_enabled){
          throw 'R139_AGENT_ENABLE_READBACK_FAILED'
       }
       Write-Host 'R139_R135_BASELINE=SEALED'
       Write-Host 'R139_AGENT_MUTATION=ENABLED'
       Write-Host 'R139_PLAYBACK_MUTATION=DEFERRED_UNTIL_CLOSED'
       return $existing
    } finally {
       if($null -ne $agent){Exit-SpotifyControlMutex -Mutex $agent}
       Exit-SpotifyControlMutex -Mutex $maintenance
    }
}

function Assert-R136NoBypassFromOwnerHold {
    param([string]$RequestedAction)
    # Only ordinary playback, observation, or the independently approved
    # R135 single-target action can continue after owner adoption.
    $changes=@(
      'UpdateMarketplace','UpdateSpicetify','SpicetifyRollbackTest',
      'RollbackSpicetify','UpdateSpotify','SpotifyRollbackTest',
      'RollbackSpotify','InstallTasks','SelfUpdate','SelfUpdateRollbackTest',
      'RollbackSelfUpdate','GuardUpdates'
    )
    if($RequestedAction -cin $changes){
        if(Test-R134OwnerReconciledMutationHold){
            throw 'R136_OWNER_ADOPTION_NOT_APPROVAL_FOR_OTHER_MUTATIONS'
        }
    }
}

function Test-R134OwnerReconciledMutationHold {
    # Read the authoritative journal on EVERY mutation admission. State flags,
    # including agent_mutation_enabled=true from before R132 adoption, cannot
    # authorize a new Spicetify CLI upgrade or an unrelated maintenance write.
    $txn=Get-SpicetifyTransaction
    $claim=Read-R135OwnerAttempt
    if($null -ne $claim){
        if($script:R135ActiveOwnerAttempt -eq $true){
            [void](Assert-R135ActiveOwnerAttempt $txn)
            return $false
        }
        $settled=Read-R139SafeAutoReceipt
        if($null -ne $settled){
            $settledState=Ensure-StateShape (Load-State)
            if([bool]$settledState.agent_mutation_enabled){return $false}
            return $true
        }
        return $true
    }
    if($null -eq $txn){return $false}
    if([string]$txn.status -ceq 'owner-reviewed-preimage'){
        [void](Assert-SpicetifyOwnerPreimageAdoption $txn)
        return $true
    }
    return $false
}

function Start-SpicetifyCliTransaction {
    param([switch]$ForceReinstall)
    if(Test-R134OwnerReconciledMutationHold){
        throw 'R134_OWNER_ADOPTION_NOT_UPGRADE_APPROVAL'
    }
    if (Test-SpotifyRunning) { throw 'Spotify is running; Spicetify CLI transaction requires Spotify to be fully closed.' }
    $existing = Get-SpicetifyTransaction
    if($existing -and [string]$existing.status -ceq 'owner-reviewed-preimage'){
        [void](Assert-SpicetifyOwnerPreimageAdoption $existing)
    }elseif($existing -and [string]$existing.status -notin @('committed','rolled-back')){
        throw "An uncommitted Spicetify transaction already exists: $($existing.id) status=$($existing.status)"
    }
    $install = Get-SpicetifyManagedInstallInfo
    if (-not $install.Managed) { throw "Spicetify executable is not managed by the official LOCALAPPDATA installation; refusing automatic replacement. path=$($install.Path)" }
    $targetRoot = Split-Path -Parent ([string]$install.Path)
    $currentVersion = [string]$install.Version
    if ([string]::IsNullOrWhiteSpace($currentVersion)) { throw 'Could not determine installed Spicetify version.' }
    $latest = if($script:R135ActiveOwnerAttempt -eq $true){
        [void](Assert-R135ActiveOwnerAttempt $existing)
        Get-SpicetifyReleaseInfoForVersion -Version '2.46.7'
    }else{
        Get-SpicetifyLatestReleaseInfo
    }
    if (-not $latest.Verified) { throw $latest.Error }
    if($script:R135ActiveOwnerAttempt -eq $true -and
       ([string]$latest.Tag -cne 'v2.46.7' -or
        [string]$latest.Version -cne '2.46.7' -or
        [string]$latest.Architecture -cne 'x64' -or
        [string]$latest.AssetDigest -cne
          'sha256:c5a723d31eae529ba13f6922a7a027124238c7f3da7edd182a73eab03c447e9e')){
        throw 'R135_OFFICIAL_TARGET_2467_ASSET_PIN_MISMATCH'
    }
    $cmp = Compare-VersionParts -A $latest.Version -B $currentVersion -Count 3
    if ($null -eq $cmp) { throw "Could not compare Spicetify versions $currentVersion and $($latest.Version)." }
    if ($cmp -lt 0) { throw "Installed Spicetify $currentVersion is newer than GitHub latest $($latest.Version); refusing downgrade." }
    if ($cmp -eq 0 -and -not $ForceReinstall) { return [pscustomobject]@{ Changed=$false; Status='already-current'; Transaction=$null; Latest=$latest } }
    # Do NOT swap a new CLI while its preprocessed assets were generated by
    # the old CLI. Upstream Apply() exits 1 before checking Spotify state when
    # Backup.with != running CLI version. A valid migration must snapshot and
    # restore Spotify Apps + Roaming Spicetify Backup/config, not just the exe.
    $spiceConfig=Get-ConfigPath
    if ([string]::IsNullOrWhiteSpace([string]$spiceConfig)) {
        throw 'R130_BACKUP_PREPROCESSOR_CONFIG_UNVERIFIED_NO_ROOT_MUTATION'
    }
    $backupWith=Get-IniSectionValue -Path $spiceConfig -Section 'Backup' -Key 'with'
    $upgradeClass=Get-SpicetifyBackupMigrationClass -InstalledVersion $currentVersion -TargetVersion ([string]$latest.Version) -BackupWith ([string]$backupWith)
    if ($upgradeClass -cnotin @('BACKUP_PREPROCESSOR_CURRENT',
        'VERSION_CHANGE_REQUIRES_ATOMIC_BACKUP_REPROCESSING')) {
        throw ('R131_PREPROCESSOR_PREIMAGE_INVALID:'+$upgradeClass)
    }
    $migratePreprocessed=($upgradeClass -ceq 'VERSION_CHANGE_REQUIRES_ATOMIC_BACKUP_REPROCESSING')

    $id = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)
    $work = Join-Path $Root ('staging\spicetify-' + $id)
    $txnBackupDir = Join-Path $BackupDir ('spicetify-transactions\' + $id)
    $backupRoot = Join-Path $txnBackupDir 'root-before'
    $parentRoot = Split-Path -Parent $targetRoot
    $sameDirNewRoot = Join-Path $parentRoot ('.spotifycontrol-spicetify-new-' + $id)
    $sameDirOldRoot = Join-Path $parentRoot ('.spotifycontrol-spicetify-old-' + $id)
    New-Item -ItemType Directory -Force -Path $work,$txnBackupDir | Out-Null
    try {
        $latestWork = Join-Path $work 'latest-release'
        New-Item -ItemType Directory -Force -Path $latestWork | Out-Null
        $afterPayload = Expand-AndValidateSpicetifyAsset -ReleaseInfo $latest -WorkRoot $latestWork
        $beforeRelease = if ([string]$latest.Version -ceq $currentVersion) { $latest } else { Get-SpicetifyReleaseInfoForVersion -Version $currentVersion }
        if (-not $beforeRelease.Verified) { throw "Could not establish the exact official installed Spicetify baseline: $($beforeRelease.Error)" }
        $beforePayload = if ([string]$latest.Version -ceq $currentVersion) {
            $afterPayload
        } else {
            $beforeWork = Join-Path $work 'installed-release'
            New-Item -ItemType Directory -Force -Path $beforeWork | Out-Null
            Expand-AndValidateSpicetifyAsset -ReleaseInfo $beforeRelease -WorkRoot $beforeWork
        }
        $baseline = Test-SpicetifyLivePayloadBaseline -LiveRoot $targetRoot -Payload $beforePayload
        if (-not $baseline.Verified) { throw "Installed Spicetify root is not an exact official $($beforeRelease.Tag) payload baseline: $($baseline.Error)" }
        Assert-SpicetifyOverlaySafe -LiveManifest $baseline.LiveManifest -BeforePayloadManifest $beforePayload.Manifest -AfterPayloadManifest $afterPayload.Manifest
        $beforeManifest = $baseline.LiveManifest
        [void](Copy-SpicetifyRootExact -Source $targetRoot -Destination $backupRoot -ExpectedTreeSha256 $beforeManifest.TreeSha256)
        $persistentBackupManifest = Get-SpicetifyRootManifest -Path $backupRoot
        if ($persistentBackupManifest.TreeSha256 -cne $beforeManifest.TreeSha256) { throw "Spicetify persistent rollback backup tree mismatch. expected=$($beforeManifest.TreeSha256) actual=$($persistentBackupManifest.TreeSha256)" }
        [void](Copy-SpicetifyRootExact -Source $targetRoot -Destination $sameDirNewRoot -ExpectedTreeSha256 $beforeManifest.TreeSha256)
        Remove-ObsoleteSpicetifyPayloadPaths -DestinationRoot $sameDirNewRoot -BeforePayloadManifest $beforePayload.Manifest -AfterPayloadManifest $afterPayload.Manifest
        Overlay-SpicetifyPayload -Payload $afterPayload -DestinationRoot $sameDirNewRoot
        $afterManifest = Assert-SpicetifyPayloadApplied -RootPath $sameDirNewRoot -PayloadManifest $afterPayload.Manifest
        $extraProof = Assert-SpicetifyNonPayloadPreserved -BeforeManifest $beforeManifest -AfterManifest $afterManifest -BeforePayloadManifest $beforePayload.Manifest -AfterPayloadManifest $afterPayload.Manifest
        $stagedExe = Join-Path $sameDirNewRoot 'spicetify.exe'
        if ((Get-ExactFileSha256 -Path $stagedExe) -cne [string]$afterPayload.ExeSha256) { throw 'Staged full-root Spicetify executable hash mismatch.' }
        $stageVersion = Invoke-NativeCapture -FilePath $stagedExe -Arguments @('--version')
        if ($stageVersion.ExitCode -ne 0 -or [string]$stageVersion.Output -notmatch [regex]::Escape([string]$latest.Version)) { throw "Staged full-root Spicetify version verification failed: $($stageVersion.Output)" }
        $compatAfter = Get-SpicetifyReleaseCompatibilityForVersion -Version $latest.Version
        if (-not $compatAfter.Verified) { throw $compatAfter.Error }
        $external=$null
    if($migratePreprocessed){
      $external=New-SpicetifyMigrationPreimage -TransactionBackupDir $txnBackupDir -InstalledCliVersion $currentVersion
    }
    $txn = [pscustomobject]@{
            schema=3; root_transaction=$true; id=$id; status='prepared'; target_root=$targetRoot; target_path=(Join-Path $targetRoot 'spicetify.exe')
            backup_root=$backupRoot; backup_path=(Join-Path $backupRoot 'spicetify.exe'); same_dir_new_root=$sameDirNewRoot; same_dir_old_root=$sameDirOldRoot
            same_dir_new=$null; same_dir_old=$null; before_tree_sha256=$beforeManifest.TreeSha256; after_tree_sha256=$afterManifest.TreeSha256
            before_file_count=$beforeManifest.FileCount; after_file_count=$afterManifest.FileCount; payload_tree_sha256=$afterPayload.Manifest.TreeSha256
            payload_file_count=$afterPayload.Manifest.FileCount; extras_preserved=$true; extra_file_count=$extraProof.Before.FileCount; extras_before_tree_sha256=$extraProof.Before.TreeSha256; extras_after_tree_sha256=$extraProof.After.TreeSha256
            before_version=$currentVersion; before_sha256=(Get-ExactFileSha256 -Path ([string]$install.Path)); before_release_tag=$beforeRelease.Tag; before_asset_digest=$beforeRelease.AssetDigest
            after_version=$latest.Version; after_sha256=$afterPayload.ExeSha256; release_tag=$latest.Tag; asset_digest=$latest.AssetDigest; asset_size=$latest.AssetSize
            compatibility_min=$compatAfter.Min; compatibility_max=$compatAfter.Max; started_at=(Get-Date).ToString('o'); swapped_at=$null
            apply_attempted=$false; apply_succeeded=$false; apply_at=$null; post_apply_guard_succeeded=$false; post_apply_guard_at=$null
            rollback_reapply_succeeded=$null; rollback_reapply_at=$null; committed_at=$null; rolled_back_at=$null; error=$null
            migration_required=$migratePreprocessed; migration_snapshot_ready=($null -ne $external)
            migration_started=$false; migration_finished=$false; migration_external_rollback_restored=$false
            migration_snapshot_root=$(if($external){$external.BackupRoot}else{$null})
            migration_spicetify_root=$(if($external){$external.Roaming}else{$null})
            migration_apps_root=$(if($external){$external.Apps}else{$null})
            migration_spicetify_before_sha256=$(if($external){$external.RoamingTreeSha256}else{$null})
            migration_apps_before_sha256=$(if($external){$external.AppsTreeSha256}else{$null})
            migration_semantic_before_sha256=$(if($external){$external.SemanticHash}else{$null})
            migration_spicetify_after_sha256=$null; migration_apps_after_sha256=$null
        }
        Save-SpicetifyTransaction -Transaction $txn
        if (Test-SpotifyRunning) { throw 'Spotify started during Spicetify staging; transaction aborted before full-root swap.' }
        $liveBeforeSwap = Get-SpicetifyRootManifest -Path $targetRoot
        if ($liveBeforeSwap.TreeSha256 -cne $beforeManifest.TreeSha256) { throw 'Installed Spicetify root changed after backup; refusing full-root swap.' }
        $backupBeforeSwap = Get-SpicetifyRootManifest -Path $backupRoot
        if ($backupBeforeSwap.TreeSha256 -cne $beforeManifest.TreeSha256) { throw 'Spicetify persistent rollback backup tree mismatch immediately before swap.' }
        if (Test-Path -LiteralPath $sameDirOldRoot) { throw "Reserved old-root swap path unexpectedly exists: $sameDirOldRoot" }
        Move-Item -LiteralPath $targetRoot -Destination $sameDirOldRoot
        try {
            Move-Item -LiteralPath $sameDirNewRoot -Destination $targetRoot
        } catch {
            if (-not (Test-Path -LiteralPath $targetRoot) -and (Test-Path -LiteralPath $sameDirOldRoot -PathType Container)) { Move-Item -LiteralPath $sameDirOldRoot -Destination $targetRoot }
            throw
        }
        if (-not (Test-Path -LiteralPath $sameDirOldRoot -PathType Container)) { throw 'Same-volume old Spicetify root disappeared before commit.' }
        $oldAfterSwap = Get-SpicetifyRootManifest -Path $sameDirOldRoot
        if ($oldAfterSwap.TreeSha256 -cne $beforeManifest.TreeSha256) { throw 'Same-volume old Spicetify root no longer matches the before tree.' }
        $liveAfterSwap = Get-SpicetifyRootManifest -Path $targetRoot
        if ($liveAfterSwap.TreeSha256 -cne $afterManifest.TreeSha256) { throw "Post-swap Spicetify root manifest mismatch. expected=$($afterManifest.TreeSha256) actual=$($liveAfterSwap.TreeSha256)" }
        if ((Get-ExactFileSha256 -Path (Join-Path $targetRoot 'spicetify.exe')) -cne [string]$afterPayload.ExeSha256) { throw 'Post-swap Spicetify executable hash mismatch.' }
        $r = Invoke-NativeCapture -FilePath (Join-Path $targetRoot 'spicetify.exe') -Arguments @('--version')
        if ($r.ExitCode -ne 0 -or [string]$r.Output -notmatch [regex]::Escape($latest.Version)) { throw "Post-swap Spicetify --version verification failed: $($r.Output)" }
        $txn.status='awaiting-guard'; $txn.swapped_at=(Get-Date).ToString('o'); Save-SpicetifyTransaction -Transaction $txn
        $script:Spicetify = Get-SpicetifyCommand
        Write-Log "Spicetify full-root transaction $id swapped $currentVersion -> $($latest.Version), preserving $($baseline.ExtraFileCount) extra file(s); commit is deferred until compatibility/guard/apply verification succeeds."
        return [pscustomobject]@{ Changed=$true; Status='awaiting-guard'; Transaction=$txn; Latest=$latest }
    } catch {
        $err = $_.Exception.Message
        $rollbackError = $null
        try {
            $txnNow = Get-SpicetifyTransaction
            if ($txnNow -and [string]$txnNow.id -eq $id) {
                $txnNow.error=$err; Save-SpicetifyTransaction -Transaction $txnNow
                if ([string]$txnNow.status -notin @('committed','rolled-back')) { try { [void](Rollback-SpicetifyCliTransaction) } catch { $rollbackError=$_.Exception.Message } }
            } elseif ((Test-Path -LiteralPath $sameDirOldRoot -PathType Container) -and -not (Test-Path -LiteralPath $targetRoot)) {
                Move-Item -LiteralPath $sameDirOldRoot -Destination $targetRoot
            }
        } catch { if (-not $rollbackError) { $rollbackError=$_.Exception.Message } }
        if ($rollbackError) { throw ("Spicetify transaction failed: " + $err + " | rollback_failed=" + $rollbackError) }
        throw $err
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $sameDirNewRoot -PathType Container) { Remove-Item -LiteralPath $sameDirNewRoot -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function Rollback-LegacySpicetifyCliTransaction {
    param($txn)
    $target=[string]$txn.target_path; $backup=[string]$txn.backup_path
    $backupHash=Get-ExactFileSha256 -Path $backup
    if ($backupHash -cne [string]$txn.before_sha256) { throw "Legacy Spicetify rollback backup is missing/corrupt for transaction $($txn.id)." }
    $liveHash=Get-ExactFileSha256 -Path $target
    if ($liveHash -and $liveHash -cne [string]$txn.before_sha256 -and $liveHash -cne [string]$txn.after_sha256) { throw 'Legacy live Spicetify executable matches neither transaction before nor after hash; refusing destructive rollback.' }
    if ($liveHash -cne [string]$txn.before_sha256) {
        $quarantine = Join-Path (Split-Path -Parent $target) ('.spotifycontrol-rollback-current-' + $txn.id + '.exe')
        if (Test-Path -LiteralPath $quarantine -PathType Leaf) { Remove-Item -LiteralPath $quarantine -Force }
        if (Test-Path -LiteralPath $target -PathType Leaf) { Move-Item -LiteralPath $target -Destination $quarantine }
        try { Copy-Item -LiteralPath $backup -Destination $target -Force } catch { if (-not (Test-Path -LiteralPath $target -PathType Leaf) -and (Test-Path -LiteralPath $quarantine -PathType Leaf)) { Move-Item -LiteralPath $quarantine -Destination $target }; throw }
        Remove-Item -LiteralPath $quarantine -Force -ErrorAction SilentlyContinue
    }
    if ((Get-ExactFileSha256 -Path $target) -cne [string]$txn.before_sha256) { throw 'Legacy Spicetify rollback hash verification failed.' }
    if ([bool]$txn.apply_attempted) {
        $restoreApply=Invoke-NativeCapture -FilePath $target -Arguments @('apply','--no-restart')
        $txn.rollback_reapply_succeeded=($restoreApply.ExitCode -eq 0); $txn.rollback_reapply_at=(Get-Date).ToString('o')
        if ($restoreApply.ExitCode -ne 0) { $txn.status='rollback-binary-restored-apply-failed'; $txn.error="Old Spicetify binary restored, but restore apply failed: $($restoreApply.Output)"; Save-SpicetifyTransaction -Transaction $txn; throw $txn.error }
    }
    foreach($leftover in @([string]$txn.same_dir_new,[string]$txn.same_dir_old)){ if(-not [string]::IsNullOrWhiteSpace($leftover)){ Remove-Item -LiteralPath $leftover -Force -ErrorAction SilentlyContinue } }
    $txn.status='rolled-back'; $txn.rolled_back_at=(Get-Date).ToString('o'); Save-SpicetifyTransaction -Transaction $txn
    return [pscustomobject]@{ Success=$true; Status='rolled-back'; Transaction=$txn }
}

function Rollback-SpicetifyCliTransaction {
    $txn = Get-SpicetifyTransaction
    if([string]$txn.status -ceq 'owner-reviewed-preimage'){
        [void](Assert-SpicetifyOwnerPreimageAdoption $txn)
        throw 'R134_OWNER_ADOPTION_NOT_ROLLBACK_PERMISSION'
    }
    if (-not $txn) { return [pscustomobject]@{ Success=$true; Status='none'; Transaction=$null } }
    if ([string]$txn.status -eq 'rolled-back') { return [pscustomobject]@{ Success=$true; Status='rolled-back'; Transaction=$txn } }
    if ([string]$txn.status -eq 'committed') { throw "Spicetify transaction $($txn.id) is already committed; automatic rollback is not allowed." }
    if (-not [bool]$txn.root_transaction) {
        $legacy=Rollback-LegacySpicetifyCliTransaction -txn $txn
        $script:Spicetify=Get-SpicetifyCommand
        Write-Log "Rolled back legacy executable-only Spicetify transaction $($txn.id)." 'WARN'
        return $legacy
    }
    $targetRoot=[string]$txn.target_root; $backupRoot=[string]$txn.backup_root; $oldRoot=[string]$txn.same_dir_old_root; $newRoot=[string]$txn.same_dir_new_root
    if (-not (Test-Path -LiteralPath $backupRoot -PathType Container)) { throw "Spicetify rollback root backup is missing: $backupRoot" }
    $backupManifest=Get-SpicetifyRootManifest -Path $backupRoot
    if ($backupManifest.TreeSha256 -cne [string]$txn.before_tree_sha256) { throw "Spicetify rollback root backup is corrupt. expected=$($txn.before_tree_sha256) actual=$($backupManifest.TreeSha256)" }
    $liveManifest=$null
    if (Test-Path -LiteralPath $targetRoot -PathType Container) { $liveManifest=Get-SpicetifyRootManifest -Path $targetRoot }
    if ($liveManifest -and $liveManifest.TreeSha256 -cne [string]$txn.before_tree_sha256 -and $liveManifest.TreeSha256 -cne [string]$txn.after_tree_sha256) { throw 'Live Spicetify root matches neither transaction before nor after tree; refusing destructive rollback.' }
    if (Test-Path -LiteralPath $oldRoot -PathType Container) {
        $oldManifest=Get-SpicetifyRootManifest -Path $oldRoot
        if ($oldManifest.TreeSha256 -cne [string]$txn.before_tree_sha256) { throw 'Same-volume Spicetify old-root backup does not match transaction before tree; refusing rollback.' }
    }
    $quarantine = Join-Path (Split-Path -Parent $targetRoot) ('.spotifycontrol-spicetify-rollback-current-' + [string]$txn.id)
    if(Test-Path -LiteralPath $quarantine){
        # Only a displaced, byte-exact after-root from this transaction is
        # allowed to survive across an interrupted root rollback.
        $quarantineManifest=Get-SpicetifyRootManifest -Path $quarantine
        if($quarantineManifest.TreeSha256 -cne [string]$txn.after_tree_sha256 -or
           ($liveManifest -and $liveManifest.TreeSha256 -cne [string]$txn.before_tree_sha256)){
          throw 'R131_INTERRUPTED_CLI_QUARANTINE_CONFLICT_HOLD'
        }
    }
    if (-not $liveManifest -or $liveManifest.TreeSha256 -cne [string]$txn.before_tree_sha256) {
        if ($liveManifest) { Move-Item -LiteralPath $targetRoot -Destination $quarantine }
        try {
            if (Test-Path -LiteralPath $oldRoot -PathType Container) {
                Move-Item -LiteralPath $oldRoot -Destination $targetRoot
            } else {
                $restoreRoot=Join-Path (Split-Path -Parent $targetRoot) ('.spotifycontrol-spicetify-restore-' + [string]$txn.id)
                if(Test-Path -LiteralPath $restoreRoot){
        $restoreManifest=Get-SpicetifyRootManifest -Path $restoreRoot
        if($restoreManifest.TreeSha256 -cne [string]$txn.before_tree_sha256){
          throw 'R131_INTERRUPTED_CLI_RESTORE_STAGE_INVALID_HOLD'
        }
    }else{
        [void](Copy-SpicetifyRootExact -Source $backupRoot -Destination $restoreRoot -ExpectedTreeSha256 ([string]$txn.before_tree_sha256))
    }
                Move-Item -LiteralPath $restoreRoot -Destination $targetRoot
            }
        } catch {
            if (-not (Test-Path -LiteralPath $targetRoot) -and (Test-Path -LiteralPath $quarantine -PathType Container)) { Move-Item -LiteralPath $quarantine -Destination $targetRoot }
            throw
        }
    }
    $restoredManifest=Get-SpicetifyRootManifest -Path $targetRoot
    if ($restoredManifest.TreeSha256 -cne [string]$txn.before_tree_sha256) { throw 'Spicetify full-root rollback tree verification failed.' }
    $targetExe=Join-Path $targetRoot 'spicetify.exe'
    if ((Get-ExactFileSha256 -Path $targetExe) -cne [string]$txn.before_sha256) { throw 'Spicetify rollback executable hash verification failed.' }
    $r=Invoke-NativeCapture -FilePath $targetExe -Arguments @('--version')
    if ($r.ExitCode -ne 0 -or [string]$r.Output -notmatch [regex]::Escape([string]$txn.before_version)) { throw "Spicetify rollback version verification failed: $($r.Output)" }
    if([bool]$txn.migration_required){
        $restore=Restore-SpicetifyMigrationPreimage -Txn $txn
        if(-not $restore.Restored){throw 'R131_EXTERNAL_RESTORE_NOT_VERIFIED'}
        $txn.migration_external_rollback_restored=$true
        $txn.rollback_reapply_succeeded=$null
        $txn.rollback_reapply_at=$null
        Save-SpicetifyTransaction -Transaction $txn
    } elseif ([bool]$txn.apply_attempted) {
        $restoreApply=Invoke-NativeCapture -FilePath $targetExe -Arguments @('apply','--no-restart')
        $txn.rollback_reapply_succeeded=($restoreApply.ExitCode -eq 0); $txn.rollback_reapply_at=(Get-Date).ToString('o')
        if ($restoreApply.ExitCode -ne 0) { $txn.status='rollback-root-restored-apply-failed'; $txn.error="Old Spicetify root restored, but restore apply failed: $($restoreApply.Output)"; Save-SpicetifyTransaction -Transaction $txn; throw $txn.error }
    }
    foreach($leftover in @($newRoot,$oldRoot,$quarantine)){ if(-not [string]::IsNullOrWhiteSpace([string]$leftover) -and (Test-Path -LiteralPath $leftover)){ Remove-Item -LiteralPath $leftover -Recurse -Force -ErrorAction SilentlyContinue } }
    $txn.status='rolled-back'; $txn.rolled_back_at=(Get-Date).ToString('o'); Save-SpicetifyTransaction -Transaction $txn
    $script:Spicetify=Get-SpicetifyCommand
    Write-Log "Rolled back and verified full Spicetify root transaction $($txn.id)." 'WARN'
    return [pscustomobject]@{ Success=$true; Status='rolled-back'; Transaction=$txn }
}

function Commit-SpicetifyCliTransaction {
    $txn=Get-SpicetifyTransaction
    if (-not $txn) { throw 'No Spicetify transaction ledger exists to commit.' }
    if ([string]$txn.status -eq 'committed') { return [pscustomobject]@{ Success=$true; Status='committed'; Transaction=$txn } }
    if ([string]$txn.status -ne 'awaiting-guard') { throw "Spicetify transaction is not commit-ready: status=$($txn.status)" }
    if (-not [bool]$txn.root_transaction) { throw 'Executable-only Spicetify transactions cannot be newly committed by v0.6.8; roll back and retry as a full-root transaction.' }
    $live=Get-SpicetifyRootManifest -Path ([string]$txn.target_root)
    if ($live.TreeSha256 -cne [string]$txn.after_tree_sha256) { throw 'Spicetify commit root no longer matches the fully staged after tree.' }
    $targetExe=Join-Path ([string]$txn.target_root) 'spicetify.exe'
    if ((Get-ExactFileSha256 -Path $targetExe) -cne [string]$txn.after_sha256) { throw 'Spicetify commit executable hash no longer matches staged release.' }
    $r=Invoke-NativeCapture -FilePath $targetExe -Arguments @('--version')
    if ($r.ExitCode -ne 0 -or [string]$r.Output -notmatch [regex]::Escape([string]$txn.after_version)) { throw "Spicetify commit version verification failed: $($r.Output)" }
    if (-not [bool]$txn.extras_preserved -or [string]$txn.extras_before_tree_sha256 -cne [string]$txn.extras_after_tree_sha256) { throw 'Spicetify commit lacks exact non-payload/user-file preservation proof.' }
    if([bool]$txn.migration_required){
        if(-not [bool]$txn.migration_snapshot_ready -or
           -not [bool]$txn.migration_finished -or
           -not [bool]$txn.apply_succeeded -or
           -not [bool]$txn.post_apply_guard_succeeded){
            throw 'R131_COMMIT_MIGRATION_INCOMPLETE'
        }
        # Pin the original after-image values before mutating PSCustomObject.
        $pinnedApps=[string]$txn.migration_apps_after_sha256
        $pinnedRoaming=[string]$txn.migration_spicetify_after_sha256
        if($pinnedApps -cnotmatch '^[a-f0-9]{64}$' -or
           $pinnedRoaming -cnotmatch '^[a-f0-9]{64}$'){
            throw 'R131_COMMIT_EXTERNAL_AFTER_PINS_MISSING'
        }
        # Probe a detached in-memory copy: a rejected commit must not
        # overwrite pinned expectations even for a later invocation.
        $probe=$txn | ConvertTo-Json -Depth 8 | ConvertFrom-Json
        $current=Confirm-SpicetifyMigrationApplied $probe
        if([string]$current.migration_apps_after_sha256 -cne $pinnedApps -or
           [string]$current.migration_spicetify_after_sha256 -cne $pinnedRoaming){
            throw 'R131_COMMIT_EXTERNAL_AFTER_TREE_CHANGED'
        }
    }
    foreach($leftover in @([string]$txn.same_dir_old_root,[string]$txn.same_dir_new_root)){ if(-not [string]::IsNullOrWhiteSpace($leftover) -and (Test-Path -LiteralPath $leftover)){ Remove-Item -LiteralPath $leftover -Recurse -Force -ErrorAction SilentlyContinue } }
    $txn.status='committed'; $txn.committed_at=(Get-Date).ToString('o'); Save-SpicetifyTransaction -Transaction $txn
    Write-Log "Committed full-root Spicetify transaction $($txn.id): $($txn.before_version) -> $($txn.after_version); user extras preserved=$($txn.extras_preserved)."
    return [pscustomobject]@{ Success=$true; Status='committed'; Transaction=$txn }
}

function Repair-PendingSpicetifyTransaction {
    $txn=Get-SpicetifyTransaction
    if (-not $txn) { return $null }
    if ([string]$txn.status -in @('committed','rolled-back')) { return $txn }
    if([string]$txn.status -ceq 'owner-reviewed-preimage'){
           [void](Assert-SpicetifyOwnerPreimageAdoption $txn)
           return $txn
       }
       if($null -eq $txn.PSObject.Properties['migration_required']){
           throw 'R131_UNSETTLED_PRE_MIGRATION_LEDGER_OWNER_REVIEW_HOLD'
       }
       if([bool]$txn.migration_required -and -not [bool]$txn.migration_snapshot_ready){
           throw 'R131_UNSETTLED_MIGRATION_SNAPSHOT_NOT_CERTIFIED_HOLD'
       }
       Write-Log "Found uncommitted Spicetify transaction $($txn.id) status=$($txn.status); rolling it back before new mutation." 'WARN'
    [void](Rollback-SpicetifyCliTransaction)
    return Get-SpicetifyTransaction
}

function Invoke-SpicetifyTransactionalMaintenance {
    param($State,[switch]$ForceReinstall,[switch]$RollbackAfterSwap)
    $State=Ensure-StateShape $State
    [void](Repair-PendingSpicetifyTransaction)
    $start=Start-SpicetifyCliTransaction -ForceReinstall:$ForceReinstall
    $State.last_spicetify_upgrade_check=[DateTimeOffset]::UtcNow.ToString('o')
    if (-not $start.Changed) {
        $State.pending_spicetify_upgrade=$false
        $State.spicetify_installed_version=Get-InstalledSpicetifyVersion
        $State.spicetify_install_mode=(Get-SpicetifyManagedInstallInfo).Mode
        Save-State $State
        return [pscustomobject]@{ Success=$true; Changed=$false; Status='already-current'; State=$State; GuardPlan=$null; GuardResult=$null; Transaction=$null }
    }
    $txn=$start.Transaction
    if (Test-SpotifyRunning) {
        [void](Rollback-SpicetifyCliTransaction)
        $State.pending_spicetify_upgrade=$true
        $State.spicetify_last_transaction_id=[string]$txn.id; $State.spicetify_last_transaction_status='rolled-back-spotify-started'; $State.spicetify_last_transaction_utc=[DateTimeOffset]::UtcNow.ToString('o')
        Save-State $State
        return [pscustomobject]@{ Success=$false; Changed=$true; Status='rolled-back-spotify-started'; State=$State; GuardPlan=$null; GuardResult=$null; Transaction=(Get-SpicetifyTransaction) }
    }
    if ($RollbackAfterSwap) {
        $rb=Rollback-SpicetifyCliTransaction
        $State.spicetify_last_transaction_id=[string]$txn.id; $State.spicetify_last_transaction_status='rolled-back'; $State.spicetify_last_transaction_utc=[DateTimeOffset]::UtcNow.ToString('o')
        $State.spicetify_installed_version=Get-InstalledSpicetifyVersion; $State.spicetify_install_mode=(Get-SpicetifyManagedInstallInfo).Mode
        Save-State $State
        return [pscustomobject]@{ Success=$rb.Success; Changed=$true; Status='rolled-back'; State=$State; GuardPlan=$null; GuardResult=$null; Transaction=$rb.Transaction }
    }

    $plan=$null
    $guard=$null
    try {
        $plan=Get-SmartUpdateGuardPlan
        if ($plan.CurrentSupported -ne $true) {
            throw "Installed Spotify is not verified inside the new Spicetify compatibility range $($plan.MinSupported) -> $($plan.MaxSupported)."
        }
        $guard=Invoke-SmartUpdateGuard -State $State -Plan $plan
        $State=Ensure-StateShape $guard.State
        if (-not $guard.Success) { throw 'Smart Update Guard could not be enforced after the Spicetify executable swap.' }
    } catch {
        $verificationError=$_.Exception.Message
        try { [void](Rollback-SpicetifyCliTransaction) }
        catch { throw ("Post-swap compatibility/guard verification failed: " + $verificationError + " | rollback failed=" + $_.Exception.Message) }
        $script:Spicetify=Get-SpicetifyCommand
        $oldPlan=Get-SmartUpdateGuardPlan
        try { [void](Invoke-SmartUpdateGuard -State $State -Plan $oldPlan) }
        catch { throw ("New CLI was rolled back, but old Smart Update Guard restoration failed: " + $_.Exception.Message) }
        $State=Ensure-StateShape (Load-State); $State.pending_spicetify_upgrade=$true
        $State.spicetify_last_transaction_id=[string]$txn.id; $State.spicetify_last_transaction_status='rolled-back-post-swap-verification-failure'; $State.spicetify_last_transaction_utc=[DateTimeOffset]::UtcNow.ToString('o'); Save-State $State
        return [pscustomobject]@{ Success=$false; Changed=$true; Status='rolled-back-post-swap-verification-failure'; State=$State; GuardPlan=$plan; GuardResult=$guard; Transaction=(Get-SpicetifyTransaction) }
    }
    if (Test-SpotifyRunning) {
        [void](Rollback-SpicetifyCliTransaction)
        $script:Spicetify=Get-SpicetifyCommand
        $oldPlan=Get-SmartUpdateGuardPlan
        $oldGuard=Invoke-SmartUpdateGuard -State $State -Plan $oldPlan
        $State=Ensure-StateShape $oldGuard.State
        if (-not $oldGuard.Success) { throw 'Spotify started before apply; old CLI was restored, but old Smart Update Guard restoration failed.' }
        $State.pending_spicetify_upgrade=$true
        $State.spicetify_installed_version=Get-InstalledSpicetifyVersion
        $State.spicetify_compat_tag=$oldPlan.SpicetifyTag
        $State.spicetify_compat_min_windows=$oldPlan.MinSupported
        $State.spicetify_max_windows=$oldPlan.MaxSupported
        $State.spicetify_last_transaction_id=[string]$txn.id; $State.spicetify_last_transaction_status='rolled-back-spotify-started-before-apply'; $State.spicetify_last_transaction_utc=[DateTimeOffset]::UtcNow.ToString('o')
        Save-State $State
        return [pscustomobject]@{ Success=$false; Changed=$true; Status='rolled-back-spotify-started-before-apply'; State=$State; GuardPlan=$oldPlan; GuardResult=$oldGuard; Transaction=(Get-SpicetifyTransaction) }
    }

    $txnForApply = Get-SpicetifyTransaction
    $txnForApply.apply_attempted = $true
    if([bool]$txnForApply.migration_required){$txnForApply.migration_started=$true}
    Save-SpicetifyTransaction -Transaction $txnForApply
    try {
        if([bool]$txnForApply.migration_required){
            [void](Invoke-Spice -Arguments @('restore','backup','apply','--no-restart'))
            $txnForApply=Confirm-SpicetifyMigrationApplied (Get-SpicetifyTransaction)
            Save-SpicetifyTransaction -Transaction $txnForApply
        }else{
            [void](Invoke-Spice -Arguments @('apply','--no-restart'))
            $txnForApply=Get-SpicetifyTransaction
        }
        $txnForApply.apply_succeeded = $true
        $txnForApply.apply_at = (Get-Date).ToString('o')
        Save-SpicetifyTransaction -Transaction $txnForApply
    } catch {
        $applyError = $_.Exception.Message
        try { [void](Rollback-SpicetifyCliTransaction) }
        catch { throw ("New Spicetify apply failed: " + $applyError + " | rollback/old-reapply failed=" + $_.Exception.Message) }
        $script:Spicetify=Get-SpicetifyCommand
        $oldPlan=Get-SmartUpdateGuardPlan
        [void](Invoke-SmartUpdateGuard -State $State -Plan $oldPlan)
        $State=Ensure-StateShape (Load-State); $State.pending_spicetify_upgrade=$true
        $State.spicetify_last_transaction_id=[string]$txn.id; $State.spicetify_last_transaction_status='rolled-back-apply-failure'; $State.spicetify_last_transaction_utc=[DateTimeOffset]::UtcNow.ToString('o'); Save-State $State
        return [pscustomobject]@{ Success=$false; Changed=$true; Status='rolled-back-apply-failure'; State=$State; GuardPlan=$plan; GuardResult=$guard; Transaction=(Get-SpicetifyTransaction) }
    }

    try {
        $postApplyPlan = Get-SmartUpdateGuardPlan
        if ($postApplyPlan.CurrentSupported -ne $true) { throw 'Current Spotify compatibility became unverified after Spicetify apply.' }
        $postApplyGuard = Invoke-SmartUpdateGuard -State $State -Plan $postApplyPlan
        $State = Ensure-StateShape $postApplyGuard.State
        if (-not $postApplyGuard.Success) { throw 'Smart Update Guard could not be re-verified after Spicetify apply.' }
        $txnForApply = Get-SpicetifyTransaction
        $txnForApply.post_apply_guard_succeeded = $true
        $txnForApply.post_apply_guard_at = (Get-Date).ToString('o')
        Save-SpicetifyTransaction -Transaction $txnForApply
        $plan = $postApplyPlan
        $guard = $postApplyGuard
    } catch {
        $postApplyError = $_.Exception.Message
        try { [void](Rollback-SpicetifyCliTransaction) }
        catch { throw ("Post-apply compatibility/guard verification failed: " + $postApplyError + " | rollback/old-reapply failed=" + $_.Exception.Message) }
        $script:Spicetify=Get-SpicetifyCommand
        $oldPlan=Get-SmartUpdateGuardPlan
        [void](Invoke-SmartUpdateGuard -State $State -Plan $oldPlan)
        $State=Ensure-StateShape (Load-State); $State.pending_spicetify_upgrade=$true
        $State.spicetify_last_transaction_id=[string]$txn.id; $State.spicetify_last_transaction_status='rolled-back-post-apply-guard-failure'; $State.spicetify_last_transaction_utc=[DateTimeOffset]::UtcNow.ToString('o'); Save-State $State
        return [pscustomobject]@{ Success=$false; Changed=$true; Status='rolled-back-post-apply-guard-failure'; State=$State; GuardPlan=$postApplyPlan; GuardResult=$null; Transaction=(Get-SpicetifyTransaction) }
    }

    $commit=Commit-SpicetifyCliTransaction
    $State=Ensure-StateShape (Load-State)
    $State.pending_spicetify_upgrade=$false; $State.spicetify_installed_version=[string]$txn.after_version; $State.spicetify_compat_tag=[string]$plan.SpicetifyTag
    $State.spicetify_compat_min_windows=[string]$plan.MinSupported; $State.spicetify_max_windows=[string]$plan.MaxSupported; $State.spicetify_latest_tag=[string]$start.Latest.Tag
    $State.spicetify_last_digest=[string]$txn.asset_digest; $State.spicetify_last_transaction_id=[string]$txn.id; $State.spicetify_last_transaction_status='committed'; $State.spicetify_last_transaction_utc=[DateTimeOffset]::UtcNow.ToString('o')
    $State.spicetify_install_mode=(Get-SpicetifyManagedInstallInfo).Mode; Save-State $State
    return [pscustomobject]@{ Success=$true; Changed=$true; Status='committed'; State=$State; GuardPlan=$plan; GuardResult=$guard; Transaction=$commit.Transaction }
}

function Get-IniSectionValue {
    param([string]$Path,[string]$Section,[string]$Key)
    if (-not (Test-UsablePath -Path $Path -PathType 'Leaf')) { return $null }
    $inside=$false
    try {
        foreach($line in @(Get-Content -LiteralPath $Path -ErrorAction Stop)) {
            $t=[string]$line
            if($t -match '^\s*\[(?<section>[^\]]+)\]\s*$') { $inside=([string]$Matches['section'] -ieq $Section); continue }
            if($inside -and $t -match '^\s*(?<key>[^=]+?)\s*=\s*(?<value>.*?)\s*$') {
                if(([string]$Matches['key']).Trim() -ieq $Key) { return ([string]$Matches['value']).Trim().Trim('"') }
            }
        }
    } catch {}
    return $null
}

function Get-SpotifyPrefsPath {
    $fallback=Join-Path $env:APPDATA 'Spotify\prefs'
    if (Test-UsablePath -Path $fallback -PathType 'Leaf') { return $fallback }
    return $null
}

function Get-SpotifyPrefsLaunchedVersion {
    param([string]$Path=(Get-SpotifyPrefsPath))
    if (-not (Test-UsablePath -Path $Path -PathType 'Leaf')) { return $null }
    try {
        foreach($line in @(Get-Content -LiteralPath $Path -ErrorAction Stop)) {
            if([string]$line -match '^\s*app\.last-launched-version\s*=\s*"?(?<v>[^"\r\n]+)"?\s*$') { return ([string]$Matches['v']).Trim() }
        }
    } catch {}
    return $null
}

function ConvertTo-SpotifyPrefsBytesWithVersion {
    param([byte[]]$Bytes,[string]$Version)
    if($null -eq $Bytes -or $Bytes.Length -eq 0){throw 'Spotify prefs bytes are empty.'}
    if([string]::IsNullOrWhiteSpace($Version) -or $Version -notmatch '^\d+\.\d+\.\d+\.\d+(?:\.g[0-9A-Za-z]+)?$'){throw "Spotify prefs target version is invalid: $Version"}
    $needle=[System.Text.Encoding]::ASCII.GetBytes('app.last-launched-version=')
    $hits=New-Object System.Collections.Generic.List[int]
    for($i=0;$i -le $Bytes.Length-$needle.Length;$i++){
        $ok=$true
        for($j=0;$j -lt $needle.Length;$j++){if($Bytes[$i+$j] -ne $needle[$j]){$ok=$false;break}}
        if($ok){
            $lineBoundary=($i -eq 0 -or $Bytes[$i-1] -eq 10 -or $Bytes[$i-1] -eq 13)
            if($lineBoundary){$hits.Add($i)}
        }
    }
    if($hits.Count -ne 1){throw "Spotify prefs must contain exactly one app.last-launched-version line; found $($hits.Count)."}
    $start=[int]$hits[0];$end=$start+$needle.Length
    while($end -lt $Bytes.Length -and $Bytes[$end] -ne 10 -and $Bytes[$end] -ne 13){$end++}
    $replacement=[System.Text.Encoding]::ASCII.GetBytes(('app.last-launched-version="'+$Version+'"'))
    $result=New-Object byte[] ($Bytes.Length-($end-$start)+$replacement.Length)
    if($start -gt 0){[System.Buffer]::BlockCopy($Bytes,0,$result,0,$start)}
    [System.Buffer]::BlockCopy($replacement,0,$result,$start,$replacement.Length)
    $tail=$Bytes.Length-$end
    if($tail -gt 0){[System.Buffer]::BlockCopy($Bytes,$end,$result,$start+$replacement.Length,$tail)}
    return ,$result
}

function Invoke-SpicetifyBackupApplyPinnedPrefs {
    param([string]$FullVersion)
    $prefs=Get-SpotifyPrefsPath
    if(-not $prefs){throw 'Spotify prefs file is missing; refusing backup/apply.'}
    $before=[System.IO.File]::ReadAllBytes($prefs)
    $beforeHash=Get-ExactFileSha256 -Path $prefs
    $patched=ConvertTo-SpotifyPrefsBytesWithVersion -Bytes $before -Version $FullVersion
    try {
        [System.IO.File]::WriteAllBytes($prefs,$patched)
        $readback=Get-SpotifyPrefsLaunchedVersion -Path $prefs
        if($readback -cne $FullVersion){throw "Temporary Spotify prefs version stamp failed. expected=$FullVersion actual=$readback"}
        $r=Invoke-SpiceCapture -Arguments @('backup','apply')
        return $r
    } finally {
        [System.IO.File]::WriteAllBytes($prefs,$before)
        $afterHash=Get-ExactFileSha256 -Path $prefs
        if($afterHash -cne $beforeHash){throw 'Spotify prefs byte-exact restoration failed after Spicetify backup/apply.'}
    }
}

function Set-IniSectionValueBytePreserving {
    param([string]$Path,[string]$Section,[string]$Key,[string]$Value)
    if(-not(Test-UsablePath -Path $Path -PathType 'Leaf')){throw "INI file missing: $Path"}
    $bytes=[System.IO.File]::ReadAllBytes($Path)
    $utf8Bom=($bytes.Length -ge 3 -and $bytes[0]-eq 0xEF -and $bytes[1]-eq 0xBB -and $bytes[2]-eq 0xBF)
    $decode=[System.Text.UTF8Encoding]::new($false,$true)
    try {
        if($utf8Bom){$text=$decode.GetString($bytes,3,$bytes.Length-3)}else{$text=$decode.GetString($bytes)}
    } catch {throw 'INI file is not valid UTF-8; refusing metadata mutation.'}
    $linePattern='(?im)^(?<prefix>[ \t]*'+[regex]::Escape($Key)+'[ \t]*=[ \t]*)(?<value>[^\r\n]*)(?=\r?$)'
    $sectionPattern='(?im)^[ \t]*\['+[regex]::Escape($Section)+'\][ \t]*(?=\r?$)'
    $sectionMatch=[regex]::Match($text,$sectionPattern)
    if(-not $sectionMatch.Success){throw "INI section missing: [$Section]"}
    $searchStart=$sectionMatch.Index+$sectionMatch.Length
    $tail=$text.Substring($searchStart)
    $next=[regex]::Match($tail,'(?im)^[ \t]*\[[^\]]+\][ \t]*(?=\r?$)')
    $sectionText=if($next.Success){$tail.Substring(0,$next.Index)}else{$tail}
    $m=[regex]::Match($sectionText,$linePattern)
    if(-not $m.Success){throw "INI key missing in [$Section]: $Key"}
    $absolute=$searchStart+$m.Index
    $oldLine=$m.Value
    $newLine=$m.Groups['prefix'].Value+$Value
    $newText=$text.Substring(0,$absolute)+$newLine+$text.Substring($absolute+$oldLine.Length)
    $enc=[System.Text.UTF8Encoding]::new($utf8Bom)
    [System.IO.File]::WriteAllText($Path,$newText,$enc)
}

function Test-SpicetifyBackupMetadataRepairEligibility {
    param($Transaction,[string]$InstalledVersion,[string]$PrefsFullVersion,[string]$BackupVersion,[string]$BackupWith,[string]$InstalledSpicetifyVersion)
    $reasons=New-Object System.Collections.Generic.List[string]
    if($null -eq $Transaction){$reasons.Add('spotify-transaction-missing')}
    else {
        if([string]$Transaction.status -cne 'committed'){$reasons.Add('spotify-transaction-not-committed')}
        if([string]$Transaction.after_version -cne $InstalledVersion){$reasons.Add('transaction-after-version-mismatch')}
        if([string]$Transaction.final_version -cne $InstalledVersion){$reasons.Add('transaction-final-version-mismatch')}
        if([string]$Transaction.after_fullversion -cne $PrefsFullVersion){$reasons.Add('transaction-fullversion-mismatch')}
        if([string]::IsNullOrWhiteSpace([string]$Transaction.apply_finished_at)){$reasons.Add('transaction-apply-proof-missing')}
        if([string]::IsNullOrWhiteSpace([string]$Transaction.committed_at)){$reasons.Add('transaction-commit-proof-missing')}
        if([string]$Transaction.protected_before_tree_sha256 -cne [string]$Transaction.protected_after_tree_sha256){$reasons.Add('protected-data-proof-mismatch')}
        if([string]$Transaction.spicetify_config_semantic_before -cne [string]$Transaction.spicetify_config_semantic_after){$reasons.Add('spicetify-config-semantic-proof-mismatch')}
        if([string]$Transaction.spicetify_user_assets_before_tree_sha256 -cne [string]$Transaction.spicetify_user_assets_after_tree_sha256){$reasons.Add('spicetify-user-assets-proof-mismatch')}
    }
    if([string]::IsNullOrWhiteSpace($PrefsFullVersion)){$reasons.Add('prefs-version-missing')}
    if([string]::IsNullOrWhiteSpace($BackupVersion)){$reasons.Add('backup-version-missing')}
    if($BackupVersion -ceq $PrefsFullVersion){$reasons.Add('already-current')}
    if([string]::IsNullOrWhiteSpace($BackupWith) -or $BackupWith -cne $InstalledSpicetifyVersion){$reasons.Add('backup-spicetify-version-mismatch')}
    return [pscustomobject]@{Eligible=($reasons.Count -eq 0);Reasons=$reasons.ToArray()}
}

function Repair-SpicetifyBackupMetadataIfTrusted {
    $config=Get-ConfigPath
    $prefs=Get-SpotifyPrefsPath
    if(-not $config -or -not $prefs){return [pscustomobject]@{Changed=$false;Status='unavailable';Reason='config-or-prefs-missing'}}
    $backupVersion=Get-IniSectionValue -Path $config -Section 'Backup' -Key 'version'
    $backupWith=Get-IniSectionValue -Path $config -Section 'Backup' -Key 'with'
    $prefsVersion=Get-SpotifyPrefsLaunchedVersion -Path $prefs
    if(-not [string]::IsNullOrWhiteSpace($backupVersion) -and $backupVersion -ceq $prefsVersion){return [pscustomobject]@{Changed=$false;Status='already-current';Reason=$null}}
    $installedExe=Get-SpotifyExecutable;$installedVersion=Get-SpotifyVersion -Exe $installedExe;$installedSpice=Get-InstalledSpicetifyVersion
    $txn=Get-SpotifyTransaction
    $elig=Test-SpicetifyBackupMetadataRepairEligibility -Transaction $txn -InstalledVersion $installedVersion -PrefsFullVersion $prefsVersion -BackupVersion $backupVersion -BackupWith $backupWith -InstalledSpicetifyVersion $installedSpice
    if(-not $elig.Eligible){return [pscustomobject]@{Changed=$false;Status='blocked-unproven';Reason=(@($elig.Reasons)-join ',')}}
    $backupDir=Join-Path $env:APPDATA 'spicetify\Backup'
    $spa=@(Get-ChildItem -LiteralPath $backupDir -Filter '*.spa' -File -ErrorAction SilentlyContinue)
    if($spa.Count -lt 1){return [pscustomobject]@{Changed=$false;Status='blocked-unproven';Reason='backup-spa-missing'}}
    try {
        $applyStart=[DateTimeOffset]::Parse([string]$txn.apply_started_at).UtcDateTime.AddMinutes(-2)
        $commitEnd=[DateTimeOffset]::Parse([string]$txn.committed_at).UtcDateTime.AddMinutes(2)
        foreach($f in $spa){if($f.LastWriteTimeUtc -lt $applyStart -or $f.LastWriteTimeUtc -gt $commitEnd){return [pscustomobject]@{Changed=$false;Status='blocked-unproven';Reason=('backup-spa-timestamp-outside-trusted-transaction:'+ $f.Name)}}}
    } catch {return [pscustomobject]@{Changed=$false;Status='blocked-unproven';Reason='transaction-time-proof-unreadable'}}
    $before=[System.IO.File]::ReadAllBytes($config);$beforeHash=Get-ExactFileSha256 -Path $config
    try {
        Set-IniSectionValueBytePreserving -Path $config -Section 'Backup' -Key 'version' -Value $prefsVersion
        $afterVersion=Get-IniSectionValue -Path $config -Section 'Backup' -Key 'version'
        if($afterVersion -cne $prefsVersion){throw 'Spicetify Backup version metadata did not update to the current trusted Spotify full version.'}
        if((Get-SpicetifyConfigSemanticHash) -cne [string]$txn.spicetify_config_semantic_after){throw 'Spicetify config semantic hash changed during Backup metadata repair.'}
        Write-Log "Repaired trusted stale Spicetify Backup version metadata: $backupVersion -> $prefsVersion; backup payload was provenance-gated to committed Spotify transaction $($txn.id)." 'WARN'
        return [pscustomobject]@{Changed=$true;Status='repaired';Reason=$null;Before=$backupVersion;After=$prefsVersion;TransactionId=[string]$txn.id}
    } catch {
        [System.IO.File]::WriteAllBytes($config,$before)
        if((Get-ExactFileSha256 -Path $config) -cne $beforeHash){throw 'Spicetify config rollback failed after Backup metadata repair failure.'}
        throw
    }
}

function Get-SpotifyClassicInstallRoot {
    $expected = [System.IO.Path]::GetFullPath((Join-Path $env:APPDATA 'Spotify')).TrimEnd([char[]]@([char]92,[char]47))
    $exe = Get-SpotifyExecutable
    if (-not (Test-UsablePath -Path $exe -PathType 'Leaf')) { throw 'Spotify executable is missing.' }
    $actual = [System.IO.Path]::GetFullPath((Split-Path -Parent $exe)).TrimEnd([char[]]@([char]92,[char]47))
    if (-not $actual.Equals($expected,[System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Spotify transaction supports only the classic per-user APPDATA install. actual=$actual expected=$expected"
    }
    return $actual
}

function Get-SpotifyPublisherSignature {
    param([string]$Path)
    $result=[ordered]@{Valid=$false;Status=$null;Subject=$null;Thumbprint=$null;Error=$null}
    try {
        if (-not (Test-UsablePath -Path $Path -PathType 'Leaf')) { throw "Executable missing: $Path" }
        $sig=Get-AuthenticodeSignature -LiteralPath $Path
        $result.Status=[string]$sig.Status
        if ($sig.SignerCertificate) {
            $result.Subject=[string]$sig.SignerCertificate.Subject
            $result.Thumbprint=[string]$sig.SignerCertificate.Thumbprint
        }
        if ([string]$sig.Status -ne 'Valid') { throw "Authenticode status is $($sig.Status)." }
        if ([string]::IsNullOrWhiteSpace([string]$result.Subject) -or [string]$result.Subject -notmatch '(?i)(^|,\s*)(O|CN)=Spotify AB(,|$)') {
            throw "Signer is not Spotify AB: $($result.Subject)"
        }
        $result.Valid=$true
    } catch { $result.Error=$_.Exception.Message }
    return [pscustomobject]$result
}

function Get-SpotifyRootManifest {
    param([string]$Path)
    if (-not (Test-UsablePath -Path $Path -PathType 'Container')) { throw "Spotify root does not exist: $Path" }
    $root=Get-Item -LiteralPath $Path -Force
    if (($root.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Reparse-point Spotify root refused: $Path" }
    $rootFull=$root.FullName.TrimEnd([char[]]@([char]92,[char]47))
    $rows=New-Object System.Collections.Generic.List[object]
    foreach($item in @(Get-ChildItem -LiteralPath $Path -Force -Recurse | Sort-Object FullName)) {
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Reparse point refused in Spotify root: $($item.FullName)" }
        $rel=$item.FullName.Substring($rootFull.Length).TrimStart([char[]]@([char]92,[char]47)).Replace([char]92,[char]47)
        if ([string]::IsNullOrWhiteSpace($rel)) { continue }
        if ($item.PSIsContainer) { $rows.Add([pscustomobject]@{path=$rel;type='dir';size=[int64]0;sha256=$null}) }
        else { $rows.Add([pscustomobject]@{path=$rel;type='file';size=[int64]$item.Length;sha256=(Get-ExactFileSha256 -Path $item.FullName)}) }
    }
    $ordered=@($rows.ToArray() | Sort-Object path,type)
    $json=$ordered | ConvertTo-Json -Depth 5 -Compress
    return [pscustomobject]@{Root=$rootFull;Rows=$ordered;TreeSha256=(Get-StringSha256 -Text $json);FileCount=@($ordered|Where-Object{$_.type -eq 'file'}).Count;DirectoryCount=@($ordered|Where-Object{$_.type -eq 'dir'}).Count}
}

function Copy-SpotifyRootExact {
    param([string]$Source,[string]$Destination,[string]$ExpectedTreeSha256)
    if (Test-Path -LiteralPath $Destination) { throw "Spotify backup destination already exists: $Destination" }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination -Recurse -Force
    $m=Get-SpotifyRootManifest -Path $Destination
    if ($ExpectedTreeSha256 -and $m.TreeSha256 -cne $ExpectedTreeSha256) { throw "Spotify root copy verification mismatch. expected=$ExpectedTreeSha256 actual=$($m.TreeSha256)" }
    return $m
}

function Test-SpotifyTransactionSandbox {
    $base = Join-Path ([System.IO.Path]::GetTempPath()) ("spotify-control-spotify-txn-selftest-" + [guid]::NewGuid().ToString('N'))
    try {
        $source = Join-Path $base 'source'
        $backup = Join-Path $base 'backup'
        New-Item -ItemType Directory -Force -Path (Join-Path $source 'Apps') | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $source 'Spotify.exe'),'fixture-exe',[System.Text.Encoding]::ASCII)
        [System.IO.File]::WriteAllText((Join-Path $source 'prefs'),'fixture-prefs',[System.Text.Encoding]::ASCII)
        [System.IO.File]::WriteAllText((Join-Path $source 'Apps\xpui.spa'),'fixture-app',[System.Text.Encoding]::ASCII)
        $before = Get-SpotifyRootManifest -Path $source
        [void](Copy-SpotifyRootExact -Source $source -Destination $backup -ExpectedTreeSha256 $before.TreeSha256)
        [System.IO.File]::WriteAllText((Join-Path $source 'Spotify.exe'),'changed',[System.Text.Encoding]::ASCII)
        $changed = Get-SpotifyRootManifest -Path $source
        if ($changed.TreeSha256 -ceq $before.TreeSha256) { throw 'Mutation fixture did not change root fingerprint.' }
        Remove-Item -LiteralPath $source -Recurse -Force
        [void](Copy-SpotifyRootExact -Source $backup -Destination $source -ExpectedTreeSha256 $before.TreeSha256)
        $restored = Get-SpotifyRootManifest -Path $source
        if ($restored.TreeSha256 -cne $before.TreeSha256) { throw 'Exact rollback fixture did not restore original fingerprint.' }
        [System.IO.File]::AppendAllText((Join-Path $backup 'Spotify.exe'),'corrupt',[System.Text.Encoding]::ASCII)
        $corrupt = Get-SpotifyRootManifest -Path $backup
        if ($corrupt.TreeSha256 -ceq $before.TreeSha256) { throw 'Corrupted rollback backup was not detected.' }
        return [pscustomobject]@{Pass=$true;Detail=("exact backup + mutation + rollback verified; corrupt backup rejected; tree=" + $before.TreeSha256)}
    } catch {
        return [pscustomobject]@{Pass=$false;Detail=$_.Exception.Message}
    } finally {
        Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-SpotifyProtectedDataManifest {
    $specs=@(
        [pscustomobject]@{label='roaming/prefs';path=(Join-Path $env:APPDATA 'Spotify\prefs')},
        [pscustomobject]@{label='roaming/Users';path=(Join-Path $env:APPDATA 'Spotify\Users')},
        [pscustomobject]@{label='local/Browser';path=(Join-Path $env:LOCALAPPDATA 'Spotify\Browser')},
        [pscustomobject]@{label='local/Default';path=(Join-Path $env:LOCALAPPDATA 'Spotify\Default')},
        [pscustomobject]@{label='local/IndexedDB';path=(Join-Path $env:LOCALAPPDATA 'Spotify\IndexedDB')},
        [pscustomobject]@{label='local/Local Storage';path=(Join-Path $env:LOCALAPPDATA 'Spotify\Local Storage')},
        [pscustomobject]@{label='local/Session Storage';path=(Join-Path $env:LOCALAPPDATA 'Spotify\Session Storage')},
        [pscustomobject]@{label='local/WebStorage';path=(Join-Path $env:LOCALAPPDATA 'Spotify\WebStorage')}
    )
    $rows=New-Object System.Collections.Generic.List[object]
    foreach($spec in $specs) {
        $p=[string]$spec.path;$label=[string]$spec.label
        if (Test-Path -LiteralPath $p -PathType Leaf) {
            $f=Get-Item -LiteralPath $p -Force
            $rows.Add([pscustomobject]@{path=$label;type='file';size=[int64]$f.Length;sha256=(Get-ExactFileSha256 -Path $p)})
        } elseif (Test-Path -LiteralPath $p -PathType Container) {
            $root=Get-Item -LiteralPath $p -Force
            if (($root.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Protected Spotify path is a reparse point: $p" }
            $rows.Add([pscustomobject]@{path=$label;type='dir';size=[int64]0;sha256=$null})
            $rootFull=$root.FullName.TrimEnd([char[]]@([char]92,[char]47))
            foreach($item in @(Get-ChildItem -LiteralPath $p -Force -Recurse | Sort-Object FullName)) {
                if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Protected Spotify data contains reparse point: $($item.FullName)" }
                $rel=$item.FullName.Substring($rootFull.Length).TrimStart([char[]]@([char]92,[char]47)).Replace([char]92,[char]47)
                $rp=$label + '/' + $rel
                if ($item.PSIsContainer) { $rows.Add([pscustomobject]@{path=$rp;type='dir';size=[int64]0;sha256=$null}) }
                else { $rows.Add([pscustomobject]@{path=$rp;type='file';size=[int64]$item.Length;sha256=(Get-ExactFileSha256 -Path $item.FullName)}) }
            }
        } else {
            $rows.Add([pscustomobject]@{path=$label;type='absent';size=[int64]0;sha256=$null})
        }
    }
    $ordered=@($rows.ToArray() | Sort-Object path,type)
    $json=$ordered | ConvertTo-Json -Depth 5 -Compress
    return [pscustomobject]@{Rows=$ordered;TreeSha256=(Get-StringSha256 -Text $json);FileCount=@($ordered|Where-Object{$_.type -eq 'file'}).Count}
}

function Get-SpicetifyRoamingRootManifest {
    $root=Join-Path $env:APPDATA 'spicetify'
    if (-not (Test-UsablePath -Path $root -PathType 'Container')) { throw "Roaming Spicetify root missing: $root" }
    return Get-SpotifyRootManifest -Path $root
}

function Get-SpicetifyConfigSemanticHash {
    $path=Get-ConfigPath
    if (-not (Test-UsablePath -Path $path -PathType 'Leaf')) { throw 'Spicetify config missing.' }
    $lines=Get-Content -LiteralPath $path
    $section=''
    $kept=New-Object System.Collections.Generic.List[string]
    foreach($line in $lines) {
        if ($line -match '^\s*\[(?<s>[^\]]+)\]\s*$') { $section=$Matches['s'];$kept.Add($line);continue }
        if ($section -ieq 'Backup' -and $line -match '^\s*(version|with)\s*=') { continue }
        $kept.Add($line)
    }
    return Get-StringSha256 -Text ($kept.ToArray() -join "`n")
}

function Get-SpicetifyUserAssetManifest {
    $rows=New-Object System.Collections.Generic.List[object]
    foreach($pair in @(@('local',(Join-Path $env:LOCALAPPDATA 'spicetify')),@('roaming',(Join-Path $env:APPDATA 'spicetify')))) {
        $label=[string]$pair[0];$root=[string]$pair[1]
        foreach($dirName in @('Extensions','CustomApps','Themes')) {
            $dir=Join-Path $root $dirName;$baseLabel=$label+'/'+$dirName
            if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
                $rows.Add([pscustomobject]@{path=$baseLabel;type='absent';size=[int64]0;sha256=$null})
                continue
            }
            $rootItem=Get-Item -LiteralPath $dir -Force
            if (($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Spicetify user asset root is a reparse point: $dir" }
            $rootFull=$rootItem.FullName.TrimEnd([char[]]@([char]92,[char]47))
            $rows.Add([pscustomobject]@{path=$baseLabel;type='dir';size=[int64]0;sha256=$null})
            foreach($item in @(Get-ChildItem -LiteralPath $dir -Force -Recurse | Sort-Object FullName)) {
                if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Spicetify user asset contains reparse point: $($item.FullName)" }
                $rel=$item.FullName.Substring($rootFull.Length).TrimStart([char[]]@([char]92,[char]47)).Replace([char]92,[char]47)
                $rp=$baseLabel+'/'+$rel
                if($item.PSIsContainer){$rows.Add([pscustomobject]@{path=$rp;type='dir';size=[int64]0;sha256=$null})}
                else{$rows.Add([pscustomobject]@{path=$rp;type='file';size=[int64]$item.Length;sha256=(Get-ExactFileSha256 -Path $item.FullName)})}
            }
        }
    }
    $ordered=@($rows.ToArray()|Sort-Object path,type);$json=$ordered|ConvertTo-Json -Depth 5 -Compress
    return [pscustomobject]@{Rows=$ordered;TreeSha256=(Get-StringSha256 -Text $json);FileCount=@($ordered|Where-Object{$_.type -eq 'file'}).Count}
}

function Get-SpotifyRegistryKeys {
    return @(
        'HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\Spotify',
        'HKCU\Software\Microsoft\Windows\CurrentVersion\App Paths\Spotify.exe',
        'HKCU\Software\Classes\spotify',
        'HKCU\Software\Classes\Applications\Spotify.exe',
        'HKCU\Software\Spotify'
    )
}

function Get-SpotifyRegistrySemanticHash {
    $reg=Join-Path $env:SystemRoot 'System32\reg.exe'
    $rows=New-Object System.Collections.Generic.List[string]
    foreach($key in @(Get-SpotifyRegistryKeys)) {
        $r=Invoke-NativeCapture -FilePath $reg -Arguments @('query',$key,'/s')
        if($r.ExitCode -eq 0) {
            $lines=@(([string]$r.Output -split "`r?`n") | ForEach-Object { $_.TrimEnd() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            $rows.Add(('KEY '+$key))
            foreach($line in $lines){$rows.Add($line)}
        } else {
            $rows.Add(('ABSENT '+$key))
        }
    }
    return Get-StringSha256 -Text ($rows.ToArray() -join "`n")
}

function Get-SpotifyShortcutManifest {
    $rows=New-Object System.Collections.Generic.List[object]
    foreach($path in @(Get-SpotifyShortcutPaths)) {
        if(Test-Path -LiteralPath $path -PathType Leaf) {
            $f=Get-Item -LiteralPath $path -Force
            $rows.Add([pscustomobject]@{path=$path;type='file';size=[int64]$f.Length;sha256=(Get-ExactFileSha256 -Path $path)})
        } else {
            $rows.Add([pscustomobject]@{path=$path;type='absent';size=[int64]0;sha256=$null})
        }
    }
    $ordered=@($rows.ToArray()|Sort-Object path);$json=$ordered|ConvertTo-Json -Depth 4 -Compress
    return [pscustomobject]@{Rows=$ordered;TreeSha256=(Get-StringSha256 -Text $json)}
}

function Backup-SpotifyRegistry {
    param([string]$Destination)
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    $reg=Join-Path $env:SystemRoot 'System32\reg.exe';$i=0
    foreach($key in @(Get-SpotifyRegistryKeys)) {
        $name=('key-{0:D2}' -f $i);$i++
        $query=Invoke-NativeCapture -FilePath $reg -Arguments @('query',$key)
        if ($query.ExitCode -eq 0) {
            $file=Join-Path $Destination ($name+'.reg')
            $r=Invoke-NativeCapture -FilePath $reg -Arguments @('export',$key,$file,'/y')
            if ($r.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Could not export registry key: $key" }
        } else {
            New-Item -ItemType File -Force -Path (Join-Path $Destination ($name+'.absent')) | Out-Null
        }
        Set-Content -LiteralPath (Join-Path $Destination ($name+'.name')) -Value $key -Encoding ASCII
    }
}

function Restore-SpotifyRegistry {
    param([string]$Source)
    $reg=Join-Path $env:SystemRoot 'System32\reg.exe'
    foreach($nameFile in @(Get-ChildItem -LiteralPath $Source -Filter '*.name' -File | Sort-Object Name)) {
        $base=[System.IO.Path]::GetFileNameWithoutExtension($nameFile.Name);$key=(Get-Content -LiteralPath $nameFile.FullName -Raw).Trim()
        [void](Invoke-NativeCapture -FilePath $reg -Arguments @('delete',$key,'/f'))
        $regFile=Join-Path $Source ($base+'.reg')
        if (Test-Path -LiteralPath $regFile -PathType Leaf) {
            $r=Invoke-NativeCapture -FilePath $reg -Arguments @('import',$regFile)
            if ($r.ExitCode -ne 0) { throw "Could not restore registry key: $key" }
        }
    }
}

function Get-SpotifyShortcutPaths {
    return @(
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Spotify.lnk'),
        (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Spotify.lnk')
    )
}

function Backup-SpotifyShortcuts {
    param([string]$Destination)
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    $i=0
    foreach($path in @(Get-SpotifyShortcutPaths)) {
        $base=('shortcut-{0:D2}' -f $i);$i++
        Set-Content -LiteralPath (Join-Path $Destination ($base+'.path')) -Value $path -Encoding UTF8
        if (Test-Path -LiteralPath $path -PathType Leaf) { Copy-Item -LiteralPath $path -Destination (Join-Path $Destination ($base+'.lnk')) -Force }
        else { New-Item -ItemType File -Force -Path (Join-Path $Destination ($base+'.absent')) | Out-Null }
    }
}

function Restore-SpotifyShortcuts {
    param([string]$Source)
    foreach($pf in @(Get-ChildItem -LiteralPath $Source -Filter '*.path' -File | Sort-Object Name)) {
        $base=[System.IO.Path]::GetFileNameWithoutExtension($pf.Name);$path=(Get-Content -LiteralPath $pf.FullName -Raw).Trim()
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        $src=Join-Path $Source ($base+'.lnk')
        if (Test-Path -LiteralPath $src -PathType Leaf) { New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null;Copy-Item -LiteralPath $src -Destination $path -Force }
    }
}

function Stop-AllSpotifyProcesses {
    $deadline=(Get-Date).AddSeconds(15)
    do {
        $items=@(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like 'Spotify*' })
        if ($items.Count -eq 0) { return }
        foreach($p in $items) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
        Start-Sleep -Milliseconds 400
    } while((Get-Date) -lt $deadline)
    if (@(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like 'Spotify*' }).Count -gt 0) { throw 'Could not stop all Spotify processes.' }
}

function Test-IsCurrentProcessElevated {
    $id=[System.Security.Principal.WindowsIdentity]::GetCurrent();$p=New-Object System.Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-SpotifyInstallerIdentity {
    param([string]$Path,$Candidate)
    $result=[ordered]@{Verified=$false;Sha256=$null;Size=[int64]0;ProductVersion=$null;Signature=$null;Error=$null}
    try {
        if (-not (Test-UsablePath -Path $Path -PathType 'Leaf')) { throw 'Installer file missing.' }
        $item=Get-Item -LiteralPath $Path -Force;$result.Size=[int64]$item.Length
        $result.Sha256=(Get-ExactFileSha256 -Path $Path)
        if ($result.Size -ne [int64]$Candidate.Size) { throw "Installer size mismatch. expected=$($Candidate.Size) actual=$($result.Size)" }
        if ($result.Sha256 -cne ([string]$Candidate.Sha256).ToLowerInvariant()) { throw "Installer SHA-256 mismatch. expected=$($Candidate.Sha256) actual=$($result.Sha256)" }
        $sig=Get-SpotifyPublisherSignature -Path $Path;$result.Signature=$sig
        if (-not $sig.Valid) { throw "Installer signature verification failed: $($sig.Error)" }
        $pv=[string][System.Diagnostics.FileVersionInfo]::GetVersionInfo($Path).ProductVersion;$result.ProductVersion=$pv
        if ([string]::IsNullOrWhiteSpace($pv) -or $pv.Trim() -cne ([string]$Candidate.FullVersion).Trim()) { throw "Installer ProductVersion mismatch. expected=$($Candidate.FullVersion) actual=$pv" }
        $result.Verified=$true
    } catch { $result.Error=$_.Exception.Message }
    return [pscustomobject]$result
}

function Get-VerifiedSpotifyInstaller {
    param($Candidate)
    New-Item -ItemType Directory -Force -Path $SpotifyInstallerCacheDir | Out-Null
    $safeVersion=([string]$Candidate.FullVersion -replace '[^A-Za-z0-9._-]','_')
    $cache=Join-Path $SpotifyInstallerCacheDir ("SpotifyFullSetupX64-$safeVersion-$(([string]$Candidate.Sha256).Substring(0,12)).exe")
    if (Test-Path -LiteralPath $cache -PathType Leaf) {
        $cached=Test-SpotifyInstallerIdentity -Path $cache -Candidate $Candidate
        if ($cached.Verified) { return [pscustomobject]@{Path=$cache;Identity=$cached;Downloaded=$false} }
        Remove-Item -LiteralPath $cache -Force
    }
    $tmp=$cache+'.partial-'+[guid]::NewGuid().ToString('N')
    try {
        $headers=@{'User-Agent'="SpotifyControl/$ScriptVersion";'If-Match'=[string]$Candidate.Etag}
        Invoke-WebRequest -Uri ([string]$Candidate.Url) -Headers $headers -UseBasicParsing -OutFile $tmp -MaximumRedirection 5
        $identity=Test-SpotifyInstallerIdentity -Path $tmp -Candidate $Candidate
        if (-not $identity.Verified) { throw $identity.Error }
        Move-Item -LiteralPath $tmp -Destination $cache
        return [pscustomobject]@{Path=$cache;Identity=$identity;Downloaded=$true}
    } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
}

function Ensure-SpotifyTransactionShape {
    param($Transaction)
    if ($null -eq $Transaction) { return $null }
    foreach($name in @('schema','status','prepared_at','install_started_at','install_finished_at','apply_started_at','apply_finished_at','guard_verified_at','committed_at','rolled_back_at','error')) {
        if (-not $Transaction.PSObject.Properties[$name]) { $Transaction | Add-Member -NotePropertyName $name -NotePropertyValue $null }
    }
    $Transaction.schema = 2
    return $Transaction
}

function Get-SpotifyTransaction {
    if (-not (Test-UsablePath -Path $SpotifyTransactionPath -PathType 'Leaf')) { return $null }
    try { return Ensure-SpotifyTransactionShape (Get-Content -LiteralPath $SpotifyTransactionPath -Raw | ConvertFrom-Json) }
    catch { throw "Spotify transaction ledger is unreadable; refusing mutation: $($_.Exception.Message)" }
}

function Save-SpotifyTransaction {
    param($Transaction)
    $Transaction=Ensure-SpotifyTransactionShape $Transaction
    $Transaction | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $SpotifyTransactionPath -Encoding UTF8
    $Transaction | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $SpotifyTransactionReport -Encoding UTF8
}

function Backup-SpotifyProtectedLocalPaths {
    param([string]$Destination)
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    $specs=@('Browser','Default','IndexedDB','Local Storage','Session Storage','WebStorage')
    $root=Join-Path $env:LOCALAPPDATA 'Spotify'
    foreach($name in $specs) {
        $src=Join-Path $root $name;$safe=($name -replace '[^A-Za-z0-9._-]','_');$marker=Join-Path $Destination ($safe+'.absent')
        if (Test-Path -LiteralPath $src -PathType Container) { Copy-Item -LiteralPath $src -Destination $Destination -Recurse -Force }
        elseif (Test-Path -LiteralPath $src -PathType Leaf) { Copy-Item -LiteralPath $src -Destination (Join-Path $Destination $name) -Force }
        else { New-Item -ItemType File -Force -Path $marker | Out-Null }
    }
}

function Restore-SpotifyProtectedLocalPaths {
    param([string]$Source)
    $specs=@('Browser','Default','IndexedDB','Local Storage','Session Storage','WebStorage')
    $root=Join-Path $env:LOCALAPPDATA 'Spotify';New-Item -ItemType Directory -Force -Path $root | Out-Null
    foreach($name in $specs) {
        $target=Join-Path $root $name;Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue
        $src=Join-Path $Source $name
        if (Test-Path -LiteralPath $src -PathType Container) { Copy-Item -LiteralPath $src -Destination $root -Recurse -Force }
        elseif (Test-Path -LiteralPath $src -PathType Leaf) { Copy-Item -LiteralPath $src -Destination $target -Force }
    }
}

function Restore-SpotifyTransactionSnapshot {
    param($Transaction)
    $txn=Ensure-SpotifyTransactionShape $Transaction
    Stop-AllSpotifyProcesses
    $appRoot=[string]$txn.spotify_root;$backupRoot=[string]$txn.spotify_backup_root
    if (-not (Test-Path -LiteralPath $backupRoot -PathType Container)) { throw "Spotify rollback backup missing: $backupRoot" }
    $bm=Get-SpotifyRootManifest -Path $backupRoot
    if ($bm.TreeSha256 -cne [string]$txn.spotify_before_tree_sha256) { throw 'Spotify rollback backup tree hash mismatch.' }
    $quarantine=$appRoot+'.spotifycontrol-failed-'+[string]$txn.id
    Remove-Item -LiteralPath $quarantine -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $appRoot) { Move-Item -LiteralPath $appRoot -Destination $quarantine }
    try { [void](Copy-SpotifyRootExact -Source $backupRoot -Destination $appRoot -ExpectedTreeSha256 ([string]$txn.spotify_before_tree_sha256)) }
    catch { if(-not(Test-Path -LiteralPath $appRoot)-and(Test-Path -LiteralPath $quarantine)){Move-Item -LiteralPath $quarantine -Destination $appRoot};throw }
    Remove-Item -LiteralPath $quarantine -Recurse -Force -ErrorAction SilentlyContinue

    $localBackup=[string]$txn.spotify_local_protected_backup
    if ($localBackup) { Restore-SpotifyProtectedLocalPaths -Source $localBackup }

    foreach($pair in @(@([string]$txn.spicetify_local_root,[string]$txn.spicetify_local_backup,[string]$txn.spicetify_local_before_tree_sha256),@([string]$txn.spicetify_roaming_root,[string]$txn.spicetify_roaming_backup,[string]$txn.spicetify_roaming_before_tree_sha256))) {
        $target=$pair[0];$bak=$pair[1];$expected=$pair[2]
        if ([string]::IsNullOrWhiteSpace($target) -or [string]::IsNullOrWhiteSpace($bak)) { continue }
        $b=Get-SpotifyRootManifest -Path $bak;if($b.TreeSha256 -cne $expected){throw "Spicetify rollback backup corrupt: $bak"}
        $q=$target+'.spotifycontrol-failed-'+[string]$txn.id;Remove-Item -LiteralPath $q -Recurse -Force -ErrorAction SilentlyContinue
        if(Test-Path -LiteralPath $target){Move-Item -LiteralPath $target -Destination $q}
        try{[void](Copy-SpotifyRootExact -Source $bak -Destination $target -ExpectedTreeSha256 $expected)}catch{if(-not(Test-Path -LiteralPath $target)-and(Test-Path -LiteralPath $q)){Move-Item -LiteralPath $q -Destination $target};throw}
        Remove-Item -LiteralPath $q -Recurse -Force -ErrorAction SilentlyContinue
    }
    Restore-SpotifyRegistry -Source ([string]$txn.registry_backup)
    Restore-SpotifyShortcuts -Source ([string]$txn.shortcuts_backup)
    $restored=Get-SpotifyRootManifest -Path $appRoot
    if($restored.TreeSha256 -cne [string]$txn.spotify_before_tree_sha256){throw 'Spotify rollback post-verify failed.'}
    $protected=Get-SpotifyProtectedDataManifest
    if($protected.TreeSha256 -cne [string]$txn.protected_before_tree_sha256){throw 'Spotify protected user-data rollback post-verify failed.'}
    if($txn.PSObject.Properties['registry_before_semantic_sha256'] -and -not [string]::IsNullOrWhiteSpace([string]$txn.registry_before_semantic_sha256)) {
        if((Get-SpotifyRegistrySemanticHash) -cne [string]$txn.registry_before_semantic_sha256){throw 'Spotify registry rollback post-verify failed.'}
    }
    if($txn.PSObject.Properties['shortcuts_before_tree_sha256'] -and -not [string]::IsNullOrWhiteSpace([string]$txn.shortcuts_before_tree_sha256)) {
        if((Get-SpotifyShortcutManifest).TreeSha256 -cne [string]$txn.shortcuts_before_tree_sha256){throw 'Spotify shortcut rollback post-verify failed.'}
    }
    $version=Get-SpotifyVersion -Exe (Join-Path $appRoot 'Spotify.exe')
    if($version -cne [string]$txn.before_version){throw "Spotify rollback version mismatch. expected=$($txn.before_version) actual=$version"}
    $guardPlan=Get-SmartUpdateGuardPlan -SpotifyVersionOverride $version
    $state=Ensure-StateShape (Load-State);$guard=Invoke-SmartUpdateGuard -State $state -Plan $guardPlan
    if(-not $guard.Success -or [string]$guard.Enforced -ne 'blocked'){throw 'Spotify rollback restored files but Smart Update Guard could not be re-blocked.'}
    $txn.status='rolled-back';$txn.rolled_back_at=(Get-Date).ToString('o');Save-SpotifyTransaction -Transaction $txn
    Write-Log "Rolled back and verified Spotify transaction $($txn.id): $($txn.after_version) -> $($txn.before_version)." 'WARN'
    return [pscustomobject]@{Success=$true;Status='rolled-back';Transaction=$txn;State=(Ensure-StateShape (Load-State));GuardResult=$guard}
}

function Rollback-SpotifyTransaction {
    param([switch]$AllowCommitted)
    $txn=Get-SpotifyTransaction
    if(-not $txn){return [pscustomobject]@{Success=$true;Status='none';Transaction=$null}}
    if([string]$txn.status -eq 'rolled-back'){return [pscustomobject]@{Success=$true;Status='rolled-back';Transaction=$txn}}
    if([string]$txn.status -eq 'committed'){
        if(-not $AllowCommitted){throw "Spotify transaction $($txn.id) is committed; automatic rollback is refused."}
        $currentVersion=Get-SpotifyVersion -Exe (Join-Path ([string]$txn.spotify_root) 'Spotify.exe')
        if($currentVersion -cne [string]$txn.after_version){throw "Committed rollback refused because current Spotify version changed. expected=$($txn.after_version) actual=$currentVersion"}
        $protectedNow=Get-SpotifyProtectedDataManifest
        if($protectedNow.TreeSha256 -cne [string]$txn.protected_before_tree_sha256){throw 'Committed rollback refused because protected Spotify user data changed after commit.'}
        $assetsNow=Get-SpicetifyUserAssetManifest
        if($assetsNow.TreeSha256 -cne [string]$txn.spicetify_user_assets_after_tree_sha256){throw 'Committed rollback refused because Spicetify source assets changed after commit.'}
        if($txn.PSObject.Properties['registry_after_semantic_sha256'] -and -not [string]::IsNullOrWhiteSpace([string]$txn.registry_after_semantic_sha256)) {
            if((Get-SpotifyRegistrySemanticHash) -cne [string]$txn.registry_after_semantic_sha256){throw 'Committed rollback refused because Spotify registry state changed after commit.'}
        }
        if($txn.PSObject.Properties['shortcuts_after_tree_sha256'] -and -not [string]::IsNullOrWhiteSpace([string]$txn.shortcuts_after_tree_sha256)) {
            if((Get-SpotifyShortcutManifest).TreeSha256 -cne [string]$txn.shortcuts_after_tree_sha256){throw 'Committed rollback refused because Spotify shortcut state changed after commit.'}
        }
    }
    return Restore-SpotifyTransactionSnapshot -Transaction $txn
}

function Repair-PendingSpotifyTransaction {
    $txn=Get-SpotifyTransaction
    if(-not $txn){return $null}
    if([string]$txn.status -in @('committed','rolled-back')){return $txn}
    Write-Log "Found uncommitted Spotify transaction $($txn.id) status=$($txn.status); restoring the exact pre-update snapshot before new mutation." 'WARN'
    [void](Restore-SpotifyTransactionSnapshot -Transaction $txn)
    return Get-SpotifyTransaction
}

function Invoke-SpotifyPreflight {
    $report=[ordered]@{generated_at=(Get-Date).ToString('o');version=$ScriptVersion;verified=$false;error=$null}
    try {
        if(Test-IsCurrentProcessElevated){throw 'Spotify transaction must run as the normal user, not elevated.'}
        if(Test-SpotifyRunning){throw 'Spotify must be fully closed for Spotify transaction preflight.'}
        [void](Repair-PendingSpotifyTransaction)
        $root=Get-SpotifyClassicInstallRoot;$exe=Join-Path $root 'Spotify.exe';$before=Get-SpotifyVersion -Exe $exe
        $sig=Get-SpotifyPublisherSignature -Path $exe;if(-not $sig.Valid){throw "Installed Spotify signature is not trusted: $($sig.Error)"}
        $compat=Get-SpicetifyWindowsCompatibility;if(-not $compat.Verified){throw "Spicetify compatibility metadata unavailable: $($compat.Error)"}
        if(-not(Test-SpotifyVersionInRange -SpotifyVersion $before -MinSupported $compat.Min -MaxSupported $compat.Max)){throw "Installed Spotify $before is outside Spicetify support $($compat.Min) -> $($compat.Max)."}
        $candidate=Get-LatestSpotifyWindowsCandidate;if(-not $candidate.Verified){throw "Spotify candidate trust failed: $($candidate.Error)"}
        if(-not(Test-SpotifyVersionInRange -SpotifyVersion $candidate.Version -MinSupported $compat.Min -MaxSupported $compat.Max)){throw "Spotify candidate $($candidate.Version) is outside Spicetify support $($compat.Min) -> $($compat.Max)."}
        $cmp=Compare-VersionParts -A $candidate.Version -B $before -Count 4;if($null -eq $cmp){throw 'Could not compare installed/candidate Spotify versions.'}
        $installer=Get-VerifiedSpotifyInstaller -Candidate $candidate
        $protected=Get-SpotifyProtectedDataManifest
        $report.installed_version=$before;$report.installed_signature_subject=$sig.Subject;$report.candidate_version=$candidate.Version;$report.candidate_fullversion=$candidate.FullVersion;$report.candidate_etag=$candidate.Etag;$report.candidate_sha256=$candidate.Sha256;$report.candidate_size=$candidate.Size;$report.installer_path=$installer.Path;$report.installer_downloaded=[bool]$installer.Downloaded;$report.spicetify_tag=$compat.Tag;$report.spicetify_min=$compat.Min;$report.spicetify_max=$compat.Max;$report.protected_user_data_tree_sha256=$protected.TreeSha256;$report.update_needed=($cmp -gt 0);$report.verified=$true
        $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $SpotifyPreflightReport -Encoding UTF8
        Write-Log "Spotify preflight verified installed $before and pinned candidate $($candidate.Version) by official ETag + SHA-256 + Spotify AB signature + ProductVersion."
        return [pscustomobject]$report
    } catch { $report.error=$_.Exception.Message;$report|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $SpotifyPreflightReport -Encoding UTF8;throw }
}

function Invoke-SpotifyTransactionalMaintenance {
    param($State,[switch]$ForceReinstall,[switch]$RollbackAfterApply)
    $State=Ensure-StateShape $State
    if(Test-IsCurrentProcessElevated){throw 'Spotify transaction must run as the normal user, not elevated.'}
    if(Test-SpotifyRunning){throw 'Spotify transaction requires Spotify to be fully closed.'}
    [void](Repair-PendingSpotifyTransaction)
    $pre=Invoke-SpotifyPreflight
    $before=[string]$pre.installed_version;$candidate=Get-LatestSpotifyWindowsCandidate
    $cmp=Compare-VersionParts -A $candidate.Version -B $before -Count 4
    if($cmp -lt 0){throw "Automatic Spotify downgrade is refused: installed=$before candidate=$($candidate.Version)"}
    if($cmp -eq 0 -and -not $ForceReinstall){
        $State.pending_spotify_update=$false;Save-State $State
        return [pscustomobject]@{Success=$true;Changed=$false;Status='already-current';State=$State;Transaction=$null}
    }
    $installer=Get-VerifiedSpotifyInstaller -Candidate $candidate
    $spotifyRoot=Get-SpotifyClassicInstallRoot;$spotifyBefore=Get-SpotifyRootManifest -Path $spotifyRoot
    $protectedBefore=Get-SpotifyProtectedDataManifest
    $spiceLocal=Join-Path $env:LOCALAPPDATA 'spicetify';$spiceRoaming=Join-Path $env:APPDATA 'spicetify'
    $spiceLocalBefore=Get-SpicetifyRootManifest -Path $spiceLocal;$spiceRoamingBefore=Get-SpotifyRootManifest -Path $spiceRoaming
    $configSemanticBefore=Get-SpicetifyConfigSemanticHash
    $userAssetsBefore=Get-SpicetifyUserAssetManifest
    $registryBefore=Get-SpotifyRegistrySemanticHash
    $shortcutsBefore=Get-SpotifyShortcutManifest
    $id=(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
    $backupBase=Join-Path $SpotifyBackupRoot $id;$spotifyBackup=Join-Path $backupBase 'spotify-roaming-root';$localProtected=Join-Path $backupBase 'spotify-local-protected';$spiceLocalBackup=Join-Path $backupBase 'spicetify-local-root';$spiceRoamingBackup=Join-Path $backupBase 'spicetify-roaming-root';$regBackup=Join-Path $backupBase 'registry';$shortcutBackup=Join-Path $backupBase 'shortcuts'
    New-Item -ItemType Directory -Force -Path $backupBase | Out-Null
    [void](Copy-SpotifyRootExact -Source $spotifyRoot -Destination $spotifyBackup -ExpectedTreeSha256 $spotifyBefore.TreeSha256)
    Backup-SpotifyProtectedLocalPaths -Destination $localProtected
    [void](Copy-SpotifyRootExact -Source $spiceLocal -Destination $spiceLocalBackup -ExpectedTreeSha256 $spiceLocalBefore.TreeSha256)
    [void](Copy-SpotifyRootExact -Source $spiceRoaming -Destination $spiceRoamingBackup -ExpectedTreeSha256 $spiceRoamingBefore.TreeSha256)
    Backup-SpotifyRegistry -Destination $regBackup;Backup-SpotifyShortcuts -Destination $shortcutBackup
    if((Get-SpotifyProtectedDataManifest).TreeSha256 -cne $protectedBefore.TreeSha256){throw 'Protected Spotify user data changed while creating transaction backup.'}
    if((Get-SpotifyRootManifest -Path $spotifyBackup).TreeSha256 -cne $spotifyBefore.TreeSha256){throw 'Persistent Spotify rollback backup failed pre-mutation verification.'}
    $txn=[pscustomobject]@{schema=2;id=$id;status='prepared';prepared_at=(Get-Date).ToString('o');before_version=$before;after_version=[string]$candidate.Version;after_fullversion=[string]$candidate.FullVersion;candidate_etag=[string]$candidate.Etag;candidate_sha256=[string]$candidate.Sha256;candidate_size=[int64]$candidate.Size;installer_path=[string]$installer.Path;spotify_root=$spotifyRoot;spotify_backup_root=$spotifyBackup;spotify_before_tree_sha256=$spotifyBefore.TreeSha256;protected_before_tree_sha256=$protectedBefore.TreeSha256;protected_after_tree_sha256=$null;spotify_local_protected_backup=$localProtected;spicetify_local_root=$spiceLocal;spicetify_local_backup=$spiceLocalBackup;spicetify_local_before_tree_sha256=$spiceLocalBefore.TreeSha256;spicetify_roaming_root=$spiceRoaming;spicetify_roaming_backup=$spiceRoamingBackup;spicetify_roaming_before_tree_sha256=$spiceRoamingBefore.TreeSha256;spicetify_config_semantic_before=$configSemanticBefore;spicetify_config_semantic_after=$null;spicetify_user_assets_before_tree_sha256=$userAssetsBefore.TreeSha256;spicetify_user_assets_before_file_count=$userAssetsBefore.FileCount;spicetify_user_assets_after_tree_sha256=$null;spicetify_user_assets_after_file_count=$null;registry_before_semantic_sha256=$registryBefore;registry_after_semantic_sha256=$null;shortcuts_before_tree_sha256=$shortcutsBefore.TreeSha256;shortcuts_after_tree_sha256=$null;post_guard_desired=$null;post_guard_enforced=$null;final_version=$null;final_spicetify_version=$null;registry_backup=$regBackup;shortcuts_backup=$shortcutBackup;install_started_at=$null;install_finished_at=$null;apply_started_at=$null;apply_finished_at=$null;guard_verified_at=$null;committed_at=$null;rolled_back_at=$null;error=$null}
    Save-SpotifyTransaction -Transaction $txn
    try {
        if((Get-SpotifyRootManifest -Path $spotifyRoot).TreeSha256 -cne $spotifyBefore.TreeSha256){throw 'Spotify root changed after backup; refusing installer launch.'}
        $txn.status='installing';$txn.install_started_at=(Get-Date).ToString('o');Save-SpotifyTransaction -Transaction $txn
        $proc=Start-Process -FilePath ([string]$installer.Path) -ArgumentList @('/silent','/skip-app-launch') -Wait -PassThru -WindowStyle Hidden
        $exit=[int]$proc.ExitCode;$proc.Dispose();Stop-AllSpotifyProcesses
        if($exit -notin @(0,1641,3010)){throw "Spotify installer failed with exit code $exit."}
        $txn.install_finished_at=(Get-Date).ToString('o')
        $newExe=Join-Path $spotifyRoot 'Spotify.exe';$newVersion=Get-SpotifyVersion -Exe $newExe
        if($newVersion -cne [string]$candidate.Version){throw "Installed Spotify version mismatch. expected=$($candidate.Version) actual=$newVersion"}
        $newSig=Get-SpotifyPublisherSignature -Path $newExe;if(-not $newSig.Valid){throw "Installed Spotify executable signature failed: $($newSig.Error)"}
        $protectedAfterInstall=Get-SpotifyProtectedDataManifest;if($protectedAfterInstall.TreeSha256 -cne $protectedBefore.TreeSha256){throw 'Spotify installer changed protected user data; rolling back.'}
        $txn.status='awaiting-apply';Save-SpotifyTransaction -Transaction $txn
        $txn.apply_started_at=(Get-Date).ToString('o');Save-SpotifyTransaction -Transaction $txn
        $apply=Invoke-SpicetifyBackupApplyPinnedPrefs -FullVersion ([string]$candidate.FullVersion)
        if($apply.ExitCode -ne 0){throw "spicetify backup apply failed after Spotify update: $($apply.Output)"}
        $txn.apply_finished_at=(Get-Date).ToString('o')
        Stop-AllSpotifyProcesses
        $protectedAfterApply=Get-SpotifyProtectedDataManifest;if($protectedAfterApply.TreeSha256 -cne $protectedBefore.TreeSha256){throw 'Spicetify repair changed protected Spotify user data; rolling back.'}
        $configSemanticAfter=Get-SpicetifyConfigSemanticHash;if($configSemanticAfter -cne $configSemanticBefore){throw 'Spicetify configuration changed outside allowed Backup version fields.'}
        $userAssetsAfter=Get-SpicetifyUserAssetManifest;if($userAssetsAfter.TreeSha256 -cne $userAssetsBefore.TreeSha256){throw 'Spicetify extension/custom-app/theme source assets changed during Spotify repair.'}
        $guardPlan=Get-SmartUpdateGuardPlan -SpotifyVersionOverride $newVersion
        if($guardPlan.CurrentSupported -ne $true){throw 'Updated Spotify is no longer verified as compatible with installed Spicetify.'}
        $guard=Invoke-SmartUpdateGuard -State $State -Plan $guardPlan
        if(-not $guard.Success -or [string]$guard.Enforced -ne 'blocked'){throw 'Smart Update Guard was not verified blocked after Spotify update.'}
        $registryAfter=Get-SpotifyRegistrySemanticHash;$shortcutsAfter=Get-SpotifyShortcutManifest
        $txn.protected_after_tree_sha256=$protectedAfterApply.TreeSha256;$txn.spicetify_config_semantic_after=$configSemanticAfter;$txn.spicetify_user_assets_after_tree_sha256=$userAssetsAfter.TreeSha256;$txn.spicetify_user_assets_after_file_count=$userAssetsAfter.FileCount;$txn.registry_after_semantic_sha256=$registryAfter;$txn.shortcuts_after_tree_sha256=$shortcutsAfter.TreeSha256;$txn.post_guard_desired=[string]$guard.Desired;$txn.post_guard_enforced=[string]$guard.Enforced;$txn.guard_verified_at=(Get-Date).ToString('o');$txn.status='awaiting-commit';Save-SpotifyTransaction -Transaction $txn
        if($RollbackAfterApply){return Restore-SpotifyTransactionSnapshot -Transaction $txn}
        $finalVersion=Get-SpotifyVersion -Exe (Join-Path $spotifyRoot 'Spotify.exe');if($finalVersion -cne [string]$candidate.Version){throw 'Spotify version changed before commit.'}
        if((Get-SpotifyProtectedDataManifest).TreeSha256 -cne $protectedBefore.TreeSha256){throw 'Protected Spotify user data changed before commit.'}
        $txn.final_version=$finalVersion;$txn.final_spicetify_version=Get-InstalledSpicetifyVersion;$txn.status='committed';$txn.committed_at=(Get-Date).ToString('o');Save-SpotifyTransaction -Transaction $txn
        $State=Ensure-StateShape (Load-State);$State.pending_spotify_update=$false;$State.last_spotify_version=$finalVersion;$State.spotify_last_installer_sha256=[string]$candidate.Sha256;$State.spotify_last_transaction_id=$txn.id;$State.spotify_last_transaction_status='committed';$State.spotify_last_transaction_utc=[DateTimeOffset]::UtcNow.ToString('o');Save-State $State
        Write-Log "Committed trusted Spotify transaction $($txn.id): $before -> $finalVersion; protected user data unchanged."
        return [pscustomobject]@{Success=$true;Changed=$true;Status='committed';State=$State;Transaction=$txn;GuardResult=$guard}
    } catch {
        $err=$_.Exception.Message
        try { $txn=Get-SpotifyTransaction;if($txn){$txn.error=$err;Save-SpotifyTransaction -Transaction $txn};$rb=Restore-SpotifyTransactionSnapshot -Transaction (Get-SpotifyTransaction);$State=Ensure-StateShape (Load-State);$State.pending_spotify_update=$true;$State.spotify_last_transaction_id=$txn.id;$State.spotify_last_transaction_status='rolled-back-failure';$State.spotify_last_transaction_utc=[DateTimeOffset]::UtcNow.ToString('o');Save-State $State;return [pscustomobject]@{Success=$false;Changed=$true;Status='rolled-back-failure';State=$State;Transaction=$rb.Transaction;Error=$err} }
        catch { throw "Spotify transaction failed: $err | rollback failed: $($_.Exception.Message)" }
    }
}


function Get-LatestSpotifyWindowsCandidate {
    $result = [ordered]@{
        Verified = $false
        Version = $null
        FullVersion = $null
        Etag = $null
        OfficialEtag = $null
        OfficialLastModified = $null
        Sha256 = $null
        Size = [int64]0
        Url = $null
        Error = $null
        Source = "Spotify official permanent installer + RobyRew version catalog ETag/SHA-256 match"
    }

    $permanentUrl = "https://download.scdn.co/SpotifyFullSetupX64.exe"
    $feedUrl = "https://robyrew.github.io/spotify-versions-history/api/v1/windows-x64.json"

    try {
        $head = Invoke-WebRequest `
            -Uri $permanentUrl `
            -Method Head `
            -UseBasicParsing `
            -MaximumRedirection 5 `
            -Headers @{ "User-Agent" = "SpotifyControl/$ScriptVersion" }

        $officialEtag = Normalize-Etag ([string]$head.Headers["ETag"])
        $result.OfficialEtag = $officialEtag
        $result.OfficialLastModified = [string]$head.Headers["Last-Modified"]

        if ([string]::IsNullOrWhiteSpace($officialEtag)) {
            throw "Spotify official installer HEAD did not return an ETag."
        }

        $feed = Invoke-RestMethod `
            -Uri $feedUrl `
            -Headers @{ "User-Agent" = "SpotifyControl/$ScriptVersion" }

        if ($null -eq $feed) {
            throw "Spotify version feed returned no data."
        }

        foreach ($property in $feed.PSObject.Properties) {
            $entry = $property.Value
            if ($null -eq $entry -or $null -eq $entry.win -or $null -eq $entry.win.x64) { continue }

            $asset = $entry.win.x64
            $feedEtag = Normalize-Etag ([string]$asset.etag)
            if ([string]::IsNullOrWhiteSpace($feedEtag)) { continue }
            if ($feedEtag -ne $officialEtag) { continue }

            $officialUrl = [string]$asset.official
            $primaryUrl = [string]$asset.url
            $pointsToOfficial = (
                $officialUrl -eq $permanentUrl -or
                $primaryUrl -eq $permanentUrl
            )
            if (-not $pointsToOfficial) { continue }

            $candidateVersion = [string]$property.Name
            $candidateFull = [string]$entry.fullversion

            if ($null -eq (ConvertTo-VersionParts -Version $candidateVersion -Count 4)) {
                throw "Matched feed record had an invalid version: $candidateVersion"
            }

            if ([string]::IsNullOrWhiteSpace($candidateFull)) {
                $candidateFull = $candidateVersion
            }

            $sha256 = ([string]$asset.sha256).Trim().ToLowerInvariant()
            $size = [int64]0
            try { $size = [int64]$asset.size } catch { $size = [int64]0 }
            if ($sha256 -notmatch '^[0-9a-f]{64}$') { throw "Matched feed record is missing a valid SHA-256: $candidateVersion" }
            if ($size -le 0) { throw "Matched feed record is missing a valid installer size: $candidateVersion" }

            $result.Version = $candidateVersion
            $result.FullVersion = $candidateFull
            $result.Etag = $feedEtag
            $result.Sha256 = $sha256
            $result.Size = $size
            $result.Url = $permanentUrl
            $result.Verified = $true
            break
        }

        if (-not $result.Verified) {
            throw "No Windows x64 feed entry matched Spotify's current official installer ETag."
        }
    }
    catch {
        $result.Error = $_.Exception.Message
    }

    return [pscustomobject]$result
}

function Get-SpotifyUpdatePatchState {
    param([string]$SpotifyExe)

    if (-not (Test-UsablePath -Path $SpotifyExe -PathType "Leaf")) { return "unknown" }

    $blockedNeedle = "desktop-update/no/thanks"
    $openNeedle = "desktop-update/v2/update"
    $prefixNeedle = "desktop-update/"
    $maxNeedle = [Math]::Max($blockedNeedle.Length, $openNeedle.Length)
    $buffer = New-Object byte[] (1024 * 1024)
    $carry = ""
    $sawPrefix = $false

    try {
        $fs = [System.IO.File]::Open(
            $SpotifyExe,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::ReadWrite
        )
        try {
            while (($read = $fs.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $chunk = $carry + [System.Text.Encoding]::ASCII.GetString($buffer, 0, $read)
                if ($chunk.Contains($blockedNeedle)) { return "blocked" }
                if ($chunk.Contains($openNeedle)) { return "unblocked" }
                if ($chunk.Contains($prefixNeedle)) { $sawPrefix = $true }

                if ($chunk.Length -gt ($maxNeedle - 1)) {
                    $carry = $chunk.Substring($chunk.Length - ($maxNeedle - 1))
                } else {
                    $carry = $chunk
                }
            }
        }
        finally {
            $fs.Dispose()
        }

        # File was readable, but the legacy endpoint pattern is not present.
        # Current Spotify builds may use a different updater path.
        if (-not $sawPrefix) { return "unrecognized" }
        return "unrecognized"
    }
    catch {
        Write-Log ("Could not inspect Spotify update endpoint state: " + $_.Exception.Message) "WARN"
        return "unknown"
    }
}

function Get-SpotifyUpdateDirectory {
    return (Join-Path $env:LOCALAPPDATA "Spotify\Update")
}

function Get-CurrentUserSid {
    try {
        return [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    } catch {
        return $null
    }
}

function Get-SpotifyUpdateAclState {
    $updateDir = Get-SpotifyUpdateDirectory
    if (-not (Test-UsablePath -Path $updateDir -PathType "Container")) {
        return "unblocked"
    }

    $sidText = Get-CurrentUserSid
    if ([string]::IsNullOrWhiteSpace($sidText)) { return "unknown" }

    try {
        $acl = Get-Acl -LiteralPath $updateDir
        $denyWrite = $false
        $denyDelete = $false

        foreach ($rule in $acl.Access) {
            if ($rule.AccessControlType -ne [System.Security.AccessControl.AccessControlType]::Deny) { continue }

            $ruleSid = $null
            try {
                $ruleSid = $rule.IdentityReference.Translate(
                    [System.Security.Principal.SecurityIdentifier]
                ).Value
            } catch {
                $ruleSid = [string]$rule.IdentityReference
            }

            if ($ruleSid -ne $sidText -and $ruleSid -ne ("*" + $sidText)) { continue }

            $rights = [System.Security.AccessControl.FileSystemRights]$rule.FileSystemRights

            $writeMask = (
                [System.Security.AccessControl.FileSystemRights]::Write -bor
                [System.Security.AccessControl.FileSystemRights]::WriteData -bor
                [System.Security.AccessControl.FileSystemRights]::CreateFiles -bor
                [System.Security.AccessControl.FileSystemRights]::AppendData -bor
                [System.Security.AccessControl.FileSystemRights]::CreateDirectories -bor
                [System.Security.AccessControl.FileSystemRights]::Modify
            )

            if (($rights -band $writeMask) -ne 0) { $denyWrite = $true }
            if (($rights -band [System.Security.AccessControl.FileSystemRights]::Delete) -ne 0) {
                $denyDelete = $true
            }
        }

        if ($denyWrite -and $denyDelete) { return "blocked" }
        return "unblocked"
    }
    catch {
        Write-Log ("Could not inspect Spotify Update folder ACL: " + $_.Exception.Message) "WARN"
        return "unknown"
    }
}

function Invoke-Icacls {
    param([string[]]$Arguments)

    $icacls = Join-Path $env:SystemRoot "System32\icacls.exe"
    if (-not (Test-UsablePath -Path $icacls -PathType "Leaf")) {
        return [pscustomobject]@{
            ExitCode = 127
            StdOut = ""
            StdErr = "icacls.exe not found."
            Output = "icacls.exe not found."
        }
    }

    return Invoke-NativeCapture -FilePath $icacls -Arguments $Arguments
}

function Move-StagedSpotifyUpdateAside {
    $updateDir = Get-SpotifyUpdateDirectory
    if (-not (Test-UsablePath -Path $updateDir -PathType "Container")) { return $null }

    $hasContents = @(Get-ChildItem -LiteralPath $updateDir -Force -ErrorAction SilentlyContinue).Count -gt 0
    if (-not $hasContents) { return $null }

    $quarantineRoot = Join-Path $BackupDir "spotify-update-staging"
    New-Item -ItemType Directory -Force -Path $quarantineRoot | Out-Null

    $dest = Join-Path $quarantineRoot (Get-Date -Format "yyyyMMdd-HHmmss")
    try {
        Move-Item -LiteralPath $updateDir -Destination $dest -Force
        Write-Log "Moved an already-staged Spotify update aside before applying the compatibility lock: $dest" "WARN"

        # Keep at most two quarantined staging directories.
        $old = @(
            Get-ChildItem -LiteralPath $quarantineRoot -Directory -ErrorAction SilentlyContinue |
                Sort-Object Name -Descending |
                Select-Object -Skip 2
        )
        foreach ($item in $old) {
            Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }

        return $dest
    }
    catch {
        Write-Log ("Could not quarantine Spotify's staged update: " + $_.Exception.Message) "ERROR"
        throw
    }
}

function Set-SpotifyUpdateAclState {
    param([ValidateSet("blocked","unblocked")][string]$Desired)

    $updateDir = Get-SpotifyUpdateDirectory
    $sidText = Get-CurrentUserSid

    if ([string]::IsNullOrWhiteSpace($sidText)) {
        return [pscustomobject]@{
            Success = $false
            Previous = "unknown"
            Current = "unknown"
            Changed = $false
            Error = "Could not determine current Windows user SID."
        }
    }

    $previous = Get-SpotifyUpdateAclState
    if ($previous -eq $Desired) {
        return [pscustomobject]@{
            Success = $true
            Previous = $previous
            Current = $previous
            Changed = $false
            Error = $null
        }
    }

    try {
        if ($Desired -eq "blocked") {
            # If Spotify already staged an unsupported update, preserve it outside
            # Spotify's live Update directory rather than deleting it.
            [void](Move-StagedSpotifyUpdateAside)

            if (-not (Test-UsablePath -Path $updateDir -PathType "Container")) {
                New-Item -ItemType Directory -Force -Path $updateDir | Out-Null
            }

            # Numeric SID + leading * avoids localized account-name problems.
            $identity = "*" + $sidText
            $ace = $identity + ":(OI)(CI)(W,D)"
            $r = Invoke-Icacls -Arguments @($updateDir, "/deny", $ace)
            if ($r.ExitCode -ne 0) {
                throw "icacls /deny failed (exit $($r.ExitCode)): $($r.Output)"
            }
        }
        else {
            if (Test-UsablePath -Path $updateDir -PathType "Container") {
                $identity = "*" + $sidText
                $r = Invoke-Icacls -Arguments @($updateDir, "/remove:d", $identity)
                if ($r.ExitCode -ne 0) {
                    throw "icacls /remove:d failed (exit $($r.ExitCode)): $($r.Output)"
                }
            }
        }
    }
    catch {
        $currentOnError = Get-SpotifyUpdateAclState
        return [pscustomobject]@{
            Success = $false
            Previous = $previous
            Current = $currentOnError
            Changed = ($previous -ne $currentOnError)
            Error = $_.Exception.Message
        }
    }

    $current = Get-SpotifyUpdateAclState
    return [pscustomobject]@{
        Success = ($current -eq $Desired)
        Previous = $previous
        Current = $current
        Changed = ($previous -ne $current)
        Error = $(if ($current -eq $Desired) { $null } else { "ACL verification returned '$current' after requesting '$Desired'." })
    }
}

function Set-SpotifyUpdateGuardState {
    param(
        [ValidateSet("blocked","unblocked")][string]$Desired,
        [string]$SpotifyExe
    )

    $patchBefore = Get-SpotifyUpdatePatchState -SpotifyExe $SpotifyExe
    $patchAfter = $patchBefore
    $patchError = $null

    # The binary patch is optional. Use it only when the legacy endpoint is
    # recognizable. The ACL is the authoritative Windows guard.
    if ($script:Spicetify -and $patchBefore -in @("blocked","unblocked")) {
        if ($patchBefore -ne $Desired) {
            $verb = if ($Desired -eq "blocked") { "block" } else { "unblock" }
            $r = Invoke-Spice -Arguments @("spotify-updates",$verb) -AllowFailure
            $patchAfter = Get-SpotifyUpdatePatchState -SpotifyExe $SpotifyExe

            if ($r.ExitCode -ne 0 -or $patchAfter -ne $Desired) {
                $patchError = "Spicetify endpoint patch did not verify: exit=$($r.ExitCode), state=$patchAfter"
                Write-Log $patchError "WARN"
            }
        }
    }
    elseif ($patchBefore -eq "unrecognized") {
        Write-Log "Spotify binary no longer exposes Spicetify's legacy desktop-update endpoint; using Update-folder ACL guard." "WARN"
    }
    elseif ($patchBefore -eq "unknown") {
        Write-Log "Spotify binary update endpoint state is unknown; using Update-folder ACL guard." "WARN"
    }

    $acl = Set-SpotifyUpdateAclState -Desired $Desired

    if ($Desired -eq "blocked") {
        $success = ($acl.Success -and $acl.Current -eq "blocked")
        $enforced = if ($success) { "blocked" } else { "unknown" }
    }
    else {
        # For an unblocked state, the ACL must be open and a known legacy patch
        # must not still be blocked.
        $patchStillBlocked = ($patchAfter -eq "blocked")
        $success = ($acl.Success -and $acl.Current -eq "unblocked" -and -not $patchStillBlocked)
        $enforced = if ($success) { "unblocked" } else { "unknown" }
    }

    $method = if ($patchAfter -eq $Desired -and $acl.Current -eq $Desired) {
        "binary+acl"
    } elseif ($acl.Current -eq $Desired) {
        "acl"
    } elseif ($patchAfter -eq $Desired) {
        "binary"
    } else {
        "none"
    }

    $errors = @()
    if ($patchError) { $errors += $patchError }
    if (-not $acl.Success -and $acl.Error) { $errors += $acl.Error }

    return [pscustomobject]@{
        Success = $success
        Desired = $Desired
        Enforced = $enforced
        Method = $method
        PatchBefore = $patchBefore
        PatchCurrent = $patchAfter
        AclPrevious = $acl.Previous
        AclCurrent = $acl.Current
        Error = $(if ($errors.Count -gt 0) { $errors -join " | " } else { $null })
    }
}

function Get-SmartUpdateGuardPlan {
    param([AllowNull()][AllowEmptyString()][string]$SpotifyVersionOverride)

    $spotifyExe = Get-SpotifyExecutable
    $spotifyVersion = if (-not [string]::IsNullOrWhiteSpace($SpotifyVersionOverride)) {
        $SpotifyVersionOverride
    } else {
        Get-SpotifyVersion -Exe $spotifyExe
    }
    $compat = Get-SpicetifyWindowsCompatibility
    $candidate = Get-LatestSpotifyWindowsCandidate

    $currentSupported = $false
    $currentSupportKnown = $false

    if ($compat.Verified -and -not [string]::IsNullOrWhiteSpace($spotifyVersion)) {
        $currentSupportKnown = $true
        $currentSupported = Test-SpotifyVersionInRange `
            -SpotifyVersion $spotifyVersion `
            -MinSupported $compat.Min `
            -MaxSupported $compat.Max
    }

    $desired = "blocked"
    $reason = ""
    $updateWindow = $false

    if (-not $compat.Verified) {
        $reason = "Spicetify compatibility could not be verified; fail-closed."
    }
    elseif ([string]::IsNullOrWhiteSpace($spotifyVersion)) {
        $reason = "Installed Spotify version could not be determined; fail-closed."
    }
    elseif (-not $currentSupported) {
        $reason = "Installed Spotify $spotifyVersion is outside installed Spicetify $($compat.Tag) Windows support range $($compat.Min) -> $($compat.Max)."
    }
    elseif (-not $candidate.Verified) {
        $reason = "Latest Spotify candidate could not be ETag-verified; fail-closed."
    }
    elseif (-not (Test-SpotifyVersionInRange -SpotifyVersion $candidate.Version -MinSupported $compat.Min -MaxSupported $compat.Max)) {
        $reason = "Latest Spotify $($candidate.Version) is outside installed Spicetify $($compat.Tag) Windows support range $($compat.Min) -> $($compat.Max)."
    }
    else {
        $cmp = Compare-VersionParts -A $candidate.Version -B $spotifyVersion -Count 4
        if ($null -eq $cmp) {
            $reason = "Could not compare installed and candidate Spotify versions; fail-closed."
        }
        elseif ($cmp -gt 0) {
            if ($SpotifyTransactionalUpdatesReady) {
                $desired = "blocked"
                $updateWindow = $true
                $reason = "Verified compatible Spotify Control transaction is available: $spotifyVersion -> $($candidate.Version); native updater remains blocked and only the pinned transaction may install it."
            } else {
                $reason = "Verified compatible Spotify $($candidate.Version) exists, but the trusted Spotify transaction stage is not armed yet; native updater remains blocked fail-closed."
            }
        }
        else {
            $reason = "No newer verified compatible Spotify build is pending; updater window closed."
        }
    }

    return [pscustomobject]@{
        Desired = $desired
        Reason = $reason
        CurrentVersion = $spotifyVersion
        CurrentSupported = $(if ($currentSupportKnown) { $currentSupported } else { $null })
        CompatibilityVerified = $compat.Verified
        SpicetifyTag = $compat.Tag
        MinSupported = $compat.Min
        MaxSupported = $compat.Max
        CandidateVerified = $candidate.Verified
        CandidateVersion = $candidate.Version
        CandidateFullVersion = $candidate.FullVersion
        CandidateEtag = $candidate.Etag
        CandidateSha256 = $candidate.Sha256
        CandidateSize = $candidate.Size
        CandidateUrl = $candidate.Url
        OfficialEtag = $candidate.OfficialEtag
        UpdateWindow = $updateWindow
        CompatibilityError = $compat.Error
        CandidateError = $candidate.Error
    }
}

function Invoke-SmartUpdateGuard {
    param($State, $Plan = $null)

    $State = Ensure-StateShape $State
    if ($null -eq $Plan) { $Plan = Get-SmartUpdateGuardPlan }

    $spotifyExe = Get-SpotifyExecutable
    $desired = [string]$Plan.Desired
    if ([string]::IsNullOrWhiteSpace($desired)) { $desired = "blocked" }

    $patch = Set-SpotifyUpdateGuardState -Desired $desired -SpotifyExe $spotifyExe

    if (-not $patch.Success) {
        Write-Log ("Smart Update Guard could not enforce '$desired': " + $patch.Error) "ERROR"
    }

    $State.last_guard_check = [DateTimeOffset]::UtcNow.ToString("o")
    $State.guard_desired = $desired
    $State.guard_enforced = $patch.Enforced
    $State.guard_enforcement_ok = [bool]$patch.Success
    $State.guard_method = $patch.Method
    $State.update_patch_state = $patch.PatchCurrent
    $State.update_acl_state = $patch.AclCurrent
    $State.guard_blocked = $(if ($patch.Enforced -eq "blocked") { $true } elseif ($patch.Enforced -eq "unblocked") { $false } else { $null })
    $State.guard_reason = [string]$Plan.Reason
    $State.current_spotify_supported = $Plan.CurrentSupported
    $State.spicetify_installed_version = Get-InstalledSpicetifyVersion
    $State.spicetify_compat_tag = $Plan.SpicetifyTag
    $State.spicetify_compat_min_windows = $Plan.MinSupported
    $State.spicetify_max_windows = $Plan.MaxSupported
    $State.spotify_candidate_version = $Plan.CandidateVersion
    $State.spotify_candidate_fullversion = $Plan.CandidateFullVersion
    $State.spotify_candidate_etag = $Plan.CandidateEtag
    $State.pending_guard_desired = $desired
    $State.pending_guard_reason = [string]$Plan.Reason
    Save-State $State

    $level = if ($desired -eq "blocked") { "WARN" } else { "INFO" }
    Write-Log ("Smart Update Guard: desired={0}; enforced={1}; method={2}; patch={3}; acl={4}; installed={5}; candidate={6}; spicetify={7}; max={8}; reason={9}" -f `
        $desired,
        $patch.Enforced,
        $patch.Method,
        $patch.PatchCurrent,
        $patch.AclCurrent,
        $Plan.CurrentVersion,
        $Plan.CandidateVersion,
        $Plan.SpicetifyTag,
        $Plan.MaxSupported,
        $Plan.Reason
    ) $level

    $result = [pscustomobject]@{
        Success = $patch.Success
        Desired = $desired
        Enforced = $patch.Enforced
        Method = $patch.Method
        PatchState = $patch.PatchCurrent
        AclState = $patch.AclCurrent
        Reason = $Plan.Reason
        CurrentVersion = $Plan.CurrentVersion
        CurrentSupported = $Plan.CurrentSupported
        CompatibilityVerified = $Plan.CompatibilityVerified
        SpicetifyTag = $Plan.SpicetifyTag
        MinSupported = $Plan.MinSupported
        MaxSupported = $Plan.MaxSupported
        CandidateVerified = $Plan.CandidateVerified
        CandidateVersion = $Plan.CandidateVersion
        CandidateFullVersion = $Plan.CandidateFullVersion
        CandidateEtag = $Plan.CandidateEtag
        OfficialEtag = $Plan.OfficialEtag
        UpdateWindow = $Plan.UpdateWindow
        State = $State
    }

    $script:LastGuardResult = $result
    return $result
}

function Backup-Config {
    $config = Get-ConfigPath
    if ($config) {
        $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $dest = Join-Path $BackupDir "config-$stamp.ini"
        Copy-Item -LiteralPath $config -Destination $dest -Force
        Write-Log "Backed up Spicetify config to $dest"
    }
}

function Set-SafePreprocessDefaults {
    if (-not $script:Spicetify) { return $false }

    $config = Get-ConfigPath
    $changes = @()
    foreach ($item in @(
        @("disable_sentry","1"),
        @("disable_ui_logging","1"),
        @("remove_rtl_rule","1")
    )) {
        $key = $item[0]
        $wanted = $item[1]
        $current = Get-IniValue -Path $config -Key $key
        if ($current -ne $wanted) {
            $changes += @($key,$wanted)
        }
    }

    if ($changes.Count -eq 0) {
        Write-Log "Lightweight preprocess settings already correct."
        return $false
    }

    $r = Invoke-Spice -Arguments (@("config") + $changes) -AllowFailure
    if ($r.ExitCode -ne 0) {
        Write-Log "Could not set lightweight preprocess options; existing config kept." "WARN"
        return $false
    }
    return $true
}

function Get-CustomAppsValue {
    if (-not $script:Spicetify) { return "" }
    $r = Invoke-SpiceCapture -Arguments @("config","custom_apps")
    if ($r.ExitCode -ne 0) { return "" }
    return $r.StdOut
}

function Update-Marketplace {
    param($State)
    $State = Ensure-StateShape $State
    $txid = [guid]::NewGuid().ToString("N")
    $started = [DateTimeOffset]::UtcNow.ToString("o")
    $report = [ordered]@{
        schema=1; transaction_id=$txid; started_utc=$started; finished_utc=$null; status="starting"
        tag=$null; target=$null; backup=$null; published_digest=$null; actual_digest=$null
        old_tree_sha256=$null; new_tree_sha256=$null; apply_exit_code=$null; rollback_apply_exit_code=$null
        swapped=$false; post_verify=$false; rollback_attempted=$false; rollback_verified=$false; error=$null
    }
    $work = Join-Path $env:TEMP ("SpotifyControl-Marketplace-Txn-" + $txid)
    $stageLocal = $null; $oldLocal = $null; $backup = $null; $configBackup = $null
    $marketApp = $null; $oldRemoteTag = $State.marketplace_remote_tag
    $committed = $false
    $swapStarted = $false

    if (-not $script:Spicetify) {
        Write-Log "Skipping Marketplace update: Spicetify not found." "WARN"
        return [pscustomobject]@{ Changed=$false; ApplyCompleted=$false; State=$State; Status="skipped" }
    }
    if (Test-SpotifyRunning) {
        Write-Log "Marketplace transaction deferred because Spotify is running." "WARN"
        return [pscustomobject]@{ Changed=$false; ApplyCompleted=$false; State=$State; Status="deferred-running" }
    }

    New-Item -ItemType Directory -Force -Path $work | Out-Null
    try {
        $resolution = Get-MarketplaceInstallResolution
        if ($resolution.Status -ne "resolved") {
            throw "Marketplace installation must resolve to exactly one existing root; status=$($resolution.Status); locations=$(@($resolution.Locations) -join '; ')"
        }
        $marketApp = $resolution.Path
        $report.target = $marketApp
        $oldPayload = Test-MarketplacePayload -Path $marketApp
        if (-not $oldPayload.Valid) { throw "Existing Marketplace install is not a valid rollback source: $($oldPayload.Error)" }
        $report.old_tree_sha256 = $oldPayload.TreeSha256

        $info = Get-MarketplaceLatestReleaseInfo
        $State.last_marketplace_check = [DateTimeOffset]::UtcNow.ToString("o")
        if (-not $info.Verified) { throw "Marketplace release trust verification failed: $($info.Error)" }
        $tag = Normalize-MarketplaceTag $info.Tag
        $report.tag=$tag; $report.published_digest=$info.AssetDigest

        if (-not $Force -and (Normalize-MarketplaceTag ([string]$State.marketplace_remote_tag)) -eq $tag) {
            $State.marketplace_remote_tag = $tag
            $State.marketplace_last_digest = $info.AssetDigest
            $State.pending_marketplace_update = $false
            $State.pending_marketplace_tag = $tag
            $State.pending_marketplace_digest = $info.AssetDigest
            Save-State $State
            $report.status="already-current"; $report.finished_utc=[DateTimeOffset]::UtcNow.ToString("o")
            $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $MarketplaceTransactionReport -Encoding UTF8
            Write-Log "Marketplace already at trusted latest tag $tag. No mutation required."
            return [pscustomobject]@{ Changed=$false; ApplyCompleted=$false; State=$State; Status="already-current" }
        }

        $payload = Expand-AndValidateMarketplaceAsset -ReleaseInfo $info -WorkRoot $work
        $report.actual_digest=$payload.ActualDigest; $report.new_tree_sha256=$payload.Validation.TreeSha256

        if (Test-SpotifyRunning) { throw "Spotify started before Marketplace staging/swap; transaction aborted before mutation." }

        $parent = Split-Path -Parent $marketApp
        $stageLocal = Join-Path $parent (".spotifycontrol-marketplace-stage-" + $txid)
        $oldLocal = Join-Path $parent (".spotifycontrol-marketplace-old-" + $txid)
        if (Test-Path -LiteralPath $stageLocal) { Remove-Item -LiteralPath $stageLocal -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $stageLocal | Out-Null
        Copy-Item -Path (Join-Path $payload.Source "*") -Destination $stageLocal -Recurse -Force
        $localValidation = Test-MarketplacePayload -Path $stageLocal
        if (-not $localValidation.Valid -or $localValidation.TreeSha256 -ne $payload.Validation.TreeSha256) { throw "Same-volume staged Marketplace tree failed validation/hash equality." }

        $safeTag = ($tag -replace '[^A-Za-z0-9._-]','_')
        $backup = Join-Path $BackupDir ("marketplace-transactions\{0}-{1}-{2}" -f (Get-Date -Format "yyyyMMdd-HHmmss"),$safeTag,$txid.Substring(0,8))
        New-Item -ItemType Directory -Force -Path $backup | Out-Null
        Copy-Item -LiteralPath $marketApp -Destination (Join-Path $backup "before") -Recurse -Force
        $report.backup=$backup
        $backupValidation = Test-MarketplacePayload -Path (Join-Path $backup "before")
        if (-not $backupValidation.Valid -or $backupValidation.TreeSha256 -ne $oldPayload.TreeSha256) { throw "Marketplace rollback backup verification failed before swap." }
        if ($resolution.ConfigPath -and (Test-UsablePath -Path $resolution.ConfigPath -PathType "Leaf")) {
            $configBackup = Join-Path $backup "config-xpui.ini.before"
            Copy-Item -LiteralPath $resolution.ConfigPath -Destination $configBackup -Force
        }

        if (Test-SpotifyRunning) { throw "Spotify started immediately before Marketplace swap; transaction aborted before mutation." }
        $swapStarted=$true
        Move-Item -LiteralPath $marketApp -Destination $oldLocal
        Move-Item -LiteralPath $stageLocal -Destination $marketApp
        $report.swapped=$true

        $customApps = Get-CustomAppsValue
        if ($customApps -notmatch '(^|[|,\s])marketplace($|[|,\s])') {
            $cfg = Invoke-Spice -Arguments @("config","custom_apps","marketplace") -AllowFailure
            if ($cfg.ExitCode -ne 0) { throw "Could not ensure Marketplace is present in Spicetify custom_apps." }
        }

        if (Test-SpotifyRunning) { throw "Spotify started after Marketplace swap but before apply." }
        $apply = Invoke-Spice -Arguments @("apply","--no-restart") -AllowFailure
        $report.apply_exit_code=[int]$apply.ExitCode
        if ($apply.ExitCode -ne 0) { throw "spicetify apply failed after Marketplace swap with exit code $($apply.ExitCode)." }

        $post = Test-MarketplacePayload -Path $marketApp
        $customAppsPost = Get-CustomAppsValue
        if (-not $post.Valid) { throw "Marketplace post-verify payload failed: $($post.Error)" }
        if ($post.TreeSha256 -ne $payload.Validation.TreeSha256) { throw "Marketplace post-verify tree hash differs from trusted staged tree." }
        if ($customAppsPost -notmatch '(^|[|,\s])marketplace($|[|,\s])') { throw "Marketplace post-verify custom_apps check failed." }
        $report.post_verify=$true

        # Commit state only after published digest verification, swap, apply, and post-verify all succeed.
        $State.marketplace_remote_tag = $tag
        $State.marketplace_last_digest = $info.AssetDigest
        $State.marketplace_last_transaction_id = $txid
        $State.marketplace_last_transaction_status = "committed"
        $State.marketplace_last_transaction_utc = [DateTimeOffset]::UtcNow.ToString("o")
        $State.pending_marketplace_update = $false
        $State.pending_marketplace_tag = $tag
        $State.pending_marketplace_digest = $info.AssetDigest
        Save-State $State
        $committed=$true
        $report.status="committed"
        if (Test-Path -LiteralPath $oldLocal -PathType Container) { Remove-Item -LiteralPath $oldLocal -Recurse -Force -ErrorAction SilentlyContinue }
        Write-Log "Marketplace transaction committed: tag=$tag digest=$($info.AssetDigest) backup=$backup"
        return [pscustomobject]@{ Changed=$true; ApplyCompleted=$true; State=$State; Status="committed" }
    } catch {
        $report.error=$_.Exception.Message
        Write-Log ("Marketplace transaction failed: " + $report.error) "WARN"
        $rollbackError=$null
        if ($swapStarted) {
            $report.rollback_attempted=$true
            try {
                if ($marketApp) {
                    $oldExists = ($oldLocal -and (Test-Path -LiteralPath $oldLocal -PathType Container))
                    if ($oldExists) {
                        if (Test-Path -LiteralPath $marketApp -PathType Container) { Remove-Item -LiteralPath $marketApp -Recurse -Force -ErrorAction Stop }
                        Move-Item -LiteralPath $oldLocal -Destination $marketApp
                    } elseif (-not (Test-Path -LiteralPath $marketApp -PathType Container) -and $backup -and (Test-Path -LiteralPath (Join-Path $backup "before") -PathType Container)) {
                        Copy-Item -LiteralPath (Join-Path $backup "before") -Destination $marketApp -Recurse -Force
                    }
                    if ($configBackup -and $resolution.ConfigPath -and (Test-Path -LiteralPath $configBackup -PathType Leaf)) {
                        Copy-Item -LiteralPath $configBackup -Destination $resolution.ConfigPath -Force
                    }
                    $restored = Test-MarketplacePayload -Path $marketApp
                    if ($restored.Valid -and $report.old_tree_sha256 -and $restored.TreeSha256 -eq $report.old_tree_sha256) { $report.rollback_verified=$true }
                }
                if (-not (Test-SpotifyRunning)) {
                    $rbApply = Invoke-Spice -Arguments @("apply","--no-restart") -AllowFailure
                    $report.rollback_apply_exit_code=[int]$rbApply.ExitCode
                    if ($rbApply.ExitCode -ne 0) { $State.pending_auto_repair=$true }
                } else {
                    $State.pending_auto_repair=$true
                }
            } catch { $rollbackError=$_.Exception.Message; $State.pending_auto_repair=$true }
        } else {
            # Trust/staging failures happened before any live Marketplace mutation.
            $report.rollback_verified=$true
        }
        $script:MaintenanceHealthy = $false
        $State.marketplace_remote_tag = $oldRemoteTag
        $State.marketplace_last_transaction_id = $txid
        $State.marketplace_last_transaction_status = $(if(-not $swapStarted){"aborted-pre-mutation"}elseif($report.rollback_verified){"rolled-back"}else{"rollback-incomplete"})
        $State.marketplace_last_transaction_utc = [DateTimeOffset]::UtcNow.ToString("o")
        Save-State $State
        if ($rollbackError) { $report.error += " | rollback_error=" + $rollbackError }
        $report.status = $State.marketplace_last_transaction_status
        return [pscustomobject]@{ Changed=$false; ApplyCompleted=$false; State=$State; Status=$report.status }
    } finally {
        if (-not $committed -and $stageLocal -and (Test-Path -LiteralPath $stageLocal)) { Remove-Item -LiteralPath $stageLocal -Recurse -Force -ErrorAction SilentlyContinue }
        if ($committed -and $oldLocal -and (Test-Path -LiteralPath $oldLocal)) { Remove-Item -LiteralPath $oldLocal -Recurse -Force -ErrorAction SilentlyContinue }
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
        $report.finished_utc=[DateTimeOffset]::UtcNow.ToString("o")
        try { $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $MarketplaceTransactionReport -Encoding UTF8 } catch {}
    }
}
function Invoke-AddonManager {
    param(
        [ValidateSet("Check","Update","Backup","RollbackLast","CommitLast","Status","FinalizeRecovery","PithayaPreflight","TransactionSelfTest","DirectExtensionPreflight")]
        [string]$AddonAction,
        [switch]$ForceAddon
    )

    if (-not (Test-UsablePath -Path $AddonManager -PathType "Leaf")) {
        Write-Log "Addon Manager script not found: $AddonManager" "WARN"
        return [pscustomobject]@{ ExitCode=127; Output="Addon Manager missing" }
    }

    $ps = Join-Path $PSHOME "powershell.exe"
    if (-not (Test-UsablePath -Path $ps -PathType "Leaf")) {
        $ps = (Get-Command powershell.exe -ErrorAction Stop).Path
    }

    $args = @("-NoProfile","-ExecutionPolicy","Bypass","-File",$AddonManager,"-Action",$AddonAction)
    if ($ForceAddon) { $args += "-Force" }
    $r = Invoke-NativeCapture -FilePath $ps -Arguments $args

    if ($r.Output) {
        $clean = $r.Output -replace "`r?`n"," | "
        $level = if ($r.ExitCode -in @(0,10)) { "INFO" } else { "WARN" }
        Write-Log ("AddonManager {0} [exit={1}]: {2}" -f $AddonAction,$r.ExitCode,$clean) $level
    }
    return $r
}

function Start-PerformanceSnapshotAsync {
    if (-not (Test-UsablePath -Path $PerformanceProfiler -PathType "Leaf")) { return }
    try {
        $ps = Join-Path $PSHOME "powershell.exe"
        if (-not (Test-UsablePath -Path $ps -PathType "Leaf")) {
            $ps = (Get-Command powershell.exe -ErrorAction Stop).Path
        }
        Start-Process -FilePath $ps -WindowStyle Hidden -ArgumentList @(
            "-NoProfile","-ExecutionPolicy","Bypass",
            "-File",$PerformanceProfiler,
            "-Action","Snapshot"
        ) | Out-Null
    } catch {
        Write-Log ("Could not start background performance snapshot: "+$_.Exception.Message) "WARN"
    }
}

function Install-TasksAndShortcuts {
    $installedBin = Join-Path $Root "bin"
    New-Item -ItemType Directory -Force -Path $installedBin | Out-Null

    foreach ($name in @(
        "spotify-control.ps1",
        "collect-spotify-diagnostics.ps1",
        "launch-managed.vbs",
        "run-audit.cmd",
        "show-status.cmd",
        "addon-manager.ps1",
        "show-addons.cmd",
        "performance-profiler.ps1",
        "show-performance.cmd",
        "health-report.ps1",
        "show-health.cmd",
        "performance-ab-profiler.ps1",
        "run-performance-ab.cmd",
        "show-performance-ab.cmd",
        "marketplace-isolation-profiler.ps1",
        "run-marketplace-isolation.cmd",
        "show-marketplace-isolation.cmd"
    )) {
        $source = Join-Path $BinDir $name
        if (Test-UsablePath -Path $source) {
            Copy-Item -LiteralPath $source -Destination (Join-Path $installedBin $name) -Force
        }
    }

    $installedMain = Join-Path $installedBin "spotify-control.ps1"
    $installedVbs = Join-Path $installedBin "launch-managed.vbs"
    $installedAudit = Join-Path $installedBin "run-audit.cmd"
    Remove-Item -LiteralPath (Join-Path $installedBin "launch-managed.cmd") -Force -ErrorAction SilentlyContinue

    $ps = Join-Path $PSHOME "powershell.exe"
    if (-not (Test-UsablePath -Path $ps -PathType "Leaf")) {
        $ps = (Get-Command powershell.exe -ErrorAction Stop).Path
    }

    $taskName = "SpotifyControl Maintenance"
    $taskCmd = "`"$ps`" -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$installedMain`" -Action Maintain"
    $taskCreated = $false

    try {
        $task = Invoke-NativeCapture -FilePath (Join-Path $env:SystemRoot "System32\schtasks.exe") -Arguments @(
            "/Create","/TN",$taskName,"/SC","ONLOGON","/DELAY","0001:00","/TR",$taskCmd,"/F"
        )
        if ($task.ExitCode -eq 0) {
            $taskCreated = $true
            Write-Log "Created scheduled task: $taskName"
        } else {
            Write-Log "Task Scheduler creation failed ($($task.ExitCode)): $($task.Output)" "WARN"
        }
    } catch {
        Write-Log ("Task Scheduler creation failed: " + $_.Exception.Message) "WARN"
    }

    $shell = New-Object -ComObject WScript.Shell

    $startupDir = [Environment]::GetFolderPath("Startup")
    if (-not $startupDir) {
        $startupDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup"
    }
    $startupLink = Join-Path $startupDir "SpotifyControl Maintenance.lnk"

    if (-not $taskCreated) {
        New-Item -ItemType Directory -Force -Path $startupDir | Out-Null
        $startupShortcut = $shell.CreateShortcut($startupLink)
        $startupShortcut.TargetPath = $ps
        $startupShortcut.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$installedMain`" -Action Maintain"
        $startupShortcut.WorkingDirectory = $Root
        $startupShortcut.Description = "Spotify Control automatic maintenance"
        $startupShortcut.Save()
        Write-Log "Using per-user Startup fallback for automatic maintenance."
    } else {
        Remove-Item -LiteralPath $startupLink -Force -ErrorAction SilentlyContinue
    }

    $spotifyExe = $null
    try {
        $spotifyExe = Get-SpotifyExecutable
    } catch {
        Write-Log ("Spotify executable discovery failed during shortcut creation; continuing without a custom icon. " + $_.Exception.Message) "WARN"
        $spotifyExe = $null
    }

    $desktop = [Environment]::GetFolderPath("Desktop")
    $startMenu = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
    $wscript = Join-Path $env:SystemRoot "System32\wscript.exe"

    $managedTargets = @()
    if (-not [string]::IsNullOrWhiteSpace($desktop)) {
        $managedTargets += (Join-Path $desktop "Spotify (Managed).lnk")
    }
    if (-not [string]::IsNullOrWhiteSpace($startMenu)) {
        $managedTargets += (Join-Path $startMenu "Spotify (Managed).lnk")
    }

    # Future managed-shortcut safety: custom owner launchers are immutable.
# A WScript shortcut targeting another VBS is not ours to change or execute.
$expectedManagedArgs = '"' + $installedVbs + '"'
# If the owner has kept only one of the default locations, never recreate
# the deliberately absent Desktop or Start Menu shortcut on maintenance.
# For a genuinely fresh install with neither link, create both as before.
$managedLinkAlreadyPresent = @($managedTargets | Where-Object {
    Test-Path -LiteralPath $_
}).Count -gt 0
foreach ($target in $managedTargets) {
    $exists = Test-Path -LiteralPath $target
    if (-not $exists -and $managedLinkAlreadyPresent) { continue }
    $ownedOldBin = $false
    $skip = $false
    if ($exists) {
        try {
            $file = Get-Item -LiteralPath $target -Force -ErrorAction Stop
            if ($file.PSIsContainer -or
                ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                $skip = $true
            } else {
                $entry = $shell.CreateShortcut($target)
                $official = [string]::Equals([string]$entry.TargetPath,
                    [string]$wscript,[StringComparison]::OrdinalIgnoreCase) -and
                    ([string]$entry.Arguments -ceq $expectedManagedArgs)
                if (-not $official) {
                    $skip = $true
                } elseif ([string]::Equals([string]$entry.WorkingDirectory,
                        [string]$Root,[StringComparison]::OrdinalIgnoreCase)) {
                    $skip = $true
                } elseif ([string]::Equals([string]$entry.WorkingDirectory,
                        [string]$installedBin,[StringComparison]::OrdinalIgnoreCase)) {
                    $ownedOldBin = $true
                } else {
                    # Owner-custom working directory is not ours.
                    $skip = $true
                }
            }
        } catch {
            $skip = $true
        }
    }
    if ($skip) { continue }

    $temp = Join-Path (Split-Path -Parent $target) (
        ".spotify-control-managed-cwd-" + [guid]::NewGuid().ToString("N") + ".lnk")
    try {
        $sourceHash = $null
        if ($ownedOldBin) {
            $sourceHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
            [IO.File]::Copy($target,$temp,$false)
            # Do not change the owner's description, icon, hotkeys or other
            # metadata on an already-owned official launcher. Only its CWD.
            $candidate = $shell.CreateShortcut($temp)
            $candidate.WorkingDirectory = $Root
        } else {
            $candidate = $shell.CreateShortcut($temp)
            $candidate.TargetPath = $wscript
            $candidate.Arguments = $expectedManagedArgs
            $candidate.WorkingDirectory = $Root
            if (Test-UsablePath -Path $spotifyExe -PathType "Leaf") {
                $candidate.IconLocation = "$spotifyExe,0"
            }
            $candidate.Description = "Launch Spotify through Spotify Control without a console window"
        }
        $candidate.Save()

        $check = $shell.CreateShortcut($temp)
        if (-not [string]::Equals([string]$check.TargetPath,
                [string]$wscript,[StringComparison]::OrdinalIgnoreCase) -or
            [string]$check.Arguments -cne $expectedManagedArgs -or
            -not [string]::Equals([string]$check.WorkingDirectory,
                [string]$Root,[StringComparison]::OrdinalIgnoreCase)) {
            throw "Staged managed link identity mismatch"
        }
        if ($ownedOldBin) {
            $again = $shell.CreateShortcut($target)
            if (-not [string]::Equals([string]$again.TargetPath,
                    [string]$wscript,[StringComparison]::OrdinalIgnoreCase) -or
                [string]$again.Arguments -cne $expectedManagedArgs -or
                -not [string]::Equals([string]$again.WorkingDirectory,
                    [string]$installedBin,[StringComparison]::OrdinalIgnoreCase)) {
                throw "Original managed link changed while staging"
            }
            if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -cne $sourceHash) {
                throw "Original managed link bytes changed during staging"
            }
            # Adjacent immutable original backup: same-volume atomic replace.
            $saved = Join-Path (Split-Path -Parent $target) (
                ".spotify-control-managed-before-neutral-" +
                [guid]::NewGuid().ToString("N") + ".lnk")
            [IO.File]::Replace($temp,$target,$saved,$true)
        } else {
            # Atomic create-no-replace; a raced custom link remains untouched.
            [IO.File]::Move($temp,$target)
        }
    } catch {
        Write-Log "Managed shortcut neutral workdir deferred; original preserved." "WARN"
    } finally {
        if (Test-Path -LiteralPath $temp) {
            try { [IO.File]::Delete($temp) } catch {}
        }
    }
}

    if (-not [string]::IsNullOrWhiteSpace($startMenu)) {
        $diagTarget = Join-Path $startMenu "Spotify Control Diagnostics.lnk"
        $diagShortcut = $shell.CreateShortcut($diagTarget)
        $diagShortcut.TargetPath = $installedAudit
        $diagShortcut.WorkingDirectory = $installedBin
        if (Test-UsablePath -Path $spotifyExe -PathType "Leaf") { $diagShortcut.IconLocation = "$spotifyExe,0" }
        $diagShortcut.Description = "Collect Spotify/Spicetify diagnostics"
        $diagShortcut.Save()

        $statusCmd = Join-Path $installedBin "show-status.cmd"
        if (Test-UsablePath -Path $statusCmd -PathType "Leaf") {
            $statusTarget = Join-Path $startMenu "Spotify Control Status.lnk"
            $statusShortcut = $shell.CreateShortcut($statusTarget)
            $statusShortcut.TargetPath = $statusCmd
            $statusShortcut.WorkingDirectory = $installedBin
            if (Test-UsablePath -Path $spotifyExe -PathType "Leaf") { $statusShortcut.IconLocation = "$spotifyExe,0" }
            $statusShortcut.Description = "Show Spotify Control Smart Update Guard status"
            $statusShortcut.Save()
        }

        $addonsCmd = Join-Path $installedBin "show-addons.cmd"
        if (Test-UsablePath -Path $addonsCmd -PathType "Leaf") {
            $addonsTarget = Join-Path $startMenu "Spotify Control Addons.lnk"
            $addonsShortcut = $shell.CreateShortcut($addonsTarget)
            $addonsShortcut.TargetPath = $addonsCmd
            $addonsShortcut.WorkingDirectory = $installedBin
            if (Test-UsablePath -Path $spotifyExe -PathType "Leaf") { $addonsShortcut.IconLocation = "$spotifyExe,0" }
            $addonsShortcut.Description = "Show CustomApps/extension update and backup status"
            $addonsShortcut.Save()
        }

        $perfCmd = Join-Path $installedBin "show-performance.cmd"
        if (Test-UsablePath -Path $perfCmd -PathType "Leaf") {
            $perfShortcut = $shell.CreateShortcut((Join-Path $startMenu "Spotify Control Performance.lnk"))
            $perfShortcut.TargetPath = $perfCmd
            $perfShortcut.WorkingDirectory = $installedBin
            if (Test-UsablePath -Path $spotifyExe -PathType "Leaf") { $perfShortcut.IconLocation = "$spotifyExe,0" }
            $perfShortcut.Description = "Show daily Spotify CPU/RAM performance snapshots"
            $perfShortcut.Save()
        }

        $healthCmd = Join-Path $installedBin "show-health.cmd"
        if (Test-UsablePath -Path $healthCmd -PathType "Leaf") {
            $healthShortcut = $shell.CreateShortcut((Join-Path $startMenu "Spotify Control Health.lnk"))
            $healthShortcut.TargetPath = $healthCmd
            $healthShortcut.WorkingDirectory = $installedBin
            if (Test-UsablePath -Path $spotifyExe -PathType "Leaf") { $healthShortcut.IconLocation = "$spotifyExe,0" }
            $healthShortcut.Description = "Show unified Spotify Control health summary"
            $healthShortcut.Save()
        }

        $abCmd = Join-Path $installedBin "run-performance-ab.cmd"
        if (Test-UsablePath -Path $abCmd -PathType "Leaf") {
            $abShortcut = $shell.CreateShortcut((Join-Path $startMenu "Spotify Control A-B Profiler.lnk"))
            $abShortcut.TargetPath = $abCmd
            $abShortcut.WorkingDirectory = $installedBin
            if (Test-UsablePath -Path $spotifyExe -PathType "Leaf") { $abShortcut.IconLocation = "$spotifyExe,0" }
            $abShortcut.Description = "Benchmark extensions and CustomApps one at a time, then restore original config"
            $abShortcut.Save()
        }

        $abResultsCmd = Join-Path $installedBin "show-performance-ab.cmd"
        if (Test-UsablePath -Path $abResultsCmd -PathType "Leaf") {
            $abResultsShortcut = $shell.CreateShortcut((Join-Path $startMenu "Spotify Control A-B Results.lnk"))
            $abResultsShortcut.TargetPath = $abResultsCmd
            $abResultsShortcut.WorkingDirectory = $installedBin
            if (Test-UsablePath -Path $spotifyExe -PathType "Leaf") { $abResultsShortcut.IconLocation = "$spotifyExe,0" }
            $abResultsShortcut.Description = "Show the latest Spotify extension performance ranking"
            $abResultsShortcut.Save()
        }

        $marketCmd = Join-Path $installedBin "run-marketplace-isolation.cmd"
        if (Test-UsablePath -Path $marketCmd -PathType "Leaf") {
            $marketShortcut = $shell.CreateShortcut((Join-Path $startMenu "Spotify Control Marketplace Isolation.lnk"))
            $marketShortcut.TargetPath = $marketCmd
            $marketShortcut.WorkingDirectory = $installedBin
            if (Test-UsablePath -Path $spotifyExe -PathType "Leaf") { $marketShortcut.IconLocation = "$spotifyExe,0" }
            $marketShortcut.Description = "Measure Marketplace and Marketplace-managed extension overhead without editing Marketplace data"
            $marketShortcut.Save()
        }

        $marketResultsCmd = Join-Path $installedBin "show-marketplace-isolation.cmd"
        if (Test-UsablePath -Path $marketResultsCmd -PathType "Leaf") {
            $marketResultsShortcut = $shell.CreateShortcut((Join-Path $startMenu "Spotify Control Marketplace Isolation Results.lnk"))
            $marketResultsShortcut.TargetPath = $marketResultsCmd
            $marketResultsShortcut.WorkingDirectory = $installedBin
            if (Test-UsablePath -Path $spotifyExe -PathType "Leaf") { $marketResultsShortcut.IconLocation = "$spotifyExe,0" }
            $marketResultsShortcut.Description = "Show the latest Marketplace isolation benchmark"
            $marketResultsShortcut.Save()
        }
    }

    Write-Log "Installed/updated Spotify Control shortcuts and maintenance entry."
    Write-Host ""
    Write-Host "Installed Spotify Control v$ScriptVersion." -ForegroundColor Green
    Write-Host "Managed Spotify now launches with no console window." -ForegroundColor Cyan
}

function Invoke-MaintenanceCheckPhase {
    param($State)

    $State = Ensure-StateShape $State
    $running = Test-SpotifyRunning
    $now = [DateTimeOffset]::UtcNow.ToString("o")
    $errors = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $reasons = New-Object System.Collections.Generic.List[string]

    $selfUpdate = $null
    if (Test-DueHours -Value $State.last_self_update_check -Hours $SelfUpdateCheckIntervalHours) {
        $selfUpdate = Get-SelfUpdateCheckResult
        $State.last_self_update_check = $now
        if (-not $selfUpdate.Verified) {
            if ($selfUpdate.TrustedStableBehindPrivate -eq $true) {
                # No self-update is permitted. Independent Spicetify/addon
                # checks still have to pass their existing fail-closed guards.
                $warnings.Add("Pinned private v0.6.30 is newer than authenticated public stable v0.6.28; self-update disabled.")
            } else {
                $errors.Add("Spotify Control self-update discovery: $($selfUpdate.Error)")
            }
        }
    } else {
        $selfUpdate = [pscustomobject]@{
            Verified=(-not [string]::IsNullOrWhiteSpace([string]$State.self_update_latest_version))
            TrustedStableBehindPrivate=$false
            UpdateAvailable=[bool]$State.pending_self_update
            InstalledVersion=$ScriptVersion
            LatestVersion=[string]$State.self_update_latest_version
            BootstrapVersion=[string]$State.self_update_bootstrap_version
            SourceCommit=[string]$State.self_update_source_commit
            PayloadSetSha256=[string]$State.self_update_payload_set_sha256
            TransactionId=[string]$State.self_update_last_transaction_id
            TransactionStatus=[string]$State.self_update_last_transaction_status
            Error=$null
        }
    }

    $spotifyExe = Get-SpotifyExecutable
    $spotifyVersion = Get-SpotifyVersion -Exe $spotifyExe
    $installedSpicetify = Get-InstalledSpicetifyVersion
    $spicetifyInstall = Get-SpicetifyManagedInstallInfo
    $spicetifyLatest = Get-SpicetifyLatestReleaseInfo
    $guardPlan = Get-SmartUpdateGuardPlan -SpotifyVersionOverride $spotifyVersion

    if (-not $spicetifyInstall.Managed) {
        $errors.Add("Spicetify install is not the official LOCALAPPDATA layout; auto-update disabled: $($spicetifyInstall.Path)")
    }
    if (-not $spicetifyLatest.Verified) {
        $errors.Add("Spicetify latest release discovery: $($spicetifyLatest.Error)")
    }
    if (-not $guardPlan.CompatibilityVerified) {
        $errors.Add("Installed Spicetify compatibility metadata: $($guardPlan.CompatibilityError)")
    }

    $spicetifyUpgradePending = $false
    if ($spicetifyLatest.Verified -and -not [string]::IsNullOrWhiteSpace($installedSpicetify)) {
        $cmpSpice = Compare-VersionParts -A ([string]$spicetifyLatest.Version) -B $installedSpicetify -Count 3
        if ($null -eq $cmpSpice) {
            $errors.Add("Could not compare installed Spicetify $installedSpicetify with latest $($spicetifyLatest.Version).")
        } elseif ($cmpSpice -gt 0) {
            $spicetifyUpgradePending = $true
        } elseif ($cmpSpice -lt 0) {
            $warnings.Add("Installed Spicetify $installedSpicetify is newer than GitHub latest $($spicetifyLatest.Version); automatic downgrade is disabled.")
        }
    }

    $marketInfo = $null
    if (Test-Due -Value $State.last_marketplace_discovery_check -Days 1) {
        $marketInfo = Get-MarketplaceLatestReleaseInfo
        $State.last_marketplace_discovery_check = $now
        if ($marketInfo.Verified) {
            $State.pending_marketplace_tag = $marketInfo.Tag
            $State.pending_marketplace_digest = $marketInfo.AssetDigest
        } elseif ($marketInfo.Error) {
            $errors.Add("Marketplace discovery: $($marketInfo.Error)")
        }
    } else {
        $marketInfo = [pscustomobject]@{
            Verified = (-not [string]::IsNullOrWhiteSpace([string]$State.pending_marketplace_tag))
            Tag = $State.pending_marketplace_tag
            AssetDigest = $State.pending_marketplace_digest
            Error = $null
        }
    }

    $marketplacePending = $false
    if ($marketInfo.Verified -and -not [string]::IsNullOrWhiteSpace([string]$marketInfo.Tag)) {
        $known = Normalize-MarketplaceTag ([string]$State.marketplace_remote_tag)
        $candidateTag = Normalize-MarketplaceTag ([string]$marketInfo.Tag)
        if ([string]::IsNullOrWhiteSpace($known) -or $known -ne $candidateTag) { $marketplacePending = $true }
    }

    $addonCheck = Invoke-AddonManager -AddonAction "Check" -ForceAddon:$Force
    if ($addonCheck.ExitCode -notin @(0,127)) {
        $errors.Add("Addon check exit code $($addonCheck.ExitCode).")
    }
    $addonSummary = Get-AddonPendingSummary
    if ($addonSummary.Error) { $errors.Add("Addon report: $($addonSummary.Error)") }
    if ($addonSummary.CheckErrorCount -gt 0) { $errors.Add("Addon sources with check errors: $($addonSummary.CheckErrorCount).") }
    if ($addonSummary.BlockedAutoCount -gt 0) { $errors.Add("Auto-managed addons blocked by local-integrity safety: $($addonSummary.BlockedAutoCount).") }
    if ($addonSummary.AutoAmbiguousCount -gt 0) { $errors.Add("Ambiguous auto-managed addon installations: $($addonSummary.AutoAmbiguousCount).") }
    if ($addonSummary.NonAutoAmbiguousCount -gt 0) { $warnings.Add("Ambiguous monitor-only/unknown addon installations: $($addonSummary.NonAutoAmbiguousCount). Auto-mutation is unaffected, but those items remain untouched.") }
    if ($addonSummary.DirectExtensionBlockedCount -gt 0) { $warnings.Add("Spicetify-owned direct extensions have local/ambiguous drift and will not be overwritten automatically: $($addonSummary.DirectExtensionBlockedCount).") }
    if ($addonSummary.DirectExtensionUnknownCount -gt 0) { $warnings.Add("Unknown-source direct extensions remain warning-only and untouched: $($addonSummary.DirectExtensionUnknownCount).") }

    $spicetifyRepairPending = ($addonSummary.DirectExtensionRepairCount -gt 0)
    $spotifyUpdatePending = [bool]$guardPlan.UpdateWindow
    if ($selfUpdate.Verified -and $selfUpdate.UpdateAvailable) { $reasons.Add("spotify-control-self-update:$($selfUpdate.LatestVersion)") }
    if ($spicetifyUpgradePending) { $reasons.Add("spicetify-cli-update") }
    if ($spicetifyRepairPending) { $reasons.Add("spicetify-official-extension-repair:$($addonSummary.DirectExtensionRepairCount)") }
    if ($spotifyUpdatePending) { $reasons.Add("spotify-update") }
    if ($marketplacePending) { $reasons.Add("marketplace-update") }
    if ($addonSummary.AutoUpdateCount -gt 0) { $reasons.Add("addon-updates:$($addonSummary.AutoUpdateCount)") }
    if ($guardPlan.CurrentSupported -eq $false) { $reasons.Add("compatibility-repair") }
    if (-not [string]::IsNullOrWhiteSpace($spotifyVersion) -and -not [string]::IsNullOrWhiteSpace([string]$State.last_spotify_version) -and $spotifyVersion -ne $State.last_spotify_version) {
        $reasons.Add("spotify-version-change")
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$guardPlan.Desired) -and $State.guard_enforced -ne $guardPlan.Desired) {
        $reasons.Add("guard-state-change:$($guardPlan.Desired)")
    }

    $State.last_check_only_utc = $now
    $State.last_check_only_while_running = $running
    $State.maintenance_check_healthy = ($errors.Count -eq 0)
    $State.pending_maintenance = ($reasons.Count -gt 0)
    $State.pending_reasons = @($reasons.ToArray())
    $State.pending_spicetify_upgrade = $spicetifyUpgradePending
    $State.pending_spicetify_repair = $spicetifyRepairPending
    $State.pending_direct_extension_repair_count = [int]$addonSummary.DirectExtensionRepairCount
    $State.pending_direct_extension_blocked_count = [int]$addonSummary.DirectExtensionBlockedCount
    $State.pending_direct_extension_unknown_count = [int]$addonSummary.DirectExtensionUnknownCount
    $State.pending_spotify_update = $spotifyUpdatePending
    $State.pending_marketplace_update = $marketplacePending
    $State.pending_addon_updates = [int]$addonSummary.AutoUpdateCount
    $State.pending_addon_auto_ambiguous = [int]$addonSummary.AutoAmbiguousCount
    $State.pending_addon_nonauto_ambiguous = [int]$addonSummary.NonAutoAmbiguousCount
    $State.pending_guard_desired = $guardPlan.Desired
    $State.pending_guard_reason = $guardPlan.Reason
    $State.current_spotify_supported = $guardPlan.CurrentSupported
    $State.spicetify_installed_version = $installedSpicetify
    $State.spicetify_install_mode = $spicetifyInstall.Mode
    $State.spicetify_compat_tag = $guardPlan.SpicetifyTag
    $State.spicetify_compat_min_windows = $guardPlan.MinSupported
    $State.spicetify_max_windows = $guardPlan.MaxSupported
    if ($spicetifyLatest.Verified) {
        $State.spicetify_latest_tag = $spicetifyLatest.Tag
        $State.pending_spicetify_tag = $spicetifyLatest.Tag
        $State.pending_spicetify_digest = $spicetifyLatest.AssetDigest
    }
    $State.spotify_candidate_version = $guardPlan.CandidateVersion
    $State.spotify_candidate_fullversion = $guardPlan.CandidateFullVersion
    $State.spotify_candidate_etag = $guardPlan.CandidateEtag
    $State.spotify_candidate_sha256 = $guardPlan.CandidateSha256
    $State.spotify_candidate_size = $guardPlan.CandidateSize
    if ($selfUpdate.Verified) {
        $State.self_update_bootstrap_version = $selfUpdate.BootstrapVersion
        $State.self_update_latest_version = $selfUpdate.LatestVersion
        $State.self_update_source_commit = $selfUpdate.SourceCommit
        $State.self_update_payload_set_sha256 = $selfUpdate.PayloadSetSha256
        $State.pending_self_update = [bool]$selfUpdate.UpdateAvailable
    }
    Save-State $State

    $report = [pscustomobject]@{
        generated_at = (Get-Date).ToString("o")
        version = $ScriptVersion
        phase = "check-only"
        spotify_running = $running
        mutations_performed = $false
        mutation_phase_allowed = (-not $running)
        healthy = ($errors.Count -eq 0)
        self_update = [pscustomobject]@{
            verified=$selfUpdate.Verified
            bootstrap_version=$selfUpdate.BootstrapVersion
            installed_version=$selfUpdate.InstalledVersion
            latest_version=$selfUpdate.LatestVersion
            update_available=$selfUpdate.UpdateAvailable
            source_commit=$selfUpdate.SourceCommit
            payload_set_sha256=$selfUpdate.PayloadSetSha256
            error=$selfUpdate.Error
        }
        spotify = [pscustomobject]@{ version=$spotifyVersion; executable=$spotifyExe }
        spicetify = [pscustomobject]@{
            installed_version=$installedSpicetify
            install_mode=$spicetifyInstall.Mode
            installed_compat_tag=$guardPlan.SpicetifyTag
            windows_min=$guardPlan.MinSupported
            windows_max=$guardPlan.MaxSupported
            latest_tag=$(if($spicetifyLatest.Verified){$spicetifyLatest.Tag}else{$null})
            latest_digest=$(if($spicetifyLatest.Verified){$spicetifyLatest.AssetDigest}else{$null})
            upgrade_pending=$spicetifyUpgradePending
        }
        marketplace = [pscustomobject]@{
            installed_tag=$State.marketplace_remote_tag
            candidate_tag=$marketInfo.Tag
            candidate_verified=$marketInfo.Verified
            update_pending=$marketplacePending
        }
        addons = [pscustomobject]@{
            check_exit_code=$addonCheck.ExitCode
            auto_update_count=$addonSummary.AutoUpdateCount
            check_error_count=$addonSummary.CheckErrorCount
            blocked_auto_count=$addonSummary.BlockedAutoCount
            blocked_auto_items=@($addonSummary.BlockedAutoItems)
            ambiguous_count=$addonSummary.AmbiguousCount
            auto_ambiguous_count=$addonSummary.AutoAmbiguousCount
            nonauto_ambiguous_count=$addonSummary.NonAutoAmbiguousCount
            ambiguous_items=@($addonSummary.AmbiguousItems)
            direct_extension_repair_count=$addonSummary.DirectExtensionRepairCount
            direct_extension_blocked_count=$addonSummary.DirectExtensionBlockedCount
            direct_extension_unknown_count=$addonSummary.DirectExtensionUnknownCount
            direct_extension_rescue_count=$addonSummary.DirectExtensionRescueCount
            direct_extension_repair_items=@($addonSummary.DirectExtensionRepairItems)
            direct_extension_blocked_items=@($addonSummary.DirectExtensionBlockedItems)
            direct_extension_unknown_items=@($addonSummary.DirectExtensionUnknownItems)
            report_path=$addonSummary.ReportPath
        }
        guard_plan = [pscustomobject]@{
            desired=$guardPlan.Desired
            reason=$guardPlan.Reason
            current_supported=$guardPlan.CurrentSupported
            candidate_verified=$guardPlan.CandidateVerified
            candidate_version=$guardPlan.CandidateVersion
            candidate_sha256=$guardPlan.CandidateSha256
            candidate_size=$guardPlan.CandidateSize
            update_window=$guardPlan.UpdateWindow
        }
        pending = ($reasons.Count -gt 0)
        pending_reasons = @($reasons.ToArray())
        warnings = @($warnings.ToArray())
        errors = @($errors.ToArray())
    }
    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $MaintenanceCheckReport -Encoding UTF8

    $level = if ($errors.Count -eq 0) { "INFO" } else { "WARN" }
    Write-Log ("Maintenance check-only phase complete: spotify_running={0}; pending={1}; reasons={2}; warnings={3}; errors={4}; report={5}" -f `
        $running,
        ($reasons.Count -gt 0),
        $(if($reasons.Count){$reasons.ToArray() -join ','}else{'none'}),
        $warnings.Count,
        $errors.Count,
        $MaintenanceCheckReport
    ) $level

    return [pscustomobject]@{
        State = $State
        GuardPlan = $guardPlan
        Report = $report
    }
}

function Invoke-MaintenanceMutationPhase {
    param($State, $GuardPlan = $null)

    $State = Ensure-StateShape $State
    if(Test-R134OwnerReconciledMutationHold){
        Write-Log 'R134 owner-reviewed baseline is observation-only until a separate owner upgrade approval.' 'WARN'
        return $State
    }
    if (Test-SpotifyRunning) {
        Write-Log "Spotify became active before the mutation phase. All Spotify/Spicetify mutations are deferred." "WARN"
        return $State
    }

    if ([bool]$State.pending_self_update) {
        try {
            $su = Invoke-SelfUpdateMutation -SelfAction "Update"
            $State = Ensure-StateShape (Load-State)
            $State.pending_self_update = $false
            $State.self_update_last_transaction_id = [string]$su.transaction_id
            $State.self_update_last_transaction_status = [string]$su.transaction_status
            $State.self_update_last_transaction_utc = [DateTimeOffset]::UtcNow.ToString("o")
            Save-State $State
            Write-Log "Spotify Control self-update committed. Ending this maintenance pass so the next invocation runs the new code."
            return $State
        } catch {
            Write-Log ("Spotify Control self-update failed safely: " + $_.Exception.Message) "ERROR"
            $State.self_update_last_transaction_status = "failed"
            $State.self_update_last_transaction_utc = [DateTimeOffset]::UtcNow.ToString("o")
            $script:MaintenanceHealthy = $false
            Save-State $State
            return $State
        }
    }

    Backup-Config

    $backupResult = Invoke-AddonManager -AddonAction "Backup"
    if ($backupResult.ExitCode -ne 0 -and $backupResult.ExitCode -ne 127) {
        Write-Log "Addon/WebView backup failed; addon mutation will be skipped this run." "WARN"
    }

    if (Test-SpotifyRunning) {
        Write-Log "Spotify started after backup. Stopping before any update mutation." "WARN"
        return $State
    }

    [void](Repair-PendingSpicetifyTransaction)
    try {
        $backupMetadataRepair=Repair-SpicetifyBackupMetadataIfTrusted
    } catch {
        Write-Log ("Spicetify Backup metadata repair failed safely: "+$_.Exception.Message) 'ERROR'
        $script:MaintenanceHealthy=$false
        Save-State $State
        return $State
    }
    if([string]$backupMetadataRepair.Status -eq 'blocked-unproven'){
        Write-Log ("Spicetify Backup metadata mismatch remains fail-closed; apply-dependent maintenance is deferred: "+[string]$backupMetadataRepair.Reason) 'WARN'
        $script:MaintenanceHealthy=$false
        Save-State $State
        return $State
    }
    if([string]$backupMetadataRepair.Status -eq 'repaired'){
        Write-Log ("Spicetify Backup metadata provenance repair completed before apply-dependent maintenance. transaction="+[string]$backupMetadataRepair.TransactionId)
    }
    $guard = $null
    $guardHandledBySpicetifyTransaction = $false
    $upgradeDue = (Test-Due -Value $State.last_spicetify_upgrade_check -Days 1)
    $forceOwnedExtensionRepair = [bool]$State.pending_spicetify_repair -and -not [bool]$State.pending_spicetify_upgrade
    if ($State.pending_spicetify_upgrade -or $State.pending_spicetify_repair -or $upgradeDue) {
        try {
            $spiceTxn = Invoke-SpicetifyTransactionalMaintenance -State $State -ForceReinstall:$forceOwnedExtensionRepair
            $State = Ensure-StateShape $spiceTxn.State
            if (-not $spiceTxn.Success) {
                Write-Log "Transactional Spicetify maintenance failed safely with status=$($spiceTxn.Status); remaining mutations are deferred." "WARN"
                $script:MaintenanceHealthy = $false
                Save-State $State
                return $State
            }
            if ($spiceTxn.Changed -and $spiceTxn.Status -eq 'committed') {
                if ($State.pending_spicetify_repair) {
                    $State.pending_spicetify_repair = $false
                    $State.pending_direct_extension_repair_count = 0
                    Save-State $State
                }
                $guard = $spiceTxn.GuardResult
                $GuardPlan = $spiceTxn.GuardPlan
                $guardHandledBySpicetifyTransaction = $true
            } else {
                $GuardPlan = Get-SmartUpdateGuardPlan
            }
        } catch {
            Write-Log ("Transactional Spicetify maintenance aborted fail-closed: " + $_.Exception.Message) "ERROR"
            $State.pending_spicetify_upgrade = $true
            $script:MaintenanceHealthy = $false
            Save-State $State
            return $State
        }
    } else {
        Write-Log "Spicetify update/owned-extension repair check is not due and no pending repair was discovered."
    }

    if (Test-SpotifyRunning) {
        Write-Log "Spotify started after Spicetify CLI maintenance. Remaining mutation is deferred." "WARN"
        return $State
    }

    if (-not $guardHandledBySpicetifyTransaction) {
        $guard = Invoke-SmartUpdateGuard -State $State -Plan $GuardPlan
        $State = Ensure-StateShape $guard.State
        Save-State $State
    }

    if ($guard.CurrentSupported -ne $true) {
        Write-Log "Current Spotify is not verified as Spicetify-compatible. Marketplace/apply/CustomApp mutation are deferred." "WARN"
        $spotifyExe = Get-SpotifyExecutable
        $spotifyVersion = Get-SpotifyVersion -Exe $spotifyExe
        if ($spotifyVersion) { $State.last_spotify_version = $spotifyVersion }
        $State.pending_auto_repair = $true
        Save-State $State
        return $State
    }

    if (Test-SpotifyRunning) {
        Write-Log "Spotify started after guard enforcement. Remaining customization mutation is deferred." "WARN"
        return $State
    }

    if ($State.pending_spotify_update -or [bool]$GuardPlan.UpdateWindow) {
        try {
            $spotifyTxn = Invoke-SpotifyTransactionalMaintenance -State $State
            $State = Ensure-StateShape $spotifyTxn.State
            if (-not $spotifyTxn.Success) {
                Write-Log "Transactional Spotify update failed safely with status=$($spotifyTxn.Status); remaining mutations are deferred." "WARN"
                $script:MaintenanceHealthy = $false
                Save-State $State
                return $State
            }
            $GuardPlan = Get-SmartUpdateGuardPlan
            $guard = Invoke-SmartUpdateGuard -State $State -Plan $GuardPlan
            $State = Ensure-StateShape $guard.State
            Save-State $State
            if (-not $guard.Success -or $guard.CurrentSupported -ne $true -or [string]$guard.Enforced -ne 'blocked') {
                throw 'Post-Spotify-transaction compatibility/guard verification failed.'
            }
        } catch {
            Write-Log ("Transactional Spotify maintenance aborted fail-closed: " + $_.Exception.Message) "ERROR"
            $State.pending_spotify_update = $true
            $script:MaintenanceHealthy = $false
            Save-State $State
            return $State
        }
    }

    $configChangedByUs = Set-SafePreprocessDefaults

    $marketChanged = $false
    if ($State.pending_marketplace_update -or (Test-Due -Value $State.last_marketplace_check -Days 7)) {
        if (Test-SpotifyRunning) {
            Write-Log "Spotify started before Marketplace mutation. Marketplace update deferred." "WARN"
            return $State
        }
        $m = Update-Marketplace -State $State
        $State = Ensure-StateShape $m.State
        $marketChanged = ([bool]$m.Changed -and -not [bool]$m.ApplyCompleted)
        if ($m.Changed -and $m.Status -eq "committed") { $State.pending_marketplace_update = $false }
        if ($m.Status -notin @("committed","already-current")) {
            $State.pending_marketplace_update = $true
            $script:MaintenanceHealthy = $false
            Save-State $State
            Write-Log "Marketplace transaction did not commit (status=$($m.Status)); remaining CustomApp mutation is deferred fail-closed." "WARN"
            return $State
        }
        Save-State $State
    } else {
        Write-Log "Marketplace update check is not due and no pending release was discovered."
    }

    $addonChanged = $false
    if ($backupResult.ExitCode -eq 0) {
        if (Test-SpotifyRunning) {
            Write-Log "Spotify started before CustomApp mutation. Addon update deferred." "WARN"
            return $State
        }
        $addonResult = Invoke-AddonManager -AddonAction "Update"
        if ($addonResult.ExitCode -eq 10) {
            $addonChanged = $true
            Write-Log "Allowlisted CustomApps changed; one Spicetify apply will validate the transaction."
        } elseif ($addonResult.ExitCode -ne 0) {
            Write-Log "Addon Manager update failed; existing apps/backups were preserved and this maintenance cycle is fail-closed." "WARN"
            $script:MaintenanceHealthy = $false
        }
    } else {
        Write-Log "Skipping addon update because the pre-update data backup was not successful." "WARN"
    }

    $spotifyExe = Get-SpotifyExecutable
    $spotifyVersion = Get-SpotifyVersion -Exe $spotifyExe
    $configPath = Get-ConfigPath
    $configHash = Get-FileSha256 -Path $configPath

    $spotifyChanged = (
        $spotifyVersion -and
        $State.last_spotify_version -and
        $spotifyVersion -ne $State.last_spotify_version
    )

    if ($spotifyChanged) {
        Write-Log "Spotify version changed from $($State.last_spotify_version) to $spotifyVersion. Repair is delegated to 'spicetify auto'."
        $State.pending_auto_repair = $true
    }

    if ($marketChanged -or $configChangedByUs -or $addonChanged) {
        if (Test-SpotifyRunning) {
            Write-Log "Spotify started before Spicetify apply. Apply is deferred; pending repair remains set." "WARN"
            $State.pending_auto_repair = $true
            $script:MaintenanceHealthy = $false
        } else {
            Write-Log "Customization files/settings changed while Spotify is closed. Running one apply."
            $r = Invoke-Spice -Arguments @("apply","--no-restart") -AllowFailure

            if ($r.ExitCode -ne 0) {
                if ($addonChanged) {
                    Write-Log "Apply failed after transactional CustomApp changes. Rolling back all changed apps before any retry." "WARN"
                    $rollback = Invoke-AddonManager -AddonAction "RollbackLast"
                    if ($rollback.ExitCode -eq 0) {
                        $retry = Invoke-Spice -Arguments @("apply","--no-restart") -AllowFailure
                        if ($retry.ExitCode -eq 0) {
                            Write-Log "Apply succeeded after fully verified addon rollback. CustomApp transaction was safely reverted." "WARN"
                            $addonChanged = $false
                        } else {
                            Write-Log "Apply still failed after verified addon rollback. No vanilla restore/delete was performed." "WARN"
                            $State.pending_auto_repair = $true
                            $script:MaintenanceHealthy = $false
                        }
                    } else {
                        Write-Log "Addon rollback itself failed; refusing to apply a potentially mixed filesystem state." "ERROR"
                        $State.pending_auto_repair = $true
                        $script:MaintenanceHealthy = $false
                    }
                } else {
                    Write-Log "Spicetify apply returned exit code $($r.ExitCode). No restore/delete was performed." "WARN"
                    $State.pending_auto_repair = $true
                    $script:MaintenanceHealthy = $false
                }
            } else {
                if ($addonChanged) {
                    $commit = Invoke-AddonManager -AddonAction "CommitLast"
                    if ($commit.ExitCode -ne 0) {
                        Write-Log "CustomApp commit verification failed after apply. Rolling back the whole transaction and restoring the previous applied state." "ERROR"
                        $rollback = Invoke-AddonManager -AddonAction "RollbackLast"
                        if ($rollback.ExitCode -eq 0) {
                            $retry = Invoke-Spice -Arguments @("apply","--no-restart") -AllowFailure
                            if ($retry.ExitCode -eq 0) {
                                Write-Log "Commit failure recovered: previous CustomApps restored and reapplied." "WARN"
                                $addonChanged = $false
                            } else {
                                Write-Log "Rollback succeeded after commit failure, but reapply failed." "ERROR"
                                $State.pending_auto_repair = $true
                                $script:MaintenanceHealthy = $false
                            }
                        } else {
                            Write-Log "Commit and rollback both failed; transaction ledger is retained for fail-closed recovery." "ERROR"
                            $State.pending_auto_repair = $true
                            $script:MaintenanceHealthy = $false
                        }
                    }
                }
            }
        }
    } else {
        Write-Log "No customization change requiring apply."
    }

    if ($spotifyVersion) { $State.last_spotify_version = $spotifyVersion }
    if ($configHash) { $State.last_config_hash = $configHash }
    if ($script:MaintenanceHealthy) {
        $State.last_success_utc = [DateTimeOffset]::UtcNow.ToString("o")
    }
    Save-State $State
    return $State
}

function Invoke-ResidentAgentTick {
    param([string]$EventName)

    $lease = Enter-SpotifyControlMutex -Purpose "AgentTick"
    if ($null -eq $lease) {
        Write-Log "Resident-agent tick skipped because another tick is already active."
        return
    }

    $maintenanceLease = $null
    try {
    # Cross-process manual Maintain must serialize with resident DISCOVERY,
    # not just the later mutation. Nonblocking avoids delaying Spotify.
    $maintenanceLease = Enter-SpotifyControlMutex -Purpose "Maintenance"
    if ($null -eq $maintenanceLease) {
        Write-Log "Resident tick deferred: another Maintenance owner holds the exclusive lease."
        return
    }
    $State = Ensure-StateShape (Load-State)
    $State = Migrate-StateFromLog $State
    $running = Test-SpotifyRunning
    $checkDue = Test-DueHours -Value $State.last_check_only_utc -Hours $AgentDiscoveryIntervalHours
    $decision = "noop"
    $checkRan = $false
    $freshCheck = $null
    $mutationRan = $false

        # Trigger a fresh read-only check when Spotify actually closes.
    # Without this, an update immediately after a 12-hour scan could
    # leave a missing Spicetify patch unnoticed until the next scan.
    $exitRefreshDone = $false
    if (-not $running -and $EventName -ceq "SpotifyExit") {
        $freshCheck = Invoke-MaintenanceCheckPhase -State $State
        $State = Ensure-StateShape (Load-State)
        $checkRan = $true
        $exitRefreshDone = $true
    }
    # Recover from stale unhealthy/ambiguous discovery while closed.
    # Keep the existing 12-hour cadence; do not make unchecked network
    # requests on every resident tick after a failed or partial check.
    # This ONLY performs discovery/state bookkeeping; the existing
    # armed/healthy/unambiguous gate below still owns all mutations.
    if (-not $running -and -not $exitRefreshDone -and $checkDue -and
        [bool]$State.pending_maintenance -and
        ($State.maintenance_check_healthy -eq $false -or
         [int]$State.pending_addon_auto_ambiguous -gt 0)) {
        # Persist retry admission BEFORE remote checks. If discovery
        # throws early, subsequent ticks cannot hammer free endpoints.
        $State.last_check_only_utc = [DateTimeOffset]::UtcNow.ToString("o")
        Save-State (Ensure-StateShape $State)
        $freshCheck = Invoke-MaintenanceCheckPhase -State $State
        $State = Ensure-StateShape (Load-State)
        $checkRan = $true
        $exitRefreshDone = $true
    }
    if ($running) {
        if ($checkDue) {
            $freshCheck = Invoke-MaintenanceCheckPhase -State $State
            $State = Ensure-StateShape (Load-State)
            $checkRan = $true
            $decision = "check-only-running"
            try {
                $warmStatus=Invoke-R138PlaybackWarm -Discovery $freshCheck
                Write-Log ('R138 playback-safe warm: '+$warmStatus)
            } catch {
                Write-Log ('R138 warm held: '+$_.Exception.GetType().Name) 'WARN'
            }
        } else {
            $decision = "running-check-not-due"
        }
    } else {
        if ([bool]$State.agent_mutation_enabled -and [bool]$State.pending_maintenance -and ([int]$State.pending_addon_auto_ambiguous -gt 0 -or $State.maintenance_check_healthy -eq $false)) {
            $decision = "mutation-blocked-unhealthy-or-auto-ambiguous"
        } elseif ([bool]$State.agent_mutation_enabled -and [bool]$State.pending_maintenance) {
            $script:LastResidentMutationPhaseEntered = $false
            Maintain -FromResidentAgent -VerifiedAgentCheck $freshCheck
            $State = Ensure-StateShape (Load-State)
            $mutationRan = [bool]$script:LastResidentMutationPhaseEntered
            $checkRan = $checkRan -or [bool]$script:LastResidentDiscoveryRan
            $decision = $(if($mutationRan){"maintenance-phase-entered"}else{"maintenance-deferred-or-lease-busy"})
        } elseif ($checkDue -and -not $exitRefreshDone) {
            $freshCheck = Invoke-MaintenanceCheckPhase -State $State
            $State = Ensure-StateShape (Load-State)
            $checkRan = $true
            $decision = $(if([bool]$State.agent_mutation_enabled){"check-only-closed-no-pending"}else{"observe-only-closed"})
        } elseif ([bool]$State.pending_maintenance -and -not [bool]$State.agent_mutation_enabled) {
            $decision = "pending-observed-mutation-disarmed"
        } else {
            $decision = "closed-check-not-due"
        }
    }

    $State.last_agent_tick_utc = [DateTimeOffset]::UtcNow.ToString("o")
    $State.last_agent_event = $EventName
    $State.last_agent_decision = $decision
    $State.agent_version = "0.1.1"
    Save-State $State

    $report = [pscustomobject]@{
        generated_at=(Get-Date).ToString("o")
        spotify_control_version=$ScriptVersion
        agent_version="0.1.1"
        event=$EventName
        spotify_running=$running
        discovery_interval_hours=$AgentDiscoveryIntervalHours
        check_due=$checkDue
        check_ran=$checkRan
        mutation_enabled=[bool]$State.agent_mutation_enabled
        mutation_ran=$mutationRan
        pending_maintenance=[bool]$State.pending_maintenance
        pending_reasons=@($State.pending_reasons)
        auto_ambiguous=[int]$State.pending_addon_auto_ambiguous
        nonauto_ambiguous=[int]$State.pending_addon_nonauto_ambiguous
        decision=$decision
    }
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $AgentReport -Encoding UTF8
    Write-Log ("Resident-agent tick: event={0}; spotify_running={1}; decision={2}; pending={3}; mutation_enabled={4}" -f `
        $EventName,$running,$decision,[bool]$State.pending_maintenance,[bool]$State.agent_mutation_enabled)
    } finally {
        Exit-SpotifyControlMutex -Mutex $maintenanceLease
        Exit-SpotifyControlMutex -Mutex $lease
    }
}

function Maintain {
    param([switch]$FromResidentAgent, $VerifiedAgentCheck = $null)
    # This flag records *admission* to the real mutation phase, not whether
    # an update actually changed files or committed. Both are distinct.
    $script:LastResidentMutationPhaseEntered = $false
    $script:LastResidentDiscoveryRan = $false
    $lease = Enter-SpotifyControlMutex -Purpose "Maintenance"
    if ($null -eq $lease) {
        Write-Log "Maintenance skipped because another maintenance/check operation is already active." "WARN"
        return
    }

    try {
    $script:MaintenanceHealthy = $true
    $script:LastGuardResult = $null

    if (-not $script:Spicetify) {
        Write-Log "Spicetify is not installed or not on PATH. Maintenance skipped." "WARN"
        return
    }

    $State = Ensure-StateShape (Load-State)
    if(Test-R134OwnerReconciledMutationHold){
        Write-Log 'R134 owner-reviewed baseline: resident and manual maintenance mutation held until separate owner approval.' 'WARN'
        return
    }
    $State = Migrate-StateFromLog $State
    # A concurrent owner disarm or another state/health invalidation
    # between AgentTick discovery and the Maintenance mutex must not cause
    # even a second network check, much less an automatic mutation.
    if ($FromResidentAgent -and
        (-not [bool]$State.agent_mutation_enabled -or
         -not [bool]$State.pending_maintenance -or
         $State.maintenance_check_healthy -ne $true -or
         [int]$State.pending_addon_auto_ambiguous -gt 0)) {
        Write-Log "Resident maintenance deferred at mutex: owner disarmed or discovery not healthy." "WARN"
        return
    }
    Save-State $State

    # Independent manual/Launch calls always discover as before. The agent
    # can reuse only the result of its own most recent check. Any mismatch
    # forces a fresh discovery instead of trusting stale network metadata.
    $check = $null
    if ($FromResidentAgent -and $null -ne $VerifiedAgentCheck) {
        $receipt = $VerifiedAgentCheck.Report
        $snapshot = $VerifiedAgentCheck.State
        if ($null -ne $receipt -and $null -ne $snapshot -and
            [string]$receipt.phase -ceq "check-only" -and
            [bool]$receipt.healthy -and
            [bool]$State.agent_mutation_enabled -and
            [bool]$State.pending_maintenance -and
            $State.maintenance_check_healthy -eq $true -and
            [int]$State.pending_addon_auto_ambiguous -eq 0 -and
            [string]$State.last_check_only_utc -ceq [string]$snapshot.last_check_only_utc -and
            $null -ne $VerifiedAgentCheck.GuardPlan) {
            $check = $VerifiedAgentCheck
            Write-Log "Resident agent reused its completed read-only discovery (no duplicate network scan)."
        }
    }
    if ($null -eq $check) {
        $check = Invoke-MaintenanceCheckPhase -State $State
        if ($FromResidentAgent) { $script:LastResidentDiscoveryRan = $true }
    }
    $State = Ensure-StateShape $check.State

    # Recheck the current persisted owner approval and health after obtaining
    # the existing Maintenance mutex, even if they were valid in AgentTick.
    # Manual Maintain/Launch retain their independently authorized behavior.
    if ($FromResidentAgent) {
        $latest = Ensure-StateShape (Load-State)
        if (-not [bool]$latest.agent_mutation_enabled -or
            -not [bool]$latest.pending_maintenance -or
            $latest.maintenance_check_healthy -ne $true -or
            [int]$latest.pending_addon_auto_ambiguous -gt 0 -or
            [string]$latest.last_check_only_utc -cne [string]$State.last_check_only_utc) {
            Write-Log "Resident maintenance deferred: approval, fresh check or health changed under mutex." "WARN"
            return
        }
    }

    $mode = Get-MaintenanceMode -SpotifyRunning (Test-SpotifyRunning)
    if ($mode -eq "check-only") {
        Write-Log "Spotify is running. Update discovery completed; all target mutation is deferred until a closed window."
        return
    }

    # A lease failure or user revocation must never be reported as a
    # mutation execution. This flag is set immediately before phase entry.
    $script:LastResidentMutationPhaseEntered = $true
    [void](Invoke-MaintenanceMutationPhase -State $State -GuardPlan $check.GuardPlan)
    } finally {
        Exit-SpotifyControlMutex -Mutex $lease
    }
}

function Launch-ManagedSpotify {
    $spotifyExe = Get-SpotifyExecutable

    if (Test-SpotifyRunning) {
        Write-Log "Spotify is already running. Leaving the active session untouched."
        if ($spotifyExe) {
            Start-Process -FilePath $spotifyExe
        }
        Start-PerformanceSnapshotAsync
        return
    }

    Maintain

    $guard = $script:LastGuardResult
    # Launch remains usable, but no unapproved "spicetify auto" may rewrite
    # Spotify Apps while an owner-reconciled or attempted update is held.
    if(Test-R134OwnerReconciledMutationHold){
        $guard=$null
        Write-Log 'R136 owner review active: launching ordinary Spotify without spicetify auto.' 'WARN'
    }

    if ($guard -and $guard.CurrentSupported -eq $true -and $script:Spicetify) {
        Write-Log "Current Spotify is inside the verified Spicetify compatibility range. Launching via 'spicetify auto'."
        $r = Invoke-Spice -Arguments @("auto") -AllowFailure

        if ($r.ExitCode -eq 0) {
            $state = Ensure-StateShape (Load-State)
            $state.pending_auto_repair = $false
            $state.last_success_utc = [DateTimeOffset]::UtcNow.ToString("o")
            $freshExe = Get-SpotifyExecutable
            $freshVersion = Get-SpotifyVersion -Exe $freshExe
            if ($freshVersion) { $state.last_spotify_version = $freshVersion }
            Save-State $state
            Start-Sleep -Seconds 8
            Start-PerformanceSnapshotAsync
            return
        }

        Write-Log "'spicetify auto' returned exit code $($r.ExitCode). Falling back to Spotify without restore/delete operations." "WARN"
    }
    elseif ($guard) {
        Write-Log ("Skipping 'spicetify auto' because current Spotify is not verified compatible. " + $guard.Reason) "WARN"
    }
    else {
        Write-Log "No guard result was available; skipping 'spicetify auto' as a fail-safe." "WARN"
    }

    if (-not $spotifyExe) { $spotifyExe = Get-SpotifyExecutable }
    if ($spotifyExe) {
        Start-Process -FilePath $spotifyExe
        Start-Sleep -Seconds 8
        Start-PerformanceSnapshotAsync
        return
    }

    throw "Spotify executable not found."
}

function Invoke-SelfTest {
    Write-Log "Running read-only self-test."

    $results = New-Object System.Collections.Generic.List[object]

    function Add-Result([string]$Name, [bool]$Pass, [string]$Detail) {
        $results.Add([pscustomobject]@{
            Name = $Name
            Pass = $Pass
            Detail = $Detail
        })
    }

    Add-Result "Root directory" (Test-UsablePath -Path $Root -PathType "Container") $Root
    Add-Result "Main script path" (Test-UsablePath -Path $ScriptFile -PathType "Leaf") ([string]$ScriptFile)
    $auxResolutionOkay = (Test-UsablePath -Path $AuxBinDir -PathType "Container")
    Add-Result "Auxiliary helper bin resolution" $auxResolutionOkay ("script_bin={0}; aux_bin={1}; installed_bin={2}" -f $BinDir,$AuxBinDir,$InstalledBinDir)

    $nativeWrapperOkay = $false
    $nativeDetail = ""
    if ($script:Spicetify -and (Test-UsablePath -Path $script:Spicetify -PathType "Leaf")) {
        $r = Invoke-SpiceCapture -Arguments @("--version")
        $nativeWrapperOkay = ($r.ExitCode -eq 0)
        $nativeDetail = "exit=$($r.ExitCode); output=$($r.Output)"
    } else {
        $nativeWrapperOkay = $true
        $nativeDetail = "Spicetify not found; wrapper invocation skipped."
    }
    Add-Result "Native process wrapper" $nativeWrapperOkay $nativeDetail

    $splitModeOkay = ((Get-MaintenanceMode -SpotifyRunning $true) -eq "check-only") -and `
        ((Get-MaintenanceMode -SpotifyRunning $false) -eq "check+mutation")
    Add-Result "Maintenance phase selector" $splitModeOkay "running=>check-only; closed=>check+mutation"

    $shapeProbe = Ensure-StateShape ([pscustomobject]@{})
    $shapeOkay = ($shapeProbe.schema -eq 20) -and ($null -ne $shapeProbe.pending_reasons) -and $shapeProbe.PSObject.Properties['spicetify_last_transaction_status'] -and $shapeProbe.PSObject.Properties['spotify_last_transaction_status'] -and $shapeProbe.PSObject.Properties['pending_spotify_update'] -and $shapeProbe.PSObject.Properties['pending_spicetify_repair'] -and $shapeProbe.PSObject.Properties['pending_direct_extension_repair_count'] -and $shapeProbe.PSObject.Properties['pending_self_update'] -and $shapeProbe.PSObject.Properties['self_update_latest_version']
    Add-Result "Maintenance pending-state schema" $shapeOkay "schema=$($shapeProbe.schema); Spicetify + Spotify + direct-extension + self-update fields present"

    $directFixtureItems = @(
        [pscustomobject]@{name='bookmark.js';kind='extension';policy='spicetify-release-owned';status='repair-needed-trusted-old-official';installed=$true},
        [pscustomobject]@{name='loopyLoop.js';kind='extension';policy='spicetify-release-owned';status='repair-blocked-local-modified';installed=$true},
        [pscustomobject]@{name='mystery.js';kind='extension';policy='unknown-source';status='manual-source-identification-required';installed=$true},
        [pscustomobject]@{name='sc-star-ratings.js';kind='extension';policy='rescue-copy-cleanup-only';status='rescue-copy-active';installed=$true}
    )
    $directFixture = Get-DirectExtensionPolicyCounts -Items $directFixtureItems
    $directFixtureOkay = ($directFixture.RepairCount -eq 1) -and ($directFixture.BlockedCount -eq 1) -and ($directFixture.UnknownCount -eq 1) -and ($directFixture.RescueCount -eq 1)
    Add-Result "Managed direct-extension policy routing" $directFixtureOkay ("repair={0}; blocked={1}; unknown={2}; rescue={3}" -f $directFixture.RepairCount,$directFixture.BlockedCount,$directFixture.UnknownCount,$directFixture.RescueCount)

    $bootstrapSelfTest = Invoke-SelfUpdaterJsonAction -SelfAction "SelfTest"
    $bootstrapSelfOkay = ($bootstrapSelfTest.ExitCode -eq 0) -and $bootstrapSelfTest.Report -and [bool]$bootstrapSelfTest.Report.success
    $bootstrapSelfDetail = if ($bootstrapSelfTest.Report -and $bootstrapSelfTest.Report.result) { "version=" + [string]$bootstrapSelfTest.Report.result.bootstrap_version + "; path=" + $SelfUpdater } else { [string]$bootstrapSelfTest.Output }
    Add-Result "Self-update bootstrap trust root" $bootstrapSelfOkay $bootstrapSelfDetail

    $agentDefaultOkay = (-not [bool]$shapeProbe.agent_mutation_enabled) -and ($AgentDiscoveryIntervalHours -ge 6)
    Add-Result "Resident agent safe default" $agentDefaultOkay "mutation_enabled=$($shapeProbe.agent_mutation_enabled); discovery_interval_hours=$AgentDiscoveryIntervalHours"

    $compatBodyFixture = @(
        '## Compatibility',
        '- Spotify for **macOS**: `1.2.14` -> `1.3.6`',
        '- Spotify for **Linux**: `1.2.14` -> `1.3.4`',
        '- Spotify for **Windows/Microsoft Store**: `1.2.14` -> `1.3.6`'
    ) -join "`n"
    $compatFixture = [pscustomobject]@{ tag_name='v9.8.7'; draft=$false; prerelease=$false; published_at='2026-01-01T00:00:00Z'; body=$compatBodyFixture }
    $compatParsed = ConvertFrom-SpicetifyReleaseCompatibility -Release $compatFixture -ExpectedTag 'v9.8.7'
    $compatFixtureOkay = $compatParsed.Verified -and $compatParsed.Version -eq '9.8.7' -and $compatParsed.Min -eq '1.2.14' -and $compatParsed.Max -eq '1.3.6'
    Add-Result "Spicetify compatibility parser fixture" $compatFixtureOkay ("tag={0}; range={1}->{2}; error={3}" -f $compatParsed.Tag,$compatParsed.Min,$compatParsed.Max,$compatParsed.Error)

    $unicodeArrowBody = ('## Compatibility' + "`n" + '- Spotify for **Windows/Microsoft Store**: `1.2.14` ' + [char]0x2192 + ' `1.3.6`')
    $unicodeArrowFixture = [pscustomobject]@{ tag_name='v9.8.7'; draft=$false; prerelease=$false; published_at='2026-01-01T00:00:00Z'; body=$unicodeArrowBody }
    $unicodeArrowParsed = ConvertFrom-SpicetifyReleaseCompatibility -Release $unicodeArrowFixture -ExpectedTag 'v9.8.7'
    Add-Result "Spicetify compatibility Unicode-arrow fixture" ($unicodeArrowParsed.Verified -and $unicodeArrowParsed.Min -eq '1.2.14' -and $unicodeArrowParsed.Max -eq '1.3.6') ([string]$unicodeArrowParsed.Error)

    $plainSeparatorFixture = [pscustomobject]@{ tag_name='v9.8.7'; draft=$false; prerelease=$false; published_at='2026-01-01T00:00:00Z'; body="## Compatibility`n- Spotify for **Windows/Microsoft Store**: 1.2.14 to 1.3.6" }
    $plainSeparatorParsed = ConvertFrom-SpicetifyReleaseCompatibility -Release $plainSeparatorFixture -ExpectedTag 'v9.8.7'
    Add-Result "Spicetify compatibility separator-independent fixture" ($plainSeparatorParsed.Verified -and $plainSeparatorParsed.Min -eq '1.2.14' -and $plainSeparatorParsed.Max -eq '1.3.6') ([string]$plainSeparatorParsed.Error)

    $thirdVersionFixture = [pscustomobject]@{ tag_name='v9.8.7'; draft=$false; prerelease=$false; published_at='2026-01-01T00:00:00Z'; body="## Compatibility`n- Spotify for **Windows/Microsoft Store**: 1.2.14 -> 1.3.6; legacy 1.2.0" }
    $thirdVersionParsed = ConvertFrom-SpicetifyReleaseCompatibility -Release $thirdVersionFixture -ExpectedTag 'v9.8.7'
    Add-Result "Spicetify compatibility third-version rejection" (-not $thirdVersionParsed.Verified) ([string]$thirdVersionParsed.Error)

    $reversedRangeFixture = [pscustomobject]@{ tag_name='v9.8.7'; draft=$false; prerelease=$false; published_at='2026-01-01T00:00:00Z'; body="## Compatibility`n- Spotify for **Windows/Microsoft Store**: 1.3.6 -> 1.2.14" }
    $reversedRangeParsed = ConvertFrom-SpicetifyReleaseCompatibility -Release $reversedRangeFixture -ExpectedTag 'v9.8.7'
    Add-Result "Spicetify compatibility reversed-range rejection" (-not $reversedRangeParsed.Verified) ([string]$reversedRangeParsed.Error)

    $fixtureArch = Get-SpicetifyArchitecture
    $fixtureAssetName = "spicetify-9.8.7-windows-$fixtureArch.zip"
    $releaseFixture = [pscustomobject]@{
        tag_name='v9.8.7'; draft=$false; prerelease=$false; published_at='2026-01-01T00:00:00Z'
        body=$compatBodyFixture
        assets=@([pscustomobject]@{
            name=$fixtureAssetName; state='uploaded'; digest=('sha256:' + ('a' * 64)); size=123456; id=987
            browser_download_url=("https://github.com/spicetify/cli/releases/download/v9.8.7/" + $fixtureAssetName)
        })
    }
    $releaseParsed = ConvertFrom-SpicetifyReleaseInfo -Release $releaseFixture -ExpectedTag 'v9.8.7'
    $releaseFixtureOkay = $releaseParsed.Verified -and $releaseParsed.Version -eq '9.8.7' -and $releaseParsed.AssetName -eq $fixtureAssetName -and $releaseParsed.AssetDigest -eq ('sha256:' + ('a' * 64))
    Add-Result "Spicetify official asset metadata fixture" $releaseFixtureOkay ("asset={0}; arch={1}; error={2}" -f $releaseParsed.AssetName,$releaseParsed.Architecture,$releaseParsed.Error)


    $wrongArch = $(if($fixtureArch -eq 'x64'){'arm64'}else{'x64'})
    $wrongUrlFixture = [pscustomobject]@{
        tag_name='v9.8.7'; draft=$false; prerelease=$false; published_at='2026-01-01T00:00:00Z'
        body=$compatBodyFixture
        assets=@([pscustomobject]@{
            name=$fixtureAssetName; state='uploaded'; digest=('sha256:' + ('a' * 64)); size=123456; id=988
            browser_download_url=("https://github.com/spicetify/cli/releases/download/v9.8.7/spicetify-9.8.7-windows-" + $wrongArch + ".zip")
        })
    }
    $wrongUrlParsed = ConvertFrom-SpicetifyReleaseInfo -Release $wrongUrlFixture -ExpectedTag 'v9.8.7'
    Add-Result "Spicetify architecture/asset URL mismatch rejection" (-not $wrongUrlParsed.Verified) ([string]$wrongUrlParsed.Error)

    $badDigestFixture = [pscustomobject]@{
        tag_name='v9.8.7'; draft=$false; prerelease=$false; published_at='2026-01-01T00:00:00Z'
        body=$compatBodyFixture
        assets=@([pscustomobject]@{
            name=$fixtureAssetName; state='uploaded'; digest=''; size=123456; id=989
            browser_download_url=("https://github.com/spicetify/cli/releases/download/v9.8.7/" + $fixtureAssetName)
        })
    }
    $badDigestParsed = ConvertFrom-SpicetifyReleaseInfo -Release $badDigestFixture -ExpectedTag 'v9.8.7'
    Add-Result "Spicetify missing published digest rejection" (-not $badDigestParsed.Verified) ([string]$badDigestParsed.Error)

    $legacyTxn = ([pscustomobject]@{ schema=1; id='fixture'; status='awaiting-guard' } | ConvertTo-Json | ConvertFrom-Json)
    $legacyTxn = Ensure-SpicetifyTransactionShape $legacyTxn
    $legacyTxn.apply_attempted = $true
    $legacyTxn.apply_succeeded = $true
    $legacyTxn.post_apply_guard_succeeded = $true
    $ledgerShapeOkay = ($legacyTxn.schema -eq 3) -and $legacyTxn.PSObject.Properties['rolled_back_at'] -and $legacyTxn.PSObject.Properties['rollback_reapply_succeeded'] -and [bool]$legacyTxn.apply_attempted -and [bool]$legacyTxn.post_apply_guard_succeeded
    Add-Result "Spicetify legacy transaction schema migration" $ledgerShapeOkay "missing lifecycle fields can be added and assigned after JSON round-trip"

    $rangeOkay = (Test-SpotifyVersionInRange -SpotifyVersion '1.3.3.264' -MinSupported '1.2.14' -MaxSupported '1.3.6') -and `
        (-not (Test-SpotifyVersionInRange -SpotifyVersion '1.3.7.1' -MinSupported '1.2.14' -MaxSupported '1.3.6')) -and `
        (-not (Test-SpotifyVersionInRange -SpotifyVersion '1.2.13.9' -MinSupported '1.2.14' -MaxSupported '1.3.6'))
    Add-Result "Spicetify compatibility range semantics" $rangeOkay "min and max boundaries enforced at major.minor.patch granularity"

    $legacySpotifyTxn = ([pscustomobject]@{ schema=1; id='spotify-fixture'; status='prepared' } | ConvertTo-Json | ConvertFrom-Json)
    $legacySpotifyTxn = Ensure-SpotifyTransactionShape $legacySpotifyTxn
    $legacySpotifyTxn.install_started_at = 'fixture'
    $legacySpotifyTxn.committed_at = 'fixture-commit'
    $spotifyLedgerOkay = ($legacySpotifyTxn.schema -eq 2) -and $legacySpotifyTxn.PSObject.Properties['rolled_back_at'] -and $legacySpotifyTxn.PSObject.Properties['guard_verified_at'] -and ([string]$legacySpotifyTxn.committed_at -eq 'fixture-commit')
    Add-Result "Spotify legacy transaction schema migration" $spotifyLedgerOkay "missing lifecycle fields can be added and assigned after JSON round-trip"

    $spotifyTxnSandbox = Test-SpotifyTransactionSandbox
    Add-Result "Spotify transaction exact-backup sandbox" ([bool]$spotifyTxnSandbox.Pass) ([string]$spotifyTxnSandbox.Detail)

    $prefsFixtureOkay=$false;$prefsFixtureDetail=''
    try {
        $fixtureText='alpha=1'+"`r`n"+'app.last-launched-version="1.3.3.264.gold"'+"`r`n"+'omega=2'+"`r`n"
        $fixtureBytes=[System.Text.Encoding]::UTF8.GetBytes($fixtureText)
        $patchedBytes=ConvertTo-SpotifyPrefsBytesWithVersion -Bytes $fixtureBytes -Version '1.3.6.1921.gnew'
        $patchedText=[System.Text.Encoding]::UTF8.GetString($patchedBytes)
        $expectedText='alpha=1'+"`r`n"+'app.last-launched-version="1.3.6.1921.gnew"'+"`r`n"+'omega=2'+"`r`n"
        $prefsFixtureOkay=($patchedText -ceq $expectedText)
        $prefsFixtureDetail='single-line byte-preserving fullversion stamp with CRLF preserved'
    } catch {$prefsFixtureDetail=$_.Exception.Message}
    Add-Result "Spotify prefs fullversion byte-stamp fixture" $prefsFixtureOkay $prefsFixtureDetail

    $iniFixtureOkay=$false;$iniFixtureDetail=''
    $iniFixture=Join-Path $env:TEMP ('SpotifyControl-IniMetadataFixture-'+[guid]::NewGuid().ToString('N')+'.ini')
    try {
        $iniText='[Setting]'+"`r`n"+'foo = bar'+"`r`n"+'[Backup]'+"`r`n"+'version = 1.3.3.264.gold'+"`r`n"+'with = 2.46.2'+"`r`n"+'[Patch]'+"`r`n"+'x = y'+"`r`n"
        $iniEnc=[System.Text.UTF8Encoding]::new($true)
        [System.IO.File]::WriteAllText($iniFixture,$iniText,$iniEnc)
        $beforeIni=[System.IO.File]::ReadAllBytes($iniFixture)
        Set-IniSectionValueBytePreserving -Path $iniFixture -Section 'Backup' -Key 'version' -Value '1.3.6.1921.gnew'
        $afterIni=[System.IO.File]::ReadAllBytes($iniFixture)
        $afterText=[System.Text.UTF8Encoding]::new($true,$true).GetString($afterIni,3,$afterIni.Length-3)
        $expectedIni=$iniText.Replace('version = 1.3.3.264.gold','version = 1.3.6.1921.gnew')
        $iniFixtureOkay=($afterIni.Length -ge 3 -and $afterIni[0]-eq 0xEF -and $afterIni[1]-eq 0xBB -and $afterIni[2]-eq 0xBF -and $afterText -ceq $expectedIni -and (Get-IniSectionValue -Path $iniFixture -Section 'Backup' -Key 'with') -ceq '2.46.2')
        $iniFixtureDetail='UTF-8 BOM + CRLF preserved; only Backup.version value changed'
    } catch {$iniFixtureDetail=$_.Exception.Message}
    finally {Remove-Item -LiteralPath $iniFixture -Force -ErrorAction SilentlyContinue}
    Add-Result "Spicetify Backup metadata BOM/CRLF rewrite fixture" $iniFixtureOkay $iniFixtureDetail

    $eligTxn=[pscustomobject]@{status='committed';after_version='1.3.6.1921';final_version='1.3.6.1921';after_fullversion='1.3.6.1921.gnew';apply_finished_at='2026-01-01T00:00:10Z';committed_at='2026-01-01T00:00:20Z';protected_before_tree_sha256='p';protected_after_tree_sha256='p';spicetify_config_semantic_before='c';spicetify_config_semantic_after='c';spicetify_user_assets_before_tree_sha256='u';spicetify_user_assets_after_tree_sha256='u'}
    $elig=Test-SpicetifyBackupMetadataRepairEligibility -Transaction $eligTxn -InstalledVersion '1.3.6.1921' -PrefsFullVersion '1.3.6.1921.gnew' -BackupVersion '1.3.3.264.gold' -BackupWith '2.46.2' -InstalledSpicetifyVersion '2.46.2'
    $blocked=Test-SpicetifyBackupMetadataRepairEligibility -Transaction $eligTxn -InstalledVersion '1.3.6.1921' -PrefsFullVersion '1.3.6.1921.gnew' -BackupVersion '1.3.3.264.gold' -BackupWith '2.45.3' -InstalledSpicetifyVersion '2.46.2'
    Add-Result "Spicetify stale Backup metadata provenance gate fixture" ([bool]$elig.Eligible -and -not [bool]$blocked.Eligible) ("eligible={0}; mismatch_blocked={1}" -f $elig.Eligible,(-not $blocked.Eligible))

    Add-Result "Spotify trusted transaction stage armed" ([bool]$SpotifyTransactionalUpdatesReady) "native updater remains blocked; only pinned Spotify Control transaction may update"

    $spiceTxnSandbox = Test-SpicetifySwapRollbackSandbox
    Add-Result "Spicetify full-root sandbox swap/rollback" ([bool]$spiceTxnSandbox.Pass) ([string]$spiceTxnSandbox.Detail)

    $tagNormalizeOkay = ((Normalize-MarketplaceTag " v1.0.11. ") -eq "v1.0.11")
    Add-Result "Marketplace tag normalization" $tagNormalizeOkay "trailing-dot legacy state normalizes deterministically"

    $marketResolution = Get-MarketplaceInstallResolution
    $marketResolutionOkay = ($marketResolution.Status -ne "ambiguous")
    Add-Result "Marketplace install resolution" $marketResolutionOkay ("status={0}; locations={1}" -f $marketResolution.Status,(@($marketResolution.Locations) -join '; '))
    if ($marketResolution.Status -eq "resolved") {
        $marketPayloadProbe = Test-MarketplacePayload -Path $marketResolution.Path
        Add-Result "Installed Marketplace payload validation" ([bool]$marketPayloadProbe.Valid) ("files={0}; tree={1}; error={2}" -f $marketPayloadProbe.FileCount,$marketPayloadProbe.TreeSha256,$marketPayloadProbe.Error)
    }
    $marketTxnSandbox = Test-MarketplaceSwapRollbackSandbox
    Add-Result "Marketplace sandbox swap/rollback" ([bool]$marketTxnSandbox.Pass) ([string]$marketTxnSandbox.Detail)

    $spotifyExe = $null
    try { $spotifyExe = Get-SpotifyExecutable } catch {}
    $spotifyDetail = if ($spotifyExe) { $spotifyExe } else { "Not found; non-fatal for install." }
    Add-Result "Spotify executable discovery" $true $spotifyDetail

    $configPath = $null
    try { $configPath = Get-ConfigPath } catch {}
    $configDetail = if ($configPath) { $configPath } else { "Not found; non-fatal for install." }
    Add-Result "Spicetify config discovery" $true $configDetail

    $patchState = if ($spotifyExe) { Get-SpotifyUpdatePatchState -SpotifyExe $spotifyExe } else { "unknown" }
    Add-Result "Spotify update endpoint inspection" $true $patchState

    $aclState = Get-SpotifyUpdateAclState
    Add-Result "Spotify Update folder ACL inspection" $true $aclState

    # Read-only smoke test for the exact native command path used by the ACL guard.
    # This catches undefined wrapper names / quoting problems before GuardUpdates mutates anything.
    $icaclsSmokeOk = $false
    $icaclsSmokeDetail = ""
    try {
        $icaclsSmoke = Invoke-Icacls -Arguments @($Root)
        $icaclsSmokeOk = ($icaclsSmoke.ExitCode -eq 0)
        $icaclsSmokeDetail = "exit=$($icaclsSmoke.ExitCode)"
        if (-not [string]::IsNullOrWhiteSpace($icaclsSmoke.Output)) {
            $firstLine = ($icaclsSmoke.Output -split "`r?`n" | Select-Object -First 1)
            if ($firstLine) { $icaclsSmokeDetail += "; " + $firstLine.Trim() }
        }
    }
    catch {
        $icaclsSmokeOk = $false
        $icaclsSmokeDetail = $_.Exception.Message
    }
    Add-Result "icacls native wrapper smoke test" $icaclsSmokeOk $icaclsSmokeDetail

    Add-Result "Addon Manager script" (Test-UsablePath -Path $AddonManager -PathType "Leaf") $AddonManager
    Add-Result "Performance Profiler script" (Test-UsablePath -Path $PerformanceProfiler -PathType "Leaf") $PerformanceProfiler
    Add-Result "Health Reporter script" (Test-UsablePath -Path $HealthReporter -PathType "Leaf") $HealthReporter
    $abProfiler = Join-Path $AuxBinDir "performance-ab-profiler.ps1"
    Add-Result "Performance A/B Profiler script" (Test-UsablePath -Path $abProfiler -PathType "Leaf") $abProfiler
    $marketProfiler = Join-Path $AuxBinDir "marketplace-isolation-profiler.ps1"
    Add-Result "Marketplace Isolation Profiler script" (Test-UsablePath -Path $marketProfiler -PathType "Leaf") $marketProfiler

    $failed = @($results | Where-Object { -not $_.Pass })
    foreach ($item in $results) {
        $level = if ($item.Pass) { "INFO" } else { "ERROR" }
        $prefix = if ($item.Pass) { "PASS" } else { "FAIL" }
        Write-Log ("SELFTEST {0}: {1} - {2}" -f $prefix,$item.Name,$item.Detail) $level
    }

    if ($failed.Count -gt 0) {
        throw "Self-test failed: $($failed.Name -join ', ')"
    }

    Write-Log "Read-only self-test passed."
}

function Show-SpotifyControlStatus {
    $state = Ensure-StateShape (Load-State)
    $spotifyExe = Get-SpotifyExecutable
    $spotifyVersion = Get-SpotifyVersion -Exe $spotifyExe
    $patchState = Get-SpotifyUpdatePatchState -SpotifyExe $spotifyExe
    $aclState = Get-SpotifyUpdateAclState

    $liveEnforced = if ($aclState -eq "blocked") {
        "blocked"
    } elseif ($aclState -eq "unblocked" -and $patchState -ne "blocked") {
        "unblocked"
    } else {
        "unknown"
    }

    Write-Host ""
    Write-Host "Spotify Control v$ScriptVersion" -ForegroundColor Cyan
    Write-Host "------------------------------"
    Write-Host ("Spotify:                 " + $(if ($spotifyVersion) { $spotifyVersion } else { "unknown" }))
    Write-Host ("Guard desired:           " + $(if ($state.guard_desired) { $state.guard_desired } else { "unknown" }))
    Write-Host ("Guard enforced (live):   " + $liveEnforced)
    Write-Host ("Guard method:            " + $(if ($state.guard_method) { $state.guard_method } else { "unknown" }))
    Write-Host ("Update binary endpoint:  " + $patchState)
    Write-Host ("Update folder ACL:       " + $aclState)
    Write-Host ("Last guard check:        " + $(if ($state.last_guard_check) { $state.last_guard_check } else { "never" }))
    Write-Host ("Spicetify installed:     " + $(if ($state.spicetify_installed_version) { $state.spicetify_installed_version } else { (Get-InstalledSpicetifyVersion) }))
    Write-Host ("Spicetify install mode:  " + $(if ($state.spicetify_install_mode) { $state.spicetify_install_mode } else { "unknown" }))
    Write-Host ("Spicetify compat tag:    " + $(if ($state.spicetify_compat_tag) { $state.spicetify_compat_tag } else { "unknown" }))
    Write-Host ("Spicetify latest tag:    " + $(if ($state.spicetify_latest_tag) { $state.spicetify_latest_tag } else { "unknown" }))
    $spicetifyRange = if ($state.spicetify_max_windows) {
        $rangeMin = if ($state.spicetify_compat_min_windows) { [string]$state.spicetify_compat_min_windows } else { "?" }
        $rangeMin + " -> " + [string]$state.spicetify_max_windows
    } else {
        "unknown"
    }
    Write-Host ("Spicetify Windows range: " + $spicetifyRange)
    Write-Host ("Spicetify txn status:    " + $(if ($state.spicetify_last_transaction_status) { $state.spicetify_last_transaction_status } else { "never" }))
    Write-Host ("Spicetify asset digest:  " + $(if ($state.spicetify_last_digest) { $state.spicetify_last_digest } else { "unknown" }))
    Write-Host ("Spotify candidate:       " + $(if ($state.spotify_candidate_version) { $state.spotify_candidate_version } else { "unknown" }))
    Write-Host ("Current supported:       " + $(if ($null -ne $state.current_spotify_supported) { $state.current_spotify_supported } else { "unknown" }))
    Write-Host ("Reason:                  " + $(if ($state.guard_reason) { $state.guard_reason } else { "not checked yet" }))
    Write-Host ("Last check-only:         " + $(if ($state.last_check_only_utc) { $state.last_check_only_utc } else { "never" }))
    Write-Host ("Pending maintenance:     " + [bool]$state.pending_maintenance)
    Write-Host ("Pending reasons:         " + $(if (@($state.pending_reasons).Count -gt 0) { @($state.pending_reasons) -join ", " } else { "none" }))
    Write-Host ("Pending Spicetify CLI:   " + [bool]$state.pending_spicetify_upgrade)
    Write-Host ("Pending Spicetify repair:" + (' ' * 3) + [bool]$state.pending_spicetify_repair)
    Write-Host ("Direct ext repair/block/unknown: {0}/{1}/{2}" -f [int]$state.pending_direct_extension_repair_count,[int]$state.pending_direct_extension_blocked_count,[int]$state.pending_direct_extension_unknown_count)
    Write-Host ("Pending Spotify update:  " + [bool]$state.pending_spotify_update)
    Write-Host ("Spotify txn status:      " + $(if ($state.spotify_last_transaction_status) { $state.spotify_last_transaction_status } else { "never" }))
    Write-Host ("Pending Marketplace:     " + [bool]$state.pending_marketplace_update)
    Write-Host ("Marketplace txn status: " + $(if ($state.marketplace_last_transaction_status) { $state.marketplace_last_transaction_status } else { "never" }))
    Write-Host ("Marketplace digest:     " + $(if ($state.marketplace_last_digest) { $state.marketplace_last_digest } else { "unknown" }))
    Write-Host ("Pending addon updates:   " + [int]$state.pending_addon_updates)
    Write-Host ("Auto addon ambiguity:    " + [int]$state.pending_addon_auto_ambiguous)
    Write-Host ("Monitor ambiguity:       " + [int]$state.pending_addon_nonauto_ambiguous)
    Write-Host ("Self-update latest:       " + $(if ($state.self_update_latest_version) { $state.self_update_latest_version } else { "unknown" }))
    Write-Host ("Pending self-update:      " + [bool]$state.pending_self_update)
    Write-Host ("Self-update txn status:   " + $(if ($state.self_update_last_transaction_status) { $state.self_update_last_transaction_status } else { "never" }))
    Write-Host ("Resident agent mutation: " + [bool]$state.agent_mutation_enabled)
    Write-Host ("Last agent tick:         " + $(if ($state.last_agent_tick_utc) { $state.last_agent_tick_utc } else { "never" }))
    Write-Host ("Last agent event:        " + $(if ($state.last_agent_event) { $state.last_agent_event } else { "none" }))
    Write-Host ("Last agent decision:     " + $(if ($state.last_agent_decision) { $state.last_agent_decision } else { "none" }))

    if ($state.guard_desired -and $liveEnforced -ne $state.guard_desired) {
        Write-Host ""
        Write-Host "WARNING: desired guard state is not verified live." -ForegroundColor Yellow
    }
    Write-Host ""
}

try {
    Write-Log "Spotify Control v$ScriptVersion action=$Action force=$Force"

    Assert-R136NoBypassFromOwnerHold -RequestedAction $Action
    switch ($Action) {
        "OwnerSpicetifyOnce" {
            [void](Invoke-R135OwnerSpicetifyOneShot -OwnerApproval $OwnerOnceApproval -ForceReinstall:$Force)
        }

        "OwnerEnableSafeAuto" {
            [void](Invoke-R139EnableSafeAuto -OwnerApproval $OwnerSafeAutoApproval)
        }

        "Maintain" {
            Maintain
        }

        "CheckOnly" {
            if (-not $script:Spicetify) {
                Write-Log "Spicetify is not installed or not on PATH. Check-only maintenance skipped." "WARN"
            } else {
                $lease = Enter-SpotifyControlMutex -Purpose "Maintenance"
                if ($null -eq $lease) {
                    Write-Log "Check-only maintenance skipped because another maintenance/check operation is already active." "WARN"
                } else {
                    try {
                        $state = Ensure-StateShape (Load-State)
                        $state = Migrate-StateFromLog $state
                        [void](Invoke-MaintenanceCheckPhase -State $state)
                    } finally {
                        Exit-SpotifyControlMutex -Mutex $lease
                    }
                }
            }
        }

        "AgentTick" {
            if (-not $script:Spicetify) {
                Write-Log "Spicetify is not installed or not on PATH. Resident-agent tick skipped." "WARN"
            } else {
                Invoke-ResidentAgentTick -EventName $AgentEvent
            }
        }

        "UpdateMarketplace" {
            if (Test-SpotifyRunning) {
                Write-Log "Spotify is running; Marketplace transaction postponed." "WARN"
            } else {
                $state = Ensure-StateShape (Load-State)
                $state = Migrate-StateFromLog $state
                $m = Update-Marketplace -State $state
                Save-State (Ensure-StateShape $m.State)
                if ($m.Status -notin @("committed","already-current")) { throw "Marketplace transaction did not commit (status=$($m.Status)); see $MarketplaceTransactionReport" }
            }
        }

        "MarketplacePreflight" {
            [void](Invoke-MarketplacePreflight)
        }

        "SpicetifyPreflight" {
            [void](Invoke-SpicetifyPreflight)
        }

        "UpdateSpicetify" {
            if (Test-SpotifyRunning) { throw "Spotify is running; Spicetify CLI transaction requires Spotify to be fully closed." }
            $lease = Enter-SpotifyControlMutex -Purpose "Maintenance"
            if ($null -eq $lease) { throw "Another maintenance/check operation is already active." }
            try {
                $state = Ensure-StateShape (Load-State)
                $state = Migrate-StateFromLog $state
                $result = Invoke-SpicetifyTransactionalMaintenance -State $state -ForceReinstall:$Force
                if (-not $result.Success -or $result.Status -notin @("committed","already-current")) {
                    throw "Spicetify transaction did not complete safely (status=$($result.Status)); see $SpicetifyTransactionReport"
                }
                if ($result.Status -eq "already-current") {
                    $plan = Get-SmartUpdateGuardPlan
                    $guard = Invoke-SmartUpdateGuard -State $result.State -Plan $plan
                    if (-not $guard.Success -or $guard.CurrentSupported -ne $true) {
                        throw "Spicetify is current, but compatibility/guard verification failed."
                    }
                }
            } finally {
                Exit-SpotifyControlMutex -Mutex $lease
            }
        }

        "SpicetifyRollbackTest" {
            if (Test-SpotifyRunning) { throw "Spotify is running; Spicetify rollback acceptance requires Spotify to be fully closed." }
            $lease = Enter-SpotifyControlMutex -Purpose "Maintenance"
            if ($null -eq $lease) { throw "Another maintenance/check operation is already active." }
            try {
                $state = Ensure-StateShape (Load-State)
                $state = Migrate-StateFromLog $state
                $result = Invoke-SpicetifyTransactionalMaintenance -State $state -ForceReinstall -RollbackAfterSwap
                if (-not $result.Success -or $result.Status -ne "rolled-back") {
                    throw "Spicetify live rollback acceptance did not restore the original executable (status=$($result.Status))."
                }
                $plan = Get-SmartUpdateGuardPlan
                $guard = Invoke-SmartUpdateGuard -State $result.State -Plan $plan
                if (-not $guard.Success -or $guard.CurrentSupported -ne $true) {
                    throw "Spicetify rollback succeeded but post-rollback compatibility/guard verification failed."
                }
            } finally {
                Exit-SpotifyControlMutex -Mutex $lease
            }
        }

        "RollbackSpicetify" {
            if (Test-SpotifyRunning) { throw "Spotify is running; Spicetify rollback requires Spotify to be fully closed." }
            $lease = Enter-SpotifyControlMutex -Purpose "Maintenance"
            if ($null -eq $lease) { throw "Another maintenance/check operation is already active." }
            try {
                $state = Ensure-StateShape (Load-State)
                $rb = Rollback-SpicetifyCliTransaction
                if (-not $rb.Success) { throw "Spicetify rollback failed." }
                $state.spicetify_last_transaction_id = $(if($rb.Transaction){[string]$rb.Transaction.id}else{$null})
                $state.spicetify_last_transaction_status = [string]$rb.Status
                $state.spicetify_last_transaction_utc = [DateTimeOffset]::UtcNow.ToString("o")
                $state.spicetify_installed_version = Get-InstalledSpicetifyVersion
                $state.spicetify_install_mode = (Get-SpicetifyManagedInstallInfo).Mode
                $plan = Get-SmartUpdateGuardPlan
                $guard = Invoke-SmartUpdateGuard -State $state -Plan $plan
                if (-not $guard.Success -or $guard.CurrentSupported -ne $true) {
                    throw "Spicetify rollback completed but compatibility/guard verification failed."
                }
            } finally {
                Exit-SpotifyControlMutex -Mutex $lease
            }
        }

        "SpotifyPreflight" {
            [void](Invoke-SpotifyPreflight)
        }

        "UpdateSpotify" {
            if (Test-SpotifyRunning) { throw "Spotify is running; Spotify transaction requires Spotify to be fully closed." }
            $lease = Enter-SpotifyControlMutex -Purpose "Maintenance"
            if ($null -eq $lease) { throw "Another maintenance/check operation is already active." }
            try {
                $state = Ensure-StateShape (Load-State)
                $state = Migrate-StateFromLog $state
                $result = Invoke-SpotifyTransactionalMaintenance -State $state -ForceReinstall:$Force
                if (-not $result.Success -or $result.Status -notin @('committed','already-current')) { throw "Spotify transaction did not complete safely (status=$($result.Status)); see $SpotifyTransactionReport" }
            } finally { Exit-SpotifyControlMutex -Mutex $lease }
        }

        "SpotifyRollbackTest" {
            if (Test-SpotifyRunning) { throw "Spotify is running; Spotify rollback acceptance requires Spotify to be fully closed." }
            $lease = Enter-SpotifyControlMutex -Purpose "Maintenance"
            if ($null -eq $lease) { throw "Another maintenance/check operation is already active." }
            try {
                $state = Ensure-StateShape (Load-State)
                $state = Migrate-StateFromLog $state
                $result = Invoke-SpotifyTransactionalMaintenance -State $state -ForceReinstall -RollbackAfterApply
                if (-not $result.Success -or $result.Status -ne 'rolled-back') { throw "Spotify live rollback acceptance failed (status=$($result.Status))." }
            } finally { Exit-SpotifyControlMutex -Mutex $lease }
        }

        "RollbackSpotify" {
            if (Test-SpotifyRunning) { throw "Spotify is running; Spotify rollback requires Spotify to be fully closed." }
            $lease = Enter-SpotifyControlMutex -Purpose "Maintenance"
            if ($null -eq $lease) { throw "Another maintenance/check operation is already active." }
            try { $rb=Rollback-SpotifyTransaction -AllowCommitted:$Force;if(-not $rb.Success){throw 'Spotify rollback failed.'} }
            finally { Exit-SpotifyControlMutex -Mutex $lease }
        }

        "InstallTasks" {
            Install-TasksAndShortcuts
        }

        "SelfTest" {
            Invoke-SelfTest
        }

        "SelfUpdateCheck" {
            $r=Get-SelfUpdateCheckResult
            if (-not $r.Verified) { throw "Spotify Control self-update check failed: $($r.Error)" }
            $r | Format-List | Out-String | Write-Host
        }

        "SelfUpdate" {
            if (Test-SpotifyRunning) { throw "Spotify is running; Spotify Control self-update requires Spotify to be fully closed." }
            $lease=Enter-SpotifyControlMutex -Purpose "Maintenance"
            if ($null -eq $lease) { throw "Another maintenance/check operation is already active." }
            try { [void](Invoke-SelfUpdateMutation -SelfAction "Update" -ForceSelf:$Force) } finally { Exit-SpotifyControlMutex -Mutex $lease }
        }

        "SelfUpdateRollbackTest" {
            if (Test-SpotifyRunning) { throw "Spotify is running; self-update rollback acceptance requires Spotify to be fully closed." }
            $lease=Enter-SpotifyControlMutex -Purpose "Maintenance"
            if ($null -eq $lease) { throw "Another maintenance/check operation is already active." }
            try { [void](Invoke-SelfUpdateMutation -SelfAction "RollbackTest") } finally { Exit-SpotifyControlMutex -Mutex $lease }
        }

        "RollbackSelfUpdate" {
            if (Test-SpotifyRunning) { throw "Spotify is running; self-update rollback requires Spotify to be fully closed." }
            $lease=Enter-SpotifyControlMutex -Purpose "Maintenance"
            if ($null -eq $lease) { throw "Another maintenance/check operation is already active." }
            try { [void](Invoke-SelfUpdateMutation -SelfAction "Rollback" -ForceSelf:$Force) } finally { Exit-SpotifyControlMutex -Mutex $lease }
        }

        "GuardUpdates" {
            if (Test-SpotifyRunning) {
                Write-Log "Spotify is running; Smart Update Guard mutation postponed until Spotify is closed." "WARN"
            } else {
                $state = Ensure-StateShape (Load-State)
                $guard = Invoke-SmartUpdateGuard -State $state
                if (-not $guard.Success) {
                    throw ("Smart Update Guard could not enforce the desired update state. desired={0}; enforced={1}; method={2}; patch={3}; acl={4}" -f `
                        $guard.Desired,
                        $guard.Enforced,
                        $guard.Method,
                        $guard.PatchCurrent,
                        $guard.AclCurrent
                    )
                }
            }
        }

        "Status" {
            Show-SpotifyControlStatus
        }

        "Audit" {
            if (-not (Test-UsablePath -Path $AuditScript -PathType "Leaf")) {
                throw "Audit script not found: $AuditScript"
            }

            $auditResult = Invoke-NativeCapture -FilePath (Join-Path $PSHOME "powershell.exe") -Arguments @(
                "-NoProfile",
                "-ExecutionPolicy","Bypass",
                "-File",$AuditScript
            )

            if ($auditResult.Output) { Write-Host $auditResult.Output }
            if ($auditResult.ExitCode -ne 0) {
                throw "Diagnostic collector returned exit code $($auditResult.ExitCode).`n$($auditResult.Output)"
            }
        }

        "Launch" {
            Launch-ManagedSpotify
        }
    }

    exit 0
}
catch {
    Write-Log $_.Exception.Message "ERROR"
    $errorPath = Write-ActionError -ActionName $Action -ErrorRecord $_
    if ($Host.Name -ne "Default Host") {
        Write-Host ""
        Write-Host "Spotify Control failed." -ForegroundColor Red
        Write-Host "Error log: $errorPath" -ForegroundColor Yellow
    }
    exit 1
}
