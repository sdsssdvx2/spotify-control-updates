# Main-program enrollment admission, development-only and source-pinned.
# Complements the V061/V062 Addon Manager function gates by blocking canonical
# Spotify Control maintenance BEFORE it starts, and rechecking when the normal
# maintenance check phase hands off to the main mutation phase. It does NOT
# serialize already-running, unpatched or manually copied Spotify Control.
# This is NOT a source replacement or production cutover controller.
param([Parameter(Mandatory=$true)][string]$ParentMain,
      [Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
 $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
 $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
 [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
 throw 'MAIN_PREFLIGHT_HOSTED_WINDOWS_ONLY'
}
$runner=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
$src=(Resolve-Path -LiteralPath $ParentMain).Path
$dir=[IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\','/')
# Input is the independently SHA-pinned reconstruction, never installed code.
if([IO.Path]::GetFileName($src) -cne 'spotify-control.ps1' -or
 -not$dir.StartsWith(($runner+'\'),[StringComparison]::OrdinalIgnoreCase) -or
 [IO.Directory]::Exists($dir) -or [IO.File]::Exists($dir)){
 throw 'MAIN_PREFLIGHT_RECONSTRUCTED_SOURCE_AND_PRIVATE_OUTPUT_REQUIRED'
}
$raw=[IO.File]::ReadAllBytes($src)
$sha=(Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash.ToLowerInvariant()
if($raw.Length -ne 284321 -or
 $sha -cne 'af1582ec335807f8f5daa9b3a65b13d567264f326d3c608c082ae02ff0a4cfc0'){
 throw 'MAIN_PREFLIGHT_EXACT_V0628_MAIN_PIN_REQUIRED'
}
$bom=if($raw.Length -ge 3 -and $raw[0] -eq 239 -and
 $raw[1] -eq 187 -and $raw[2] -eq 191){3}else{0}
$utf8=[Text.UTF8Encoding]::new($false,$true)
$original=$utf8.GetString($raw,$bom,$raw.Length-$bom)
$crlf=[string][char]13+[string][char]10
$lf=[string][char]10
$nl=if($original.Contains($crlf)){$crlf}else{$lf}
$tokens=$null;$parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($original,[ref]$tokens,[ref]$parseErrors)
if($parseErrors.Count -ne 0 -or $null-eq$ast.ParamBlock -or
 @($ast.UsingStatements).Count -ne 0){
 throw 'MAIN_PREFLIGHT_SCRIPT_HEADER_STRUCTURE_UNEXPECTED'
}
$oldFns=@($ast.FindAll({param($node)
 $node -is [Management.Automation.Language.FunctionDefinitionAst]},$true))
if(@($oldFns|Where-Object{$_.Name -ceq 'Assert-CustomAppNormalUpdateEngineExclusivityV010'}).Count -ne 0){
 throw 'MAIN_PREFLIGHT_ALREADY_ENROLLED_WITH_GATE'
}
$mutation=@($oldFns|Where-Object{$_.Name -ceq 'Invoke-MaintenanceMutationPhase'})
if($mutation.Count -ne 1){throw 'MAIN_PREFLIGHT_MUTATION_PHASE_NOT_UNIQUE'}
$phase=$mutation[0]
# This is a START admission and a second check-phase->mutation boundary.
# We intentionally do not open V047 over the entire main parent process:
# its Addon Manager child needs that exact OS-exclusive handle.
$v010=Join-Path $PSScriptRoot '..\custom-app-normal-entrypoint-transaction-integration\normal-update-engine-fence.ps1'
$source=[IO.File]::ReadAllText($v010,$utf8)
$gt=$null;$ge=$null
$gateAst=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$gt,[ref]$ge)
if($ge.Count){throw 'MAIN_PREFLIGHT_REVIEWED_V010_PARSE_FAILED'}
$gateFn=@($gateAst.FindAll({param($node)
 $node -is [Management.Automation.Language.FunctionDefinitionAst]},$true) |
 Where-Object{$_.Name -ceq 'Assert-CustomAppNormalUpdateEngineExclusivityV010'})
if($gateFn.Count -ne 1){throw 'MAIN_PREFLIGHT_EXACT_EXISTING_V010_FUNCTION_NOT_FOUND'}
$fnText=[string]$gateFn[0].Extent.Text
foreach($required in @(
 'SpotifyControlUpdates-CustomApp-State',
 'normal-update-engine-gate-dpapi-enrollment-present-requires-journal-recovery-or-migration',
 'journal_engine_enrollment_seen=$false',
 'production_mutation_authorized=$false',
 'normal-update-engine-gate-test-override-not-hosted')){
 if(-not$fnText.Contains($required)){
  throw ('MAIN_PREFLIGHT_V010_GATE_CONTRACT_DRIFT_'+$required)
 }
}
$fnNormalized=$fnText.Replace($crlf,$lf).Replace($lf,$nl)
# Inject gate definition and one top-level execution BEFORE EVERY ORIGINAL
# executable statement, not merely before a late action-dispatch switch.
$startText=$nl+$fnNormalized+$nl+
 '[void](Assert-CustomAppNormalUpdateEngineExclusivityV010)'+$nl
$recheckText=$nl+
 '    [void](Assert-CustomAppNormalUpdateEngineExclusivityV010)'+$nl
$entry=[int]$ast.ParamBlock.Extent.EndOffset
$phaseEntry=if($null-ne$phase.Body.ParamBlock){
 [int]$phase.Body.ParamBlock.Extent.EndOffset
}else{[int]$phase.Body.Extent.StartOffset+1}
if($entry -ge $phaseEntry -or $phaseEntry -ge [int]$phase.Body.Extent.EndOffset-1){
 throw 'MAIN_PREFLIGHT_AST_INSERTION_RANGES_INVALID'
}
$patches=@(
 [pscustomobject]@{offset=$entry;text=$startText;label='startup'},
 [pscustomobject]@{offset=$phaseEntry;text=$recheckText;label='mutation'}
)
$final=$original
foreach($p in @($patches|Sort-Object offset -Descending)){
 $final=$final.Insert([int]$p.offset,[string]$p.text)
}
$inverse=$final
foreach($p in @($patches|Sort-Object offset)){
 $position=[int]$p.offset;$needle=[string]$p.text
 if($inverse.Substring($position,$needle.Length) -cne $needle){
  throw ('MAIN_PREFLIGHT_INSERTION_NOT_REVERSIBLE_'+[string]$p.label)
 }
 $inverse=$inverse.Remove($position,$needle.Length)
}
if($inverse -cne $original){throw 'MAIN_PREFLIGHT_STABLE_MAIN_ORIGINAL_TEXT_CHANGED'}
$nt=$null;$ne=$null
$newAst=[Management.Automation.Language.Parser]::ParseInput($final,[ref]$nt,[ref]$ne)
if($ne.Count){throw ('MAIN_PREFLIGHT_CANDIDATE_PS51_PARSE_FAILED_'+$ne[0].Message)}
$newFns=@($newAst.FindAll({param($node)
 $node -is [Management.Automation.Language.FunctionDefinitionAst]},$true))
if($newFns.Count -ne $oldFns.Count+1){throw 'MAIN_PREFLIGHT_FUNCTION_COUNT_DRIFT'}
$rewritten=@($newFns|Where-Object{$_.Name -ceq 'Invoke-MaintenanceMutationPhase'})
if($rewritten.Count -ne 1 -or
 -not([string]$rewritten[0].Body.Extent.Text).Contains('Assert-CustomAppNormalUpdateEngineExclusivityV010')){
 throw 'MAIN_PREFLIGHT_MUTATION_SECOND_GATE_MISSING'
}
foreach($old in $oldFns){
 if($old.Name -ceq 'Invoke-MaintenanceMutationPhase'){continue}
 $matched=@($newFns|Where-Object{$_.Name -ceq $old.Name})
 if($matched.Count -ne @($oldFns|Where-Object{$_.Name -ceq $old.Name}).Count){
   throw ('MAIN_PREFLIGHT_OLD_FUNCTION_MULTIPLICITY_CHANGED_'+$old.Name)
 }
 $idx=@($oldFns|Where-Object{$_.Name -ceq $old.Name}).IndexOf($old)
 if($idx -lt 0 -or [string]$matched[$idx].Extent.Text -cne [string]$old.Extent.Text){
   throw ('MAIN_PREFLIGHT_UNRELATED_STABLE_MAIN_FUNCTION_CHANGED_'+$old.Name)
 }
}
$injected=@($newFns|Where-Object{$_.Name -ceq 'Assert-CustomAppNormalUpdateEngineExclusivityV010'})
if($injected.Count -ne 1 -or [string]$injected[0].Extent.Text -cne $fnNormalized){
 throw 'MAIN_PREFLIGHT_EXISTING_REVIEWED_V010_NOT_IDENTICAL'
}
# Function declaration is followed by a top-level guard; original
# executable statements cannot be reached before it.
$topStatements=@($newAst.EndBlock.Statements|Where-Object{
 $_ -isnot [Management.Automation.Language.FunctionDefinitionAst]
})
if($topStatements.Count -lt 2 -or
 [string]$topStatements[0].Extent.Text -cne
 '[void](Assert-CustomAppNormalUpdateEngineExclusivityV010)'){
 throw 'MAIN_PREFLIGHT_TOP_LEVEL_GUARD_NOT_FIRST_EXECUTED_STATEMENT'
}
[void][IO.Directory]::CreateDirectory($dir)
$file=Join-Path $dir 'spotify-control-enrollment-preflight-NONDEPLOY.ps1'
$out=$utf8.GetBytes($final)
if($bom -eq 3){$out=[byte[]]@(239,187,191)+$out}
$h=[IO.File]::Open($file,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try{$h.Write($out,0,$out.Length);$h.Flush($true)}finally{$h.Dispose()}
$openedT=$null;$openedE=$null
[void][Management.Automation.Language.Parser]::ParseFile($file,[ref]$openedT,[ref]$openedE)
if($openedE.Count){throw 'MAIN_PREFLIGHT_PUBLISHED_CANDIDATE_PARSE_FAILURE'}
Write-Host 'MAIN_PREFLIGHT_EXACT_PINNED_MAIN_SOURCE_INVERSE_AND_UNRELATED_FUNCTIONS_PASS'
Write-Host 'MAIN_PREFLIGHT_FIRST_TOP_LEVEL_STATEMENT_EXISTING_V010_ENROLLMENT_GUARD_PASS'
Write-Host 'MAIN_PREFLIGHT_CHECK_TO_MUTATION_BOUNDARY_RECHECK_PASS'
Write-Host 'MAIN_PREFLIGHT_NONDEPLOY_MAIN_NO_PRODUCTION_OPERATIONS_PASS'
