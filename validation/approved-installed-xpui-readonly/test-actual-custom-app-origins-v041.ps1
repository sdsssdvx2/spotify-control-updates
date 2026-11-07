# V041 targeted, read-only official custom app path precedence; Windows CI.
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot 'installed-xpui-readonly.ps1')
. (Join-Path $PSScriptRoot 'actual-custom-app-origins-v041.ps1')
function Assert-V041([bool]$Condition,[string]$Reason){
 if(-not$Condition){throw ('V041_TEST_'+$Reason)}
}
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
 $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
 [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
 throw 'V041_TEST_HOSTED_WINDOWS_ONLY'
}
$fixture=Join-Path $env:RUNNER_TEMP ('v041-app-origin-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
$roaming=Join-Path $fixture 'Roaming'
$local=Join-Path $fixture 'Local'
$configRoot=Join-Path $roaming 'spicetify'
$config=Join-Path $configRoot 'config-xpui.ini'
$spotify=Join-Path $fixture 'FakeSpotify'
$xpui=Join-Path $spotify 'Apps\xpui'
$prefs=Join-Path $roaming 'Spotify\prefs'
$exe=Join-Path $fixture 'Tools\spicetify.exe'
$first=Join-Path $configRoot 'CustomApps'
$second=Join-Path $fixture 'Tools\CustomApps'
$primaryApp=Join-Path $first 'better-local-files'
$shadowApp=Join-Path $second 'better-local-files'
$secondApp=Join-Path $second 'ivlyrics'
$nested=Join-Path $second 'eternal-jukebox\archive\compiled'
$unknown=Join-Path $second 'lyrics-plus'
foreach($p in @($local,$xpui,(Split-Path -Parent $prefs),
 (Split-Path -Parent $exe),$primaryApp,$shadowApp,$secondApp,
 $nested,$unknown)){
 [IO.Directory]::CreateDirectory($p)|Out-Null
}
[IO.File]::WriteAllText($exe,'V041_CI_FIXTURE_NEVER_EXECUTE')
[IO.File]::WriteAllText($prefs,'V041_PRIVATE_PREFS_SHOULD_NEVER_APPEAR')
[IO.File]::WriteAllText((Join-Path $xpui 'foreign-owned.dat'),'V041_PRIVATE_XPUI_FILE')
[IO.File]::WriteAllText((Join-Path $primaryApp 'index.js'),'V041_PRIMARY_INDEX')
[IO.File]::WriteAllText((Join-Path $primaryApp 'manifest.json'),'{"name":"V041_TEST"}')
[IO.File]::WriteAllText((Join-Path $shadowApp 'index.js'),'V041_SHADOW_NOT_TO_READ')
[IO.File]::WriteAllText((Join-Path $shadowApp 'manifest.json'),'{"name":"SHADOW"}')
[IO.File]::WriteAllText((Join-Path $secondApp 'index.js'),'V041_CLI_ROOT_INDEX')
[IO.File]::WriteAllText((Join-Path $secondApp 'manifest.json'),'{"name":"V041_TEST"}')
[IO.File]::WriteAllText((Join-Path $nested 'index.js'),'V041_NESTED_INDEX')
[IO.File]::WriteAllText((Join-Path $nested 'manifest.json'),'{"name":"V041_TEST"}')
[IO.File]::WriteAllText((Join-Path $unknown 'index.js'),'V041_UNMANAGED_PRIVATE_APP')
[IO.File]::WriteAllText((Join-Path $unknown 'manifest.json'),'{"name":"UNMANAGED"}')
$nl=[Environment]::NewLine
$ini='[Setting]'+$nl+'spotify_path = '+$spotify+$nl+
 'prefs_path = '+$prefs+$nl+'[AdditionalOptions]'+$nl+
 'custom_apps = better-local-files|ivLyrics|eternal-jukebox|lyrics-plus'+$nl
[IO.File]::WriteAllText($config,$ini,[Text.UTF8Encoding]::new($false))
$unchanged=@{}
foreach($path in @($config,$prefs,(Join-Path $xpui 'foreign-owned.dat'),
 (Join-Path $unknown 'index.js'),(Join-Path $shadowApp 'index.js'))){
 $unchanged[$path]=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
}
function Inspect-V041 {
 return Test-ActualCustomAppOriginsReadOnlyV041 -HostedFixtureRoot $fixture -HostedFixtureCliPath $exe
}
$r=Inspect-V041
Assert-V041 ($r.status -ceq 'observed-readonly' -and
 $r.official_cli_source_resolution -ceq 'hosted-synthetic-only' -and
 -not[bool]$r.exact_cli_sha_verified -and
 $r.approved_config_apps -eq 3 -and $r.other_config_apps -eq 1 -and
 $r.approved_user_origin -eq 1 -and $r.approved_cli_origin -eq 2 -and
 $r.approved_source_missing -eq 0 -and $r.approved_source_incomplete -eq 0 -and
 $r.approved_nested_source -eq 1 -and $r.approved_origin_shadowed -eq 1 -and
 [bool]$r.all_approved_sources_structurally_complete -and
 [bool]$r.unknown_apps_preserved -and
 -not[bool]$r.production_mutation_authorized) 'OFFICIAL_SOURCE_RESOLUTION_PRECEDENCE_INCORRECT'
$json=$r|ConvertTo-Json -Compress
Assert-V041 (-not$json.Contains($fixture) -and -not$json.Contains('lyrics-plus') -and
 -not$json.Contains('V041_PRIVATE') -and -not$json.Contains('better-local-files') -and
 -not$json.Contains('SPICETIFY_CONFIG')) 'SENSITIVE_LOCATION_OR_APP_NAMES_EXPOSED'
foreach($f in @($unchanged.Keys)){
 Assert-V041 ((Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash -ceq [string]$unchanged[$f]) 'READONLY_CHANGED_SENSITIVE_FIXTURE_INPUT'
}
Write-Host 'V041_OFFICIAL_PRIMARY_VS_EXECUTABLE_FALLBACK_AND_NESTED_RESOLUTION_PASS'
Write-Host 'V041_SHADOWED_USER_PRIMARY_WINS_AND_UNMANAGED_APP_UNTOUCHED_PASS'
# A configured approved app with no manifest is NOT automatically
# installable, even if the vendor would locate its folder.
$manifest=Join-Path $secondApp 'manifest.json'
[IO.File]::Move($manifest,($manifest+'.test-unavailable'))
try {
 $bad=Inspect-V041
 Assert-V041 ($bad.status -ceq 'observed-readonly' -and
 $bad.approved_source_incomplete -eq 1 -and
 -not[bool]$bad.all_approved_sources_structurally_complete) 'MISSING_MANIFEST_SILENTLY_APPROVED'
}finally{[IO.File]::Move(($manifest+'.test-unavailable'),$manifest)}
# Two child app entrypoints would be order-dependent in Go: fail closed.
$collision=Join-Path $second 'eternal-jukebox\another\compiled'
[IO.Directory]::CreateDirectory($collision)|Out-Null
[IO.File]::WriteAllText((Join-Path $collision 'index.js'),'AMBIGUOUS_NESTED')
$ambiguous=Inspect-V041
Assert-V041 ($ambiguous.status -ceq 'blocked' -and
 $ambiguous.reason -ceq 'V041_SOURCE_AMBIGUOUS_NESTED_APPS') 'TWO_NESTED_APPS_ACCEPTED'
# Simulate a configured app not installed in either vendor-supported root.
$missing=Join-Path $second 'ivlyrics'
[IO.Directory]::Move($missing,($missing+'-not-present-in-ci'))
try{
 $absent=Inspect-V041
 Assert-V041 ($absent.status -ceq 'blocked' -and
 $absent.reason -ceq 'V041_SOURCE_AMBIGUOUS_NESTED_APPS') 'MULTIPLE_NEGATIVES_UNEXPECTED'
}finally{[IO.Directory]::Move(($missing+'-not-present-in-ci'),$missing)}
# The valid baseline must still pass after all synthetic negative probes.
[IO.Directory]::Delete($collision,$true)
Assert-V041 ((Inspect-V041).approved_source_missing -eq 0) 'VALID_BASELINE_NOT_RESTORED'
[IO.Directory]::Move($missing,($missing+'-not-present-in-ci'))
try{
 $absent=Inspect-V041
 Assert-V041 ($absent.status -ceq 'observed-readonly' -and
 $absent.approved_source_missing -eq 1 -and
 -not[bool]$absent.all_approved_sources_structurally_complete) 'MISSING_APPROVED_SOURCE_SILENTLY_ACCEPTED'
}finally{[IO.Directory]::Move(($missing+'-not-present-in-ci'),$missing)}
$outside=Test-ActualCustomAppOriginsReadOnlyV041 -HostedFixtureRoot $env:SystemRoot -HostedFixtureCliPath $exe
Assert-V041 ($outside.status -ceq 'blocked') 'FIXTURE_BYPASSED_RUNNER_BOUNDARY'
Write-Host 'V041_INCOMPLETE_MISSING_DUPLICATE_NESTED_AND_OUTSIDE_ROOT_FAIL_CLOSED_PASS'
Write-Host 'V041_NO_APP_CONTENT_READ_NO_CONFIG_WRITE_NO_SPOTIFY_NO_PROCESS_NO_NETWORK_PASS'
