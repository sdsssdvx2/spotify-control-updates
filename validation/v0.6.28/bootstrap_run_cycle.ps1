param([Parameter(Mandatory=$true)][string]$Fixture)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'

$fixtureRoot=(Resolve-Path -LiteralPath $Fixture).Path
$root=Join-Path $fixtureRoot 'LocalAppData\SpotifyControl';$bin=Join-Path $root 'bin'
$bootExact=Join-Path $root 'bootstrap\spotify-control-self-updater.ps1';$bootRun=Join-Path $root 'bootstrap\spotify-control-self-updater-ci-local-manifest.ps1'
$manifestDir=Join-Path $fixtureRoot 'ci-manifest';$manifestPath=Join-Path $manifestDir 'manifest.json'
$main=Join-Path $bin 'spotify-control.ps1';$addon=Join-Path $bin 'addon-manager.ps1';$agentPath=Join-Path $bin 'spotify-control-agent.vbs'
$StartVersion='0.6.27';$TargetVersion='0.6.28'
$StartMain='9eb51ff9e001ebd84fd43532a2b3869f6d61f9b230a8008742119e8892202787';$StartAddon='c8d52542faaf033c0ede8216f71fe2e40d73636bd343d3faf88eb926e5017152'
$TargetMain='af1582ec335807f8f5daa9b3a65b13d567264f326d3c608c082ae02ff0a4cfc0';$TargetAddon='5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285'
$Agent='2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278';$Bootstrap='d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6'
$SourceCommit='bb6d90146f20b73d36fbf8cb813f1b190f403c48';$PayloadSet='4be96c5d41c2160ed9ac96001b469998595629232929b82c8b0f34b11fda3b43'
$CoverCatalog='c12391e57a393d37d70ffd7a984bdbb6af9f4a83cf3c2b0a8c9bf040247c731f'
$CoverCommit='9454b55e454fb354ecedcf3f72c5a4f0a9671651';$CoverSha='0aea69246e14156b22a10261af07b84f3abc58bed4368e03f740ed76db329738'
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
if($ciManifest.latest_version -cne $TargetVersion -or $ciManifest.source_commit -cne $SourceCommit -or $ciManifest.payload_set_sha256 -cne $PayloadSet){throw 'CI manifest release fields changed.'}
if($ciManifest.bootstrap.version -cne '1.0.6' -or $ciManifest.bootstrap.sha256 -cne $runSha -or [int64]$ciManifest.bootstrap.size -ne $runSize){throw 'CI manifest Bootstrap pin mismatch.'}
$edge=@($ciManifest.updates|Where-Object{$_.from_version -ceq $StartVersion -and $_.to_version -ceq $TargetVersion});if($edge.Count -ne 1 -or @($edge[0].patches).Count -ne 2){throw 'Exact v0.6.27 -> v0.6.28 edge missing/ambiguous.'}
Assert-Identity $main $StartMain 284317 'Start v0.6.27 main';Assert-Identity $addon $StartAddon 303745 'Start Addon Manager r16';Assert-Identity $agentPath $Agent 4855 'Resident agent'

