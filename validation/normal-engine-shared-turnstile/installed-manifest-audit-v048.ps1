# V048: actual configured approved CustomApps manifest footprint, READ ONLY.
# Requires an already-held V047 cooperative legacy/new engine OS file lease
# and exact V046 pre-enrollment snapshot. Uses V041 source precedence and
# V044 authentic official 2.46.4 output enumeration. Never runs Spicetify,
# enrolls a DPAPI ledger, stages an app, modifies XPUI, or reveals paths.
#
# This is NOT release provenance, durable escrow, a real process sandbox,
# an execution permit, or proof older unpatched Addon Managers are stopped.
# Dot-source AFTER V010, V036/V041/V042, V044, V046 and V047 helpers.
function Get-CustomAppInstalledManifestAuditV048 {
 param([Parameter(Mandatory=$true)]$CutoverLease,
       [Parameter(Mandatory=$true)][string]$ExpectedProfileSha256,
       [string]$HostedFixtureRoot=$null,
       [string]$HostedFixtureCliPath=$null)
 $deny={param([string]$Reason)
   return [pscustomobject]@{
      schema=1;status='blocked';reason=$Reason
      approved_manifest_count=0;owned_output_files=0
      release_provenance_verified=$false
      production_enrollment_authorized=$false
      production_mutation_authorized=$false
      actual_backup_created=$false
      no_files_modified=$true;no_processes_started=$true
      no_network=$true
   }
 }
 try{
   if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){
      throw 'V048_WINDOWS_ONLY'
   }
   if($ExpectedProfileSha256 -cnotmatch '^[a-f0-9]{64}$' -or
      [string]$CutoverLease.status -cne 'locked-readonly' -or
      [string]$CutoverLease.binding_sha256 -cne $ExpectedProfileSha256 -or
      -not[bool]$CutoverLease.cooperative_legacy_engine_lease_held -or
      [bool]$CutoverLease.production_mutation_authorized){
      throw 'V048_CUTOVER_LEASE_OR_EXPECTED_BINDING_INVALID'
   }
   $fixture=-not[string]::IsNullOrWhiteSpace($HostedFixtureRoot)
   if($fixture){
      if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
         $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
         [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
         throw 'V048_FIXTURE_OVERRIDE_NOT_HOSTED_WINDOWS'
      }
      $base=Assert-XpuiReadOnlyCanonicalV036 -Path $HostedFixtureRoot -Label 'V048_FIXTURE'
      $local=Join-Path $base 'Local'
      $config=Join-Path $base 'Roaming\spicetify\config-xpui.ini'
      $cli=Assert-XpuiReadOnlyCanonicalV036 -Path $HostedFixtureCliPath -Label 'V048_FIXTURE_CLI'
   }else{
      if(-not[string]::IsNullOrWhiteSpace($HostedFixtureCliPath) -or
         -not[string]::IsNullOrWhiteSpace($env:SPICETIFY_CONFIG)){
         throw 'V048_CUSTOM_CONFIG_OR_CLI_OVERRIDE_NOT_QUALIFIED'
      }
      $local=[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
      $config=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::ApplicationData)) 'spicetify\config-xpui.ini'
      $sources=@(Get-Command spicetify -CommandType Application -All -ErrorAction Stop |
            ForEach-Object{[string]$_.Source}|Sort-Object -Unique)
      if($sources.Count -ne 1){throw 'V048_REAL_SPICETIFY_CLI_AMBIGUOUS'}
      $cli=Assert-XpuiReadOnlyCanonicalV036 -Path $sources[0] -Label 'V048_CLI'
   }
   $local=Assert-CustomAppCutoverLocalRootV046 -Root $local
   $config=Assert-XpuiReadOnlyCanonicalV036 -Path $config -Label 'V048_CONFIG'
   $cli=Assert-XpuiReadOnlyCanonicalV036 -Path $cli -Label 'V048_CLI'
   $lock=Assert-XpuiReadOnlyCanonicalV036 -Path (Join-Path $local 'SpotifyControl\.engine-cutover-turnstile.lock') -Label 'V048_TURNSTILE'
   $handle=$CutoverLease.lock_handle
   if($null-eq$handle -or $handle -isnot [IO.FileStream] -or
      $handle.SafeFileHandle.IsClosed -or $handle.SafeFileHandle.IsInvalid -or
      -not$handle.CanWrite -or [int64]$handle.Length -ne 0 -or
      -not([string]::Equals([IO.Path]::GetFullPath([string]$handle.Name),
        [IO.Path]::GetFullPath($lock),[StringComparison]::OrdinalIgnoreCase))){
      throw 'V048_OS_TURNSTILE_HANDLE_NOT_LIVE_OR_WRONG_PROFILE'
   }
   $pre=Test-CustomAppCutoverReadOnlyAdmissionV046 -ExpectedProfileSha256 $ExpectedProfileSha256 -HostedFixtureRoot $HostedFixtureRoot -HostedFixtureCliPath $HostedFixtureCliPath
   if(-not[bool]$pre.ok -or [bool]$pre.production_mutation_authorized){
      throw 'V048_PROFILE_OR_LEGACY_STATE_CHANGED_BEFORE_MANIFEST_AUDIT'
   }
   $binding=Get-ActualSourceXpuiBindingV042 -HostedFixtureRoot $HostedFixtureRoot -HostedFixtureCliPath $HostedFixtureCliPath
   $ini=Read-XpuiReadOnlyIniV036 -Path $config
   if(-not$ini.ContainsKey('additionaloptions.custom_apps')){
      throw 'V048_CONFIGURED_APPS_ABSENT'
   }
   $appNames=@(([string]$ini['additionaloptions.custom_apps']) -split '\|' |
         Where-Object{-not[string]::IsNullOrWhiteSpace($_)})
   $approved=@('ivlyrics','better-local-files','eternal-jukebox','playlist-maker')
   $userRoot=Assert-XpuiReadOnlyCanonicalV036 -Path (Join-Path (Split-Path -Parent $config) 'CustomApps') -Label 'V048_USER_APPS'
   $cliRoot=Assert-XpuiReadOnlyCanonicalV036 -Path (Join-Path (Split-Path -Parent $cli) 'CustomApps') -Label 'V048_EXEC_APPS'
   $seen=@{};$rows=New-Object 'System.Collections.Generic.List[string]'
   [int]$count=0;[int]$unknown=0;[int]$files=0;[int]$extensions=0;[int]$assets=0
   foreach($item in $appNames){
      $name=$item.Trim().ToLowerInvariant()
      if($name -cnotmatch '^[a-z0-9-]{1,64}$' -or $seen.ContainsKey($name)){
         throw 'V048_CONFIGURED_APP_NAME_DUPLICATE_OR_INVALID'
      }
      $seen[$name]=$true
      if($name -notin $approved){$unknown++;continue}
      $primary=Assert-XpuiReadOnlyCanonicalV036 -Path (Join-Path $userRoot $name) -Label 'V048_APP_USER_ORIGIN'
      $fallback=Assert-XpuiReadOnlyCanonicalV036 -Path (Join-Path $cliRoot $name) -Label 'V048_APP_CLI_ORIGIN'
      $hasUser=[IO.Directory]::Exists($primary)
      $hasCli=[IO.Directory]::Exists($fallback)
      if($hasUser -eq $hasCli){throw 'V048_APP_ORIGIN_NOT_UNIQUE'}
      $selected=Get-ApprovedAppOriginNestedV041 -Root $(if($hasUser){$primary}else{$fallback})
      if([bool]$selected.nested){
         throw 'V048_NESTED_APP_SOURCE_NEEDS_EXACT_OFFICIAL_CLI_PROOF'
      }
      $source=Assert-XpuiReadOnlyCanonicalV036 -Path ([string]$selected.path) -Label 'V048_APPROVED_SOURCE'
      # V044 mode only ADDS read-only source inspection. Its actual XPUI
      # mutation comparator remains hosted-only and unchanged.
      $manifest=Get-ApprovedNativeManifestOwnedScopeV044 -Name $name -SourceAppPath $source -InstalledReadOnlyAudit
      $owned=@($manifest.owned_files)
      if(-not[bool]$manifest.installed_readonly_audit -or
         [bool]$manifest.production_mutation_authorized -or
         $owned.Count -lt 3 -or $owned.Count -gt 256 -or
         [string]$manifest.source_tree_sha256 -cnotmatch '^[a-f0-9]{64}$' -or
         [string]$manifest.manifest_sha256 -cnotmatch '^[a-f0-9]{64}$'){
         throw 'V048_DECLARED_MANIFEST_OUTPUT_NOT_BOUNDED'
      }
      $count++;$files+=$owned.Count
      $extensions+=[int]$manifest.declared_extensions
      $assets+=[int]$manifest.declared_asset_files
      $rows.Add(($name+'|'+([string]$source).ToLowerInvariant()+'|'+
         [string]$manifest.source_tree_sha256+'|'+
         [string]$manifest.manifest_sha256+'|'+
         ($owned -join ',')+'|'+[string]$manifest.declared_extensions+'|'+
         [string]$manifest.declared_asset_files))
   }
   if($count -ne [int]$binding.source_tree_count -or
      $unknown -ne [int]$binding.unmanaged_app_count -or
      $files -lt ($count*3)){
      throw 'V048_MANIFEST_COUNTS_NOT_BOUND_TO_INSTALLED_PROFILE'
   }
   $post=Get-ActualSourceXpuiBindingV042 -HostedFixtureRoot $HostedFixtureRoot -HostedFixtureCliPath $HostedFixtureCliPath
   if([string]$post.binding_sha256 -cne [string]$binding.binding_sha256){
      throw 'V048_CONFIG_CLI_APPROVED_SOURCE_OR_XPUI_CHANGED_DURING_INSPECTION'
   }
   $end=Test-CustomAppCutoverReadOnlyAdmissionV046 -ExpectedProfileSha256 $ExpectedProfileSha256 -HostedFixtureRoot $HostedFixtureRoot -HostedFixtureCliPath $HostedFixtureCliPath
   if(-not[bool]$end.ok -or [bool]$end.production_mutation_authorized){
      throw 'V048_PROFILE_OR_LEGACY_TRANSACTION_CHANGED_DURING_INSPECTION'
   }
   $list=[string[]]$rows.ToArray()
   [Array]::Sort($list,[StringComparer]::Ordinal)
   $digest=Get-CustomAppUpdateStringSha256V010 -Text (
      (@('v048-installed-approved-manifest-readonly',$ExpectedProfileSha256,
        [string]$binding.binding_sha256,
        [string]$count,[string]$unknown,[string]$files,
        [string]$extensions,[string]$assets)+@($list)) -join [char]10
   )
   return [pscustomobject]@{
      schema=1;status='observed-readonly'
      reason='V048_APPROVED_INSTALLED_MANIFEST_OUTPUTS_STRUCTURALLY_BOUNDED'
      approved_manifest_count=$count;unmanaged_configured_apps=$unknown
      owned_output_files=$files;declared_extensions=$extensions
      declared_asset_files=$assets
      manifest_footprint_sha256=$digest
      installed_profile_binding_sha256=[string]$binding.binding_sha256
      cutover_snapshot_sha256=$ExpectedProfileSha256
      original_legacy_state_unchanged=$true
      exact_manifest_source_trees_rechecked=$true
      all_declared_official_outputs_bounded=$true
      unmanaged_app_source_not_inspected=$true
      os_turnstile_held_during_audit=$true
      release_provenance_verified=$false
      older_unpatched_processes_excluded=$false
      actual_backup_created=$false;restore_ability_proven=$false
      production_enrollment_authorized=$false
      production_mutation_authorized=$false
      no_files_modified=$true;no_processes_started=$true
      no_network=$true;no_user_paths_or_app_names_exposed=$true
   }
 }catch{
   # Don't reveal private absolute paths or actual manifest file content.
   $message=[string]$_.Exception.Message
   $reason=if($message -cmatch '^(V0(?:36|41|42|44|46|47|48)_[A-Z0-9_]+)$'){$matches[1]}else{
       'V048_INSTALLED_MANIFEST_NOT_QUALIFIED'
   }
   return & $deny $reason
 }
}
