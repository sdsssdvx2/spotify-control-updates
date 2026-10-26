param(
    [string]$Base = '29d6c52c6a79559e513b367ec57edcccebae5fd0'
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'

$ExpectedSource='9a90d5f13eb63023d8f965a004be14d309d99429'
$ExpectedPayload='7bd1bd7559eee615f4e0aa049b3ec1574f6b215dbdf7417a0a57ea99b20b6c55'
$ExpectedMain='f97c78c905b83e90e58a24035febcaccc27cb12113ae9cbc64acdc79f5853828'
$ExpectedAddon='7991b8eaa5a943957aebb9d3dd84d455ed6266430da442a672c05c145fe497a2'
$ExpectedAgent='2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278'
$ExpectedBootstrap='d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6'
$ExpectedPolicy='1e982cad2c043d8715871c6cc8ecf0244b7e4592e4764257f240d20205224e06'
$ExpectedGuard='8c598f96c4b4a4c6409c531657cc4949c92ae9d362785e6186f5334043505407'

$m=Get-Content manifest.json -Raw|ConvertFrom-Json
if($m.latest_version -ne '0.6.21'){throw "Unexpected latest_version: $($m.latest_version)"}
if($m.min_bootstrap_version -ne '1.0.6'){throw 'min_bootstrap_version changed.'}
if($m.source_commit -ne $ExpectedSource){throw "Unexpected source_commit: $($m.source_commit)"}
git cat-file -e "$ExpectedSource^{commit}"
if($LASTEXITCODE -ne 0){throw 'Manifest source_commit is not an available commit.'}
if((git merge-base $ExpectedSource HEAD).Trim() -ne $ExpectedSource){throw 'Manifest source_commit is not an ancestor of release head.'}
if($m.payload_set_sha256 -ne $ExpectedPayload){throw 'Unexpected v0.6.21 payload set.'}
if($m.bootstrap.version -ne '1.0.6' -or $m.bootstrap.sha256 -ne $ExpectedBootstrap -or [int64]$m.bootstrap.size -ne 42963){throw 'Bootstrap 1.0.6 contract changed.'}

$main=@($m.latest_files|Where-Object path -eq 'bin/spotify-control.ps1')
$addon=@($m.latest_files|Where-Object path -eq 'bin/addon-manager.ps1')
$agent=@($m.latest_files|Where-Object path -eq 'bin/spotify-control-agent.vbs')
if($main.Count -ne 1 -or [int64]$main[0].size -ne 281579 -or $main[0].sha256 -ne $ExpectedMain){throw 'v0.6.21 main identity mismatch.'}
if($addon.Count -ne 1 -or [int64]$addon[0].size -ne 250616 -or $addon[0].sha256 -ne $ExpectedAddon){throw 'Addon Manager r10 identity mismatch.'}
if($agent.Count -ne 1 -or [int64]$agent[0].size -ne 4855 -or $agent[0].sha256 -ne $ExpectedAgent){throw 'Resident agent identity mismatch.'}
$edge=@($m.updates|Where-Object{$_.from_version -eq '0.6.20' -and $_.to_version -eq '0.6.21'})
if($edge.Count -ne 1 -or @($edge[0].patches).Count -ne 2){throw 'Exact v0.6.20 -> v0.6.21 edge missing or ambiguous.'}
$wrong=@($m.updates|Where-Object{$_.from_version -eq '0.6.20' -and $_.to_version -ne '0.6.21'})
if($wrong.Count){throw 'Unexpected competing update edge from v0.6.20.'}
$paths=@($edge[0].patches|ForEach-Object{[string]$_.path}|Sort-Object)
if(($paths -join ',') -cne 'bin/addon-manager.ps1,bin/spotify-control.ps1'){throw "Unexpected v0.6.21 patch paths: $($paths -join ',')"}

$meta=Get-Content validation/v0.6.21/candidate-metadata.json -Raw|ConvertFrom-Json
if($meta.validation_provenance.head -ne '248dcd5315cd98cb798b0b711d21f50355c65d1d' -or $meta.validation_provenance.push_run -ne '40283288327' -or $meta.validation_provenance.pr_run -ne '40283546439'){throw 'r10 validation provenance changed.'}
if([int64]$meta.validation_provenance.validated_addon_size -ne 250616 -or $meta.validation_provenance.validated_addon_sha256 -ne $ExpectedAddon){throw 'Validated r10 identity provenance changed.'}
if([int64]$meta.policy_registry.size -ne 12842 -or $meta.policy_registry.sha256 -ne $ExpectedPolicy){throw 'Policy registry source identity changed.'}
if([int64]$meta.transaction_guard.size -ne 10408 -or $meta.transaction_guard.sha256 -ne $ExpectedGuard){throw 'Transaction guard source identity changed.'}

foreach($file in @('validation/v0.6.21/out/bin/spotify-control.ps1','validation/v0.6.21/out/bin/addon-manager.ps1','validation/v0.6.21-bootstrap-e2e/run_bootstrap_cycle.ps1')){
    $tokens=$null;$errors=$null
    [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $file),[ref]$tokens,[ref]$errors)|Out-Null
    if($errors.Count){$errors|ForEach-Object{Write-Error ("{0}:{1}: {2}" -f $file,$_.Extent.StartLineNumber,$_.Message)};throw "PowerShell 5.1 parser failed: $file"}
}
$mainText=Get-Content validation/v0.6.21/out/bin/spotify-control.ps1 -Raw
$addonText=Get-Content validation/v0.6.21/out/bin/addon-manager.ps1 -Raw
if($mainText.IndexOf('# Spotify Control v0.6.21 Addon Registry r10',[StringComparison]::Ordinal) -ne 0 -or $mainText.IndexOf('$ScriptVersion = "0.6.21"',[StringComparison]::Ordinal) -lt 0){throw 'v0.6.21 main markers changed.'}
if($addonText.IndexOf('$Version = "0.6.5-r10"',[StringComparison]::Ordinal) -lt 0){throw 'Addon Manager r10 marker missing.'}
foreach($required in @("data_policy='protect-ratings-tags-notes'","data_policy='never-disable-or-optimize'",'Assert-AddonTransactionRegistryAuthorization -Tx $tx','legacy-schema2-no-registry','registry-v1-authorized','Invoke-AddonRegistryCommitCycleSelfTest')){
    if($addonText.IndexOf($required,[StringComparison]::Ordinal) -lt 0){throw "r10 policy contract missing: $required"}
}
if(([regex]::Matches($addonText,"mutation_mode='auto'")).Count -ne 4){throw 'r10 automatic mutation authority count changed.'}
$u0=$addonText.IndexOf('function Update-AutoApps {',[StringComparison]::Ordinal);$u1=$addonText.IndexOf("`nfunction ",$u0+1,[StringComparison]::Ordinal);$u=$addonText.Substring($u0,$u1-$u0)
foreach($bad in @('$item.source -eq "Pithaya/spicetify-apps-dist"','$item.source -eq "ivLis-Studio/ivLyrics"')){if($u.IndexOf($bad,[StringComparison]::Ordinal) -ge 0){throw "Hard-coded source mutation branch remains: $bad"}}
$r0=$addonText.IndexOf('function Rollback-LastTransaction {',[StringComparison]::Ordinal);$r1=$addonText.IndexOf("`nfunction ",$r0+1,[StringComparison]::Ordinal);$rb=$addonText.Substring($r0,$r1-$r0)
foreach($bad in @('Assert-AddonTransactionRegistryAuthorization','Get-AddonPolicyRegistryFingerprint','registry_sha256')){if($rb.IndexOf($bad,[StringComparison]::Ordinal) -ge 0){throw "Rollback became registry-dependent: $bad"}}

# v0.6.21 must not modify the already runtime-accepted performance trees.
git diff --quiet $Base HEAD -- performance/overlay
if($LASTEXITCODE -ne 0){throw 'performance/overlay changed in v0.6.21 release.'}
git diff --quiet $Base HEAD -- performance/star-ratings
if($LASTEXITCODE -ne 0){throw 'performance/star-ratings changed in v0.6.21 release.'}
$t=Get-Content performance/star-ratings/target.json -Raw|ConvertFrom-Json
if($t.target.expected_size -ne 43396 -or $t.target.expected_sha256 -ne '198fd7c3307de8f2efc36f40df4e79846188cf35a1d5b550ed3d8ab85e8139b1' -or $t.target.transformed_sha256 -ne '6e0d1c84408294a619d91191eec83a6d10794ef31093d31ccf1f1bd39ea8c8a3' -or $t.target.source_revision -ne '33aa3d293f9fbb58d7a749a8cea10c318351e6c6'){throw 'Star Ratings target contract changed.'}

Write-Host "V0621_RELEASE_CONTRACT_PASS source=$ExpectedSource payload=$ExpectedPayload main=$ExpectedMain addon=$ExpectedAddon agent=$ExpectedAgent"
