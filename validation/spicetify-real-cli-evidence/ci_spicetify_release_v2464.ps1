# GitHub-hosted Windows ONLY. Execute the real official CLI release inside a
# disposable, isolated profile. This is NOT a production update/apply test.
# -v and -c may create Spicetify config/state directories from Go package init.
# The official release archive hash pins provenance of the downloaded bytes.
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP) -or
   [string]::IsNullOrWhiteSpace($env:GITHUB_RUN_ID)){
    throw 'SPICETIFY_REAL_CLI_PROVENANCE_HOSTED_WINDOWS_ONLY'
}
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){
    throw 'SPICETIFY_REAL_CLI_REQUIRES_WINDOWS'
}
$release='2.46.4'
$assetName='spicetify-2.46.4-windows-x64.zip'
$assetSha='0490380bf59e00c94cf6cb12bfac5152791b91bb8009aceef53c49815b45a56f'
$assetUrl='https://github.com/spicetify/cli/releases/download/v2.46.4/spicetify-2.46.4-windows-x64.zip'
$runner=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
$root=Join-Path $runner ('spicetify-real-cli-provenance-'+$env:GITHUB_RUN_ID+'-'+[guid]::NewGuid().ToString('N'))
if([IO.Directory]::Exists($root) -or [IO.File]::Exists($root)){
    throw 'SPICETIFY_REAL_CLI_TEST_ROOT_PREEXISTS'
}
[IO.Directory]::CreateDirectory($root)|Out-Null
$archive=Join-Path $root $assetName
$unpack=Join-Path $root 'unpack'
$local=Join-Path $root 'profile-local'
$roaming=Join-Path $root 'profile-roaming'
$config=Join-Path $root 'isolated-config'
$state=Join-Path $root 'isolated-state'
foreach($d in @($unpack,$local,$roaming)){
    [IO.Directory]::CreateDirectory($d)|Out-Null
}
if(@(Get-Process Spotify -ErrorAction SilentlyContinue).Count -gt 0){
    throw 'SPICETIFY_REAL_CLI_UNEXPECTED_SPOTIFY_PROCESS_ON_RUNNER'
}
$ProgressPreference='SilentlyContinue'
$oldTls=[Net.ServicePointManager]::SecurityProtocol
try{
    [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $assetUrl -OutFile $archive -UseBasicParsing -ErrorAction Stop
}finally{
    [Net.ServicePointManager]::SecurityProtocol=$oldTls
}
if((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -cne $assetSha){
    throw 'SPICETIFY_REAL_CLI_RELEASE_ARCHIVE_SHA256_MISMATCH'
}
Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
$zip=$null
$seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
try{
    $zip=[IO.Compression.ZipFile]::OpenRead($archive)
    if($zip.Entries.Count -lt 1 -or $zip.Entries.Count -gt 10000){
        throw 'SPICETIFY_REAL_CLI_ZIP_ENTRY_COUNT_INVALID'
    }
    $total=[int64]0
    foreach($entry in $zip.Entries){
        $rel=[string]$entry.FullName
        if([string]::IsNullOrWhiteSpace($rel) -or
           $rel.StartsWith('/') -or $rel.StartsWith('\') -or
           $rel.Contains(':') -or $rel.Contains('//')){
            throw 'SPICETIFY_REAL_CLI_ZIP_ENTRY_PATH_INVALID'
        }
        $rel=$rel.Replace('/','\')
        $isDir=$rel.EndsWith('\')
        $full=[IO.Path]::GetFullPath((Join-Path $unpack $rel))
        if(-not $full.StartsWith(([IO.Path]::GetFullPath($unpack).TrimEnd('\')+'\'),
             [StringComparison]::OrdinalIgnoreCase)){
            throw 'SPICETIFY_REAL_CLI_ZIP_PATH_ESCAPE'
        }
        if(-not $seen.Add($full)){
            throw 'SPICETIFY_REAL_CLI_ZIP_DUPLICATE_CASE_INSENSITIVE_ENTRY'
        }
        if($isDir){
            [IO.Directory]::CreateDirectory($full)|Out-Null
            continue
        }
        $total+=[int64]$entry.Length
        if($total -gt 150000000){
            throw 'SPICETIFY_REAL_CLI_ZIP_UNCOMPRESSED_SIZE_EXCEEDED'
        }
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($full))|Out-Null
        $in=$null;$out=$null
        try{
            $in=$entry.Open()
            $out=[IO.File]::Open($full,[IO.FileMode]::CreateNew,
                [IO.FileAccess]::Write,[IO.FileShare]::None)
            $in.CopyTo($out)
            $out.Flush($true)
        }finally{
            if($null-ne$out){$out.Dispose()}
            if($null-ne$in){$in.Dispose()}
        }
    }
}finally{
    if($null-ne$zip){$zip.Dispose()}
}
$executables=@(Get-ChildItem -LiteralPath $unpack -Recurse -Force -File -Filter 'spicetify.exe')
if($executables.Count -ne 1){
    throw 'SPICETIFY_REAL_CLI_RELEASE_EXECUTABLE_CARDINALITY_INVALID'
}
$exe=$executables[0].FullName
$exeBytes=[IO.File]::ReadAllBytes($exe)
if($exeBytes.Length -lt 500000 -or $exeBytes.Length -gt 30000000 -or
   $exeBytes[0] -ne 0x4d -or $exeBytes[1] -ne 0x5a){
    throw 'SPICETIFY_REAL_CLI_PE_HEADER_OR_SIZE_INVALID'
}
$exeHash=(Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant()
if($exeHash -cnotmatch '^[0-9a-f]{64}$'){
    throw 'SPICETIFY_REAL_CLI_EXECUTABLE_SHA256_INVALID'
}
$cfgPath=Join-Path $config 'config-xpui.ini'
# Pass explicit profile and config roots to the CLI child; do NOT call -v/-c
# using its inherited real user profile: package-level initializers can WRITE.
function Invoke-IsolatedSpicetifyProbe {
    param([Parameter(Mandatory=$true)][string]$Arguments)
    $start=New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName=$exe
    $start.Arguments=$Arguments
    $start.WorkingDirectory=$unpack
    $start.UseShellExecute=$false
    $start.CreateNoWindow=$true
    $start.RedirectStandardOutput=$true
    $start.RedirectStandardError=$true
    $start.EnvironmentVariables['APPDATA']=$roaming
    $start.EnvironmentVariables['LOCALAPPDATA']=$local
    $start.EnvironmentVariables['SPICETIFY_CONFIG']=$config
    $start.EnvironmentVariables['SPICETIFY_STATE']=$state
    $start.EnvironmentVariables['USERPROFILE']=$root
    $p=New-Object System.Diagnostics.Process
    try{
        $p.StartInfo=$start
        if(-not $p.Start()){throw 'SPICETIFY_REAL_CLI_PROCESS_NOT_STARTED'}
        if(-not $p.WaitForExit(15000)){
            $p.Kill()
            throw 'SPICETIFY_REAL_CLI_READONLY_FLAG_TIMEOUT'
        }
        $all=($p.StandardOutput.ReadToEnd()+[Environment]::NewLine+
              $p.StandardError.ReadToEnd()).Trim()
        if($p.ExitCode -ne 0){
            throw ('SPICETIFY_REAL_CLI_READONLY_FLAG_NONZERO_'+$p.ExitCode)
        }
        if($all.Length -gt 4096){
            throw 'SPICETIFY_REAL_CLI_READONLY_FLAG_EXCESS_OUTPUT'
        }
        return $all
    }finally{$p.Dispose()}
}
if([IO.File]::Exists($cfgPath)){
    throw 'SPICETIFY_REAL_CLI_CONFIG_ALREADY_EXISTS_BEFORE_PROBE'
}
$versionOutput=Invoke-IsolatedSpicetifyProbe -Arguments '-v'
if($versionOutput -notmatch '(^|\s)v?2\.46\.4(\s|$)'){
    throw 'SPICETIFY_REAL_CLI_VERSION_OUTPUT_NOT_PINNED'
}
$configOutput=Invoke-IsolatedSpicetifyProbe -Arguments '-c'
if(-not $configOutput.Contains($cfgPath)){
    throw 'SPICETIFY_REAL_CLI_CONFIG_LOCATION_UNEXPECTED'
}
if([IO.File]::Exists($cfgPath)){
    throw 'SPICETIFY_REAL_CLI_CONFIG_FILE_CREATED_BY_VERSION_OR_CONFIG_FLAG'
}
foreach($d in @($config,$state)){
    if(-not[IO.Directory]::Exists($d)){
        throw 'SPICETIFY_REAL_CLI_EXPECTED_PACKAGE_INIT_DIRECTORIES_NOT_CREATED'
    }
}
if(@(Get-Process Spotify -ErrorAction SilentlyContinue).Count -gt 0){
    throw 'SPICETIFY_REAL_CLI_STARTED_SPOTIFY_UNEXPECTEDLY'
}
if((Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant() -cne $exeHash -or
   (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -cne $assetSha){
    throw 'SPICETIFY_REAL_CLI_BINARY_MODIFIED_AFTER_ISOLATED_PROBE'
}

# A static, canonical CurrentUser evidence reader must NOT launch the CLI,
# look up a PATH alias, or trust release ZIP SHA as the executable's SHA.
# Negative check BEFORE installing the sandbox-only copy: no directory
# materialization allowed by this host-side read-only evidence primitive.
. (Join-Path $PSScriptRoot 'static-spicetify-provenance.ps1')
$beforeEvidence=Get-CustomAppSpicetifyCanonicalEvidenceV015 -HostedCiProfileRoot $root -ExpectedExecutableSha256 $exeHash
$profileExe=Join-Path (Join-Path $local 'spicetify') 'spicetify.exe'
if([bool]$beforeEvidence.ok -or [IO.File]::Exists($profileExe) -or
   [IO.Directory]::Exists((Join-Path $local 'spicetify'))){
    throw 'SPICETIFY_STATIC_READER_CREATED_MISSING_CANONICAL_INSTALL'
}
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($profileExe))|Out-Null
[IO.File]::Copy($exe,$profileExe,$false)
$profileHash=(Get-FileHash -LiteralPath $profileExe -Algorithm SHA256).Hash.ToLowerInvariant()
if($profileHash -cne $exeHash){throw 'SPICETIFY_STATIC_READER_SANDBOX_COPY_HASH_MISMATCH'}
$validEvidence=Get-CustomAppSpicetifyCanonicalEvidenceV015 -HostedCiProfileRoot $root -ExpectedExecutableSha256 $exeHash
if(-not[bool]$validEvidence.ok -or -not[bool]$validEvidence.executable_pin_matched -or
   [string]$validEvidence.executable_sha256 -cne $exeHash -or
   [bool]$validEvidence.executable_was_started -or
   [bool]$validEvidence.production_execution_authorized -or
   [bool]$validEvidence.production_mutation_authorized -or
   [bool]$validEvidence.config_file_present){
    throw 'SPICETIFY_STATIC_CURRENTUSER_EVIDENCE_VALID_PIN_FAIL'
}
$badEvidence=Get-CustomAppSpicetifyCanonicalEvidenceV015 -HostedCiProfileRoot $root -ExpectedExecutableSha256 ('0'*64)
if([bool]$badEvidence.ok -or
   [string]$badEvidence.reason -cne 'spicetify-profile-enrolled-exe-pin-mismatch' -or
   [bool]$badEvidence.production_mutation_authorized){
    throw 'SPICETIFY_STATIC_CURRENTUSER_WRONG_EXE_PIN_ACCEPTED'
}
$deniedWrongRoot=$false
try{
    $badRoot=Get-CustomAppSpicetifyCanonicalEvidenceV015 -HostedCiProfileRoot $env:SystemRoot
}catch{$deniedWrongRoot=$true}
if(-not $deniedWrongRoot){throw 'SPICETIFY_STATIC_CURRENTUSER_HOSTED_ROOT_ESCAPE_ACCEPTED'}
if((Get-FileHash -LiteralPath $profileExe -Algorithm SHA256).Hash.ToLowerInvariant() -cne $exeHash -or
   (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant() -cne $exeHash){
    throw 'SPICETIFY_STATIC_CURRENTUSER_READ_MUTATED_EXE'
}
Write-Host 'SPICETIFY_CANONICAL_CURRENTUSER_EXE_SNAPSHOT_PASS no_caller_path=true pinned_exe=true wrong_sha_denied=true no_process_started=true absent_exe_not_created=true user_profile_untouched=true'

$report=[ordered]@{
    schema=1
    release='v2.46.4'
    release_asset=$assetName
    release_zip_sha256=$assetSha
    extracted_executable_sha256=$exeHash
    executable_bytes=[int64]$exeBytes.Length
    version_reported=$release
    config_basename='config-xpui.ini'
    package_init_created_config_directory=$true
    package_init_created_state_directory=$true
    no_config_file_write_during_version_and_config_flags=$true
    no_cli_apply_or_spotify_execution=$true
    canonical_profile_executable_read_only_verified=$true
    wrong_hash_denied=$true
    no_executable_or_config_write_by_static_reader=$true
    hosted_profile_only=$true
    executable_sha_is_not_an_enrolled_user_pin=$true
    result_is_not_production_execution_authority=$true
}
$reportPath=Join-Path $PSScriptRoot 'real-cli-provenance-ci.json'
[IO.File]::WriteAllText($reportPath,($report|ConvertTo-Json -Depth 8),
    (New-Object Text.UTF8Encoding($false)))
Write-Host ('SPICETIFY_REAL_OFFICIAL_RELEASE_EXE_SHA256='+$exeHash)
Write-Host ('SPICETIFY_REAL_OFFICIAL_RELEASE_EXE_BYTES='+$exeBytes.Length)
Write-Host 'SPICETIFY_REAL_CLI_HOSTED_ISOLATED_PROVENANCE_PASS release_zip_pinned=true extracted_exe_hashed=true version_flag=true config_path_flag=true init_creates_directories=true no_apply=true real_user_profile_unchanged=true'
