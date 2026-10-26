param(
    [Parameter(Mandatory=$true)][string]$Fixture
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'

$fixtureRoot=(Resolve-Path -LiteralPath $Fixture).Path
$root=Join-Path $fixtureRoot 'LocalAppData\SpotifyControl'
$bin=Join-Path $root 'bin'
$bootExact=Join-Path $root 'bootstrap\spotify-control-self-updater.ps1'
$bootRun=Join-Path $root 'bootstrap\spotify-control-self-updater-ci-local-manifest.ps1'
$manifestDir=Join-Path $fixtureRoot 'ci-manifest'
$manifestPath=Join-Path $manifestDir 'manifest.json'
$main=Join-Path $bin 'spotify-control.ps1'
$addon=Join-Path $bin 'addon-manager.ps1'
$agentPath=Join-Path $bin 'spotify-control-agent.vbs'

$StartVersion='0.6.20'
$TargetVersion='0.6.21'
$StartMain='e9f0181756cfb84c505c30f54b6067e321f6d178d3a1936489714b8f4441ba18'
$StartAddon='3a20fcd552b363ebc05e26854a8fe010ffe50e5c756ebd3d7fca54011e8a8b86'
$TargetMain='f97c78c905b83e90e58a24035febcaccc27cb12113ae9cbc64acdc79f5853828'
$TargetAddon='7991b8eaa5a943957aebb9d3dd84d455ed6266430da442a672c05c145fe497a2'
$Agent='2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278'
$Bootstrap='d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6'
$SourceCommit='9a90d5f13eb63023d8f965a004be14d309d99429'
$PayloadSet='7bd1bd7559eee615f4e0aa049b3ec1574f6b215dbdf7417a0a57ea99b20b6c55'
$MainManifestUrl='https://raw.githubusercontent.com/sdsssdvx2/spotify-control-updates/main/manifest.json'
$LocalManifestUrl='http://127.0.0.1:8765/manifest.json'

function Assert-Identity([string]$Path,[string]$Sha,[int64]$Size,[string]$Label){
    if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){throw "$Label missing: $Path"}
    $item=Get-Item -LiteralPath $Path
    $hash=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if([int64]$item.Length -ne $Size -or $hash -cne $Sha){throw "$Label identity mismatch: size=$($item.Length) sha=$hash"}
}

Assert-Identity $bootExact $Bootstrap 42963 'Bootstrap 1.0.6'
if(-not (Test-Path -LiteralPath $bootRun -PathType Leaf)){throw 'CI manifest-injected Bootstrap execution copy is missing.'}
if(-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)){throw 'CI local manifest is missing.'}
$exactText=Get-Content -LiteralPath $bootExact -Raw
$runText=Get-Content -LiteralPath $bootRun -Raw
if(([regex]::Matches($exactText,[regex]::Escape($MainManifestUrl))).Count -ne 1 -or $exactText.Contains($LocalManifestUrl)){throw 'Exact Bootstrap manifest URL contract changed.'}
if(([regex]::Matches($runText,[regex]::Escape($LocalManifestUrl))).Count -ne 1 -or $runText.Contains($MainManifestUrl)){throw 'CI Bootstrap copy does not contain exactly the localhost manifest URL substitution.'}
if($runText.Replace($LocalManifestUrl,$MainManifestUrl) -cne $exactText){throw 'CI Bootstrap copy differs from released Bootstrap by more than manifest URL.'}
$runSha=(Get-FileHash -LiteralPath $bootRun -Algorithm SHA256).Hash.ToLowerInvariant()
$runSize=[int64](Get-Item -LiteralPath $bootRun).Length

$ciManifest=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json
if($ciManifest.latest_version -ne $TargetVersion -or $ciManifest.source_commit -ne $SourceCommit -or $ciManifest.payload_set_sha256 -ne $PayloadSet){throw 'CI manifest release payload fields changed.'}
if($ciManifest.bootstrap.version -ne '1.0.6' -or $ciManifest.bootstrap.sha256 -ne $runSha -or [int64]$ciManifest.bootstrap.size -ne $runSize){throw 'CI manifest does not pin the manifest-URL-only Bootstrap execution copy.'}
$edge=@($ciManifest.updates|Where-Object{$_.from_version -eq $StartVersion -and $_.to_version -eq $TargetVersion})
if($edge.Count -ne 1 -or @($edge[0].patches).Count -ne 2){throw 'CI manifest exact v0.6.20 -> v0.6.21 edge missing or ambiguous.'}
Assert-Identity $main $StartMain 281585 'Start v0.6.20 main'
Assert-Identity $addon $StartAddon 225044 'Start Addon Manager r9'
Assert-Identity $agentPath $Agent 4855 'Resident agent'

$env:LOCALAPPDATA=Join-Path $fixtureRoot 'LocalAppData'
$env:APPDATA=Join-Path $fixtureRoot 'Roaming'
New-Item -ItemType Directory -Force -Path $env:APPDATA|Out-Null

