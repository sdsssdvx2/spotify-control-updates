# V062 HOLD: apply the existing V047/V060/V010 cooperative guard to the
# two auxiliary XPUI writers discovered outside the three V061 transactions.
# Input must be the freshly verified V061 synthetic Windows candidate.
# Output is NONDEPLOY in a new private RUNNER_TEMP path; never runs r17.
param(
 [Parameter(Mandatory=$true)][string]$ParentCandidate,
 [Parameter(Mandatory=$true)][string]$OutputDirectory
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
   $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
  throw 'V062_HOSTED_WINDOWS_ONLY'
}
$root=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
$source=(Resolve-Path -LiteralPath $ParentCandidate).Path
$outdir=[IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\','/')
if(-not$source.StartsWith(($root+'\'),[StringComparison]::OrdinalIgnoreCase) -or
 [IO.Path]::GetFileName($source) -cne 'addon-manager-reentrant-enrollment-V061-NONDEPLOY.ps1' -or
 -not$outdir.StartsWith(($root+'\'),[StringComparison]::OrdinalIgnoreCase) -or
 [IO.File]::Exists($outdir) -or [IO.Directory]::Exists($outdir)){
 throw 'V062_ONLY_FRESH_RUNNER_TEMP_INPUT_OUTPUT'
}
$bytes=[IO.File]::ReadAllBytes($source)
if($bytes.Length -lt 323385 -or $bytes.Length -gt 390000){
 throw 'V062_V061_PARENT_SIZE_IMPLAUSIBLE'
}
$bom=if($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and
 $bytes[1] -eq 187 -and $bytes[2] -eq 191){3}else{0}
$utf8=New-Object Text.UTF8Encoding($false,$true)
$original=$utf8.GetString($bytes,$bom,$bytes.Length-$bom)
$crlf=[string][char]13+[string][char]10
$lf=[string][char]10
$nl=if($original.Contains($crlf)){$crlf}else{$lf}
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($original,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'V062_PARENT_PS51_PARSE_FAILED'}
$functions=@($ast.FindAll({param($node)
 $node -is [Management.Automation.Language.FunctionDefinitionAst]},$true))
$targets=@('Invoke-PerformanceOverlayBestEffort','Invoke-StarRatingsPerformanceBestEffort')
$oldProtected=@('Update-AutoApps','Rollback-LastTransaction','Commit-LastTransaction')
foreach($name in $oldProtected){
 $found=@($functions|Where-Object{$_.Name -ceq $name})
 if($found.Count -ne 1 -or
    -not([string]$found[0].Body.Extent.Text).Contains('Enter-CustomAppReentrantTurnstileV060') -or
    -not([string]$found[0].Body.Extent.Text).Contains('Assert-CustomAppNormalUpdateEngineExclusivityV010')){
  throw ('V062_V061_PREEXISTING_MUTATOR_GATE_MISSING_'+$name)
 }
}
$helper=@($functions|Where-Object{$_.Name -ceq 'Assert-CustomAppNormalUpdateEngineExclusivityV010'})
if($helper.Count -ne 1){throw 'V062_V010_FUNCTION_NOT_UNIQUE'}
$open=$nl+'    $__auxLeaseV062 = Enter-CustomAppReentrantTurnstileV060'+$nl+
 '    try {'+$nl+
 '        [void](Assert-CustomAppNormalUpdateEngineExclusivityV010)'+$nl
$close=$nl+'    } finally {'+$nl+
 '        Exit-CustomAppReentrantTurnstileV060 -Token $__auxLeaseV062'+$nl+
 '    }'+$nl
if($original.Contains('$__auxLeaseV062')){
 throw 'V062_PARENT_ALREADY_CONTAINS_AUXILIARY_LEASE'
}
$edits=New-Object 'System.Collections.Generic.List[object]'
foreach($name in $targets){
 $found=@($functions|Where-Object{$_.Name -ceq $name})
 if($found.Count -ne 1){throw ('V062_AUX_WRITER_NOT_UNIQUE_'+$name)}
 $f=$found[0]
 $body=[string]$f.Body.Extent.Text
 if($body.Length -lt 120 -or -not$body.Contains('Reason')){
  throw ('V062_AUX_WRITER_BODY_UNEXPECTED_'+$name)
 }
 $begin=if($null-ne$f.Body.ParamBlock){
  [int]$f.Body.ParamBlock.Extent.EndOffset
 }else{[int]$f.Body.Extent.StartOffset+1}
 $end=[int]$f.Body.Extent.EndOffset-1
 if($begin -ge $end -or $begin -le [int]$f.Body.Extent.StartOffset){
   throw ('V062_AUX_WRITER_AST_RANGE_INVALID_'+$name)
 }
 $edits.Add([pscustomobject]@{position=$begin;content=$open;name=$name+'-enter'})
 $edits.Add([pscustomobject]@{position=$end;content=$close;name=$name+'-exit'})
}
$final=$original
foreach($item in @($edits|Sort-Object position -Descending)){
 $final=$final.Insert([int]$item.position,[string]$item.content)
}
$inverse=$final
foreach($item in @($edits|Sort-Object position)){
 $pos=[int]$item.position;$needle=[string]$item.content
 if($inverse.Substring($pos,$needle.Length) -cne $needle){
   throw ('V062_NOT_EXACTLY_INVERTIBLE_'+$item.name)
 }
 $inverse=$inverse.Remove($pos,$needle.Length)
}
if($inverse -cne $original){throw 'V062_V061_PARENT_SOURCE_CHANGED'}
$newTokens=$null;$newErrors=$null
$newAst=[Management.Automation.Language.Parser]::ParseInput($final,[ref]$newTokens,[ref]$newErrors)
if($newErrors.Count){throw ('V062_FINAL_PS51_PARSE_FAILED_'+$newErrors[0].Message)}
$newFunctions=@($newAst.FindAll({param($node)
 $node -is [Management.Automation.Language.FunctionDefinitionAst]},$true))
if($newFunctions.Count -ne $functions.Count){
 throw 'V062_FUNCTION_COUNT_CHANGED'
}
for($i=0;$i -lt $functions.Count;$i++){
 $prior=$functions[$i];$now=$newFunctions[$i]
 if($prior.Name -cne $now.Name){throw 'V062_FUNCTION_ORDER_CHANGED'}
 if($prior.Name -cnotin $targets -and
    [string]$prior.Extent.Text -cne [string]$now.Extent.Text){
    throw ('V062_UNRELATED_FUNCTION_CHANGED_'+$prior.Name)
 }
}
foreach($name in $targets){
 $now=@($newFunctions|Where-Object{$_.Name -ceq $name})
 $body=[string]$now[0].Body.Extent.Text
 $enter=$body.IndexOf('Enter-CustomAppReentrantTurnstileV060',[StringComparison]::Ordinal)
 $gate=$body.IndexOf('Assert-CustomAppNormalUpdateEngineExclusivityV010',[StringComparison]::Ordinal)
 $exit=$body.LastIndexOf('Exit-CustomAppReentrantTurnstileV060',[StringComparison]::Ordinal)
 if($enter -lt 0 -or $gate -le $enter -or $exit -le $gate){
  throw ('V062_AUX_GUARD_SEQUENCE_INVALID_'+$name)
 }
}
[void][IO.Directory]::CreateDirectory($outdir)
$output=Join-Path $outdir 'addon-manager-auxiliary-gated-V062-NONDEPLOY.ps1'
$bodyBytes=$utf8.GetBytes($final)
$all=if($bom -eq 3){[byte[]]@(239,187,191)+$bodyBytes}else{$bodyBytes}
$h=[IO.File]::Open($output,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try{$h.Write($all,0,$all.Length);$h.Flush($true)}finally{$h.Dispose()}
$freshTokens=$null;$freshErr=$null
[void][Management.Automation.Language.Parser]::ParseFile($output,[ref]$freshTokens,[ref]$freshErr)
if($freshErr.Count){throw 'V062_WRITTEN_FILE_PS51_PARSE_FAILED'}
Write-Host 'V062_EXACT_V061_PARENT_PRESERVED_ALL_UNRELATED_FUNCTIONS_PASS'
Write-Host 'V062_BOTH_AUX_XPUI_WRITERS_REENTRANT_LOCK_AND_ENROLLMENT_GATED_PASS'
Write-Host 'V062_HOSTED_NONDEPLOY_NO_REAL_SPOTIFY_OR_USER_PROFILE_PASS'
