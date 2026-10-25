param(
    [Parameter(Mandatory=$true)][string]$Fixture,
    [Parameter(Mandatory=$true)][ValidateSet('0.6.18','0.6.19')][string]$StartVersion,
    [Parameter(Mandatory=$true)][int]$ExpectedEdges,
    [Parameter(Mandatory=$true)][string]$StartMainSha,
    [Parameter(Mandatory=$true)][int64]$StartMainSize,
    [Parameter(Mandatory=$true)][string]$StartAddonSha,
    [Parameter(Mandatory=$true)][int64]$StartAddonSize
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'

$fixtureRoot=(Resolve-Path -LiteralPath $Fixture).Path
$root=Join-Path $fixtureRoot 'LocalAppData\SpotifyControl'
$bin=Join-Path $root 'bin'
$bootExact=Join-Path $root 'bootstrap\spotify-control-self-updater.ps1'
$bootRun=Join-Path $root 'bootstrap\spotify-control-self-updater-ci-release-manifest.ps1'
$main=Join-Path $bin 'spotify-control.ps1'
$addon=Join-Path $bin 'addon-manager.ps1'
$agentPath=Join-Path $bin 'spotify-control-agent.vbs'
$TargetMain='e9f0181756cfb84c505c30f54b6067e321f6d178d3a1936489714b8f4441ba18'
$TargetAddon='3a20fcd552b363ebc05e26854a8fe010ffe50e5c756ebd3d7fca54011e8a8b86'
$Agent='2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278'
$Bootstrap='d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6'
$MainManifestUrl='https://raw.githubusercontent.com/sdsssdvx2/spotify-control-updates/main/manifest.json'
$ReleaseManifestUrl='https://raw.githubusercontent.com/sdsssdvx2/spotify-control-updates/release/v0.6.20-star-ratings-performance/manifest.json'

function Assert-Identity([string]$Path,[string]$Sha,[int64]$Size,[string]$Label){
    if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){throw "$Label missing: $Path"}
    $item=Get-Item -LiteralPath $Path;$hash=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if([int64]$item.Length -ne $Size -or $hash -ne $Sha){throw "$Label identity mismatch: size=$($item.Length) sha=$hash"}
}

Assert-Identity $bootExact $Bootstrap 42963 'Bootstrap 1.0.6'
if(-not (Test-Path -LiteralPath $bootRun -PathType Leaf)){throw 'CI manifest-injected Bootstrap execution copy is missing.'}
$exactText=Get-Content -LiteralPath $bootExact -Raw
$runText=Get-Content -LiteralPath $bootRun -Raw
if(([regex]::Matches($exactText,[regex]::Escape($MainManifestUrl))).Count -ne 1 -or $exactText.Contains($ReleaseManifestUrl)){throw 'Exact Bootstrap manifest URL contract changed.'}
if(([regex]::Matches($runText,[regex]::Escape($ReleaseManifestUrl))).Count -ne 1 -or $runText.Contains($MainManifestUrl)){throw 'CI Bootstrap copy does not contain exactly the release manifest URL substitution.'}
$reversed=$runText.Replace($ReleaseManifestUrl,$MainManifestUrl)
$utf8=New-Object Text.UTF8Encoding($false)
$revBytes=$utf8.GetBytes($reversed)
$exactBytes=[IO.File]::ReadAllBytes($bootExact)
# Get-Content -Raw strips no BOM from this ASCII bootstrap; prove textual identity and retain byte-level SHA proof from fixture preparation.
if($reversed -cne $exactText){throw 'CI Bootstrap copy differs from released Bootstrap by more than manifest URL.'}
Assert-Identity $main $StartMainSha $StartMainSize "Start $StartVersion main"
Assert-Identity $addon $StartAddonSha $StartAddonSize "Start $StartVersion addon"
Assert-Identity $agentPath $Agent 4855 'Resident agent'

