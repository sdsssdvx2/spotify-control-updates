# V049: bounded backup and detached restore-ready preimages, HOSTED FIXTURE ONLY.
# Integrates the actual V047 shared lock + V046 profile identity + V048
# approved-manifest inventory. No Spotify, Addon Manager, or real-user writes.
# Never use this code for production enrollment or as a live execution permit.
# Dot-source after V010, V036/V041/V042, V044, V046/V047/V048.
function Assert-CustomAppHostedPreimagePathV049 {
 param([Parameter(Mandatory=$true)][string]$Path)
 if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
    $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
    [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP) -or
    [Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){
    throw 'V049_HOSTED_WINDOWS_ONLY'
 }
 return Assert-CustomAppUpdateFixturePathV010 -ValidationRoot $env:RUNNER_TEMP -Path $Path -Label 'V049_BOUND_PATH'
}
function Get-CustomAppHostedPreimageFileShaV049 {
 param([Parameter(Mandatory=$true)][string]$Path)
 $p=Assert-CustomAppHostedPreimagePathV049 -Path $Path
 $item=Get-Item -LiteralPath $p -Force -ErrorAction Stop
 if($item.PSIsContainer -or
    ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
    [int64]$item.Length -gt 4194304){
   throw 'V049_UNSAFE_PROTECTED_FILE'
 }
 return (Get-FileHash -LiteralPath $p -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}
function Invoke-CustomAppHostedPreimageRehearsalV049 {
 param([Parameter(Mandatory=$true)]$CutoverLease,
       [Parameter(Mandatory=$true)][string]$ExpectedProfileSha256,
       [Parameter(Mandatory=$true)][string]$HostedFixtureRoot,
       [Parameter(Mandatory=$true)][string]$HostedFixtureCliPath,
       [Parameter(Mandatory=$true)][string]$OutputDirectory)
 $base=Assert-CustomAppHostedPreimagePathV049 -Path $HostedFixtureRoot
 $cli=Assert-CustomAppHostedPreimagePathV049 -Path $HostedFixtureCliPath
 $out=Assert-CustomAppHostedPreimagePathV049 -Path $OutputDirectory
 if([string]::IsNullOrWhiteSpace($HostedFixtureRoot) -or
    (Test-CustomAppUpdatePathsOverlapV010 -A $base -B $out) -or
    (Test-Path -LiteralPath $out)){
    throw 'V049_OUTPUT_NOT_NEW_OR_FIXTURE_OVERLAP'
 }
 $args=@{HostedFixtureRoot=$base;HostedFixtureCliPath=$cli}
 $audit=Get-CustomAppInstalledManifestAuditV048 -CutoverLease $CutoverLease -ExpectedProfileSha256 $ExpectedProfileSha256 @args
 if([string]$audit.status -cne 'observed-readonly' -or
    [int]$audit.approved_manifest_count -ne 3 -or
    [string]$audit.manifest_footprint_sha256 -cnotmatch '^[a-f0-9]{64}$' -or
    -not[bool]$audit.os_turnstile_held_during_audit -or
    [bool]$audit.production_mutation_authorized){
    throw 'V049_LOCKED_APPROVED_MANIFEST_NOT_QUALIFIED'
 }
 # Exact fixture paths are deliberate: no synthetic override may become
 # an arbitrary operating path via config or environment.
 $xpui=Assert-CustomAppHostedPreimagePathV049 -Path (Join-Path $base 'FakeSpotify\Apps\xpui')
 $apps=Assert-CustomAppHostedPreimagePathV049 -Path (Join-Path $base 'VendorCLI\CustomApps')
 $cfg=Assert-CustomAppHostedPreimagePathV049 -Path (Join-Path $base 'Roaming\spicetify\config-xpui.ini')
 $state=Assert-CustomAppHostedPreimagePathV049 -Path (Join-Path $base 'Local\SpotifyControl\addons-state.json')
 $prefs=Assert-CustomAppHostedPreimagePathV049 -Path (Join-Path $base 'Roaming\Spotify\prefs')
 if($cli -cne (Join-Path $base 'VendorCLI\spicetify.exe')){
    throw 'V049_UNEXPECTED_FIXTURE_CLI'
 }
 $ini=Read-XpuiReadOnlyIniV036 -Path $cfg
 if([string]$ini['setting.spotify_path'] -cne (Join-Path $base 'FakeSpotify') -or
    [string]$ini['setting.prefs_path'] -cne $prefs){
    throw 'V049_FIXTURE_CONFIG_NOT_EXACTLY_BOUND'
 }
 $names=@('better-local-files','eternal-jukebox','ivlyrics')
 $before=@{}
 $before['xpui']=Get-CustomAppUpdateTreeSnapshotV010 -Root $xpui
 foreach($name in $names){
   $src=Assert-CustomAppHostedPreimagePathV049 -Path (Join-Path $apps $name)
   [void](Get-ApprovedNativeManifestOwnedScopeV044 -Name $name -SourceAppPath $src -InstalledReadOnlyAudit)
   $before[$name]=Get-CustomAppUpdateTreeSnapshotV010 -Root $src
 }
 $single=@{}
 foreach($key in @('config','state','prefs')){
   $p=switch($key){'config'{$cfg};'state'{$state};'prefs'{$prefs}}
   $single[$key]=Get-CustomAppHostedPreimageFileShaV049 -Path $p
 }
 # No backup creation until all path, lease, manifest and profile tests pass.
 [IO.Directory]::CreateDirectory($out)|Out-Null
 $copyRoot=Join-Path $out 'preimage'
 [IO.Directory]::CreateDirectory($copyRoot)|Out-Null
 $xpuiCopy=Join-Path $copyRoot 'xpui'
 [void](Copy-CustomAppUpdateTreeFixtureV010 -Source $xpui -Destination $xpuiCopy -ValidationRoot $env:RUNNER_TEMP)
 $appCopy=Join-Path $copyRoot 'approved-apps'
 [IO.Directory]::CreateDirectory($appCopy)|Out-Null
 foreach($name in $names){
   [void](Copy-CustomAppUpdateTreeFixtureV010 -Source (Join-Path $apps $name) -Destination (Join-Path $appCopy $name) -ValidationRoot $env:RUNNER_TEMP)
 }
 $guard=Join-Path $copyRoot 'protected'
 [IO.Directory]::CreateDirectory($guard)|Out-Null
 [IO.File]::Copy($cfg,(Join-Path $guard 'config.ini'),$false)
 [IO.File]::Copy($state,(Join-Path $guard 'legacy-state.json'),$false)
 [IO.File]::Copy($prefs,(Join-Path $guard 'prefs'),$false)
 # Verify original inputs and the backup independently after all copying.
 foreach($key in @('xpui')+$names){
   $src=if($key -ceq 'xpui'){$xpui}else{Join-Path $apps $key}
   $dst=if($key -ceq 'xpui'){$xpuiCopy}else{Join-Path $appCopy $key}
   $orig=Get-CustomAppUpdateTreeSnapshotV010 -Root $src
   $copied=Get-CustomAppUpdateTreeSnapshotV010 -Root $dst
   if([string]$orig.tree_sha256 -cne [string]$before[$key].tree_sha256 -or
      [string]$copied.tree_sha256 -cne [string]$before[$key].tree_sha256){
      throw 'V049_INPUT_CHANGED_OR_COPY_NOT_EXACT'
   }
 }
 $filePairs=@{config=@($cfg,(Join-Path $guard 'config.ini'));state=@($state,(Join-Path $guard 'legacy-state.json'));prefs=@($prefs,(Join-Path $guard 'prefs'))}
 foreach($key in @('config','state','prefs')){
   foreach($p in $filePairs[$key]){
     if((Get-CustomAppHostedPreimageFileShaV049 -Path $p) -cne [string]$single[$key]){
        throw 'V049_PROTECTED_INPUT_OR_BACKUP_CHANGED'
     }
   }
 }
 $end=Get-CustomAppInstalledManifestAuditV048 -CutoverLease $CutoverLease -ExpectedProfileSha256 $ExpectedProfileSha256 @args
 if([string]$end.status -cne 'observed-readonly' -or
    [string]$end.manifest_footprint_sha256 -cne [string]$audit.manifest_footprint_sha256){
    throw 'V049_LOCKED_PROFILE_CHANGED_DURING_ESCROW'
 }
 $digests=@{}
 foreach($key in @('xpui')+$names){$digests[$key]=[string]$before[$key].tree_sha256}
 $receipt=[ordered]@{
   schema=1;kind='hosted-only-approved-customapp-preimage'
   expected_profile_sha256=$ExpectedProfileSha256
   manifest_footprint_sha256=[string]$audit.manifest_footprint_sha256
   approved_names=$names
   tree_sha256=$digests
   protected_file_sha256=$single
   production_authorized=$false
 }
 $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($receipt|ConvertTo-Json -Compress -Depth 6))
 $record=Join-Path $out 'receipt.json'
 $fs=[IO.FileStream]::new($record,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
 try{$fs.Write($bytes,0,$bytes.Length);$fs.Flush($true)}finally{$fs.Dispose()}
 $pin=Get-CustomAppHostedPreimageFileShaV049 -Path $record
 return [pscustomobject]@{
   status='hosted-rehearsal-preimages-verified';receipt_sha256=$pin
   approved_apps=3;xpui_files=[int]$before['xpui'].file_count
   manifest_footprint_sha256=[string]$audit.manifest_footprint_sha256
   independent_restore_required=$true;user_spotify_modified=$false
   original_profile_modified=$false;production_backup_durable=$false
   production_enrollment_authorized=$false;production_mutation_authorized=$false
 }
}
function Test-CustomAppHostedPreimageRehearsalV049 {
 param([Parameter(Mandatory=$true)][string]$OutputDirectory,
       [Parameter(Mandatory=$true)][string]$ExpectedReceiptSha256)
 try{
   $out=Assert-CustomAppHostedPreimagePathV049 -Path $OutputDirectory
   if($ExpectedReceiptSha256 -cnotmatch '^[a-f0-9]{64}$'){throw 'V049_BAD_RECEIPT_PIN'}
   $r=Join-Path $out 'receipt.json'
   if((Get-CustomAppHostedPreimageFileShaV049 -Path $r) -cne $ExpectedReceiptSha256){throw 'V049_RECEIPT_CHANGED'}
   $data=[IO.File]::ReadAllText($r,[Text.UTF8Encoding]::new($false,$true))|ConvertFrom-Json
   if([int]$data.schema -ne 1 -or
      [string]$data.kind -cne 'hosted-only-approved-customapp-preimage' -or
      [bool]$data.production_authorized -or @($data.approved_names).Count -ne 3){
      throw 'V049_RECEIPT_CONTENT_INVALID'
   }
   $pre=Join-Path $out 'preimage'
   $map=@{xpui=(Join-Path $pre 'xpui')}
   foreach($name in @('better-local-files','eternal-jukebox','ivlyrics')){
      $map[$name]=Join-Path (Join-Path $pre 'approved-apps') $name
   }
   foreach($key in @('xpui','better-local-files','eternal-jukebox','ivlyrics')){
      $copy=Get-CustomAppUpdateTreeSnapshotV010 -Root $map[$key]
      if([string]$copy.tree_sha256 -cne [string]$data.tree_sha256.$key){
         throw 'V049_PREIMAGE_TREE_NOT_MATCHING_RECEIPT'
      }
   }
   $guards=@{config='config.ini';state='legacy-state.json';prefs='prefs'}
   foreach($key in $guards.Keys){
      $p=Join-Path (Join-Path $pre 'protected') $guards[$key]
      if((Get-CustomAppHostedPreimageFileShaV049 -Path $p) -cne [string]$data.protected_file_sha256.$key){
         throw 'V049_PROTECTED_PREIMAGE_NOT_MATCHING_RECEIPT'
      }
   }
   return [pscustomobject]@{ok=$true;reason='hosted-preimages-reverified';production_mutation_authorized=$false}
 }catch{
   return [pscustomobject]@{ok=$false;reason='V049_RECEIPT_OR_PREIMAGE_NOT_VERIFIED';production_mutation_authorized=$false}
 }
}
