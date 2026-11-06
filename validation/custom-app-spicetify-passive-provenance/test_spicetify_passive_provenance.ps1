param()
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
    throw 'SPICETIFY_PASSIVE_TEST_HOSTED_WINDOWS_ONLY'
}
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
foreach($p in @(
    'validation/custom-app-user-transaction-store-bundle/user-transaction-store.ps1',
    'validation/custom-app-normal-entrypoint-transaction-integration/normal-update-engine-fence.ps1',
    'validation/custom-app-legacy-journal-settlement-barrier/legacy-settlement-barrier.ps1',
    'validation/custom-app-cooperative-cross-engine-lock/cross-engine-transaction-lock.ps1',
    'validation/custom-app-spicetify-passive-provenance/spicetify-passive-provenance.ps1'
)){
    . (Join-Path $repo $p)
}
$root=Join-Path $env:RUNNER_TEMP ('spicetify-passive-'+[Guid]::NewGuid().ToString('N'))
$store=Join-Path $root 'user-root'
$local=Join-Path $root 'Local'
$roaming=Join-Path $root 'Roaming'
foreach($d in @($root,$store,$local,$roaming)){
    [void][IO.Directory]::CreateDirectory($d)
}
$sourceArgs=@{HostedCiRoot=$store;HostedCiLocalAppDataRoot=$local;HostedCiAppDataRoot=$roaming}
$exeDir=Join-Path $local 'spicetify'
$exe=Join-Path $exeDir 'spicetify.exe'
$configDir=Join-Path $roaming 'spicetify'
$config=Join-Path $configDir 'config-xpui.ini'
$empty=Get-CustomAppSpicetifyPassiveObservationV015 @sourceArgs
if([bool]$empty.ok -or [bool]$empty.production_mutation_authorized -or
   [IO.Directory]::Exists($exeDir) -or [IO.Directory]::Exists($configDir)){
    throw 'SPICETIFY_PASSIVE_EMPTY_PROBE_CREATED_TREE'
}
foreach($d in @($exeDir,$configDir)){[void][IO.Directory]::CreateDirectory($d)}
$fake=[byte[]]::new(8192)
for($i=0;$i -lt $fake.Length;$i++){$fake[$i]=[byte]($i%251)}
[IO.File]::WriteAllBytes($exe,$fake)
[IO.File]::WriteAllText($config,"[AdditionalOptions]\ncustom_apps = tagify\n",[Text.UTF8Encoding]::new($false))
$exeHash=(Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant()
$cfgHash=(Get-FileHash -LiteralPath $config -Algorithm SHA256).Hash.ToLowerInvariant()
$s=Get-CustomAppSpicetifyPassiveObservationV015 @sourceArgs
if(-not[bool]$s.ok -or [string]$s.exe_sha256 -cne $exeHash -or
   [string]$s.config_sha256 -cne $cfgHash -or
   [string]$s.observation_fingerprint -cnotmatch '^[0-9a-f]{64}$' -or
   [bool]$s.binary_trusted -or [bool]$s.enrolled_executable_pin -or
   [bool]$s.recovery_apply_eligible -or [bool]$s.result_is_authority -or
   [bool]$s.production_execution_authorized -or
   [bool]$s.production_mutation_authorized){
    throw 'SPICETIFY_PASSIVE_OBSERVATION_ESCAPED_ZERO_AUTHORITY'
}
$s2=Get-CustomAppSpicetifyPassiveObservationV015 @sourceArgs
if(-not[bool]$s2.ok -or
   [string]$s.observation_fingerprint -cne [string]$s2.observation_fingerprint){
    throw 'SPICETIFY_PASSIVE_SNAPSHOT_NONDETERMINISTIC'
}
$held=Open-CustomAppCrossEngineTransactionLockV010 -HostedCiRoot $store
try{
    $inside=Get-CustomAppSpicetifyPassiveObservationV015 @sourceArgs -HeldCrossEngineSession $held
    if(-not[bool]$inside.ok -or
       [string]$inside.observation_fingerprint -cne [string]$s.observation_fingerprint){
        throw 'SPICETIFY_PASSIVE_SHARED_GLOBAL_LOCK_FAILED'
    }
    $denied=Get-CustomAppSpicetifyPassiveObservationV015 @sourceArgs
    if([bool]$denied.ok){throw 'SPICETIFY_PASSIVE_LOCK_CONCURRENTLY_ACQUIRED'}
    $wrong=Get-CustomAppSpicetifyPassiveObservationV015 -HostedCiRoot (Join-Path $root 'other') -HostedCiLocalAppDataRoot $local -HostedCiAppDataRoot $roaming -HeldCrossEngineSession $held
    if([bool]$wrong.ok){throw 'SPICETIFY_PASSIVE_WRONG_GLOBAL_ROOT_ACCEPTED'}
    [void](Assert-CustomAppCrossEngineTransactionLockHeldV010 -Session $held)
}finally{$held.lock_handle.Dispose()}
$env:SPICETIFY_CONFIG=(Join-Path $root 'hostile-config-override')
try{
    $spoof=Get-CustomAppSpicetifyPassiveObservationV015 @sourceArgs
    if([bool]$spoof.ok -or [bool]$spoof.recovery_apply_eligible){
        throw 'SPICETIFY_PASSIVE_UNTRUSTED_CONFIG_OVERRIDE_ACCEPTED'
    }
}finally{Remove-Item Env:SPICETIFY_CONFIG -ErrorAction SilentlyContinue}
$env:SPICETIFY_STATE=(Join-Path $root 'hostile-state-override')
try{
    $spoof=Get-CustomAppSpicetifyPassiveObservationV015 @sourceArgs
    if([bool]$spoof.ok){throw 'SPICETIFY_PASSIVE_UNTRUSTED_STATE_OVERRIDE_ACCEPTED'}
}finally{Remove-Item Env:SPICETIFY_STATE -ErrorAction SilentlyContinue}
[IO.File]::AppendAllText($config,'; altered config fingerprint')
$changedCfg=Get-CustomAppSpicetifyPassiveObservationV015 @sourceArgs
if(-not[bool]$changedCfg.ok -or
   [string]$changedCfg.config_sha256 -ceq $cfgHash -or
   [string]$changedCfg.observation_fingerprint -ceq [string]$s.observation_fingerprint -or
   [bool]$changedCfg.recovery_apply_eligible){
    throw 'SPICETIFY_PASSIVE_CONFIG_DRIFT_UNOBSERVED'
}
[IO.File]::WriteAllBytes($exe,[byte[]](1,2,3,4))
$bad=Get-CustomAppSpicetifyPassiveObservationV015 @sourceArgs
if([bool]$bad.ok){throw 'SPICETIFY_PASSIVE_TRUNCATED_EXE_ACCEPTED'}
[IO.File]::WriteAllBytes($exe,$fake)
[IO.File]::Delete($config)
$absent=Get-CustomAppSpicetifyPassiveObservationV015 @sourceArgs
if([bool]$absent.ok -or [IO.File]::Exists($config)){
    throw 'SPICETIFY_PASSIVE_MISSING_CONFIG_CREATED'
}
Write-Host 'SPICETIFY_PASSIVE_WINDOWS_NEGATIVE_MATRIX_PASS no_spicetify_write=true unknown_executable_untrusted=true held_and_busy_global_lock=true wrong_root_denied=true overrides_denied=true config_fingerprint_drift=true truncated_exe_denied=true missing_config_unchanged=true'
