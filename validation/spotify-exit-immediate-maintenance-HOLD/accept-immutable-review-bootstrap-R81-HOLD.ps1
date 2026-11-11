# R81: native Windows real Bootstrap 1.0.6 full-file Check->Update->Check
# for the FUNCTIONALLY INTEGRATED R37/R38 v0.6.30 payload. Hosted scratch only.
# No owner PC, actual Spotify, Git push or release.
[CmdletBinding()]
param()
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -cne 'true' -or
   $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
  throw 'R81_NATIVE_HOSTED_WINDOWS_ONLY'
}
$repositoryRoot=(Get-Location).Path
$fixture=Join-Path $env:RUNNER_TEMP 'spotify-future-bootstrap-rehearsal'
$script=(Resolve-Path 'validation/spotify-exit-immediate-maintenance-HOLD/rehearse-localhost-bootstrap-future.py').Path
$bootstrapInput=Join-Path $env:RUNNER_TEMP 'spotify-verified-bootstrap-v106.ps1'
$sourceCombined=Join-Path $env:RUNNER_TEMP 'spotify-r81-immutable-github-review-stage'
$expectedMain='b2b2fbf1afb60b58d501312160f7e2437c2452e90cb61ca8c2be0d877f92232d'
$expectedAgent='e56609ed8927512595f55c01ea50dbb9c8c59e4a2c86dcb3d16195a565c604d5'
$expectedAddon='5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285'
$server=$null
$beforeLocal=$env:LOCALAPPDATA
$beforeRoaming=$env:APPDATA
function Hash([string]$p){
  return (Get-FileHash -LiteralPath $p -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}
function Official([string]$p,[string]$act){
  $lines=@(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $p -Action $act -Json 2>&1)
  if($LASTEXITCODE -ne 0 -or $lines.Count -eq 0){
    throw ('R81_OFFICIAL_BOOTSTRAP_'+$act+'_FAILED')
  }
  try{$r=$lines[-1]|ConvertFrom-Json -ErrorAction Stop}
  catch{throw ('R81_OFFICIAL_BOOTSTRAP_'+$act+'_INVALID_JSON')}
  if($r.success -ne $true -or [string]$r.action -cne $act){
    throw ('R81_OFFICIAL_BOOTSTRAP_'+$act+'_NOT_SUCCESS')
  }
  return $r
}
try {
  if(Test-Path -LiteralPath $fixture){throw 'R81_SCRATCH_ALREADY_EXISTS'}
  if(-not(Test-Path -LiteralPath $bootstrapInput -PathType Leaf) -or
     (Hash $bootstrapInput) -cne 'd9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6'){
    throw 'R81_PINNED_ORIGINAL_BOOTSTRAP_NOT_PRESENT'
  }
  $combined=(Resolve-Path $sourceCombined).Path
  if((Hash (Join-Path $combined 'bin/spotify-control.ps1')) -cne $expectedMain -or
     (Hash (Join-Path $combined 'bin/spotify-control-agent.vbs')) -cne $expectedAgent -or
     (Hash (Join-Path $combined 'bin/addon-manager.ps1')) -cne $expectedAddon){
    throw 'R81_R38_COMBINED_RELEASE_BYTES_NOT_ACCEPTED'
  }
  $python=(Get-Command python -ErrorAction Stop).Source
  $server=Start-Process -FilePath $python -ArgumentList ('"'+$script+'" serve') -PassThru -WindowStyle Hidden
  $ready=Join-Path $fixture 'server-port'
  for($i=0;$i -lt 100 -and -not(Test-Path -LiteralPath $ready);$i++){
    Start-Sleep -Milliseconds 100
    if($server.HasExited){throw 'R81_FIXED_LOOPBACK_SERVER_EARLY_EXIT'}
  }
  if(-not(Test-Path -LiteralPath $ready)){throw 'R81_LOOPBACK_NOT_READY'}
  # Reuse original R28 localhost mirror and preparation byte-for-byte.
  # Only replace its STAGED read locator in memory to our R38 combined source.
  & $python 'validation/spotify-exit-immediate-maintenance-HOLD/accept-immutable-review-bootstrap-R81-HOLD.py' mirror
  if($LASTEXITCODE -ne 0){throw 'R81_COMBINED_FIXED_LOCALHOST_MIRROR_PREPARE_FAILED'}
  $app=Join-Path $fixture 'LocalAppData/SpotifyControl'
  $boot=Join-Path $app 'bootstrap/spotify-control-self-updater.ps1'
  $expect=Get-Content -LiteralPath (Join-Path $fixture 'rehearsal-report.json') -Raw | ConvertFrom-Json
  $staged=Get-Content -LiteralPath (Join-Path $combined 'stage-receipt.json') -Raw | ConvertFrom-Json
  if([string]$expect.future_main_sha256 -cne $expectedMain -or
     [string]$expect.future_agent_sha256 -cne $expectedAgent -or
     [string]$expect.future_payload_set_sha256 -cne [string]$staged.payload_sha256 -or
     [string]$expect.staged_manifest_sha256 -cne [string]$staged.manifest_sha256 -or
     (Hash $boot) -cne [string]$expect.bootstrap_locator_only_copy_sha256){
    throw 'R81_REAL_BOOTSTRAP_NOT_BOUND_TO_COMBINED_RELEASE'
  }
  $env:LOCALAPPDATA=Join-Path $fixture 'LocalAppData'
  $env:APPDATA=Join-Path $fixture 'Roaming'
  $state=Join-Path $app 'state.json'
  $sentinel=Join-Path $app 'unrelated-user-preserve.txt'
  $stateSha=Hash $state
  $sentinelSha=Hash $sentinel
  $initial=Official $boot 'Check'
  Write-Output 'R81_OFFICIAL_BOOTSTRAP_INITIAL_CHECK=PASS'
  # Real Bootstrap rollback rehearsal before first published release.
  # RollbackTest must restore the original v0.6.28 main and v0.1.1 resident
  # without ever touching the user's production profile.
  $undo=Official $boot 'RollbackTest'
  if((Hash (Join-Path $app 'bin/spotify-control.ps1')) -cne
       'af1582ec335807f8f5daa9b3a65b13d567264f326d3c608c082ae02ff0a4cfc0' -or
     (Hash (Join-Path $app 'bin/spotify-control-agent.vbs')) -cne
       '2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278'){
    throw 'R81_BOOTSTRAP_ROLLBACK_TEST_DID_NOT_RESTORE_STABLE'
  }
  Write-Output 'R81_BOOTSTRAP_REAL_ROLLBACK_TEST_RESTORED_ORIGINALS=PASS'
  $applied=Official $boot 'Update'
  Write-Output 'R81_OFFICIAL_BOOTSTRAP_INTEGRATED_FULL_FILE_UPDATE=PASS'
  $bin=Join-Path $app 'bin'
  if((Hash (Join-Path $bin 'spotify-control.ps1')) -cne $expectedMain -or
     (Hash (Join-Path $bin 'spotify-control-agent.vbs')) -cne $expectedAgent -or
     (Hash (Join-Path $bin 'addon-manager.ps1')) -cne $expectedAddon){
    throw 'R81_OFFICIAL_BOOTSTRAP_UPDATE_NEW_TARGET_BYTES_INVALID'
  }
  $txn=Get-Content -LiteralPath (Join-Path $app 'self-update-last-transaction.json') -Raw|ConvertFrom-Json
  if([string]$txn.status -cne 'committed'){throw 'R81_OFFICIAL_BOOTSTRAP_JOURNAL_NOT_COMMITTED'}
  if((Hash $state) -cne $stateSha -or (Hash $sentinel) -cne $sentinelSha){
    throw 'R81_OWNER_STATE_OR_UNRELATED_SENTINEL_CHANGED'
  }
  $after=Official $boot 'Check'
  Write-Output 'R81_OFFICIAL_BOOTSTRAP_POSTCHECK=PASS'
  Write-Output 'R81_EXACT_REMOTE_REVIEW_TWO_FILES_REAL_BOOTSTRAP_COMMITTED=PASS'
  Write-Output 'R81_HOSTED_USER_STATE_AND_ADDON_R17_EXACT_PRESERVE=PASS'
  Write-Output 'R81_UNPUBLISHED_HOSTED_ONLY_NO_USER_PC_OR_RELEASE=YES'
} finally {
  $env:LOCALAPPDATA=$beforeLocal
  $env:APPDATA=$beforeRoaming
  if($null -ne $server){
    try{
      if(-not $server.HasExited){Stop-Process -Id $server.Id -Force -ErrorAction Stop}
      [void]$server.WaitForExit(5000)
    }catch{}
  }
  if(Test-Path -LiteralPath $fixture){
    Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
  }
  if(Test-Path -LiteralPath $bootstrapInput){
    Remove-Item -LiteralPath $bootstrapInput -Force -ErrorAction SilentlyContinue
  }
}
