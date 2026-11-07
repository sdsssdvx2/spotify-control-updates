# V054 hosted-only byte-exact validator for native Spicetify v2.46.4
# RefreshApps Go source: spicetify/cli@v2.46.4 src/cmd/apply.go.
# The upstream Go file was SHA-pinned and its behavior exercised by prior
# V044 GitHub-hosted Windows real-official-CLI CI. This is NOT a live executor.
# Preload V010 and V044; all paths must be disposable runner fixtures.
function Test-CustomAppV054OfficialSourceBoundRoutes {
 param([Parameter(Mandatory=$true)][string]$Name,
       [Parameter(Mandatory=$true)][string]$SourceAppPath,
       [Parameter(Mandatory=$true)][string]$CandidateXpuiRoot,
       [Parameter(Mandatory=$true)][string]$ExpectedSourceTreeSha256)
 Assert-ApprovedNativeManifestHostedV044
 if($ExpectedSourceTreeSha256 -cnotmatch '^[0-9a-f]{64}$'){
    throw 'V054_EXPECTED_SOURCE_SHA_INVALID'
 }
 $sc=Get-ApprovedNativeManifestOwnedScopeV044 -Name $Name -SourceAppPath $SourceAppPath
 if([string]$sc.source_tree_sha256 -cne $ExpectedSourceTreeSha256){
    throw 'V054_SOURCE_TREE_NOT_BOUND_TO_CANDIDATE'
 }
 $root=Assert-CustomAppUpdateFixturePathV010 -ValidationRoot $env:RUNNER_TEMP -Path $CandidateXpuiRoot -Label 'V054_XPUI'
 if(-not[IO.Directory]::Exists($root)){throw 'V054_CANDIDATE_XPUI_MISSING'}
 $before=Get-CustomAppUpdateTreeSnapshotV010 -Root $root
 $byName=@{}
 foreach($e in @($before.entries)){
   $key=([string]$e.path).Replace('\','/').ToLowerInvariant()
   if($byName.ContainsKey($key)){throw 'V054_XPUI_CASE_COLLISION'}
   $byName[$key]=$e
 }
 $n=$Name.ToLowerInvariant()
 $r='spicetify-routes-'+$n
 foreach($ext in @('.js','.css','.json')){
   $rel=$r+$ext
   if(-not$byName.ContainsKey($rel) -or [string]$byName[$rel].type -cne 'file'){
     throw 'V054_REQUIRED_NATIVE_ROUTE_MISSING'
   }
 }
 # V044 has already parsed and verified all relative subfile paths and source
 # hashes; a second tree snapshot after reading excludes stable source drift.
 $source=Assert-CustomAppUpdateFixturePathV010 -ValidationRoot $env:RUNNER_TEMP -Path $SourceAppPath -Label 'V054_SOURCE'
 $mf=Join-Path $source 'manifest.json'
 $idx=Join-Path $source 'index.js'
 $style=Join-Path $source 'style.css'
 $utf8=[Text.UTF8Encoding]::new($false,$true)
 $manifestBytes=[IO.File]::ReadAllBytes($mf)
 if($manifestBytes.Length -gt 65536){throw 'V054_MANIFEST_EXCEEDS_CAP'}
 $parsed=$utf8.GetString($manifestBytes)|ConvertFrom-Json -ErrorAction Stop
 $subfiles=@()
 $p=$parsed.PSObject.Properties['subfiles']
 if($null-ne$p -and $null-ne$p.Value){$subfiles=@($p.Value)}
 # Do not use an if-expression here: WinPS5.1 unwraps an empty byte[] into
 # $null, and StrictMode then rejects the .Length inspection.
 [byte[]]$expectedCss=[byte[]]@()
 if([IO.File]::Exists($style)){$expectedCss=[IO.File]::ReadAllBytes($style)}
 if($expectedCss.Length -gt 16777216){throw 'V054_CSS_TOO_LARGE'}
 $stream=New-Object IO.MemoryStream
 $sha=[Security.Cryptography.SHA256]::Create()
 try {
   $prefix='((e)=>{const t=e.rspackChunk||e.rspackChunkclient_web||e.webpackChunkclient_web||[];return e.rspackChunk=e.rspackChunk||t,e.rspackChunkclient_web=e.rspackChunkclient_web||t,e.webpackChunkclient_web=e.webpackChunkclient_web||t,t})("undefined"!=typeof self?self:globalThis).push([["'+$n+'"],{"'+$n+'":(e,t,n)=>{'+[char]10+'"use strict";n.r(t),n.d(t,{default:()=>render});'+[char]10
   $pre=$utf8.GetBytes($prefix)
   $stream.Write($pre,0,$pre.Length)
   $main=[IO.File]::ReadAllBytes($idx)
   if($main.Length -gt 16777216){throw 'V054_INDEX_TOO_LARGE'}
   $stream.Write($main,0,$main.Length)
   foreach($item in @($subfiles)){
     $relative=Assert-ApprovedNativeManifestRelativeV044 -Value ([string]$item)
     $path=Join-Path $source $relative.Replace('/','\')
     $chunk=[IO.File]::ReadAllBytes($path)
     if([int64]$stream.Length+[int64]$chunk.Length+2 -gt 33554432){throw 'V054_JS_BUNDLE_TOO_LARGE'}
     $stream.WriteByte(10)
     $stream.Write($chunk,0,$chunk.Length)
   }
   $post=[char]10+'}}]);'
   $tail=$utf8.GetBytes($post)
   $stream.Write($tail,0,$tail.Length)
   if($stream.Length -gt 33554432){throw 'V054_JS_BUNDLE_TOO_LARGE'}
   $stream.Position=0
   $expectedJs=([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant()
   # Diagnostic is in-memory only; do not emit route contents or paths.
   $expectedJsBytes=$stream.ToArray()
   $expectedManifest=([BitConverter]::ToString($sha.ComputeHash($manifestBytes))).Replace('-','').ToLowerInvariant()
   $expectedStyle=([BitConverter]::ToString($sha.ComputeHash($expectedCss))).Replace('-','').ToLowerInvariant()
 }finally{
   $sha.Dispose()
   $stream.Dispose()
 }
 $actualJs=[string]$byName[$r+'.js'].sha256
 $actualCss=[string]$byName[$r+'.css'].sha256
 $actualManifest=[string]$byName[$r+'.json'].sha256
 if($actualJs -cne $expectedJs){
   if($env:V054_CI_DIAGNOSTIC -ceq '1' -and $env:GITHUB_ACTIONS -ceq 'true'){
     $actualBytes=[IO.File]::ReadAllBytes((Join-Path $root ($r+'.js')))
     $limit=[Math]::Min($expectedJsBytes.Length,$actualBytes.Length)
     $first=0
     while($first -lt $limit -and $expectedJsBytes[$first] -eq $actualBytes[$first]){$first++}
     $left=if($first -lt $expectedJsBytes.Length){[int]$expectedJsBytes[$first]}else{-1}
     $right=if($first -lt $actualBytes.Length){[int]$actualBytes[$first]}else{-1}
     Write-Host ('V054_HOSTED_ROUTE_BYTE_DIFF expected_length='+$expectedJsBytes.Length+
       ';actual_length='+$actualBytes.Length+';first_byte_index='+$first+
       ';expected_byte='+$left+';actual_byte='+$right+
       ';expected_sha256='+$expectedJs+';actual_sha256='+$actualJs)
   }
   throw 'V054_VENDOR_ROUTE_JS_NOT_SOURCE_DERIVED'
 }
 if($actualCss -cne $expectedStyle){throw 'V054_VENDOR_ROUTE_CSS_NOT_SOURCE_DERIVED'}
 if($actualManifest -cne $expectedManifest){throw 'V054_VENDOR_ROUTE_MANIFEST_NOT_SOURCE_DERIVED'}
 $sourceAgain=Get-CustomAppUpdateTreeSnapshotV010 -Root $source
 $xpuiAgain=Get-CustomAppUpdateTreeSnapshotV010 -Root $root
 if([string]$sourceAgain.tree_sha256 -cne $ExpectedSourceTreeSha256 -or
    [string]$xpuiAgain.tree_sha256 -cne [string]$before.tree_sha256){
   throw 'V054_SOURCE_OR_XPUI_CHANGED_DURING_OFFICIAL_BYTES_PROOF'
 }
 return [pscustomobject]@{
  ok=$true;source_tree_sha256=$ExpectedSourceTreeSha256
  route_js_sha256=$expectedJs;route_css_sha256=$expectedStyle
  route_manifest_sha256=$expectedManifest
  native_renderer='spicetify-v2.46.4-go-RefreshApps'
  module_format_from_official_source=$true
  production_mutation_authorized=$false
  real_release_provenance_verified=$false
 }
}
