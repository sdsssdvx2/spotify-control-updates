# Actual existing Bootstrap 1.0.6 -> 0.6.28 to 0.6.29
# one-main-file forward upgrade, rollback rehearsal, commit and post-check.
# 100% hosted runner disposable fixture; no installed user app.
param([Parameter(Mandatory=$true)][string]$SourceCommit)
Set-StrictMode -Version 2.0
$ErrorActionPreference="Stop"
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
    throw 'BOOTSTRAP_V0629_INTEGRATION_REQUIRES_PRIVATE_HOSTED_WINDOWS'
}
if($SourceCommit -cnotmatch '^[0-9a-f]{40}$'){throw 'UNPINNED_PACKAGE_SOURCE_COMMIT'}
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$origin=(git -C $repo rev-parse origin/main).Trim()
if($origin -cne 'd38e88d9ae99f6a4983e2ad64f74f6fce7e6cde2'){
    throw 'CURRENT_OPERATING_MAIN_NOT_EXPECTED'
}
$metadata=Get-Content (Join-Path $PSScriptRoot 'out/bootstrappable-preview-metadata.json') -Raw | ConvertFrom-Json
$preview=Get-Content (Join-Path $PSScriptRoot 'out/preview/manifest.json') -Raw | ConvertFrom-Json
if($preview.latest_version -cne '0.6.29' -or $preview.source_commit -cne $SourceCommit -or
   [int]@($preview.updates[-1].patches).Count -ne 1 -or
   [string]$preview.updates[-1].patches[0].path -cne 'bin/spotify-control.ps1'){
    throw 'SINGLE_PATCH_PREVIEW_MANIFEST_INVALID'
}
$targetMain=Join-Path $PSScriptRoot 'out/bin/spotify-control.ps1'
$sourceMain=Join-Path $repo 'validation/v0.6.28/out/bin/spotify-control.ps1'
$addon=Join-Path $repo 'validation/v0.6.28/out/bin/addon-manager.ps1'
$targetHash=(Get-FileHash -LiteralPath $targetMain -Algorithm SHA256).Hash.ToLowerInvariant()
if($targetHash -cne [string]$metadata.new_main_sha256){throw 'CANDIDATE_BYTES_UNTRUSTED'}
# Use exact already-qualified Bootstrap fixture preparation, not a new
# simulated updater or a patched copy of any user's application.
Push-Location $repo
try {
    python validation/bootstrap-contract-repair/build_bootstrap_fixture.py
    if($LASTEXITCODE -ne 0){throw 'ORIGINAL_BOOTSTRAP_FIXTURE_UNAVAILABLE'}
} finally {Pop-Location}
$fixture=Join-Path $repo 'ci-bootstrap-fixture'
$private=Join-Path $env:RUNNER_TEMP ('spotify-control-v0629-e2e-'+[Guid]::NewGuid().ToString('N'))
$root=Join-Path $private 'LocalAppData/SpotifyControl'
$manifestDir=Join-Path $private 'ci-manifest'
$server=$null
$originalLocal=$env:LOCALAPPDATA
$originalRoaming=$env:APPDATA
$originalProfile=$env:USERPROFILE
try {
    if(-not $private.StartsWith(([IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\\')+'\\'),[StringComparison]::OrdinalIgnoreCase)){
        throw 'E2E_PRIVATE_PATH_NOT_BENEATH_RUNNER_TEMP'
    }
    [IO.Directory]::CreateDirectory($private)|Out-Null
    Copy-Item -LiteralPath $fixture -Destination $private -Recurse -Force
    # Copy-Item of fixture directory into existing private yields child fixture.
    $copied=Join-Path $private 'ci-bootstrap-fixture'
    if(-not [IO.Directory]::Exists($copied)){throw 'BOOTSTRAP_FIXTURE_COPY_MISSING'}
    $root=Join-Path $copied 'LocalAppData/SpotifyControl'
    $manifestDir=Join-Path $copied 'ci-manifest'
    $bin=Join-Path $root 'bin'
    $installedMain=Join-Path $bin 'spotify-control.ps1'
    $installedAddon=Join-Path $bin 'addon-manager.ps1'
    $installedAgent=Join-Path $bin 'spotify-control-agent.vbs'
    [IO.File]::Copy($sourceMain,$installedMain,$true)
    [IO.File]::Copy($addon,$installedAddon,$true)
    function Assert-SHA([string]$P,[string]$Expected) {
        if(-not [IO.File]::Exists($P) -or (Get-FileHash -LiteralPath $P -Algorithm SHA256).Hash.ToLowerInvariant() -cne $Expected){
            throw 'EXACT_STAGED_FILE_SHA_MISMATCH'
        }
    }
    Assert-SHA $installedMain 'af1582ec335807f8f5daa9b3a65b13d567264f326d3c608c082ae02ff0a4cfc0'
    Assert-SHA $installedAddon '5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285'
    Assert-SHA $installedAgent '2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278'
    $exactBootstrap=Join-Path $root 'bootstrap/spotify-control-self-updater.ps1'
    Assert-SHA $exactBootstrap 'd9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6'
    $original=[IO.File]::ReadAllBytes($exactBootstrap)
    $mainUrl='https://raw.githubusercontent.com/sdsssdvx2/spotify-control-updates/main/manifest.json'
    $localUrl='http://127.0.0.1:8765/manifest.json'
    $content=[Text.Encoding]::UTF8.GetString($original)
    if($content.Split(@($mainUrl),[StringSplitOptions]::None).Count -ne 2){
        throw 'BOOTSTRAP_MANIFEST_URL_ANCHOR_DRIFT'
    }
    $replaced=$content.Replace($mainUrl,$localUrl)
    $inject=Join-Path $root 'bootstrap/spotify-control-self-updater-ci-local-manifest.ps1'
    $injected=[Text.Encoding]::UTF8.GetBytes($replaced)
    [IO.File]::WriteAllBytes($inject,$injected)
    $check=([Text.Encoding]::UTF8.GetString($injected)).Replace($localUrl,$mainUrl)
    if($check -cne $content){throw 'BOOTSTRAP_COPY_CHANGED_BEYOND_LOCAL_URL'}
    $ciManifest=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'out/preview/manifest.json') -Raw | ConvertFrom-Json
    $ciManifest.bootstrap.sha256=([Security.Cryptography.SHA256]::Create().ComputeHash($injected)|ForEach-Object ToString x2) -join ''
    $ciManifest.bootstrap.size=$injected.Length
    [IO.Directory]::CreateDirectory($manifestDir)|Out-Null
    $ciManifest|ConvertTo-Json -Depth 100 -Compress|Set-Content -LiteralPath (Join-Path $manifestDir 'manifest.json') -Encoding UTF8
    $env:LOCALAPPDATA=Join-Path $copied 'LocalAppData'
    $env:APPDATA=Join-Path $copied 'Roaming'
    [IO.Directory]::CreateDirectory($env:APPDATA)|Out-Null
    foreach($name in @('update-state.json','update-transaction.json','rollback-state.json')){
        $p=Join-Path $root $name
        if(Test-Path -LiteralPath $p){Remove-Item -LiteralPath $p -Force}
    }
    $python=(Get-Command python.exe -ErrorAction Stop).Source
    $server=Start-Process -FilePath $python -ArgumentList @('-m','http.server','8765','--bind','127.0.0.1','--directory',$manifestDir) -WindowStyle Hidden -PassThru
    $ready=$false
    for($i=0;$i -lt 40;$i++){
        try{
            $probe=Invoke-RestMethod -Uri $localUrl -TimeoutSec 2
            if($probe.latest_version -ceq '0.6.29'){$ready=$true;break}
        }catch{}
        Start-Sleep -Milliseconds 250
    }
    if(-not $ready){throw 'LOCAL_PREVIEW_MANIFEST_SERVER_DID_NOT_START'}
    function Run-Boot([string]$Action){
        $rows=@(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $inject -Action $Action -Json 2>&1)
        $rc=$LASTEXITCODE
        if($rc -ne 0){
            $msg=($rows|Select-Object -Last 6|Out-String)
            throw ('ORIGINAL_BOOTSTRAP_'+$Action+'_FAILED='+$rc+' '+$msg)
        }
        $json=@($rows|Where-Object{[string]$_ -match '^\s*\{' }|Select-Object -Last 1)
        if($json.Count -ne 1){throw 'BOOTSTRAP_NO_JSON_RESULT'}
        return ($json[0]|ConvertFrom-Json)
    }
    $pre=Run-Boot 'Check'
    if(-not [bool]$pre.success -or [string]$pre.installed_version -cne '0.6.28' -or
       [int]$pre.result.edge_count -ne 1){throw 'REAL_BOOTSTRAP_DID_NOT_RECOGNIZE_ONE_FORWARD_EDGE'}
    $rollback=Run-Boot 'RollbackTest'
    if(-not [bool]$rollback.success -or [string]$rollback.transaction_status -cne 'rolled-back'){
        throw 'REAL_BOOTSTRAP_ROLLBACK_TEST_FAILED'
    }
    Assert-SHA $installedMain 'af1582ec335807f8f5daa9b3a65b13d567264f326d3c608c082ae02ff0a4cfc0'
    Assert-SHA $installedAddon '5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285'
    $updated=Run-Boot 'Update'
    if(-not [bool]$updated.success -or [string]$updated.transaction_status -cne 'committed'){
        throw 'REAL_BOOTSTRAP_FORWARD_UPDATE_FAILED'
    }
    Assert-SHA $installedMain ([string]$metadata.new_main_sha256)
    Assert-SHA $installedAddon '5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285'
    Assert-SHA $installedAgent '2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278'
    Assert-SHA $exactBootstrap 'd9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6'
    $post=Run-Boot 'Check'
    if(-not [bool]$post.success -or [string]$post.installed_version -cne '0.6.29' -or
       [bool]$post.result.already_current -ne $true){throw 'BOOTSTRAP_POST_CHECK_NOT_CURRENT'}
    $mainText=[IO.File]::ReadAllText($installedMain)
    if($mainText.IndexOf('$ScriptVersion = "0.6.29"',[StringComparison]::Ordinal) -lt 0){
        throw 'UPGRADED_MAIN_INTERNAL_VERSION_MISSING'
    }
    Write-Host 'BOOTSTRAP_V106_SINGLE_FILE_0628_TO_0629_CHECK_ROLLBACK_COMMIT_POSTCHECK_PASS'
    Write-Host 'BOOTSTRAP_V106_R17_AGENT_PRIVATE_FIXTURE_PROTECTED_PASS'
    Write-Host 'BOOTSTRAP_V106_USER_SPOTIFY_NOT_ACCESSED_HOLD'
} finally {
    $env:LOCALAPPDATA=$originalLocal
    $env:APPDATA=$originalRoaming
    $env:USERPROFILE=$originalProfile
    if($null -ne $server -and -not $server.HasExited){
        Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue
        try{$server.WaitForExit(5000)|Out-Null}catch{}
    }
    if([IO.Directory]::Exists($private)){Remove-Item -LiteralPath $private -Recurse -Force -ErrorAction SilentlyContinue}
    if([IO.Directory]::Exists($fixture)){Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue}
}