$env:LOCALAPPDATA=Join-Path $fixtureRoot 'LocalAppData';$env:APPDATA=Join-Path $fixtureRoot 'Roaming';New-Item -ItemType Directory -Force -Path $env:APPDATA|Out-Null
function Run-Boot([string]$Action){Assert-Identity $bootExact $Bootstrap 42963 'Installed exact Bootstrap before action';$out=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $bootRun -Action $Action -Json 2>&1;$code=$LASTEXITCODE;Write-Host ("BOOTSTRAP_V0628_"+$Action+"_EXIT="+$code);$out|ForEach-Object{Write-Host $_};if($code -ne 0){throw "Bootstrap $Action failed with exit $code"};$last=@($out|Where-Object{[string]$_ -match '^\s*\{'})|Select-Object -Last 1;if(-not$last){throw "Bootstrap $Action emitted no JSON result"};return($last|ConvertFrom-Json)}
function Get-FnBlock([string]$Text,[string]$Name){$marker="function $Name {";$start=$Text.IndexOf($marker,[StringComparison]::Ordinal);if($start -lt 0){throw "Missing function: $Name"};$next=$Text.IndexOf("`nfunction ",$start+$marker.Length,[StringComparison]::Ordinal);if($next -lt 0){$next=$Text.Length};return $Text.Substring($start,$next-$start)}
function Assert-UpdatedCandidate {
  Assert-Identity $main $TargetMain 284321 'Updated v0.6.28 main';Assert-Identity $addon $TargetAddon 323385 'Updated Addon Manager r17';Assert-Identity $agentPath $Agent 4855 'Updated resident agent';Assert-Identity $bootExact $Bootstrap 42963 'Updated exact Bootstrap'
  foreach($file in @($main,$addon)){$tokens=$null;$errors=$null;[System.Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)|Out-Null;if($errors.Count){$errors|ForEach-Object{Write-Error $_.Message};throw "Updated candidate failed PowerShell 5.1 parse: $file"}}
  $mainText=Get-Content -LiteralPath $main -Raw;$addonText=Get-Content -LiteralPath $addon -Raw
  if($mainText.IndexOf('$ScriptVersion = "0.6.28"',[StringComparison]::Ordinal) -lt 0){throw 'Updated main v0.6.28 marker missing.'};if($addonText.IndexOf('$Version = "0.6.5-r17"',[StringComparison]::Ordinal) -lt 0){throw 'Updated Addon Manager r17 marker missing.'}
  foreach($required in @(
    'function Get-SCCoverAmbienceSnapshotCatalog','function Get-SCCoverAmbienceFileSnapshotProvenance','function Resolve-SCCoverAmbienceInstalledSnapshotProvenance','function Get-SCCoverAmbienceRemoteHead',
    $CoverCatalog,$CoverCommit,$CoverSha,'watched-current-proven','watched-upstream-head-unproven-new-snapshot','ownership_migration_authorized','disable_or_optimize_authorized',
    'function Get-StarRatingsReleaseCatalog','function Resolve-StarRatingsInstalledReleaseProvenance','2592f43a26c3c49b9d58b8244654d27448d801995465c7c8e4ba8d3159b9aa27','performance-original-backup-v1','active-exact-upstream-dist-v1',
    'function Resolve-TagifyInstalledReleaseProvenance','75d66f6e06ec76c8f96fbc7941617e7330844979a87d3297e8e4ff824c3b6a1a',
    'function Resolve-SplitifyInstalledReleaseProvenance','60311e81ae11727528fd5e34879533e1cfacdaaf7b2b21dd1808fb20e3b32454',
    'never-disable-or-optimize','protect-ratings-tags-notes','playlist-backed-ratings-preserve')){
      if(($mainText+$addonText).IndexOf([string]$required,[StringComparison]::OrdinalIgnoreCase) -lt 0){throw "Updated r17 provenance/protection contract missing: $required"}
  }
  $registry=Get-FnBlock $addonText 'Get-AddonPolicyRegistry'
  foreach($name in @('ivLyrics','better-local-files','eternal-jukebox','playlist-maker')){if($registry.IndexOf("name='$name'",[StringComparison]::OrdinalIgnoreCase) -lt 0){throw "Expected automatic authority missing: $name"}}
  foreach($required in @("name='sc-cover-ambience.js'","inventory_policy='rescue-copy-cleanup-only'","mutation_mode='deny'","install_mode='recovery-owned'","version_strategy='owner-cleanup-only'","rollback_strategy='external-owner'","data_policy='never-disable-or-optimize'")){if($registry.IndexOf($required,[StringComparison]::OrdinalIgnoreCase) -lt 0){throw "SC Cover Ambience protected registry contract drifted: $required"}}
  if($registry.IndexOf("name='star-ratings'",[StringComparison]::OrdinalIgnoreCase) -lt 0 -or $registry.IndexOf("data_policy='playlist-backed-ratings-preserve'",[StringComparison]::OrdinalIgnoreCase) -lt 0){throw 'Star Ratings protected policy drifted.'}
  if($registry.IndexOf("name='tagify'",[StringComparison]::OrdinalIgnoreCase) -lt 0 -or $registry.IndexOf("data_policy='protect-ratings-tags-notes'",[StringComparison]::OrdinalIgnoreCase) -lt 0){throw 'Tagify protected policy drifted.'}
  if($registry.IndexOf("name='splitify'",[StringComparison]::OrdinalIgnoreCase) -lt 0){throw 'Splitify protected registry entry missing.'}
  $update=Get-FnBlock $addonText 'Update-AutoApps';if($update.IndexOf('sc-cover-ambience',[StringComparison]::OrdinalIgnoreCase) -ge 0){throw 'SC Cover Ambience gained automatic mutation route.'}
  $rollback=Get-FnBlock $addonText 'Rollback-LastTransaction';if($rollback.IndexOf('Assert-AddonSourceAdapterTransactionAuthorization',[StringComparison]::OrdinalIgnoreCase) -ge 0){throw 'RollbackLast became source-adapter-dependent.'}
  $mainSelf=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $main -Action SelfTest 2>&1;$mainCode=$LASTEXITCODE;$mainSelf|ForEach-Object{Write-Host $_};if($mainCode -ne 0){throw 'Updated v0.6.28 main SelfTest failed.'}
  $addonSelf=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $addon -Action SelfTest 2>&1;$addonCode=$LASTEXITCODE;$addonSelf|ForEach-Object{Write-Host $_};if($addonCode -ne 0){throw 'Updated Addon Manager r17 SelfTest failed.'}
}

