# Build the actual qualified generated Addon Manager with an OS-backed
# cooperative lease around ALL THREE old mutating handlers. Hosted CI only.
param([Parameter(Mandatory=$true)][string]$ParentCandidate,
      [Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
 throw 'V047_BUILDER_HOSTED_WINDOWS_ONLY'
}
$parent=(Resolve-Path -LiteralPath $ParentCandidate).Path
$bytes=[IO.File]::ReadAllBytes($parent)
if($bytes.Length -lt 1453028 -or $bytes.Length -gt 1500000){
 throw 'V047_PARENT_ADDON_GENERATED_SIZE_NOT_QUALIFIED'
}
$bom=if($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191){3}else{0}
$utf8=[Text.UTF8Encoding]::new($false,$true)
$original=$utf8.GetString($bytes,$bom,$bytes.Length-$bom)
$crlf=[string][char]13+[string][char]10
$lf=[string][char]10
$nl=if($original.Contains($crlf)){$crlf}else{$lf}
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($original,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'V047_GENERATED_PARENT_POWERSHELL_PARSE_FAILED'}
$originalFuncs=@($ast.FindAll({
 param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]
},$true))
$targets=@('Update-AutoApps','Commit-LastTransaction','Rollback-LastTransaction')
$inserts=New-Object 'System.Collections.Generic.List[object]'
$prefix=$nl+'    $__engineLeaseV047 = Enter-CustomAppEngineTurnstileV047'+$nl+'    try {'+$nl
$suffix=$nl+'    } finally {'+$nl+'        if($null -ne $__engineLeaseV047){$__engineLeaseV047.Dispose()}'+$nl+'    }'+$nl
if($original.Contains('$__engineLeaseV047') -or
   $original.Contains('Enter-CustomAppEngineTurnstileV047')){
 throw 'V047_PREVIOUS_TURNSTILE_ALREADY_IN_ADDON'
}
foreach($name in $targets){
 $set=@($originalFuncs|Where-Object{$_.Name -ceq $name})
 if($set.Count -ne 1){throw ('V047_QUALIFIED_HANDLER_NOT_UNIQUE_'+$name)}
 $fn=$set[0]
 $oldText=[string]$fn.Extent.Text
 if(-not$oldText.Contains('Assert-CustomAppNormalUpdateEngineExclusivityV010')){
   throw ('V047_PREVIOUS_NORMAL_MANUAL_GUARD_MISSING_'+$name)
 }
 if($name -ceq 'Update-AutoApps'){
   foreach($oldSideEffect in @('Rollback-LastTransaction','Backup-SpotifyWebData',
       'Get-AddonInventory','Invoke-AtomicDirectorySwap')){
      if($oldText.IndexOf($oldSideEffect,[StringComparison]::Ordinal) -lt 0 -or
         $oldText.IndexOf('Assert-CustomAppNormalUpdateEngineExclusivityV010',[StringComparison]::Ordinal) -ge
           $oldText.IndexOf($oldSideEffect,[StringComparison]::Ordinal)){
        throw ('V047_PREVIOUS_UPDATE_GUARD_NOT_BEFORE_MUTATION_'+$oldSideEffect)
      }
   }
 }
 if($null-eq$fn.Body -or $null-eq$fn.Body.EndBlock){
    throw ('V047_HANDLER_HAS_UNEXPECTED_AST_SHAPE_'+$name)
 }
 $begin=if($null-ne$fn.Body.ParamBlock){[int]$fn.Body.ParamBlock.Extent.EndOffset}
        else{[int]$fn.Body.Extent.StartOffset+1}
 $end=[int]$fn.Body.Extent.EndOffset-1
 if($begin -ge $end -or $begin -le [int]$fn.Body.Extent.StartOffset){
    throw ('V047_HANDLER_INSERTION_OUTSIDE_BODY_'+$name)
 }
 $inserts.Add([pscustomobject]@{position=$begin;text=$prefix;label=$name+'-begin'})
 $inserts.Add([pscustomobject]@{position=$end;text=$suffix;label=$name+'-end'})
}
$wrapped=$original
foreach($p in @($inserts|Sort-Object position -Descending)){
 $wrapped=$wrapped.Insert([int]$p.position,[string]$p.text)
}
# Reversing the exact six insertions must reproduce the entire parent bytes
# before adding only one uniquely named lease function. No policy diff.
$roundTrip=$wrapped
foreach($p in @($inserts|Sort-Object position)){
 $offset=[int]$p.position;$v=[string]$p.text
 if($roundTrip.Substring($offset,$v.Length) -cne $v){
    throw ('V047_INVERSE_INSERTION_MISMATCH_'+[string]$p.label)
 }
 $roundTrip=$roundTrip.Remove($offset,$v.Length)
}
if($roundTrip -cne $original){throw 'V047_WRAPPER_DID_NOT_RESTORE_ORIGINAL'}
$modulePath=Join-Path $PSScriptRoot 'engine-turnstile-v047.ps1'
$moduleText=[IO.File]::ReadAllText($modulePath,$utf8).Replace($crlf,$lf).TrimEnd()
$moduleText=$moduleText.Replace($lf,$nl)
$payload=$moduleText+$nl+$nl
$anchor='function Test-Due {'
if(($wrapped.Split([string[]]@($anchor),[StringSplitOptions]::None)).Count -ne 2){
 throw 'V047_REAL_ADDON_HELPER_INSERTION_ANCHOR_MISSING'
}
$final=$wrapped.Replace($anchor,($payload+$anchor))
if(($final.Split([string[]]@($payload),[StringSplitOptions]::None)).Count -ne 2 -or
    $final.Replace($payload,'') -cne $wrapped){
 throw 'V047_MODULE_NOT_EXACTLY_REVERSIBLE'
}
$parsedTokens=$null;$parseErrors=$null
$newAst=[Management.Automation.Language.Parser]::ParseInput($final,[ref]$parsedTokens,[ref]$parseErrors)
if($parseErrors.Count){
 throw ('V047_LOCKED_WINPS51_PARSE_FAILED_'+$parseErrors[0].Message)
}
$nextFuncs=@($newAst.FindAll({
 param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]
},$true))
$expectedNames=@($originalFuncs|ForEach-Object{$_.Name})+@('Enter-CustomAppEngineTurnstileV047')
if(@($nextFuncs).Count -ne $expectedNames.Count -or
   @($nextFuncs|Where-Object{$_.Name -notin $expectedNames}).Count){
 throw 'V047_UNEXPECTED_FUNCTIONS_IN_GENERATED_PROGRAM'
}
# Original generated Addon Manager intentionally includes some repeated
# helper FUNCTION NAMES (different modules). Preserve each definition in
# AST document order; do not silently merge or demand name uniqueness for
# unrelated original helpers. Only the three mutating handlers are unique.
$newOriginalFuncs=@($nextFuncs|Where-Object{$_.Name -cne 'Enter-CustomAppEngineTurnstileV047'})
if($newOriginalFuncs.Count -ne $originalFuncs.Count){
 throw 'V047_ORIGINAL_FUNCTION_SEQUENCE_COUNT_CHANGED'
}
for($i=0;$i -lt $originalFuncs.Count;$i++){
 $old=$originalFuncs[$i];$new=$newOriginalFuncs[$i]
 if([string]$old.Name -cne [string]$new.Name){
   throw ('V047_ORIGINAL_FUNCTION_ORDER_CHANGED_AT_'+[string]$i)
 }
 $pOld=if($null-ne$old.Body.ParamBlock){[string]$old.Body.ParamBlock.Extent.Text}else{''}
 $pNew=if($null-ne$new.Body.ParamBlock){[string]$new.Body.ParamBlock.Extent.Text}else{''}
 if($pOld -cne $pNew){throw ('V047_ORIGINAL_SIGNATURE_CHANGED_'+$old.Name)}
 if($old.Name -notin $targets -and
    [string]$new.Extent.Text -cne [string]$old.Extent.Text){
   throw ('V047_UNRELATED_ORIGINAL_FUNCTION_CHANGED_'+$old.Name)
 }
}
foreach($name in $targets){
 $node=@($nextFuncs|Where-Object{$_.Name -ceq $name})[0]
 $actual=[string]$node.Extent.Text
 if(-not$actual.Contains('$__engineLeaseV047 = Enter-CustomAppEngineTurnstileV047') -or
    -not$actual.Contains('$__engineLeaseV047.Dispose()') -or
    $actual.IndexOf('Enter-CustomAppEngineTurnstileV047',[StringComparison]::Ordinal) -ge
      $actual.IndexOf('Assert-CustomAppNormalUpdateEngineExclusivityV010',[StringComparison]::Ordinal)){
     throw ('V047_LOCK_NOT_BEFORE_OLD_ENGINE_GUARD_'+$name)
 }
}
$lockFn=@($nextFuncs|Where-Object{$_.Name -ceq 'Enter-CustomAppEngineTurnstileV047'})
if($lockFn.Count -ne 1){throw 'V047_EXACTLY_ONE_SHARED_LOCK_FUNCTION_REQUIRED'}
if(-not$final.Contains('Custom App production full-chain execution is intentionally unavailable in integration-only candidate.')){
 throw 'V047_NEW_FULLCHAIN_HARD_DISABLE_NOT_PRESERVED'
}
$finalBytes=$utf8.GetBytes($final)
if($bom -eq 3){
 $all=New-Object byte[] ($finalBytes.Length+3)
 [Array]::Copy([byte[]](239,187,191),0,$all,0,3)
 [Array]::Copy($finalBytes,0,$all,3,$finalBytes.Length)
}else{$all=$finalBytes}
$dest=[IO.Path]::GetFullPath($OutputDirectory)
$runnerRoot=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
if(-not$dest.StartsWith(($runnerRoot+'\'),[StringComparison]::OrdinalIgnoreCase) -or
   [IO.Directory]::Exists($dest)){
 throw 'V047_OUTPUT_MUST_BE_NEW_HOSTED_RUNNER_DIRECTORY'
}
[IO.Directory]::CreateDirectory($dest)|Out-Null
[IO.File]::WriteAllBytes((Join-Path $dest 'addon-manager.ps1'),$all)
$sourceDir=[IO.Path]::GetDirectoryName($parent)
foreach($support in @('spotify-control.ps1','Collect-Marketplace-Records.ps1','LevelDbReadOnly.cs')){
 [IO.File]::Copy((Join-Path $sourceDir $support),(Join-Path $dest $support),$false)
}
$sha=[Security.Cryptography.SHA256]::Create()
try{$digest=([BitConverter]::ToString($sha.ComputeHash($all))).Replace('-','').ToLowerInvariant()}
finally{$sha.Dispose()}
Write-Host ('V047_GENERATED_ACTUAL_ADDON_SHA='+$digest+';bytes='+[string]$all.Length)
Write-Host 'V047_ALL_THREE_NORMAL_AND_MANUAL_ENTRYPOINTS_SHARED_LOCK_AND_EXACT_PARENT_INVERSE_PASS'
Write-Host 'V047_NO_NEW_ENGINE_EXECUTION_NO_PRODUCTION_INSTALL_NO_BACKUP_CLEANUP_PASS'
