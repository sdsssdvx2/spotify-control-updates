param([Parameter(Mandatory=$true)][string]$Fixture)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'

$fixtureRoot=(Resolve-Path -LiteralPath $Fixture).Path
$root=Join-Path $fixtureRoot 'LocalAppData\SpotifyControl';$bin=Join-Path $root 'bin'
$bootExact=Join-Path $root 'bootstrap\spotify-control-self-updater.ps1';$bootRun=Join-Path $root 'bootstrap\spotify-control-self-updater-ci-local-manifest.ps1'
$manifestDir=Join-Path $fixtureRoot 'ci-manifest';$manifestPath=Join-Path $manifestDir 'manifest.json'
$main=Join-Path $bin 'spotify-control.ps1';$addon=Join-Path $bin 'addon-manager.ps1';$agentPath=Join-Path $bin 'spotify-control-agent.vbs'
$StartVersion='0.6.24';$TargetVersion='0.6.25'
$StartMain='dc5d7ec17f18f7546786c81f3172c08f6fb1692842c2e6c0a69a86171e6b1151';$StartAddon='81343687c475f7f48f1311b09c98205a021776f26e8d55082e0ec47f8ebfb470'
$TargetMain='896bb74e71385b5b6ada118af41cbe9d398dc662ce3719234104028e6eed197f';$TargetAddon='25ebd0a5d5158f7d3cb4b4ce2ecf89f05f4dad3ef6bc799599e7204ce103c29c'
$Agent='2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278';$Bootstrap='d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6'
$SourceCommit='7c23a470ecf9c83dff5c42caeed03ff20f669072';$PayloadSet='bb6c5f63d3b65fb61f3f03ca64d43060de4508a2b0bb72e77df868c64337079a'
$MainManifestUrl='https://raw.githubusercontent.com/sdsssdvx2/spotify-control-updates/main/manifest.json';$LocalManifestUrl='http://127.0.0.1:8765/manifest.json'

function Assert-Identity([string]$Path,[string]$Sha,[int64]$Size,[string]$Label){if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "$Label missing: $Path"};$item=Get-Item -LiteralPath $Path;$hash=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant();if([int64]$item.Length -ne $Size -or $hash -cne $Sha){throw "$Label identity mismatch: size=$($item.Length) sha=$hash"}}
Assert-Identity $bootExact $Bootstrap 42963 'Bootstrap 1.0.6'
if(-not(Test-Path -LiteralPath $bootRun -PathType Leaf)){throw 'CI manifest-injected Bootstrap copy missing.'}
$exactText=Get-Content -LiteralPath $bootExact -Raw;$runText=Get-Content -LiteralPath $bootRun -Raw
if(([regex]::Matches($exactText,[regex]::Escape($MainManifestUrl))).Count -ne 1 -or $exactText.Contains($LocalManifestUrl)){throw 'Exact Bootstrap manifest URL contract changed.'}
if(([regex]::Matches($runText,[regex]::Escape($LocalManifestUrl))).Count -ne 1 -or $runText.Contains($MainManifestUrl)){throw 'CI Bootstrap copy manifest URL substitution invalid.'}
if($runText.Replace($LocalManifestUrl,$MainManifestUrl) -cne $exactText){throw 'CI Bootstrap copy differs by more than manifest URL.'}
$runSha=(Get-FileHash -LiteralPath $bootRun -Algorithm SHA256).Hash.ToLowerInvariant();$runSize=[int64](Get-Item $bootRun).Length
$ciManifest=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json
if($ciManifest.latest_version -ne $TargetVersion -or $ciManifest.source_commit -ne $SourceCommit -or $ciManifest.payload_set_sha256 -ne $PayloadSet){throw 'CI manifest release fields changed.'}
if($ciManifest.bootstrap.version -ne '1.0.6' -or $ciManifest.bootstrap.sha256 -ne $runSha -or [int64]$ciManifest.bootstrap.size -ne $runSize){throw 'CI manifest Bootstrap pin mismatch.'}
$edge=@($ciManifest.updates|Where-Object{$_.from_version -eq $StartVersion -and $_.to_version -eq $TargetVersion});if($edge.Count -ne 1 -or @($edge[0].patches).Count -ne 2){throw 'Exact v0.6.24 -> v0.6.25 edge missing/ambiguous.'}
Assert-Identity $main $StartMain 284312 'Start v0.6.24 main';Assert-Identity $addon $StartAddon 275414 'Start Addon Manager r13';Assert-Identity $agentPath $Agent 4855 'Resident agent'

