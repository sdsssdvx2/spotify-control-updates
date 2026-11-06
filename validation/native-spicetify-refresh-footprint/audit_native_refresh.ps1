# Official Spicetify native scoped-refresh behavior, CI-only proof.
# Never run on a real Spotify installation or a developer's workstation.
# This test verifies surprising upstream CLI semantics before we choose a
# production apply/refresh strategy; it grants NO execution authority.
param([Parameter(Mandatory=$true)][string]$OfficialExecutable)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
    throw 'NATIVE_REFRESH_AUDIT_GITHUB_HOSTED_WINDOWS_ONLY'
}
$runner=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
$exe=[IO.Path]::GetFullPath($OfficialExecutable)
if(-not $exe.StartsWith(($runner+'\'),[StringComparison]::OrdinalIgnoreCase) -or
   -not[IO.File]::Exists($exe) -or
   (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant() -cne
   '3563f26acd7527adc97e6c19272fa1b48ce976a913625d9804ac57d3c54fb4db'){
    throw 'NATIVE_REFRESH_AUDIT_OFFICIAL_EXE_SHA_MISMATCH'
}
$sandboxRoot=Join-Path $env:RUNNER_TEMP ('native-refresh-audit-'+[guid]::NewGuid().ToString('N'))
$roaming=Join-Path $sandboxRoot 'Roaming';$local=Join-Path $sandboxRoot 'Local'
$user=Join-Path $sandboxRoot 'User';$spicetify=Join-Path $roaming 'spicetify'
$spotify=Join-Path $sandboxRoot 'FakeSpotify';$apps=Join-Path $spotify 'Apps'
$xpui=Join-Path $apps 'xpui'
$backup=Join-Path $spicetify 'Backup'
$custom=Join-Path $spicetify 'CustomApps'
$prefs=Join-Path $sandboxRoot 'prefs'
$config=Join-Path $spicetify 'config-xpui.ini'
foreach($dir in @($sandboxRoot,$roaming,$local,$user,$spicetify,$spotify,$apps,$xpui,$backup,$custom,(Join-Path $custom 'alpha'),(Join-Path $custom 'beta'))){
    [void][IO.Directory]::CreateDirectory($dir)
}
$env:APPDATA=$roaming
$env:LOCALAPPDATA=$local
$env:HOME=$user
$env:USERPROFILE=$user
Remove-Item Env:SPICETIFY_CONFIG,Env:SPICETIFY_STATE -ErrorAction SilentlyContinue
[IO.File]::WriteAllText($prefs,'app.last-launched-version = 1.2.3'+[Environment]::NewLine,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllBytes((Join-Path $backup 'xpui.spa'),[byte[]](0x50,0x4b))
[IO.File]::WriteAllText((Join-Path $xpui 'unchanged-user-resource.dat'),'unchanged protected sentinel',[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $custom 'alpha\index.js'),'console.log("ALPHA_V1");',[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $custom 'beta\index.js'),'console.log("BETA_V1");',[Text.UTF8Encoding]::new($false))
$alphaJS=Join-Path $xpui 'spicetify-routes-alpha.js'
$betaJS=Join-Path $xpui 'spicetify-routes-beta.js'
$sentinel=Join-Path $xpui 'unchanged-user-resource.dat'
$sentinelSha=(Get-FileHash -LiteralPath $sentinel -Algorithm SHA256).Hash
function Set-SyntheticConfig([string]$Apps){
    # Synthetic paths are confined to RUNNER_TEMP; this is not the user's profile.
    $cfg=('[Setting]'+[Environment]::NewLine+
        'spotify_path = '+$spotify+[Environment]::NewLine+
        'prefs_path = '+$prefs+[Environment]::NewLine+
        'check_spicetify_update = false'+[Environment]::NewLine+
        'current_theme = '+[Environment]::NewLine+
        '[Backup]'+[Environment]::NewLine+
        'version = 1.2.3'+[Environment]::NewLine+
        'with = 2.46.4'+[Environment]::NewLine+
        '[AdditionalOptions]'+[Environment]::NewLine+
        'custom_apps = '+$Apps+[Environment]::NewLine)
    [IO.File]::WriteAllText($config,$cfg,[Text.UTF8Encoding]::new($false))
}
function Invoke-SyntheticRefresh([string[]]$Arguments,[string]$LogName){
    $log=Join-Path $sandboxRoot $LogName
    $errs=Join-Path $sandboxRoot ($LogName+'.err')
    $p=New-Object System.Diagnostics.ProcessStartInfo
    $p.FileName=$exe;$p.WorkingDirectory=$sandboxRoot
    $p.UseShellExecute=$false;$p.CreateNoWindow=$true
    $p.RedirectStandardOutput=$true;$p.RedirectStandardError=$true
    # PowerShell 5.1 StartInfo.Arguments does not support ArgumentList.
    # GitHub hosted runner may run with an elevated token. Bypass admin only
    # against disposable synthetic Spotify fixture under RUNNER_TEMP.
    $p.Arguments=('--bypass-admin '+($Arguments -join ' '))
    $proc=New-Object Diagnostics.Process;$proc.StartInfo=$p
    if(-not$proc.Start()){throw 'NATIVE_REFRESH_AUDIT_PROCESS_START_FALSE'}
    try{
        $stdout=$proc.StandardOutput.ReadToEnd()
        $stderr=$proc.StandardError.ReadToEnd()
        if(-not$proc.WaitForExit(30000)){
            $proc.Kill();throw 'NATIVE_REFRESH_AUDIT_PROCESS_TIMEOUT'
        }
        # Avoid printing logs or user-profile filenames. Synthetic logs only.
        [IO.File]::WriteAllText($log,$stdout)
        [IO.File]::WriteAllText($errs,$stderr)
        return [pscustomobject]@{exit_code=[int]$proc.ExitCode;output=($stdout+$stderr)}
    }finally{$proc.Dispose()}
}
Set-SyntheticConfig -Apps 'alpha|beta'
$first=Invoke-SyntheticRefresh -Arguments @('-a','refresh') -LogName 'both-refresh.log'
if($first.exit_code -ne 0 -or -not[IO.File]::Exists($alphaJS) -or
   -not[IO.File]::Exists($betaJS) -or
   -not[IO.File]::ReadAllText($alphaJS).Contains('ALPHA_V1') -or
   -not[IO.File]::ReadAllText($betaJS).Contains('BETA_V1')){
    throw ('NATIVE_REFRESH_AUDIT_BOTH_APPS_NOT_RENDERED exit='+$first.exit_code)
}
$bothAlphaSha=(Get-FileHash -LiteralPath $alphaJS -Algorithm SHA256).Hash
$bothBetaSha=(Get-FileHash -LiteralPath $betaJS -Algorithm SHA256).Hash
if((Get-FileHash -LiteralPath $sentinel -Algorithm SHA256).Hash -cne $sentinelSha){
    throw 'NATIVE_REFRESH_AUDIT_SENTINEL_MUTATED'
}
Write-Host 'NATIVE_REFRESH_REAL_OFFICIAL_TWO_ENABLED_APPS_BOTH_REFRESHED_PASS'

[IO.File]::Delete((Join-Path $custom 'beta\index.js'))
[IO.File]::WriteAllText((Join-Path $custom 'alpha\index.js'),'console.log("ALPHA_V2");',[Text.UTF8Encoding]::new($false))
$missing=Invoke-SyntheticRefresh -Arguments @('-a','refresh') -LogName 'missing-beta.log'
if($missing.exit_code -ne 0 -or
   (Get-FileHash -LiteralPath $alphaJS -Algorithm SHA256).Hash -ceq $bothAlphaSha -or
   (Get-FileHash -LiteralPath $betaJS -Algorithm SHA256).Hash -cne $bothBetaSha){
    throw ('NATIVE_REFRESH_AUDIT_PARTIAL_FAILURE_NOT_OBSERVED exit='+$missing.exit_code)
}
Write-Host 'NATIVE_REFRESH_REAL_OFFICIAL_PARTIAL_FAILURE_EXIT_ZERO_PASS'

[IO.File]::WriteAllText((Join-Path $custom 'beta\index.js'),'console.log("BETA_V2");',[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $custom 'alpha\index.js'),'console.log("ALPHA_V3");',[Text.UTF8Encoding]::new($false))
$oldAlphaHash=(Get-FileHash -LiteralPath $alphaJS -Algorithm SHA256).Hash
$oldBetaHash=(Get-FileHash -LiteralPath $betaJS -Algorithm SHA256).Hash
$misleading=Invoke-SyntheticRefresh -Arguments @('-a','refresh','alpha') -LogName 'misleading-target.log'
if($misleading.exit_code -eq 0 -or
   (Get-FileHash -LiteralPath $alphaJS -Algorithm SHA256).Hash -ceq $oldAlphaHash -or
   (Get-FileHash -LiteralPath $betaJS -Algorithm SHA256).Hash -ceq $oldBetaHash){
    throw ('NATIVE_REFRESH_AUDIT_TARGET_ARGUMENT_NOT_SIDE_EFFECT_BEFORE_ERROR exit='+$misleading.exit_code)
}
Write-Host 'NATIVE_REFRESH_REAL_OFFICIAL_TARGET_ARGUMENT_SIDE_EFFECT_BEFORE_ERROR_PASS'

Set-SyntheticConfig -Apps 'alpha'
[IO.File]::WriteAllText((Join-Path $custom 'alpha\index.js'),'console.log("ALPHA_V4");',[Text.UTF8Encoding]::new($false))
$oldBetaHash=(Get-FileHash -LiteralPath $betaJS -Algorithm SHA256).Hash
$targetOnly=Invoke-SyntheticRefresh -Arguments @('-a','refresh') -LogName 'single-configured.log'
if($targetOnly.exit_code -ne 0 -or
   -not[IO.File]::ReadAllText($alphaJS).Contains('ALPHA_V4') -or
   (Get-FileHash -LiteralPath $betaJS -Algorithm SHA256).Hash -cne $oldBetaHash){
    throw ('NATIVE_REFRESH_AUDIT_SINGLE_CONFIGURED_SCOPE_CHANGED_OTHERS exit='+$targetOnly.exit_code)
}
if((Get-FileHash -LiteralPath $sentinel -Algorithm SHA256).Hash -cne $sentinelSha){
    throw 'NATIVE_REFRESH_AUDIT_PROTECTED_SENTINEL_CHANGED'
}
Write-Host 'NATIVE_REFRESH_REAL_OFFICIAL_SINGLE_CONFIGURED_APP_NARROW_REFRESH_PASS'

# A disposable configuration + source + backup clone can narrow the real
# upstream native refresh WITHOUT changing the canonical user's config.
# This is still hosted-only and is not an execution permit for actual Spotify.
Set-SyntheticConfig -Apps 'alpha|beta'
$userConfigHash=(Get-FileHash -LiteralPath $config -Algorithm SHA256).Hash
$userAlphaHash=(Get-FileHash -LiteralPath (Join-Path $custom 'alpha\index.js') -Algorithm SHA256).Hash
$scoped=Join-Path $sandboxRoot 'ScopedConfig'
$scopedApp=Join-Path $scoped 'CustomApps\alpha'
$scopedBackup=Join-Path $scoped 'Backup'
foreach($d in @($scoped,$scopedApp,$scopedBackup)){
    [void][IO.Directory]::CreateDirectory($d)
}
[IO.File]::WriteAllBytes((Join-Path $scopedBackup 'xpui.spa'),[byte[]](0x50,0x4b))
[IO.File]::WriteAllText((Join-Path $scopedApp 'index.js'),
    'console.log("ALPHA_SCOPED_V5");',[Text.UTF8Encoding]::new($false))
$scopedCfg=Join-Path $scoped 'config-xpui.ini'
$text=[IO.File]::ReadAllText($config)
if($text.Split('custom_apps = alpha|beta').Length -ne 2){
    throw 'NATIVE_REFRESH_SCOPE_SOURCE_CONFIG_NOT_SINGLE_ANCHOR'
}
[IO.File]::WriteAllText($scopedCfg,$text.Replace('custom_apps = alpha|beta',
    'custom_apps = alpha'),[Text.UTF8Encoding]::new($false))
$pre=@{}
foreach($entry in @(Get-ChildItem -LiteralPath $xpui -File -Recurse -ErrorAction Stop)){
    $pre[$entry.FullName]=[pscustomobject]@{
        content=[IO.File]::ReadAllBytes($entry.FullName)
        sha=(Get-FileHash -LiteralPath $entry.FullName -Algorithm SHA256).Hash
    }
}
$betaPrior=(Get-FileHash -LiteralPath $betaJS -Algorithm SHA256).Hash
$alphaPrior=(Get-FileHash -LiteralPath $alphaJS -Algorithm SHA256).Hash
$env:SPICETIFY_CONFIG=$scoped
$env:SPICETIFY_STATE=$scoped
try{
    $scopedResult=Invoke-SyntheticRefresh -Arguments @('-a','refresh') -LogName 'isolated-scoped-refresh.log'
}finally{
    Remove-Item Env:SPICETIFY_CONFIG,Env:SPICETIFY_STATE -ErrorAction SilentlyContinue
}
if($scopedResult.exit_code -ne 0 -or
   -not[IO.File]::ReadAllText($alphaJS).Contains('ALPHA_SCOPED_V5') -or
   (Get-FileHash -LiteralPath $alphaJS -Algorithm SHA256).Hash -ceq $alphaPrior -or
   (Get-FileHash -LiteralPath $betaJS -Algorithm SHA256).Hash -cne $betaPrior -or
   (Get-FileHash -LiteralPath $config -Algorithm SHA256).Hash -cne $userConfigHash -or
   (Get-FileHash -LiteralPath (Join-Path $custom 'alpha\index.js') -Algorithm SHA256).Hash -cne $userAlphaHash){
    throw 'NATIVE_REFRESH_SCOPED_CLONED_PROFILE_NOT_CONFINED'
}
$postFiles=@(Get-ChildItem -LiteralPath $xpui -File -Recurse -ErrorAction Stop)
$allowed=@($alphaJS,(Join-Path $xpui 'spicetify-routes-alpha.json'),(Join-Path $xpui 'spicetify-routes-alpha.css'))
foreach($entry in $postFiles){
    if($entry.FullName -notin $allowed){
        if(-not$pre.ContainsKey($entry.FullName) -or
           (Get-FileHash -LiteralPath $entry.FullName -Algorithm SHA256).Hash -cne [string]$pre[$entry.FullName].sha){
            throw 'NATIVE_REFRESH_CLONED_PROFILE_OUTSIDE_APP_OUTPUT_CHANGED'
        }
    }
}
Write-Host 'NATIVE_REFRESH_OFFICIAL_CLONED_CONFIG_SINGLE_APP_SOURCE_PROFILE_CONFINE_PASS'
# Explicitly simulate post-apply rejection, restore every managed target artifact
# to its byte-for-byte pre-apply contents, and check every unrelated artifact.
foreach($path in $allowed){
    if($pre.ContainsKey($path)){
        [IO.File]::WriteAllBytes($path,[byte[]]$pre[$path].content)
    }elseif([IO.File]::Exists($path)){
        [IO.File]::Delete($path)
    }
}
$afterRestore=@(Get-ChildItem -LiteralPath $xpui -File -Recurse -ErrorAction Stop)
if($afterRestore.Count -ne $pre.Count){throw 'NATIVE_REFRESH_ROLLBACK_FILE_COUNT_NOT_RESTORED'}
foreach($entry in $afterRestore){
    if(-not$pre.ContainsKey($entry.FullName) -or
       (Get-FileHash -LiteralPath $entry.FullName -Algorithm SHA256).Hash -cne [string]$pre[$entry.FullName].sha){
        throw 'NATIVE_REFRESH_ROLLBACK_SNAPSHOT_BYTES_NOT_RESTORED'
    }
}
Write-Host 'NATIVE_REFRESH_OFFICIAL_SCOPED_REFRESH_BYTE_EXACT_ROLLBACK_SYNTHETIC_PASS'

Write-Host 'NATIVE_REFRESH_REAL_OFFICIAL_CLI_SOURCE_SEMANTICS_PROVED_NO_USER_SPOTIFY_PASS'