function Run-Boot([string]$Action){
    Assert-Identity $bootExact $Bootstrap 42963 'Installed exact Bootstrap before action'
    $out=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $bootRun -Action $Action -Json 2>&1
    $code=$LASTEXITCODE
    Write-Host ("BOOTSTRAP_V0621_"+$Action+"_EXIT="+$code)
    $out|ForEach-Object{Write-Host $_}
    if($code -ne 0){throw "Bootstrap $Action failed with exit $code"}
    $last=@($out|Where-Object{[string]$_ -match '^\s*\{'})|Select-Object -Last 1
    if(-not $last){throw "Bootstrap $Action emitted no JSON result"}
    return ($last|ConvertFrom-Json)
}

function Assert-UpdatedCandidate {
    Assert-Identity $main $TargetMain 281579 'Updated v0.6.21 main'
    Assert-Identity $addon $TargetAddon 250616 'Updated Addon Manager r10'
    Assert-Identity $agentPath $Agent 4855 'Updated resident agent'
    Assert-Identity $bootExact $Bootstrap 42963 'Updated exact Bootstrap'

    foreach($file in @($main,$addon)){
        $tokens=$null;$errors=$null
        [System.Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)|Out-Null
        if($errors.Count){$errors|ForEach-Object{Write-Error $_.Message};throw "Updated candidate failed PowerShell 5.1 parse: $file"}
    }
    $mainText=Get-Content -LiteralPath $main -Raw
    $addonText=Get-Content -LiteralPath $addon -Raw
    if($mainText.IndexOf('$ScriptVersion = "0.6.21"',[StringComparison]::Ordinal) -lt 0){throw 'Updated main v0.6.21 version marker missing.'}
    if($addonText.IndexOf('$Version = "0.6.5-r10"',[StringComparison]::Ordinal) -lt 0){throw 'Updated Addon Manager r10 version marker missing.'}
    foreach($required in @("data_policy='protect-ratings-tags-notes'","data_policy='never-disable-or-optimize'",'Assert-AddonTransactionRegistryAuthorization -Tx $tx')){
        if($addonText.IndexOf($required,[StringComparison]::Ordinal) -lt 0){throw "Updated r10 registry contract missing: $required"}
    }

    $mainSelf=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $main -Action SelfTest 2>&1
    $mainSelfCode=$LASTEXITCODE;$mainSelf|ForEach-Object{Write-Host $_}
    if($mainSelfCode -ne 0){throw 'Updated v0.6.21 main SelfTest failed.'}
    $addonSelf=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $addon -Action SelfTest 2>&1
    $addonSelfCode=$LASTEXITCODE;$addonSelf|ForEach-Object{Write-Host $_}
    if($addonSelfCode -ne 0){throw 'Updated Addon Manager r10 SelfTest failed.'}
}

$python=(Get-Command python -ErrorAction Stop).Source
$server=$null
try {
    $server=Start-Process -FilePath $python -ArgumentList @('-m','http.server','8765','--bind','127.0.0.1','--directory',$manifestDir) -WindowStyle Hidden -PassThru
    $ready=$false
    for($i=0;$i -lt 40;$i++){
        try{$probe=Invoke-RestMethod -Uri $LocalManifestUrl -TimeoutSec 2;if($probe.latest_version -eq $TargetVersion){$ready=$true;break}}catch{}
        Start-Sleep -Milliseconds 250
    }
    if(-not $ready){throw 'Local CI manifest server did not become ready.'}

    $check=Run-Boot 'Check'
    if(-not $check.success -or [string]$check.installed_version -ne $StartVersion){throw 'Check did not detect exact installed v0.6.20.'}
    if([int]$check.result.edge_count -ne 1){throw "Expected one update edge, got $($check.result.edge_count)"}
    if([string]$check.manifest_url -ne $LocalManifestUrl){throw "Pre-merge Check did not use localhost CI manifest: $($check.manifest_url)"}

    $rb=Run-Boot 'RollbackTest'
    if(-not $rb.success -or [string]$rb.transaction_status -ne 'rolled-back'){throw 'RollbackTest did not finish rolled-back.'}
    Assert-Identity $main $StartMain 281585 'Rollback v0.6.20 main'
    Assert-Identity $addon $StartAddon 225044 'Rollback Addon Manager r9'
    Assert-Identity $agentPath $Agent 4855 'Rollback resident agent'
    Assert-Identity $bootExact $Bootstrap 42963 'Rollback exact Bootstrap'

    $up=Run-Boot 'Update'
    if(-not $up.success -or [string]$up.transaction_status -ne 'committed'){throw 'Update did not commit v0.6.21.'}
    Assert-UpdatedCandidate

    $post=Run-Boot 'Check'
    if(-not $post.success -or [string]$post.installed_version -ne $TargetVersion){throw 'Post-update Check did not detect v0.6.21.'}
    if($post.result.already_current -ne $true -or [int]$post.result.edge_count -ne 0){throw 'Post-update Check is not already-current with zero edges.'}
    Assert-Identity $bootExact $Bootstrap 42963 'Final exact Bootstrap'
    Write-Host 'BOOTSTRAP_V106_LOCAL_MANIFEST_TRUST_PIN_ONLY_V0620_TO_V0621_E2E_PASS edges=1'
} finally {
    if($server -and -not $server.HasExited){Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue;try{$server.WaitForExit(5000)|Out-Null}catch{}}
}
