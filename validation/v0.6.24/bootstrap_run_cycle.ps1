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

$StartVersion='0.6.23';$TargetVersion='0.6.24'
$StartMain='bc9861bdd64ff8af94f68f0f065739f82b235271dcd18ad6325b819205528a08'
$StartAddon='23ad2210aea4352f535d1cf0b3ebb827a82200dcba2b70bf1ebae96499d82687'
$TargetMain='dc5d7ec17f18f7546786c81f3172c08f6fb1692842c2e6c0a69a86171e6b1151'
$TargetAddon='81343687c475f7f48f1311b09c98205a021776f26e8d55082e0ec47f8ebfb470'
$Agent='2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278'
$Bootstrap='d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6'
$SourceCommit='5597598026c788e32645f31232f40f487f10a2f2'
$PayloadSet='07e8519a5e2b0ffd3888e6d9c119e70d5754a7adb81ebdc355ad20ae8260e659'
$MainManifestUrl='https://raw.githubusercontent.com/sdsssdvx2/spotify-control-updates/main/manifest.json'
$LocalManifestUrl='http://127.0.0.1:8765/manifest.json'

function Assert-Identity([string]$Path,[string]$Sha,[int64]$Size,[string]$Label){
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "$Label missing: $Path"}
    $item=Get-Item -LiteralPath $Path;$hash=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if([int64]$item.Length -ne $Size -or $hash -cne $Sha){throw "$Label identity mismatch: size=$($item.Length) sha=$hash"}
}

Assert-Identity $bootExact $Bootstrap 42963 'Bootstrap 1.0.6'
if(-not(Test-Path -LiteralPath $bootRun -PathType Leaf)){throw 'CI manifest-injected Bootstrap execution copy is missing.'}
if(-not(Test-Path -LiteralPath $manifestPath -PathType Leaf)){throw 'CI local manifest is missing.'}
$exactText=Get-Content -LiteralPath $bootExact -Raw;$runText=Get-Content -LiteralPath $bootRun -Raw
if(([regex]::Matches($exactText,[regex]::Escape($MainManifestUrl))).Count -ne 1 -or $exactText.Contains($LocalManifestUrl)){throw 'Exact Bootstrap manifest URL contract changed.'}
if(([regex]::Matches($runText,[regex]::Escape($LocalManifestUrl))).Count -ne 1 -or $runText.Contains($MainManifestUrl)){throw 'CI Bootstrap copy does not contain exactly the localhost manifest URL substitution.'}
if($runText.Replace($LocalManifestUrl,$MainManifestUrl) -cne $exactText){throw 'CI Bootstrap copy differs from released Bootstrap by more than manifest URL.'}
$runSha=(Get-FileHash -LiteralPath $bootRun -Algorithm SHA256).Hash.ToLowerInvariant();$runSize=[int64](Get-Item -LiteralPath $bootRun).Length
$ciManifest=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json
if($ciManifest.latest_version -ne $TargetVersion -or $ciManifest.source_commit -ne $SourceCommit -or $ciManifest.payload_set_sha256 -ne $PayloadSet){throw 'CI manifest release payload fields changed.'}
if($ciManifest.bootstrap.version -ne '1.0.6' -or $ciManifest.bootstrap.sha256 -ne $runSha -or [int64]$ciManifest.bootstrap.size -ne $runSize){throw 'CI manifest does not pin the manifest-URL-only Bootstrap execution copy.'}
$edge=@($ciManifest.updates|Where-Object{$_.from_version -eq $StartVersion -and $_.to_version -eq $TargetVersion})
if($edge.Count -ne 1 -or @($edge[0].patches).Count -ne 2){throw 'CI manifest exact v0.6.23 -> v0.6.24 edge missing or ambiguous.'}
Assert-Identity $main $StartMain 281588 'Start v0.6.23 main';Assert-Identity $addon $StartAddon 272494 'Start Addon Manager r12';Assert-Identity $agentPath $Agent 4855 'Resident agent'

