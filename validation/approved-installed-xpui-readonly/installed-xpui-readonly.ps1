# V036: read-only installed Windows Spicetify configuration/XPUI map.
# Official Windows default config: %APPDATA%\spicetify\config-xpui.ini
# Does not invoke the Spicetify CLI or read Spotify prefs contents.
function Assert-XpuiReadOnlyCanonicalV036 {
 param([string]$Path,[string]$Label)
 if([string]::IsNullOrWhiteSpace($Path) -or $Path.Length -gt 8192 -or
    $Path -notmatch '^[A-Za-z]:\\' -or $Path -match '[%*?]' -or
    $Path.StartsWith('\\')){throw ('V036_UNSAFE_'+$Label)}
 $full=[IO.Path]::GetFullPath($Path).TrimEnd('\','/')
 if($full -notmatch '^[A-Za-z]:\\'){throw ('V036_NONLOCAL_'+$Label)}
 $p=$full
 while($p){
   if(Test-Path -LiteralPath $p){
     $item=Get-Item -LiteralPath $p -Force -ErrorAction Stop
     if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
       throw ('V036_REPARSE_'+$Label)
     }
   }
   $parent=[IO.Directory]::GetParent($p)
   if($null-eq$parent -or $parent.FullName -ceq $p){break}
   $p=$parent.FullName
 }
 return $full
}
function Read-XpuiReadOnlyIniV036 {
 param([string]$Path)
 $f=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
 if($f.PSIsContainer -or $f.Length -gt 262144 -or $f.Length -lt 8 -or
    ($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
    throw 'V036_CONFIG_BAD_FILE_OR_SIZE'
 }
 $bytes=[IO.File]::ReadAllBytes($Path)
 if($bytes.Length -ne $f.Length){throw 'V036_CONFIG_RACED'}
 $text=[Text.UTF8Encoding]::new($false,$true).GetString($bytes)
 if($text.Contains([char]0)){throw 'V036_CONFIG_NUL'}
 $section='';$sections=@{};$values=@{}
 $lines=$text -split '\r?\n'
 if($lines.Count -gt 4096){throw 'V036_CONFIG_TOO_MANY_LINES'}
 foreach($raw in $lines){
   $line=$raw.Trim()
   if($line.Length -eq 0 -or $line.StartsWith(';') -or $line.StartsWith('#')){continue}
   if($line -match '^\[([A-Za-z0-9_-]{1,72})\]$'){
     $section=$matches[1].ToLowerInvariant()
     if($sections.ContainsKey($section)){throw 'V036_CONFIG_DUPLICATE_SECTION'}
     $sections[$section]=$true
     continue
   }
   if(!$section -or $line -notmatch '^([A-Za-z0-9_.-]{1,128})\s*=\s*(.*)$'){
     throw 'V036_CONFIG_MALFORMED'
   }
   $key=$section+'.'+$matches[1].ToLowerInvariant()
   if($values.ContainsKey($key)){throw 'V036_CONFIG_DUPLICATE_KEY'}
   $values[$key]=$matches[2].Trim()
 }
 foreach($needed in @('setting.spotify_path','setting.prefs_path')){
   if(-not$values.ContainsKey($needed)){throw 'V036_CONFIG_REQUIRED_PATH_MISSING'}
 }
 return $values
}
function Get-XpuiReadOnlyMetadataV036 {
 param([string]$Root)
 # Existing V010 snapshot caps: 20k files, 64MiB/file, 256MiB total.
 # This enumerates metadata only and rejects all reparse points.
 $stack=New-Object System.Collections.Generic.Stack[string]
 $stack.Push($Root);[int]$files=0;[int]$dirs=0;[int64]$bytes=0
 while($stack.Count -gt 0){
  foreach($entry in @(Get-ChildItem -LiteralPath ($stack.Pop()) -Force -ErrorAction Stop)){
    if(($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
      throw 'V036_XPUI_REPARSE_CHILD'
    }
    if($entry.PSIsContainer){$dirs++;$stack.Push($entry.FullName)}
    else{$files++;$bytes += [int64]$entry.Length
      if([int64]$entry.Length -gt 67108864){throw 'V036_V010_FILE_TOO_LARGE'}
    }
    if($files -gt 20000 -or $dirs -gt 20000 -or $bytes -gt 268435456){
      throw 'V036_V010_TREE_TOO_LARGE'
    }
  }
 }
 return [pscustomobject]@{files=$files;bytes=$bytes}
}
function Test-InstalledXpuiReadOnlyV036 {
 param([string]$HostedFixtureRoot=$null)
 $deny={param([string]$Reason)
  [pscustomobject]@{
   schema=1;status='blocked';reason=$Reason;xpui_state='unverified'
   snapshot_policy='unverified';config_origin='not-qualified'
   approved_config_apps=0;other_config_apps=0;approved_local_apps=0
   no_network=$true;no_process_launch=$true;spotify_prefs_content_read=$false
   current_profile_changed=$false;real_spotify_mutated=$false
   apply_authorized=$false;rollback_authorized=$false
   terminal_commit_authorized=$false;production_mutation_authorized=$false
  }
 }
 try{
  if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){
    throw 'V036_WINDOWS_ONLY'
  }
  $fixture=-not[string]::IsNullOrWhiteSpace($HostedFixtureRoot)
  if($fixture){
    if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
       $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or -not$env:RUNNER_TEMP){
      throw 'V036_FIXTURE_HOST_ONLY'
    }
    $runner=Assert-XpuiReadOnlyCanonicalV036 -Path $env:RUNNER_TEMP -Label 'RUNNER'
    $base=Assert-XpuiReadOnlyCanonicalV036 -Path $HostedFixtureRoot -Label 'FIXTURE'
    if(-not$base.StartsWith(($runner+'\'),[StringComparison]::OrdinalIgnoreCase)){
      throw 'V036_FIXTURE_OUTSIDE_RUNNER'
    }
    $roaming=Join-Path $base 'Roaming'
    $local=Join-Path $base 'Local'
    $origin='synthetic-hosted'
  }else{
    if(-not[string]::IsNullOrWhiteSpace($env:SPICETIFY_CONFIG)){
      throw 'V036_CUSTOM_CONFIG_OVERRIDE_UNRESOLVED'
    }
    $roaming=[Environment]::GetFolderPath([Environment+SpecialFolder]::ApplicationData)
    $local=[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    $origin='default-documented-not-cli-confirmed'
  }
  $roaming=Assert-XpuiReadOnlyCanonicalV036 $roaming 'ROAMING'
  $local=Assert-XpuiReadOnlyCanonicalV036 $local 'LOCAL'
  if(-not[IO.Directory]::Exists($roaming) -or -not[IO.Directory]::Exists($local)){
    throw 'V036_PROFILE_ROOT_MISSING'
  }
  $configRoot=Assert-XpuiReadOnlyCanonicalV036 (Join-Path $roaming 'spicetify') 'CONFIG_ROOT'
  $config=Assert-XpuiReadOnlyCanonicalV036 (Join-Path $configRoot 'config-xpui.ini') 'CONFIG'
  if(-not[IO.File]::Exists($config)){throw 'V036_DEFAULT_CONFIG_MISSING'}
  $ini=Read-XpuiReadOnlyIniV036 $config
  $spotify=Assert-XpuiReadOnlyCanonicalV036 ([string]$ini['setting.spotify_path']) 'SPOTIFY_PATH'
  $prefs=Assert-XpuiReadOnlyCanonicalV036 ([string]$ini['setting.prefs_path']) 'PREFS_PATH'
  if(-not[IO.Directory]::Exists($spotify) -or -not[IO.File]::Exists($prefs)){
    throw 'V036_REFERENCED_PATHS_MISSING'
  }
  $apps=Assert-XpuiReadOnlyCanonicalV036 (Join-Path $spotify 'Apps') 'SPOTIFY_APPS'
  if(-not[IO.Directory]::Exists($apps)){throw 'V036_SPOTIFY_APPS_MISSING'}
  $xpui=Assert-XpuiReadOnlyCanonicalV036 (Join-Path $apps 'xpui') 'XPUI'
  $spa=Assert-XpuiReadOnlyCanonicalV036 (Join-Path $apps 'xpui.spa') 'SPA'
  $state=if([IO.Directory]::Exists($xpui)){'extracted-directory'}elseif([IO.File]::Exists($spa)){'spa-only'}else{'missing'}
  $policy='not-applicable';$stat=$null
  if($state -ceq 'extracted-directory'){
    try{$stat=Get-XpuiReadOnlyMetadataV036 $xpui;$policy='within-v010-limits'}
    catch{
      if([string]$_.Exception.Message -like 'V036_V010_*'){$policy='exceeds-v010-limits'}
      else{throw}
    }
  }
  $custom=if($ini.ContainsKey('additionaloptions.custom_apps')){[string]$ini['additionaloptions.custom_apps']}else{''}
  if($custom -match '[,;]'){throw 'V036_CUSTOMAPPS_UNEXPECTED_SEPARATOR'}
  $names=@($custom -split '\|'|Where-Object{-not[string]::IsNullOrWhiteSpace($_)})
  $approved=@('ivlyrics','better-local-files','eternal-jukebox','playlist-maker')
  $seen=@{}
  foreach($name in $names){
    $name=$name.Trim().ToLowerInvariant()
    if($name -notmatch '^[a-z0-9-]{1,64}$' -or $seen.ContainsKey($name)){
      throw 'V036_CUSTOMAPPS_DUPLICATE_OR_INVALID'
    }
    $seen[$name]=$true
  }
  [int]$a=0;[int]$u=0;[int]$i=0
  foreach($key in @($seen.Keys)){if($key -in $approved){$a++}else{$u++}}
  $ca=Assert-XpuiReadOnlyCanonicalV036 (Join-Path $configRoot 'CustomApps') 'CUSTOMAPPS'
  foreach($n in $approved){
    $dir=Assert-XpuiReadOnlyCanonicalV036 (Join-Path $ca $n) 'CUSTOM_APP'
    if([IO.Directory]::Exists($dir)){$i++}
  }
  return [pscustomobject]@{
   schema=1;status='observed-readonly'
   reason='inventory-only-not-cli-proven-or-transaction-authority'
   config_origin=$origin;xpui_state=$state;snapshot_policy=$policy
   xpui_file_count=if($stat){[int]$stat.files}else{0}
   xpui_size_band=if(-not$stat){'unverified'}elseif($stat.bytes -lt 67108864){'under64mib'}else{'64to256mib'}
   approved_config_apps=$a;other_config_apps=$u;approved_local_apps=$i
   exact_cli_config_path_verified=$false;native_binary_verified=$false
   xpui_preimage_durably_sealed=$false
   no_network=$true;no_process_launch=$true;spotify_prefs_content_read=$false
   current_profile_changed=$false;real_spotify_mutated=$false
   apply_authorized=$false;rollback_authorized=$false
   terminal_commit_authorized=$false;production_mutation_authorized=$false
  }
 }catch{
  # Never include raw exception strings: they may contain private paths.
  $s=[string]$_.Exception.Message
  $why=if($s -cmatch '^(V036_[A-Z0-9_]+)'){$matches[1]}else{'V036_DISCOVERY_INCOMPLETE'}
  return & $deny $why
 }
}
# Importing this module does nothing; it is NOT wired into auto-update.
