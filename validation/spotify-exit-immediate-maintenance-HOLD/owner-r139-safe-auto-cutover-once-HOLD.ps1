[CmdletBinding()]
param(
  [ValidateSet('Plan','Once','Recover')][string]$Mode='Plan',
  [string]$ApprovalPhrase='',
  [switch]$SyntheticHostTest
)
$ErrorActionPreference='Stop'
$root=Join-Path $env:LOCALAPPDATA 'SpotifyControl'
$main=Join-Path $root 'bin\spotify-control.ps1'
$statePath=Join-Path $root 'state.json'
$ledgerPath=Join-Path $root 'spicetify-last-transaction.json'
$claimPath=Join-Path $root 'owner-recovery\r135-v2467-owner-once-claim.v1.json'
$receiptPath=Join-Path $root 'owner-recovery\r139-safe-auto-baseline.v1.json'
$oldMainSha='4ac4e4ccb48c57b59b9fe87d688df76dd823998e5e791f4ed877c289175e7d99'
$newMainSha='0eed27b94f498b7a4e1e9e6575b9cfdd89ad52ce07a9dac413158b7a148a2595'
$newMainSize=341023
$newCommit='a48e0ea4315a12ab5ee102ea1f6779dc6cb9daf1'
$newUrl='https://raw.githubusercontent.com/sdsssdvx2/spotify-control-updates/'+$newCommit+'/validation/spotify-exit-immediate-maintenance-HOLD/spotify-control-R139-SafeAutoAfterR135-HOLD.ps1'
$approval='APPROVE_R139_SOURCE_AND_SAFE_AUTO_ONCE'
$recoverApproval='APPROVE_R139_CRASH_SOURCE_RECOVERY_ONCE'
$enableApproval='APPROVE_R139_SAFE_AUTOMATION_AFTER_VERIFIED_R135'
$out=New-Object 'System.Collections.Generic.List[string]'
[void]$out.Add('DIAGNOSTIC=SPOTIFY_R139_SAFE_AUTO_CUTOVER')
[void]$out.Add("MODE=$Mode")
[void]$out.Add('R135_UPDATE=NOT_REPEATED')
[void]$out.Add('SPOTIFY_OR_SPICETIFY_UPDATE=NO')
[void]$out.Add('AUTO_RETRY=NO')