$env:LOCALAPPDATA=Join-Path $fixtureRoot 'LocalAppData';$env:APPDATA=Join-Path $fixtureRoot 'Roaming';New-Item -ItemType Directory -Force -Path $env:APPDATA|Out-Null
function Run-Boot([string]$Action){
    Assert-Identity $bootExact $Bootstrap 42963 'Installed exact Bootstrap before action'
    $out=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $bootRun -Action $Action -Json 2>&1;$code=$LASTEXITCODE
    Write-Host ("BOOTSTRAP_V0624_"+$Action+"_EXIT="+$code);$out|ForEach-Object{Write-Host $_}
    if($code -ne 0){throw "Bootstrap $Action failed with exit $code"}
    $last=@($out|Where-Object{[string]$_ -match '^\s*\{'})|Select-Object -Last 1
    if(-not$last){throw "Bootstrap $Action emitted no JSON result"};return($last|ConvertFrom-Json)
}
function Assert-UpdatedCandidate {
    Assert-Identity $main $TargetMain 284312 'Updated v0.6.24 main';Assert-Identity $addon $TargetAddon 275414 'Updated Addon Manager r13';Assert-Identity $agentPath $Agent 4855 'Updated resident agent';Assert-Identity $bootExact $Bootstrap 42963 'Updated exact Bootstrap'
    foreach($file in @($main,$addon)){$tokens=$null;$errors=$null;[System.Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)|Out-Null;if($errors.Count){$errors|ForEach-Object{Write-Error $_.Message};throw "Updated candidate failed PowerShell 5.1 parse: $file"}}
    $mainText=Get-Content -LiteralPath $main -Raw;$addonText=Get-Content -LiteralPath $addon -Raw
    if($mainText.IndexOf('$ScriptVersion = "0.6.24"',[StringComparison]::Ordinal) -lt 0){throw 'Updated main v0.6.24 version marker missing.'}
    if($addonText.IndexOf('$Version = "0.6.5-r13"',[StringComparison]::Ordinal) -lt 0){throw 'Updated Addon Manager r13 version marker missing.'}
    foreach($required in @('function Test-SpotifyControlZipArchiveSafety','Test-SpotifyControlZipArchiveSafety -ZipPath $zip','function Test-PithayaZipArchiveSafety','Test-PithayaZipArchiveSafety -ZipPath $zip','ivLyrics ZIP entry exceeds the accepted per-entry cap','ivLyrics ZIP contains a symlink entry','never-disable-or-optimize','protect-ratings-tags-notes','preserve-installed-content')){if(($mainText+$addonText).IndexOf($required,[StringComparison]::OrdinalIgnoreCase) -lt 0){throw "Updated r13 archive/protection contract missing: $required"}}
    $registryStart=$addonText.IndexOf('function Get-AddonPolicyRegistry {',[StringComparison]::Ordinal);$registryNext=$addonText.IndexOf("`nfunction ",$registryStart+1,[StringComparison]::Ordinal);$registryBlock=$addonText.Substring($registryStart,$registryNext-$registryStart)
    foreach($name in @('ivLyrics','better-local-files','eternal-jukebox','playlist-maker')){if($registryBlock.IndexOf("name='$name'",[StringComparison]::OrdinalIgnoreCase) -lt 0){throw "Expected automatic-authority registry entry missing: $name"}}
    if($registryBlock.IndexOf("name='sc-cover-ambience.js'",[StringComparison]::OrdinalIgnoreCase) -lt 0 -or $registryBlock.IndexOf("data_policy='never-disable-or-optimize'",[StringComparison]::OrdinalIgnoreCase) -lt 0){throw 'SC Cover Ambience protection drifted.'}
    $mainSelf=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $main -Action SelfTest 2>&1;$mainSelfCode=$LASTEXITCODE;$mainSelf|ForEach-Object{Write-Host $_};if($mainSelfCode -ne 0){throw 'Updated v0.6.24 main SelfTest failed.'}
    $addonSelf=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $addon -Action SelfTest 2>&1;$addonSelfCode=$LASTEXITCODE;$addonSelf|ForEach-Object{Write-Host $_};if($addonSelfCode -ne 0){throw 'Updated Addon Manager r13 SelfTest failed.'}
}

$python=(Get-Command python -ErrorAction Stop).Source;$server=$null
try{
    $server=Start-Process -FilePath $python -ArgumentList @('-m','http.server','8765','--bind','127.0.0.1','--directory',$manifestDir) -WindowStyle Hidden -PassThru
    $ready=$false;for($i=0;$i -lt 40;$i++){try{$probe=Invoke-RestMethod -Uri $LocalManifestUrl -TimeoutSec 2;if($probe.latest_version -eq $TargetVersion){$ready=$true;break}}catch{};Start-Sleep -Milliseconds 250};if(-not$ready){throw 'Local CI manifest server did not become ready.'}
    $check=Run-Boot 'Check';if(-not$check.success -or [string]$check.installed_version -ne $StartVersion){throw 'Check did not detect exact installed v0.6.23.'};if([int]$check.result.edge_count -ne 1){throw "Expected one update edge, got $($check.result.edge_count)"};if([string]$check.manifest_url -ne $LocalManifestUrl){throw "Pre-merge Check did not use localhost CI manifest: $($check.manifest_url)"}
    $rb=Run-Boot 'RollbackTest';if(-not$rb.success -or [string]$rb.transaction_status -ne 'rolled-back'){throw 'RollbackTest did not finish rolled-back.'};Assert-Identity $main $StartMain 281588 'Rollback v0.6.23 main';Assert-Identity $addon $StartAddon 272494 'Rollback Addon Manager r12';Assert-Identity $agentPath $Agent 4855 'Rollback resident agent';Assert-Identity $bootExact $Bootstrap 42963 'Rollback exact Bootstrap'
    $up=Run-Boot 'Update';if(-not$up.success -or [string]$up.transaction_status -ne 'committed'){throw 'Update did not commit v0.6.24.'};Assert-UpdatedCandidate
    $post=Run-Boot 'Check';if(-not$post.success -or [string]$post.installed_version -ne $TargetVersion){throw 'Post-update Check did not detect v0.6.24.'};if($post.result.already_current -ne $true -or [int]$post.result.edge_count -ne 0){throw 'Post-update Check is not already-current with zero edges.'};Assert-Identity $bootExact $Bootstrap 42963 'Final exact Bootstrap'
    Write-Host 'BOOTSTRAP_V106_LOCAL_MANIFEST_TRUST_PIN_ONLY_V0623_TO_V0624_E2E_PASS edges=1'
}finally{if($server -and -not$server.HasExited){Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue;try{$server.WaitForExit(5000)|Out-Null}catch{}}}
