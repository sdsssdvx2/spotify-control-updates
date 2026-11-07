# V043: one REAL pinned Spicetify CLI refresh on a disposable FakeSpotify
# with all three approved CustomApps located NEXT TO the CLI executable
# (official GetCustomAppPath fallback), plus one unmanaged configured app.
# The original 4-app config is READ ONLY; only an isolated temporary
# one-app config is passed to the official CLI. Nothing touches user Spotify.
param([Parameter(Mandatory=$true)][string]$OfficialExecutable)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
 throw 'V043_HOSTED_WINDOWS_ONLY'
}
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $repo 'validation/custom-app-update-transaction-protocol-v0.1.0/custom-app-update-transaction.ps1')
. (Join-Path $PSScriptRoot 'installed-xpui-readonly.ps1')
. (Join-Path $PSScriptRoot 'actual-custom-app-origins-v041.ps1')
. (Join-Path $PSScriptRoot 'verified-source-xpui-binding-v042.ps1')
. (Join-Path $repo 'validation/approved-real-native-xpui-crash-restore/native-xpui-escrow-recovery.ps1')
function Assert-V043([bool]$ok,[string]$why){if(-not$ok){throw ('V043_TEST_'+$why)}}
$binary='3563f26acd7527adc97e6c19272fa1b48ce976a913625d9804ac57d3c54fb4db'
$provided=Assert-XpuiReadOnlyCanonicalV036 -Path $OfficialExecutable -Label 'ORIGINAL_OFFICIAL_CLI'
if((Get-FileHash -LiteralPath $provided -Algorithm SHA256).Hash.ToLowerInvariant() -cne $binary){
 throw 'V043_ORIGINAL_CLI_PIN_CHANGED'
}
$root=Join-Path $env:RUNNER_TEMP ('v043-physical-fallback-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
$vendor=Join-Path $root 'VendorCLI'
$exe=Join-Path $vendor 'spicetify.exe'
$roaming=Join-Path $root 'Roaming'
$local=Join-Path $root 'Local'
$configRoot=Join-Path $roaming 'spicetify'
$config=Join-Path $configRoot 'config-xpui.ini'
$oneConfig=Join-Path $root 'PrivateSingleAppConfig'
$privateIni=Join-Path $oneConfig 'config-xpui.ini'
$spotify=Join-Path $root 'FakeSpotify'
$xpui=Join-Path $spotify 'Apps\xpui'
$prefs=Join-Path $roaming 'Spotify\prefs'
$backup=Join-Path $oneConfig 'Backup'
$cliApps=Join-Path $vendor 'CustomApps'
$targetName='better-local-files'
$names=@($targetName,'ivlyrics','eternal-jukebox','some-unmanaged-app')
foreach($d in @($vendor,$local,$configRoot,$oneConfig,$xpui,(Split-Path -Parent $prefs),$backup)){
 [IO.Directory]::CreateDirectory($d)|Out-Null
}
[IO.File]::Copy($provided,$exe,$false)
Assert-V043 ((Get-FileHash $exe -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $binary) 'FIXTURE_CLI_BYTE_PIN_MISMATCH'
foreach($name in $names){
 $p=Join-Path $cliApps $name
 [IO.Directory]::CreateDirectory($p)|Out-Null
 [IO.File]::WriteAllText((Join-Path $p 'index.js'),('const V043_APP_SOURCE_'+$name.Replace('-','_')+'=true;'))
 [IO.File]::WriteAllText((Join-Path $p 'style.css'),('/* V043_SOURCE_CSS_'+$name+' */'))
 [IO.File]::WriteAllText((Join-Path $p 'manifest.json'),('{"name":"'+$name+'"}'))
}
$foreign=@('spicetify-routes-ivlyrics.js','spicetify-routes-eternal-jukebox.js',
 'spicetify-routes-some-unmanaged-app.js','user-settings-dont-change.dat')
foreach($relative in $foreign){
 [IO.File]::WriteAllText((Join-Path $xpui $relative),('ORIGINAL_V043_'+$relative))
}
$destination=Join-Path $xpui ('spicetify-routes-'+$targetName+'.js')
[IO.File]::WriteAllText($destination,'V043_OLD_SELECTED_ROUTE')
[IO.File]::WriteAllText($prefs,'app.last-launched-version = 1.2.3'+[Environment]::NewLine)
[IO.File]::WriteAllBytes((Join-Path $backup 'xpui.spa'),[byte[]](0x50,0x4b))
$nl=[Environment]::NewLine
$settings='[Setting]'+$nl+'spotify_path = '+$spotify+$nl+
  'prefs_path = '+$prefs+$nl+'check_spicetify_update = false'+$nl+
  'current_theme = '+$nl+'[Backup]'+$nl+
  'version = 1.2.3'+$nl+'with = 2.46.4'+$nl+'[AdditionalOptions]'+$nl
[IO.File]::WriteAllText($config,($settings+'custom_apps = '+($names -join '|')+$nl),[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($privateIni,($settings+'custom_apps = '+$targetName+$nl),[Text.UTF8Encoding]::new($false))
$originalConfig=(Get-FileHash $config -Algorithm SHA256).Hash
$originalPrefs=(Get-FileHash $prefs -Algorithm SHA256).Hash
$sourceDigests=@{}
foreach($name in $names){
 $f=Join-Path $cliApps ($name+'\index.js')
 $sourceDigests[$f]=(Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash
}
$before=Get-CustomAppUpdateTreeSnapshotV010 -Root $xpui
$baseline=Read-ActualSourceXpuiBindingSafeV042 -HostedFixtureRoot $root -HostedFixtureCliPath $exe
Assert-V043 ([string]$baseline.status -ceq 'observed-readonly' -and
 [int]$baseline.source_tree_count -eq 3 -and
 [int]$baseline.unmanaged_app_count -eq 1 -and
 [int]$baseline.official_executable_origin_approved_count -eq 3) 'UNMODIFIED_REAL_LAYOUT_BASELINE_NOT_BOUND'
$psi=New-Object Diagnostics.ProcessStartInfo
$psi.FileName=$exe
$psi.Arguments='--bypass-admin -n -a refresh'
$psi.WorkingDirectory=$root
$psi.UseShellExecute=$false
$psi.CreateNoWindow=$true
$psi.RedirectStandardOutput=$true
$psi.RedirectStandardError=$true
$psi.EnvironmentVariables['SPICETIFY_CONFIG']=$oneConfig
$psi.EnvironmentVariables['SPICETIFY_STATE']=$oneConfig
$psi.EnvironmentVariables['APPDATA']=$roaming
$psi.EnvironmentVariables['LOCALAPPDATA']=$local
$proc=New-Object Diagnostics.Process
try{
 $proc.StartInfo=$psi
 if(-not$proc.Start()){throw 'V043_OFFICIAL_CLI_START_FAILED'}
 if(-not$proc.WaitForExit(60000)){
   $proc.Kill();[void]$proc.WaitForExit()
   throw 'V043_OFFICIAL_CLI_TIMEOUT'
 }
 if($proc.ExitCode -ne 0){
   # Never print stdout/stderr: CLI may emit sensitive paths in other contexts.
   throw ('V043_OFFICIAL_CLI_FAILED_EXIT_CODE_'+$proc.ExitCode)
 }
}finally{$proc.Dispose()}
$after=Get-CustomAppUpdateTreeSnapshotV010 -Root $xpui
[void](Test-ApprovedNativeXpuiOnlyOwnedTargetChangedV035 -Before $before -After $after -Name $targetName)
$owned=@(
 ('spicetify-routes-'+$targetName+'.js'),
 ('spicetify-routes-'+$targetName+'.css'),
 ('spicetify-routes-'+$targetName+'.json'))
foreach($rel in $owned){
 $row=@($after.entries|Where-Object{[string]$_.path -ceq $rel})
 Assert-V043 ($row.Count -eq 1 -and [string]$row[0].type -ceq 'file') 'ONE_OF_THREE_OFFICIAL_OWNED_OUTPUTS_MISSING'
}
$generated=[IO.File]::ReadAllText($destination)
Assert-V043 ($generated.Contains('V043_APP_SOURCE_better_local_files') -and
 -not$generated.Contains('V043_APP_SOURCE_ivlyrics') -and
 [string]$after.tree_sha256 -cne [string]$before.tree_sha256) 'NATIVE_EXECUTABLE_FALLBACK_APP_NOT_SELECTED'
foreach($f in @($sourceDigests.Keys)){
 Assert-V043 ((Get-FileHash $f -Algorithm SHA256).Hash -ceq $sourceDigests[$f]) 'OFFICIAL_REFRESH_CHANGED_SIBLING_APP_SOURCE'
}
Assert-V043 ((Get-FileHash $config -Algorithm SHA256).Hash -ceq $originalConfig -and
 (Get-FileHash $prefs -Algorithm SHA256).Hash -ceq $originalPrefs) 'OFFICIAL_REFRESH_CHANGED_USER_CONFIG_OR_PREFS'
foreach($rel in $foreign){
 Assert-V043 ([IO.File]::ReadAllText((Join-Path $xpui $rel)) -ceq ('ORIGINAL_V043_'+$rel)) 'NATIVE_REFRESH_CHANGED_OTHER_APPROVED_OR_UNMANAGED_OUTPUT'
}
$drift=Test-ActualSourceXpuiBindingV042 -ExpectedBindingSha256 ([string]$baseline.binding_sha256) -HostedFixtureRoot $root -HostedFixtureCliPath $exe
Assert-V043 (-not[bool]$drift.ok -and [string]$drift.reason -ceq 'V042_SOURCE_XPUI_CONFIG_OR_ORIGIN_DRIFTED') 'READONLY_PRELAUNCH_PIN_DID_NOT_DETECT_OFFICIAL_OUTPUT'
$rebased=Read-ActualSourceXpuiBindingSafeV042 -HostedFixtureRoot $root -HostedFixtureCliPath $exe
Assert-V043 ($rebased.status -ceq 'observed-readonly' -and
 $rebased.binding_sha256 -cne $baseline.binding_sha256 -and
 $rebased.source_tree_count -eq 3 -and
 [bool](Test-ActualSourceXpuiBindingV042 -ExpectedBindingSha256 ([string]$rebased.binding_sha256) -HostedFixtureRoot $root -HostedFixtureCliPath $exe).ok) 'NEW_READONLY_SOURCE_PIN_NOT_READABLE'
Assert-V043 (-not[IO.Directory]::Exists((Join-Path $local 'SpotifyControlUpdates-CustomApp-State'))) 'TEST_CREATED_REAL_USER_TRANSACTION_LEDGER'
Write-Host 'V043_REAL_OFFICIAL_CLI_EXECUTABLE_ROOT_CUSTOMAPPS_FALLBACK_PASS'
Write-Host 'V043_ONE_APPROVED_APP_ONLY_OTHER_APPROVED_AND_UNMANAGED_XPUI_UNCHANGED_PASS'
Write-Host 'V043_ORIGINAL_CONFIG_PREFS_FOUR_APP_SOURCES_UNCHANGED_PASS'
Write-Host 'V043_V042_PRELAUNCH_IMMUTABLE_HASH_DRIFT_AND_REBASE_PASS'
Write-Host 'V043_FAKE_SPOTIFY_ONLY_NO_LEDGER_NO_PRODUCTION_AUTHORITY_PASS'
