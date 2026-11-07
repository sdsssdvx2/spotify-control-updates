# V044 - bounded manifest-driven official Spicetify 2.46.4 XPUI scope.
# Hosted Windows sandbox only; NOT normal Addon Manager or production apply.
# Official AppManifest keys: subfiles, subfiles_extension, assets.
# Source tree SHA is checked before and after reading manifest. Reparse points,
# traversal, unsafe glob syntax, unknown outputs and foreign edits all DENIED.
# No filesystem writes in this module.
function Assert-ApprovedNativeManifestHostedV044 {
 if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
    $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
    $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
    [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
    throw 'V044_HOSTED_WINDOWS_ONLY'
 }
}
function Assert-ApprovedNativeManifestRelativeV044 {
 param([Parameter(Mandatory=$true)][string]$Value)
 if($Value.Length -gt 160 -or $Value -cnotmatch '^[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*$' -or
    $Value -cmatch '(^|/)\.{1,2}(/|$)' -or $Value.Contains('\') -or
    $Value.Contains(':')){
    throw 'V044_MANIFEST_UNSAFE_RELATIVE_SOURCE'
 }
 return $Value.ToLowerInvariant()
}
function Get-ApprovedNativeManifestOwnedScopeV044 {
 param([Parameter(Mandatory=$true)][string]$Name,
       [Parameter(Mandatory=$true)][string]$SourceAppPath)
 Assert-ApprovedNativeManifestHostedV044
 if($Name -cnotmatch '^[a-z][a-z0-9-]{1,63}$' -or
    $Name -notin @('ivlyrics','better-local-files','eternal-jukebox','playlist-maker')){
    throw 'V044_NAME_NOT_APPROVED'
 }
 $source=Assert-CustomAppUpdateFixturePathV010 -ValidationRoot $env:RUNNER_TEMP -Path $SourceAppPath -Label 'V044_APP_SOURCE'
 $tree=Get-CustomAppUpdateTreeSnapshotV010 -Root $source
 if([int]$tree.file_count -lt 2){throw 'V044_APP_SOURCE_INCOMPLETE'}
 $map=@{}
 foreach($entry in @($tree.entries)){
    $rel=([string]$entry.path).Replace('\','/').ToLowerInvariant()
    if($map.ContainsKey($rel)){throw 'V044_DUPLICATE_SOURCE_CASE'}
    $map[$rel]=$entry
 }
 foreach($key in @('index.js','manifest.json')){
    if(-not$map.ContainsKey($key) -or [string]$map[$key].type -cne 'file'){
       throw 'V044_ENTRYPOINT_OR_MANIFEST_MISSING'
    }
 }
 $mf=Join-Path $source 'manifest.json'
 if((Get-Item -LiteralPath $mf).Length -gt 65536){throw 'V044_MANIFEST_TOO_LARGE'}
 $raw=[IO.File]::ReadAllText($mf,[Text.UTF8Encoding]::new($false,$true))
 try{$m=$raw|ConvertFrom-Json -ErrorAction Stop}catch{throw 'V044_MANIFEST_JSON_INVALID'}
 if($null-eq$m -or $m -isnot [pscustomobject]){throw 'V044_MANIFEST_NOT_OBJECT'}
 $fields=@('subfiles','subfiles_extension','assets')
 foreach($f in $fields){
    if($null-ne$m.$f -and $m.$f -isnot [array]){
       throw 'V044_MANIFEST_DECLARATION_NOT_ARRAY'
    }
 }
 $paths=@{}
 $ownedFiles=@{}
 $allowedDirs=@{}
 $required=@{}
 $copiedHash=@{}
 [int]$extensionCount=0;[int]$assetsCount=0
 function Add-ApprovedOwnedFileV044([string]$Relative) {
    $r=Assert-ApprovedNativeManifestRelativeV044 -Value $Relative
    if($ownedFiles.ContainsKey($r)){throw 'V044_OWNED_OUTPUT_COLLISION'}
    $ownedFiles[$r]=$true;$required[$r]=$true
    $dir=[IO.Path]::GetDirectoryName($r.Replace('/','\'))
    while(-not[string]::IsNullOrWhiteSpace($dir)){
       $d=$dir.Replace('\','/').ToLowerInvariant()
       $allowedDirs[$d]=$true
       $dir=[IO.Path]::GetDirectoryName($dir)
    }
 }
 foreach($end in @('.js','.css','.json')){
   Add-ApprovedOwnedFileV044 ('spicetify-routes-'+$Name+$end)
 }
 if($null-ne$m.subfiles){foreach($item in @($m.subfiles)){
   if($item -isnot [string]){throw 'V044_SUBFILE_NOT_STRING'}
   $rel=Assert-ApprovedNativeManifestRelativeV044 -Value ([string]$item)
   if($paths.ContainsKey('subfile|'+$rel)){throw 'V044_DUPLICATE_MANIFEST_SUBFILE'}
   $paths['subfile|'+$rel]=$true
   if(-not$map.ContainsKey($rel) -or [string]$map[$rel].type -cne 'file'){
      throw 'V044_MANIFEST_SUBFILE_MISSING'
   }
 }
 }
 if($null-ne$m.subfiles_extension){foreach($item in @($m.subfiles_extension)){
   if($item -isnot [string]){throw 'V044_EXTENSION_NOT_STRING'}
   $rel=Assert-ApprovedNativeManifestRelativeV044 -Value ([string]$item)
   if($paths.ContainsKey('ext|'+$rel)){throw 'V044_DUPLICATE_EXTENSION'}
   $paths['ext|'+$rel]=$true
   if(-not$map.ContainsKey($rel) -or [string]$map[$rel].type -cne 'file'){
      throw 'V044_MANIFEST_EXTENSION_SOURCE_MISSING'
   }
   $leaf=[IO.Path]::GetFileName($rel)
   if($leaf -cnotmatch '^[a-zA-Z0-9_-][a-zA-Z0-9_.-]*\.(js|mjs)$'){
      throw 'V044_UNSUPPORTED_EXTENSION_BASENAME'
   }
   if($leaf -notmatch '\.js$'){throw 'V044_MJS_REWRITE_NEEDS_SEPARATE_PROOF'}
   $output=('extensions/'+$Name+'/'+$leaf)
   Add-ApprovedOwnedFileV044 $output
   $copiedHash[$output]=[string]$map[$rel].sha256
   $extensionCount++
 }
 }
 if($null-ne$m.assets){foreach($item in @($m.assets)){
   if($item -isnot [string]){throw 'V044_ASSET_SELECTOR_NOT_STRING'}
   $expr=[string]$item
   $glob=$expr.EndsWith('/*',[StringComparison]::Ordinal)
   $base=if($glob){$expr.Substring(0,$expr.Length-2)}else{$expr}
   $rootRel=Assert-ApprovedNativeManifestRelativeV044 -Value $base
   if($rootRel -cnotmatch '^assets(?:/|$)'){
       throw 'V044_ASSETS_OUTSIDE_SCOPED_ASSETS_DIRECTORY'
   }
   if($paths.ContainsKey('asset|'+$expr.ToLowerInvariant())){
       throw 'V044_DUPLICATE_ASSET_PATTERN'
   }
   $paths['asset|'+$expr.ToLowerInvariant()]=$true
   if(-not$map.ContainsKey($rootRel) -or
       ($glob -and [string]$map[$rootRel].type -cne 'dir')){
      throw 'V044_ASSET_SELECTOR_MISSING'
   }
   $prefix=($rootRel+'/')
   $matching=@()
   if($glob){
      $matching=@($tree.entries|Where-Object {
         ([string]$_.path).Replace('\','/').ToLowerInvariant().StartsWith($prefix,[StringComparison]::Ordinal)
      })
   }else{
      $matching=@($tree.entries|Where-Object {
        $v=([string]$_.path).Replace('\','/').ToLowerInvariant()
        $v -ceq $rootRel -or $v.StartsWith($prefix,[StringComparison]::Ordinal)
      })
   }
   if($matching.Count -lt 1){throw 'V044_ASSET_GLOB_MATCHES_NOTHING'}
   foreach($match in $matching){
      if([string]$match.type -ne 'file'){continue}
      $relative=([string]$match.path).Replace('\','/').ToLowerInvariant()
      $output='assets/'+$Name+'/'+$relative
      if(-not$ownedFiles.ContainsKey($output)){
          Add-ApprovedOwnedFileV044 $output
          $copiedHash[$output]=[string]$match.sha256
          $assetsCount++
      }
   }
 }
 }
 if($paths.Count -gt 96 -or $ownedFiles.Count -gt 5000 -or
    @($tree.entries).Count -gt 10000){throw 'V044_OUTPUT_SCOPE_CAP_EXCEEDED'}
 # Guarantee no source mutations raced any manifest read/enumeration.
 $final=Get-CustomAppUpdateTreeSnapshotV010 -Root $source
 if([string]$final.tree_sha256 -cne [string]$tree.tree_sha256 -or
    [int]$final.file_count -ne [int]$tree.file_count){
    throw 'V044_SOURCE_TREE_CHANGED_WHILE_BUILDING_SCOPE'
 }
 return [pscustomobject]@{
    schema=1;approved_name=$Name
    source_tree_sha256=[string]$tree.tree_sha256
    manifest_sha256=[string]$map['manifest.json'].sha256
    byte_exact_copied_outputs=$copiedHash
    owned_files=@($ownedFiles.Keys|Sort-Object)
    owned_directories=@($allowedDirs.Keys|Sort-Object)
    declared_extensions=$extensionCount
    declared_asset_files=$assetsCount
    output_scope_determined_by_official_2464_manifest=$true
    production_mutation_authorized=$false
 }
}
function Test-ApprovedNativeManifestOnlyOwnedTargetChangedV044 {
 param([Parameter(Mandatory=$true)]$Before,
       [Parameter(Mandatory=$true)]$After,
       [Parameter(Mandatory=$true)][string]$Name,
       [Parameter(Mandatory=$true)][string]$SourceAppPath,
       [Parameter(Mandatory=$true)][string]$ExpectedSourceTreeSha256)
 $scope=Get-ApprovedNativeManifestOwnedScopeV044 -Name $Name -SourceAppPath $SourceAppPath
 if($ExpectedSourceTreeSha256 -cnotmatch '^[a-f0-9]{64}$' -or
    [string]$scope.source_tree_sha256 -cne $ExpectedSourceTreeSha256){
    throw 'V044_MANIFEST_OWNED_SCOPE_SOURCE_CHANGED_SINCE_ADMISSION'
 }
 $allowed=@{};foreach($v in @($scope.owned_files)){$allowed[[string]$v]=$true}
 $directories=@{};foreach($v in @($scope.owned_directories)){$directories[[string]$v]=$true}
 $old=@{};$new=@{}
 foreach($e in @($Before.entries)){
    $rel=([string]$e.path).Replace('\','/').ToLowerInvariant()
    if($old.ContainsKey($rel)){throw 'V044_CASE_INSENSITIVE_OLD_XPUI_COLLISION'}
    $old[$rel]=([string]$e.type+'|'+[string]$e.size+'|'+[string]$e.sha256)
 }
 foreach($e in @($After.entries)){
    $rel=([string]$e.path).Replace('\','/').ToLowerInvariant()
    if($new.ContainsKey($rel)){throw 'V044_CASE_INSENSITIVE_NEW_XPUI_COLLISION'}
    $new[$rel]=([string]$e.type+'|'+[string]$e.size+'|'+[string]$e.sha256)
 }
 foreach($owned in @($allowed.Keys)){
    if(-not$new.ContainsKey($owned) -or
      -not([string]$new[$owned]).StartsWith('file|',[StringComparison]::Ordinal)){
        throw 'V044_DECLARED_OFFICIAL_FILE_MISSING'
    }
 }
 # Extension/asset bytes must be exactly identical to selected approved
 # source files, rather than merely landing under the correct directory.
 foreach($copy in @($scope.byte_exact_copied_outputs.Keys)){
    $expected=[string]$scope.byte_exact_copied_outputs[$copy]
    if([string]::IsNullOrWhiteSpace($expected) -or $expected -cnotmatch '^[a-f0-9]{64}$' -or
       -not$new.ContainsKey([string]$copy) -or
       -not([string]$new[[string]$copy]).EndsWith(('|'+$expected),[StringComparison]::Ordinal)){
       throw 'V044_MANIFEST_SOURCE_COPIED_BYTES_DID_NOT_MATCH'
    }
 }
 foreach($v in @($old.Keys)){
    if($allowed.ContainsKey($v)){continue}
    if($directories.ContainsKey($v)){
       if($old[$v] -cne 'dir|0|'){throw 'V044_ALLOWED_PARENT_ALREADY_NOT_DIR'}
       continue
    }
    if(-not$new.ContainsKey($v) -or [string]$old[$v] -cne [string]$new[$v]){
      throw 'V044_FOREIGN_XPUI_EXISTING_FILE_CHANGED'
    }
 }
 foreach($v in @($new.Keys)){
    if($allowed.ContainsKey($v)){continue}
    if($directories.ContainsKey($v)){
       if($new[$v] -cne 'dir|0|'){throw 'V044_ALLOWED_PARENT_NOW_NOT_DIR'}
       continue
    }
    if(-not$old.ContainsKey($v)){throw 'V044_UNDECLARED_XPUI_OUTPUT_CREATED'}
 }
 return [pscustomobject]@{
  ok=$true;reason='exact-manifest-declared-output-and-all-foreign-xpui-preserved'
  source_tree_sha256=[string]$scope.source_tree_sha256
  manifest_sha256=[string]$scope.manifest_sha256
  scoped_file_count=@($scope.owned_files).Count
  scoped_extension_files=[int]$scope.declared_extensions
  scoped_asset_files=[int]$scope.declared_asset_files
  pre_xpui_sha256=[string]$Before.tree_sha256
  post_xpui_sha256=[string]$After.tree_sha256
  foreign_xpui_preserved=$true;production_mutation_authorized=$false
 }
}
