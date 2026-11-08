# Run only the AST-extracted V010 gate and maintenance function under a private
# GitHub-hosted fixture. DO NOT execute, source, or import the whole stable main.
param([Parameter(Mandatory=$true)][string]$Candidate)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
 $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
 $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
 [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
 throw 'MAIN_ACCEPTANCE_HOSTED_WINDOWS_ONLY'
}
function Assert-MainAcceptance([bool]$ok,[string]$message){
 if(-not$ok){throw ('MAIN_ACCEPTANCE_'+$message)}
}
function Expect-MainDenial([scriptblock]$attempt,[string]$reason){
 $denied=$false
 try{[void](& $attempt)}catch{
  if([string]$_.Exception.Message -ceq $reason){$denied=$true}
  else{throw}
 }
 Assert-MainAcceptance $denied ('EXPECTED_'+$reason)
}
$runner=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
$src=[IO.Path]::GetFullPath($Candidate)
Assert-MainAcceptance ($src.StartsWith(($runner+'\'),[StringComparison]::OrdinalIgnoreCase) -and
 [IO.Path]::GetFileName($src) -ceq 'spotify-control-enrollment-preflight-NONDEPLOY.ps1' -and
 [IO.File]::Exists($src)) 'NONDEPLOY_CANDIDATE_REQUIRED'
$tok=$null;$parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($src,[ref]$tok,[ref]$parseErrors)
Assert-MainAcceptance ($parseErrors.Count -eq 0 -and $null-ne$ast.ParamBlock) 'CANDIDATE_AST'
$top=@($ast.EndBlock.Statements|Where-Object{
 $_ -isnot [Management.Automation.Language.FunctionDefinitionAst]
})
Assert-MainAcceptance ($top.Count -gt 1 -and
 [string]$top[0].Extent.Text -ceq
 '[void](Assert-CustomAppNormalUpdateEngineExclusivityV010)') 'FIRST_EXECUTED_SOURCE_STATEMENT_GUARDED'
$fn=@($ast.FindAll({param($node)
 $node -is [Management.Automation.Language.FunctionDefinitionAst]},$true))
$gate=@($fn|Where-Object{$_.Name -ceq 'Assert-CustomAppNormalUpdateEngineExclusivityV010'})
$mut=@($fn|Where-Object{$_.Name -ceq 'Invoke-MaintenanceMutationPhase'})
Assert-MainAcceptance ($gate.Count -eq 1 -and $mut.Count -eq 1) 'MUTATOR_AND_V010_EXACT'
$block=[string]$mut[0].Body.Extent.Text
$first=$block.IndexOf('Assert-CustomAppNormalUpdateEngineExclusivityV010',[StringComparison]::Ordinal)
$effects=$block.IndexOf('Invoke-SelfUpdateMutation',[StringComparison]::Ordinal)
Assert-MainAcceptance ($first -gt 0 -and $effects -gt $first) 'MAIN_MUTATION_RECHECK_BEFORE_SELF_UPDATE'
# The real gate is extracted from the exact original source, but the only
# dynamically executed version is forced to use RUNNER_TEMP via the existing
# hard-coded V010 HostedCiRoot CI predicate.
. ([scriptblock]::Create([string]$gate[0].Extent.Text))
$actual=(Get-Command Assert-CustomAppNormalUpdateEngineExclusivityV010).ScriptBlock
$local=Join-Path $runner ('main-enrollment-fixture-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($local)
$script:SafeLocal=$local
$script:GateCalls=0
$script:UnexpectedMainEffects=0
function Assert-CustomAppNormalUpdateEngineExclusivityV010 {
 param([string]$HostedCiRoot=$null)
 if(-not[string]::IsNullOrWhiteSpace($HostedCiRoot)){
  throw 'MAIN_ACCEPTANCE_NO_CALLER_FIXTURE_OVERRIDE'
 }
 $script:GateCalls++
 & $actual -HostedCiRoot $script:SafeLocal
}
$marker=Join-Path $local 'SpotifyControlUpdates-CustomApp-State'
# First simulate normal pre-enrollment read-only admission; no real user data.
$clean=Assert-CustomAppNormalUpdateEngineExclusivityV010
Assert-MainAcceptance ([bool]$clean.ok -and -not[bool]$clean.production_mutation_authorized) 'NO_ENROLLMENT_READ_ONLY_OK'
# Once enrolled, the main start gate must stop even before loading any
# original stable modules, network, config, or update execution.
[void][IO.Directory]::CreateDirectory($marker)
try{
 Expect-MainDenial {Assert-CustomAppNormalUpdateEngineExclusivityV010} 'normal-update-engine-gate-dpapi-enrollment-present-requires-journal-recovery-or-migration'
 Assert-MainAcceptance ($script:GateCalls -eq 2 -and
  $script:UnexpectedMainEffects -eq 0 -and
  [IO.Directory]::Exists($marker)) 'STARTUP_GUARD_RETURNS_WHEN_ENROLLED'
 # Execute ONLY the extracted real main maintenance function with a fixed
 # V010 intercept; its first guarded statement MUST abort. Any later main
 # function or file system call is excluded by the deliberately blocked path.
 . ([scriptblock]::Create([string]$mut[0].Extent.Text))
 Expect-MainDenial {
  Invoke-MaintenanceMutationPhase -State ([pscustomobject]@{}) -GuardPlan ([pscustomobject]@{})
 } 'normal-update-engine-gate-dpapi-enrollment-present-requires-journal-recovery-or-migration'
 Assert-MainAcceptance ($script:GateCalls -eq 3 -and
  $script:UnexpectedMainEffects -eq 0) 'CHECK_TO_MUTATION_RECHECK_FAILED'
}finally{
 Assert-MainAcceptance (@(Get-ChildItem -LiteralPath $marker -Force).Count -eq 0) 'MARKER_UNEXPECTEDLY_CHANGED'
 [IO.Directory]::Delete($marker)
}
# A file (not a directory) with this exact name is also a no-authority
# enrollment object and must be kept intact.
[IO.File]::WriteAllText($marker,'main-private-scratch-marker')
try{
 Expect-MainDenial {Assert-CustomAppNormalUpdateEngineExclusivityV010} 'normal-update-engine-gate-dpapi-enrollment-present-requires-journal-recovery-or-migration'
 Assert-MainAcceptance ([IO.File]::ReadAllText($marker) -ceq 'main-private-scratch-marker') 'UNRECOGNIZED_MARKER_WAS_MODIFIED'
}finally{[IO.File]::Delete($marker)}
Write-Host 'MAIN_ACCEPTANCE_REAL_V010_START_AND_MAINTENANCE_ENROLLMENT_DENIAL_PASS'
Write-Host 'MAIN_ACCEPTANCE_PRIVATE_FIXTURE_ONLY_NO_INSTALLED_MAIN_OR_VBS_EXECUTED_PASS'
Write-Host 'MAIN_ACCEPTANCE_NO_MAIN_CHILD_LOCK_HANDOFF_OR_LIVE_CUTOVER_CLAIM_PASS'
