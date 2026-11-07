# V036 synthetic fixture tests; Windows hosted CI only.
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot 'installed-xpui-readonly.ps1')
function Require-V036([bool]$Test,[string]$Why){if(-not$Test){throw ('V036_TEST_'+$Why)}}
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted'){throw 'V036_HOSTED_TEST_ONLY'}
$base=Join-Path $env:RUNNER_TEMP ('v036-test-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
$r=Join-Path $base 'Roaming';$l=Join-Path $base 'Local'
$c=Join-Path $r 'spicetify';$s=Join-Path $base 'Spotify'
$xpui=Join-Path $s 'Apps\xpui';$prefs=Join-Path $r 'Spotify\prefs'
$cfg=Join-Path $c 'config-xpui.ini'
foreach($d in @($l,$c,$xpui,(Join-Path $r 'Spotify'),(Join-Path $c 'CustomApps\better-local-files'))){
  [IO.Directory]::CreateDirectory($d)|Out-Null
}
[IO.File]::WriteAllText($prefs,'PRIVATE_PREFS_DO_NOT_RETURN')
[IO.File]::WriteAllText((Join-Path $xpui 'spicetify-routes-better-local-files.js'),'before')
[IO.File]::WriteAllText((Join-Path $xpui 'user-foreign.dat'),'PRIVATE_FOREIGN_DO_NOT_RETURN')
$nl=[Environment]::NewLine
$ini=('[Setting]'+$nl+'spotify_path = '+$s+$nl+'prefs_path = '+$prefs+$nl+
 '[AdditionalOptions]'+$nl+'custom_apps = better-local-files'+$nl)
[IO.File]::WriteAllText($cfg,$ini,[Text.UTF8Encoding]::new($false))
$before=(Get-FileHash $cfg -Algorithm SHA256).Hash
$foreign=(Get-FileHash (Join-Path $xpui 'user-foreign.dat') -Algorithm SHA256).Hash
$ok=Test-InstalledXpuiReadOnlyV036 -HostedFixtureRoot $base
Require-V036 ($ok.status -ceq 'observed-readonly' -and
 $ok.xpui_state -ceq 'extracted-directory' -and
 $ok.snapshot_policy -ceq 'within-v010-limits' -and
 $ok.approved_config_apps -eq 1 -and $ok.approved_local_apps -eq 1 -and
 $ok.other_config_apps -eq 0 -and
 -not$ok.production_mutation_authorized -and -not$ok.no_network -eq $false) 'EXPECTED_BASE_INVENTORY'
Require-V036 ((Get-FileHash $cfg -Algorithm SHA256).Hash -ceq $before -and
 (Get-FileHash (Join-Path $xpui 'user-foreign.dat') -Algorithm SHA256).Hash -ceq $foreign) 'READONLY_DATA_CHANGED'
$json=$ok|ConvertTo-Json -Compress
Require-V036 (-not$json.Contains($base) -and -not$json.Contains('PRIVATE_') -and
 -not$json.Contains('spotify_path') -and -not$json.Contains('prefs_path')) 'PRIVATE_CONFIG_OUTPUT'
[IO.File]::WriteAllText($cfg,$ini+'spotify_path = '+$s+$nl)
$dupe=Test-InstalledXpuiReadOnlyV036 -HostedFixtureRoot $base
Require-V036 ($dupe.status -ceq 'blocked' -and $dupe.reason -ceq 'V036_CONFIG_DUPLICATE_KEY') 'DUPLICATE_KEY_ALLOWED'
[IO.File]::WriteAllText($cfg,$ini.Replace($s,'\\server\unc-spotify'))
$remote=Test-InstalledXpuiReadOnlyV036 -HostedFixtureRoot $base
Require-V036 ($remote.status -ceq 'blocked' -and $remote.reason -ceq 'V036_UNSAFE_SPOTIFY_PATH') 'UNC_ROOT_ALLOWED'
[IO.File]::WriteAllText($cfg,$ini)
[IO.File]::WriteAllText((Join-Path $xpui 'another-foreign.txt'),'another')
$foreignObserved=Test-InstalledXpuiReadOnlyV036 -HostedFixtureRoot $base
Require-V036 ($foreignObserved.status -ceq 'observed-readonly' -and $foreignObserved.xpui_file_count -eq 3) 'FOREIGN_CONTENT_NOT_INVENTORIED'
[IO.Directory]::Move($xpui,(Join-Path $s 'Apps\xpui-away'))
[IO.File]::WriteAllText((Join-Path $s 'Apps\xpui.spa'),'zip-stub')
$spa=Test-InstalledXpuiReadOnlyV036 -HostedFixtureRoot $base
Require-V036 ($spa.xpui_state -ceq 'spa-only' -and
 $spa.snapshot_policy -ceq 'not-applicable' -and -not$spa.terminal_commit_authorized) 'SPA_ONLY_WAS_TREATED_AS_XPUI'
$outside=Test-InstalledXpuiReadOnlyV036 -HostedFixtureRoot $env:SystemRoot
Require-V036 ($outside.status -ceq 'blocked' -and $outside.reason -ceq 'V036_FIXTURE_OUTSIDE_RUNNER') 'RUNNER_OUTSIDE_ALLOWED'
Write-Host 'V036_OFFICIAL_DOCUMENTED_PATHS_AND_CONFIG_XPUI_INSPECTED_PASS'
Write-Host 'V036_NO_PREFS_CONTENT_OR_PRIVATE_PATHS_EXPOSED_PASS'
Write-Host 'V036_DUPLICATE_UNC_OUTSIDE_FIXTURE_REJECTED_PASS'
Write-Host 'V036_XPUI_DIRECTORY_VS_SPA_ONLY_AND_V010_LIMITS_PASS'
Write-Host 'V036_CI_ONLY_FIXTURE_NO_INSTALL_CLI_NETWORK_MUTATION_PASS'
