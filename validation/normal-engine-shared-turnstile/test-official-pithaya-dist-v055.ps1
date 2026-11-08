# V055: Fetch immutable upstream Pithaya dist commits and render actual
# Better Local Files + Eternal Jukebox through pinned real Spicetify 2.46.4.
# GitHub-hosted Windows only; no user Spotify, no production authority.
param([Parameter(Mandatory=$true)][string]$OfficialExecutable)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
   $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
 throw 'V055_HOSTED_WINDOWS_ONLY'
}
. (Join-Path $PSScriptRoot '..\custom-app-update-transaction-protocol-v0.1.0\custom-app-update-transaction.ps1')
. (Join-Path $PSScriptRoot '..\approved-native-manifest-scope\manifest-owned-xpui-v044.ps1')
. (Join-Path $PSScriptRoot 'official-route-byte-binding-v054.ps1')
function Assert-V055([bool]$Ok,[string]$Why){if(-not$Ok){throw ('V055_TEST_'+$Why)}}
function Must-Deny-V055([scriptblock]$Body,[string]$Reason){
 $blocked=$false
 try{[void](& $Body)}catch{
   if([string]$_.Exception.Message -ceq $Reason){$blocked=$true}else{throw}
 }
 Assert-V055 $blocked ('EXPECTED_FAIL_CLOSED_'+$Reason)
}
$exe=[IO.Path]::GetFullPath($OfficialExecutable)
$runner=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
$exeHash='3563f26acd7527adc97e6c19272fa1b48ce976a913625d9804ac57d3c54fb4db'
if(-not$exe.StartsWith(($runner+'\'),[StringComparison]::OrdinalIgnoreCase) -or
   -not[IO.File]::Exists($exe) -or
   (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant() -cne $exeHash){
 throw 'V055_UNPINNED_OR_NONRUNNER_VENDOR_EXECUTABLE'
}
# Upstream official publisher branches and exact commit/tree blob IDs,
# observed 2026-11-08. Download-only: these app files are not vendored.
$specs=@(
 [pscustomobject]@{
  name='better-local-files'
  commit='bf467fab93e6c1f8b8d4189dc1054bd1cafb3f3a'
  files=@(
   @('README.md','4b9cc23843b531e303f734f29bc083f2d7c4f7f3',3959),
   @('extension.js','7a0d0fa3fa7d6213ff8add05f849c5deba2004c8',23643),
   @('index.js','fa2dfaeb269dffc2c2a02246c3a5e0e88a656d75',92619),
   @('manifest.json','ccfde34913baeb53acb2df0eda752a65443875dc',858),
   @('preview.png','f87bcac8e6afb7c57cdc0f084df3ed5163d9dd70',254223),
   @('style.css','45f703c97bd5bedb92085f8e2aeea402a9a09da9',29574))
 },
 [pscustomobject]@{
  name='eternal-jukebox'
  commit='78764378798505884cc5c6e40fe7f7ac504d6c8a'
  files=@(
   @('README.md','dfbd600640fbea98d461180687d102fdfaa1c4c4',4475),
   @('extension.js','7763c782566b73dc79b81b58089faa09655ef47e',101549),
   @('index.js','69a7298c814acc14e7575fd79c219fac88ca17ea',45434),
   @('manifest.json','05d47d3009cc19ba0cce9cb26c281fb45b5ad15f',982),
   @('preview.png','c56785a15417df010e3492459cb4e7c5cab46e67',247870),
   @('style.css','11004de4e48351e9f423395b22bd32c2dd3b012b',4720))
 }
)
function Assert-V055PublisherFiles($Spec,[string]$Directory){
 $files=@(Get-ChildItem -LiteralPath $Directory -Force -File)
 if($files.Count -ne @($Spec.files).Count){throw 'V055_UPSTREAM_FILE_SET_CHANGED'}
 foreach($file in @($Spec.files)){
   $filename=[string]$file[0];$blob=[string]$file[1];$length=[long]$file[2]
   $candidate=Join-Path $Directory $filename
   if(-not[IO.File]::Exists($candidate) -or
      (Get-Item -LiteralPath $candidate -Force).Length -ne $length){
      throw 'V055_UPSTREAM_BLOB_FILE_SIZE_MISMATCH'
   }
   $hash=@(& git hash-object --no-filters -- $candidate 2>$null)
   if($LASTEXITCODE -ne 0 -or $hash.Count -ne 1 -or
      [string]$hash[0] -cne $blob){
      throw 'V055_UPSTREAM_COMMIT_TREE_BLOB_MISMATCH'
   }
 }
 return $true
}
function Invoke-V055VendorRefresh([string]$Binary,[string]$Folder,[string]$Name,[string]$FakeSpotify,[string]$Prefs,[string]$Config,[string]$Roaming,[string]$Local){
 $p=New-Object Diagnostics.ProcessStartInfo
 $p.FileName=$Binary
 $p.Arguments='--bypass-admin -n -a refresh'
 $p.WorkingDirectory=$Folder
 $p.UseShellExecute=$false;$p.CreateNoWindow=$true
 $p.RedirectStandardOutput=$true;$p.RedirectStandardError=$true
 $p.EnvironmentVariables['APPDATA']=$Roaming
 $p.EnvironmentVariables['LOCALAPPDATA']=$Local
 $p.EnvironmentVariables['USERPROFILE']=$Folder
 $p.EnvironmentVariables['HOME']=$Folder
 $p.EnvironmentVariables['SPICETIFY_CONFIG']=$Config
 $p.EnvironmentVariables['SPICETIFY_STATE']=(Join-Path $Folder 'PrivateState')
 $proc=New-Object Diagnostics.Process
 try{
  $proc.StartInfo=$p
  if(-not$proc.Start()){throw 'V055_VENDOR_CLI_START_FAILED'}
  if(-not$proc.WaitForExit(60000)){
   $proc.Kill();[void]$proc.WaitForExit()
   throw 'V055_VENDOR_CLI_TIMEOUT'
  }
  $out=$proc.StandardOutput.ReadToEnd()
  $err=$proc.StandardError.ReadToEnd()
  if($proc.ExitCode -ne 0 -or $out.Length+$err.Length -gt 65536){
   throw 'V055_VENDOR_CLI_EXECUTION_FAILED'
  }
 }finally{$proc.Dispose()}
}
foreach($spec in $specs){
 $root=Join-Path $env:RUNNER_TEMP ('v055-'+$spec.name+'-'+[guid]::NewGuid().ToString('N'))
 $vendor=Join-Path $root 'VendorCLI'
 $source=Join-Path $vendor ('CustomApps\'+$spec.name)
 $spotify=Join-Path $root 'FakeSpotify'
 $xpui=Join-Path $spotify 'Apps\xpui'
 $config=Join-Path $root 'PrivateConfig'
 $local=Join-Path $root 'Local'
 $roaming=Join-Path $root 'Roaming'
 $state=Join-Path $vendor 'PrivateState'
 $back=Join-Path $config 'Backup'
 foreach($dir in @($source,$xpui,$config,$local,$roaming,$state,$back)){
   [void][IO.Directory]::CreateDirectory($dir)
 }
 foreach($f in @($spec.files)){
   $filename=[string]$f[0]
   $url='https://raw.githubusercontent.com/Pithaya/spicetify-apps-dist/'+[string]$spec.commit+'/'+$filename
   $destination=Join-Path $source $filename
   Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $destination -ErrorAction Stop
 }
 Assert-V055 (Assert-V055PublisherFiles -Spec $spec -Directory $source) 'UNPINNED_PUBLISHER_SOURCE'
 # The negative test does not need a second network call and never changes
 # the original owner branch. Reject same-name unexpected file edits.
 $idx=Join-Path $source 'index.js'
 $originalBytes=[IO.File]::ReadAllBytes($idx)
 try{
   [IO.File]::AppendAllText($idx,'V055_ADVERSARIAL_TAMPER')
   Must-Deny-V055 {Assert-V055PublisherFiles -Spec $spec -Directory $source} 'V055_UPSTREAM_BLOB_FILE_SIZE_MISMATCH'
 }finally{[IO.File]::WriteAllBytes($idx,$originalBytes)}
 Assert-V055 (Assert-V055PublisherFiles -Spec $spec -Directory $source) 'PUBLISHER_SOURCE_NOT_REVERIFIABLE'
 $bin=Join-Path $vendor 'spicetify.exe'
 [IO.File]::Copy($exe,$bin,$false)
 Assert-V055 ((Get-FileHash $bin -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $exeHash) 'VENDOR_COPY_HASH'
 $prefs=Join-Path $root 'prefs'
 [IO.File]::WriteAllText($prefs,('app.last-launched-version = 1.2.3'+[char]10),([Text.UTF8Encoding]::new($false)))
 [IO.File]::WriteAllBytes((Join-Path $back 'xpui.spa'),[byte[]](0x50,0x4b))
 $foreign=Join-Path $xpui 'user-custom-unmanaged-preserved.dat'
 [IO.File]::WriteAllText($foreign,'PRESERVE_UNMANAGED_BYTES_V055')
 $foreignSha=(Get-FileHash $foreign -Algorithm SHA256).Hash
 $conf='[Setting]'+[Environment]::NewLine+
        'spotify_path = '+$spotify+[Environment]::NewLine+
        'prefs_path = '+$prefs+[Environment]::NewLine+
        'check_spicetify_update = false'+[Environment]::NewLine+
        'current_theme = '+[Environment]::NewLine+
        '[Backup]'+[Environment]::NewLine+
        'version = 1.2.3'+[Environment]::NewLine+
        'with = 2.46.4'+[Environment]::NewLine+
        '[AdditionalOptions]'+[Environment]::NewLine+
        'custom_apps = '+$spec.name+[Environment]::NewLine
 [IO.File]::WriteAllText((Join-Path $config 'config-xpui.ini'),$conf,([Text.UTF8Encoding]::new($false)))
 $before=Get-CustomAppUpdateTreeSnapshotV010 -Root $xpui
 $sourceBefore=Get-CustomAppUpdateTreeSnapshotV010 -Root $source
 # Like the real user's canonical config, this separate ORIGINAL config is
 # never passed to the child. The scoped private clone may be rewritten by
 # Spicetify 2.46.4 even for -a refresh; preservation applies to original.
 $canonical=Join-Path $roaming 'spicetify'
 [IO.Directory]::CreateDirectory($canonical)|Out-Null
 $canonicalIni=Join-Path $canonical 'config-xpui.ini'
 [IO.File]::WriteAllText($canonicalIni,
    ('[AdditionalOptions]'+[Environment]::NewLine+
     'custom_apps = ivLyrics|better-local-files|eternal-jukebox|unmanaged'+[Environment]::NewLine),
    ([Text.UTF8Encoding]::new($false)))
 $canonicalSha=(Get-FileHash $canonicalIni -Algorithm SHA256).Hash
 $prefsSha=(Get-FileHash $prefs -Algorithm SHA256).Hash
 Invoke-V055VendorRefresh -Binary $bin -Folder $vendor -Name $spec.name -FakeSpotify $spotify -Prefs $prefs -Config $config -Roaming $roaming -Local $local
 $after=Get-CustomAppUpdateTreeSnapshotV010 -Root $xpui
 $scope=Get-ApprovedNativeManifestOwnedScopeV044 -Name $spec.name -SourceAppPath $source
 $proof=Test-ApprovedNativeManifestOnlyOwnedTargetChangedV044 -Before $before -After $after -Name $spec.name -SourceAppPath $source -ExpectedSourceTreeSha256 ([string]$sourceBefore.tree_sha256)
 $exact=Test-CustomAppV054OfficialSourceBoundRoutes -Name $spec.name -SourceAppPath $source -CandidateXpuiRoot $xpui -ExpectedSourceTreeSha256 ([string]$sourceBefore.tree_sha256)
 # Parse real go-ini sections and key values. The vendor may re-align
 # whitespace in the disposable config; canonical original must stay exact.
 $values=New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::OrdinalIgnoreCase)
 $section=''
 foreach($line in [IO.File]::ReadAllLines((Join-Path $config 'config-xpui.ini'))){
   $trimmed=$line.Trim()
   if($trimmed.Length -eq 0 -or $trimmed.StartsWith(';') -or $trimmed.StartsWith('#')){continue}
   if($trimmed -match '^\[([A-Za-z][A-Za-z0-9]*)\]$'){
     $section=[string]$Matches[1]
     continue
   }
   $separator=$trimmed.IndexOf('=')
   if($separator -le 0 -or [string]::IsNullOrWhiteSpace($section)){throw 'V055_SCOPED_INI_UNPARSEABLE'}
   $key=$section+'.'+$trimmed.Substring(0,$separator).Trim()
   if($values.ContainsKey($key)){throw 'V055_SCOPED_INI_DUPLICATE_SECTION_KEY'}
   $values.Add($key,$trimmed.Substring($separator+1).Trim())
 }
 $exactCloneApps=($values.ContainsKey('AdditionalOptions.custom_apps') -and
   [string]$values['AdditionalOptions.custom_apps'] -ceq [string]$spec.name)
 $exactCloneSpotify=($values.ContainsKey('Setting.spotify_path') -and
   [string]$values['Setting.spotify_path'] -ceq $spotify)
 $exactClonePrefs=($values.ContainsKey('Setting.prefs_path') -and
   [string]$values['Setting.prefs_path'] -ceq $prefs)
 $accept=[ordered]@{
   proof_ok=[bool]$proof.ok
   foreign_scope_preserved=[bool]$proof.foreign_xpui_preserved
   declared_file_count_four=([int]$proof.scoped_file_count -eq 4)
   one_extension=([int]$proof.scoped_extension_files -eq 1)
   source_derived_route_bytes=[bool]$exact.ok
   source_scope_pin=([string]$scope.source_tree_sha256 -ceq [string]$sourceBefore.tree_sha256)
   foreign_file_untouched=((Get-FileHash $foreign -Algorithm SHA256).Hash -ceq $foreignSha)
   prefs_untouched=((Get-FileHash $prefs -Algorithm SHA256).Hash -ceq $prefsSha)
   canonical_original_config_untouched=((Get-FileHash $canonicalIni -Algorithm SHA256).Hash -ceq $canonicalSha)
   isolated_clone_single_app_only=$exactCloneApps
   isolated_clone_fake_spotify_only=$exactCloneSpotify
   isolated_clone_fake_prefs_only=$exactClonePrefs
   real_upstream_source_untouched=((Get-CustomAppUpdateTreeSnapshotV010 -Root $source).tree_sha256 -ceq $sourceBefore.tree_sha256)
   pinned_exe_untouched=((Get-FileHash $bin -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $exeHash)
   no_v044_authority=(-not[bool]$proof.production_mutation_authorized)
   no_v054_authority=(-not[bool]$exact.production_mutation_authorized)
 }
 if(@($accept.Values|Where-Object{-not[bool]$_}).Count -ne 0){
   $states=@($accept.Keys|ForEach-Object{[string]$_+'='+[string]$accept[$_]}) -join ';'
   Write-Host ('V055_SAFE_BOOLEAN_ONLY_PROOF_STATUS_'+$spec.name+'='+$states)
 }
 Assert-V055 (@($accept.Values|Where-Object{-not[bool]$_}).Count -eq 0) 'REAL_PITHAYA_UPSTREAM_TO_NATIVE_OUTPUT_NOT_BOUND'
 # Valid output path but changed JS, CSS, JSON, or manifest-copied extension
 # must be rejected. Do not run Spicetify again for these negatives.
 foreach($case in @(
    [pscustomobject]@{relative=('spicetify-routes-'+$spec.name+'.js');denial='V054_VENDOR_ROUTE_JS_NOT_SOURCE_DERIVED'},
    [pscustomobject]@{relative=('spicetify-routes-'+$spec.name+'.css');denial='V054_VENDOR_ROUTE_CSS_NOT_SOURCE_DERIVED'},
    [pscustomobject]@{relative=('spicetify-routes-'+$spec.name+'.json');denial='V054_VENDOR_ROUTE_MANIFEST_NOT_SOURCE_DERIVED'})){
    $target=Join-Path $xpui ([string]$case.relative)
    $saved=[IO.File]::ReadAllBytes($target)
    try{
      [IO.File]::AppendAllText($target,'V055_INVALID_OFFICIAL_OUTPUT')
      Must-Deny-V055 {Test-CustomAppV054OfficialSourceBoundRoutes -Name $spec.name -SourceAppPath $source -CandidateXpuiRoot $xpui -ExpectedSourceTreeSha256 ([string]$sourceBefore.tree_sha256)} ([string]$case.denial)
    }finally{[IO.File]::WriteAllBytes($target,$saved)}
 }
 $ext=Join-Path $xpui ('extensions\'+$spec.name+'\extension.js')
 $saved=[IO.File]::ReadAllBytes($ext)
 try{
    [IO.File]::AppendAllText($ext,'V055_FAKE_EXTERNAL_EXTENSION')
    $drift=Get-CustomAppUpdateTreeSnapshotV010 -Root $xpui
    Must-Deny-V055 {Test-ApprovedNativeManifestOnlyOwnedTargetChangedV044 -Before $before -After $drift -Name $spec.name -SourceAppPath $source -ExpectedSourceTreeSha256 ([string]$sourceBefore.tree_sha256)} 'V044_MANIFEST_SOURCE_COPIED_BYTES_DID_NOT_MATCH'
 }finally{[IO.File]::WriteAllBytes($ext,$saved)}
 Assert-V055 ((Get-CustomAppUpdateTreeSnapshotV010 -Root $xpui).tree_sha256 -ceq [string]$after.tree_sha256) 'NEGATIVE_TEST_FAILED_TO_RESTORE_OUTPUT'
 Assert-V055 (Assert-V055PublisherFiles -Spec $spec -Directory $source) 'FINAL_PIN_CHANGED'
 Write-Host ('V055_PINNED_OFFICIAL_PITHAYA_'+$spec.name.ToUpperInvariant().Replace('-','_')+'_COMMIT_BLOBS_AND_NATIVE_ROUTES_PASS')
 Write-Host ('V055_'+$spec.name.ToUpperInvariant().Replace('-','_')+'_FORGED_JS_CSS_JSON_AND_EXTENSION_DENIED_PASS')
}
Write-Host 'V055_TWO_REAL_OFFICIAL_PITHAYA_DISTRIBUTIONS_RENDERED_WITH_PINNED_SPICETIFY_2464_PASS'
Write-Host 'V055_HOSTED_READ_ONLY_USER_PROFILE_SOURCE_NOT_VENDORED_NO_INSTALL_NO_PRODUCTION_AUTHORITY_PASS'
