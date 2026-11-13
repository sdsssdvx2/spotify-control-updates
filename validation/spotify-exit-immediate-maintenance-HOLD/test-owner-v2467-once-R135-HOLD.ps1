$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$base='validation/spotify-exit-immediate-maintenance-HOLD/'
$p=$base+'out/owner-v2467-one-approved-attempt-R135/spotify-control.ps1'
$errors=$null;$tokens=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($p,[ref]$tokens,[ref]$errors)
if(@($errors).Count -gt 0){throw 'R135_WINDOWS_PS51_FULL_PRODUCT_SYNTAX_INVALID'}
$functions=@('Get-R135OwnerAttemptPath','Read-R135OwnerAttempt',
 'Assert-R135ActiveOwnerAttempt','Invoke-R135OwnerSpicetifyOneShot',
 'Test-R134OwnerReconciledMutationHold','Start-SpicetifyCliTransaction')
$defs=@($ast.FindAll({param($n)
  $n -is [Management.Automation.Language.FunctionDefinitionAst] -and
  $n.Name -cin $functions
},$true))
if($defs.Count -ne $functions.Count){throw 'R135_REAL_FUNCTIONS_MISSING'}
. ([ScriptBlock]::Create((@($defs|ForEach-Object{$_.Extent.Text}) -join [Environment]::NewLine)))
$old=$env:LOCALAPPDATA
$scratch=Join-Path $env:RUNNER_TEMP ('R135-OwnerOnly-'+[guid]::NewGuid().ToString('N'))
$env:LOCALAPPDATA=Join-Path $scratch 'Local'
try {
  $script:Root=Join-Path $env:LOCALAPPDATA 'SpotifyControl'
  $script:SpicetifyTransactionPath=Join-Path $script:Root 'spicetify-last-transaction.json'
  $dir=Join-Path $script:Root 'owner-recovery'
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $txnId='20261113-200055-aabbccdd'
  $global:Owner=[pscustomobject]@{
    schema=3;root_transaction=$true;id=$txnId;status='owner-reviewed-preimage'
    before_version='2.46.4';before_tree_sha256=('a'*64)
    target_root=(Join-Path $env:LOCALAPPDATA 'spicetify')
    owner_reconciliation=[pscustomobject]@{evidence_sha256=('b'*64)}
  }
  $enc=New-Object System.Text.UTF8Encoding($false)
  [IO.File]::WriteAllText($script:SpicetifyTransactionPath,'{"synthetic":"ledger"}',$enc)
  $global:Calls=0
  $global:ProductMutations=0
  $global:FailAuthorizedAttempt=$false
  function Get-SpicetifyTransaction{return $global:Owner}
  function Assert-SpicetifyOwnerPreimageAdoption {param($Txn);return $true}
  function Get-ExactFileSha256 {
    param([string]$Path)
    if($Path -ceq (Join-Path $env:LOCALAPPDATA 'spicetify\spicetify.exe')){
      return '3563f26acd7527adc97e6c19272fa1b48ce976a913625d9804ac57d3c54fb4db'
    }
    if(Test-Path -LiteralPath $Path -PathType Leaf){
      return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    return $null
  }
  function Test-SpotifyRunning{return $false}
  function Enter-SpotifyControlMutex {param([string]$Purpose);return ('SYNTHETIC:'+ $Purpose)}
  function Exit-SpotifyControlMutex {param($Mutex)}
  function Get-SpicetifyRootManifest {param([string]$Path);return [pscustomobject]@{TreeSha256=('a'*64)}}
  function Get-IniSectionValue {param($Path,$Section,$Key);return '2.46.4'}
  function Load-State {return [pscustomobject]@{agent_mutation_enabled=$true;pending_spicetify_upgrade=$true}}
  function Ensure-StateShape {param($State);return $State}
  function Write-Log {param($Message,$Level)}
  function Invoke-SpicetifyTransactionalMaintenance {
     param($State)
     $global:Calls++
     if($global:FailAuthorizedAttempt){throw 'R135_SYNTHETIC_EXTERNAL_RESULT_UNCERTAIN'}
     if(-not $script:R135ActiveOwnerAttempt -or
        -not(Test-R134OwnerReconciledMutationHold) -eq $false){
        throw 'R135_SYNTHETIC_PROCESS_PERMIT_NOT_VALID'
     }
     $global:Owner=[pscustomobject]@{status='committed';id='new-transaction';before_version='2.46.4';after_version='2.46.7'}
     return [pscustomobject]@{Success=$true;Status='committed';Changed=$true;State=$State}
  }
  $script:R135AttemptCalls=0
  $script:R135ActiveOwnerAttempt=$false
  $script:R135ClaimSHA=$null
  $script:R135OwnerId=$null
  if((Test-R134OwnerReconciledMutationHold) -ne $true){throw 'R135_INITIAL_OWNER_STATUS_NOT_HELD'}
  $rejected=$false
  try{[void](Invoke-R135OwnerSpicetifyOneShot -OwnerApproval 'WRONG')}catch{
     $rejected=$_.Exception.Message -ceq 'R135_EXPLICIT_OWNER_APPROVAL_REQUIRED'
  }
  if(-not $rejected -or (Test-Path (Get-R135OwnerAttemptPath))){
     throw 'R135_UNAPPROVED_ATTEMPT_CREATED_CLAIM'
  }
  $result=Invoke-R135OwnerSpicetifyOneShot -OwnerApproval 'APPROVE_R135_SPICETIFY_2467_ONE_NATIVE_ATTEMPT'
  if($global:Calls -ne 1 -or -not(Test-Path -LiteralPath (Get-R135OwnerAttemptPath) -PathType Leaf)){
     throw 'R135_ONE_APPROVED_COMMIT_NOT_CLAIMED'
  }
  $c=Read-R135OwnerAttempt
  if([string]$c.owner_transaction_id -cne $txnId -or
     [string]$c.target_version -cne '2.46.7' -or
     (Test-R134OwnerReconciledMutationHold) -ne $true){
    throw 'R135_POST_COMMIT_GLOBAL_HOLD_NOT_PERSISTED'
  }
  $blocked=$false
  try{[void](Invoke-R135OwnerSpicetifyOneShot -OwnerApproval 'APPROVE_R135_SPICETIFY_2467_ONE_NATIVE_ATTEMPT')}catch{
    $blocked=$true
  }
  if(-not $blocked -or $global:Calls -ne 1){throw 'R135_SECOND_OWNER_ATTEMPT_ALLOWED'}
  Write-Host 'R135_SINGLE_EXPLICIT_OWNER_ATTEMPT_AND_DURABLE_CLAIM=PASS'
  Write-Host 'R135_NO_REPLAY_AFTER_COMMIT_AND_AUTOMATION_REMAINS_HELD=PASS'
  # A distinct scratch owner record verifies that a failed/unresponsive
  # attempt remains consumed across a fresh PowerShell-like runtime.
  $env:LOCALAPPDATA=Join-Path $scratch 'Local-Failed'
  $script:Root=Join-Path $env:LOCALAPPDATA 'SpotifyControl'
  $script:SpicetifyTransactionPath=Join-Path $script:Root 'spicetify-last-transaction.json'
  $dir=Join-Path $script:Root 'owner-recovery'
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  [IO.File]::WriteAllText($script:SpicetifyTransactionPath,'{"synthetic":"failed-ledger"}',$enc)
  $global:Owner=[pscustomobject]@{
    schema=3;root_transaction=$true;id=$txnId;status='owner-reviewed-preimage'
    before_version='2.46.4';before_tree_sha256=('a'*64)
    target_root=(Join-Path $env:LOCALAPPDATA 'spicetify')
    owner_reconciliation=[pscustomobject]@{evidence_sha256=('b'*64)}
  }
  $global:Calls=0
  $global:FailAuthorizedAttempt=$true
  $script:R135AttemptCalls=0
  $script:R135ActiveOwnerAttempt=$false
  $script:R135ClaimSHA=$null
  $script:R135OwnerId=$null
  $failed=$false
  try{
    [void](Invoke-R135OwnerSpicetifyOneShot -OwnerApproval 'APPROVE_R135_SPICETIFY_2467_ONE_NATIVE_ATTEMPT')
  }catch{
    $failed=$_.Exception.Message -ceq 'R135_SYNTHETIC_EXTERNAL_RESULT_UNCERTAIN'
  }
  if(-not $failed -or $global:Calls -ne 1 -or
     -not(Test-Path -LiteralPath (Get-R135OwnerAttemptPath) -PathType Leaf) -or
     $script:R135ActiveOwnerAttempt -ne $false){
     throw 'R135_UNCERTAIN_ATTEMPT_NOT_PERSISTENTLY_CONSUMED'
  }
  # Reset in-memory state, as on a new process, while keeping the same
  # exact persistent claim: the second model/native attempt is refused.
  $script:R135AttemptCalls=0
  $script:R135ActiveOwnerAttempt=$false
  $script:R135ClaimSHA=$null
  $script:R135OwnerId=$null
  $blocked=$false
  try{[void](Invoke-R135OwnerSpicetifyOneShot -OwnerApproval 'APPROVE_R135_SPICETIFY_2467_ONE_NATIVE_ATTEMPT')}catch{
     $blocked=$_.Exception.Message -ceq 'R135_PREVIOUS_ATTEMPT_EXISTS_NO_AUTO_RETRY'
  }
  if(-not $blocked -or $global:Calls -ne 1 -or
     (Test-R134OwnerReconciledMutationHold) -ne $true){
     throw 'R135_UNCERTAIN_ATTEMPT_REPLAYED_AFTER_PROCESS_RESET'
  }
  Write-Host 'R135_UNCERTAIN_FIRST_ATTEMPT_NO_REPLAY_AFTER_PROCESS_RESET=PASS'
  # Exercise the actual R135 direct Start-SpicetifyCliTransaction path,
  # stopping before mutation, to verify it never uses /releases/latest.
  $global:ReleaseLookups=0
  $global:ReleaseBad=$true
  function Get-SpicetifyManagedInstallInfo {
     return [pscustomobject]@{Managed=$true;Path=(Join-Path $env:LOCALAPPDATA 'spicetify\spicetify.exe');Version='2.46.4'}
  }
  function Get-SpicetifyLatestReleaseInfo {throw 'R135_LATEST_RELEASE_ENDPOINT_NOT_PERMITTED_FOR_APPROVED_ATTEMPT'}
  function Get-SpicetifyReleaseInfoForVersion {
     param($Version)
     $global:ReleaseLookups++
     if($Version -cne '2.46.7'){throw 'R135_WRONG_EXACT_TARGET_VERSION'}
     return [pscustomobject]@{
       Verified=$true;Tag='v2.46.7';Version=$Version;Architecture='x64'
       AssetDigest=$(if($global:ReleaseBad){'sha256:'+('0'*64)}else{
         'sha256:c5a723d31eae529ba13f6922a7a027124238c7f3da7edd182a73eab03c447e9e'})
     }
  }
  function Get-SpicetifyBackupMigrationClass {throw 'R135_SYNTHETIC_STOP_PRE_MUTATION'}
  function Compare-VersionParts {param($A,$B,$Count);return 1}
  function Get-ConfigPath{return (Join-Path $env:APPDATA 'spicetify\config-xpui.ini')}
  $script:R135AttemptCalls=1
  $script:R135ActiveOwnerAttempt=$true
  $script:R135OwnerId=$txnId
  $script:R135ClaimSHA=Get-ExactFileSha256 -Path (Get-R135OwnerAttemptPath)
  $digestRejected=$false
  try{[void](Start-SpicetifyCliTransaction)}catch{
     $digestRejected=$_.Exception.Message -ceq 'R135_OFFICIAL_TARGET_2467_ASSET_PIN_MISMATCH'
  }
  if(-not $digestRejected){throw 'R135_OFFICIAL_TARGET_MISMATCH_NOT_DENIED'}
  $global:ReleaseBad=$false
  $pinnedReached=$false
  try{[void](Start-SpicetifyCliTransaction)}catch{
     $pinnedReached=$_.Exception.Message -ceq 'R135_SYNTHETIC_STOP_PRE_MUTATION'
  }
  if(-not $pinnedReached -or $global:ReleaseLookups -ne 2){
     throw 'R135_PINNED_OFFICIAL_VERSION_DID_NOT_REACH_PRE_MUTATION_BOUNDARY'
  }
  $script:R135ActiveOwnerAttempt=$false
  if((Test-R134OwnerReconciledMutationHold) -ne $true){
     throw 'R135_OWNER_HOLD_NOT_RESTORED_AFTER_SYNTHETIC_TARGET_CHECK'
  }
  Write-Host 'R135_TARGET_2467_EXACT_RELEASE_DIGEST_AND_NOT_LATEST=PASS'
}finally {
  $env:LOCALAPPDATA=$old
  if(Test-Path $scratch){Remove-Item -LiteralPath $scratch -Recurse -Force}
}
