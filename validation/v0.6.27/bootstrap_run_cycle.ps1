param([Parameter(Mandatory=$true)][string]$Fixture)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'

$fixtureRoot=(Resolve-Path -LiteralPath $Fixture).Path
$root=Join-Path $fixtureRoot 'LocalAppData\SpotifyControl';$bin=Join-Path $root 'bin'
$bootExact=Join-Path $root 'bootstrap\spotify-control-self-updater.ps1';$bootRun=Join-Path $root 'bootstrap\spotify-control-self-updater-ci-local-manifest.ps1'
$manifestDir=Join-Path $fixtureRoot 'ci-manifest';$manifestPath=Join-Path $manifestDir 'manifest.json'
$main=Join-Path $bin 'spotify-control.ps1';$addon=Join-Path $bin 'addon-manager.ps1';$agentPath=Join-Path $bin 'spotify-control-agent.vbs'
$StartVersion='0.6.26';$TargetVersion='0.6.27'
$StartMain='d7b484a2a7b10a27db0f182d71fe36f590784171db7208189540045bcf4f54d1';$StartAddon='4aa56dd5d4ef07da21d3bdf5c76227fabb49c64767a281b1e11ee48e7211a09f'
$TargetMain='9eb51ff9e001ebd84fd43532a2b3869f6d61f9b230a8008742119e8892202787';$TargetAddon='c8d52542faaf033c0ede8216f71fe2e40d73636bd343d3faf88eb926e5017152'
$Agent='2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278';$Bootstrap='d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6'
$SourceCommit='1bead7959e27c7fff58116c43b8ca8e09a88203e';$PayloadSet='d74d39b2f705a6e225e639038390d24027ff32d27cd390a1b82700739bb0f178'
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
$edge=@($ciManifest.updates|Where-Object{$_.from_version -eq $StartVersion -and $_.to_version -eq $TargetVersion});if($edge.Count -ne 1 -or @($edge[0].patches).Count -ne 2){throw 'Exact v0.6.26 -> v0.6.27 edge missing/ambiguous.'}
Assert-Identity $main $StartMain 284311 'Start v0.6.26 main';Assert-Identity $addon $StartAddon 291294 'Start Addon Manager r15';Assert-Identity $agentPath $Agent 4855 'Resident agent'

$env:LOCALAPPDATA=Join-Path $fixtureRoot 'LocalAppData';$env:APPDATA=Join-Path $fixtureRoot 'Roaming';New-Item -ItemType Directory -Force -Path $env:APPDATA|Out-Null
function Run-Boot([string]$Action){Assert-Identity $bootExact $Bootstrap 42963 'Installed exact Bootstrap before action';$out=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $bootRun -Action $Action -Json 2>&1;$code=$LASTEXITCODE;Write-Host ("BOOTSTRAP_V0627_"+$Action+"_EXIT="+$code);$out|ForEach-Object{Write-Host $_};if($code -ne 0){throw "Bootstrap $Action failed with exit $code"};$last=@($out|Where-Object{[string]$_ -match '^\s*\{'})|Select-Object -Last 1;if(-not$last){throw "Bootstrap $Action emitted no JSON result"};return($last|ConvertFrom-Json)}
function Assert-UpdatedCandidate {
  Assert-Identity $main $TargetMain 284317 'Updated v0.6.27 main';Assert-Identity $addon $TargetAddon 303745 'Updated Addon Manager r16';Assert-Identity $agentPath $Agent 4855 'Updated resident agent';Assert-Identity $bootExact $Bootstrap 42963 'Updated exact Bootstrap'
  foreach($file in @($main,$addon)){$tokens=$null;$errors=$null;[System.Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)|Out-Null;if($errors.Count){$errors|ForEach-Object{Write-Error $_.Message};throw "Updated candidate failed PowerShell 5.1 parse: $file"}}
  $mainText=Get-Content -LiteralPath $main -Raw;$addonText=Get-Content -LiteralPath $addon -Raw
  if($mainText.IndexOf('$ScriptVersion = "0.6.27"',[StringComparison]::Ordinal) -lt 0){throw 'Updated main v0.6.27 marker missing.'};if($addonText.IndexOf('$Version = "0.6.5-r16"',[StringComparison]::Ordinal) -lt 0){throw 'Updated Addon Manager r16 marker missing.'}
  foreach($required in @(
    'function Get-StarRatingsReleaseCatalog','function Get-StarRatingsReleaseFileProvenance','function Resolve-StarRatingsInstalledReleaseProvenance',
    '2592f43a26c3c49b9d58b8244654d27448d801995465c7c8e4ba8d3159b9aa27','performance-original-backup-v1','active-exact-upstream-dist-v1',
    'function Resolve-TagifyInstalledReleaseProvenance','75d66f6e06ec76c8f96fbc7941617e7330844979a87d3297e8e4ff824c3b6a1a',
    'function Resolve-SplitifyInstalledReleaseProvenance','60311e81ae11727528fd5e34879533e1cfacdaaf7b2b21dd1808fb20e3b32454',
    'never-disable-or-optimize','protect-ratings-tags-notes','playlist-backed-ratings-preserve')){
      if(($mainText+$addonText).IndexOf($required,[StringComparison]::OrdinalIgnoreCase) -lt 0){throw "Updated r16 provenance/protection contract missing: $required"}
  }
  $registryStart=$addonText.IndexOf('function Get-AddonPolicyRegistry {',[StringComparison]::Ordinal);$registryNext=$addonText.IndexOf("`nfunction ",$registryStart+1,[StringComparison]::Ordinal);$registryBlock=$addonText.Substring($registryStart,$registryNext-$registryStart)
  foreach($name in @('ivLyrics','better-local-files','eternal-jukebox','playlist-maker')){if($registryBlock.IndexOf("name='$name'",[StringComparison]::OrdinalIgnoreCase) -lt 0){throw "Expected automatic authority missing: $name"}}
  if($registryBlock.IndexOf("name='star-ratings'",[StringComparison]::OrdinalIgnoreCase) -lt 0 -or $registryBlock.IndexOf("inventory_policy='source-watch-only'",[StringComparison]::OrdinalIgnoreCase) -lt 0 -or $registryBlock.IndexOf("mutation_mode='deny'",[StringComparison]::OrdinalIgnoreCase) -lt 0 -or $registryBlock.IndexOf("data_policy='playlist-backed-ratings-preserve'",[StringComparison]::OrdinalIgnoreCase) -lt 0){throw 'Star Ratings protected deny/source-watch-only policy drifted.'}
  if($registryBlock.IndexOf("name='tagify'",[StringComparison]::OrdinalIgnoreCase) -lt 0 -or $registryBlock.IndexOf("data_policy='protect-ratings-tags-notes'",[StringComparison]::OrdinalIgnoreCase) -lt 0){throw 'Tagify protected policy drifted.'}
  if($registryBlock.IndexOf("name='splitify'",[StringComparison]::OrdinalIgnoreCase) -lt 0){throw 'Splitify protected registry entry missing.'}
  $mainSelf=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $main -Action SelfTest 2>&1;$mainCode=$LASTEXITCODE;$mainSelf|ForEach-Object{Write-Host $_};if($mainCode -ne 0){throw 'Updated v0.6.27 main SelfTest failed.'}
  $addonSelf=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $addon -Action SelfTest 2>&1;$addonCode=$LASTEXITCODE;$addonSelf|ForEach-Object{Write-Host $_};if($addonCode -ne 0){throw 'Updated Addon Manager r16 SelfTest failed.'}
}