function Hash {
  param([string]$p)
  if(-not(Test-Path -LiteralPath $p -PathType Leaf)){return $null}
  return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()
}
function RunningSpotify {
  if($SyntheticHostTest){return ([string]$env:R139_TEST_SPOTIFY_RUNNING -ceq 'YES')}
  return (@(Get-Process -Name Spotify -ErrorAction SilentlyContinue).Count -gt 0)
}
function VerifyR135Baseline {
  if((Hash $main) -cne $oldMainSha){throw 'R139_CURRENT_MAIN_NOT_EXACT_R137'}
  if(-not(Test-Path -LiteralPath $claimPath -PathType Leaf)){throw 'R139_R135_CLAIM_MISSING'}
  if(-not(Test-Path -LiteralPath $ledgerPath -PathType Leaf)){throw 'R139_LEDGER_MISSING'}
  $tx=Get-Content -LiteralPath $ledgerPath -Raw|ConvertFrom-Json
  if([string]$tx.status -cne 'committed' -or
     [string]$tx.before_version -cne '2.46.4' -or
     [string]$tx.after_version -cne '2.46.7' -or
     [string]$tx.asset_digest -cne 'sha256:c5a723d31eae529ba13f6922a7a027124238c7f3da7edd182a73eab03c447e9e' -or
     -not [bool]$tx.apply_succeeded -or
     -not [bool]$tx.migration_finished -or
     -not [bool]$tx.post_apply_guard_succeeded -or
     -not [bool]$tx.extras_preserved -or
     [string]$tx.extras_before_tree_sha256 -cne [string]$tx.extras_after_tree_sha256){
    throw 'R139_R135_COMMITTED_BASELINE_NOT_EXACT'
  }
  $exe=Join-Path $env:LOCALAPPDATA 'spicetify\spicetify.exe'
  if((Hash $exe) -cne ([string]$tx.after_sha256).ToLowerInvariant()){
    throw 'R139_SPICETIFY_EXE_NOT_COMMITTED_BASELINE'
  }
  return $tx
}
function GetCandidateBytes {
  if($SyntheticHostTest){
    $p=[string]$env:R139_TEST_SOURCE_PATH
    if([string]::IsNullOrWhiteSpace($p) -or -not(Test-Path -LiteralPath $p -PathType Leaf)){
      throw 'R139_TEST_SOURCE_MISSING'
    }
    return [IO.File]::ReadAllBytes($p)
  }
  [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
  $wc=New-Object Net.WebClient
  try{return $wc.DownloadData($newUrl)}finally{$wc.Dispose()}
}
function BytesSha {
  param([byte[]]$bytes)
  $h=[Security.Cryptography.SHA256]::Create()
  try{return ([BitConverter]::ToString($h.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()}
  finally{$h.Dispose()}
}
function Acquire {
  param([string]$purpose)
  $sid=if($SyntheticHostTest){'SYNTHETIC'}else{[Security.Principal.WindowsIdentity]::GetCurrent().User.Value}
  $safe=([string]$sid -replace '[^A-Za-z0-9]','_')
  $m=[System.Threading.Mutex]::new($false,("Local\SpotifyControl-{0}-{1}" -f $purpose,$safe))
  try{$ok=$m.WaitOne(0,$false)} catch [System.Threading.AbandonedMutexException] {$ok=$true}
  if(-not $ok){$m.Dispose();return $null}
  return $m
}
function Release-Mutex {
  param($Mutex)
  if($null -ne $Mutex){
    try{$Mutex.ReleaseMutex()}catch{}
    $Mutex.Dispose()
  }
}
function ReadEnabledState {
  if(-not(Test-Path -LiteralPath $statePath -PathType Leaf)){return $false}
  try{
    $s=Get-Content -LiteralPath $statePath -Raw|ConvertFrom-Json
    return [bool]$s.agent_mutation_enabled
  }catch{return $false}
}
function ValidR139Receipt {
  if(-not(Test-Path -LiteralPath $receiptPath -PathType Leaf)){return $false}
  try{
    $item=Get-Item -LiteralPath $receiptPath -Force
    if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){return $false}
    $r=Get-Content -LiteralPath $receiptPath -Raw|ConvertFrom-Json
    if([string]$r.schema -cne '1' -or
       [string]$r.kind -cne 'R139_SAFE_AUTO_AFTER_VERIFIED_R135' -or
       [string]$r.r135_claim_sha256 -cnotmatch '^[a-f0-9]{64}$' -or
       [string]$r.r135_committed_ledger_sha256 -cnotmatch '^[a-f0-9]{64}$' -or
       [string]$r.r135_transaction_id -cnotmatch '^\d{8}-\d{6}-[a-f0-9]{8}$' -or
       [string]$r.spicetify_version -cne '2.46.7' -or
       [string]$r.spicetify_exe_sha256 -cnotmatch '^[a-f0-9]{64}$' -or
       [string]$r.r135_asset_digest -cne 'sha256:c5a723d31eae529ba13f6922a7a027124238c7f3da7edd182a73eab03c447e9e'){
      return $false
    }
    return ((Hash $claimPath) -ceq [string]$r.r135_claim_sha256)
  }catch{return $false}
}

$maintenance=$null
$agent=$null
$backup=$main+'.r139-previous'
$held=$main+'.r139-failed-new-HOLD'
try{
  if($Mode -ceq 'Recover'){
    $mainHash=Hash $main
    $backupHash=Hash $backup
    if($mainHash -eq $newMainSha -and
       (ValidR139Receipt) -and
       (ReadEnabledState)){
      [void]$out.Add('R139_MAIN=INSTALLED_PIN_VERIFIED')
      [void]$out.Add('R139_SAFE_AUTO_BASELINE=PRESENT')
      [void]$out.Add('R139_AGENT_MUTATION=ENABLED')
      [void]$out.Add('RESULT=R139_CUTOVER_ALREADY_CONFIRMED')
      return
    }
    if($ApprovalPhrase -cne $recoverApproval){throw 'R139_EXPLICIT_RECOVERY_APPROVAL_REQUIRED'}
    if($mainHash -cne $newMainSha -or $backupHash -cne $oldMainSha){
      throw 'R139_CRASH_STATE_NOT_EXACTLY_RECOVERABLE'
    }
    if(Test-Path -LiteralPath $held){throw 'R139_FAILED_NEW_HOLD_COLLISION'}
    $maintenance=Acquire 'Maintenance'
    if($null -eq $maintenance){throw 'R139_MAINTENANCE_MUTEX_BUSY'}
    $agent=Acquire 'AgentTick'
    if($null -eq $agent){throw 'R139_AGENT_MUTEX_BUSY'}
    if((Hash $main) -cne $newMainSha -or (Hash $backup) -cne $oldMainSha){
      throw 'R139_CRASH_STATE_CHANGED_UNDER_MUTEX'
    }
    [IO.File]::Replace($backup,$main,$held,$true)
    if((Hash $main) -cne $oldMainSha -or (Hash $held) -cne $newMainSha){
      throw 'R139_RECOVERY_READBACK_FAILED'
    }
    [void]$out.Add('ROLLBACK_SOURCE=R137_RESTORED_SHA_VERIFIED')
    [void]$out.Add('R139_FAILED_NEW_SOURCE=PRESERVED_SHA_VERIFIED')
    [void]$out.Add('RESULT=R139_SOURCE_RECOVERED_OWNER_REVIEW_REQUIRED')
    return
  }

  $candidate=GetCandidateBytes
  if($candidate.Length -ne $newMainSize -or (BytesSha $candidate) -cne $newMainSha){
    throw 'R139_CANDIDATE_SHA_OR_SIZE_MISMATCH'
  }
  $text=([Text.Encoding]::UTF8.GetString($candidate)).TrimStart([char]0xFEFF)
  $tokens=$null;$errors=$null
  [void][Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors)
  if(@($errors).Count -ne 0 -or
     $text -notmatch 'OwnerEnableSafeAuto' -or
     $text -notmatch 'Invoke-R138PlaybackWarm' -or
     $text -notmatch 'agent_mutation_enabled'){
    throw 'R139_CANDIDATE_PARSE_OR_FEATURE_MISSING'
  }
  [void]$out.Add('R139_CANDIDATE=SHA256_AND_PARSE_PASS')

  [void](VerifyR135Baseline)
  [void]$out.Add('R137_CURRENT_MAIN=SHA256_PASS')
  [void]$out.Add('R135_COMMITTED_BASELINE=PASS')
  if(-not(RunningSpotify)){throw 'R139_SPOTIFY_MUST_BE_RUNNING_FOR_SAFE_ENABLE'}
  [void]$out.Add('SPOTIFY_RUNNING=PASS')

  if($Mode -ceq 'Plan'){
    [void]$out.Add('FILE_WRITE=NO')
    [void]$out.Add('RESULT=R139_CUTOVER_READY_NO_OPERATING_WRITE')
    return
  }
  if($ApprovalPhrase -cne $approval){throw 'R139_EXPLICIT_CUTOVER_APPROVAL_REQUIRED'}

  $maintenance=Acquire 'Maintenance'
  if($null -eq $maintenance){throw 'R139_MAINTENANCE_MUTEX_BUSY'}
  $agent=Acquire 'AgentTick'
  if($null -eq $agent){throw 'R139_AGENT_MUTEX_BUSY'}
  if(-not(RunningSpotify)){throw 'R139_SPOTIFY_CLOSED_BEFORE_SOURCE_SWAP'}
  [void](VerifyR135Baseline)
  if((Test-Path -LiteralPath $backup) -or (Test-Path -LiteralPath $held)){
    throw 'R139_STALE_CUTOVER_ARTIFACT_HOLD'
  }

  $temp=Join-Path (Split-Path -Parent $main) ('.r139-new-'+[guid]::NewGuid().ToString('N')+'.tmp')
  [IO.File]::WriteAllBytes($temp,$candidate)
  if((Hash $temp) -cne $newMainSha){throw 'R139_STAGED_SOURCE_HASH_MISMATCH'}
  [IO.File]::Replace($temp,$main,$backup,$true)
  if((Hash $main) -cne $newMainSha -or (Hash $backup) -cne $oldMainSha){
    throw 'R139_SOURCE_SWAP_READBACK_FAILED'
  }
  [void]$out.Add('R139_MAIN=INSTALLED_PIN_VERIFIED')

  # New R139 must acquire the product mutexes itself. Release the wrapper
  # locks only after the source swap is verified. Until its durable receipt
  # plus enabled state exist, R139 remains fail-closed on the old R135 claim.
  Release-Mutex $agent; $agent=$null
  Release-Mutex $maintenance; $maintenance=$null

  if($SyntheticHostTest){
    if([string]$env:R139_TEST_ENABLE_RESULT -ceq 'PASS'){
      $tx=Get-Content -LiteralPath $ledgerPath -Raw|ConvertFrom-Json
      $rr=[ordered]@{
        schema=1;kind='R139_SAFE_AUTO_AFTER_VERIFIED_R135'
        r135_claim_sha256=(Hash $claimPath)
        r135_committed_ledger_sha256=(Hash $ledgerPath)
        r135_transaction_id='20261114-020000-11223344'
        spicetify_version='2.46.7'
        spicetify_exe_sha256=[string]$tx.after_sha256
        r135_asset_digest='sha256:c5a723d31eae529ba13f6922a7a027124238c7f3da7edd182a73eab03c447e9e'
        issued_at=[DateTimeOffset]::UtcNow.ToString('o')
      }
      [IO.File]::WriteAllText($receiptPath,($rr|ConvertTo-Json -Depth 5))
      $st=Get-Content -LiteralPath $statePath -Raw|ConvertFrom-Json
      $st.agent_mutation_enabled=$true
      [IO.File]::WriteAllText($statePath,($st|ConvertTo-Json -Depth 8))
      $enableOutput=@('R139_R135_BASELINE=SEALED','R139_AGENT_MUTATION=ENABLED')
      $enableExit=0
    }else{
      $enableOutput=@('synthetic failure')
      $enableExit=2
    }
  }else{
    $psi=New-Object Diagnostics.ProcessStartInfo
    $psi.FileName=Join-Path $PSHOME 'powershell.exe'
    $psi.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$main+'" -Action OwnerEnableSafeAuto -OwnerSafeAutoApproval '+$enableApproval
    $psi.UseShellExecute=$false
    $psi.CreateNoWindow=$true
    $psi.RedirectStandardOutput=$true
    $psi.RedirectStandardError=$true
    $p=New-Object Diagnostics.Process
    $p.StartInfo=$psi
    try{
      if(-not $p.Start()){throw 'R139_ENABLE_PROCESS_START_FAILED'}
      $a=$p.StandardOutput.ReadToEndAsync()
      $b=$p.StandardError.ReadToEndAsync()
      $p.WaitForExit()
      $enableOutput=@(($a.Result -split '\r?\n')|Where-Object{$_})
      [void]$b.Result
      $enableExit=$p.ExitCode
    }finally{$p.Dispose()}
  }

  $enableOk=($enableExit -eq 0 -and
             $enableOutput -contains 'R139_R135_BASELINE=SEALED' -and
             $enableOutput -contains 'R139_AGENT_MUTATION=ENABLED')
  if(-not $enableOk){throw 'R139_SAFE_AUTO_ENABLE_NOT_CONFIRMED'}
  if(-not(ValidR139Receipt)){throw 'R139_RECEIPT_NOT_VERIFIED'}
  if(-not(ReadEnabledState)){throw 'R139_AGENT_MUTATION_NOT_ENABLED'}
  if((Hash $main) -cne $newMainSha){throw 'R139_MAIN_CHANGED_AFTER_ENABLE'}

  [void]$out.Add('R139_SAFE_AUTO_BASELINE=SEALED')
  [void]$out.Add('R139_AGENT_MUTATION=ENABLED')
  [void]$out.Add('R139_PREVIOUS_SOURCE=SHA256_VERIFIED')
  [void]$out.Add('RESULT=R139_CUTOVER_AND_SAFE_AUTO_ENABLED')
}catch{
  $reason=[string]$_.Exception.Message
  if($Mode -ceq 'Once' -and
     (Test-Path -LiteralPath $backup -PathType Leaf) -and
     (Hash $main) -eq $newMainSha){
    try{
      # Reacquire both product locks before reverting a failed cutover.
      $maintenance=Acquire 'Maintenance'
      if($null -eq $maintenance){throw 'R139_ROLLBACK_MAINTENANCE_MUTEX_BUSY'}
      $agent=Acquire 'AgentTick'
      if($null -eq $agent){throw 'R139_ROLLBACK_AGENT_MUTEX_BUSY'}
      if((Hash $main) -cne $newMainSha -or (Hash $backup) -cne $oldMainSha){
        throw 'R139_ROLLBACK_PREIMAGE_CHANGED'
      }
      if(Test-Path -LiteralPath $held){throw 'R139_FAILED_NEW_HOLD_COLLISION'}
      [IO.File]::Replace($backup,$main,$held,$true)
      if((Hash $main) -eq $oldMainSha -and (Hash $held) -eq $newMainSha){
        [void]$out.Add('ROLLBACK_SOURCE=R137_RESTORED_SHA_VERIFIED')
        [void]$out.Add('R139_FAILED_NEW_SOURCE=PRESERVED_SHA_VERIFIED')
      }else{
        [void]$out.Add('ROLLBACK_SOURCE=VERIFY_FAILED')
      }
    }catch{
      [void]$out.Add('ROLLBACK_SOURCE=FAILED_HOLD')
    }
  }
  if($reason -cnotmatch '^[A-Z0-9_]{4,100}$'){$reason=$_.Exception.GetType().Name}
  [void]$out.Add("HOLD_CLASS=$reason")
  [void]$out.Add('RESULT=HOLD_NO_AUTO_RETRY')
}finally{
  Release-Mutex $agent; $agent=$null
  Release-Mutex $maintenance; $maintenance=$null
  $receipt=$out.ToArray() -join [Environment]::NewLine
  if(-not $SyntheticHostTest){try{Set-Clipboard -Value $receipt -ErrorAction Stop}catch{}}
  Write-Output $receipt
}
