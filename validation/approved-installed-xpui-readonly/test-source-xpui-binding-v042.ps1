# V042 synthetic physical-layout source+XPUI hash binding acceptance only.
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if($env:GITHUB_ACTIONS -cne 'true' -or
   $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted'){
 throw 'V042_TEST_REQUIRES_HOSTED_WINDOWS_FIXTURE'
}
$top=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $top 'validation/custom-app-update-transaction-protocol-v0.1.0/custom-app-update-transaction.ps1')
. (Join-Path $PSScriptRoot 'installed-xpui-readonly.ps1')
. (Join-Path $PSScriptRoot 'actual-custom-app-origins-v041.ps1')
. (Join-Path $PSScriptRoot 'verified-source-xpui-binding-v042.ps1')
function Assert-V042([bool]$ok,[string]$code){if(-not$ok){throw ('V042_TEST_'+$code)}}
$root=Join-Path $env:RUNNER_TEMP ('v042-actual-layout-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
$roaming=Join-Path $root 'Roaming'
$local=Join-Path $root 'Local'
$configRoot=Join-Path $roaming 'spicetify'
$config=Join-Path $configRoot 'config-xpui.ini'
$spotify=Join-Path $root 'FakeSpotify'
$xpui=Join-Path $spotify 'Apps\xpui'
$prefs=Join-Path $roaming 'Spotify\prefs'
$cli=Join-Path $root 'VendorCLI\spicetify.exe'
$cliApps=Join-Path $root 'VendorCLI\CustomApps'
$unknown=Join-Path $cliApps 'some-unmanaged-app'
foreach($dir in @($local,$xpui,(Split-Path -Parent $prefs),(Split-Path -Parent $cli),
 (Join-Path $cliApps 'better-local-files'),
 (Join-Path $cliApps 'ivlyrics'),
 (Join-Path $cliApps 'eternal-jukebox'),$unknown,$configRoot)){
 [IO.Directory]::CreateDirectory($dir)|Out-Null
}
[IO.File]::WriteAllText($cli,'V042_OFFICIAL_SHAPE_FAKE_CLI_NEVER_EXECUTED')
[IO.File]::WriteAllText($prefs,'V042_PRIVATE_PREFS_NEVER_READ')
[IO.File]::WriteAllText((Join-Path $xpui 'spicetify-routes-better-local-files.js'),'original')
[IO.File]::WriteAllText((Join-Path $xpui 'foreign-user-data.dat'),'V042_PRIVATE_FOREIGN_XPUI')
foreach($app in @('better-local-files','ivlyrics','eternal-jukebox')){
 $p=Join-Path $cliApps $app
 [IO.File]::WriteAllText((Join-Path $p 'index.js'),('V042_OFFICIAL_SOURCE_'+$app))
 [IO.File]::WriteAllText((Join-Path $p 'manifest.json'),('{"name":"'+$app+'"}'))
}
[IO.File]::WriteAllText((Join-Path $unknown 'index.js'),'V042_UNKNOWN_SOURCE_NEVER_EXAMINE')
[IO.File]::WriteAllText((Join-Path $unknown 'manifest.json'),'{"name":"private"}')
$nl=[Environment]::NewLine
$ini='[Setting]'+$nl+'spotify_path = '+$spotify+$nl+'prefs_path = '+$prefs+$nl+
 '[AdditionalOptions]'+$nl+'custom_apps = better-local-files|ivlyrics|eternal-jukebox|some-unmanaged-app'+$nl
[IO.File]::WriteAllText($config,$ini,[Text.UTF8Encoding]::new($false))
$args=@{HostedFixtureRoot=$root;HostedFixtureCliPath=$cli}
$beforeUnknown=(Get-FileHash -LiteralPath (Join-Path $unknown 'index.js') -Algorithm SHA256).Hash
$beforeForeign=(Get-FileHash -LiteralPath (Join-Path $xpui 'foreign-user-data.dat') -Algorithm SHA256).Hash
$beforeConfig=(Get-FileHash -LiteralPath $config -Algorithm SHA256).Hash
$good=Read-ActualSourceXpuiBindingSafeV042 @args
if([string]$good.status -cne 'observed-readonly'){
  Write-Host ('V042_READONLY_DIAGNOSTIC_STATUS='+[string]$good.status+
   '; reason='+[string]$good.reason)
}else{
  Write-Host ('V042_READONLY_DIAGNOSTIC_COUNTS=apps:'+[string]$good.source_tree_count+
    ';files:'+[string]$good.source_total_files+
    ';unmanaged:'+[string]$good.unmanaged_app_count+
    ';cli_apps:'+[string]$good.official_executable_origin_approved_count+
    ';xpui_files:'+[string]$good.xpui_file_count)
}
Assert-V042 ($good.status -ceq 'observed-readonly' -and
 [string]$good.binding_sha256 -cmatch '^[a-f0-9]{64}$' -and
 $good.source_tree_count -eq 3 -and
 $good.source_total_files -eq 6 -and
 $good.unmanaged_app_count -eq 1 -and
 $good.official_executable_origin_approved_count -eq 3 -and
 $good.user_config_origin_approved_count -eq 0 -and
 $good.xpui_file_count -eq 2 -and
 [bool]$good.no_writes -and -not[bool]$good.production_mutation_authorized) 'VALID_ORIGIN_AND_PROTECTED_XPUI_BOUNDARY'
$json=$good|ConvertTo-Json -Compress
Assert-V042 (-not$json.Contains($root) -and
 -not$json.Contains('better-local-files') -and
 -not$json.Contains('some-unmanaged-app') -and
 -not$json.Contains('V042_PRIVATE') -and
 -not$json.Contains('FakeSpotify')) 'SENSITIVE_ABSOLUTE_PATH_OR_SOURCE_NAME_LEAK'
$pin=[string]$good.binding_sha256
$again=Test-ActualSourceXpuiBindingV042 -ExpectedBindingSha256 $pin @args
Assert-V042 ([bool]$again.ok -and -not[bool]$again.production_mutation_authorized) 'STABLE_REAL_ORIGIN_PIN_FAILED'
Write-Host 'V042_THREE_EXECUTABLE_ORIGIN_SOURCES_CONFIG_AND_WHOLE_XPUI_BOUND_PASS'
# Byte change in one existing approved source fails requalification.
$source=Join-Path $cliApps 'ivlyrics\index.js'
$bytes=[IO.File]::ReadAllBytes($source)
[IO.File]::AppendAllText($source,'V042_SOURCE_RACE')
$d=Test-ActualSourceXpuiBindingV042 -ExpectedBindingSha256 $pin @args
Assert-V042 (-not[bool]$d.ok -and $d.reason -ceq 'V042_SOURCE_XPUI_CONFIG_OR_ORIGIN_DRIFTED') 'APP_SOURCE_RACE_NOT_REJECTED'
[IO.File]::WriteAllBytes($source,$bytes)
# Unrelated user-owned XPUI modification must block native admission.
$foreign=Join-Path $xpui 'foreign-user-data.dat'
$foreignBytes=[IO.File]::ReadAllBytes($foreign)
[IO.File]::AppendAllText($foreign,'V042_CONCURRENT_USER_WRITE')
$d=Test-ActualSourceXpuiBindingV042 -ExpectedBindingSha256 $pin @args
Assert-V042 (-not[bool]$d.ok -and $d.reason -ceq 'V042_SOURCE_XPUI_CONFIG_OR_ORIGIN_DRIFTED') 'FOREIGN_XPUI_USER_WRITE_IGNORED'
[IO.File]::WriteAllBytes($foreign,$foreignBytes)
# Source path location is part of fingerprint even if bytes stay identical.
$userApp=Join-Path $configRoot 'CustomApps\ivlyrics'
[IO.Directory]::CreateDirectory($userApp)|Out-Null
[IO.File]::WriteAllBytes((Join-Path $userApp 'index.js'),$bytes)
[IO.File]::WriteAllText((Join-Path $userApp 'manifest.json'),'{"name":"ivlyrics"}')
$d=Read-ActualSourceXpuiBindingSafeV042 @args
Assert-V042 ($d.status -ceq 'blocked' -and
 $d.reason -ceq 'V042_CONFIGURED_APP_OWNERSHIP_NOT_UNAMBIGUOUS') 'USER_ROOT_SHADOWED_SOURCE_ACCEPTED'
[IO.Directory]::Delete($userApp,$true)
# Configured unmanaged app is never scanned or changed, its source file
# does not grant mutation authority and is outside approved source binding.
[IO.File]::AppendAllText((Join-Path $unknown 'index.js'),'V042_UNMANAGED_USER_UPDATE')
$unmanaged=Test-ActualSourceXpuiBindingV042 -ExpectedBindingSha256 $pin @args
Assert-V042 ([bool]$unmanaged.ok) 'UNMANAGED_FOREIGN_APP_WAS_TREATED_AS_MANAGED'
# But changing the config list itself still breaks the initial pin.
[IO.File]::WriteAllText($config,$ini.Replace('some-unmanaged-app','some-other-unmanaged-app'))
$d=Test-ActualSourceXpuiBindingV042 -ExpectedBindingSha256 $pin @args
Assert-V042 (-not[bool]$d.ok) 'CONFIG_APP_LIST_RACE_NOT_REJECTED'
[IO.File]::WriteAllText($config,$ini,[Text.UTF8Encoding]::new($false))
Assert-V042 ([bool](Test-ActualSourceXpuiBindingV042 -ExpectedBindingSha256 $pin @args).ok) 'RESTORED_SOURCE_BINDING_NOT_IDEMPOTENT'
Assert-V042 ((Get-FileHash $config -Algorithm SHA256).Hash -ceq $beforeConfig -and
 (Get-FileHash $foreign -Algorithm SHA256).Hash -ceq $beforeForeign -and
 (Get-FileHash (Join-Path $unknown 'index.js') -Algorithm SHA256).Hash -cne $beforeUnknown) 'INDEPENDENT_SOURCE_OR_USER_STATE_UNEXPECTED'
Write-Host 'V042_APPROVED_SOURCE_FOREIGN_XPUI_AND_CONFIG_DRIFT_REJECTED_PASS'
Write-Host 'V042_UNKNOWN_CONFIGURED_APP_UNMANAGED_AND_UNTOUCHED_BY_ATTESTER_PASS'
Write-Host 'V042_IDENTICAL_CONTENT_SOURCE_ORIGIN_SHADOW_FAIL_CLOSED_PASS'
Write-Host 'V042_NO_NETWORK_NO_EXECUTABLE_NO_PROFILE_WRITE_NO_PRODUCTION_AUTHORITY_PASS'
