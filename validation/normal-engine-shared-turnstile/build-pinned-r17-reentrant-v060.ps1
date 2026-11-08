# V060 source-only, GitHub-hosted Windows acceptance builder.
# Insert exact nested-aware V060 -> V047 shared OS file lease around the
# THREE real production r17 mutators. Requires a byte-perfect stable r17
# SHA pin. Output exists only under RUNNER_TEMP; no install, source
# replacement, release, user data read, Spotify launch or process changes.
param([Parameter(Mandatory=$true)][string]$ParentCandidate,
      [Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   [Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
 throw 'V060_PINNED_BUILDER_HOSTED_WINDOWS_ONLY'
}
$src=(Resolve-Path -LiteralPath $ParentCandidate).Path
$sha='5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285'
$bytes=[IO.File]::ReadAllBytes($src)
if($bytes.Length -ne 323385 -or
 (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash.ToLowerInvariant() -cne $sha){
 throw 'V060_STABLE_R17_PARENT_BYTES_NOT_PINNED'
}
$runner=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
$destination=[IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\','/')
if(-not$destination.StartsWith(($runner+'\'),[StringComparison]::OrdinalIgnoreCase)){
 throw 'V060_OUTPUT_MUST_BE_PRIVATE_RUNNER_TEMP'
}
if([IO.Directory]::Exists($destination) -or
   [IO.File]::Exists($destination)){
 throw 'V060_OUTPUT_DIRECTORY_MUST_NOT_EXIST'
}
$bom=if($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and
         $bytes[1] -eq 187 -and $bytes[2] -eq 191){3}else{0}
$utf8=[Text.UTF8Encoding]::new($false,$true)
$original=$utf8.GetString($bytes,$bom,$bytes.Length-$bom)
$crlf=[string][char]13+[string][char]10
$lf=[string][char]10
$nl=if($original.Contains($crlf)){$crlf}else{$lf}
$tokens=$null;$parseErrors=$null
$oldAst=[Management.Automation.Language.Parser]::ParseInput($original,[ref]$tokens,[ref]$parseErrors)
if($parseErrors.Count){throw 'V060_ORIGINAL_R17_PS51_PARSE_FAILED'}
$oldFns=@($oldAst.FindAll({param($node)
 $node -is [Management.Automation.Language.FunctionDefinitionAst]},$true))
$targets=@('Update-AutoApps','Commit-LastTransaction','Rollback-LastTransaction')
$positions=New-Object 'System.Collections.Generic.List[object]'
$prefix=$nl+'    $__leaseV060 = Enter-CustomAppReentrantTurnstileV060'+$nl+
 '    try {'+$nl
$suffix=$nl+'    } finally {'+$nl+
 '        Exit-CustomAppReentrantTurnstileV060 -Token $__leaseV060'+$nl+
 '    }'+$nl
if($original.Contains('$__leaseV060') -or
   $original.Contains('Enter-CustomAppReentrantTurnstileV060') -or
   $original.Contains('Enter-CustomAppEngineTurnstileV047')){
 throw 'V060_UNEXPECTED_ALREADY_WRAPPED_STABLE_SOURCE'
}
foreach($name in $targets){
 $set=@($oldFns|Where-Object{$_.Name -ceq $name})
 if($set.Count -ne 1){throw ('V060_R17_MUTATOR_FUNCTION_NOT_UNIQUE_'+$name)}
 $f=$set[0]
 $begin=if($null-ne$f.Body.ParamBlock){
   [int]$f.Body.ParamBlock.Extent.EndOffset
 }else{
   [int]$f.Body.Extent.StartOffset+1
 }
 $end=[int]$f.Body.Extent.EndOffset-1
 if($begin -ge $end -or $begin -le [int]$f.Body.Extent.StartOffset){
   throw ('V060_MUTATOR_INVALID_AST_BODY_'+$name)
 }
 $body=[string]$f.Body.Extent.Text
 if($name -ceq 'Update-AutoApps' -and
    (-not$body.Contains('Rollback-LastTransaction') -or
     -not$body.Contains('Invoke-AtomicDirectorySwap'))){
   throw 'V060_STABLE_R17_NESTED_ROLLBACK_SCOPE_NOT_EXPECTED'
 }
 $positions.Add([pscustomobject]@{position=$begin;text=$prefix;label=$name+'-enter'})
 $positions.Add([pscustomobject]@{position=$end;text=$suffix;label=$name+'-exit'})
}
$wrapped=$original
foreach($p in @($positions|Sort-Object position -Descending)){
  $wrapped=$wrapped.Insert([int]$p.position,[string]$p.text)
}
$inverse=$wrapped
foreach($p in @($positions|Sort-Object position)){
 $i=[int]$p.position
 $needle=[string]$p.text
 if($inverse.Substring($i,$needle.Length) -cne $needle){
    throw ('V060_WRAPPER_INVERSE_BYTES_NOT_EXACT_'+[string]$p.label)
 }
 $inverse=$inverse.Remove($i,$needle.Length)
}
if($inverse -cne $original){throw 'V060_ANY_ORIGINAL_STABLE_R17_TEXT_CHANGED'}
$modulePaths=@(
 'engine-turnstile-v047.ps1',
 'reentrant-addon-turnstile-v060.ps1'
)
$parts=@()
foreach($name in $modulePaths){
 $path=Join-Path $PSScriptRoot $name
 $part=[IO.File]::ReadAllText($path,$utf8).Replace($crlf,$lf).TrimEnd()
 $parts+=($part.Replace($lf,$nl))
}
$modulePayload=($parts -join ($nl+$nl))+$nl+$nl
$anchor='function Test-Due {'
if(($wrapped.Split([string[]]@($anchor),[StringSplitOptions]::None)).Count -ne 2){
 throw 'V060_ADDON_HELPER_INSERTION_NOT_UNIQUE'
}
$final=$wrapped.Replace($anchor,$modulePayload+$anchor)
if(($final.Split([string[]]@($modulePayload),[StringSplitOptions]::None)).Count -ne 2 -or
    $final.Replace($modulePayload,'') -cne $wrapped){
 throw 'V060_MODULE_PAYLOAD_CANNOT_BE_INVERTED'
}
$newTokens=$null;$newErrors=$null
$newAst=[Management.Automation.Language.Parser]::ParseInput($final,[ref]$newTokens,[ref]$newErrors)
if($newErrors.Count){throw ('V060_CANDIDATE_PS51_PARSE_FAILED_'+$newErrors[0].Message)}
$newFns=@($newAst.FindAll({param($node)
 $node -is [Management.Automation.Language.FunctionDefinitionAst]},$true))
$names=@($oldFns|ForEach-Object{$_.Name})
$expected=@($names)+@(
 'Enter-CustomAppEngineTurnstileV047',
 'Enter-CustomAppReentrantTurnstileV060',
 'Exit-CustomAppReentrantTurnstileV060',
 'Assert-CustomAppReentrantLeaseInvariantV060'
)
if($newFns.Count -ne $expected.Count){
 throw 'V060_STABLE_SOURCE_FUNCTION_COUNT_CHANGED_UNEXPECTEDLY'
}
$actual=@($newFns|ForEach-Object{$_.Name})
if(@(Compare-Object ($actual|Sort-Object) ($expected|Sort-Object)).Count -ne 0){
 throw 'V060_STABLE_SOURCE_OR_NEW_MODULE_FUNCTION_NAME_DRIFT'
}
foreach($fn in $oldFns){
 if($fn.Name -cin $targets){continue}
 $matches=@($newFns|Where-Object{$_.Name -ceq $fn.Name})
 if($matches.Count -ne 1 -or [string]$matches[0].Extent.Text -cne [string]$fn.Extent.Text){
   throw ('V060_NON_TARGET_STABLE_FUNCTION_BYTES_CHANGED_'+$fn.Name)
 }
}
foreach($name in $targets){
 $matches=@($newFns|Where-Object{$_.Name -ceq $name})
 if($matches.Count -ne 1){throw 'V060_CANDIDATE_MUTATOR_COUNT_CHANGED'}
 $actual=[string]$matches[0].Body.Extent.Text
 if(-not$actual.Contains('Enter-CustomAppReentrantTurnstileV060') -or
    -not$actual.Contains('Exit-CustomAppReentrantTurnstileV060 -Token $__leaseV060') -or
    $actual.IndexOf('Enter-CustomAppReentrantTurnstileV060',[StringComparison]::Ordinal) -ge
      $actual.IndexOf('Invoke-AtomicDirectorySwap',[StringComparison]::Ordinal) -and
      $name -ceq 'Update-AutoApps'){
   throw ('V060_ORIGINAL_MUTATOR_NOT_LOCKED_BEFORE_WRITE_'+$name)
 }
}
[void][IO.Directory]::CreateDirectory($destination)
$output=Join-Path $destination 'addon-manager-reentrant-V060-NONDEPLOY.ps1'
$bodyBytes=$utf8.GetBytes($final)
$all=if($bom -eq 3){
 [byte[]]@(239,187,191)+$bodyBytes
}else{$bodyBytes}
$h=[IO.File]::Open($output,[IO.FileMode]::CreateNew,
  [IO.FileAccess]::Write,[IO.FileShare]::None)
try{$h.Write($all,0,$all.Length);$h.Flush($true)}finally{$h.Dispose()}
if(-not[IO.File]::Exists($output) -or
  [IO.File]::ReadAllBytes($output).Length -ne $all.Length){
 throw 'V060_WRITTEN_CANDIDATE_NOT_VERIFIED'
}
$parsedTokens=$null;$freshErr=$null
[void][Management.Automation.Language.Parser]::ParseFile($output,[ref]$parsedTokens,[ref]$freshErr)
if($freshErr.Count){throw 'V060_REOPENED_CANDIDATE_WINPS51_SYNTAX_INVALID'}
Write-Host 'V060_STABLE_R17_SOURCE_EXACT_SHA_PIN_AND_INVERSE_3_MUTATORS_PASS'
Write-Host 'V060_STABLE_R17_OTHER_FUNCTIONS_BYTE_IDENTICAL_AND_FOUR_HELPERS_ONLY_PASS'
Write-Host 'V060_REAL_R17_UPDATE_COMMIT_ROLLBACK_ALL_REENTRANT_WRAPPED_PS51_PASS'
Write-Host 'V060_NONDEPLOY_CANDIDATE_ONLY_UNDER_GITHUB_RUNNER_TEMP_NO_INSTALL_PASS'
