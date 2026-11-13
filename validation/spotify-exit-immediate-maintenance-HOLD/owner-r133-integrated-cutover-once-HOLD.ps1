[CmdletBinding()]
param(
  [ValidateSet('Plan','Once')][string]$Mode='Plan',
  [string]$ApprovalPhrase='',
  [switch]$SyntheticHostedFixture
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
# R133: owner-approved source cutover + R132 current-preimage adoption.
# Never invoke Spicetify, Spotify or AgentTick; never automatically retry.
$script:OldMainSha='b2b2fbf1afb60b58d501312160f7e2437c2452e90cb61ca8c2be0d877f92232d'
$script:NewMainSha='16db29223a50c9b2a504a543ab01fa898660642904e4be0414b959195bb113b1'
$script:R132Sha='c11d4c63f60f2487a9fbc33a9ab68066e08515aa150ee17c2f6a4e0ceecc86a0'
$script:PinnedCommit='a532704e092b088dcaba1d67d8aee40c3016c736'
$script:Repo='sdsssdvx2/spotify-control-updates'
$script:Folder='validation/spotify-exit-immediate-maintenance-HOLD/'
$script:Root=Join-Path $env:LOCALAPPDATA 'SpotifyControl'
$script:Main=Join-Path $script:Root 'bin\spotify-control.ps1'
$script:Ledger=Join-Path $script:Root 'spicetify-last-transaction.json'
$script:Phase='START'
$script:Published=$false
$script:Adopted=$false
$script:OldLedgerSha=$null
$script:OldBackup=$null
$script:Tmp=$null
$script:Locks=@()
$script:Report=New-Object 'System.Collections.Generic.List[string]'
function Emit([string]$Key,[string]$Value){
  [void]$script:Report.Add($Key+'='+$Value)
}
function HBytes([byte[]]$Data){
  $sha=[Security.Cryptography.SHA256]::Create()
  try{return ([BitConverter]::ToString($sha.ComputeHash($Data))).Replace('-','').ToLowerInvariant()}
  finally{$sha.Dispose()}
}
function HFile([string]$Path){
  $f=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
  if($f.PSIsContainer -or ($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
    throw 'R133_UNSAFE_FILE'
  }
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}
function New-File([string]$Path,[byte[]]$Bytes){
  $fs=[IO.FileStream]::new($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try{$fs.Write($Bytes,0,$Bytes.Length);$fs.Flush($true)}finally{$fs.Dispose()}
}
function Pinned-Download([string]$Name,[string]$Hash,[int64]$Length){
  $url='https://raw.githubusercontent.com/'+$script:Repo+'/'+$script:PinnedCommit+'/'+$script:Folder+$Name
  $wc=New-Object Net.WebClient
  try{[byte[]]$b=$wc.DownloadData($url)}finally{$wc.Dispose()}
  if($b.Length -ne $Length -or (HBytes $b) -cne $Hash){
    throw 'R133_REMOTE_SOURCE_PIN_INVALID'
  }
  $enc=[Text.UTF8Encoding]::new($false,$true)
  $text=$enc.GetString($b)
  $astErrors=$null;$astTokens=$null
  [void][Management.Automation.Language.Parser]::ParseInput($text,[ref]$astTokens,[ref]$astErrors)
  if(@($astErrors).Count -ne 0){throw 'R133_REMOTE_SOURCE_PS51_SYNTAX_INVALID'}
  return [pscustomobject]@{Bytes=$b;Text=$text}
}
function Acquire([string]$Purpose){
  $ident=[Security.Principal.WindowsIdentity]::GetCurrent()
  $name='Local\SpotifyControl-'+$Purpose+'-'+$ident.User.Value
  $m=[Threading.Mutex]::new($false,$name)
  try{
    if(-not $m.WaitOne(0)){throw 'R133_MAINTENANCE_BUSY'}
    $script:Locks+=,$m
  }catch{$m.Dispose();throw}
}
function Release-Locks{
  foreach($m in @($script:Locks)){
    if($null -ne $m){try{$m.ReleaseMutex()}finally{$m.Dispose()}}
  }
  $script:Locks=@()
}
function Check-Old-Admission {
  $mainSHA=HFile $script:Main
  if($mainSHA -cne $script:OldMainSha){throw 'R133_OWNER_MAIN_NOT_APPROVED_R112'}
  $script:OldLedgerSha=HFile $script:Ledger
  $tx=Get-Content -LiteralPath $script:Ledger -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
  if([string]$tx.status -cne 'awaiting-guard' -or
     [string]$tx.schema -cne '3' -or
     -not [bool]$tx.root_transaction -or
     [string]$tx.before_version -cne '2.46.4'){
     throw 'R133_OWNER_LEDGER_NOT_EXACT_PENDING_R112'
  }
  if((HFile $script:Ledger) -cne $script:OldLedgerSha){throw 'R133_LEDGER_CHANGED_DURING_ADMISSION'}
  return [string]$tx.id
}
function Try-SafeRestore {
  # The source may be restored only when R132 did not publish any new ledger
  # and when the exact new source is still installed.
  try{
    Acquire 'Maintenance'
    Acquire 'AgentTick'
    if((HFile $script:Ledger) -cne $script:OldLedgerSha -or
       (HFile $script:Main) -cne $script:NewMainSha -or
       (HFile $script:OldBackup) -cne $script:OldMainSha){
      Emit 'ROLLBACK_SOURCE' 'NOT_ATTEMPTED_UNCERTAIN_STATE'
      return
    }
    $restore=$script:Main+'.r133-restore-'+[guid]::NewGuid().ToString('N')+'.tmp'
    New-File $restore ([IO.File]::ReadAllBytes($script:OldBackup))
    if((HFile $restore) -cne $script:OldMainSha){throw 'R133_RESTORE_STAGE_SHA_INVALID'}
    $failed=$script:Main+'.r133-new-source-held'
    if(Test-Path -LiteralPath $failed){throw 'R133_EXISTING_FAILED_SOURCE_BACKUP'}
    [IO.File]::Replace($restore,$script:Main,$failed,$true)
    if((HFile $script:Main) -cne $script:OldMainSha){throw 'R133_RESTORED_MAIN_READBACK_INVALID'}
    Emit 'ROLLBACK_SOURCE' 'R112_RESTORED_SHA_VERIFIED'
  }catch{
    Emit 'ROLLBACK_SOURCE' 'UNCERTAIN_OWNER_REVIEW_REQUIRED'
  }finally{
    Release-Locks
  }
}
Emit 'DIAGNOSTIC' 'SPOTIFY_R133_INTEGRATED_R131_R132_OWNER_CUTOVER'
Emit 'MODE' $Mode
Emit 'NATIVE_CLI' 'NOT_EXECUTED'
Emit 'SPOTIFY_OR_AGENT_RESTART' 'NO'
Emit 'NO_AUTO_RETRY' 'YES'
$previousTLS=[Net.ServicePointManager]::SecurityProtocol
try{
  if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
     $PSVersionTable.PSVersion.Major -ne 5 -or
     $PSVersionTable.PSEdition -cne 'Desktop'){throw 'R133_WINDOWS_PS51_ONLY'}
  if($SyntheticHostedFixture){
    if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
       $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
       -not $env:LOCALAPPDATA.StartsWith([string]$env:RUNNER_TEMP,[StringComparison]::OrdinalIgnoreCase)){
      throw 'R133_SYNTHETIC_HOST_NOT_TRUSTED'
    }
    $script:OldMainSha=[string]$env:R133_TEST_OLD_MAIN_SHA
    if($script:OldMainSha -cnotmatch '^[a-f0-9]{64}$'){throw 'R133_SYNTHETIC_OLD_MAIN_SHA_MISSING'}
  }
  if($Mode -ceq 'Once'){
    if($ApprovalPhrase -cne 'APPROVE_R133_R131_SOURCE_AND_R132_OWNER_ADOPTION_ONCE'){
      throw 'R133_EXPLICIT_OWNER_APPROVAL_REQUIRED'
    }
    $principal=[Security.Principal.WindowsPrincipal]::new(
      [Security.Principal.WindowsIdentity]::GetCurrent())
    if(-not $SyntheticHostedFixture -and
       $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
      throw 'R133_NONADMIN_OWNER_REQUIRED'
    }
  }
  $script:Phase='PIN_SOURCES'
  [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
  $mainSource=Pinned-Download 'spotify-control-R131-Owner-Candidate-HOLD.ps1' $script:NewMainSha 316638
  $ownerSource=Pinned-Download 'owner-r132-current-preimage-adoption-HOLD.ps1' $script:R132Sha 12497
  Emit 'R131_SOURCE' 'EXACT_PIN_VERIFIED'
  Emit 'R132_SOURCE' 'EXACT_PIN_VERIFIED'
  $script:Phase='READ_OWNER_ADMISSION'
  $transactionId=Check-Old-Admission
  Emit 'R112_MAIN_AND_PENDING_LEDGER' 'SHA_ADMITTED'
  if($Mode -ceq 'Plan'){
    Emit 'RESULT' 'CUTOVER_PLAN_READY_NO_OPERATING_WRITES'
  }else{
    $script:Phase='EXCLUSIVE_SOURCE_CUTOVER'
    Acquire 'Maintenance'
    Acquire 'AgentTick'
    if(@(Get-Process -Name Spotify -ErrorAction SilentlyContinue).Count -ne 0){
      throw 'R133_SPOTIFY_RUNNING'
    }
    [void](Check-Old-Admission)
    $serial=[guid]::NewGuid().ToString('N')
    $store=Join-Path $script:Root ('owner-recovery\R133-source-'+$serial)
    [void][IO.Directory]::CreateDirectory($store)
    $script:OldBackup=Join-Path $store 'original-R112-main.ps1'
    [IO.File]::Copy($script:Main,$script:OldBackup,$false)
    if((HFile $script:OldBackup) -cne $script:OldMainSha){
      throw 'R133_ORIGINAL_MAIN_BACKUP_SHA_INVALID'
    }
    $script:Tmp=Join-Path (Split-Path -Parent $script:Main) ('.r133-'+$serial+'.tmp')
    New-File $script:Tmp $mainSource.Bytes
    if((HFile $script:Tmp) -cne $script:NewMainSha){
      throw 'R133_STAGED_MAIN_SHA_INVALID'
    }
    $backup=$script:Main+'.r133-previous'
    if(Test-Path -LiteralPath $backup){throw 'R133_PRIOR_SOURCE_SNAPSHOT_EXISTS'}
    if((HFile $script:Ledger) -cne $script:OldLedgerSha -or
       (HFile $script:Main) -cne $script:OldMainSha){
      throw 'R133_SOURCE_OR_LEDGER_CHANGED_BEFORE_SWAP'
    }
    [IO.File]::Replace($script:Tmp,$script:Main,$backup,$true)
    $script:Published=$true
    if((HFile $script:Main) -cne $script:NewMainSha -or
       (HFile $backup) -cne $script:OldMainSha){
      throw 'R133_NEW_SOURCE_OR_SNAPSHOT_READBACK_INVALID'
    }
    Release-Locks
    $script:Phase='R132_OWNER_PREIMAGE_ADOPTION'
    if($SyntheticHostedFixture){
      $env:R132_TEST_MAIN_SHA=$script:NewMainSha
      $env:R132_TEST_CLI_SHA=(HFile (Join-Path $env:LOCALAPPDATA 'spicetify\spicetify.exe'))
    }
    $args=@{Mode='Adopt';ApprovalPhrase='APPROVE_R132_CURRENT_PREIMAGE_ONCE'}
    if($SyntheticHostedFixture){$args.SyntheticHostTest=$true}
    $result=@(& ([ScriptBlock]::Create($ownerSource.Text)) @args)
    $receipt=@(($result -join [Environment]::NewLine) -split '\r?\n')
    if($receipt -notcontains 'RESULT=OWNER_ADOPTION_RECEIPTED_NOT_SPOTIFY_APPLY_PROOF'){
      throw 'R133_R132_ADOPTION_FAILED_NO_CLI_CALL'
    }
    $script:Phase='VERIFY_ATOMIC_OWNER_RESULT'
    $final=Get-Content -LiteralPath $script:Ledger -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if([string]$final.id -cne $transactionId -or
       [string]$final.status -cne 'owner-reviewed-preimage' -or
       (HFile $script:Main) -cne $script:NewMainSha){
      throw 'R133_FINAL_LEDGER_MAIN_BINDING_INVALID'
    }
    $script:Adopted=$true
    Emit 'R131_MAIN' 'INSTALLED_PIN_VERIFIED'
    Emit 'R132_LEDGER' 'OWNER_REVIEWED_CURRENT_PREIMAGE'
    Emit 'HISTORICAL_SPOTIFY_APPLY_RESTORE' 'NOT_CLAIMED'
    Emit 'NATIVE_SPICETIFY_UPGRADE' 'NOT_EXECUTED'
    Emit 'RESULT' 'OWNER_CUTOVER_ADOPTED_NO_MODEL_OR_SPICETIFY_CALL'
  }
}catch{
  Emit 'FAILED_PHASE' $script:Phase
  if($script:Published -and -not $script:Adopted){
    Release-Locks
    Try-SafeRestore
  }
  Emit 'RESULT' $(if($script:Published){'HOLD_AFTER_SOURCE_CUTOVER_REVIEW_REQUIRED'}else{'HOLD_NO_OPERATING_CUTOVER'})
}finally{
  Release-Locks
  [Net.ServicePointManager]::SecurityProtocol=$previousTLS
  Remove-Item Env:R132_TEST_MAIN_SHA -ErrorAction SilentlyContinue
  Remove-Item Env:R132_TEST_CLI_SHA -ErrorAction SilentlyContinue
}
$receipt=@($script:Report.ToArray()) -join [Environment]::NewLine
try{Set-Clipboard -Value $receipt -ErrorAction Stop}catch{}
Write-Output $receipt
