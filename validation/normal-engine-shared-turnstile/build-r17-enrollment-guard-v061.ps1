# V061 development-only guard COMPOSER over existing V060 stable-r17 candidate.
# Reuses existing reviewed V010 enrollment barrier *without* making a new
# engine authorization. The three V060-wrapped real mutators must check
# enrollment WHILE they hold their reentrant V047 OS FileShare.None lease,
# before any original transaction/backup/file/network side effect.
# Only GitHub-hosted Windows / RUNNER_TEMP; no user profile or installed files.
param([Parameter(Mandatory=$true)][string]$ParentCandidate,
      [Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
 $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
 $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
 [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
 throw 'V061_ENROLLMENT_COMPOSER_HOSTED_WINDOWS_ONLY'
}
$runner=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
$src=(Resolve-Path -LiteralPath $ParentCandidate).Path
$outputDir=[IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\','/')
if(-not$src.StartsWith(($runner+'\'),[StringComparison]::OrdinalIgnoreCase) -or
 [IO.Path]::GetFileName($src) -cne 'addon-manager-reentrant-V060-NONDEPLOY.ps1' -or
 -not$outputDir.StartsWith(($runner+'\'),[StringComparison]::OrdinalIgnoreCase) -or
 [IO.Directory]::Exists($outputDir) -or [IO.File]::Exists($outputDir)){
 throw 'V061_ENROLLMENT_COMPOSER_ONLY_FRESH_RUNNER_TEMP'
}
$bytes=[IO.File]::ReadAllBytes($src)
if($bytes.Length -lt 323385 -or $bytes.Length -gt 380000){
 throw 'V061_PARENT_CANDIDATE_FILE_SIZE_IMPLAUSIBLE'
}
$bom=if($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and
 $bytes[1] -eq 187 -and $bytes[2] -eq 191){3}else{0}
$utf8=[Text.UTF8Encoding]::new($false,$true)
$parent=$utf8.GetString($bytes,$bom,$bytes.Length-$bom)
$crlf=[string][char]13+[string][char]10
$lf=[string][char]10
$nl=if($parent.Contains($crlf)){$crlf}else{$lf}
$tok=$null;$err=$null
$oldAst=[Management.Automation.Language.Parser]::ParseInput($parent,[ref]$tok,[ref]$err)
if($err.Count){throw 'V061_V060_QUALIFIED_SOURCE_PARSE_FAILED'}
$all=@($oldAst.FindAll({param($node)
 $node -is [Management.Automation.Language.FunctionDefinitionAst]},$true))
$targets=@('Update-AutoApps','Commit-LastTransaction','Rollback-LastTransaction')
$insertions=New-Object 'System.Collections.Generic.List[object]'
# Source-derived V060 structure: exactly one top-level protected try after
# the OS-lease assignment; all original body statements are inside it.
$gate=$nl+'        [void](Assert-CustomAppNormalUpdateEngineExclusivityV010)'+$nl
if($parent.Contains('Assert-CustomAppNormalUpdateEngineExclusivityV010')){
 throw 'V061_V060_PARENT_ALREADY_CONTAINS_ENROLLMENT_GATE'
}
foreach($name in $targets){
 $found=@($all|Where-Object{$_.Name -ceq $name})
 if($found.Count -ne 1){throw ('V061_MUTATOR_NOT_UNIQUE_'+$name)}
 $f=$found[0]
 $statements=@($f.Body.EndBlock.Statements)
 $tries=@($statements|Where-Object{
   $_ -is [Management.Automation.Language.TryStatementAst]
 })
 if($statements.Count -ne 2 -or $tries.Count -ne 1 -or
    $statements[0] -isnot [Management.Automation.Language.AssignmentStatementAst] -or
    $statements[1] -isnot [Management.Automation.Language.TryStatementAst]){
   throw ('V061_V060_MUTATOR_NOT_EXACT_OUTER_LOCK_TRY_'+$name)
 }
 $before=[string]$statements[0].Extent.Text
 if(-not$before.Contains('Enter-CustomAppReentrantTurnstileV060')){
   throw ('V061_V060_MUTATOR_ENTER_NOT_OUTSIDE_TRY_'+$name)
 }
 $block=[string]$tries[0].Body.Extent.Text
 if(-not$block.StartsWith('{') -or $block.Length -lt 10){
   throw ('V061_V060_TRY_BODY_NOT_EXPECTED_'+$name)
 }
 $pos=[int]$tries[0].Body.Extent.StartOffset+1
 $insertions.Add([pscustomobject]@{position=$pos;text=$gate;name=$name})
}
$wrapped=$parent
foreach($x in @($insertions|Sort-Object position -Descending)){
 $wrapped=$wrapped.Insert([int]$x.position,[string]$x.text)
}
# Exact inverse: composition changes only three bounded insertion spans.
$inverse=$wrapped
foreach($x in @($insertions|Sort-Object position)){
 $offset=[int]$x.position
 if($inverse.Substring($offset,$gate.Length) -cne $gate){
   throw 'V061_INSERTION_NOT_EXACTLY_REVERSIBLE'
 }
 $inverse=$inverse.Remove($offset,$gate.Length)
}
if($inverse -cne $parent){throw 'V061_OTHER_V060_CANDIDATE_BYTES_CHANGED'}
# Qualified old/new engine incompatibility barrier existed in the repo,
# and is read-only. Use only the precise reviewed function AST, not its
# test entrypoint or any other source at import time.
$v010Path=Join-Path $PSScriptRoot '..\custom-app-normal-entrypoint-transaction-integration\normal-update-engine-fence.ps1'
if(-not[IO.File]::Exists($v010Path)){throw 'V061_V010_REVIEWED_MODULE_UNAVAILABLE'}
$v010Bytes=[IO.File]::ReadAllBytes($v010Path)
if($v010Bytes.Length -lt 2500 -or $v010Bytes.Length -gt 8000){
 throw 'V061_V010_REVIEWED_MODULE_LENGTH_DRIFT'
}
$v010Text=$utf8.GetString($v010Bytes)
$oldToken=$null;$oldErrors=$null
$gateAst=[Management.Automation.Language.Parser]::ParseInput($v010Text,[ref]$oldToken,[ref]$oldErrors)
if($oldErrors.Count){throw 'V061_EXISTING_V010_GATE_SOURCE_PARSE_FAILED'}
$gateFns=@($gateAst.FindAll({param($node)
 $node -is [Management.Automation.Language.FunctionDefinitionAst]},$true)|
 Where-Object{$_.Name -ceq 'Assert-CustomAppNormalUpdateEngineExclusivityV010'})
if($gateFns.Count -ne 1){throw 'V061_EXISTING_V010_ENROLLMENT_FUNCTION_NOT_UNIQUE'}
$gateFn=[string]$gateFns[0].Extent.Text
foreach($required in @(
 'SpotifyControlUpdates-CustomApp-State',
 'normal-update-engine-gate-dpapi-enrollment-present-requires-journal-recovery-or-migration',
 'journal_engine_enrollment_seen=$false',
 'production_mutation_authorized=$false',
 'normal-update-engine-gate-test-override-not-hosted')){
 if(-not$gateFn.Contains($required)){
  throw ('V061_REVIEWED_V010_GATE_NO_LONGER_HAS_REQUIRED_DENIAL_'+$required)
 }
}
$gateNormalized=$gateFn.Replace($crlf,$lf).Replace($lf,$nl)
$gatePayload=$gateNormalized+$nl+$nl
$anchor='function Test-Due {'
if(($wrapped.Split([string[]]@($anchor),[StringSplitOptions]::None)).Count -ne 2){
 throw 'V061_EXACT_GATE_HELPER_ANCHOR_MISSING'
}
$final=$wrapped.Replace($anchor,$gatePayload+$anchor)
if(($final.Split([string[]]@($gatePayload),[StringSplitOptions]::None)).Count -ne 2 -or
  $final.Replace($gatePayload,'') -cne $wrapped){
 throw 'V061_EXTRA_GATE_FUNCTION_NOT_BYTE_REVERSIBLE'
}
$tokens=$null;$parseErrors=$null
$newAst=[Management.Automation.Language.Parser]::ParseInput($final,[ref]$tokens,[ref]$parseErrors)
if($parseErrors.Count){throw ('V061_FINAL_PS51_PARSE_FAILED_'+$parseErrors[0].Message)}
$newFns=@($newAst.FindAll({param($node)
 $node -is [Management.Automation.Language.FunctionDefinitionAst]},$true))
if($newFns.Count -ne $all.Count+1){throw 'V061_ORIGINAL_V060_FUNCTION_COUNT_NOT_PRESERVED'}
$extra=@($newFns|Where-Object{$_.Name -ceq 'Assert-CustomAppNormalUpdateEngineExclusivityV010'})
if($extra.Count -ne 1 -or
  [string]$extra[0].Extent.Text -cne $gateNormalized){
 throw 'V061_V010_GATE_FUNCTION_NOT_EXACTLY_INJECTED'
}
foreach($old in $all){
 $new=@($newFns|Where-Object{$_.Name -ceq $old.Name})
 if($new.Count -ne @($all|Where-Object{$_.Name -ceq $old.Name}).Count){
   throw ('V061_ORIGINAL_FUNCTION_MULTIPLICITY_CHANGED_'+$old.Name)
 }
 if($old.Name -cin $targets){continue}
 # Original modules have some duplicate helper names; compare the
 # matching definition's document-order occurrence instead of collapsing.
 $index=@($all|Where-Object{$_.Name -ceq $old.Name}).IndexOf($old)
 if($index -lt 0 -or
    [string]$new[$index].Extent.Text -cne [string]$old.Extent.Text){
   throw ('V061_UNRELATED_FUNCTION_TEXT_CHANGED_'+$old.Name)
 }
}
foreach($name in $targets){
 $new=@($newFns|Where-Object{$_.Name -ceq $name})
 if($new.Count -ne 1){throw 'V061_TARGET_MUTATOR_COUNT_CHANGED'}
 $body=[string]$new[0].Body.Extent.Text
 $lease=$body.IndexOf('Enter-CustomAppReentrantTurnstileV060',[StringComparison]::Ordinal)
 $guard=$body.IndexOf('Assert-CustomAppNormalUpdateEngineExclusivityV010',[StringComparison]::Ordinal)
 $effect=if($name -ceq 'Update-AutoApps'){
   $body.IndexOf('Get-Process Spotify',[StringComparison]::Ordinal)
 }else{
   $body.IndexOf('Test-PathSafe',[StringComparison]::Ordinal)
 }
 if($lease -lt 0 -or $guard -le $lease -or $effect -le $guard -or
    -not$body.Contains('Exit-CustomAppReentrantTurnstileV060 -Token $__leaseV060')){
   throw ('V061_ENROLLMENT_NOT_INSIDE_LEASE_BEFORE_EFFECT_'+$name)
 }
}
[void][IO.Directory]::CreateDirectory($outputDir)
$out=Join-Path $outputDir 'addon-manager-reentrant-enrollment-V061-NONDEPLOY.ps1'
$encoded=$utf8.GetBytes($final)
$allBytes=if($bom -eq 3){
 $buffer=New-Object byte[] ($encoded.Length+3)
 [Array]::Copy([byte[]]@(239,187,191),0,$buffer,0,3)
 [Array]::Copy($encoded,0,$buffer,3,$encoded.Length)
 $buffer
}else{$encoded}
$stream=[IO.File]::Open($out,[IO.FileMode]::CreateNew,
  [IO.FileAccess]::Write,[IO.FileShare]::None)
try{
 $stream.Write($allBytes,0,$allBytes.Length)
 $stream.Flush($true)
}finally{$stream.Dispose()}
if([IO.File]::ReadAllBytes($out).Length -ne $allBytes.Length){
 throw 'V061_FINAL_DISK_OUTPUT_BYTE_COUNT_CHANGED'
}
Write-Host 'V061_EXACT_V060_PARENT_CANDIDATE_INVERSE_3_GUARDS_BYTE_PRESERVED_PASS'
Write-Host 'V061_EXISTING_V010_ENROLLMENT_GATE_EXACT_REUSED_IN_ALL_3_MUTATORS_PASS'
Write-Host 'V061_V047_OS_LEASE_THEN_V010_FAIL_CLOSED_BEFORE_ANY_OLD_SIDE_EFFECT_PASS'
Write-Host 'V061_NONDEPLOY_GUARDED_CANDIDATE_ONLY_IN_HOSTED_RUNNER_TEMP_PASS'
