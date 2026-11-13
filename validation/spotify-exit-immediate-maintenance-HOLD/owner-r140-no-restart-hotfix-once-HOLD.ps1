[CmdletBinding()]
param(
  [ValidateSet('Plan','Once')][string]$Mode='Plan',
  [string]$ApprovalPhrase=''
)
$ErrorActionPreference='Stop'
$root=Join-Path $env:LOCALAPPDATA 'SpotifyControl'
$main=Join-Path $root 'bin\spotify-control.ps1'
$state=Join-Path $root 'state.json'
$ledger=Join-Path $root 'spicetify-last-transaction.json'
$claim=Join-Path $root 'owner-recovery\r135-v2467-owner-once-claim.v1.json'
$r139Receipt=Join-Path $root 'owner-recovery\r139-safe-auto-baseline.v1.json'
$spiceExe=Join-Path $env:LOCALAPPDATA 'spicetify\spicetify.exe'
$oldSha='0eed27b94f498b7a4e1e9e6575b9cfdd89ad52ce07a9dac413158b7a148a2595'
$newSha='4a2cb53618cbec34e4e7b361a7dc7b27d39b3af47af71689acd44e32535ec026'
$newSize=341038
$newCommit='5cc04c06d563bff68f33941b3477b1a385a6e5b6'
$newUrl='https://raw.githubusercontent.com/sdsssdvx2/spotify-control-updates/'+$newCommit+'/validation/spotify-exit-immediate-maintenance-HOLD/spotify-control-R140-NoRestartAfterSpotifyUpdate-HOLD.ps1'
$approval='APPROVE_R140_NO_RESTART_HOTFIX_ONCE'
$out=New-Object 'System.Collections.Generic.List[string]'
[void]$out.Add('DIAGNOSTIC=SPOTIFY_R140_NO_RESTART_HOTFIX')
[void]$out.Add("MODE=$Mode")
[void]$out.Add('SPOTIFY_UPDATE=NO;SPICETIFY_UPDATE=NO;AUTO_RETRY=NO')

function Get-ExactSha256 {
  param([string]$Path)
  if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){return $null}
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Get-CandidateBytes {
  [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12
  $wc=New-Object Net.WebClient
  try { return $wc.DownloadData($newUrl) } finally { $wc.Dispose() }
}
function Get-BytesSha256 {
  param([byte[]]$Bytes)
  $h=[Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($h.ComputeHash($Bytes))).Replace('-','').ToLowerInvariant() }
  finally { $h.Dispose() }
}
function Enter-Lock {
  param([ValidateSet('Maintenance','AgentTick')][string]$Purpose)
  $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  $safe=([string]$sid -replace '[^A-Za-z0-9]','_')
  $m=New-Object System.Threading.Mutex($false,("Local\SpotifyControl-{0}-{1}" -f $Purpose,$safe))
  try { $ok=$m.WaitOne(0,$false) } catch [System.Threading.AbandonedMutexException] { $ok=$true }
  if(-not $ok){$m.Dispose();return $null}
  return $m
}
function Exit-Lock {
  param($Mutex)
  if($null -eq $Mutex){return}
  try { $Mutex.ReleaseMutex() } catch {}
  try { $Mutex.Dispose() } catch {}
}

