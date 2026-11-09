# R22 inspect exact Spotify Control managed shortcut properties. READ ONLY.
# Emits only finite, fixed non-sensitive categories. No shortcut or agent writes.
[CmdletBinding()]
param([string]$HostedFixtureRoot='')
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$out=New-Object 'System.Collections.Generic.List[string]'
$out.Add('DIAGNOSTIC=SPOTIFY_R22_MANAGED_SHORTCUTS_READONLY')
$out.Add('SHORTCUT_WRITE=NO;AGENT_RESTART=NO;BOOTSTRAP=NO;BIN_WRITE=NO')
function PlainFile([string]$p) {
  try {
    $item=Get-Item -LiteralPath $p -Force -ErrorAction Stop
    return (-not $item.PSIsContainer -and
      ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -and
      $item.Length -ge 30 -and $item.Length -le 102400)
  }catch{return $false}
}
function SamePath([string]$a,[string]$b) {
  try {
    if([string]::IsNullOrWhiteSpace($a) -or [string]::IsNullOrWhiteSpace($b)){return $false}
    $a=[Environment]::ExpandEnvironmentVariables($a)
    $b=[Environment]::ExpandEnvironmentVariables($b)
    return [IO.Path]::GetFullPath($a).TrimEnd('\','/').Equals(
      [IO.Path]::GetFullPath($b).TrimEnd('\','/'),[StringComparison]::OrdinalIgnoreCase)
  }catch{return $false}
}
function TargetClass([string]$value,[string]$w32,[string]$w64) {
  if([string]::IsNullOrWhiteSpace($value)){return 'EMPTY'}
  if(SamePath $value $w32){return 'SYSTEM32_WSCRIPT'}
  if(SamePath $value $w64){return 'SYSWOW64_WSCRIPT'}
  if($value -match '(?i)(^|[\\/])cscript\.exe$'){return 'CSCRIPT'}
  if($value -match '(?i)(^|[\\/])(powershell|pwsh)\.exe$'){return 'POWERSHELL'}
  if($value -match '(?i)(^|[\\/])spotify\.exe$'){return 'SPOTIFY_EXE'}
  if($value -match '(?i)(^|[\\/])wscript\.exe$'){return 'OTHER_WSCRIPT'}
  return 'OTHER_TARGET'
}
function ArgsClass([string]$value,[string]$agent){
  if([string]::IsNullOrWhiteSpace($value)){return 'EMPTY'}
  $v=$value.Trim()
  if($v -ceq ('"'+$agent+'"')){return 'EXACT_QUOTED_AGENT'}
  if(SamePath $v $agent){return 'EXACT_UNQUOTED_AGENT'}
  # A single quoted VBS with optional WScript switches is categorically
  # distinct from a custom command and cannot be silently overwritten.
  $matches=[regex]::Matches($v,'(?i)(?:"([^"]+\.vbs)"|(?<=\s)([^\s"]+\.vbs)(?=\s|$))')
  if($matches.Count -eq 1){
    $vbs=if($matches[0].Groups[1].Success){$matches[0].Groups[1].Value}else{$matches[0].Groups[2].Value}
    if(SamePath $vbs $agent){return 'AGENT_WITH_EXTRA_ARGUMENTS'}
    return 'OTHER_VBS'
  }
  if($v -match '(?i)\.vbs'){return 'AMBIGUOUS_VBS'}
  return 'OTHER_ARGS'
}
function DirClass([string]$value,[string]$bin,[string]$root){
  if([string]::IsNullOrWhiteSpace($value)){return 'EMPTY'}
  if(SamePath $value $bin){return 'INSTALLED_BIN'}
  if(SamePath $value $root){return 'APP_ROOT'}
  return 'OTHER_WORKDIR'
}
function Classify([string]$label,[string]$folder,[string]$name,[string]$w32,[string]$w64,[string]$agent,[string]$bin,[string]$root,[object]$shell){
  if([string]::IsNullOrWhiteSpace($folder)){
    $out.Add($label+'_LINK=FOLDER_UNAVAILABLE')
    return
  }
  $link=Join-Path $folder $name
  if(-not(Test-Path -LiteralPath $link)){$out.Add($label+'_LINK=ABSENT');return}
  if(-not(PlainFile $link)){$out.Add($label+'_LINK=UNSAFE_OR_UNEXPECTED_FILE');return}
  try{
    $sh=$shell.CreateShortcut($link)
    $out.Add($label+'_LINK=PRESENT_PLAIN')
    $out.Add($label+'_TARGET='+ (TargetClass ([string]$sh.TargetPath) $w32 $w64))
    $out.Add($label+'_ARGUMENTS='+ (ArgsClass ([string]$sh.Arguments) $agent))
    $out.Add($label+'_WORKDIR='+ (DirClass ([string]$sh.WorkingDirectory) $bin $root))
  }catch{
    $out.Add($label+'_LINK=UNREADABLE_COM')
  }
}
try{
  if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw 'WINDOWS_REQUIRED'}
  if($PSVersionTable.PSEdition -cne 'Desktop' -or $PSVersionTable.PSVersion.Major -ne 5){throw 'PS51_REQUIRED'}
  if($HostedFixtureRoot.Length -gt 0){
    if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
       $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
       [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){throw 'HOSTED_OVERRIDE_DENIED'}
    $runner=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
    $base=[IO.Path]::GetFullPath($HostedFixtureRoot)
    if(-not $base.StartsWith($runner+'\',[StringComparison]::OrdinalIgnoreCase)){
      throw 'HOSTED_OVERRIDE_OUTSIDE_RUNNER'
    }
    $root=Join-Path $base 'LocalAppData\SpotifyControl'
    $desktop=Join-Path $base 'Desktop'
    $desktopAlternate=$desktop
    $startMenu=Join-Path $base 'StartMenu'
  }else{
    $root=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'SpotifyControl'
    $desktop=[Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory)
    $desktopAlternate=[Environment]::GetFolderPath('Desktop')
    $startMenu=Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
  }
  $out.Add('DESKTOP_FOLDER_RESOLUTION='+$(if(SamePath $desktop $desktopAlternate){'SAME'}else{'DIFFERENT_OR_UNAVAILABLE'}))
  $bin=Join-Path $root 'bin'
  $agent=Join-Path $bin 'spotify-control-agent.vbs'
  $w32=Join-Path $env:WINDIR 'System32\wscript.exe'
  $w64=Join-Path $env:WINDIR 'SysWOW64\wscript.exe'
  $shell=New-Object -ComObject WScript.Shell
  Classify 'DESKTOP' $desktop 'Spotify (Managed).lnk' $w32 $w64 $agent $bin $root $shell
  if(-not(SamePath $desktop $desktopAlternate)){
    Classify 'DESKTOP_ALTERNATE' $desktopAlternate 'Spotify (Managed).lnk' $w32 $w64 $agent $bin $root $shell
  }
  Classify 'STARTMENU' $startMenu 'Spotify (Managed).lnk' $w32 $w64 $agent $bin $root $shell
  $out.Add('RESULT=READONLY_SHORTCUT_CATEGORIES_COMPLETE')
}catch{
  $out.Add('RESULT=HOLD_SHORTCUT_INSPECTION_UNVERIFIED')
}
$out.Add('RAW_PATHS_ARGS_USERNAMES_IDS_AND_ERRORS_EXPORTED=NO')
$out | ForEach-Object{Write-Output $_}
