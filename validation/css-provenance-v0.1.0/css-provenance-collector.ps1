param(
    [ValidateSet('Collect','SelfTest')]
    [string]$Action = 'Collect',
    [string]$XpuiRoot,
    [string]$SpicetifyRoot,
    [string]$OutputRoot
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$Version = '0.1.0'

function Get-Sha256([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-FileIdentity([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{ exists = $false; size = $null; sha256 = $null }
    }
    $item = Get-Item -LiteralPath $Path
    return [pscustomobject]@{ exists = $true; size = [int64]$item.Length; sha256 = (Get-Sha256 $Path) }
}

function Get-TextEncodingInfo([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $bytes = [IO.File]::ReadAllBytes($Path)
    $bom = 'none'
    $offset = 0
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { $bom = 'utf8-bom'; $offset = 3 }
    elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { $bom = 'utf16le-bom'; $offset = 2 }
    elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) { $bom = 'utf16be-bom'; $offset = 2 }
    $crlf = 0; $lf = 0; $cr = 0
    for ($i = $offset; $i -lt $bytes.Length; $i++) {
        if ($bytes[$i] -eq 10) {
            if ($i -gt $offset -and $bytes[$i-1] -eq 13) { $crlf++ } else { $lf++ }
        } elseif ($bytes[$i] -eq 13) {
            if ($i + 1 -ge $bytes.Length -or $bytes[$i+1] -ne 10) { $cr++ }
        }
    }
    $lineEnding = if ($crlf -gt 0 -and $lf -eq 0 -and $cr -eq 0) { 'crlf' } elseif ($lf -gt 0 -and $crlf -eq 0 -and $cr -eq 0) { 'lf' } elseif ($crlf -eq 0 -and $lf -eq 0 -and $cr -eq 0) { 'none' } else { 'mixed' }
    return [pscustomobject]@{ bom = $bom; line_ending = $lineEnding; crlf_count = $crlf; lf_count = $lf; lone_cr_count = $cr }
}

function Read-TextBestEffort([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return (New-Object Text.UTF8Encoding($true, $true)).GetString($bytes, 3, $bytes.Length - 3)
    }
    try { return (New-Object Text.UTF8Encoding($false, $true)).GetString($bytes) }
    catch { return [Text.Encoding]::Default.GetString($bytes) }
}

function Normalize-PathForReport([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    $p = $Path
    foreach ($pair in @(
        [pscustomobject]@{ Value = $env:APPDATA; Token = '%APPDATA%' },
        [pscustomobject]@{ Value = $env:LOCALAPPDATA; Token = '%LOCALAPPDATA%' },
        [pscustomobject]@{ Value = $env:USERPROFILE; Token = '%USERPROFILE%' }
    )) {
        if (-not [string]::IsNullOrWhiteSpace([string]$pair.Value) -and $p.StartsWith([string]$pair.Value, [StringComparison]::OrdinalIgnoreCase)) {
            return [string]$pair.Token + $p.Substring(([string]$pair.Value).Length)
        }
    }
    return $p
}

function Get-IniThemeSettings([string]$ConfigPath) {
    $wanted = @('current_theme','color_scheme','inject_css','replace_colors','overwrite_assets')
    $result = @{}
    foreach ($k in $wanted) { $result[$k] = $null }
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { return $result }
    $section = ''
    foreach ($line in (Get-Content -LiteralPath $ConfigPath -ErrorAction Stop)) {
        $trim = $line.Trim()
        if ($trim -match '^\[(.+)\]$') { $section = $Matches[1]; continue }
        if ($section -ne 'Setting' -or $trim.StartsWith(';') -or $trim.StartsWith('#') -or $trim.IndexOf('=') -lt 0) { continue }
        $eq = $trim.IndexOf('=')
        $key = $trim.Substring(0,$eq).Trim(); $value = $trim.Substring($eq+1).Trim()
        if ($wanted -contains $key) { $result[$key] = $value }
    }
    return $result
}

function Get-CssStaticStats([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $text = Read-TextBestEffort $Path
    if ($null -eq $text) { return $null }
    function Count-Re([string]$Pattern) { return [regex]::Matches($text, $Pattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase).Count }
    $lines = $text -split "`r?`n"
    $hot = New-Object Collections.Generic.List[object]
    $hotPatterns = @(
        [pscustomobject]@{ name='backdrop-filter'; pattern='(?i)\b(?:-webkit-)?backdrop-filter\s*:' },
        [pscustomobject]@{ name='filter'; pattern='(?i)(?<!backdrop-)\bfilter\s*:' },
        [pscustomobject]@{ name='box-shadow'; pattern='(?i)\bbox-shadow\s*:' },
        [pscustomobject]@{ name='text-shadow'; pattern='(?i)\btext-shadow\s*:' },
        [pscustomobject]@{ name='animation'; pattern='(?i)\banimation(?:-[\w-]+)?\s*:' },
        [pscustomobject]@{ name='transition'; pattern='(?i)\btransition(?:-[\w-]+)?\s*:' },
        [pscustomobject]@{ name='position-fixed'; pattern='(?i)\bposition\s*:\s*fixed\b' },
        [pscustomobject]@{ name='has-selector'; pattern='(?i):has\s*\(' }
    )
    for ($i = 0; $i -lt $lines.Count; $i++) {
        foreach ($hp in $hotPatterns) {
            if ($lines[$i] -match $hp.pattern) {
                $sample = $lines[$i].Trim()
                if ($sample.Length -gt 220) { $sample = $sample.Substring(0,220) }
                $hot.Add([pscustomobject]@{ line = $i + 1; kind = $hp.name; sample = $sample })
            }
        }
    }
    return [pscustomobject]@{
        bytes = [int64](Get-Item -LiteralPath $Path).Length
        line_count = $lines.Count
        block_open_count = Count-Re '\{'
        important_count = Count-Re '!important\b'
        universal_selector_count = Count-Re '(?m)(^|,|\s)\*\s*(?:[\.#:\[,>+~]|\{)'
        has_selector_count = Count-Re ':has\s*\('
        nth_selector_count = Count-Re ':nth-(?:child|last-child|of-type|last-of-type)\s*\('
        attribute_selector_count = Count-Re '\[[^\]]+\]'
        hover_selector_count = Count-Re ':hover\b'
        backdrop_filter_count = Count-Re '\b(?:-webkit-)?backdrop-filter\s*:'
        filter_property_count = Count-Re '(?<!backdrop-)\bfilter\s*:'
        box_shadow_count = Count-Re '\bbox-shadow\s*:'
        text_shadow_count = Count-Re '\btext-shadow\s*:'
        transition_count = Count-Re '\btransition(?:-[\w-]+)?\s*:'
        animation_count = Count-Re '\banimation(?:-[\w-]+)?\s*:'
        keyframes_count = Count-Re '@(?:-webkit-)?keyframes\b'
        fixed_position_count = Count-Re '\bposition\s*:\s*fixed\b'
        sticky_position_count = Count-Re '\bposition\s*:\s*sticky\b'
        media_query_count = Count-Re '@media\b'
        supports_query_count = Count-Re '@supports\b'
        url_count = Count-Re 'url\s*\('
        hot_line_count = $hot.Count
        hot_lines = $hot.ToArray()
    }
}

function Get-SourceFingerprint([string[]]$Paths) {
    $rows = New-Object Collections.Generic.List[object]
    foreach ($p in ($Paths | Sort-Object -Unique)) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        if (Test-Path -LiteralPath $p -PathType Leaf) {
            $item = Get-Item -LiteralPath $p
            $rows.Add([pscustomobject]@{ path = $p; size = [int64]$item.Length; sha256 = Get-Sha256 $p })
        }
    }
    return @($rows.ToArray())
}

function Assert-FingerprintEqual($Before, $After) {
    $a = @($Before | Sort-Object path | ForEach-Object { "$($_.path)|$($_.size)|$($_.sha256)" })
    $b = @($After | Sort-Object path | ForEach-Object { "$($_.path)|$($_.size)|$($_.sha256)" })
    if (($a -join "`n") -cne ($b -join "`n")) { throw 'Read-only safety failure: one or more source files changed during collection.' }
}

function Copy-ExactIfPresent([string]$Source,[string]$Destination) {
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { return $false }
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
    if ((Get-Sha256 $Source) -cne (Get-Sha256 $Destination)) { throw "Exact capture verification failed: $Source" }
    return $true
}

function Write-Utf8NoBom([string]$Path,[string]$Text) {
    [IO.File]::WriteAllBytes($Path, (New-Object Text.UTF8Encoding($false)).GetBytes($Text))
}

function New-CaptureZip([string]$SourceDir,[string]$ZipPath) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (Test-Path -LiteralPath $ZipPath) { Remove-Item -LiteralPath $ZipPath -Force }
    [IO.Compression.ZipFile]::CreateFromDirectory($SourceDir, $ZipPath, [IO.Compression.CompressionLevel]::Optimal, $false)
}

function Collect-CssProvenance([string]$ResolvedXpui,[string]$ResolvedSpicetify,[string]$ResolvedOutput,[string]$SessionName) {
    if (-not (Test-Path -LiteralPath $ResolvedXpui -PathType Container)) { throw "Active xpui folder not found: $ResolvedXpui" }
    if (-not (Test-Path -LiteralPath $ResolvedSpicetify -PathType Container)) { throw "Spicetify config folder not found: $ResolvedSpicetify" }
    New-Item -ItemType Directory -Force -Path $ResolvedOutput | Out-Null
    $session = Join-Path $ResolvedOutput $SessionName
    $capture = Join-Path $session 'capture'
    New-Item -ItemType Directory -Force -Path $capture | Out-Null

    $config = Join-Path $ResolvedSpicetify 'config-xpui.ini'
    $index = Join-Path $ResolvedXpui 'index.html'
    $activeUser = Join-Path $ResolvedXpui 'user.css'
    $activeColors = Join-Path $ResolvedXpui 'colors.css'
    $settings = Get-IniThemeSettings $config
    $themeName = [string]$settings['current_theme']
    $scheme = [string]$settings['color_scheme']
    $themeDir = if ([string]::IsNullOrWhiteSpace($themeName)) { $null } else { Join-Path (Join-Path $ResolvedSpicetify 'Themes') $themeName }
    $themeUser = if ($themeDir) { Join-Path $themeDir 'user.css' } else { $null }
    $themeColor = if ($themeDir) { Join-Path $themeDir 'color.ini' } else { $null }

    $sourcePaths = @($config,$index,$activeUser,$activeColors,$themeUser,$themeColor)
    $before = Get-SourceFingerprint $sourcePaths

    $captured = [ordered]@{}
    $captured['active_user_css'] = Copy-ExactIfPresent $activeUser (Join-Path $capture 'active-user.css')
    $captured['active_colors_css'] = Copy-ExactIfPresent $activeColors (Join-Path $capture 'active-colors.css')
    $captured['theme_user_css'] = if ($themeUser) { Copy-ExactIfPresent $themeUser (Join-Path $capture 'theme-user.css') } else { $false }
    $captured['theme_color_ini'] = if ($themeColor) { Copy-ExactIfPresent $themeColor (Join-Path $capture 'theme-color.ini') } else { $false }

    $indexMatches = New-Object Collections.Generic.List[string]
    if (Test-Path -LiteralPath $index -PathType Leaf) {
        $indexText = Read-TextBestEffort $index
        foreach ($line in ($indexText -split "`r?`n")) {
            if ($line -match '(?i)(user\.css|colors\.css)') {
                $safe = $line.Trim()
                if ($safe.Length -gt 2000) { $safe = $safe.Substring(0,2000) }
                $indexMatches.Add($safe)
            }
        }
    }
    Write-Utf8NoBom (Join-Path $capture 'index-css-links.txt') ((@($indexMatches.ToArray()) -join "`r`n") + $(if($indexMatches.Count){"`r`n"}else{''}))

    $settingLines = @(
        "current_theme=$($settings['current_theme'])",
        "color_scheme=$($settings['color_scheme'])",
        "inject_css=$($settings['inject_css'])",
        "replace_colors=$($settings['replace_colors'])",
        "overwrite_assets=$($settings['overwrite_assets'])"
    )
    Write-Utf8NoBom (Join-Path $capture 'spicetify-theme-settings.txt') (($settingLines -join "`r`n") + "`r`n")

    $activeUserId = Get-FileIdentity $activeUser
    $activeColorsId = Get-FileIdentity $activeColors
    $themeUserId = if ($themeUser) { Get-FileIdentity $themeUser } else { [pscustomobject]@{exists=$false;size=$null;sha256=$null} }
    $themeColorId = if ($themeColor) { Get-FileIdentity $themeColor } else { [pscustomobject]@{exists=$false;size=$null;sha256=$null} }
    $userExactMatch = [bool]($activeUserId.exists -and $themeUserId.exists -and $activeUserId.sha256 -ceq $themeUserId.sha256 -and $activeUserId.size -eq $themeUserId.size)

    $productionRoot = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'SpotifyControl' } else { $null }
    $production = [ordered]@{}
    foreach ($row in @(
        [pscustomobject]@{ key='spotify_control'; rel='bin\spotify-control.ps1' },
        [pscustomobject]@{ key='addon_manager'; rel='bin\addon-manager.ps1' },
        [pscustomobject]@{ key='resident_agent'; rel='bin\spotify-control-agent.vbs' },
        [pscustomobject]@{ key='bootstrap'; rel='bootstrap\spotify-control-self-updater.ps1' }
    )) {
        $p = if ($productionRoot) { Join-Path $productionRoot $row.rel } else { $null }
        $id = if ($p) { Get-FileIdentity $p } else { [pscustomobject]@{exists=$false;size=$null;sha256=$null} }
        $production[$row.key] = $id
    }

    $report = [ordered]@{
        schema = 1
        collector_version = $Version
        generated_at = (Get-Date).ToString('o')
        read_only_source_contract = $true
        spotify_process_control_used = $false
        spicetify_command_used = $false
        active_xpui = Normalize-PathForReport $ResolvedXpui
        spicetify_root = Normalize-PathForReport $ResolvedSpicetify
        theme = [ordered]@{
            current_theme = $settings['current_theme']
            color_scheme = $settings['color_scheme']
            inject_css = $settings['inject_css']
            replace_colors = $settings['replace_colors']
            overwrite_assets = $settings['overwrite_assets']
            theme_directory = Normalize-PathForReport $themeDir
        }
        active = [ordered]@{
            user_css = [ordered]@{ path = Normalize-PathForReport $activeUser; identity = $activeUserId; encoding = Get-TextEncodingInfo $activeUser; static = Get-CssStaticStats $activeUser }
            colors_css = [ordered]@{ path = Normalize-PathForReport $activeColors; identity = $activeColorsId; encoding = Get-TextEncodingInfo $activeColors; static = Get-CssStaticStats $activeColors }
            index_html = [ordered]@{ path = Normalize-PathForReport $index; identity = Get-FileIdentity $index; css_link_match_count = $indexMatches.Count }
        }
        source_theme = [ordered]@{
            user_css = [ordered]@{ path = Normalize-PathForReport $themeUser; identity = $themeUserId; encoding = if($themeUser){Get-TextEncodingInfo $themeUser}else{$null}; static = if($themeUser){Get-CssStaticStats $themeUser}else{$null} }
            color_ini = [ordered]@{ path = Normalize-PathForReport $themeColor; identity = $themeColorId; encoding = if($themeColor){Get-TextEncodingInfo $themeColor}else{$null} }
            active_user_css_exact_match = $userExactMatch
        }
        capture = $captured
        production_components = $production
        privacy = [ordered]@{
            config_full_copy_included = $false
            browser_default_read = $false
            users_read = $false
            prefs_read = $false
            local_storage_read = $false
            indexeddb_read = $false
            extension_payloads_read = $false
            star_ratings_data_read = $false
        }
    }

    $jsonPath = Join-Path $capture 'css-provenance-v010.json'
    Write-Utf8NoBom $jsonPath (($report | ConvertTo-Json -Depth 30) + "`r`n")

    $txt = New-Object Collections.Generic.List[string]
    $txt.Add('Spotify Control CSS Provenance Collector v0.1.0')
    $txt.Add('===============================================')
    $txt.Add("Generated: $($report.generated_at)")
    $txt.Add('Mode: read-only source capture; Spotify/Spicetify were not modified or restarted.')
    $txt.Add('')
    $txt.Add("Active xpui: $($report.active_xpui)")
    $txt.Add("Theme: $($settings['current_theme']) | color scheme: $($settings['color_scheme']) | inject_css=$($settings['inject_css']) | replace_colors=$($settings['replace_colors'])")
    $txt.Add("Active user.css: exists=$($activeUserId.exists) size=$($activeUserId.size) sha256=$($activeUserId.sha256)")
    $txt.Add("Active colors.css: exists=$($activeColorsId.exists) size=$($activeColorsId.size) sha256=$($activeColorsId.sha256)")
    $txt.Add("Theme user.css: exists=$($themeUserId.exists) size=$($themeUserId.size) sha256=$($themeUserId.sha256) exact-active-match=$userExactMatch")
    $txt.Add("Theme color.ini: exists=$($themeColorId.exists) size=$($themeColorId.size) sha256=$($themeColorId.sha256)")
    $txt.Add("index.html user.css/colors.css matching line count: $($indexMatches.Count)")
    $txt.Add('')
    if ($report.active.user_css.static) {
        $s=$report.active.user_css.static
        $txt.Add("user.css static: lines=$($s.line_count) blocks=$($s.block_open_count) important=$($s.important_count) has=$($s.has_selector_count) nth=$($s.nth_selector_count) attributes=$($s.attribute_selector_count) backdrop-filter=$($s.backdrop_filter_count) filter=$($s.filter_property_count) box-shadow=$($s.box_shadow_count) transition=$($s.transition_count) animation=$($s.animation_count) fixed=$($s.fixed_position_count) hot-lines=$($s.hot_line_count)")
    }
    if ($report.active.colors_css.static) {
        $s=$report.active.colors_css.static
        $txt.Add("colors.css static: lines=$($s.line_count) blocks=$($s.block_open_count) important=$($s.important_count) filters=$($s.filter_property_count) shadows=$($s.box_shadow_count) transition=$($s.transition_count) animation=$($s.animation_count)")
    }
    $txt.Add('')
    $txt.Add('Captured exact files are stored in this archive when present: active-user.css, active-colors.css, theme-user.css, theme-color.ini.')
    $txt.Add('Only theme-related config values and index.html lines mentioning user.css/colors.css are included; full config/profile/persistence data is not included.')
    Write-Utf8NoBom (Join-Path $capture 'css-provenance-v010.txt') (($txt.ToArray() -join "`r`n") + "`r`n")

    $manifest = New-Object Collections.Generic.List[string]
    Get-ChildItem -LiteralPath $capture -File | Sort-Object Name | ForEach-Object {
        $manifest.Add("$((Get-Sha256 $_.FullName))  $($_.Name)")
    }
    Write-Utf8NoBom (Join-Path $capture 'SHA256SUMS.txt') (($manifest.ToArray() -join "`r`n") + "`r`n")

    $after = Get-SourceFingerprint $sourcePaths
    Assert-FingerprintEqual $before $after

    $zip = Join-Path $session 'SpotifyControl-CSS-Provenance-v0.1.0.zip'
    New-CaptureZip $capture $zip
    $latestZip = Join-Path $ResolvedOutput 'SpotifyControl-CSS-Provenance-v0.1.0-latest.zip'
    $latestTxt = Join-Path $ResolvedOutput 'css-provenance-v010-latest.txt'
    $latestJson = Join-Path $ResolvedOutput 'css-provenance-v010-latest.json'
    Copy-Item -LiteralPath $zip -Destination $latestZip -Force
    Copy-Item -LiteralPath (Join-Path $capture 'css-provenance-v010.txt') -Destination $latestTxt -Force
    Copy-Item -LiteralPath $jsonPath -Destination $latestJson -Force

    return [pscustomobject]@{
        status = 'collected'
        session = $session
        zip = $zip
        latest_zip = $latestZip
        latest_txt = $latestTxt
        latest_json = $latestJson
        user_css_sha256 = $activeUserId.sha256
        colors_css_sha256 = $activeColorsId.sha256
        theme_user_exact_match = $userExactMatch
        source_unchanged = $true
    }
}

function Invoke-SelfTest {
    $root = Join-Path ([IO.Path]::GetTempPath()) ('spotify-control-css-prov-' + [Guid]::NewGuid().ToString('N'))
    $xpui = Join-Path $root 'Roaming\Spotify\Apps\xpui'
    $spice = Join-Path $root 'Roaming\spicetify'
    $theme = Join-Path $spice 'Themes\TestTheme'
    $out = Join-Path $root 'out'
    New-Item -ItemType Directory -Force -Path $xpui,$theme,$out | Out-Null
    $user = "/* synthetic user css */`r`n.main-view-container { backdrop-filter: blur(8px); box-shadow: 0 0 10px #000; transition: all .2s; }`r`n.main-rootlist-rootlistItem:hover { filter: brightness(1.1); }`r`n"
    $colors = ":root {`n --spice-main: #121212;`n --spice-rgb-main: 18,18,18;`n}`n"
    [IO.File]::WriteAllText((Join-Path $xpui 'user.css'),$user,(New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText((Join-Path $xpui 'colors.css'),$colors,(New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText((Join-Path $theme 'user.css'),$user,(New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText((Join-Path $theme 'color.ini'),"[Test]`r`nmain = 121212`r`n",(New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText((Join-Path $xpui 'index.html'),'<html><head><link rel="stylesheet" href="colors.css"><link rel="stylesheet" href="user.css"></head><body></body></html>',(New-Object Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText((Join-Path $spice 'config-xpui.ini'),"[Setting]`r`nspotify_path = C:\\secret\\spotify`r`nprefs_path = C:\\secret\\prefs`r`ncurrent_theme = TestTheme`r`ncolor_scheme = Test`r`ninject_css = 1`r`nreplace_colors = 1`r`noverwrite_assets = 0`r`n[AdditionalOptions]`r`nextensions = secret.js`r`ncustom_apps = secret-app`r`n",(New-Object Text.UTF8Encoding($false)))
    $sources = Get-ChildItem -LiteralPath (Join-Path $root 'Roaming') -Recurse -File | ForEach-Object { [pscustomobject]@{path=$_.FullName;size=$_.Length;sha256=Get-Sha256 $_.FullName} }
    try {
        $result = Collect-CssProvenance $xpui $spice $out 'selftest'
        $after = Get-ChildItem -LiteralPath (Join-Path $root 'Roaming') -Recurse -File | ForEach-Object { [pscustomobject]@{path=$_.FullName;size=$_.Length;sha256=Get-Sha256 $_.FullName} }
        Assert-FingerprintEqual $sources $after
        if (-not (Test-Path -LiteralPath $result.zip -PathType Leaf)) { throw 'SelfTest capture ZIP missing.' }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $z=[IO.Compression.ZipFile]::OpenRead($result.zip)
        try {
            $names=@($z.Entries|ForEach-Object{$_.FullName})
            foreach($required in @('active-user.css','active-colors.css','theme-user.css','theme-color.ini','index-css-links.txt','spicetify-theme-settings.txt','css-provenance-v010.json','css-provenance-v010.txt','SHA256SUMS.txt')){if($names -notcontains $required){throw "SelfTest archive missing $required"}}
            $bad=@($names|Where-Object{$_ -match '(?i)config-xpui\.ini|prefs|browser|default|indexeddb|local storage|extensions/'})
            if($bad.Count){throw "SelfTest privacy surface leaked into archive: $($bad -join ', ')"}
        } finally {$z.Dispose()}
        $j=Get-Content -LiteralPath $result.latest_json -Raw|ConvertFrom-Json
        if(-not $j.read_only_source_contract -or $j.spotify_process_control_used -or $j.spicetify_command_used){throw 'SelfTest read-only contract mismatch.'}
        if($j.theme.current_theme -ne 'TestTheme' -or $j.theme.color_scheme -ne 'Test' -or -not $j.source_theme.active_user_css_exact_match){throw 'SelfTest provenance mismatch.'}
        if([int]$j.active.user_css.static.backdrop_filter_count -ne 1 -or [int]$j.active.user_css.static.box_shadow_count -ne 1 -or [int]$j.active.user_css.static.transition_count -ne 1){throw 'SelfTest CSS static analysis mismatch.'}
        $txt=Get-Content -LiteralPath $result.latest_txt -Raw
        foreach($secret in @('C:\secret\spotify','C:\secret\prefs','secret.js','secret-app')){if($txt.IndexOf($secret,[StringComparison]::OrdinalIgnoreCase)-ge0){throw "SelfTest leaked non-theme config value: $secret"}}
        Write-Host 'CSS_PROVENANCE_SELFTEST_PASS'
    } finally {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($Action -eq 'SelfTest') { Invoke-SelfTest; exit 0 }
if (-not $env:APPDATA) { throw 'APPDATA is unavailable.' }
if (-not $env:LOCALAPPDATA -and [string]::IsNullOrWhiteSpace($OutputRoot)) { throw 'LOCALAPPDATA is unavailable.' }
if ([string]::IsNullOrWhiteSpace($XpuiRoot)) { $XpuiRoot = Join-Path $env:APPDATA 'Spotify\Apps\xpui' }
if ([string]::IsNullOrWhiteSpace($SpicetifyRoot)) { $SpicetifyRoot = Join-Path $env:APPDATA 'spicetify' }
if ([string]::IsNullOrWhiteSpace($OutputRoot)) { $OutputRoot = Join-Path $env:LOCALAPPDATA 'SpotifyControl\reports\css-provenance-v010' }
$sessionName = Get-Date -Format 'yyyyMMdd-HHmmss'
$result = Collect-CssProvenance $XpuiRoot $SpicetifyRoot $OutputRoot $sessionName
Write-Host ''
Write-Host 'CSS PROVENANCE CAPTURE VERIFIED' -ForegroundColor Green
Write-Host ("Archive: " + $result.latest_zip)
Write-Host ("Report:  " + $result.latest_txt)
Write-Host ("JSON:    " + $result.latest_json)
Write-Host ("user.css SHA-256:   " + $result.user_css_sha256)
Write-Host ("colors.css SHA-256: " + $result.colors_css_sha256)
Write-Host ("Theme user.css exact active match: " + $result.theme_user_exact_match)
Write-Host 'Spotify/Spicetify source files were re-hashed after capture and remained unchanged.'
