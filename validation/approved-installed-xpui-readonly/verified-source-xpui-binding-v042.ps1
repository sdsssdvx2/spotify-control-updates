# V042: immutable READ-ONLY preflight binding between actual Spicetify
# config, official v2.46.4 executable, official CustomApps origin, all
# configured approved app source trees and the ENTIRE installed XPUI tree.
# No executable launch, new ledger, backup, app overwrite or production permit.
# Import after V010 transaction snapshot + V036 + V041 helpers.
function Get-ActualSourceXpuiBindingV042 {
 param([string]$HostedFixtureRoot=$null,[string]$HostedFixtureCliPath=$null)
 $preview=Test-ActualCustomAppOriginsReadOnlyV041 -HostedFixtureRoot $HostedFixtureRoot -HostedFixtureCliPath $HostedFixtureCliPath
 if([string]$preview.status -cne 'observed-readonly' -or
    -not[bool]$preview.all_approved_sources_structurally_complete -or
    [int]$preview.approved_config_apps -lt 1 -or
    [int]$preview.approved_source_missing -ne 0 -or
    [int]$preview.approved_source_incomplete -ne 0 -or
    [int]$preview.approved_origin_shadowed -ne 0){
   throw 'V042_CONFIGURED_APP_OWNERSHIP_NOT_UNAMBIGUOUS'
 }
 $fixture=-not[string]::IsNullOrWhiteSpace($HostedFixtureRoot)
 if($fixture){
   if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
      $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
      [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
      throw 'V042_HOSTED_FIXTURE_NOT_AUTHORIZED_HERE'
   }
   $home=Assert-XpuiReadOnlyCanonicalV036 -Path $HostedFixtureRoot -Label 'FIXTURE'
   $cli=Assert-XpuiReadOnlyCanonicalV036 -Path $HostedFixtureCliPath -Label 'CLI'
   $config=Assert-XpuiReadOnlyCanonicalV036 -Path (Join-Path $home 'Roaming\spicetify\config-xpui.ini') -Label 'CONFIG'
 }else{
   if(-not[string]::IsNullOrWhiteSpace($env:SPICETIFY_CONFIG) -or
      -not[string]::IsNullOrWhiteSpace($HostedFixtureCliPath) -or
      -not[bool]$preview.exact_cli_sha_verified){
      throw 'V042_CLI_IDENTITY_OR_CONFIG_LOCATION_UNQUALIFIED'
   }
   $sources=@(Get-Command spicetify -CommandType Application -All -ErrorAction Stop |
      ForEach-Object { [string]$_.Source } | Sort-Object -Unique)
   if($sources.Count -ne 1){throw 'V042_EXECUTABLE_COMMAND_AMBIGUOUS'}
   $cli=Assert-XpuiReadOnlyCanonicalV036 -Path $sources[0] -Label 'CLI'
   $config=Assert-XpuiReadOnlyCanonicalV036 -Path (Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::ApplicationData)) 'spicetify\config-xpui.ini') -Label 'CONFIG'
 }
 $binaryHash=(Get-FileHash -LiteralPath $cli -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
 if(-not$fixture -and $binaryHash -cne '3563f26acd7527adc97e6c19272fa1b48ce976a913625d9804ac57d3c54fb4db'){
   throw 'V042_OFFICIAL_NATIVE_CLI_SHA_CHANGED'
 }
 $configHash=(Get-FileHash -LiteralPath $config -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
 $ini=Read-XpuiReadOnlyIniV036 -Path $config
 $spotify=Assert-XpuiReadOnlyCanonicalV036 -Path ([string]$ini['setting.spotify_path']) -Label 'SPOTIFY'
 $prefs=Assert-XpuiReadOnlyCanonicalV036 -Path ([string]$ini['setting.prefs_path']) -Label 'PREFS'
 if(-not[IO.Directory]::Exists($spotify) -or -not[IO.File]::Exists($prefs)){
   throw 'V042_SPOTIFY_OR_PREFS_LOCATION_MISSING'
 }
 # The prefs PATH is verified but prefs contents are never read.
 $xpui=Assert-XpuiReadOnlyCanonicalV036 -Path (Join-Path $spotify 'Apps\xpui') -Label 'XPUI'
 if(-not[IO.Directory]::Exists($xpui)){
   throw 'V042_EXTRACTED_XPUI_TREE_REQUIRED'
 }
 $xpuiTree=Get-CustomAppUpdateTreeSnapshotV010 -Root $xpui
 if([string]$xpuiTree.tree_sha256 -cnotmatch '^[a-f0-9]{64}$' -or
    [int]$xpuiTree.file_count -lt 1){
   throw 'V042_XPUI_SOURCE_SNAPSHOT_INVALID'
 }
 $sourceUser=Assert-XpuiReadOnlyCanonicalV036 -Path (Join-Path (Split-Path -Parent $config) 'CustomApps') -Label 'USER_CUSTOMAPPS'
 $sourceCli=Assert-XpuiReadOnlyCanonicalV036 -Path (Join-Path (Split-Path -Parent $cli) 'CustomApps') -Label 'CLI_CUSTOMAPPS'
 $approved=@('ivlyrics','better-local-files','eternal-jukebox','playlist-maker')
 $raw=if($ini.ContainsKey('additionaloptions.custom_apps')){[string]$ini['additionaloptions.custom_apps']}else{''}
 if($raw -match '[;,]'){throw 'V042_UNRECOGNIZED_APP_SEPARATOR'}
 $names=@($raw -split '\|' | Where-Object {-not[string]::IsNullOrWhiteSpace($_)})
 $seen=@{}
 $rows=New-Object 'System.Collections.Generic.List[string]'
 [int]$count=0;[int]$unknown=0;[int]$total=0
 foreach($entry in $names){
   $name=$entry.Trim().ToLowerInvariant()
   if($name -cnotmatch '^[a-z0-9-]{1,64}$' -or $seen.ContainsKey($name)){
     throw 'V042_CONFIGURED_APP_LIST_DUPLICATE_OR_INVALID'
   }
   $seen[$name]=$true
   if($name -notin $approved){$unknown++;continue}
   $primary=Assert-XpuiReadOnlyCanonicalV036 -Path (Join-Path $sourceUser $name) -Label 'USER_SOURCE'
   $fallback=Assert-XpuiReadOnlyCanonicalV036 -Path (Join-Path $sourceCli $name) -Label 'CLI_SOURCE'
   $hasUser=[IO.Directory]::Exists($primary)
   $hasCli=[IO.Directory]::Exists($fallback)
   if($hasUser -eq $hasCli){throw 'V042_APP_NOT_UNIQUELY_OWNED_BY_ONE_SUPPORTED_ROOT'}
   $which=if($hasUser){'user'}else{'executable'}
   $root=if($hasUser){$primary}else{$fallback}
   $leaf=Get-ApprovedAppOriginNestedV041 -Root $root
   $selected=Assert-XpuiReadOnlyCanonicalV036 -Path ([string]$leaf.path) -Label 'SELECTED_APP'
   if(-not[IO.File]::Exists((Join-Path $selected 'index.js')) -or
      -not[IO.File]::Exists((Join-Path $selected 'manifest.json'))){
     throw 'V042_APP_SOURCE_STRUCTURAL_FILES_MISSING'
   }
   $tree=Get-CustomAppUpdateTreeSnapshotV010 -Root $selected
   if([int]$tree.file_count -lt 2 -or
      [string]$tree.tree_sha256 -cnotmatch '^[a-f0-9]{64}$'){
     throw 'V042_APP_SOURCE_HASH_INVALID'
   }
   $count++;$total += [int]$tree.file_count
   # Include full canonical source PATH in fingerprint, but NEVER emit it.
   $rows.Add(($name+'|'+$which+'|'+$selected.ToLowerInvariant()+'|'+
      [string]$tree.tree_sha256+'|'+[string]$tree.file_count+'|'+
      [string]$tree.total_bytes))
 }
 if($count -ne [int]$preview.approved_config_apps -or
    $unknown -ne [int]$preview.other_config_apps -or
    $count -ne [int]$preview.approved_sources_discovered){
   throw 'V042_APP_SOURCE_COUNT_CHANGED_DURING_SNAPSHOT'
 }
 if((Get-FileHash -LiteralPath $config -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant() -cne
    $configHash -or
    (Get-FileHash -LiteralPath $cli -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant() -cne
    $binaryHash){
   throw 'V042_CONFIG_OR_OFFICIAL_CLI_CHANGED_DURING_SNAPSHOT'
 }
 # Absolute paths and private app names are hashed into the binding,
 # never included in the returned structure.
 $parts=[string[]]$rows.ToArray()
 [Array]::Sort($parts,[StringComparer]::Ordinal)
 $binding=Get-CustomAppUpdateStringSha256V010 -Text (
  (@('installed-source-xpui-binding-v042',
    $binaryHash,$configHash,$config.ToLowerInvariant(),
    $spotify.ToLowerInvariant(),$xpui.ToLowerInvariant(),
    [string]$xpuiTree.tree_sha256,[string]$xpuiTree.file_count,
    [string]$xpuiTree.total_bytes,[string]$count,
    [string]$unknown)+@($parts)) -join [char]10)
 return [pscustomobject]@{
   schema=1;status='observed-readonly'
   binding_sha256=$binding
   xpui_tree_sha256=[string]$xpuiTree.tree_sha256
   config_sha256=$configHash
   official_cli_sha256=$binaryHash
   source_tree_count=$count
   source_total_files=$total
   unmanaged_app_count=$unknown
   xpui_file_count=[int]$xpuiTree.file_count
   xpui_total_bytes=[int64]$xpuiTree.total_bytes
   official_executable_origin_approved_count=[int]$preview.approved_cli_origin
   user_config_origin_approved_count=[int]$preview.approved_user_origin
   source_location_binding_includes_canonical_paths_but_never_discloses_them=$true
   unknown_apps_not_read_or_modified=$true
   spotify_prefs_contents_read=$false
   no_network=$true;no_processes_started=$true;no_writes=$true
   recheck_at_transaction_boundary_required=$true
   real_spotify_mutated=$false;production_mutation_authorized=$false
 }
}
function Test-ActualSourceXpuiBindingV042 {
 param([string]$ExpectedBindingSha256,
       [string]$HostedFixtureRoot=$null,
       [string]$HostedFixtureCliPath=$null)
 $fail={param([string]$reason)
   [pscustomobject]@{
     ok=$false;reason=$reason;binding_sha256=$null
     actual_profile_changed=$false;production_mutation_authorized=$false
   }
 }
 try{
   if($ExpectedBindingSha256 -cnotmatch '^[a-f0-9]{64}$'){
     throw 'V042_EXPECTED_BINDING_SHA_INVALID'
   }
   $s=Get-ActualSourceXpuiBindingV042 -HostedFixtureRoot $HostedFixtureRoot -HostedFixtureCliPath $HostedFixtureCliPath
   if([string]$s.binding_sha256 -cne $ExpectedBindingSha256){
     throw 'V042_SOURCE_XPUI_CONFIG_OR_ORIGIN_DRIFTED'
   }
   return [pscustomobject]@{
     ok=$true;reason='byte-pinned-readonly-source-xpui-binding-still-equal'
     binding_sha256=[string]$s.binding_sha256
     actual_profile_changed=$false;production_mutation_authorized=$false
   }
 }catch{
   $why=[string]$_.Exception.Message
   if($why -cnotmatch '^V042_[A-Z0-9_]+$'){$why='V042_READONLY_BINDING_UNVERIFIED'}
   return & $fail $why
 }
}
function Read-ActualSourceXpuiBindingSafeV042 {
 param([string]$HostedFixtureRoot=$null,
       [string]$HostedFixtureCliPath=$null)
 try{
   return Get-ActualSourceXpuiBindingV042 -HostedFixtureRoot $HostedFixtureRoot -HostedFixtureCliPath $HostedFixtureCliPath
 }catch{
   # CI fixture diagnostic only. Never expose actual user paths.
   if($env:GITHUB_ACTIONS -ceq 'true' -and
      -not[string]::IsNullOrWhiteSpace($HostedFixtureRoot) -and
      $env:RUNNER_ENVIRONMENT -ceq 'github-hosted'){
      $safe=([string]$_.Exception.Message).Replace([string]$HostedFixtureRoot,'<fixture>').Replace([string]$env:RUNNER_TEMP,'<runner>')
      Write-Host ('V042_HOSTED_FIXTURE_EXCEPTION='+$_.Exception.GetType().Name+
        ';id='+[string]$_.FullyQualifiedErrorId+
        ';line='+[string]$_.InvocationInfo.ScriptLineNumber+
        ';message='+$safe)
   }
   $why=[string]$_.Exception.Message
   if($why -cnotmatch '^V042_[A-Z0-9_]+$'){$why='V042_SOURCE_XPUI_NOT_QUALIFIED'}
   return [pscustomobject]@{
     schema=1;status='blocked';reason=$why
     source_location_binding_includes_canonical_paths_but_never_discloses_them=$false
     no_writes=$true;production_mutation_authorized=$false
   }
 }
}
