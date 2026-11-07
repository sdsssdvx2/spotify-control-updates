# V041 installed CustomApps origin inventory. READ ONLY. The exact official
# Spicetify CLI v2.46.4 src/utils/path-utils.go checks:
# (1) GetSpicetifyFolder()/CustomApps/<name>,
# (2) GetExecutableDir()/CustomApps/<name>,
# and recursively prefers a nested child containing index.js.
# This validator never runs the CLI, invokes Spotify or reads app source.
# Output is counts/status only: no app names, paths or private values.
function Assert-ApprovedAppOriginLeafV041 {
 param([Parameter(Mandatory=$true)][string]$Path)
 if(Test-Path -LiteralPath $Path){
  $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
  if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
   throw 'V041_SOURCE_REPARSE_POINT_REFUSED'
  }
 }
}
function Get-ApprovedAppOriginNestedV041 {
 param([Parameter(Mandatory=$true)][string]$Root)
 # Mirror the official nested index.js discovery but fail closed if there
 # is more than one nested candidate or a reparse path. No file contents.
 Assert-ApprovedAppOriginLeafV041 -Path $Root
 $stack=New-Object System.Collections.Generic.Stack[object]
 $stack.Push([pscustomobject]@{p=$Root;depth=0})
 $found=New-Object 'System.Collections.Generic.List[string]'
 [int]$directories=0
 while($stack.Count -gt 0){
  $current=$stack.Pop()
  if([int]$current.depth -gt 6){throw 'V041_SOURCE_NESTING_TOO_DEEP'}
  $children=@(Get-ChildItem -LiteralPath ([string]$current.p) -Directory -Force -ErrorAction Stop)
  foreach($child in $children){
   $directories++
   if($directories -gt 128){throw 'V041_SOURCE_TREE_TOO_MANY_DIRECTORIES'}
   Assert-ApprovedAppOriginLeafV041 -Path ([string]$child.FullName)
   $index=Join-Path ([string]$child.FullName) 'index.js'
   Assert-ApprovedAppOriginLeafV041 -Path $index
   if([IO.File]::Exists($index)){
     $found.Add([string]$child.FullName)
     if($found.Count -gt 1){throw 'V041_SOURCE_AMBIGUOUS_NESTED_APPS'}
   }
   $stack.Push([pscustomobject]@{p=[string]$child.FullName;depth=([int]$current.depth+1)})
  }
 }
 if($found.Count -eq 1){
  return [pscustomobject]@{path=$found[0];nested=$true}
 }
 return [pscustomobject]@{path=$Root;nested=$false}
}
function Test-ActualCustomAppOriginsReadOnlyV041 {
 param([string]$HostedFixtureRoot=$null,[string]$HostedFixtureCliPath=$null)
 $deny={param([string]$reason)
  [pscustomobject]@{
    schema=1;status='blocked';reason=$reason
    exact_cli_sha_verified=$false;official_cli_source_resolution='unverified'
    approved_config_apps=0;other_config_apps=0
    approved_user_origin=0;approved_cli_origin=0
    approved_source_missing=0;approved_source_incomplete=0
    approved_nested_source=0;approved_origin_shadowed=0
    unknown_apps_preserved=$true
    config_path_exposed=$false;app_names_exposed=$false
    spotify_prefs_content_read=$false;app_source_content_read=$false
    network_used=$false;process_started=$false;files_modified=$false
    apply_authorized=$false;production_mutation_authorized=$false
  }
 }
 try {
  $existing=Test-InstalledXpuiReadOnlyV036 -HostedFixtureRoot $HostedFixtureRoot
  if($existing.status -cne 'observed-readonly'){
    throw 'V041_PARENT_READONLY_DISCOVERY_NOT_QUALIFIED'
  }
  $fixture=-not[string]::IsNullOrWhiteSpace($HostedFixtureRoot)
  $origin='not-qualified'
  $pin=$false
  if($fixture){
    if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
       $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
       [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
      throw 'V041_SYNTHETIC_FIXTURE_FORBIDDEN_OUTSIDE_HOSTED_WINDOWS'
    }
    $runner=Assert-XpuiReadOnlyCanonicalV036 -Path $env:RUNNER_TEMP -Label 'RUNNER'
    $root=Assert-XpuiReadOnlyCanonicalV036 -Path $HostedFixtureRoot -Label 'HOSTED_ROOT'
    $exe=Assert-XpuiReadOnlyCanonicalV036 -Path $HostedFixtureCliPath -Label 'HOSTED_CLI'
    if(-not$root.StartsWith(($runner+'\'),[StringComparison]::OrdinalIgnoreCase) -or
       -not$exe.StartsWith(($root+'\'),[StringComparison]::OrdinalIgnoreCase)){
      throw 'V041_FIXTURE_ROOT_OR_CLI_OUTSIDE_RUNNER'
    }
    $config=Join-Path (Join-Path $root 'Roaming\spicetify') 'config-xpui.ini'
    $origin='hosted-synthetic-only'
  }else{
    if(-not[string]::IsNullOrWhiteSpace($HostedFixtureCliPath)){
      throw 'V041_ARBITRARY_CLI_PATH_NOT_ALLOWED_ON_REAL_PC'
    }
    if(-not[string]::IsNullOrWhiteSpace($env:SPICETIFY_CONFIG)){
      throw 'V041_CUSTOM_CONFIG_PATH_OVERRIDE_UNVERIFIED'
    }
    $all=@(Get-Command spicetify -CommandType Application -All -ErrorAction Stop)
    $sources=@($all|ForEach-Object{[string]$_.Source}|Sort-Object -Unique)
    if($sources.Count -ne 1){throw 'V041_MULTIPLE_OR_NO_CLI_COMMANDS'}
    $exe=Assert-XpuiReadOnlyCanonicalV036 -Path $sources[0] -Label 'CLI'
    if(-not[IO.File]::Exists($exe)){throw 'V041_CLI_NOT_PRESENT'}
    $actual=(Get-FileHash -LiteralPath $exe -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
    if($actual -cne '3563f26acd7527adc97e6c19272fa1b48ce976a913625d9804ac57d3c54fb4db'){
      throw 'V041_OFFICIAL_CLI_2464_PIN_MISMATCH'
    }
    $pin=$true
    $config=Join-Path (Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::ApplicationData)) 'spicetify') 'config-xpui.ini'
    $origin='official-cli-pinned-config-default-path-inferred-no-execution'
  }
  $exe=Assert-XpuiReadOnlyCanonicalV036 -Path $exe -Label 'CLI'
  $config=Assert-XpuiReadOnlyCanonicalV036 -Path $config -Label 'CONFIG'
  if(-not[IO.File]::Exists($exe) -or -not[IO.File]::Exists($config)){
    throw 'V041_CLI_OR_CONFIG_FILE_MISSING'
  }
  $stamp=(Get-FileHash -LiteralPath $config -Algorithm SHA256 -ErrorAction Stop).Hash
  $ini=Read-XpuiReadOnlyIniV036 -Path $config
  $folder=Assert-XpuiReadOnlyCanonicalV036 -Path (Join-Path (Split-Path -Parent $config) 'CustomApps') -Label 'USER_APPS'
  $exeFolder=Assert-XpuiReadOnlyCanonicalV036 -Path (Join-Path (Split-Path -Parent $exe) 'CustomApps') -Label 'CLI_APPS'
  $known=@('ivlyrics','better-local-files','eternal-jukebox','playlist-maker')
  $raw=if($ini.ContainsKey('additionaloptions.custom_apps')){[string]$ini['additionaloptions.custom_apps']}else{''}
  if($raw -match '[;,]'){throw 'V041_CONFIG_APPS_SEPARATOR_UNEXPECTED'}
  $listed=@($raw -split '\|'|Where-Object{-not[string]::IsNullOrWhiteSpace($_)})
  $seen=@{}
  [int]$approved=0;[int]$other=0
  [int]$userOrigin=0;[int]$cliOrigin=0;[int]$missing=0;[int]$incomplete=0
  [int]$nested=0;[int]$shadowed=0
  foreach($entry in $listed){
    $name=$entry.Trim().ToLowerInvariant()
    if($name -cnotmatch '^[a-z0-9-]{1,64}$' -or $seen.ContainsKey($name)){
      throw 'V041_CONFIG_APP_DUPLICATE_OR_INVALID'
    }
    $seen[$name]=$true
    if($name -notin $known){
      $other++
      continue # Out-of-scope apps are NEVER enumerated or modified.
    }
    $approved++
    $primary=Assert-XpuiReadOnlyCanonicalV036 -Path (Join-Path $folder $name) -Label 'USER_APP'
    $fallback=Assert-XpuiReadOnlyCanonicalV036 -Path (Join-Path $exeFolder $name) -Label 'CLI_APP'
    $primaryExists=[IO.Directory]::Exists($primary)
    $fallbackExists=[IO.Directory]::Exists($fallback)
    if($primaryExists -and $fallbackExists){$shadowed++}
    if($primaryExists){$userOrigin++;$chosen=$primary}
    elseif($fallbackExists){$cliOrigin++;$chosen=$fallback}
    else{$missing++;continue}
    $selected=Get-ApprovedAppOriginNestedV041 -Root $chosen
    if([bool]$selected.nested){$nested++}
    $index=Assert-XpuiReadOnlyCanonicalV036 -Path (Join-Path ([string]$selected.path) 'index.js') -Label 'APP_INDEX'
    $manifest=Assert-XpuiReadOnlyCanonicalV036 -Path (Join-Path ([string]$selected.path) 'manifest.json') -Label 'APP_MANIFEST'
    if(-not[IO.File]::Exists($index) -or -not[IO.File]::Exists($manifest)){
      $incomplete++
    }
  }
  if($approved -ne [int]$existing.approved_config_apps -or $other -ne [int]$existing.other_config_apps){
    throw 'V041_CONFIG_APP_LIST_CHANGED_DURING_INSPECTION'
  }
  if((Get-FileHash -LiteralPath $config -Algorithm SHA256 -ErrorAction Stop).Hash -cne $stamp){
    throw 'V041_CONFIGURATION_CHANGED_DURING_READONLY_INVENTORY'
  }
  # Do not declare any production permission: this checks locations only.
  return [pscustomobject]@{
    schema=1;status='observed-readonly'
    reason='source-origins-mapped-without-mutation-authority'
    official_cli_source_resolution=$origin
    exact_cli_sha_verified=$pin
    approved_config_apps=$approved;other_config_apps=$other
    approved_user_origin=$userOrigin;approved_cli_origin=$cliOrigin
    approved_source_missing=$missing;approved_source_incomplete=$incomplete
    approved_nested_source=$nested;approved_origin_shadowed=$shadowed
    approved_sources_discovered=($approved - $missing)
    all_approved_sources_structurally_complete=($missing -eq 0 -and $incomplete -eq 0)
    nonapproved_apps_are_unmanaged_not_necessarily_unsafe=$true
    unknown_apps_preserved=$true
    config_path_exposed=$false;app_names_exposed=$false
    spotify_prefs_content_read=$false;app_source_content_read=$false
    network_used=$false;process_started=$false;files_modified=$false
    apply_authorized=$false;terminal_commit_authorized=$false
    production_mutation_authorized=$false
  }
 }catch{
  # Never return raw exceptions, names, file contents or absolute paths.
  $msg=[string]$_.Exception.Message
  $why=if($msg -cmatch '^(V041_[A-Z0-9_]+)'){$matches[1]}else{'V041_SOURCE_ORIGIN_UNVERIFIED'}
  return & $deny $why
 }
}
