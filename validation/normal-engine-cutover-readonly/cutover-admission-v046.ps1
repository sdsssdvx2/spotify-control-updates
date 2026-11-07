# V046: read-only user-profile cutover admission for actual Addon Manager.
# This is the FIRST boundary for retiring legacy automatic CustomApp updates:
# no old transaction, no new DPAPI enrollment, coherent V042 config+CLI+
# approved-source+whole-XPUI preimage, stable current legacy state.
# It NEVER enrolls, starts Spicetify, edits Spotify, backs up, migrates or
# authorizes any update. A live executor must obtain its own exclusive
# process/transaction barrier, fresh source+XPUI proof and user approval.
#
# Dependency: V010 transaction read-only snapshots + V036/V041/V042 read-only
# modules already loaded. This module contains no dynamic file import.
function Assert-CustomAppCutoverLocalRootV046 {
 param([Parameter(Mandatory=$true)][string]$Root)
 if([string]::IsNullOrWhiteSpace($Root) -or
    -not[IO.Path]::IsPathRooted($Root) -or
    $Root.StartsWith('\\',[StringComparison]::Ordinal)){
    throw 'V046_LOCAL_PROFILE_PATH_UNTRUSTED'
 }
 $p=[IO.Path]::GetFullPath($Root).TrimEnd('\','/')
 if(-not[IO.Directory]::Exists($p)){
    throw 'V046_LOCAL_PROFILE_MISSING'
 }
 $item=Get-Item -LiteralPath $p -Force -ErrorAction Stop
 if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
    throw 'V046_LOCAL_PROFILE_REPARSE'
 }
 return $p
}
function Test-CustomAppCutoverNamedEntryV046 {
 param([Parameter(Mandatory=$true)][string]$Parent,
       [Parameter(Mandatory=$true)][string]$Name)
 if(-not[IO.Directory]::Exists($Parent)){return $false}
 # Enumerate rather than rely only on File.Exists: it silently returns false
 # for some dangling reparse points, which must still block transition.
 return (@(Get-ChildItem -LiteralPath $Parent -Force -ErrorAction Stop |
   Where-Object { $_.Name.Equals($Name,[StringComparison]::OrdinalIgnoreCase) }).Count -ne 0)
}
function Get-CustomAppCutoverLegacyStateV046 {
 param([Parameter(Mandatory=$true)][string]$LocalRoot)
 $root=Assert-CustomAppCutoverLocalRootV046 -Root $LocalRoot
 $legacy=Join-Path $root 'SpotifyControl'
 $new=Join-Path $root 'SpotifyControlUpdates-CustomApp-State'
 if(Test-CustomAppCutoverNamedEntryV046 -Parent $root -Name 'SpotifyControlUpdates-CustomApp-State' -or
    [IO.Directory]::Exists($new) -or [IO.File]::Exists($new) -or
    (Test-Path -LiteralPath $new -ErrorAction SilentlyContinue)){
    throw 'V046_NEW_ENGINE_ALREADY_ENROLLED_REQUIRE_EXISTING_JOURNAL_RECOVERY'
 }
 if(-not[IO.Directory]::Exists($legacy)){
    throw 'V046_EXISTING_LEGACY_ADDON_ROOT_MISSING'
 }
 $dir=Get-Item -LiteralPath $legacy -Force -ErrorAction Stop
 if(($dir.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
    throw 'V046_LEGACY_ADDON_ROOT_REPARSE'
 }
 if(Test-CustomAppCutoverNamedEntryV046 -Parent $legacy -Name 'addon-last-transaction.json'){
    # Do not parse or archive live legacy journals here. Presence alone
    # means a pending/uncertain last transaction requires its own terminal.
    throw 'V046_LEGACY_TRANSACTION_STILL_PRESENT_DO_NOT_MIGRATE'
 }
 $stateFile=Join-Path $legacy 'addons-state.json'
 if(-not[IO.File]::Exists($stateFile) -or
    -not(Test-CustomAppCutoverNamedEntryV046 -Parent $legacy -Name 'addons-state.json')){
    throw 'V046_LEGACY_CURRENT_STATE_ABSENT'
 }
 $file=Get-Item -LiteralPath $stateFile -Force -ErrorAction Stop
 if(($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
    $file.Length -lt 2 -or $file.Length -gt 4194304){
    throw 'V046_LEGACY_CURRENT_STATE_UNSAFE'
 }
 # The state contents are never parsed or printed by the admission. If
 # original StatePath is not this documented user location, reject the
 # higher-level cutover; a future live executor must independently prove it.
 $hash=(Get-FileHash -LiteralPath $stateFile -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
 if($hash -cnotmatch '^[a-f0-9]{64}$'){
    throw 'V046_LEGACY_STATE_HASH_UNVERIFIED'
 }
 return [pscustomobject]@{
   state_sha256=$hash
   state_bytes=[int64]$file.Length
   legacy_transaction_absent=$true
   dpapi_new_engine_absent=$true
 }
}
function Get-CustomAppCutoverReadOnlyAdmissionV046 {
 param([string]$HostedFixtureRoot=$null,
       [string]$HostedFixtureCliPath=$null,
       [switch]$SimulatedSpotifyRunning)
 $deny={param([string]$Reason)
   return [pscustomobject]@{
      schema=1;status='blocked';reason=$Reason
      profile_sha256=$null;legacy_state_sha256=$null
      production_mutation_authorized=$false
      production_enrollment_authorized=$false
      live_execution_authorized=$false
      no_files_modified=$true;no_processes_started=$true
      no_legacy_commit_or_rollback_invoked=$true
   }
 }
 try{
   if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){
      throw 'V046_WINDOWS_ONLY'
   }
   $fixture=-not[string]::IsNullOrWhiteSpace($HostedFixtureRoot)
   if($fixture){
      if($env:GITHUB_ACTIONS -cne 'true' -or
         $env:RUNNER_OS -cne 'Windows' -or
         $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
         [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
          throw 'V046_TEST_PROFILE_OVERRIDE_NOT_HOSTED_WINDOWS'
      }
      $runner=Assert-CustomAppCutoverLocalRootV046 -Root $env:RUNNER_TEMP
      $base=Assert-CustomAppCutoverLocalRootV046 -Root $HostedFixtureRoot
      if(-not$base.StartsWith(($runner+'\'),[StringComparison]::OrdinalIgnoreCase) -or
         [string]::IsNullOrWhiteSpace($HostedFixtureCliPath)){
          throw 'V046_TEST_PROFILE_OVERRIDE_NOT_RUNNER_OWNED'
      }
      $local=Join-Path $base 'Local'
   }else{
      if(-not[string]::IsNullOrWhiteSpace($HostedFixtureCliPath) -or
         [bool]$SimulatedSpotifyRunning){
          throw 'V046_REAL_PROFILE_TEST_OVERRIDE_FORBIDDEN'
      }
      $local=[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
   }
   $local=Assert-CustomAppCutoverLocalRootV046 -Root $local
   $original=Get-CustomAppCutoverLegacyStateV046 -LocalRoot $local
   $profile=Get-ActualSourceXpuiBindingV042 -HostedFixtureRoot $HostedFixtureRoot -HostedFixtureCliPath $HostedFixtureCliPath
   if([string]$profile.status -cne 'observed-readonly' -or
      [string]$profile.binding_sha256 -cnotmatch '^[a-f0-9]{64}$' -or
      [int]$profile.source_tree_count -lt 1 -or
      [int]$profile.xpui_file_count -lt 1 -or
      [bool]$profile.production_mutation_authorized){
      throw 'V046_OFFICIAL_PROFILE_SOURCE_OR_XPUI_UNQUALIFIED'
   }
   $ending=Get-CustomAppCutoverLegacyStateV046 -LocalRoot $local
   if([string]$original.state_sha256 -cne [string]$ending.state_sha256 -or
      [int64]$original.state_bytes -ne [int64]$ending.state_bytes){
      throw 'V046_LEGACY_STATE_CHANGED_DURING_PROFILE_BINDING'
   }
   $current=Test-ActualSourceXpuiBindingV042 -ExpectedBindingSha256 ([string]$profile.binding_sha256) -HostedFixtureRoot $HostedFixtureRoot -HostedFixtureCliPath $HostedFixtureCliPath
   if(-not[bool]$current.ok){
      throw 'V046_PROFILE_SOURCE_OR_XPUI_CHANGED_BEFORE_ADMISSION'
   }
   $final=Get-CustomAppCutoverLegacyStateV046 -LocalRoot $local
   if([string]$ending.state_sha256 -cne [string]$final.state_sha256){
      throw 'V046_LEGACY_STATE_CHANGED_BEFORE_ADMISSION'
   }
   $running=$false
   if($fixture){$running=[bool]$SimulatedSpotifyRunning}
   else{
      $running=(@(Get-Process -Name Spotify -ErrorAction SilentlyContinue).Count -gt 0 -or
          @(Get-Process -Name spicetify -ErrorAction SilentlyContinue).Count -gt 0)
   }
   # No path, user secret, source file, transaction record or manifest body
   # becomes part of the printed result. Binding hash includes all approved
   # sources and the entire XPUI preimage, but is not a durable live lease.
   $stamp=Get-CustomAppUpdateStringSha256V010 -Text (
      (@('v046-readonly-cutover-snapshot',
         [string]$profile.binding_sha256,
         [string]$final.state_sha256,
         [string]$final.state_bytes,
         [string]$profile.source_tree_count,
         [string]$profile.unmanaged_app_count,
         [string]$profile.xpui_file_count)) -join [char]10
   )
   return [pscustomobject]@{
      schema=1
      status=if($running){'deferred'}else{'observed-readonly'}
      reason=if($running){'V046_SPOTIFY_RUNNING_OPERATION_DEFERRED'}else{'V046_CANDIDATE_ELIGIBLE_FOR_FUTURE_ISOLATED_PREPARATION_ONLY'}
      profile_sha256=$stamp
      installed_profile_binding_sha256=[string]$profile.binding_sha256
      legacy_state_sha256=[string]$final.state_sha256
      legacy_transaction_absent=$true
      new_dpapi_engine_unenrolled=$true
      native_cli_and_source_ownership_qualified=$true
      approved_configured_apps=[int]$profile.source_tree_count
      unmanaged_configured_apps=[int]$profile.unmanaged_app_count
      full_xpui_snapshot_sha256=[string]$profile.xpui_tree_sha256
      spotify_running=$running
      full_quiescence_proven=$false
      actual_backup_created=$false
      rollback_snapshot_durable=$false
      source_staging_finished=$false
      process_lease_held=$false
      final_recheck_at_mutation_boundary_required=$true
      explicit_owner_rollout_approval_required=$true
      production_mutation_authorized=$false
      production_enrollment_authorized=$false
      live_execution_authorized=$false
      no_files_modified=$true;no_processes_started=$true
      no_legacy_commit_or_rollback_invoked=$true
      no_new_dpapi_ledger_written=$true
      user_paths_or_app_names_exposed=$false
   }
 }catch{
   $message=[string]$_.Exception.Message
   $reason=if($message -cmatch '^(V046_[A-Z0-9_]+)$'){$matches[1]}else{'V046_CUTOVER_READONLY_INPUT_UNVERIFIED'}
   return & $deny $reason
 }
}
function Test-CustomAppCutoverReadOnlyAdmissionV046 {
 param([Parameter(Mandatory=$true)][string]$ExpectedProfileSha256,
       [string]$HostedFixtureRoot=$null,
       [string]$HostedFixtureCliPath=$null)
 if($ExpectedProfileSha256 -cnotmatch '^[a-f0-9]{64}$'){
   return [pscustomobject]@{ok=$false;reason='V046_INVALID_EXPECTED_SNAPSHOT_SHA';production_mutation_authorized=$false}
 }
 $current=Get-CustomAppCutoverReadOnlyAdmissionV046 -HostedFixtureRoot $HostedFixtureRoot -HostedFixtureCliPath $HostedFixtureCliPath
 if([string]$current.status -cne 'observed-readonly' -or
    [string]$current.profile_sha256 -cne $ExpectedProfileSha256){
   return [pscustomobject]@{ok=$false;reason='V046_CUTOVER_READONLY_SNAPSHOT_CHANGED_OR_DEFERRED';production_mutation_authorized=$false}
 }
 return [pscustomobject]@{
   ok=$true;reason='read-only-inputs-unchanged-requires-fresh-live-admission'
   production_mutation_authorized=$false
   actual_backup_created=$false
   production_enrollment_authorized=$false
 }
}
