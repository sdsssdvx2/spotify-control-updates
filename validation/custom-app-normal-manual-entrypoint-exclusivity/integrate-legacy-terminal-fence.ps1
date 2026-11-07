# Hosted Windows build of the actual generated Addon Manager. Keep all
# existing functions and update policies exact; only add the same qualified
# old-vs-new engine guard to the manually invoked legacy terminal handlers.
param([Parameter(Mandatory=$true)][string]$ParentCandidate,
      [Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted'){throw 'TERMINAL_FENCE_BUILDER_HOSTED_ONLY'}
$expected='0cb2362dd14772f19ba2970e5f4c2bc07bf0512c0de31494af7b01cb2a98fdd6'
$originalBytes=[IO.File]::ReadAllBytes((Resolve-Path $ParentCandidate).Path)
$sha=[Security.Cryptography.SHA256]::Create()
try{$actual=([BitConverter]::ToString($sha.ComputeHash($originalBytes))).Replace('-','').ToLowerInvariant()}
finally{$sha.Dispose()}
if($originalBytes.Length -ne 1453028 -or $actual -cne $expected){
    throw 'TERMINAL_FENCE_QUALIFIED_REAL_ADDON_PARENT_BYTES_CHANGED'
}
$bom=if($originalBytes.Length -ge 3 -and $originalBytes[0] -eq 239 -and
    $originalBytes[1] -eq 187 -and $originalBytes[2] -eq 191){3}else{0}
$utf8=[Text.UTF8Encoding]::new($false,$true)
$original=$utf8.GetString($originalBytes,$bom,$originalBytes.Length-$bom)
$parserTokens=$null;$parserErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($original,[ref]$parserTokens,[ref]$parserErrors)
if($parserErrors.Count){throw 'TERMINAL_FENCE_PARENT_WINPS51_PARSE_FAIL'}
$target=@('Commit-LastTransaction','Rollback-LastTransaction')
$positions=New-Object 'System.Collections.Generic.List[int]'
$insertion=([char]13)+([char]10)+'    [void](Assert-CustomAppNormalUpdateEngineExclusivityV010)'
$allOld=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$true))
foreach($name in $target){
    $matches=@($allOld|Where-Object{$_.Name -ceq $name})
    if($matches.Count -ne 1){throw ('TERMINAL_FENCE_ORIGINAL_HANDLER_NOT_UNIQUE '+$name)}
    $fn=$matches[0]
    # Preserve real PowerShell param blocks and their argument semantics.
    $position=if($null-ne$fn.Body.ParamBlock){[int]$fn.Body.ParamBlock.Extent.EndOffset}
              else{[int]$fn.Body.Extent.StartOffset+1}
    if($position -le [int]$fn.Body.Extent.StartOffset -or
       $position -ge [int]$fn.Body.Extent.EndOffset){
        throw ('TERMINAL_FENCE_AST_PARAM_INSERTION_INVALID '+$name)
    }
    $positions.Add($position)
}
if($positions[0] -eq $positions[1]){throw 'TERMINAL_FENCE_COLLIDING_HANDLER_STARTS'}
$candidate=$original
foreach($pos in @($positions|Sort-Object -Descending)){
    $candidate=$candidate.Insert([int]$pos,$insertion)
}
$tokens=$null;$errors=$null
$newAst=[Management.Automation.Language.Parser]::ParseInput($candidate,[ref]$tokens,[ref]$errors)
if($errors.Count){
    $errors|Select-Object -First 8|ForEach-Object{Write-Host ("PARSE "+$_.Message)}
    throw 'TERMINAL_FENCE_GENERATED_WINPS51_PARSE_FAILED'
}
$allNew=@($newAst.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$true))
if(($allOld.Name -join '|') -cne ($allNew.Name -join '|')){
    throw 'TERMINAL_FENCE_FUNCTION_NAMES_CHANGED'
}
foreach($name in $target){
    $old=@($allOld|Where-Object{$_.Name -ceq $name})[0]
    $new=@($allNew|Where-Object{$_.Name -ceq $name})[0]
    $p0=if($null-ne$old.Body.ParamBlock){[string]$old.Body.ParamBlock.Extent.Text}else{''}
    $p1=if($null-ne$new.Body.ParamBlock){[string]$new.Body.ParamBlock.Extent.Text}else{''}
    if($p0 -cne $p1){throw ('TERMINAL_FENCE_ORIGINAL_SIGNATURE_CHANGED '+$name)}
    if($null-eq$new.Body.EndBlock -or @($new.Body.EndBlock.Statements).Count -lt 1 -or
       ([string]$new.Body.EndBlock.Statements[0].Extent.Text) -cnotmatch
         '^\[void\]\(Assert-CustomAppNormalUpdateEngineExclusivityV010\)$'){
       throw ('TERMINAL_FENCE_NOT_FIRST_EXECUTED_STATEMENT '+$name)
    }
}
# Invert only the two inserted substrings. The complete 1.45 MB original
# (including every existing policy, user-data path and parser line) must match.
$roundtrip=$candidate
foreach($pos in @($positions|Sort-Object)){
    $start=[int]$pos
    if($roundtrip.Substring($start,$insertion.Length) -cne $insertion){
        throw 'TERMINAL_FENCE_REVERSE_ANCHOR_DID_NOT_MATCH'
    }
    $roundtrip=$roundtrip.Remove($start,$insertion.Length)
}
if($roundtrip -cne $original){throw 'TERMINAL_FENCE_OTHER_PARENT_BYTES_CHANGED'}
$bytes=$utf8.GetBytes($candidate)
if($bom -eq 3){
    $fileBytes=New-Object byte[] ($bytes.Length+3)
    [Array]::Copy([byte[]](239,187,191),0,$fileBytes,0,3)
    [Array]::Copy($bytes,0,$fileBytes,3,$bytes.Length)
}else{$fileBytes=$bytes}
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$out=Join-Path $OutputDirectory 'addon-manager.ps1'
[IO.File]::WriteAllBytes($out,$fileBytes)
$src=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($ParentCandidate))
foreach($name in @('spotify-control.ps1','Collect-Marketplace-Records.ps1','LevelDbReadOnly.cs')){
    [IO.File]::Copy((Join-Path $src $name),(Join-Path $OutputDirectory $name),$false)
}
$sha=[Security.Cryptography.SHA256]::Create()
try{$resultHash=([BitConverter]::ToString($sha.ComputeHash($fileBytes))).Replace('-','').ToLowerInvariant()}
finally{$sha.Dispose()}
$report=[pscustomobject]@{
 parent_sha256=$expected;result_sha256=$resultHash;result_bytes=$fileBytes.Length
 functions_preserved=$true;all_original_content_exact_inverse=$true
 exact_original_param_blocks=$true;manual_rollback_and_commit_guard_first=$true
 normal_auto_Update_guard_unchanged=$true;installed_only_policy_unchanged=$true
 new_engine_activation_authorized=$false;operating_main_unchanged=$true
}
[IO.File]::WriteAllText((Join-Path $OutputDirectory 'terminal-fence-report.json'),($report|ConvertTo-Json -Depth 5),([Text.UTF8Encoding]::new($false)))
Write-Host ('REAL_ADDON_LEGACY_TERMINAL_GUARD_GENERATED_PASS sha256='+$resultHash+' bytes='+$fileBytes.Length)
