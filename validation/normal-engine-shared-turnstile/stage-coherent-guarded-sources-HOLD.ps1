# Single coherent (two-source) nondeployment bundle from EXACT source-pinned
# stable Spotify Control v0.6.28 + Addon Manager r17. Earlier validation
# stages provide the actual generated guarded candidates, this script only
# binds them together with SHA-256 and verifies the cross-process contract.
# No installed profile, user scheduler, local data, Spicetify or network use.
param(
 [Parameter(Mandatory=$true)][string]$OriginalMain,
 [Parameter(Mandatory=$true)][string]$OriginalAddon,
 [Parameter(Mandatory=$true)][string]$GuardedMain,
 [Parameter(Mandatory=$true)][string]$GuardedAddon,
 [Parameter(Mandatory=$true)][string]$OutputDirectory
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
 $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
 $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
 [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
 throw 'GUARDED_BUNDLE_GITHUB_HOSTED_WINDOWS_ONLY'
}
function Assert-BundleTrue([bool]$Ok,[string]$Reason){
 if(-not$Ok){throw ('GUARDED_BUNDLE_'+$Reason)}
}
$runner=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
$outdir=[IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\','/')
Assert-BundleTrue ($outdir.StartsWith(($runner+'\'),[StringComparison]::OrdinalIgnoreCase) -and
 -not[IO.File]::Exists($outdir) -and -not[IO.Directory]::Exists($outdir)) 'OUTPUT_MUST_BE_NEW_PRIVATE_DIRECTORY'
$originalMainPath=(Resolve-Path -LiteralPath $OriginalMain).Path
$originalAddonPath=(Resolve-Path -LiteralPath $OriginalAddon).Path
$mainPath=(Resolve-Path -LiteralPath $GuardedMain).Path
$addonPath=(Resolve-Path -LiteralPath $GuardedAddon).Path
Assert-BundleTrue (
 [IO.Path]::GetFileName($originalMainPath) -ceq 'spotify-control.ps1' -and
 [IO.Path]::GetFileName($originalAddonPath) -ceq 'addon-manager.ps1' -and
 [IO.Path]::GetFileName($mainPath) -ceq 'spotify-control-enrollment-preflight-NONDEPLOY.ps1' -and
 [IO.Path]::GetFileName($addonPath) -ceq 'addon-manager-auxiliary-gated-V062-NONDEPLOY.ps1' -and
 $mainPath.StartsWith(($runner+'\'),[StringComparison]::OrdinalIgnoreCase) -and
 $addonPath.StartsWith(($runner+'\'),[StringComparison]::OrdinalIgnoreCase)
) 'EXACT_SOURCE_OR_CANDIDATE_PATH_EXPECTED'
$oldMainHash='af1582ec335807f8f5daa9b3a65b13d567264f326d3c608c082ae02ff0a4cfc0'
$oldAddonHash='5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285'
function Get-BundleSha([string]$Path){
 return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}
Assert-BundleTrue (
 (Get-BundleSha $originalMainPath) -ceq $oldMainHash -and
 (Get-BundleSha $originalAddonPath) -ceq $oldAddonHash -and
 (Get-Item -LiteralPath $originalMainPath).Length -eq 284321 -and
 (Get-Item -LiteralPath $originalAddonPath).Length -eq 323385
) 'EXACT_STABLE_BASELINE_SOURCE_SHA_AND_SIZE'
$utf8=[Text.UTF8Encoding]::new($false,$true)
function Read-BundleAst([string]$Path){
 $tokens=$null;$parseErrors=$null
 $ast=[Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$parseErrors)
 if($parseErrors.Count -ne 0){throw 'GUARDED_BUNDLE_CANDIDATE_POWERSHELL_51_SYNTAX_INVALID'}
 return $ast
}
$oldMainAst=Read-BundleAst $originalMainPath
$oldAddonAst=Read-BundleAst $originalAddonPath
$mainAst=Read-BundleAst $mainPath
$addonAst=Read-BundleAst $addonPath
function Get-BundleFunctions($Ast){
 return @($Ast.FindAll({param($node)
   $node -is [Management.Automation.Language.FunctionDefinitionAst]},$true))
}
$oldM=Get-BundleFunctions $oldMainAst
$oldA=Get-BundleFunctions $oldAddonAst
$newM=Get-BundleFunctions $mainAst
$newA=Get-BundleFunctions $addonAst
Assert-BundleTrue (
 $newM.Count -eq ($oldM.Count+1) -and $newA.Count -eq ($oldA.Count+5)
) 'QUALIFIED_FUNCTION_COUNTS_OR_PARENT_CHANGED'
$top=@($mainAst.EndBlock.Statements|Where-Object{
 $_ -isnot [Management.Automation.Language.FunctionDefinitionAst]
})
Assert-BundleTrue ($top.Count -ge 2 -and
 [string]$top[0].Extent.Text -ceq
 '[void](Assert-CustomAppNormalUpdateEngineExclusivityV010)') 'MAIN_FIRST_EXECUTION_NOT_ENROLLMENT_GATED'
$mainMutation=@($newM|Where-Object{$_.Name -ceq 'Invoke-MaintenanceMutationPhase'})
Assert-BundleTrue (
 $mainMutation.Count -eq 1 -and
 [string]$mainMutation[0].Body.Extent.Text -cmatch
 'Assert-CustomAppNormalUpdateEngineExclusivityV010'
) 'MAIN_MAINTENANCE_CHECK_TO_MUTATION_GATE_MISSING'
$five=@('Update-AutoApps','Rollback-LastTransaction','Commit-LastTransaction',
 'Invoke-PerformanceOverlayBestEffort','Invoke-StarRatingsPerformanceBestEffort')
foreach($name in $five){
 $set=@($newA|Where-Object{$_.Name -ceq $name})
 Assert-BundleTrue ($set.Count -eq 1) ('ADDON_FUNCTION_NOT_UNIQUE_'+$name)
 $b=[string]$set[0].Body.Extent.Text
 $enter=$b.IndexOf('Enter-CustomAppReentrantTurnstileV060',[StringComparison]::Ordinal)
 $gate=$b.IndexOf('Assert-CustomAppNormalUpdateEngineExclusivityV010',[StringComparison]::Ordinal)
 $exit=$b.LastIndexOf('Exit-CustomAppReentrantTurnstileV060',[StringComparison]::Ordinal)
 Assert-BundleTrue ($enter -ge 0 -and $gate -gt $enter -and $exit -gt $gate) (
  'ADDON_REQUIRED_LEASE_AND_ENROLLMENT_WRAPPER_MISSING_'+$name
 )
}
foreach($fn in @(
 'Assert-CustomAppNormalUpdateEngineExclusivityV010',
 'Enter-CustomAppEngineTurnstileV047',
 'Enter-CustomAppReentrantTurnstileV060',
 'Exit-CustomAppReentrantTurnstileV060',
 'Assert-CustomAppReentrantLeaseInvariantV060')){
 $target=if($fn -ceq 'Assert-CustomAppNormalUpdateEngineExclusivityV010'){$newM}else{$newA}
 Assert-BundleTrue (@($target|Where-Object{$_.Name -ceq $fn}).Count -eq 1) (
  'COHERENT_INTERFACE_NOT_UNIQUE_'+$fn)
}
# Source-preservation checks are performed at the individual composer stages.
# Here independently attest every original named function present in its
# corresponding staged candidate, except the explicitly rewritten functions.
foreach($item in @(
 [pscustomobject]@{old=$oldM;new=$newM;skip=@('Invoke-MaintenanceMutationPhase');label='MAIN'},
 [pscustomobject]@{old=$oldA;new=$newA;skip=$five;label='ADDON'}
)){
 foreach($f in $item.old){
  if($f.Name -cin $item.skip){continue}
  $matches=@($item.new|Where-Object{$_.Name -ceq $f.Name})
  Assert-BundleTrue ($matches.Count -eq 1 -and
     [string]$matches[0].Extent.Text -ceq [string]$f.Extent.Text) (
     'UNRELATED_'+$item.label+'_FUNCTION_DRIFT_'+$f.Name)
 }
}
# Keep other installed files (including resident .vbs agent, existing
# settings, themes and custom apps) entirely OUTSIDE this source-only bundle.
$bin=Join-Path $outdir 'bin'
[void][IO.Directory]::CreateDirectory($bin)
$destM=Join-Path $bin 'spotify-control.ps1'
$destA=Join-Path $bin 'addon-manager.ps1'
foreach($pair in @(
 [pscustomobject]@{from=$mainPath;to=$destM},
 [pscustomobject]@{from=$addonPath;to=$destA}
)){
 $src=[IO.File]::Open([string]$pair.from,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
 try{
  $dst=[IO.File]::Open([string]$pair.to,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  try{
   $src.CopyTo($dst)
   $dst.Flush($true)
  }finally{$dst.Dispose()}
 }finally{$src.Dispose()}
 Assert-BundleTrue ((Get-BundleSha ([string]$pair.from)) -ceq
  (Get-BundleSha ([string]$pair.to))) 'BUNDLE_BYTE_COPY_MISMATCH'
}
$mainHash=Get-BundleSha $destM
$addonHash=Get-BundleSha $destA
Assert-BundleTrue (
 $mainHash -cnotmatch ('^'+$oldMainHash+'$') -and
 $addonHash -cnotmatch ('^'+$oldAddonHash+'$') -and
 (Get-Item $destM).Length -gt (Get-Item $originalMainPath).Length -and
 (Get-Item $destA).Length -gt (Get-Item $originalAddonPath).Length
) 'BUNDLE_HAS_UNCHANGED_OR_TRUNCATED_CANDIDATE'
$manifest=[ordered]@{
 schema=1
 owner='SpotifyControl-v0628-r17-guarded-source-HOLD'
 original_main_sha256=$oldMainHash
 original_addon_sha256=$oldAddonHash
 candidate_main_sha256=$mainHash
 candidate_addon_sha256=$addonHash
 main_file='bin/spotify-control.ps1'
 addon_file='bin/addon-manager.ps1'
 tested_main_entry_gate=$true
 tested_main_maintenance_phase_gate=$true
 addon_mutators_with_v047_lease_and_v010_gate=$five
 backup_and_transaction_cutover_implemented=$false
 manual_old_unpatched_execution_excluded=$false
 scheduler_swap_implemented=$false
 real_spotify_executed=$false
 production_mutation_authorized=$false
 deployable=$false
}
$json=($manifest|ConvertTo-Json -Compress -Depth 6)
$manifestPath=Join-Path $outdir 'MANIFEST-HOLD.json'
$bytes=$utf8.GetBytes($json)
$h=[IO.File]::Open($manifestPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try{$h.Write($bytes,0,$bytes.Length);$h.Flush($true)}finally{$h.Dispose()}
# Attest manifest off disk, check all fields and source pair together.
$loaded=([IO.File]::ReadAllText($manifestPath,$utf8)|ConvertFrom-Json -ErrorAction Stop)
Assert-BundleTrue ([int]$loaded.schema -eq 1 -and
 [string]$loaded.owner -ceq 'SpotifyControl-v0628-r17-guarded-source-HOLD' -and
 [string]$loaded.candidate_main_sha256 -ceq (Get-BundleSha $destM) -and
 [string]$loaded.candidate_addon_sha256 -ceq (Get-BundleSha $destA) -and
 -not[bool]$loaded.production_mutation_authorized -and
 -not[bool]$loaded.deployable) 'MANIFEST_RELOAD_AND_PAIR_SHA_MISMATCH'
Write-Host 'GUARDED_BUNDLE_EXACT_STABLE_MAIN_AND_R17_SOURCE_PROVENANCE_PASS'
Write-Host 'GUARDED_BUNDLE_MAIN_AND_FIVE_ADDON_MUTATORS_CROSS_FILE_GUARDS_PASS'
Write-Host 'GUARDED_BUNDLE_UNRELATED_ORIGINAL_FUNCTION_TEXT_PRESERVED_PASS'
Write-Host 'GUARDED_BUNDLE_TWO_CANDIDATE_FILE_SHA256_MANIFEST_RELOADED_PASS'
Write-Host 'GUARDED_BUNDLE_NONDEPLOY_ONLY_UNCHANGED_VBS_AND_USER_PROFILE_PASS'
