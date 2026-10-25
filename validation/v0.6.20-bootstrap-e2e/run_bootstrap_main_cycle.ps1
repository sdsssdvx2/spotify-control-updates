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
$boot=Join-Path $root 'bootstrap\spotify-control-self-updater.ps1'
$main=Join-Path $bin 'spotify-control.ps1'
$addon=Join-Path $bin 'addon-manager.ps1'
$agentPath=Join-Path $bin 'spotify-control-agent.vbs'
$MainManifestUrl='https://raw.githubusercontent.com/sdsssdvx2/spotify-control-updates/main/manifest.json'
$TargetMain='e9f0181756cfb84c505c30f54b6067e321f6d178d3a1936489714b8f4441ba18'
$TargetAddon='3a20fcd552b363ebc05e26854a8fe010ffe50e5c756ebd3d7fca54011e8a8b86'
$Agent='2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278'
$Bootstrap='d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6'

function Assert-Identity([string]$Path,[string]$Sha,[int64]$Size,[string]$Label){
    if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){throw "$Label missing: $Path"}
    $item=Get-Item -LiteralPath $Path;$hash=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if([int64]$item.Length -ne $Size -or $hash -ne $Sha){throw "$Label identity mismatch: size=$($item.Length) sha=$hash"}
}

Assert-Identity $boot $Bootstrap 42963 'Exact released Bootstrap 1.0.6'
Assert-Identity $main $StartMainSha $StartMainSize "Start $StartVersion main"
Assert-Identity $addon $StartAddonSha $StartAddonSize "Start $StartVersion addon"
Assert-Identity $agentPath $Agent 4855 'Resident agent'
$bootText=Get-Content -LiteralPath $boot -Raw
if(([regex]::Matches($bootText,[regex]::Escape($MainManifestUrl))).Count -ne 1){throw 'Exact Bootstrap no longer pins the production main manifest exactly once.'}

$env:LOCALAPPDATA=Join-Path $fixtureRoot 'LocalAppData'
$env:APPDATA=Join-Path $fixtureRoot 'Roaming'
New-Item -ItemType Directory -Force -Path $env:APPDATA|Out-Null

function Run-Boot([string]$Action){
    Assert-Identity $boot $Bootstrap 42963 'Exact Bootstrap before action'
    $out=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $boot -Action $Action -Json 2>&1
    $code=$LASTEXITCODE
    Write-Host ("MAIN_BOOTSTRAP_"+$StartVersion+'_'+$Action+"_EXIT="+$code)
    $out|ForEach-Object{Write-Host $_}
    if($code -ne 0){throw "Exact Bootstrap $Action failed with exit $code"}
    $last=@($out|Where-Object{[string]$_ -match '^\s*\{'})|Select-Object -Last 1
    if(-not $last){throw "Exact Bootstrap $Action emitted no JSON result"}
    return ($last|ConvertFrom-Json)
}

$check=Run-Boot 'Check'
if(-not $check.success -or [string]$check.installed_version -ne $StartVersion){throw "Exact-main Check did not detect installed $StartVersion."}
if([int]$check.result.edge_count -ne $ExpectedEdges){throw "Expected $ExpectedEdges exact-main edge(s), got $($check.result.edge_count)"}
if([string]$check.manifest_url -ne $MainManifestUrl){throw "Exact Bootstrap did not use main manifest: $($check.manifest_url)"}
if([string]$check.result.latest_version -ne '0.6.20'){throw "Main manifest latest_version is not 0.6.20: $($check.result.latest_version)"}
if([string]$check.result.source_commit -ne '3543ee39bd9afa353a4d276c2b6b0f86dccafd74'){throw 'Main manifest source_commit mismatch.'}
if([string]$check.result.payload_set_sha256 -ne '65bf8dff2f563ce5caf80f660db64b1f6b34ced3029c24dfbfa3463f2ba3bf52'){throw 'Main manifest payload-set mismatch.'}

$rb=Run-Boot 'RollbackTest'
if(-not $rb.success -or [string]$rb.transaction_status -ne 'rolled-back'){throw 'Exact-main RollbackTest did not finish rolled-back.'}
Assert-Identity $main $StartMainSha $StartMainSize 'Exact-main rollback main'
Assert-Identity $addon $StartAddonSha $StartAddonSize 'Exact-main rollback addon'
Assert-Identity $agentPath $Agent 4855 'Exact-main rollback resident agent'
Assert-Identity $boot $Bootstrap 42963 'Exact-main rollback Bootstrap'

$up=Run-Boot 'Update'
if(-not $up.success -or [string]$up.transaction_status -ne 'committed'){throw 'Exact-main Update did not commit v0.6.20.'}
Assert-Identity $main $TargetMain 281585 'Exact-main updated v0.6.20 main'
Assert-Identity $addon $TargetAddon 225044 'Exact-main updated Addon Manager r9'
Assert-Identity $agentPath $Agent 4855 'Exact-main updated resident agent'
Assert-Identity $boot $Bootstrap 42963 'Exact-main updated Bootstrap'

foreach($file in @($main,$addon)){
    $tokens=$null;$errors=$null
    [System.Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)|Out-Null
    if($errors.Count){$errors|ForEach-Object{Write-Error $_.Message};throw "Exact-main updated candidate failed PowerShell 5.1 parse: $file"}
}
$mainSelf=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $main -Action SelfTest 2>&1
$mainSelfCode=$LASTEXITCODE;$mainSelf|ForEach-Object{Write-Host $_}
if($mainSelfCode -ne 0){throw 'Exact-main v0.6.20 main SelfTest failed.'}
$addonSelf=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $addon -Action SelfTest 2>&1
$addonSelfCode=$LASTEXITCODE;$addonSelf|ForEach-Object{Write-Host $_}
if($addonSelfCode -ne 0){throw 'Exact-main Addon Manager r9 SelfTest failed.'}

$post=Run-Boot 'Check'
if(-not $post.success -or [string]$post.installed_version -ne '0.6.20'){throw 'Exact-main post-update Check did not detect v0.6.20.'}
if($post.result.already_current -ne $true -or [int]$post.result.edge_count -ne 0){throw 'Exact-main post-update Check is not already-current with zero edges.'}
Assert-Identity $boot $Bootstrap 42963 'Final exact Bootstrap'
Write-Host "BOOTSTRAP_V106_EXACT_MAIN_${StartVersion}_TO_V0620_E2E_PASS edges=$ExpectedEdges"
