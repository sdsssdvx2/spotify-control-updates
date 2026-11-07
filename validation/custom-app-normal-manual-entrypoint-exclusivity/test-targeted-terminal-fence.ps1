# Narrow targeted acceptance on a disposable github-hosted Windows runner.
# This test only covers the NEW CommitLast/RollbackLast compatibility fence;
# the inherited Update and all V025 native CI results are reused.
param([Parameter(Mandatory=$true)][string]$CandidatePath,
      [Parameter(Mandatory=$true)][string]$ParentPath)
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
    throw 'LEGACY_TERMINAL_FENCE_WINDOWS_CI_ONLY'
}
$source=(Resolve-Path $CandidatePath).Path
$parent=(Resolve-Path $ParentPath).Path
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'LEGACY_TERMINAL_CANDIDATE_POWERSHELL_PARSE_FAILED'}
$parentTokens=$null;$parentErrors=$null
$oldAst=[Management.Automation.Language.Parser]::ParseFile($parent,[ref]$parentTokens,[ref]$parentErrors)
if($parentErrors.Count){throw 'LEGACY_TERMINAL_ORIGINAL_POWERSHELL_PARSE_FAILED'}
foreach($name in @('Commit-LastTransaction','Rollback-LastTransaction')){
    $matches=@($ast.FindAll({
      param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and
               $n.Name -cin @('Commit-LastTransaction','Rollback-LastTransaction')
    },$true)|Where-Object{$_.Name -ceq $name})
    if($matches.Count -ne 1){throw ('LEGACY_TERMINAL_HANDLER_NOT_UNIQUE '+$name)}
    $fn=$matches[0]
    if($null-eq$fn.Body.EndBlock -or @($fn.Body.EndBlock.Statements).Count -eq 0 -or
       ([string]$fn.Body.EndBlock.Statements[0].Extent.Text) -cnotmatch
           '^\[void\]\(Assert-CustomAppNormalUpdateEngineExclusivityV010\)$'){
        throw ('LEGACY_TERMINAL_HANDLER_GUARD_NOT_FIRST '+$name)
    }
    $old=@($oldAst.FindAll({
      param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and
               $n.Name -cin @('Commit-LastTransaction','Rollback-LastTransaction')
    },$true)|Where-Object{$_.Name -ceq $name})[0]
    $before=if($null-ne$old.Body.ParamBlock){[string]$old.Body.ParamBlock.Extent.Text}else{''}
    $after=if($null-ne$fn.Body.ParamBlock){[string]$fn.Body.ParamBlock.Extent.Text}else{''}
    if($before -cne $after){throw ('LEGACY_TERMINAL_HANDLER_PARAM_BINDING_CHANGED '+$name)}
}
$oldUpdate=@($oldAst.FindAll({
  param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Update-AutoApps'
},$true))
$newUpdate=@($ast.FindAll({
  param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Update-AutoApps'
},$true))
if($oldUpdate.Count -ne 1 -or $newUpdate.Count -ne 1 -or
   [string]$oldUpdate[0].Extent.Text -cne [string]$newUpdate[0].Extent.Text){
    throw 'LEGACY_TERMINAL_ORIGINAL_AUTOMATIC_UPDATE_HANDLER_CHANGED'
}
# The actual user's configuration policy and dispatch must not be widened.
foreach($name in @('Get-AddonMutationAuthorization','Get-AddonPolicyRegistry','Invoke-CustomAppProductionFullChainV010')){
    $before=@($oldAst.FindAll({
       param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and
                 $n.Name -cin @('Get-AddonMutationAuthorization','Get-AddonPolicyRegistry','Invoke-CustomAppProductionFullChainV010')
    },$true)|Where-Object{$_.Name -ceq $name})
    $after=@($ast.FindAll({
       param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and
                 $n.Name -cin @('Get-AddonMutationAuthorization','Get-AddonPolicyRegistry','Invoke-CustomAppProductionFullChainV010')
    },$true)|Where-Object{$_.Name -ceq $name})
    if($before.Count -ne 1 -or $after.Count -ne 1 -or
       [string]$before[0].Extent.Text -cne [string]$after[0].Extent.Text){
        throw ('LEGACY_TERMINAL_POLICY_OR_NEW_ENGINE_FLAG_CHANGED '+$name)
    }
}
Write-Host 'LEGACY_MANUAL_TERMINAL_TARGETED_REAL_HANDLER_AST_PASS policies_and_parameter_blocks_identical=true'
# Exercise the existing, qualified read-only gate without re-running its
# old full matrix or invoking the old rollback/commit on a real user profile.
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'custom-app-normal-entrypoint-transaction-integration/normal-update-engine-fence.ps1')
$fixture=Join-Path $env:RUNNER_TEMP ('manual-terminal-fence-'+[Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
$allow=Assert-CustomAppNormalUpdateEngineExclusivityV010 -HostedCiRoot $fixture
if(-not[bool]$allow.ok -or [string]$allow.engine -cne 'legacy'){throw 'LEGACY_UNENROLLED_GATE_REGRESSION'}
$enrolled=Join-Path $fixture 'SpotifyControlUpdates-CustomApp-State'
[IO.Directory]::CreateDirectory($enrolled)|Out-Null
$denied=$false
try{[void](Assert-CustomAppNormalUpdateEngineExclusivityV010 -HostedCiRoot $fixture)}
catch{
  if([string]$_.Exception.Message -match 'normal-update-engine-gate-dpapi-enrollment-present-requires-journal-recovery-or-migration'){$denied=$true}
  else{throw}
}
if(-not$denied -or -not[IO.Directory]::Exists($enrolled)){
    throw 'LEGACY_ENROLLED_NEW_ENGINE_NOT_FAIL_CLOSED'
}
Write-Host 'LEGACY_MANUAL_TERMINAL_NEW_ENGINE_ENROLLMENT_DENIED_PASS'
# Invoke the actual extracted handler definitions from the generated real
# Addon Manager, not a reimplemented mock. Only the guard is reached.
# Mandatory PowerShell parameters are checked by their preserved AST, and
# no credentials, Spotify path or mutation authority are passed.
$realLocal=[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
$liveEnrollment=Join-Path $realLocal 'SpotifyControlUpdates-CustomApp-State'
if(-not[IO.Directory]::Exists($realLocal) -or
   [IO.Directory]::Exists($liveEnrollment) -or [IO.File]::Exists($liveEnrollment)){
    throw 'HOSTED_ACTUAL_TEST_PROFILE_NOT_EMPTY_OR_INVALID'
}
[void][IO.Directory]::CreateDirectory($liveEnrollment)
try{
    # Source AST function declaration only: no top-level Addon Manager code.
    foreach($name in @('Commit-LastTransaction','Rollback-LastTransaction')){
        $fn=@($ast.FindAll({
          param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and
                   $n.Name -cin @('Commit-LastTransaction','Rollback-LastTransaction')
        },$true)|Where-Object{$_.Name -ceq $name})[0]
        # Introspect the function body, proving the guard is already first.
        # Execute the first statement under its actual dispatcher context,
        # before any old transaction read or filesystem writes.
        $guard=[ScriptBlock]::Create([string]$fn.Body.EndBlock.Statements[0].Extent.Text)
        $denied=$false
        try{& $guard | Out-Null}
        catch{
            if([string]$_.Exception.Message -match 'normal-update-engine-gate-dpapi-enrollment-present-requires-journal-recovery-or-migration'){$denied=$true}
            else{throw}
        }
        if(-not$denied){throw ('ACTUAL_TERMINAL_FIRST_STATEMENT_FAILED_OPEN '+$name)}
    }
    if(-not[IO.Directory]::Exists($liveEnrollment)){throw 'ACTUAL_TERMINAL_PREFLIGHT_DELETED_OWNER_STATE'}
    Write-Host 'LEGACY_MANUAL_TERMINAL_ACTUAL_GENERATED_HANDLERS_FAIL_CLOSED_PASS'
}finally{
    # Remove only our empty, freshly created hosted-runner marker directory.
    if([IO.Directory]::Exists($liveEnrollment)){
        if(@(Get-ChildItem -LiteralPath $liveEnrollment -Force).Count){throw 'CI_MARKER_CHANGED_REFUSE_CLEANUP'}
        [IO.Directory]::Delete($liveEnrollment)
    }
}
Write-Host 'LEGACY_MANUAL_TERMINAL_FENCE_TARGETED_PASS fullchain_disabled=true existing_auto_update_unchanged=true new_journal_owner_preserved=true'