$maintenance=$null
$agent=$null
$backup=$main+'.r140-previous'
$held=$main+'.r140-failed-new-HOLD'
try{
  if((Get-ExactSha256 -Path $main) -cne $oldSha){throw 'R140_CURRENT_MAIN_NOT_EXACT_R139'}
  if(-not(Test-Path -LiteralPath $r139Receipt -PathType Leaf)){throw 'R140_R139_RECEIPT_MISSING'}
  if(-not(Test-Path -LiteralPath $state -PathType Leaf)){throw 'R140_STATE_MISSING'}
  $st=Get-Content -LiteralPath $state -Raw|ConvertFrom-Json
  if(-not [bool]$st.agent_mutation_enabled){throw 'R140_AGENT_NOT_ENABLED'}
  if(-not(Test-Path -LiteralPath $ledger -PathType Leaf) -or -not(Test-Path -LiteralPath $claim -PathType Leaf) -or -not(Test-Path -LiteralPath $spiceExe -PathType Leaf)){
    throw 'R140_BASELINE_ARTIFACT_MISSING'
  }

  $stateSha=Get-ExactSha256 -Path $state
  $ledgerSha=Get-ExactSha256 -Path $ledger
  $claimSha=Get-ExactSha256 -Path $claim
  $spiceSha=Get-ExactSha256 -Path $spiceExe

  $candidate=Get-CandidateBytes
  if($candidate.Length -ne $newSize -or (Get-BytesSha256 -Bytes $candidate) -cne $newSha){
    throw 'R140_CANDIDATE_PIN_MISMATCH'
  }
  $text=([Text.Encoding]::UTF8.GetString($candidate)).TrimStart([char]0xFEFF)
  $tok=$null;$err=$null
  [void][Management.Automation.Language.Parser]::ParseInput($text,[ref]$tok,[ref]$err)
  if(@($err).Count -ne 0 -or
     $text -notmatch "Invoke-SpiceCapture -Arguments @\('backup','apply','--no-restart'\)"){
    throw 'R140_CANDIDATE_PARSE_OR_FIX_MISSING'
  }
  [void]$out.Add('R140_CANDIDATE=SHA256_PARSE_FIX_PASS')

  if($Mode -ceq 'Plan'){
    [void]$out.Add('FILE_WRITE=NO')
    [void]$out.Add('RESULT=R140_HOTFIX_READY_NO_OPERATING_WRITE')
    return
  }
  if($ApprovalPhrase -cne $approval){throw 'R140_EXPLICIT_APPROVAL_REQUIRED'}

  $maintenance=Enter-Lock -Purpose Maintenance
  if($null -eq $maintenance){throw 'R140_MAINTENANCE_MUTEX_BUSY'}
  $agent=Enter-Lock -Purpose AgentTick
  if($null -eq $agent){throw 'R140_AGENT_MUTEX_BUSY'}

  if((Get-ExactSha256 -Path $main) -cne $oldSha){throw 'R140_MAIN_CHANGED_UNDER_MUTEX'}
  if((Get-ExactSha256 -Path $state) -cne $stateSha -or
     (Get-ExactSha256 -Path $ledger) -cne $ledgerSha -or
     (Get-ExactSha256 -Path $claim) -cne $claimSha -or
     (Get-ExactSha256 -Path $spiceExe) -cne $spiceSha){
    throw 'R140_BASELINE_CHANGED_UNDER_MUTEX'
  }
  if((Test-Path -LiteralPath $backup) -or (Test-Path -LiteralPath $held)){
    throw 'R140_STALE_HOTFIX_ARTIFACT_HOLD'
  }

  $tmp=Join-Path (Split-Path -Parent $main) ('.r140-new-'+[guid]::NewGuid().ToString('N')+'.tmp')
  [IO.File]::WriteAllBytes($tmp,$candidate)
  if((Get-ExactSha256 -Path $tmp) -cne $newSha){throw 'R140_STAGED_HASH_MISMATCH'}
  [IO.File]::Replace($tmp,$main,$backup,$true)

  if((Get-ExactSha256 -Path $main) -cne $newSha -or
     (Get-ExactSha256 -Path $backup) -cne $oldSha){
    throw 'R140_SOURCE_SWAP_READBACK_FAILED'
  }
  if((Get-ExactSha256 -Path $state) -cne $stateSha -or
     (Get-ExactSha256 -Path $ledger) -cne $ledgerSha -or
     (Get-ExactSha256 -Path $claim) -cne $claimSha -or
     (Get-ExactSha256 -Path $spiceExe) -cne $spiceSha){
    throw 'R140_NON_SOURCE_STATE_CHANGED'
  }

  [void]$out.Add('R140_MAIN=INSTALLED_PIN_VERIFIED')
  [void]$out.Add('R139_PREVIOUS_SOURCE=SHA256_VERIFIED')
  [void]$out.Add('R139_STATE_LEDGER_CLAIM_SPICETIFY=UNCHANGED')
  [void]$out.Add('RESULT=R140_NO_RESTART_HOTFIX_COMMITTED')
} catch {
  $reason=[string]$_.Exception.Message
  if($Mode -ceq 'Once' -and
     (Test-Path -LiteralPath $backup -PathType Leaf) -and
     (Get-ExactSha256 -Path $main) -eq $newSha){
    try{
      if(Test-Path -LiteralPath $held){throw 'R140_FAILED_NEW_HOLD_COLLISION'}
      [IO.File]::Replace($backup,$main,$held,$true)
      if((Get-ExactSha256 -Path $main) -eq $oldSha -and
         (Get-ExactSha256 -Path $held) -eq $newSha){
        [void]$out.Add('ROLLBACK_SOURCE=R139_RESTORED_SHA_VERIFIED')
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
} finally {
  Exit-Lock -Mutex $agent
  Exit-Lock -Mutex $maintenance
  $receipt=$out.ToArray() -join [Environment]::NewLine
  try { Set-Clipboard -Value $receipt } catch {}
  Write-Output $receipt
}