$python=(Get-Command python -ErrorAction Stop).Source;$server=$null
try{
  $server=Start-Process -FilePath $python -ArgumentList @('-m','http.server','8765','--bind','127.0.0.1','--directory',$manifestDir) -WindowStyle Hidden -PassThru
  $ready=$false;for($i=0;$i -lt 40;$i++){try{$probe=Invoke-RestMethod -Uri $LocalManifestUrl -TimeoutSec 2;if($probe.latest_version -eq $TargetVersion){$ready=$true;break}}catch{};Start-Sleep -Milliseconds 250};if(-not$ready){throw 'Local CI manifest server did not become ready.'}
  $check=Run-Boot 'Check';if(-not$check.success -or [string]$check.installed_version -ne $StartVersion){throw 'Check did not detect exact installed v0.6.26.'};if([int]$check.result.edge_count -ne 1){throw "Expected one update edge, got $($check.result.edge_count)"};if([string]$check.manifest_url -ne $LocalManifestUrl){throw 'Check did not use localhost CI manifest.'}
  $rb=Run-Boot 'RollbackTest';if(-not$rb.success -or [string]$rb.transaction_status -ne 'rolled-back'){throw 'RollbackTest did not finish rolled-back.'};Assert-Identity $main $StartMain 284311 'Rollback v0.6.26 main';Assert-Identity $addon $StartAddon 291294 'Rollback Addon Manager r15';Assert-Identity $agentPath $Agent 4855 'Rollback resident agent';Assert-Identity $bootExact $Bootstrap 42963 'Rollback exact Bootstrap'
  $up=Run-Boot 'Update';if(-not$up.success -or [string]$up.transaction_status -ne 'committed'){throw 'Update did not commit v0.6.27.'};Assert-UpdatedCandidate
  $post=Run-Boot 'Check';if(-not$post.success -or [string]$post.installed_version -ne $TargetVersion){throw 'Post-update Check did not detect v0.6.27.'};if($post.result.already_current -ne $true -or [int]$post.result.edge_count -ne 0){throw 'Post-update Check not already-current with zero edges.'};Assert-Identity $bootExact $Bootstrap 42963 'Final exact Bootstrap'
  Write-Host 'BOOTSTRAP_V106_LOCAL_MANIFEST_TRUST_PIN_ONLY_V0626_TO_V0627_E2E_PASS edges=1'
}finally{if($server -and -not$server.HasExited){Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue;try{$server.WaitForExit(5000)|Out-Null}catch{}}}
