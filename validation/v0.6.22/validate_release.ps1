param(
    [string]$Base = 'dacd4faf6a632b6b33571acf16ed4b6e73a865d7'
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'

$ExpectedSource='db4dd0e4357cbf03ea95dd8773c0be173b2c91fc'
$ExpectedPayload='cb396442ac874504a04d4acb0034d3cb9fa11acce290da18e639c2dbe8e5a091'
$ExpectedMain='b5ba4dc98b10ea922ce30401b5cddf5a1ab01171366e09b3546ce3cc6fcd80fe'
$ExpectedAddon='0ee8d30bf7c2fda9d0d8d112b7191b0d0439a1071d284d0cc04a87fe8937c7bc'
$ExpectedAgent='2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278'
$ExpectedBootstrap='d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6'
$ExpectedAdapter='c0611a7b96f6ff09d1e235119efce2f2def6eb6d0a4e8e93e276cfa622c3c42d'
$ExpectedRegistry='05c40a5339fe59b001ca0f4c4929643fd59e33a3002bae7067425845c85e2f6e'

$m=Get-Content manifest.json -Raw|ConvertFrom-Json
if($m.latest_version -ne '0.6.22'){throw "Unexpected latest_version: $($m.latest_version)"}
if($m.min_bootstrap_version -ne '1.0.6'){throw 'min_bootstrap_version changed.'}
if($m.source_commit -ne $ExpectedSource){throw "Unexpected source_commit: $($m.source_commit)"}
git cat-file -e "$ExpectedSource^{commit}"
if($LASTEXITCODE -ne 0){throw 'Manifest source_commit is not an available commit.'}
if((git merge-base $ExpectedSource HEAD).Trim() -ne $ExpectedSource){throw 'Manifest source_commit is not an ancestor of stable head.'}
if($m.payload_set_sha256 -ne $ExpectedPayload){throw 'Unexpected v0.6.22 payload set.'}
if($m.bootstrap.version -ne '1.0.6' -or $m.bootstrap.sha256 -ne $ExpectedBootstrap -or [int64]$m.bootstrap.size -ne 42963){throw 'Bootstrap 1.0.6 contract changed.'}

$main=@($m.latest_files|Where-Object path -eq 'bin/spotify-control.ps1')
$addon=@($m.latest_files|Where-Object path -eq 'bin/addon-manager.ps1')
$agent=@($m.latest_files|Where-Object path -eq 'bin/spotify-control-agent.vbs')
if($main.Count -ne 1 -or [int64]$main[0].size -ne 281586 -or $main[0].sha256 -ne $ExpectedMain){throw 'v0.6.22 main identity mismatch.'}
if($addon.Count -ne 1 -or [int64]$addon[0].size -ne 268670 -or $addon[0].sha256 -ne $ExpectedAddon){throw 'Addon Manager r11 identity mismatch.'}
if($agent.Count -ne 1 -or [int64]$agent[0].size -ne 4855 -or $agent[0].sha256 -ne $ExpectedAgent){throw 'Resident agent identity mismatch.'}

$edge=@($m.updates|Where-Object{$_.from_version -eq '0.6.21' -and $_.to_version -eq '0.6.22'})
if($edge.Count -ne 1 -or @($edge[0].patches).Count -ne 2){throw 'Exact v0.6.21 -> v0.6.22 edge missing or ambiguous.'}
$wrong=@($m.updates|Where-Object{$_.from_version -eq '0.6.21' -and $_.to_version -ne '0.6.22'})
if($wrong.Count){throw 'Unexpected competing update edge from v0.6.21.'}
$paths=@($edge[0].patches|ForEach-Object{[string]$_.path}|Sort-Object)
if(($paths -join ',') -cne 'bin/addon-manager.ps1,bin/spotify-control.ps1'){throw "Unexpected v0.6.22 patch paths: $($paths -join ',')"}

$meta=Get-Content validation/v0.6.22/release-metadata.json -Raw|ConvertFrom-Json
if($meta.base_version -ne '0.6.21' -or $meta.addon_version -ne '0.6.5-r11'){throw 'v0.6.22 release metadata version contract changed.'}
if([int64]$meta.candidate_main.size -ne 281586 -or $meta.candidate_main.sha256 -ne $ExpectedMain){throw 'v0.6.22 main metadata identity changed.'}
if([int64]$meta.candidate_addon.size -ne 268670 -or $meta.candidate_addon.sha256 -ne $ExpectedAddon){throw 'r11 addon metadata identity changed.'}
if([int64]$meta.resident_agent.size -ne 4855 -or $meta.resident_agent.sha256 -ne $ExpectedAgent){throw 'resident agent metadata changed.'}
if($meta.bootstrap.version -ne '1.0.6' -or [int64]$meta.bootstrap.size -ne 42963 -or $meta.bootstrap.sha256 -ne $ExpectedBootstrap){throw 'Bootstrap metadata changed.'}
if($meta.authority_expanded -ne $false -or $meta.new_auto_install_authority -ne $false){throw 'r11 expanded automatic mutation/install authority.'}
$expectedAuthority=@('better-local-files','eternal-jukebox','ivLyrics','playlist-maker')
$actualAuthority=@($meta.auto_authority|Sort-Object)
if(($actualAuthority -join '|') -cne (($expectedAuthority|Sort-Object) -join '|')){throw "Automatic mutation authority changed: $($actualAuthority -join ', ')"}
if($meta.adapter_fingerprint -ne $ExpectedAdapter){throw 'Source adapter fingerprint changed.'}
if($meta.registry_fingerprint -ne $ExpectedRegistry){throw 'Registry fingerprint changed.'}

$mainPath='validation/v0.6.22/out/bin/spotify-control.ps1'
$addonPath='validation/v0.6.22/out/bin/addon-manager.ps1'
foreach($row in @(@($mainPath,281586,$ExpectedMain),@($addonPath,268670,$ExpectedAddon))){
    $p=[string]$row[0];$size=[int64]$row[1];$hash=[string]$row[2]
    if(-not(Test-Path -LiteralPath $p -PathType Leaf)){throw "Generated stable candidate missing: $p"}
    if((Get-Item -LiteralPath $p).Length -ne $size -or (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() -ne $hash){throw "Generated stable candidate identity mismatch: $p"}
    $tokens=$null;$errors=$null
    [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $p),[ref]$tokens,[ref]$errors)|Out-Null
    if($errors.Count){$errors|ForEach-Object{Write-Error ("{0}:{1}: {2}" -f $p,$_.Extent.StartLineNumber,$_.Message)};throw "PowerShell 5.1 parser failed: $p"}
}

$mainText=Get-Content $mainPath -Raw
$addonText=Get-Content $addonPath -Raw
if($mainText.IndexOf('# Spotify Control v0.6.22 Addon Source Registry r11',[StringComparison]::Ordinal) -ne 0 -or $mainText.IndexOf('$ScriptVersion = "0.6.22"',[StringComparison]::Ordinal) -lt 0){throw 'v0.6.22 main markers changed.'}
if($addonText.IndexOf('$Version = "0.6.5-r11"',[StringComparison]::Ordinal) -lt 0){throw 'Addon Manager r11 marker missing.'}
foreach($required in @("data_policy='protect-ratings-tags-notes'","data_policy='never-disable-or-optimize'",'source_adapter_sha256','Assert-AddonSourceAdapterTransactionAuthorization','Invoke-AddonSourceAdapterSelfTest')){
    if($addonText.IndexOf($required,[StringComparison]::Ordinal) -lt 0){throw "r11 policy/source-adapter contract missing: $required"}
}
if(([regex]::Matches($addonText,"mutation_mode='auto'")).Count -ne 4){throw 'r11 automatic mutation authority count changed.'}

$engine=Get-Content validation/v0.6.22/addon_source_adapter_engine.ps1.inc -Raw
foreach($bad in @('Invoke-WebRequest','Invoke-RestMethod','Expand-Archive','Remove-Item','Move-Item','Copy-Item','Start-Process','spicetify apply','spicetify backup','spicetify restore')){
    if($engine.IndexOf($bad,[StringComparison]::OrdinalIgnoreCase) -ge 0){throw "Generic source adapter gained forbidden side effect: $bad"}
}
$rbStart=$addonText.IndexOf('function Rollback-LastTransaction {',[StringComparison]::Ordinal)
if($rbStart -lt 0){throw 'Rollback-LastTransaction missing.'}
$rbNext=$addonText.IndexOf("`nfunction ",$rbStart+1,[StringComparison]::Ordinal)
if($rbNext -lt 0){$rbNext=$addonText.Length}
$rb=$addonText.Substring($rbStart,$rbNext-$rbStart)
if($rb.IndexOf('Assert-AddonSourceAdapterTransactionAuthorization',[StringComparison]::Ordinal) -ge 0 -or $rb.IndexOf('source_adapter_sha256',[StringComparison]::Ordinal) -ge 0){throw 'RollbackLast became source-adapter dependent.'}

python validation/v0.6.22/audit_r11.py
if($LASTEXITCODE -ne 0){throw 'r11 structural audit failed.'}
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File validation/v0.6.22/test_r11_source_adapter.ps1
if($LASTEXITCODE -ne 0){throw 'r11 source-adapter fixtures failed.'}

git diff --quiet $Base HEAD -- performance/overlay
if($LASTEXITCODE -ne 0){throw 'performance/overlay changed in v0.6.22 release.'}
git diff --quiet $Base HEAD -- performance/star-ratings
if($LASTEXITCODE -ne 0){throw 'performance/star-ratings changed in v0.6.22 release.'}

Write-Host "V0622_RELEASE_CONTRACT_PASS source=$ExpectedSource payload=$ExpectedPayload main=$ExpectedMain addon=$ExpectedAddon agent=$ExpectedAgent adapter=$ExpectedAdapter registry=$ExpectedRegistry"