$python=(Get-Command python -ErrorAction Stop).Source;$server=$null
try{
  $server=Start-Process -FilePath $python -ArgumentList @('-m','http.server','8765','--bind','127.0.0.1','--directory',$manifestDir) -WindowStyle Hidden -PassThru
  $ready=$false;for($i=0;$i -lt 40;$i++){try{$probe=Invoke-RestMethod -Uri $LocalManifestUrl -TimeoutSec 2;if($probe.latest_version -eq $TargetVersion){$ready=$true;break}}catch{};Start-Sleep -Milliseconds 250};if(-not$ready){throw 'Local CI manifest server did not become ready.'}
  $check=Run-Boot 'Check';if(-not$check.success -or [string]$check.installed_version -cne $StartVersion){throw 'Check did not detect exact installed v0.6.27.'};if([int]$check.result.edge_count -ne 1){throw "Expected one update edge, got $($check.result.edge_count)"};if([string]$check.manifest_url -cne $LocalManifestUrl){throw 'Check did not use localhost CI manifest.'}
  $rb=Run-Boot 'RollbackTest';if(-not$rb.success -or [string]$rb.transaction_status -cne 'rolled-back'){throw 'RollbackTest did not finish rolled-back.'};Assert-Identity $main $StartMain 284317 'Rollback v0.6.27 main';Assert-Identity $addon $StartAddon 303745 'Rollback Addon Manager r16';Assert-Identity $agentPath $Agent 4855 'Rollback resident agent';Assert-Identity $bootExact $Bootstrap 42963 'Rollback exact Bootstrap'
  $up=Run-Boot 'Update';if(-not$up.success -or [string]$up.transaction_status -cne 'committed'){throw 'Update did not commit v0.6.28.'};Assert-UpdatedCandidate
  $post=Run-Boot 'Check';if(-not$post.success -or [string]$post.installed_version -cne $TargetVersion){throw 'Post-update Check did not detect v0.6.28.'};if($post.result.already_current -ne $true -or [int]$post.result.edge_count -ne 0){throw 'Post-update Check not already-current with zero edges.'};Assert-Identity $bootExact $Bootstrap 42963 'Final exact Bootstrap'
  Write-Host 'BOOTSTRAP_V106_LOCAL_MANIFEST_TRUST_PIN_ONLY_V0627_TO_V0628_E2E_PASS edges=1'
}finally{if($server -and -not$server.HasExited){Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue;try{$server.WaitForExit(5000)|Out-Null}catch{}}}
