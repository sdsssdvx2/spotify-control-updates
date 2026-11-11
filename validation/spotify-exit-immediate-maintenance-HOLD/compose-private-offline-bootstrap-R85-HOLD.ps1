# R85 HOLD: compose an owner-private FILE-URI transport from R84 attested bytes.
# Absolutely no Spotify install, process change, bootstrap replacement in operating root,
# public manifest write, scheduled task, ACL change outside new private staging, or model call.
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$R84ReadyPath,
  [string]$OfficialBootstrapPath=''
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$log=New-Object 'System.Collections.Generic.List[string]'
$log.Add('DIAGNOSTIC=SPOTIFY_R85_PREPUBLICATION_PRIVATE_OFFLINE_BOOTSTRAP_HOLD')
$log.Add('NETWORK=NO;OPERATING_SPOTIFY_WRITE=NO;PROCESS_CHANGE=NO;PUBLICATION=NO;INSTALL=NO')
$phase='ENVIRONMENT'
$privateTmp=''
$created=$false
function StopNow([string]$code){throw [InvalidOperationException]::new($code)}
function Sha([byte[]]$bytes){
  $h=[Security.Cryptography.SHA256]::Create()
  try{return [BitConverter]::ToString($h.ComputeHash($bytes)).Replace('-','').ToLowerInvariant()}
  finally{$h.Dispose()}
}
function PlainDir([string]$path){
  try{$f=Get-Item -LiteralPath $path -Force -ErrorAction Stop
      return ($f.PSIsContainer -and ($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0)}
  catch{return $false}
}
function CheckedBytes([string]$path,[long]$size,[string]$hash){
  $f=Get-Item -LiteralPath $path -Force -ErrorAction Stop
  if($f.PSIsContainer -or ($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
     [long]$f.Length -ne $size){StopNow 'R85_EXPECTED_SOURCE_FILE_NOT_REGULAR'}
  [byte[]]$data=[IO.File]::ReadAllBytes($path)
  if((Sha $data) -cne $hash){StopNow 'R85_VERIFIED_STAGE_SOURCE_SHA256_INVALID'}
  return ,$data
}
function WriteNew([string]$p,[byte[]]$data){
  $s=[IO.FileStream]::new($p,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try{$s.Write($data,0,$data.Length);$s.Flush($true)}
  finally{$s.Dispose()}
}
function SamePath([string]$a,[string]$b){
  return [IO.Path]::GetFullPath($a).Equals([IO.Path]::GetFullPath($b),[StringComparison]::OrdinalIgnoreCase)
}
function PurgeOurScratchOnly([string]$p){
  if(-not $created -or -not $p -or -not (PlainDir $p)){return}
  # No recursive deletes: delete only exact files and literal known directories.
  foreach($name in @('manifest.json','bootstrap-verified-locator-copy.ps1','offline-receipt.json')){
    $f=Join-Path $p $name
    try{$item=Get-Item -LiteralPath $f -Force -ErrorAction Stop
      if(-not $item.PSIsContainer -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0){
        [IO.File]::Delete($f)
      }
    }catch{}
  }
  $relative='sdsssdvx2\spotify-control-updates\27c3bbd2935c8568ee6d260085d8008aec5e173a'
  foreach($dir in @('main-v0628-to-v0630','resident-v011-to-v012')){
    $sub=Join-Path $p ($relative+'\packages\v0.6.30\'+$dir)
    $total=if($dir -ceq 'main-v0628-to-v0630'){19}else{2}
    for($i=0;$i -lt $total;$i++){
      $f=Join-Path $sub ('chunk-'+$i.ToString('000')+'.txt')
      try{$item=Get-Item -LiteralPath $f -Force -ErrorAction Stop
        if(-not $item.PSIsContainer -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0){
          [IO.File]::Delete($f)
        }
      }catch{}
    }
    try{[IO.Directory]::Delete($sub,$false)}catch{}
  }
  foreach($sub in @(
      ($relative+'\packages\v0.6.30'),($relative+'\packages'),$relative,
      'sdsssdvx2\spotify-control-updates','sdsssdvx2')){
    try{[IO.Directory]::Delete((Join-Path $p $sub),$false)}catch{}
  }
  try{[IO.Directory]::Delete($p,$false)}catch{}
}
try{
  if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
     $PSVersionTable.PSEdition -cne 'Desktop' -or
     $PSVersionTable.PSVersion.Major -ne 5 -or -not [Environment]::Is64BitProcess){
    StopNow 'R85_WINDOWS_PS51_X64_REQUIRED'
  }
  $appData=[IO.Path]::GetFullPath($env:LOCALAPPDATA).TrimEnd([char]92,[char]47)
  if(-not (PlainDir $appData)){StopNow 'R85_APPDATA_NOT_REAL_DIRECTORY'}
  $root=[IO.Path]::GetFullPath($R84ReadyPath).TrimEnd([char]92,[char]47)
  $parent=[IO.Path]::GetDirectoryName($root)
  if(-not (SamePath $parent $appData) -or
     [IO.Path]::GetFileName($root) -cnotmatch '^SpotifyControlCanary-ready-[0-9a-f]{32}$' -or
     -not (PlainDir $root)){
    StopNow 'R85_UNEXPECTED_R84_PRIVATE_READY_PATH'
  }
  $owner=[Security.Principal.WindowsIdentity]::GetCurrent().User
  $principle=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
  if($principle.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
    StopNow 'R85_NON_ELEVATED_OWNER_REQUIRED'
  }
  $stageAcl=[IO.Directory]::GetAccessControl($root)
  if(-not $stageAcl.AreAccessRulesProtected -or
     $stageAcl.GetOwner([Security.Principal.SecurityIdentifier]).Value -cne $owner.Value){
    StopNow 'R85_STAGE_OWNER_DACL_UNVERIFIED'
  }
  $phase='R84_IMMUTABLE_PINNED_STAGE'
  $review='72f338297fe24ad47ae8315ce2c4bb70656f084c'
  $source='27c3bbd2935c8568ee6d260085d8008aec5e173a'
  $manifestSha='71395858fcce58500bb42070bf4b248e2ab14613e148e7d74e616c252d6c3332'
  $mainSha='b2b2fbf1afb60b58d501312160f7e2437c2452e90cb61ca8c2be0d877f92232d'
  $agentSha='e56609ed8927512595f55c01ea50dbb9c8c59e4a2c86dcb3d16195a565c604d5'
  $bootstrapSha='d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6'
  $p=Join-Path $root 'stage-attestation.json'
  $metaFile=Get-Item -LiteralPath $p -Force -ErrorAction Stop
  if($metaFile.PSIsContainer -or ($metaFile.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
     $metaFile.Length -lt 100 -or $metaFile.Length -gt 3000){StopNow 'R85_R84_RECEIPT_NOT_REGULAR'}
  $receipt=Get-Content -LiteralPath $p -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
  if($receipt.schema -cne 'SPOTIFY_R84_OWNER_FIRST_STAGED_CANDIDATE_V1' -or
     $receipt.state -cne 'UNAPPROVED_UNINSTALLED_NO_DEPLOY_AUTHORITY' -or
     $receipt.review_commit -cne $review -or
     $receipt.source_commit -cne $source -or
     $receipt.manifest_sha256 -cne $manifestSha -or
     $receipt.main_sha256 -cne $mainSha -or
     $receipt.resident_sha256 -cne $agentSha -or
     $receipt.bootstrap_remains_installed_stable_sha256 -cne $bootstrapSha -or
     [int]$receipt.chunk_count -ne 21){StopNow 'R85_R84_ATTESTATION_RECEIPT_MISMATCH'}
  [byte[]]$raw=CheckedBytes (Join-Path $root 'manifest.json') 125610 $manifestSha
  [void](CheckedBytes (Join-Path $root 'spotify-control.ps1') 294101 $mainSha)
  [void](CheckedBytes (Join-Path $root 'spotify-control-agent.vbs') 13308 $agentSha)
  $manifest=[Text.Encoding]::UTF8.GetString($raw) | ConvertFrom-Json -ErrorAction Stop
  if($manifest.latest_version -cne '0.6.30' -or
     [string]$manifest.source_commit -cne $source -or
     [string]$manifest.bootstrap.sha256 -cne $bootstrapSha -or
     @($manifest.updates).Count -ne 19){StopNow 'R85_REVIEW_MANIFEST_INCOMPATIBLE'}
  if([string]::IsNullOrWhiteSpace($OfficialBootstrapPath)){
    $OfficialBootstrapPath=Join-Path $appData 'SpotifyControl\bootstrap\spotify-control-self-updater.ps1'
  }
  [byte[]]$originalBoot=CheckedBytes $OfficialBootstrapPath 42963 $bootstrapSha
  $text=[Text.Encoding]::ASCII.GetString($originalBoot)
  if([Text.Encoding]::ASCII.GetByteCount($text) -ne 42963 -or
     $text.Contains([char]0)){StopNow 'R85_BOOTSTRAP_NOT_PLAIN_ASCII'}
  $fixedManifest="'https://raw.githubusercontent.com/sdsssdvx2/spotify-control-updates/main/manifest.json'"
  $fixedPrefix="'https://raw.githubusercontent.com/'"
  if($text.Split(@($fixedManifest),[StringSplitOptions]::None).Count -ne 2 -or
     $text.Split(@($fixedPrefix),[StringSplitOptions]::None).Count -ne 2){
    StopNow 'R85_ORIGINAL_BOOTSTRAP_LOCATORS_NOT_EXACT'
  }
  $specs=@(
    @{dir='main-v0628-to-v0630';count=19},
    @{dir='resident-v011-to-v012';count=2}
  )
  $chunks=@{}
  $patches=@($manifest.updates[18].patches)
  if($patches.Count -ne 2){StopNow 'R85_CHUNK_METADATA_NOT_TWO_TARGETS'}
  for($j=0;$j -lt 2;$j++){
    if(@($patches[$j].chunks).Count -ne $specs[$j].count){
      StopNow 'R85_CHUNK_COUNT_PER_TARGET_MISMATCH'
    }
    for($i=0;$i -lt $specs[$j].count;$i++){
      $entry=@($patches[$j].chunks)[$i]
      $rel='packages/v0.6.30/'+$specs[$j].dir+'/chunk-'+$i.ToString('000')+'.txt'
      if([string]$entry.path -cne $rel -or [long]$entry.size -lt 1 -or
         [long]$entry.size -gt 4096 -or [string]$entry.sha256 -cnotmatch '^[0-9a-f]{64}$'){
        StopNow 'R85_CHUNK_PATH_OR_METADATA_INVALID'
      }
      $path=Join-Path $root ($rel.Replace('/','\'))
      $chunks[$rel]=CheckedBytes $path ([long]$entry.size) ([string]$entry.sha256)
    }
  }
  if($chunks.Count -ne 21){StopNow 'R85_EXPECTED_EXACT_21_CHUNKS'}
  $phase='R85_PRIVATE_COMPOSER'
  $id=[Guid]::NewGuid().ToString('N')
  $privateTmp=Join-Path $appData ('SpotifyControlCanary-offline-tmp-'+$id)
  $ready=Join-Path $appData ('SpotifyControlCanary-offline-ready-'+$id)
  if([IO.Directory]::Exists($privateTmp) -or [IO.Directory]::Exists($ready) -or
     [IO.File]::Exists($privateTmp) -or [IO.File]::Exists($ready)){
    StopNow 'R85_PRIVATE_STAGE_EXACT_NAME_COLLISION'
  }
  $rights=New-Object Security.AccessControl.DirectorySecurity
  $rights.SetOwner($owner)
  $rights.SetAccessRuleProtection($true,$false)
  $systemSid=[Security.Principal.SecurityIdentifier]::new([Security.Principal.WellKnownSidType]::LocalSystemSid,$null)
  $inherit=[Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit
  foreach($sid in @($owner,$systemSid)){
    $rights.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
      $sid,[Security.AccessControl.FileSystemRights]::FullControl,$inherit,
      [Security.AccessControl.PropagationFlags]::None,
      [Security.AccessControl.AccessControlType]::Allow))
  }
  [void][IO.Directory]::CreateDirectory($privateTmp,$rights)
  $created=$true
  $finalUri=[Uri]::new((Join-Path $ready 'manifest.json')).AbsoluteUri
  if($finalUri -cnotmatch '^file:///[A-Za-z]:/' -or $finalUri.Contains("'") -or
     -not $finalUri.EndsWith('/manifest.json',[StringComparison]::Ordinal)){
    StopNow 'R85_LOCAL_URI_NOT_SAFE_QUOTED_ASCII'
  }
  $prefix=$finalUri.Substring(0,$finalUri.Length-'manifest.json'.Length)
  $derived=$text.Replace($fixedManifest,("'"+$finalUri+"'")).Replace($fixedPrefix,("'"+$prefix+"'"))
  if($derived.Contains('https://raw.githubusercontent.com/') -or
     -not $derived.Contains("'"+$finalUri+"'") -or
     -not $derived.Contains("'"+$prefix+"'")){
    StopNow 'R85_DERIVED_BOOTSTRAP_LOCATORS_NOT_ISOLATED'
  }
  [byte[]]$derivedBytes=[Text.Encoding]::ASCII.GetBytes($derived)
  $derivedSha=Sha $derivedBytes
  $manifest.bootstrap.sha256=$derivedSha
  $manifest.bootstrap.size=$derivedBytes.Length
  [byte[]]$mirrorManifest=[Text.Encoding]::UTF8.GetBytes(($manifest|ConvertTo-Json -Depth 70 -Compress))
  if($mirrorManifest.Length -gt 200000){StopNow 'R85_DERIVED_MANIFEST_TOO_LARGE'}
  $sourceTree=Join-Path $privateTmp ('sdsssdvx2\spotify-control-updates\'+$source+'\packages\v0.6.30')
  foreach($spec in $specs){
    [void][IO.Directory]::CreateDirectory((Join-Path $sourceTree $spec.dir),$rights)
  }
  foreach($rel in @($chunks.Keys)){
    $f=Join-Path $privateTmp ('sdsssdvx2\spotify-control-updates\'+$source+'\'+$rel.Replace('/','\'))
    WriteNew $f ([byte[]]$chunks[$rel])
    if((Sha ([IO.File]::ReadAllBytes($f))) -cne (Sha ([byte[]]$chunks[$rel]))){
      StopNow 'R85_OFFLINE_CHUNK_READBACK_INVALID'
    }
  }
  WriteNew (Join-Path $privateTmp 'manifest.json') $mirrorManifest
  WriteNew (Join-Path $privateTmp 'bootstrap-verified-locator-copy.ps1') $derivedBytes
  if((Sha ([IO.File]::ReadAllBytes((Join-Path $privateTmp 'bootstrap-verified-locator-copy.ps1')))) -cne $derivedSha){
    StopNow 'R85_OFFLINE_BOOTSTRAP_READBACK_INVALID'
  }
  $receipt85=[ordered]@{
    schema='SPOTIFY_R85_PRIVATE_OFFLINE_TRANSPORT_V1'
    result='HOLD_ONLY_NOT_DEPLOYABLE'
    source_stage_id=[IO.Path]::GetFileName($root)
    manifest_source_sha256=$manifestSha
    mirror_manifest_sha256=Sha $mirrorManifest
    original_bootstrap_sha256=$bootstrapSha
    disposable_bootstrap_sha256=$derivedSha
    manifest_source_commit=$source
    chunks=21
    installed_bootstrap_changed=$false
    owner_approved=$false
  }
  [byte[]]$json=[Text.Encoding]::UTF8.GetBytes(($receipt85|ConvertTo-Json -Compress))
  WriteNew (Join-Path $privateTmp 'offline-receipt.json') $json
  [IO.Directory]::Move($privateTmp,$ready)
  $created=$false
  $privateTmp=''
  $log.Add('R85_OWNER_OFFLINE_STAGE_ID='+$id)
  $log.Add('R85_OFFICIAL_BOOTSTRAP=UNMODIFIED_IN_OPERATING_ROOT')
  $log.Add('R85_DISPOSABLE_BOOTSTRAP_ONLY_TWO_SOURCE_LOCATORS=REPLACED')
  $log.Add('R85_R84_PINNED_21_CHUNKS_MIRRORED_FROM_LOCAL_DISK=PASS')
  $log.Add('R85_OFFLINE_PREPUBLICATION_TRANSPORT=PRIVATE_READY_NOT_EXECUTED')
  $log.Add('RESULT=R85_OWNER_PRIVATE_OFFLINE_TRANSPORT_PREPARED_HOLD')
}catch{
  PurgeOurScratchOnly $privateTmp
  $err=[string]$_.Exception.Message
  if($err -cnotmatch '^R85_[A-Z0-9_]{5,95}$'){$err='R85_PRIVATE_STAGE_UNVERIFIED'}
  $log.Add('FAILED_PHASE='+$phase)
  $log.Add('HOLD_REASON='+$err)
  $log.Add('RESULT=R85_HOLD_NO_INSTALL_NO_AUTO_RETRY')
}finally{
  $log.Add('USER_SPOTIFY_SPICETIFY_STATE=UNCHANGED')
  $log.Add('USER_RESIDENT_AND_SHORTCUTS=UNCHANGED')
  $log.Add('PUBLIC_MAIN_MANIFEST=UNCHANGED')
  try{Set-Clipboard -Value ($log -join [Environment]::NewLine) -ErrorAction Stop}catch{}
  $log | ForEach-Object {Write-Output $_}
}
