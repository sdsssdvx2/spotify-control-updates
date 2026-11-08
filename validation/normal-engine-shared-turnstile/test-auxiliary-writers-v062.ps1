# V062 hosted-only dynamic denial of the two ORIGINAL r17 XPUI writer bodies.
# Extract verified function ASTs; never dot-source or run the full addon.
param([Parameter(Mandatory=$true)][string]$CandidatePath)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
 $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
 $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
 [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
 throw 'V062_TEST_HOSTED_WINDOWS_ONLY'
}
function Assert-V062([bool]$ok,[string]$reason){
 if(-not$ok){throw ('V062_TEST_'+$reason)}
}
function Expect-V062([scriptblock]$run,[string]$expected){
 $matched=$false
 try{[void](& $run)}catch{
  if([string]$_.Exception.Message -ceq $expected){$matched=$true}
  else{throw}
 }
 Assert-V062 $matched ('EXPECTED_DENIAL_'+$expected)
}
$root=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
$src=[IO.Path]::GetFullPath($CandidatePath)
Assert-V062 ($src.StartsWith(($root+'\'),[StringComparison]::OrdinalIgnoreCase) -and
 [IO.Path]::GetFileName($src) -ceq 'addon-manager-auxiliary-gated-V062-NONDEPLOY.ps1' -and
 [IO.File]::Exists($src)) 'CANDIDATE_MUST_BE_PRIVATE_NONDEPLOY'
$t=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($src,[ref]$t,[ref]$errors)
Assert-V062 ($errors.Count -eq 0) 'PS51_PARSE'
$functions=@($ast.FindAll({param($node)
 $node -is [Management.Automation.Language.FunctionDefinitionAst]},$true))
$targets=@('Invoke-PerformanceOverlayBestEffort','Invoke-StarRatingsPerformanceBestEffort')
$required=@(
 'Enter-CustomAppEngineTurnstileV047',
 'Enter-CustomAppReentrantTurnstileV060',
 'Exit-CustomAppReentrantTurnstileV060',
 'Assert-CustomAppReentrantLeaseInvariantV060',
 'Assert-CustomAppNormalUpdateEngineExclusivityV010'
)+$targets
$fragments=New-Object 'System.Collections.Generic.List[string]'
foreach($name in $required){
 $f=@($functions|Where-Object{$_.Name -ceq $name})
 Assert-V062 ($f.Count -eq 1) ('FUNCTION_MISSING_OR_DUPLICATE_'+$name)
 $fragments.Add([string]$f[0].Extent.Text)
}
foreach($name in $targets){
 $f=@($functions|Where-Object{$_.Name -ceq $name})[0]
 $body=[string]$f.Body.Extent.Text
 $enter=$body.IndexOf('Enter-CustomAppReentrantTurnstileV060',[StringComparison]::Ordinal)
 $gate=$body.IndexOf('Assert-CustomAppNormalUpdateEngineExclusivityV010',[StringComparison]::Ordinal)
 $exit=$body.LastIndexOf('Exit-CustomAppReentrantTurnstileV060',[StringComparison]::Ordinal)
 Assert-V062 ($enter -ge 0 -and $gate -gt $enter -and $exit -gt $gate) ('ACTUAL_AUX_WRITER_UNPROTECTED_'+$name)
}
# This loads only 7 named original function ASTs, excluding ALL top-level
# initialization, dispatch, executable original code and storage I/O.
. ([scriptblock]::Create(($fragments -join [Environment]::NewLine)))
$script:V060AddonLeaseState=$null
$private=Join-Path $root ('v062-functions-'+[guid]::NewGuid().ToString('N'))
$script:SafeLocal=Join-Path $private 'Local'
$lockDir=Join-Path $script:SafeLocal 'SpotifyControl'
[void][IO.Directory]::CreateDirectory($lockDir)
$script:GateChecks=0
$script:UnexpectedEffects=0
$script:ActualV047=(Get-Command Enter-CustomAppEngineTurnstileV047).ScriptBlock
function Enter-CustomAppEngineTurnstileV047 {
 param([string]$HostedCiRoot=$null)
 if(-not[string]::IsNullOrWhiteSpace($HostedCiRoot) -and
  -not([IO.Path]::GetFullPath($HostedCiRoot)).Equals(
   [IO.Path]::GetFullPath($script:SafeLocal),
   [StringComparison]::OrdinalIgnoreCase)){
  throw 'V062_UNEXPECTED_LOCK_ROOT'
 }
 & $script:ActualV047 -HostedCiRoot $script:SafeLocal
}
$script:ActualV010=(Get-Command Assert-CustomAppNormalUpdateEngineExclusivityV010).ScriptBlock
function Assert-CustomAppNormalUpdateEngineExclusivityV010 {
 param([string]$HostedCiRoot=$null)
 if(-not[string]::IsNullOrWhiteSpace($HostedCiRoot) -and
  -not([IO.Path]::GetFullPath($HostedCiRoot)).Equals(
   [IO.Path]::GetFullPath($script:SafeLocal),
   [StringComparison]::OrdinalIgnoreCase)){
  throw 'V062_UNEXPECTED_ENROLLMENT_ROOT'
 }
 $script:GateChecks++
 & $script:ActualV010 -HostedCiRoot $script:SafeLocal
}
# Negative tests must stop at the new boundary, before executing a single
# statement of the original r17 auxiliary mutator. These are sentinels.
function Get-Process { $script:UnexpectedEffects++;throw 'V062_UNEXPECTED_GET_PROCESS' }
function Test-SpotifyRunning { $script:UnexpectedEffects++;throw 'V062_UNEXPECTED_SPOTIFY_QUERY' }
function Write-AddonLog { $script:UnexpectedEffects++;throw 'V062_UNEXPECTED_LOG' }
function Ensure-StarRatingsPerformanceEngine { $script:UnexpectedEffects++;throw 'V062_UNEXPECTED_PERFORMANCE_ENGINE' }
function Invoke-PerformanceOverlayBestEffort { $script:UnexpectedEffects++;throw 'V062_UNEXPECTED_OVERRIDDEN_FUNCTION' }
# Restore the actual first target after defining all sentinels. The second
# remains the authentic extracted definition, without any redefinition.
$actualFirst=@($functions|Where-Object{$_.Name -ceq $targets[0]})
. ([scriptblock]::Create([string]$actualFirst[0].Extent.Text))
$held=& $script:ActualV047 -HostedCiRoot $script:SafeLocal
try{
 foreach($name in $targets){
  Expect-V062 {& $name -Reason 'v062-lock-held'} 'V047_ENGINE_TURNSTILE_BUSY_OR_IO_UNSAFE'
 }
 Assert-V062 ($script:GateChecks -eq 0 -and $script:UnexpectedEffects -eq 0) 'LOCK_DENIAL_TOO_LATE'
}finally{$held.Dispose()}
$h=Assert-CustomAppReentrantLeaseInvariantV060
Assert-V062 (-not[bool]$h.active) 'LOCK_DENIAL_LEAKED_LEASE'
Write-Host 'V062_BOTH_ACTUAL_AUX_XPUI_WRITERS_STOP_BEFORE_SIDE_EFFECT_ON_HELD_OS_LOCK_PASS'
$enrollment=Join-Path $script:SafeLocal 'SpotifyControlUpdates-CustomApp-State'
[void][IO.Directory]::CreateDirectory($enrollment)
try{
 foreach($name in $targets){
  Expect-V062 {& $name -Reason 'v062-enrolled'} 'normal-update-engine-gate-dpapi-enrollment-present-requires-journal-recovery-or-migration'
 }
 Assert-V062 ($script:GateChecks -eq 2 -and $script:UnexpectedEffects -eq 0 -and
  [IO.Directory]::Exists($enrollment)) 'ENROLLMENT_GATE_TOO_LATE_OR_WRITER_MUTATED_STATE'
 $h=Assert-CustomAppReentrantLeaseInvariantV060
 Assert-V062 (-not[bool]$h.active) 'ENROLLMENT_DENIAL_LEAKED_OS_LEASE'
}finally{[IO.Directory]::Delete($enrollment)}
$probe=& $script:ActualV047 -HostedCiRoot $script:SafeLocal
Assert-V062 ($probe -is [IO.FileStream]) 'LOCK_NOT_RELEASED_AFTER_DENIAL'
$probe.Dispose()
Assert-V062 (@(Get-ChildItem -LiteralPath $lockDir -Force).Count -eq 1 -and
 [IO.File]::Exists((Join-Path $lockDir '.engine-cutover-turnstile.lock')) -and
 (Get-Item -LiteralPath (Join-Path $lockDir '.engine-cutover-turnstile.lock')).Length -eq 0) 'UNEXPECTED_FIXTURE_WRITES'
Write-Host 'V062_BOTH_ACTUAL_AUX_XPUI_WRITERS_DENY_ENROLLED_ENGINE_AND_RELEASE_LOCK_PASS'
Write-Host 'V062_NONDEPLOY_ONLY_NO_REAL_SPOTIFY_NO_NETWORK_NO_PRODUCTION_AUTHORITY_PASS'
