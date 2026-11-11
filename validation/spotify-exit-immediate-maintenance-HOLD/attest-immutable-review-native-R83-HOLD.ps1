# R83 HOLD: native Windows PowerShell 5.1-only source attestation for the
# immutable prepublication v0.6.30 candidate. No Python/git/installer needed.
# This verifier does NOT install, update, stage on disk, modify a source tree,
# launch Spotify/Spicetify, adjust a process, or authorize a release.
[CmdletBinding()]
param()
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$review='72f338297fe24ad47ae8315ce2c4bb70656f084c'
$sourceCommit='27c3bbd2935c8568ee6d260085d8008aec5e173a'
$origin='https://raw.githubusercontent.com/sdsssdvx2/spotify-control-updates/'
$manifestHash='71395858fcce58500bb42070bf4b248e2ab14613e148e7d74e616c252d6c3332'
$manifestGitBlob='d858a7ea170d6df9ffe0b435a6e93dfec01549f8'
$mainTarget='b2b2fbf1afb60b58d501312160f7e2437c2452e90cb61ca8c2be0d877f92232d'
$vbsTarget='e56609ed8927512595f55c01ea50dbb9c8c59e4a2c86dcb3d16195a565c604d5'
$addonStable='5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285'
$bootstrapStable='d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6'
$log=New-Object 'System.Collections.Generic.List[string]'
$log.Add('DIAGNOSTIC=SPOTIFY_R83_NATIVE_PS51_PREPUBLICATION_SOURCE_ATTEST')
$log.Add('NETWORK=READONLY_GITHUB_RAW;LOCAL_FILE_WRITE=NO;INSTALL=NO;UPDATE=NO')
$phase='ENVIRONMENT'
function Fail([string]$why){throw [InvalidOperationException]::new($why)}
function HashBytes([byte[]]$data,[string]$kind='SHA256'){
  $hasher=[Security.Cryptography.HashAlgorithm]::Create($kind)
  if($null -eq $hasher){Fail 'SHA_ALGORITHM_NOT_AVAILABLE'}
  try{return ([BitConverter]::ToString($hasher.ComputeHash($data))).Replace('-','').ToLowerInvariant()}
  finally{$hasher.Dispose()}
}
function DownloadPinned([string]$url,[int]$limit){
  if($url -cnotmatch '^https://raw\.githubusercontent\.com/sdsssdvx2/spotify-control-updates/[0-9a-f]{40}/(?:manifest\.json|packages/v0\.6\.30/[a-z0-9-]+/chunk-[0-9]{3}\.txt)$'){
    Fail 'R83_OUTBOUND_URL_OUTSIDE_IMMUTABLE_REVIEW_ALLOWLIST'
  }
  if($limit -lt 1 -or $limit -gt 200000){Fail 'R83_DOWNLOAD_SIZE_NOT_BOUNDED'}
  $req=[Net.HttpWebRequest][Net.WebRequest]::Create($url)
  $req.Method='GET'
  $req.Timeout=35000
  $req.ReadWriteTimeout=35000
  $req.AllowAutoRedirect=$false
  $req.KeepAlive=$false
  $response=$null
  try {
    $response=[Net.HttpWebResponse]$req.GetResponse()
    if($response.StatusCode -ne [Net.HttpStatusCode]::OK -or
       ($response.ContentLength -gt [long]$limit)){
      Fail 'R83_REMOTE_CONTENT_NOT_APPROVED'
    }
    $wire=$response.GetResponseStream()
    $mem=New-Object IO.MemoryStream
    try {
      [byte[]]$buf=New-Object byte[] 8192
      $total=0
      while(($n=$wire.Read($buf,0,$buf.Length)) -gt 0){
        $total+=$n
        if($total -gt $limit){Fail 'R83_REMOTE_CONTENT_OVERSIZED'}
        $mem.Write($buf,0,$n)
      }
      return ,([byte[]]$mem.ToArray())
    }finally{
      if($null -ne $wire){$wire.Dispose()}
      $mem.Dispose()
    }
  }finally{
    if($null -ne $response){$response.Dispose()}
  }
}
function GitBlobHash([byte[]]$data) {
  [byte[]]$prefix=[Text.Encoding]::ASCII.GetBytes(('blob '+$data.Length))
  $ms=New-Object IO.MemoryStream
  try {
    $ms.Write($prefix,0,$prefix.Length)
    $ms.WriteByte(0)
    $ms.Write($data,0,$data.Length)
    return HashBytes $ms.ToArray() 'SHA1'
  }finally{$ms.Dispose()}
}
function ExpandGzipBounded([byte[]]$compressed,[int]$limit) {
  $inputStream=[IO.MemoryStream]::new($compressed)
  $zip=[IO.Compression.GZipStream]::new($inputStream,[IO.Compression.CompressionMode]::Decompress)
  $out=New-Object IO.MemoryStream
  try{
    [byte[]]$buf=New-Object byte[] 8192
    while(($n=$zip.Read($buf,0,$buf.Length)) -gt 0){
      if($out.Length+$n -gt $limit){Fail 'R83_DECOMPRESSED_PAYLOAD_TOO_LARGE'}
      $out.Write($buf,0,$n)
    }
    return ,([byte[]]$out.ToArray())
  }finally{
    $out.Dispose()
    $zip.Dispose()
    $inputStream.Dispose()
  }
}
try {
  if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
     $PSVersionTable.PSEdition -cne 'Desktop' -or
     $PSVersionTable.PSVersion.Major -ne 5 -or
     -not [Environment]::Is64BitProcess){
    Fail 'R83_WINDOWS_X64_POWERSHELL_51_REQUIRED'
  }
  [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
  $phase='REVIEW_MANIFEST'
  [byte[]]$raw=DownloadPinned ($origin+$review+'/manifest.json') 200000
  if($raw.Length -ne 125610 -or
     (HashBytes $raw) -cne $manifestHash -or
     (GitBlobHash $raw) -cne $manifestGitBlob){
    Fail 'R83_IMMUTABLE_MANIFEST_SHA256_OR_GIT_PIN_MISMATCH'
  }
  try{$manifest=[Text.Encoding]::UTF8.GetString($raw) | ConvertFrom-Json -ErrorAction Stop}
  catch{Fail 'R83_PINNED_MANIFEST_JSON_UNREADABLE'}
  if([string]$manifest.channel -cne 'stable' -or
     [string]$manifest.latest_version -cne '0.6.30' -or
     [string]$manifest.source_commit -cne $sourceCommit -or
     [string]$manifest.source_repository -cne 'sdsssdvx2/spotify-control-updates' -or
     [string]$manifest.payload_set_sha256 -cne 'fb2bf4d27991e27b67c00d1df3efcc36166369d079173f9978c35f43a6e93fb8' -or
     @($manifest.updates).Count -ne 19 -or
     [string]$manifest.bootstrap.version -cne '1.0.6' -or
     [long]$manifest.bootstrap.size -ne 42963 -or
     [string]$manifest.bootstrap.sha256 -cne $bootstrapStable){
    Fail 'R83_RELEASE_MANIFEST_TRUST_ROOT_CHANGED'
  }
  $files=@{}
  foreach($entry in @($manifest.latest_files)){
    $path=[string]$entry.path
    if($files.ContainsKey($path)){Fail 'R83_DUPLICATE_TARGET_FILE'}
    $files[$path]=@{sha=[string]$entry.sha256;size=[long]$entry.size}
  }
  if($files.Count -ne 3 -or
     $files['bin/spotify-control.ps1'].sha -cne $mainTarget -or
     $files['bin/spotify-control.ps1'].size -ne 294101 -or
     $files['bin/spotify-control-agent.vbs'].sha -cne $vbsTarget -or
     $files['bin/spotify-control-agent.vbs'].size -ne 13308 -or
     $files['bin/addon-manager.ps1'].sha -cne $addonStable -or
     $files['bin/addon-manager.ps1'].size -ne 323385){
    Fail 'R83_FULL_RELEASE_FILE_PINS_UNEXPECTED'
  }
  $edge=@($manifest.updates)[18]
  if([string]$edge.from_version -cne '0.6.28' -or
     [string]$edge.to_version -cne '0.6.30' -or
     @($edge.patches).Count -ne 2){
    Fail 'R83_PATCH_EDGE_OR_FILE_COUNT_UNEXPECTED'
  }
  $phase='REMOTE_IMMUTABLE_CHUNKS'
  $decoded=@{}
  $chunks=0
  $targets=@(
    @{path='bin/spotify-control.ps1';dir='main-v0628-to-v0630';count=19;old='af1582ec335807f8f5daa9b3a65b13d567264f326d3c608c082ae02ff0a4cfc0';target=$mainTarget;size=294101},
    @{path='bin/spotify-control-agent.vbs';dir='resident-v011-to-v012';count=2;old='2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278';target=$vbsTarget;size=13308}
  )
  for($j=0;$j -lt 2;$j++){
    $spec=$targets[$j]
    $patch=@($edge.patches)[$j]
    if([string]$patch.path -cne $spec.path -or
       [string]$patch.encoding -cne 'gzip-base64-full-file' -or
       [string]$patch.from_sha256 -cne $spec.old -or
       [string]$patch.to_sha256 -cne $spec.target -or
       [long]$patch.target_size -ne $spec.size -or
       @($patch.chunks).Count -ne $spec.count){
      Fail 'R83_PATCH_METADATA_NOT_PINNED'
    }
    $encoded=New-Object IO.MemoryStream
    try{
      for($i=0;$i -lt $spec.count;$i++){
        $entry=@($patch.chunks)[$i]
        $rel=('packages/v0.6.30/'+$spec.dir+'/chunk-'+$i.ToString('000')+'.txt')
        if([string]$entry.path -cne $rel -or
           [long]$entry.size -lt 1 -or [long]$entry.size -gt 4096 -or
           [string]$entry.sha256 -cnotmatch '^[0-9a-f]{64}$'){
          Fail 'R83_CHUNK_IDENTITY_OR_PATH_OUT_OF_ORDER'
        }
        [byte[]]$bytes=DownloadPinned ($origin+$sourceCommit+'/'+$rel) 4096
        if($bytes.Length -ne [long]$entry.size -or
           (HashBytes $bytes) -cne [string]$entry.sha256){
          Fail 'R83_REMOTE_GIT_CHUNK_SHA256_MISMATCH'
        }
        $encoded.Write($bytes,0,$bytes.Length)
        $chunks++
      }
      [byte[]]$encodedBytes=$encoded.ToArray()
    }finally{$encoded.Dispose()}
    if($encodedBytes.Length -ne [long]$patch.encoded_size -or
       (HashBytes $encodedBytes) -cne [string]$patch.encoded_sha256){
      Fail 'R83_ENCODED_PAYLOAD_SHA256_MISMATCH'
    }
    try{[byte[]]$compressed=[Convert]::FromBase64String([Text.Encoding]::ASCII.GetString($encodedBytes))}
    catch{Fail 'R83_STRICT_GZIP_BASE64_INVALID'}
    if($compressed.Length -ne [long]$patch.compressed_size -or
       (HashBytes $compressed) -cne [string]$patch.compressed_sha256){
      Fail 'R83_COMPRESSED_PAYLOAD_SHA256_MISMATCH'
    }
    [byte[]]$plain=ExpandGzipBounded $compressed 500000
    if($plain.Length -ne $spec.size -or (HashBytes $plain) -cne $spec.target){
      Fail 'R83_FINAL_FULL_FILE_SHA256_MISMATCH'
    }
    $decoded[$spec.path]=$plain
  }
  if($chunks -ne 21 -or $decoded.Count -ne 2){
    Fail 'R83_FINAL_REMOTE_IMMUTABLE_CHUNK_COUNT_UNEXPECTED'
  }
  $log.Add('R83_GENUINE_GITHUB_REVIEW_MANIFEST_GIT_BLOB_AND_SHA256=PASS')
  $log.Add('R83_REMOTE_IMMUTABLE_21_OF_21_CHUNKS=PASS')
  $log.Add('R83_REAL_MAIN_294101_AND_AGENT_13308_SHA256=PASS')
  $log.Add('R83_ORIGINAL_BOOTSTRAP_AND_ADDON_R17_PINS=PASS')
  $log.Add('R83_EXTERNAL_PYTHON_GIT_OR_INSTALLER_REQUIRED=NO')
  $log.Add('R83_RESULT=READONLY_OWNER_FIRST_SOURCE_ADMITTED_NOT_INSTALLER')
}catch{
  $reason=[string]$_.Exception.Message
  if($reason -cnotmatch '^R83_[A-Z0-9_]{5,95}$'){
    $reason='R83_NETWORK_OR_SOURCE_UNVERIFIED'
  }
  $log.Add('FAILED_PHASE='+$phase)
  $log.Add('HOLD_REASON='+$reason)
  $log.Add('R83_RESULT=HOLD_NO_MUTATION_NO_AUTO_RETRY')
}finally{
  $log.Add('OPERATING_SPOTIFY_SPICETIFY_USER_STATE=UNCHANGED')
  $log.Add('PUBLIC_MAIN_AND_HOLD_RELEASE=UNCHANGED')
  $log|ForEach-Object{Write-Output $_}
}
