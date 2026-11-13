$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$p='validation/spotify-exit-immediate-maintenance-HOLD/out/owner-release-readiness-R137/spotify-control.ps1'
$tok=$null;$errs=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($p,[ref]$tok,[ref]$errs)
if(@($errs).Count -ne 0){throw 'R137_NATIVE_PRODUCT_SYNTAX_INVALID'}
$names=@('Assert-R137OfficialSpicetifyPairReady','Invoke-R135OwnerSpicetifyOneShot',
 'Test-R134OwnerReconciledMutationHold','Get-R135OwnerAttemptPath','Read-R135OwnerAttempt',
 'Assert-R135ActiveOwnerAttempt')
$defs=@($ast.FindAll({param($n)
 $n -is [Management.Automation.Language.FunctionDefinitionAst] -and
 $n.Name -cin $names
},$true))
if($defs.Count -ne $names.Count){throw 'R137_PRODUCTION_FUNCTIONS_NOT_FOUND'}
. ([ScriptBlock]::Create((@($defs|ForEach-Object{$_.Extent.Text}) -join [Environment]::NewLine)))
$script:Calls=@()
$script:ReleaseFailure=''
$script:BadDigest=$false
$script:BadOldDigest=$false
function Get-SpicetifyReleaseInfoForVersion {
 param([string]$Version)
 $script:Calls+=,$Version
 if($script:ReleaseFailure -ceq $Version){return [pscustomobject]@{Verified=$false}}
 return [pscustomobject]@{
   Verified=$true;Tag='v'+$Version;Version=$Version;Architecture='x64'
   AssetSize=10999999;AssetName=('spicetify-'+$Version+'-windows-x64.zip')
   AssetUrl=('https://github.com/spicetify/cli/releases/download/v'+$Version+'/spicetify-'+$Version+'-windows-x64.zip')
   AssetDigest=$(if($Version -ceq '2.46.7' -and $script:BadDigest){
      'sha256:'+('0'*64)
   }elseif($Version -ceq '2.46.7'){
      'sha256:c5a723d31eae529ba13f6922a7a027124238c7f3da7edd182a73eab03c447e9e'
   }elseif($script:BadOldDigest){'sha256:'+('1'*64)}
    else{'sha256:0490380bf59e00c94cf6cb12bfac5152791b91bb8009aceef53c49815b45a56f'})
 }
}
$fail=$false
$script:ReleaseFailure='2.46.4'
try{[void](Assert-R137OfficialSpicetifyPairReady)}catch{
 $fail=$_.Exception.Message -ceq 'R137_OFFICIAL_RELEASE_NOT_READY_2_46_4'
}
if(-not $fail){throw 'R137_MISSING_OLD_RECOVERY_RELEASE_NOT_REJECTED'}
$script:ReleaseFailure=''
$script:BadDigest=$true
$fail=$false
try{[void](Assert-R137OfficialSpicetifyPairReady)}catch{
 $fail=$_.Exception.Message -ceq 'R137_EXACT_TARGET_ASSET_SHA_MISMATCH'
}
if(-not $fail){throw 'R137_BAD_NEW_ASSET_PIN_NOT_REJECTED'}
$script:BadDigest=$false
$script:BadOldDigest=$true
$fail=$false
try{[void](Assert-R137OfficialSpicetifyPairReady)}catch{
 $fail=$_.Exception.Message -ceq 'R137_EXACT_ROLLBACK_ASSET_SHA_MISMATCH'
}
if(-not $fail){throw 'R137_BAD_OFFICIAL_2464_ASSET_PIN_NOT_REJECTED'}
$script:BadOldDigest=$false
$script:Calls=@()
if((Assert-R137OfficialSpicetifyPairReady) -cne $true -or
 $script:Calls.Count -ne 2 -or
 $script:Calls[0] -cne '2.46.4' -or $script:Calls[1] -cne '2.46.7'){
 throw 'R137_PAIR_READINESS_ORDER_INVALID'
}
Write-Host 'R137_OFFICIAL_SOURCE_AND_TARGET_RELEASE_METADATA_VERIFIED=PASS'
# Prove missing remote recovery release fails before any persistent R135
# claim, native call, or actual user's Spotify/Spicetify source writes.
$old=$env:LOCALAPPDATA;$oldRoam=$env:APPDATA
$scratch=Join-Path $env:RUNNER_TEMP ('R137-isolated-'+[guid]::NewGuid().ToString('N'))
$env:LOCALAPPDATA=Join-Path $scratch 'Local'
$env:APPDATA=Join-Path $scratch 'Roaming'
try {
  $script:Root=Join-Path $env:LOCALAPPDATA 'SpotifyControl'
  $script:SpicetifyTransactionPath=Join-Path $script:Root 'spicetify-last-transaction.json'
  $backup=Join-Path $script:Root 'owner-recovery'
  New-Item -ItemType Directory -Path $backup -Force | Out-Null
  $enc=New-Object System.Text.UTF8Encoding($false)
  [IO.File]::WriteAllText($script:SpicetifyTransactionPath,'{"synthetic":"ledger"}',$enc)
  $id='20261113-215000-aabbccdd'
  $script:Txn=[pscustomobject]@{id=$id;status='owner-reviewed-preimage';root_transaction=$true;before_version='2.46.4'
    before_tree_sha256=('a'*64);target_root=(Join-Path $env:LOCALAPPDATA 'spicetify')
    owner_reconciliation=[pscustomobject]@{evidence_sha256=('b'*64)}
  }
  $script:NativeCalls=0
  function Get-SpicetifyTransaction {return $script:Txn}
  function Test-SpotifyRunning {return $false}
  function Assert-SpicetifyOwnerPreimageAdoption {param($Txn);return $true}
  function Get-ExactFileSha256 {param($Path)
    if($Path -eq (Join-Path $env:LOCALAPPDATA 'spicetify\spicetify.exe')){
      return '3563f26acd7527adc97e6c19272fa1b48ce976a913625d9804ac57d3c54fb4db'
    }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
  }
  function Get-SpicetifyRootManifest {param($Path);return [pscustomobject]@{TreeSha256=('a'*64)}}
  function Get-IniSectionValue {param($Path,$Section,$Key);return '2.46.4'}
  function Get-SpicetifyManagedInstallInfo {return [pscustomobject]@{
    Managed=$true;Version='2.46.4';Path=(Join-Path $env:LOCALAPPDATA 'spicetify\spicetify.exe')
  }}
  function Get-SpicetifyBackupMigrationClass {
    param($InstalledVersion,$TargetVersion,$BackupWith)
    if($InstalledVersion -ne '2.46.4' -or $TargetVersion -ne '2.46.7' -or $BackupWith -ne '2.46.4'){
      throw 'R137_WRONG_MIGRATION_QUERY'
    }
    return 'VERSION_CHANGE_REQUIRES_ATOMIC_BACKUP_REPROCESSING'
  }
  function Enter-SpotifyControlMutex {param($Purpose);return ('SYNTHETIC:'+ $Purpose)}
  function Exit-SpotifyControlMutex {param($Mutex)}
  function Load-State{return [pscustomobject]@{}}
  function Ensure-StateShape {param($State);return $State}
  function Write-Log {param($Message,$Level)}
  function Invoke-SpicetifyTransactionalMaintenance {param($State)
    $script:NativeCalls++;throw 'R137_MOCK_NATIVE_ATTEMPT_REACHED'
  }
  $script:R135ActiveOwnerAttempt=$false;$script:R135AttemptCalls=0
  $script:R135ClaimSHA=$null;$script:R135OwnerId=$null
  $script:ReleaseFailure='2.46.4'
  $blocked=$false
  try{
    [void](Invoke-R135OwnerSpicetifyOneShot -OwnerApproval 'APPROVE_R135_SPICETIFY_2467_ONE_NATIVE_ATTEMPT')
  }catch{$blocked=$_.Exception.Message -ceq 'R137_OFFICIAL_RELEASE_NOT_READY_2_46_4'}
  if(-not $blocked -or $script:NativeCalls -ne 0 -or
     (Test-Path -LiteralPath (Get-R135OwnerAttemptPath))){
    throw 'R137_OWNER_CLAIM_CONSUMED_BEFORE_RELEASE_PREFLIGHT'
  }
  Write-Host 'R137_MISSING_RECOVERY_RELEASE_DOES_NOT_CONSUME_OWNER_APPROVAL=PASS'
  $script:ReleaseFailure=''
  $blocked=$false
  try{
    [void](Invoke-R135OwnerSpicetifyOneShot -OwnerApproval 'APPROVE_R135_SPICETIFY_2467_ONE_NATIVE_ATTEMPT')
  }catch{$blocked=$_.Exception.Message -ceq 'R137_MOCK_NATIVE_ATTEMPT_REACHED'}
  if(-not $blocked -or $script:NativeCalls -ne 1 -or
     -not (Test-Path -LiteralPath (Get-R135OwnerAttemptPath))){
    throw 'R137_VALID_TARGET_DID_NOT_CREATE_EXACTLY_ONE_CLAIM'
  }
  Write-Host 'R137_VALID_TARGET_CLAIM_ONLY_BEFORE_NATIVE_ATTEMPT=PASS'
}finally{
  $env:LOCALAPPDATA=$old;$env:APPDATA=$oldRoam
  if(Test-Path -LiteralPath $scratch){Remove-Item -LiteralPath $scratch -Recurse -Force}
}
