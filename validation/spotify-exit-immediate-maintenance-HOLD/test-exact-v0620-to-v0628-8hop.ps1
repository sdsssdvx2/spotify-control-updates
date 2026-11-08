# Host-only exact user's stable v0.6.20/r9 => v0.6.28/r17 full-chain.
# No user PC Spotify, settings, tasks, or data; no production release.
param([Parameter(Mandatory=$true)][string]$Fixture)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){throw 'HOSTED_FIXTURE_ONLY'}
$fixturePath=(Resolve-Path -LiteralPath $Fixture).Path
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
if(-not $fixturePath.StartsWith(($repo.TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)){
    throw 'EXACT_USER_BASELINE_FIXTURE_OUTSIDE_CHECKED_OUT_REPOSITORY'
}
$root=Join-Path $fixturePath 'LocalAppData\SpotifyControl'
$bin=Join-Path $root 'bin'
$main=Join-Path $bin 'spotify-control.ps1'
$addon=Join-Path $bin 'addon-manager.ps1'
$agent=Join-Path $bin 'spotify-control-agent.vbs'
$bootstrap=Join-Path $root 'bootstrap\spotify-control-self-updater.ps1'
$ciBootstrap=Join-Path $root 'bootstrap\spotify-control-self-updater-ci-local-manifest.ps1'
$mainBefore='e9f0181756cfb84c505c30f54b6067e321f6d178d3a1936489714b8f4441ba18'
$addonBefore='3a20fcd552b363ebc05e26854a8fe010ffe50e5c756ebd3d7fca54011e8a8b86'
$mainAfter='af1582ec335807f8f5daa9b3a65b13d567264f326d3c608c082ae02ff0a4cfc0'
$addonAfter='5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285'
$agentHash='2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278'
$bootHash='d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6'
$localManifest='http://127.0.0.1:8765/manifest.json'
function AssertHash([string]$Path,[string]$Expected,[string]$Name){
  if(-not [IO.File]::Exists($Path)){throw ('EXPECTED_FILE_ABSENT_'+$Name)}
  $actual=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
  if($actual -cne $Expected){throw ('FILE_SHA_MISMATCH_'+$Name)}
}
AssertHash $main $mainBefore 'BASE_MAIN_V0620'
AssertHash $addon $addonBefore 'BASE_ADDON_R9'
AssertHash $agent $agentHash 'BASE_RESIDENT_VBS'
AssertHash $bootstrap $bootHash 'BOOTSTRAP_V106'
$preview=Get-Content -LiteralPath (Join-Path $fixturePath 'ci-manifest\manifest.json') -Raw | ConvertFrom-Json
if($preview.latest_version -cne '0.6.28' -or
   $preview.source_commit -cne 'bb6d90146f20b73d36fbf8cb813f1b190f403c48' -or
   $preview.payload_set_sha256 -cne '4be96c5d41c2160ed9ac96001b469998595629232929b82c8b0f34b11fda3b43'){
   throw 'CURRENT_OFFICIAL_MANIFEST_CHANGED'
}
$ciHash=(Get-FileHash -LiteralPath $ciBootstrap -Algorithm SHA256).Hash.ToLowerInvariant()
if($ciHash -cne [string]$preview.bootstrap.sha256){throw 'CI_BOOTSTRAP_SELF_SHA_INVALID'}
$oldLocal=$env:LOCALAPPDATA
$oldApp=$env:APPDATA
$env:LOCALAPPDATA=Join-Path $fixturePath 'LocalAppData'
$env:APPDATA=Join-Path $fixturePath 'Roaming'
[void][IO.Directory]::CreateDirectory($env:APPDATA)
$server=$null
$python=(Get-Command python.exe -ErrorAction Stop).Source
function RunBoot([string]$Action){
    AssertHash $bootstrap $bootHash 'EXACT_BOOTSTRAP_BEFORE_ACTION'
    $lines=@(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $ciBootstrap -Action $Action -Json 2>&1)
    $rc=$LASTEXITCODE
    $json=@($lines|Where-Object{[string]$_ -match '^\s*\{' }|Select-Object -Last 1)
    if($rc -ne 0 -or $json.Count -ne 1){
       # CI fixture-only diagnostics, never real usernames or paths.
       $codes=@($lines|ForEach-Object{[string]$_}|Where-Object{$_ -match '(?i)(error|fail|edge|status|result)' }|Select-Object -Last 8)
       Write-Host ('EIGHT_EDGE_BOOTSTRAP_ACTION_FAILED='+$Action+';EXIT='+$rc+';OUTPUT_ITEMS='+$lines.Count)
       foreach($str in $codes){Write-Host ('HOSTED_DIAGNOSTIC='+$str)}
       throw ('EXACT_BOOTSTRAP_'+$Action+'_FAILED')
    }
    $doc=$json[0]|ConvertFrom-Json
    if($doc.success -ne $true){throw ('BOOTSTRAP_'+$Action+'_SUCCESS_NOT_TRUE')}
    Write-Host ('EXACT_BOOTSTRAP_'+$Action+'_SUCCESS=TRUE')
    return $doc
}
try{
    $server=Start-Process -FilePath $python -ArgumentList @('-m','http.server','8765','--bind','127.0.0.1','--directory',(Join-Path $fixturePath 'ci-manifest')) -WindowStyle Hidden -PassThru
    $ready=$false
    for($i=0;$i -lt 60;$i++){
       try{
          $res=Invoke-RestMethod -Uri $localManifest -TimeoutSec 2
          if($res.latest_version -ceq '0.6.28'){$ready=$true;break}
       }catch{}
       Start-Sleep -Milliseconds 250
    }
    if(-not $ready){throw 'CI_LOOPBACK_STABLE_MANIFEST_NOT_READY'}
    $check=RunBoot 'Check'
    if([string]$check.installed_version -cne '0.6.20' -or
       [string]$check.manifest_url -cne $localManifest -or
       [int]$check.result.edge_count -ne 8){
       throw 'ACTUAL_USER_VERSION_EIGHT_EDGE_CHECK_NOT_PLANNED'
    }
    Write-Host 'EXACT_V0620_TO_V0628_EIGHT_EDGE_CHECK_PASS'
    $rehearsal=RunBoot 'RollbackTest'
    if([string]$rehearsal.transaction_status -cne 'rolled-back'){
      throw 'ACTUAL_USER_BASELINE_EIGHT_EDGE_REHEARSAL_NOT_ROLLED_BACK'
    }
    AssertHash $main $mainBefore 'ROLLBACK_MAIN_V0620'
    AssertHash $addon $addonBefore 'ROLLBACK_ADDON_R9'
    AssertHash $agent $agentHash 'ROLLBACK_VBS'
    AssertHash $bootstrap $bootHash 'ROLLBACK_BOOTSTRAP'
    Write-Host 'EXACT_V0620_TO_V0628_EIGHT_EDGE_ROLLBACK_PASS'
    $commit=RunBoot 'Update'
    if([string]$commit.transaction_status -cne 'committed'){
       throw 'ACTUAL_USER_BASELINE_EIGHT_EDGE_UPDATE_NOT_COMMITTED'
    }
    AssertHash $main $mainAfter 'COMMITTED_MAIN_V0628'
    AssertHash $addon $addonAfter 'COMMITTED_ADDON_R17'
    AssertHash $agent $agentHash 'COMMITTED_VBS'
    AssertHash $bootstrap $bootHash 'COMMITTED_BOOTSTRAP'
    $post=RunBoot 'Check'
    if([string]$post.installed_version -cne '0.6.28' -or
       [bool]$post.result.already_current -ne $true -or
       [int]$post.result.edge_count -ne 0){
       throw 'EIGHT_EDGE_POSTCHECK_NOT_CURRENT'
    }
    Write-Host 'USER_EXACT_V0620_R9_TO_STABLE_V0628_R17_REAL_BOOTSTRAP_FULL_CHAIN_PASS'
    Write-Host 'USER_PC_OPERATING_CONFIG_SETTINGS_SPOTIFY_NOT_TOUCHED=YES'
}finally{
    $env:LOCALAPPDATA=$oldLocal
    $env:APPDATA=$oldApp
    if($null -ne $server -and -not $server.HasExited){
       Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue
       try{$server.WaitForExit(5000)|Out-Null}catch{}
    }
}
