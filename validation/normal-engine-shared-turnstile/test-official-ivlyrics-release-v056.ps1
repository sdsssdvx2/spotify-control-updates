# V056. Real official ivLyrics v7.1.6 ZIP -> uninstalled, hosted-only
# source->official Spicetify 2.46.4 renderer->exact V044/V054 outputs.
# Downloaded publisher ZIP and extracted source exist ONLY in RUNNER_TEMP.
# No installation, no user profile access, no production approval.
param([Parameter(Mandatory=$true)][string]$OfficialExecutable)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
   $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
 throw 'V056_HOSTED_WINDOWS_ONLY'
}
. (Join-Path $PSScriptRoot '..\custom-app-update-transaction-protocol-v0.1.0\custom-app-update-transaction.ps1')
. (Join-Path $PSScriptRoot '..\approved-native-manifest-scope\manifest-owned-xpui-v044.ps1')
. (Join-Path $PSScriptRoot 'official-route-byte-binding-v054.ps1')
function Assert-V056([bool]$Ok,[string]$Reason){if(-not$Ok){throw ('V056_TEST_'+$Reason)}}
function Denied-V056([scriptblock]$Code,[string]$Expected){
 $blocked=$false
 try{[void](& $Code)}catch{
   if([string]$_.Exception.Message -ceq $Expected){$blocked=$true}else{throw}
 }
 Assert-V056 $blocked ('DENIAL_NOT_ENFORCED_'+$Expected)
}
$zipSha='bdd7c047b303c519997d3f5c5f0ca416e607aad0a6de6592bb15fddb6e6269ac'
$checksumAssetSha='ea2193316c721fe2b47cd660cfb00c5afcb82c4dd7c00d9bb90b789e444125f9'
$exeSha='3563f26acd7527adc97e6c19272fa1b48ce976a913625d9804ac57d3c54fb4db'
$exe=[IO.Path]::GetFullPath($OfficialExecutable)
$hostRoot=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
if(-not$exe.StartsWith($hostRoot+'\',[StringComparison]::OrdinalIgnoreCase) -or
   -not[IO.File]::Exists($exe) -or
   (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant() -cne $exeSha){
 throw 'V056_OFFICIAL_SPICETIFY_EXE_UNPINNED_OR_NONRUNNER'
}
# Use exact release path (not latest). Assert digest and size from GitHub
# API, local archive hash, AND independent publisher checksum sidecar.
$api='https://api.github.com/repos/ivLis-Studio/ivLyrics/releases/tags/v7.1.6'
$release=Invoke-RestMethod -UseBasicParsing -Uri $api -Headers @{'User-Agent'='spotify-control-v056-hold'} -ErrorAction Stop
if([string]$release.tag_name -cne 'v7.1.6' -or [bool]$release.draft -or [bool]$release.prerelease){
 throw 'V056_PUBLISHER_RELEASE_TYPE_DRIFT'
}
$assets=@($release.assets)
$archiveAssets=@($assets|Where-Object{$_.name -ceq 'ivLyrics.zip'})
$checksumAssets=@($assets|Where-Object{$_.name -ceq 'ivLyrics.zip.sha256'})
if($archiveAssets.Count -ne 1 -or $checksumAssets.Count -ne 1 -or
   [int64]$archiveAssets[0].size -ne 10464403 -or
   [string]$archiveAssets[0].digest -cne ('sha256:'+$zipSha) -or
   [int64]$checksumAssets[0].size -ne 79 -or
   [string]$checksumAssets[0].digest -cne ('sha256:'+$checksumAssetSha) -or
   [string]$archiveAssets[0].browser_download_url -cne
     'https://github.com/ivLis-Studio/ivLyrics/releases/download/v7.1.6/ivLyrics.zip' -or
   [string]$checksumAssets[0].browser_download_url -cne
     'https://github.com/ivLis-Studio/ivLyrics/releases/download/v7.1.6/ivLyrics.zip.sha256'){
 throw 'V056_IMMUTABLE_OFFICIAL_RELEASE_ASSET_METADATA_DRIFT'
}
$root=Join-Path $env:RUNNER_TEMP ('v056-official-ivlyrics-'+[guid]::NewGuid().ToString('N'))
$download=Join-Path $root 'Downloaded'
$extracted=Join-Path $root 'Extracted'
$vendor=Join-Path $root 'VendorCLI'
$source=Join-Path $vendor 'CustomApps\ivlyrics'
$spotify=Join-Path $root 'FakeSpotify'
$xpui=Join-Path $spotify 'Apps\xpui'
$config=Join-Path $root 'PrivateConfig'
$backup=Join-Path $config 'Backup'
$roaming=Join-Path $root 'Roaming'
$local=Join-Path $root 'Local'
$state=Join-Path $root 'PrivateState'
foreach($p in @($download,$extracted,$vendor,$xpui,$config,$backup,$roaming,$local,$state)){
 [void][IO.Directory]::CreateDirectory($p)
}
$archive=Join-Path $download 'ivLyrics.zip'
$sidecar=Join-Path $download 'ivLyrics.zip.sha256'
Invoke-WebRequest -UseBasicParsing -Uri ([string]$archiveAssets[0].browser_download_url) -OutFile $archive -ErrorAction Stop
Invoke-WebRequest -UseBasicParsing -Uri ([string]$checksumAssets[0].browser_download_url) -OutFile $sidecar -ErrorAction Stop
if((Get-Item -LiteralPath $archive).Length -ne 10464403 -or
   (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -cne $zipSha -or
   (Get-Item -LiteralPath $sidecar).Length -ne 79 -or
   (Get-FileHash -LiteralPath $sidecar -Algorithm SHA256).Hash.ToLowerInvariant() -cne $checksumAssetSha){
 throw 'V056_DOWNLOADED_RELEASE_ARCHIVE_OR_CHECKSUM_PIN_FAILED'
}
$side=[IO.File]::ReadAllText($sidecar,[Text.UTF8Encoding]::new($false,$true)).Trim()
if($side -cnotmatch ('^'+$zipSha+'\s+\*?ivLyrics\.zip$')){
 throw 'V056_INDEPENDENT_PUBLISHER_CHECKSUM_CONTENT_MISMATCH'
}
Write-Host 'V056_OFFICIAL_IVLYRICS_V716_RELEASE_METADATA_ARCHIVE_AND_CHECKSUM_SHA_PINS_PASS'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$z=[IO.Compression.ZipFile]::OpenRead($archive)
try{
 [int64]$total=0
 $files=0
 $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
 foreach($entry in $z.Entries){
   $rel=[string]$entry.FullName
   if($rel -cnotmatch '^ivLyrics/' -or
      $rel.Contains('\') -or $rel.Contains(':') -or
      $rel -cmatch '(^|/)\.{1,2}(/|$)' -or
      [IO.Path]::IsPathRooted($rel) -or
      $rel.Length -gt 260 -or
      -not$seen.Add($rel)){
     throw 'V056_RELEASE_ZIP_ENTRY_UNSAFE_OR_DUPLICATE'
   }
   $mode=([int64]$entry.ExternalAttributes -shr 16) -band 61440
   if($mode -eq 40960){throw 'V056_RELEASE_ZIP_CONTAINS_SYMLINK'}
   $total+=[int64]$entry.Length
   if($total -gt 104857600 -or [int64]$entry.Length -gt 16777216){
     throw 'V056_RELEASE_ZIP_INFLATION_LIMIT'
   }
   if(-not$rel.EndsWith('/')){$files++}
   if($files -gt 1000){throw 'V056_RELEASE_TOO_MANY_MEMBERS'}
 }
 if($files -lt 90){throw 'V056_RELEASE_RUNTIME_INCOMPLETE'}
}finally{$z.Dispose()}
Expand-Archive -LiteralPath $archive -DestinationPath $extracted -ErrorAction Stop
$unpacked=Join-Path $extracted 'ivLyrics'
if(-not[IO.Directory]::Exists($unpacked) -or
   [IO.File]::Exists((Join-Path $extracted 'manifest.json')) -or
   [IO.Directory]::Exists((Join-Path $unpacked 'local-db')) -or
   [IO.Directory]::Exists((Join-Path $unpacked 'third_party'))){
 throw 'V056_RELEASE_ROOT_OR_EXCLUDED_SOURCE_FOLDERS_UNEXPECTED'
}
$activeFiles=@(Get-ChildItem -LiteralPath $unpacked -File -Force)
if(-not(@($activeFiles|Where-Object{$_.Name -ceq 'index.js'}).Count -eq 1) -or
   -not(@($activeFiles|Where-Object{$_.Name -ceq 'manifest.json'}).Count -eq 1) -or
   -not(@($activeFiles|Where-Object{$_.Name -ceq 'style.css'}).Count -eq 1) -or
   -not(@($activeFiles|Where-Object{$_.Name -ceq 'LrclibLocalDatabaseRuntime.js'}).Count -eq 1)){
 throw 'V056_REQUIRED_PUBLISHER_RUNTIME_FILES_MISSING'
}
$manifest=([IO.File]::ReadAllText((Join-Path $unpacked 'manifest.json'),[Text.UTF8Encoding]::new($false,$true)))|ConvertFrom-Json -ErrorAction Stop
if([string]$manifest.name -cne 'ivLyrics' -or
   @($manifest.subfiles).Count -ne 51 -or
   @($manifest.subfiles_extension).Count -ne 36 -or
   @($manifest.subfiles_extension) -cnotcontains 'LrclibLocalDatabaseRuntime.js'){
 throw 'V056_OFFICIAL_RELEASE_MANIFEST_RUNTIME_SCOPE_UNEXPECTED'
}
[IO.Directory]::CreateDirectory((Split-Path -Parent $source))|Out-Null
[IO.Directory]::Move($unpacked,$source)
$sourcePre=Get-CustomAppUpdateTreeSnapshotV010 -Root $source
Write-Host 'V056_OFFICIAL_RUNTIME_SOURCE_51_SUBFILES_36_EXTENSIONS_PINNED_PASS'
$bin=Join-Path $vendor 'spicetify.exe'
[IO.File]::Copy($exe,$bin,$false)
$prefs=Join-Path $root 'prefs'
[IO.File]::WriteAllText($prefs,('app.last-launched-version = 1.2.3'+[char]10),[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllBytes((Join-Path $backup 'xpui.spa'),[byte[]](0x50,0x4b))
$foreign=Join-Path $xpui 'v056-unmanaged-asset-private-sentinel.dat'
[IO.File]::WriteAllText($foreign,'DO_NOT_CHANGE_UNMANAGED_XPUI_V056')
$foreignTwo=Join-Path $xpui 'spicetify-routes-other-app.js'
[IO.File]::WriteAllText($foreignTwo,'DO_NOT_CHANGE_OTHER_APP_V056')
$foreignOneHash=(Get-FileHash $foreign -Algorithm SHA256).Hash
$foreignTwoHash=(Get-FileHash $foreignTwo -Algorithm SHA256).Hash
$canonical=Join-Path $roaming 'spicetify'
[void][IO.Directory]::CreateDirectory($canonical)
$originalConfig=Join-Path $canonical 'config-xpui.ini'
[IO.File]::WriteAllText($originalConfig,('[AdditionalOptions]'+[Environment]::NewLine+
 'custom_apps = ivLyrics|better-local-files|eternal-jukebox|unmanaged'+[Environment]::NewLine),
 [Text.UTF8Encoding]::new($false))
$originalConfigHash=(Get-FileHash $originalConfig -Algorithm SHA256).Hash
$nl=[Environment]::NewLine
$scoped='[Setting]'+$nl+'spotify_path = '+$spotify+$nl+
 'prefs_path = '+$prefs+$nl+'check_spicetify_update = false'+$nl+
 'current_theme = '+$nl+'[Backup]'+$nl+'version = 1.2.3'+$nl+
 'with = 2.46.4'+$nl+'[AdditionalOptions]'+$nl+'custom_apps = ivlyrics'+$nl
[IO.File]::WriteAllText((Join-Path $config 'config-xpui.ini'),$scoped,[Text.UTF8Encoding]::new($false))
$before=Get-CustomAppUpdateTreeSnapshotV010 -Root $xpui
$prefsHash=(Get-FileHash $prefs -Algorithm SHA256).Hash
$proc=New-Object Diagnostics.Process
try{
 $psi=New-Object Diagnostics.ProcessStartInfo
 $psi.FileName=$bin;$psi.Arguments='--bypass-admin -n -a refresh'
 $psi.WorkingDirectory=$vendor
 $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
 $psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
 $psi.EnvironmentVariables['SPICETIFY_CONFIG']=$config
 $psi.EnvironmentVariables['SPICETIFY_STATE']=$state
 $psi.EnvironmentVariables['APPDATA']=$roaming
 $psi.EnvironmentVariables['LOCALAPPDATA']=$local
 $psi.EnvironmentVariables['USERPROFILE']=$root
 $psi.EnvironmentVariables['HOME']=$root
 $proc.StartInfo=$psi
 if(-not$proc.Start()){throw 'V056_OFFICIAL_VENDOR_START_FAILED'}
 if(-not$proc.WaitForExit(90000)){
   $proc.Kill();[void]$proc.WaitForExit()
   throw 'V056_OFFICIAL_VENDOR_TIMEOUT'
 }
 $out=$proc.StandardOutput.ReadToEnd();$err=$proc.StandardError.ReadToEnd()
 if($proc.ExitCode -ne 0 -or $out.Length+$err.Length -gt 65536){
    throw 'V056_OFFICIAL_VENDOR_FAILED_OR_TOO_NOISY'
 }
}finally{$proc.Dispose()}
$after=Get-CustomAppUpdateTreeSnapshotV010 -Root $xpui
$scope=Get-ApprovedNativeManifestOwnedScopeV044 -Name 'ivlyrics' -SourceAppPath $source
$owned=Test-ApprovedNativeManifestOnlyOwnedTargetChangedV044 -Before $before -After $after -Name 'ivlyrics' -SourceAppPath $source -ExpectedSourceTreeSha256 ([string]$sourcePre.tree_sha256)
$exact=Test-CustomAppV054OfficialSourceBoundRoutes -Name 'ivlyrics' -SourceAppPath $source -CandidateXpuiRoot $xpui -ExpectedSourceTreeSha256 ([string]$sourcePre.tree_sha256)
if(-not[bool]$owned.ok -or -not[bool]$owned.foreign_xpui_preserved -or
    -not[bool]$exact.ok -or
    [int]$owned.scoped_file_count -ne 39 -or
    [int]$owned.scoped_extension_files -ne 36 -or
    [int]$owned.scoped_asset_files -ne 0 -or
    (Get-FileHash $originalConfig -Algorithm SHA256).Hash -cne $originalConfigHash -or
    (Get-FileHash $prefs -Algorithm SHA256).Hash -cne $prefsHash -or
    (Get-FileHash $foreign -Algorithm SHA256).Hash -cne $foreignOneHash -or
    (Get-FileHash $foreignTwo -Algorithm SHA256).Hash -cne $foreignTwoHash -or
    (Get-FileHash $bin -Algorithm SHA256).Hash.ToLowerInvariant() -cne $exeSha -or
    (Get-CustomAppUpdateTreeSnapshotV010 -Root $source).tree_sha256 -cne [string]$sourcePre.tree_sha256 -or
    [bool]$owned.production_mutation_authorized -or
    [bool]$exact.production_mutation_authorized){
 throw 'V056_OFFICIAL_RELEASE_SOURCE_TO_NATIVE_OUTPUT_OR_PRESERVATION_FAILED'
}
# The official CLI may reformat a scoped config; parse section+key values.
$values=New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::OrdinalIgnoreCase)
$section=''
foreach($line in [IO.File]::ReadAllLines((Join-Path $config 'config-xpui.ini'))){
 $trim=$line.Trim()
 if($trim.Length -eq 0 -or $trim.StartsWith(';') -or $trim.StartsWith('#')){continue}
 if($trim -match '^\[([A-Za-z][A-Za-z0-9]*)\]$'){$section=[string]$Matches[1];continue}
 $eq=$trim.IndexOf('=')
 if($eq -le 0 -or [string]::IsNullOrWhiteSpace($section)){throw 'V056_SCOPED_CONFIG_UNPARSEABLE'}
 $key=$section+'.'+$trim.Substring(0,$eq).Trim()
 if($values.ContainsKey($key)){throw 'V056_SCOPED_CONFIG_DUPLICATE_KEY'}
 $values.Add($key,$trim.Substring($eq+1).Trim())
}
Assert-V056 ($values.ContainsKey('Setting.spotify_path') -and
 [string]$values['Setting.spotify_path'] -ceq $spotify -and
 $values.ContainsKey('Setting.prefs_path') -and
 [string]$values['Setting.prefs_path'] -ceq $prefs -and
 $values.ContainsKey('AdditionalOptions.custom_apps') -and
 [string]$values['AdditionalOptions.custom_apps'] -ceq 'ivlyrics') 'OFFICIAL_CLI_SCOPED_CONFIG_DRIFT'
Write-Host 'V056_REAL_OFFICIAL_RELEASE_ZIP_RENDERED_39_MANIFEST_OWNED_XPUI_FILES_EXACT_PASS'
Write-Host 'V056_ORIGINAL_CONFIG_PREFS_VENDOR_AND_TWO_FOREIGN_XPUI_FILES_UNCHANGED_PASS'
# Check that allowlisted filenames alone do not authorize forged content.
foreach($negative in @(
 [pscustomobject]@{rel='spicetify-routes-ivlyrics.js';reason='V054_VENDOR_ROUTE_JS_NOT_SOURCE_DERIVED'},
 [pscustomobject]@{rel='spicetify-routes-ivlyrics.css';reason='V054_VENDOR_ROUTE_CSS_NOT_SOURCE_DERIVED'},
 [pscustomobject]@{rel='spicetify-routes-ivlyrics.json';reason='V054_VENDOR_ROUTE_MANIFEST_NOT_SOURCE_DERIVED'})){
 $dest=Join-Path $xpui ([string]$negative.rel)
 $bytes=[IO.File]::ReadAllBytes($dest)
 try{
  [IO.File]::AppendAllText($dest,'V056_FORGED_OFFICIAL_ROUTE')
  Denied-V056 {Test-CustomAppV054OfficialSourceBoundRoutes -Name 'ivlyrics' -SourceAppPath $source -CandidateXpuiRoot $xpui -ExpectedSourceTreeSha256 ([string]$sourcePre.tree_sha256)} ([string]$negative.reason)
 }finally{[IO.File]::WriteAllBytes($dest,$bytes)}
}
$extension=Join-Path $xpui 'extensions\ivlyrics\LrclibLocalDatabaseRuntime.js'
$extBytes=[IO.File]::ReadAllBytes($extension)
try{
 [IO.File]::AppendAllText($extension,'V056_FORGED_COPIED_EXTENSION')
 $changed=Get-CustomAppUpdateTreeSnapshotV010 -Root $xpui
 Denied-V056 {Test-ApprovedNativeManifestOnlyOwnedTargetChangedV044 -Before $before -After $changed -Name 'ivlyrics' -SourceAppPath $source -ExpectedSourceTreeSha256 ([string]$sourcePre.tree_sha256)} 'V044_MANIFEST_SOURCE_COPIED_BYTES_DID_NOT_MATCH'
}finally{[IO.File]::WriteAllBytes($extension,$extBytes)}
Assert-V056 ((Get-CustomAppUpdateTreeSnapshotV010 -Root $xpui).tree_sha256 -ceq [string]$after.tree_sha256) 'NEGATIVE_TEST_LEFT_OUTPUT_DIRTY'
$index=Join-Path $source 'index.js'
$indexBytes=[IO.File]::ReadAllBytes($index)
try{
 [IO.File]::AppendAllText($index,'V056_BAD_POST_RELEASE_SOURCE')
 Denied-V056 {Test-CustomAppV054OfficialSourceBoundRoutes -Name 'ivlyrics' -SourceAppPath $source -CandidateXpuiRoot $xpui -ExpectedSourceTreeSha256 ([string]$sourcePre.tree_sha256)} 'V054_SOURCE_TREE_NOT_BOUND_TO_CANDIDATE'
}finally{[IO.File]::WriteAllBytes($index,$indexBytes)}
Assert-V056 ((Get-CustomAppUpdateTreeSnapshotV010 -Root $source).tree_sha256 -ceq [string]$sourcePre.tree_sha256 -and
 (Get-FileHash $originalConfig -Algorithm SHA256).Hash -ceq $originalConfigHash -and
 (Get-FileHash $prefs -Algorithm SHA256).Hash -ceq $prefsHash) 'FINAL_VERIFIED_INPUT_RESTORATION'
Write-Host 'V056_FORGED_OFFICIAL_JS_CSS_JSON_EXTENSION_AND_POST_RELEASE_SOURCE_REJECTED_PASS'
Write-Host 'V056_REAL_PUBLISHER_ARTIFACT_HOSTED_ONLY_USER_SPOTIFY_AND_MAIN_UNCHANGED_NO_AUTHORITY_PASS'