$env:LOCALAPPDATA=Join-Path $fixtureRoot 'LocalAppData';$env:APPDATA=Join-Path $fixtureRoot 'Roaming';New-Item -ItemType Directory -Force -Path $env:APPDATA|Out-Null
function Run-Boot([string]$Action){Assert-Identity $bootExact $Bootstrap 42963 'Installed exact Bootstrap before action';$out=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $bootRun -Action $Action -Json 2>&1;$code=$LASTEXITCODE;Write-Host ("BOOTSTRAP_V0625_"+$Action+"_EXIT="+$code);$out|ForEach-Object{Write-Host $_};if($code -ne 0){throw "Bootstrap $Action failed with exit $code"};$last=@($out|Where-Object{[string]$_ -match '^\s*\{'})|Select-Object -Last 1;if(-not$last){throw "Bootstrap $Action emitted no JSON result"};return($last|ConvertFrom-Json)}
function Assert-UpdatedCandidate {
  Assert-Identity $main $TargetMain 284313 'Updated v0.6.25 main';Assert-Identity $addon $TargetAddon 282718 'Updated Addon Manager r14';Assert-Identity $agentPath $Agent 4855 'Updated resident agent';Assert-Identity $bootExact $Bootstrap 42963 'Updated exact Bootstrap'
  foreach($file in @($main,$addon)){$tokens=$null;$errors=$null;[System.Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)|Out-Null;if($errors.Count){$errors|ForEach-Object{Write-Error $_.Message};throw "Updated candidate failed PowerShell 5.1 parse: $file"}}
  $mainText=Get-Content -LiteralPath $main -Raw;$addonText=Get-Content -LiteralPath $addon -Raw
  if($mainText.IndexOf('$ScriptVersion = "0.6.25"',[StringComparison]::Ordinal) -lt 0){throw 'Updated main v0.6.25 marker missing.'};if($addonText.IndexOf('$Version = "0.6.5-r14"',[StringComparison]::Ordinal) -lt 0){throw 'Updated Addon Manager r14 marker missing.'}
  foreach($required in @('function Get-SplitifyReleaseCatalog','function Get-SplitifyTreeFingerprint','function Resolve-SplitifyInstalledReleaseProvenance','authenticated-release-catalog-tree-v1','60311e81ae11727528fd5e34879533e1cfacdaaf7b2b21dd1808fb20e3b32454','8c4525b41511fb5a32ad4921fbdbda5c59e0fb613ff0b2f223d0ee295030936a','571722765760ccb98697a50742cfc8e66fae5411f91716794359e483b4383c76','48bace1b6cef325dd1757bf4428e01fd42759a74da20a93fc16ab1ce49132777','.Sort([System.StringComparer]::OrdinalIgnoreCase)','never-disable-or-optimize','protect-ratings-tags-notes','playlist-backed-ratings-preserve')){if(($mainText+$addonText).IndexOf($required,[StringComparison]::OrdinalIgnoreCase) -lt 0){throw "Updated r14 provenance/protection contract missing: $required"}}
  $registryStart=$addonText.IndexOf('function Get-AddonPolicyRegistry {',[StringComparison]::Ordinal);$registryNext=$addonText.IndexOf("`nfunction ",$registryStart+1,[StringComparison]::Ordinal);$registryBlock=$addonText.Substring($registryStart,$registryNext-$registryStart)
  foreach($name in @('ivLyrics','better-local-files','eternal-jukebox','playlist-maker')){if($registryBlock.IndexOf("name='$name'",[StringComparison]::OrdinalIgnoreCase) -lt 0){throw "Expected automatic authority missing: $name"}}
  if($registryBlock.IndexOf("name='splitify'",[StringComparison]::OrdinalIgnoreCase) -lt 0 -or $registryBlock.IndexOf("mutation_mode='deny'",[StringComparison]::OrdinalIgnoreCase) -lt 0 -or $registryBlock.IndexOf("install_mode='never-auto-install'",[StringComparison]::OrdinalIgnoreCase) -lt 0){throw 'Splitify deny/never-auto-install policy drifted.'}
  $mainSelf=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $main -Action SelfTest 2>&1;$mainCode=$LASTEXITCODE;$mainSelf|ForEach-Object{Write-Host $_};if($mainCode -ne 0){throw 'Updated v0.6.25 main SelfTest failed.'}
  $addonSelf=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $addon -Action SelfTest 2>&1;$addonCode=$LASTEXITCODE;$addonSelf|ForEach-Object{Write-Host $_};if($addonCode -ne 0){throw 'Updated Addon Manager r14 SelfTest failed.'}
}

