# Development HOLD: native Windows File.Replace scratch acceptance for a
# WHOLE TWO-SCRIPT guarded source pair, using real source bytes and the V047
# OS lock. Only Windows github-hosted RUNNER_TEMP. Never write installed
# SpotifyControl, user profiles, scheduled tasks, or real new engine journals.
# Independent recovery requires either an exact external SHA pin or
# unambiguous CurrentUser DPAPI-authenticated discovery; never grants GO.
Set-StrictMode -Version 2.0
function Assert-V064([bool]$ok,[string]$reason){
 if(-not$ok){throw ('V064_'+$reason)}
}
function Get-V064Sha([string]$path){
 return (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}
function Assert-V064HostedFixture {
 param([Parameter(Mandatory=$true)][string]$FixtureRoot)
 Assert-V064 (
  [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT -and
  $env:GITHUB_ACTIONS -ceq 'true' -and
  $env:RUNNER_OS -ceq 'Windows' -and
  $env:RUNNER_ENVIRONMENT -ceq 'github-hosted' -and
  -not[string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)
 ) 'GITHUB_HOSTED_WINDOWS_ONLY'
 $runner=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
 $root=[IO.Path]::GetFullPath($FixtureRoot).TrimEnd('\','/')
 Assert-V064 (
  $root.StartsWith(($runner+'\'),[StringComparison]::OrdinalIgnoreCase) -and
  [IO.Path]::GetFileName($root) -cmatch '^v064-source-[a-f0-9]{32}$'
 ) 'UNOWNED_FIXTURE_ROOT'
 $local=Join-Path $root 'Local'
 $legacy=Join-Path $local 'SpotifyControl'
 $bin=Join-Path $legacy 'bin'
 $recovery=Join-Path $root 'Recovery'
 foreach($dir in @($root,$local,$legacy,$bin,$recovery)){
  $item=Get-Item -LiteralPath $dir -Force -ErrorAction Stop
  Assert-V064 ($item.PSIsContainer -and
   ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) 'FIXTURE_DIRECTORY_REPARSE'
 }
 return [pscustomobject]@{
  root=$root;local=$local;legacy=$legacy;bin=$bin;recovery=$recovery
  main=(Join-Path $bin 'spotify-control.ps1')
  addon=(Join-Path $bin 'addon-manager.ps1')
  oldMain='af1582ec335807f8f5daa9b3a65b13d567264f326d3c608c082ae02ff0a4cfc0'
  oldAddon='5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285'
 }
}
function Assert-V064ExistingFile {
 param([Parameter(Mandatory=$true)][string]$Path,
       [Parameter(Mandatory=$true)][string]$Sha256)
 $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
 Assert-V064 (-not$item.PSIsContainer -and
  ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -and
  [int64]$item.Length -gt 1 -and [int64]$item.Length -lt 4000000 -and
  (Get-V064Sha $Path) -ceq $Sha256) 'EXPECTED_REGULAR_SOURCE_FILE_SHA_CHANGED'
}
function Get-V064BundleAttestation {
 param([Parameter(Mandatory=$true)][string]$BundleRoot,
       [Parameter(Mandatory=$true)]$Paths)
 $runner=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
 $bundle=[IO.Path]::GetFullPath($BundleRoot).TrimEnd('\','/')
 Assert-V064 ($bundle.StartsWith(($runner+'\'),[StringComparison]::OrdinalIgnoreCase) -and
  [IO.Path]::GetFileName($bundle) -ceq 'guarded-source-HOLD') 'NOT_OUR_HOSTED_BUNDLE'
 $manifest=Join-Path $bundle 'MANIFEST-HOLD.json'
 $meta=Get-Item -LiteralPath $manifest -Force -ErrorAction Stop
 Assert-V064 (-not$meta.PSIsContainer -and
  ($meta.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -and
  [int64]$meta.Length -lt 16384) 'MANIFEST_NOT_SAFE'
 $utf8=[Text.UTF8Encoding]::new($false,$true)
 $j=$utf8.GetString([IO.File]::ReadAllBytes($manifest))|ConvertFrom-Json -ErrorAction Stop
 Assert-V064 ([int]$j.schema -eq 1 -and
  [string]$j.owner -ceq 'SpotifyControl-v0628-r17-guarded-source-HOLD' -and
  [string]$j.original_main_sha256 -ceq $Paths.oldMain -and
  [string]$j.original_addon_sha256 -ceq $Paths.oldAddon -and
  [string]$j.main_file -ceq 'bin/spotify-control.ps1' -and
  [string]$j.addon_file -ceq 'bin/addon-manager.ps1' -and
  [string]$j.candidate_main_sha256 -cmatch '^[a-f0-9]{64}$' -and
  [string]$j.candidate_addon_sha256 -cmatch '^[a-f0-9]{64}$' -and
  -not[bool]$j.deployable -and
  -not[bool]$j.production_mutation_authorized) 'INVALID_COHERENT_BUNDLE_MANIFEST'
 $bm=Join-Path $bundle 'bin\spotify-control.ps1'
 $ba=Join-Path $bundle 'bin\addon-manager.ps1'
 foreach($dir in @($bundle,(Join-Path $bundle 'bin'))){
  $item=Get-Item -LiteralPath $dir -Force -ErrorAction Stop
  Assert-V064 ($item.PSIsContainer -and
   ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) 'BUNDLE_DIRECTORY_REPARSE'
 }
 Assert-V064ExistingFile -Path $bm -Sha256 ([string]$j.candidate_main_sha256)
 Assert-V064ExistingFile -Path $ba -Sha256 ([string]$j.candidate_addon_sha256)
 return [pscustomobject]@{main=$bm;addon=$ba
  newMain=[string]$j.candidate_main_sha256
  newAddon=[string]$j.candidate_addon_sha256}
}
function Copy-V064DurableNew {
 param([Parameter(Mandatory=$true)][string]$Source,
       [Parameter(Mandatory=$true)][string]$Target,
       [Parameter(Mandatory=$true)][string]$ExpectedSha)
 $read=[IO.File]::Open($Source,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
 try{
  $write=[IO.File]::Open($Target,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try{
    $read.CopyTo($write)
    $write.Flush($true)
  }finally{$write.Dispose()}
 }finally{$read.Dispose()}
 Assert-V064 ((Get-V064Sha $Target) -ceq $ExpectedSha) 'DURABLE_NEW_FILE_HASH_MISMATCH'
}
function New-V064SourceIntent {
 param([Parameter(Mandatory=$true)]$Paths,
       [Parameter(Mandatory=$true)]$Bundle,
       [Parameter(Mandatory=$true)][string]$Nonce)
 $journal=Join-Path $Paths.recovery ('source-pair-intent-'+$Nonce+'.dpapi')
 $record=[ordered]@{
  schema=1;owner='V064_GITHUB_HOSTED_SOURCE_PAIR_ONLY'
  fixture_root=$Paths.root;id=$Nonce
  old_main_sha256=$Paths.oldMain;old_addon_sha256=$Paths.oldAddon
  candidate_main_sha256=$Bundle.newMain;candidate_addon_sha256=$Bundle.newAddon
  backup_main='original-main-'+$Nonce+'.bak'
  backup_addon='original-addon-'+$Nonce+'.bak'
  production_mutation_authorized=$false;source_pair_cutover_authorized=$false
 }
 # A current-user DPAPI-protected intent is recoverable with no external
 # receipt if the publisher dies AFTER the journal flush but BEFORE return.
 # DPAPI does NOT stop arbitrary hostile code executing as the same user.
 Add-Type -AssemblyName System.Security -ErrorAction Stop
 $utf8=[Text.UTF8Encoding]::new($false,$true)
 $entropy=$utf8.GetBytes('V064-HOSTED-SOURCE-INTENT|'+$Paths.root+'|'+$Nonce)
 $plain=$utf8.GetBytes(($record|ConvertTo-Json -Compress -Depth 3))
 $cipher=$null
 try{
  $cipher=[Security.Cryptography.ProtectedData]::Protect(
    $plain,$entropy,[Security.Cryptography.DataProtectionScope]::CurrentUser)
  $f=[IO.File]::Open($journal,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try{$f.Write($cipher,0,$cipher.Length);$f.Flush($true)}finally{$f.Dispose()}
 }finally{
  [Array]::Clear($plain,0,$plain.Length)
  [Array]::Clear($entropy,0,$entropy.Length)
  if($null-ne$cipher){[Array]::Clear($cipher,0,$cipher.Length)}
 }
 return [pscustomobject]@{path=$journal;sha=(Get-V064Sha $journal);record=$record}
}
function Start-V064HostedSourcePairPublish {
 param([Parameter(Mandatory=$true)][string]$FixtureRoot,
       [Parameter(Mandatory=$true)][string]$BundleRoot,
       [ValidateSet('none','after-main','after-addon')][string]$InjectStop='none',
       [switch]$ExplicitHostedSimulationApproval)
 Assert-V064 ([bool]$ExplicitHostedSimulationApproval) 'HOSTED_SIMULATION_APPROVAL_REQUIRED'
 $p=Assert-V064HostedFixture -FixtureRoot $FixtureRoot
 $b=Get-V064BundleAttestation -BundleRoot $BundleRoot -Paths $p
 # Both existing installed files are exact, unmodified stable source
 # snapshots. NO arbitrary or divergent source replacement allowed.
 Assert-V064ExistingFile -Path $p.main -Sha256 $p.oldMain
 Assert-V064ExistingFile -Path $p.addon -Sha256 $p.oldAddon
 . (Join-Path $PSScriptRoot 'engine-turnstile-v047.ps1')
 . (Join-Path $PSScriptRoot '..\normal-engine-cutover-readonly\cutover-admission-v046.ps1')
 $lease=$null
 try{
  $lease=Enter-CustomAppEngineTurnstileV047 -HostedCiRoot $p.local
  $legacy=Get-CustomAppCutoverLegacyStateV046 -LocalRoot $p.local
  Assert-V064 ([bool]$legacy.legacy_transaction_absent -and
   [bool]$legacy.dpapi_new_engine_absent) 'LEGACY_TRANSACTION_OR_NEW_ENGINE_PRESENT'
  $nonce=[guid]::NewGuid().ToString('N')
  $stageMain=Join-Path $p.bin ('main-stage-'+$nonce+'.new')
  $stageAddon=Join-Path $p.bin ('addon-stage-'+$nonce+'.new')
  Copy-V064DurableNew -Source $b.main -Target $stageMain -ExpectedSha $b.newMain
  Copy-V064DurableNew -Source $b.addon -Target $stageAddon -ExpectedSha $b.newAddon
  $intent=New-V064SourceIntent -Paths $p -Bundle $b -Nonce $nonce
  # A durable journal is written and verified BEFORE the first File.Replace.
  Assert-V064 ((Get-V064Sha $intent.path) -ceq $intent.sha) 'PRE_REPLACE_INTENT_NOT_DURABLE'
  Assert-V064ExistingFile -Path $p.main -Sha256 $p.oldMain
  Assert-V064ExistingFile -Path $p.addon -Sha256 $p.oldAddon
  $again=Get-CustomAppCutoverLegacyStateV046 -LocalRoot $p.local
  Assert-V064 ([string]$again.state_sha256 -ceq [string]$legacy.state_sha256) 'LEGACY_STATE_CHANGED_UNDER_LEASE'
  [IO.File]::Replace($stageMain,$p.main,
   (Join-Path $p.recovery ([string]$intent.record.backup_main)),$false)
  Assert-V064ExistingFile -Path $p.main -Sha256 $b.newMain
  Assert-V064ExistingFile -Path (Join-Path $p.recovery ([string]$intent.record.backup_main)) -Sha256 $p.oldMain
  if($InjectStop -ceq 'after-main'){
   return [pscustomobject]@{status='HOSTED_INJECTED_STOP_AFTER_FIRST_REPLACE'
    journal=$intent.path;journal_sha256=$intent.sha
    production_mutation_authorized=$false;real_profile_written=$false}
  }
  Assert-V064ExistingFile -Path $p.addon -Sha256 $p.oldAddon
  [IO.File]::Replace($stageAddon,$p.addon,
   (Join-Path $p.recovery ([string]$intent.record.backup_addon)),$false)
  Assert-V064ExistingFile -Path $p.addon -Sha256 $b.newAddon
  Assert-V064ExistingFile -Path (Join-Path $p.recovery ([string]$intent.record.backup_addon)) -Sha256 $p.oldAddon
  Assert-V064ExistingFile -Path $p.main -Sha256 $b.newMain
  $status=if($InjectStop -ceq 'after-addon'){
    'HOSTED_INJECTED_STOP_AFTER_TWO_REPLACES'
  }else{'HOSTED_SOURCE_PAIR_ONLY_COMMITTED'}
  return [pscustomobject]@{status=$status
    journal=$intent.path;journal_sha256=$intent.sha
    production_mutation_authorized=$false;real_profile_written=$false
    source_pair_published=$true}
 }finally{if($null-ne$lease){$lease.Dispose()}}
}
function Restore-V064HostedSourcePair {
 param([Parameter(Mandatory=$true)][string]$FixtureRoot,
       [string]$Journal=$null,
       [string]$JournalSha256=$null)
 $p=Assert-V064HostedFixture -FixtureRoot $FixtureRoot
 $providedPath=-not[string]::IsNullOrWhiteSpace($Journal)
 $providedPin=-not[string]::IsNullOrWhiteSpace($JournalSha256)
 Assert-V064 ($providedPath -eq $providedPin) 'PARTIAL_EXTERNAL_JOURNAL_PIN'
 if($providedPath){
  Assert-V064 ($JournalSha256 -cmatch '^[a-f0-9]{64}$') 'EXTERNAL_JOURNAL_PIN_INVALID'
  $path=[IO.Path]::GetFullPath($Journal)
 }else{
  # With a lost receipt, recover only if exactly one intent-like entry
  # exists. A collision, malformed name or link cannot be silently ignored.
  $all=@(Get-ChildItem -LiteralPath $p.recovery -Force -ErrorAction Stop|
   Where-Object{$_.Name.StartsWith('source-pair-intent-',
      [StringComparison]::OrdinalIgnoreCase)})
  Assert-V064 ($all.Count -eq 1) 'DISCOVERY_REQUIRES_ONE_UNAMBIGUOUS_INTENT'
  $path=[IO.Path]::GetFullPath([string]$all[0].FullName)
 }
 Assert-V064 ($path.StartsWith(($p.recovery+'\'),[StringComparison]::OrdinalIgnoreCase) -and
  [IO.Path]::GetFileName($path) -cmatch '^source-pair-intent-[a-f0-9]{32}\.dpapi$') 'INTENT_LOCATION_OR_NAME_UNTRUSTED'
 $item=Get-Item -LiteralPath $path -Force -ErrorAction Stop
 Assert-V064 (-not$item.PSIsContainer -and
  ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -and
  [int64]$item.Length -gt 150 -and [int64]$item.Length -lt 8192) 'INTENT_FILE_NOT_BOUNDED'
 if($providedPath){
  Assert-V064 ((Get-V064Sha $path) -ceq $JournalSha256) 'EXTERNAL_JOURNAL_CIPHERTEXT_SHA_CHANGED'
 }
 $nonce=[IO.Path]::GetFileNameWithoutExtension($path).Substring('source-pair-intent-'.Length)
 $utf8=[Text.UTF8Encoding]::new($false,$true)
 Add-Type -AssemblyName System.Security -ErrorAction Stop
 $cipher=[IO.File]::ReadAllBytes($path)
 $entropy=$utf8.GetBytes('V064-HOSTED-SOURCE-INTENT|'+$p.root+'|'+$nonce)
 $plain=$null
 try{
  try{
   $plain=[Security.Cryptography.ProtectedData]::Unprotect(
      $cipher,$entropy,[Security.Cryptography.DataProtectionScope]::CurrentUser)
  }catch{
   throw 'V064_INTENT_DPAPI_INTEGRITY_OR_USER_MISMATCH'
  }
  Assert-V064 ($plain.Length -gt 150 -and $plain.Length -lt 8192) 'INTENT_DECRYPTED_LENGTH_INVALID'
  $record=$utf8.GetString($plain)|ConvertFrom-Json -ErrorAction Stop
 }finally{
  [Array]::Clear($cipher,0,$cipher.Length)
  [Array]::Clear($entropy,0,$entropy.Length)
  if($null-ne$plain){[Array]::Clear($plain,0,$plain.Length)}
 }
 $fields=@('schema','owner','fixture_root','id','old_main_sha256','old_addon_sha256',
  'candidate_main_sha256','candidate_addon_sha256',
  'backup_main','backup_addon','production_mutation_authorized','source_pair_cutover_authorized')
 Assert-V064 (
  @($record.PSObject.Properties).Count -eq $fields.Count -and
  @($fields|Where-Object{$null-eq$record.PSObject.Properties[$_]}).Count -eq 0 -and
  [int]$record.schema -eq 1 -and
  [string]$record.owner -ceq 'V064_GITHUB_HOSTED_SOURCE_PAIR_ONLY' -and
  [string]$record.fixture_root -ceq $p.root -and
  [string]$record.id -ceq $nonce -and
  [string]$record.old_main_sha256 -ceq $p.oldMain -and
  [string]$record.old_addon_sha256 -ceq $p.oldAddon -and
  [string]$record.candidate_main_sha256 -cmatch '^[a-f0-9]{64}$' -and
  [string]$record.candidate_addon_sha256 -cmatch '^[a-f0-9]{64}$' -and
  [string]$record.backup_main -ceq ('original-main-'+$nonce+'.bak') -and
  [string]$record.backup_addon -ceq ('original-addon-'+$nonce+'.bak') -and
  $record.production_mutation_authorized -is [bool] -and
  -not[bool]$record.production_mutation_authorized -and
  $record.source_pair_cutover_authorized -is [bool] -and
  -not[bool]$record.source_pair_cutover_authorized
 ) 'INTENT_INVALID_SCHEMA_OR_OWNER_OR_SOURCE'
 . (Join-Path $PSScriptRoot 'engine-turnstile-v047.ps1')
 $lease=$null
 try{
  $lease=Enter-CustomAppEngineTurnstileV047 -HostedCiRoot $p.local
  # No file is modified until ALL destinations have been classified and
  # EVERY required preimage backup is verified. Never overwrite a file
  # changed by another writer.
  $records=@(
   [pscustomobject]@{target=$p.addon;old=$p.oldAddon;new=[string]$record.candidate_addon_sha256
    backup=(Join-Path $p.recovery ([string]$record.backup_addon));label='addon'},
   [pscustomobject]@{target=$p.main;old=$p.oldMain;new=[string]$record.candidate_main_sha256
    backup=(Join-Path $p.recovery ([string]$record.backup_main));label='main'}
  )
  foreach($part in $records){
   $target=(Get-V064Sha ([string]$part.target))
   Assert-V064 ($target -cin @([string]$part.old,[string]$part.new)) (
    'UNRECOGNIZED_CONCURRENT_SOURCE_DRIFT_'+$part.label)
   if($target -ceq [string]$part.new){
    Assert-V064ExistingFile -Path ([string]$part.backup) -Sha256 ([string]$part.old)
   }
  }
  $count=0
  foreach($part in $records){
   if((Get-V064Sha ([string]$part.target)) -ceq [string]$part.old){continue}
   $stage=Join-Path $p.bin ('restore-'+$part.label+'-'+$nonce+'.new')
   Copy-V064DurableNew -Source ([string]$part.backup) -Target $stage -ExpectedSha ([string]$part.old)
   $replaced=Join-Path $p.recovery ('discarded-candidate-'+$part.label+'-'+$nonce+'.bak')
   [IO.File]::Replace($stage,[string]$part.target,$replaced,$false)
   Assert-V064ExistingFile -Path ([string]$part.target) -Sha256 ([string]$part.old)
   Assert-V064ExistingFile -Path $replaced -Sha256 ([string]$part.new)
   $count++
  }
  Assert-V064ExistingFile -Path $p.main -Sha256 $p.oldMain
  Assert-V064ExistingFile -Path $p.addon -Sha256 $p.oldAddon
  return [pscustomobject]@{
   status='HOSTED_OLD_SOURCES_RESTORED_FROM_JOURNAL'
   files_rolled_back=$count
   preimage_backups_preserved=$true
   recovery_journal_retained=$true
   source_bytes_exact=$true
   production_mutation_authorized=$false;real_profile_written=$false
  }
 }finally{if($null-ne$lease){$lease.Dispose()}}
}
