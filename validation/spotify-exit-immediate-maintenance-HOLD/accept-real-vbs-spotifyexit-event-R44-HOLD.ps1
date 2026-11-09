# R44 HOLD native WScript/WMI/PowerShell bridge, hosted scratch only.
# Real exact released-candidate VBS + synthetic Spotify.exe + benign PS observer.
[CmdletBinding()]
param()
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){throw 'R44_HOSTED_WINDOWS_ONLY'}
$root=Join-Path $env:RUNNER_TEMP 'Spotify Control R44 Actual Exit Event'
if(Test-Path -LiteralPath $root){throw 'R44_SCRATCH_PREEXISTING_NO_REPLACE'}
$bin=Join-Path $root 'bin'
$source='validation/spotify-exit-immediate-maintenance-HOLD/out/integrated/spotify-control-agent.vbs'
$agent=Join-Path $bin 'spotify-control-agent.vbs'
$control=Join-Path $bin 'spotify-control.ps1'
$events=Join-Path $root 'agent-events.txt'
$hostLog=Join-Path (Join-Path $root 'logs') 'resident-agent-host.log'
$fakeExe=Join-Path $root 'Spotify.exe'
$fake=$null
$resident=$null
function Hash([string]$p){return (Get-FileHash -LiteralPath $p -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()}
function EventCount([string]$name){
  if(-not(Test-Path -LiteralPath $events -PathType Leaf)){return 0}
  return @((Get-Content -LiteralPath $events -ErrorAction Stop) | Where-Object { [string]$_ -ceq ('AgentTick|'+$name) }).Count
}
function WaitEvent([string]$name,[int]$seconds){
  for($i=0;$i -lt $seconds*4;$i++){
    if((EventCount $name) -gt 0){return $true}
    if($null -ne $resident){
      $resident.Refresh()
      if($resident.HasExited){throw 'R44_REAL_VBS_HOST_EXITED_BEFORE_EVENT'}
    }
    Start-Sleep -Milliseconds 250
  }
  return $false
}
try {
  [void][IO.Directory]::CreateDirectory($bin)
  if((Hash $source) -cne 'da054351cae6927504e735426d35f6d5e7edafcac7e06881f1adf1c20cecab9d'){throw 'R44_INTEGRATED_VBS_HASH_NOT_PINNED'}
  [IO.File]::Copy((Resolve-Path $source).Path,$agent,$false)
  # The normal VBS dispatch is unmodified. Only the requested PS entrypoint
  # points to a disposable no-op observer, which writes one event text line.
  @'
[CmdletBinding()]
param([string]$Action='', [string]$AgentEvent='')
if($Action -cne 'AgentTick' -or $AgentEvent -cnotin @('Startup','SpotifyExit','Periodic')){exit 41}
$destination=Join-Path (Split-Path -Parent $PSScriptRoot) 'agent-events.txt'
[IO.File]::AppendAllText($destination,('AgentTick|'+$AgentEvent+[Environment]::NewLine),[Text.Encoding]::ASCII)
'@ | Set-Content -LiteralPath $control -Encoding ASCII
  $tokens=$null; $errors=$null
  [void][Management.Automation.Language.Parser]::ParseFile($control,[ref]$tokens,[ref]$errors)
  if(@($errors).Count){throw 'R44_SCRATCH_POWERSHELL_STUB_PARSE_FAILED'}
  if(@(Get-CimInstance Win32_Process -Filter "Name='Spotify.exe'" -ErrorAction Stop).Count -ne 0){throw 'R44_RUNNER_FOREIGN_SPOTIFY_PROCESS_PRESENT'}
  Add-Type -TypeDefinition @'
using System;
using System.Threading;
public class SyntheticSpotifyProcess {
  public static int Main(string[] args) { Thread.Sleep(210000); return 0; }
}
'@ -OutputAssembly $fakeExe -OutputType ConsoleApplication -ErrorAction Stop
  if(-not(Test-Path -LiteralPath $fakeExe -PathType Leaf)){throw 'R44_SYNTHETIC_SPOTIFY_COMPILATION_MISSING'}
  $fake=Start-Process -FilePath $fakeExe -WorkingDirectory $root -PassThru -ErrorAction Stop
  Start-Sleep -Milliseconds 700
  $visible=@(Get-CimInstance Win32_Process -Filter "Name='Spotify.exe'" -ErrorAction Stop)
  if($visible.Count -ne 1 -or [int]$visible[0].ProcessId -ne $fake.Id -or -not [string]::Equals([string]$visible[0].ExecutablePath,$fakeExe,[StringComparison]::OrdinalIgnoreCase)){throw 'R44_SYNTHETIC_SPOTIFY_WMI_PROCESS_NOT_EXACT'}
  Write-Host 'R44_SYNTHETIC_SPOTIFY_EXE_REAL_WMI_PROCESS=VERIFIED'
  $wscript=Join-Path $env:WINDIR 'System32/wscript.exe'
  $resident=Start-Process -FilePath $wscript -WorkingDirectory $bin -ArgumentList ('//B //NoLogo "'+$agent+'"') -PassThru -ErrorAction Stop
  if(-not(WaitEvent 'Startup' 40)){throw 'R44_REAL_VBS_STARTUP_EVENT_NOT_RECEIVED'}
  if((EventCount 'SpotifyExit') -ne 0){throw 'R44_FALSE_EXIT_EVENT_WHILE_RUNNING'}
  Write-Host 'R44_REAL_VBS_STARTUP_TICK_TO_POWERSHELL=PASS'
  $moved=Join-Path $root 'bin-temporary-rename'
  [IO.Directory]::Move($bin,$moved)
  [IO.Directory]::Move($moved,$bin)
  $resident.Refresh()
  if($resident.HasExited){throw 'R44_HOST_EXITED_AFTER_BIN_RENAME'}
  Write-Host 'R44_REAL_VBS_NEUTRAL_CWD_AND_BIN_RENAME=PASS'
  $fake.Refresh()
  if($fake.HasExited){throw 'R44_SYNTHETIC_SPOTIFY_EXITED_BEFORE_OWNED_STOP'}
  $identity=@(Get-CimInstance Win32_Process -Filter ('ProcessId='+$fake.Id) -ErrorAction Stop)
  if($identity.Count -ne 1 -or -not [string]::Equals([string]$identity[0].ExecutablePath,$fakeExe,[StringComparison]::OrdinalIgnoreCase)){throw 'R44_TEST_OWNED_FAKE_PROCESS_IDENTITY_DRIFT'}
  Stop-Process -Id $fake.Id -Force -ErrorAction Stop
  [void]$fake.WaitForExit(5000)
  if(@(Get-CimInstance Win32_Process -Filter "Name='Spotify.exe'" -ErrorAction Stop).Count -ne 0){throw 'R44_FAKE_PROCESS_STILL_RUNNING'}
  Write-Host 'R44_EXACT_TEST_OWNED_SPOTIFY_STOPPED=PASS'
  if(-not(WaitEvent 'SpotifyExit' 105)){throw 'R44_REAL_VBS_POLL_SETTLE_NO_EXIT_DISPATCH'}
  if((EventCount 'SpotifyExit') -ne 1){throw 'R44_REAL_EXIT_NOT_EXACTLY_ONE_TICK'}
  if(-not(Test-Path -LiteralPath $hostLog -PathType Leaf)){throw 'R44_REAL_VBS_HOST_LOG_MISSING'}
  $lines=@(Get-Content -LiteralPath $hostLog)
  if(@($lines | Where-Object {$_ -like '*SPOTIFY EXIT confirmed*'}).Count -ne 1 -or @($lines | Where-Object {$_ -like '*TICK LAUNCHED event=SpotifyExit*'}).Count -ne 1){throw 'R44_REAL_VBS_HOST_LOG_DISPATCH_NOT_PROVEN'}
  Write-Host 'R44_ACTUAL_WMI_SPOTIFY_EXIT_VBS_SETTLE_AND_EVENT=PASS'
  Write-Host 'R44_AUTHENTIC_WSCRIPT_TO_POWERSHELL_AGENTTICK_SPOTIFYEXIT=PASS'
  Write-Host 'R44_REAL_POWERSHELL_MAINTENANCE_HANDLER=NOT_INVOKED_STUB_ONLY'
  Write-Host 'R44_RELEASABLE_VBS_BYTES=UNMODIFIED;PRODUCTION_MAIN_OR_PC=UNTOUCHED'
} finally {
  if($null -ne $resident){try{$resident.Refresh();if(-not $resident.HasExited){Stop-Process -Id $resident.Id -Force -ErrorAction SilentlyContinue;[void]$resident.WaitForExit(5000)}}catch{}}
  if($null -ne $fake){try{$fake.Refresh();if(-not $fake.HasExited){Stop-Process -Id $fake.Id -Force -ErrorAction SilentlyContinue;[void]$fake.WaitForExit(5000)}}catch{}}
  if(Test-Path -LiteralPath $root){Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue}
}
