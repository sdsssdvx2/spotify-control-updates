# Focused Windows test for one final current-user read-only scan. No real apps.
param([Parameter(Mandatory=$true)][string]$OriginalBootstrap)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){throw 'HOSTED_ONLY'}
$repo=(Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$main=Join-Path $repo 'validation/v0.6.28/out/bin/spotify-control.ps1'
$addon=Join-Path $repo 'validation/v0.6.28/out/bin/addon-manager.ps1'
$agent=Join-Path $env:RUNNER_TEMP 'agent-v011-ci.vbs'
$preflight=Join-Path $PSScriptRoot 'onepass-installed-readonly-preflight.ps1'
$fixture=Join-Path $env:RUNNER_TEMP ('spotify-control-readonly-onepass-'+[Guid]::NewGuid().ToString('N'))
function Assert-Sha([string]$Path,[string]$Digest) {
  $actual=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
  if($actual -cne $Digest){throw 'TEST_INPUT_CANONICAL_SHA_UNVERIFIED'}
}
Assert-Sha $main 'af1582ec335807f8f5daa9b3a65b13d567264f326d3c608c082ae02ff0a4cfc0'
Assert-Sha $addon '5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285'
Assert-Sha $agent '2a4f6f02103ef9d4594e9fe4ac23fd4d94d4553902d6ddaf5fc3e10bebd56278'
Assert-Sha $OriginalBootstrap 'd9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6'
try{
  $root=Join-Path $fixture 'LocalAppData/SpotifyControl'
  $bin=Join-Path $root 'bin'
  $boot=Join-Path $root 'bootstrap'
  $roaming=Join-Path $fixture 'Roaming/spicetify'
  foreach($dir in @($bin,$boot,$roaming,(Join-Path $fixture 'Startup'))){
    [void][IO.Directory]::CreateDirectory($dir)
  }
  [IO.File]::Copy($main,(Join-Path $bin 'spotify-control.ps1'),$true)
  [IO.File]::Copy($addon,(Join-Path $bin 'addon-manager.ps1'),$true)
  [IO.File]::Copy($agent,(Join-Path $bin 'spotify-control-agent.vbs'),$true)
  [IO.File]::Copy($OriginalBootstrap,(Join-Path $boot 'spotify-control-self-updater.ps1'),$true)
  $state=[ordered]@{
    schema=20
    agent_mutation_enabled=$true
    pending_maintenance=$true
    maintenance_check_healthy=$true
    pending_addon_auto_ambiguous=0
  }
  [IO.File]::WriteAllText((Join-Path $root 'state.json'),
    ($state|ConvertTo-Json -Compress),(New-Object Text.UTF8Encoding($false)))
  [IO.File]::WriteAllText((Join-Path $roaming 'config-xpui.ini'),
    ((@('[AdditionalOptions]','custom_apps = ivLyrics|better-local-files')) -join [char]10),
    (New-Object Text.UTF8Encoding($false)))
  $expected=@(
    'MAIN=EXACT_STABLE',
    'ADDON=EXACT_STABLE',
    'RESIDENT_AGENT=EXACT_STABLE',
    'BOOTSTRAP=EXACT_STABLE',
    'STATE=READABLE;SCHEMA=20',
    'AGENT_MUTATION=ENABLED',
    'PENDING_MAINTENANCE=YES;HEALTH=HEALTHY;AUTO_AMBIGUITY=ZERO',
    'ADDON_PENDING_TRANSACTION=ABSENT',
    'SPICETIFY_CONFIG=CUSTOM_APPS_2',
    'EXACT_STABLE_SOURCE_SET=PASS',
    'RESULT=BASELINE_ATTESTED_LIVE_UPDATE_NOT_AUTHORIZED',
    'LIVE_INSTALL_AUTHORIZED=NO;CONFIG_EDIT=NO;SPOTIFY_UPDATE=NO;ORIGINALS_DELETE=NO',
    'CLIPBOARD=SKIPPED_HOSTED'
  )
  $lines=@(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $preflight -HostedFixtureRoot $fixture 2>&1)
  if($LASTEXITCODE -ne 0){throw 'ONEPASS_PREFLIGHT_HOSTED_PROCESS_FAILED'}
  $report=$lines -join [char]10
  foreach($value in $expected){
    if($lines -cnotcontains $value){throw ('HOSTED_PARSING_EXPECTATION_FAILED_'+$value)}
  }
  if($report -match '(?i)(Users\\|RUNNER_TEMP|AppData\\|([A-Za-z]:\\)|Bearer\s|secret\s*=|token\s*=)'){
    throw 'READONLY_OUTPUT_LEAKED_PII_OR_PATH'
  }
  Write-Host 'REAL_STABLE_V0628_R17_VBS_BOOTSTRAP_ONEPASS_READONLY_INSTALLED_FIXTURE_PASS'

  # WinPS 5.1 "False" STRING must never be treated as a verified boolean.
  # Presence of legacy in-flight add-on ledger stays visible, not consumed.
  $state.agent_mutation_enabled='False'
  [IO.File]::WriteAllText((Join-Path $root 'state.json'),
    ($state|ConvertTo-Json -Compress),(New-Object Text.UTF8Encoding($false)))
  [IO.File]::WriteAllText((Join-Path $root 'addon-last-transaction.json'),'{}',
    (New-Object Text.UTF8Encoding($false)))
  $again=@(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $preflight -HostedFixtureRoot $fixture 2>&1)
  if($LASTEXITCODE -ne 0 -or $again -cnotcontains 'AGENT_MUTATION=UNKNOWN' -or
     $again -cnotcontains 'ADDON_PENDING_TRANSACTION=PRESENT' -or
     $again -cnotcontains 'LIVE_INSTALL_AUTHORIZED=NO;CONFIG_EDIT=NO;SPOTIFY_UPDATE=NO;ORIGINALS_DELETE=NO'){
    throw 'FALSE_BOOLEAN_OR_PENDING_TRANSACTION_NOT_FAIL_CLOSED'
  }
  Write-Host 'FALSE_BOOL_AGENT_SETTING_AND_PENDING_TRANSACTION_READONLY_FAIL_CLOSED_PASS'

  # Tamper must never be misrepresented as stable canonical source.
  [IO.File]::WriteAllText((Join-Path $bin 'spotify-control.ps1'),'untrusted',
    (New-Object Text.UTF8Encoding($false)))
  $tampered=@(& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $preflight -HostedFixtureRoot $fixture 2>&1)
  if($LASTEXITCODE -ne 0 -or $tampered -cnotcontains 'MAIN=NOT_EXACT_STABLE' -or
     $tampered -cnotcontains 'EXACT_STABLE_SOURCE_SET=NOT_PROVEN' -or
     $tampered -cnotcontains 'RESULT=HOLD_CURRENT_INSTALL_UNVERIFIED'){
    throw 'MODIFIED_INSTALLED_MAIN_NOT_BLOCKED'
  }
  Write-Host 'MODIFIED_MAIN_REJECTED_NO_DEPLOY_PASS'
}finally{
  if([IO.Directory]::Exists($fixture)){
    Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
  }
}