$env:LOCALAPPDATA=Join-Path $fixtureRoot 'LocalAppData'
$env:APPDATA=Join-Path $fixtureRoot 'Roaming'
New-Item -ItemType Directory -Force -Path $env:APPDATA|Out-Null

function Run-Boot([string]$Action){
    Assert-Identity $bootExact $Bootstrap 42963 'Installed exact Bootstrap before action'
    $out=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $bootRun -Action $Action -Json 2>&1
    $code=$LASTEXITCODE
    Write-Host ("BOOTSTRAP_"+$StartVersion+'_'+$Action+"_EXIT="+$code)
    $out|ForEach-Object{Write-Host $_}
    if($code -ne 0){throw "Bootstrap $Action failed with exit $code"}
    $last=@($out|Where-Object{[string]$_ -match '^\s*\{'})|Select-Object -Last 1
    if(-not $last){throw "Bootstrap $Action emitted no JSON result"}
    return ($last|ConvertFrom-Json)
}

$check=Run-Boot 'Check'
if(-not $check.success -or [string]$check.installed_version -ne $StartVersion){throw "Check did not detect exact installed $StartVersion."}
if([int]$check.result.edge_count -ne $ExpectedEdges){throw "Expected $ExpectedEdges update edge(s), got $($check.result.edge_count)"}
if([string]$check.manifest_url -ne $ReleaseManifestUrl){throw "Pre-merge Check did not use release manifest URL: $($check.manifest_url)"}

$rb=Run-Boot 'RollbackTest'
if(-not $rb.success -or [string]$rb.transaction_status -ne 'rolled-back'){throw 'RollbackTest did not finish rolled-back.'}
Assert-Identity $main $StartMainSha $StartMainSize 'Rollback main'
Assert-Identity $addon $StartAddonSha $StartAddonSize 'Rollback addon'
Assert-Identity $agentPath $Agent 4855 'Rollback resident agent'
Assert-Identity $bootExact $Bootstrap 42963 'Rollback exact Bootstrap'

$up=Run-Boot 'Update'
if(-not $up.success -or [string]$up.transaction_status -ne 'committed'){throw 'Update did not commit v0.6.20.'}
Assert-Identity $main $TargetMain 281585 'Updated v0.6.20 main'
Assert-Identity $addon $TargetAddon 225044 'Updated Addon Manager r9'
Assert-Identity $agentPath $Agent 4855 'Updated resident agent'
Assert-Identity $bootExact $Bootstrap 42963 'Updated exact Bootstrap'

foreach($file in @($main,$addon)){
    $tokens=$null;$errors=$null
    [System.Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)|Out-Null
    if($errors.Count){$errors|ForEach-Object{Write-Error $_.Message};throw "Updated candidate failed PowerShell 5.1 parse: $file"}
}
$mainSelf=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $main -Action SelfTest 2>&1
$mainSelfCode=$LASTEXITCODE;$mainSelf|ForEach-Object{Write-Host $_}
if($mainSelfCode -ne 0){throw 'Updated v0.6.20 main SelfTest failed.'}
$addonSelf=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $addon -Action SelfTest 2>&1
$addonSelfCode=$LASTEXITCODE;$addonSelf|ForEach-Object{Write-Host $_}
if($addonSelfCode -ne 0){throw 'Updated Addon Manager r9 SelfTest failed.'}

$post=Run-Boot 'Check'
if(-not $post.success -or [string]$post.installed_version -ne '0.6.20'){throw 'Post-update Check did not detect v0.6.20.'}
if($post.result.already_current -ne $true -or [int]$post.result.edge_count -ne 0){throw 'Post-update Check is not already-current with zero edges.'}
Assert-Identity $bootExact $Bootstrap 42963 'Final exact Bootstrap'
Write-Host "BOOTSTRAP_V106_MANIFEST_URL_ONLY_INJECTED_${StartVersion}_TO_V0620_E2E_PASS edges=$ExpectedEdges"