$python=(Get-Command python -ErrorAction Stop).Source;$server=$null
try{
  $server=Start-Process -FilePath $python -ArgumentList @('-m','http.server','8765','--bind','127.0.0.1','--directory',$manifestDir) -WindowStyle Hidden -PassThru
  $ready=$false;for($i=0;$i -lt 40;$i++){try{$probe=Invoke-RestMethod -Uri $LocalManifestUrl -TimeoutSec 2;if($probe.latest_version -eq $TargetVersion){$ready=$true;break}}catch{};Start-Sleep -Milliseconds 250};if(-not$ready){throw 'Local CI manifest server did not become ready.'}
  $check=Run-Boot 'Check';if(-not$check.success -or [string]$check.installed_version -ne $StartVersion){throw 'Check did not detect exact installed v0.6.24.'};if([int]$check.result.edge_count -ne 1){throw "Expected one update edge, got $($check.result.edge_count)"};if([string]$check.manifest_url -ne $LocalManifestUrl){throw 'Check did not use localhost CI manifest.'}
  $rb=Run-Boot 'RollbackTest';if(-not$rb.success -or [string]$rb.transaction_status -ne 'rolled-back'){throw 'RollbackTest did not finish rolled-back.'};Assert-Identity $main $StartMain 284312 'Rollback v0.6.24 main';Assert-Identity $addon $StartAddon 275414 'Rollback Addon Manager r13';Assert-Identity $agentPath $Agent 4855 'Rollback resident agent';Assert-Identity $bootExact $Bootstrap 42963 'Rollback exact Bootstrap'
  $up=Run-Boot 'Update';if(-not$up.success -or [string]$up.transaction_status -ne 'committed'){throw 'Update did not commit v0.6.25.'};Assert-UpdatedCandidate
  $post=Run-Boot 'Check';if(-not$post.success -or [string]$post.installed_version -ne $TargetVersion){throw 'Post-update Check did not detect v0.6.25.'};if($post.result.already_current -ne $true -or [int]$post.result.edge_count -ne 0){throw 'Post-update Check not already-current with zero edges.'};Assert-Identity $bootExact $Bootstrap 42963 'Final exact Bootstrap'
  Write-Host 'BOOTSTRAP_V106_LOCAL_MANIFEST_TRUST_PIN_ONLY_V0624_TO_V0625_E2E_PASS edges=1'
}finally{if($server -and -not$server.HasExited){Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue;try{$server.WaitForExit(5000)|Out-Null}catch{}}}
