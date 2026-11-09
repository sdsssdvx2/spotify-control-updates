# R20: identify processes holding SpotifyControl/bin handles. Safe witness only.
# Official signed Microsoft Sysinternals Handle v5.0, checked ZIP and EXE SHA.
# Requires explicit -AcceptMicrosoftHandleEula because -accepteula records an
# HKCU Sysinternals license acceptance. No Spotify/Bootstrap/agent mutations.
[CmdletBinding()]
param(
  [switch]$AcceptMicrosoftHandleEula,
  [string]$HostedFixtureRoot='',
  [string]$HostedExactHandleZipPath=''
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$messages=New-Object 'System.Collections.Generic.List[string]'
$messages.Add('DIAGNOSTIC=SPOTIFY_R20_BIN_HANDLE_WITNESS')
$messages.Add('SPOTIFY_INSTALL_WRITE=NO;BOOTSTRAP_EXEC=NO;UPDATE=NO;ROLLBACK=NO')
$messages.Add('NETWORK=PINNED_MICROSOFT_HANDLE_ZIP_ONLY;TEMP_FILES=CREATED_AND_REMOVED')
$messages.Add('OTHER_PROCESS_KILL=NO;FOREIGN_HANDLE_CLOSE=NO;REGISTRY_EULA_ACCEPTANCE=POSSIBLE')
function HashBytes([byte[]]$data) {
  $sha=[Security.Cryptography.SHA256]::Create()
  try{return [BitConverter]::ToString($sha.ComputeHash($data)).Replace('-','').ToLowerInvariant()}
  finally{$sha.Dispose()}
}
function CategorizeExe([string]$exe) {
  $name=$exe.ToLowerInvariant()
  if($name -in @('powershell.exe','pwsh.exe','powershell_ise.exe')){return 'POWERSHELL'}
  if($name -in @('wscript.exe','cscript.exe')){return 'SCRIPT_HOST'}
  if($name -eq 'explorer.exe'){return 'EXPLORER'}
  if($name -eq 'spotify.exe'){return 'SPOTIFY'}
  if($name -in @('cmd.exe','conhost.exe','windowsterminal.exe')){return 'CONSOLE'}
  if($name -in @('code.exe','notepad.exe','notepad++.exe','sublime_text.exe')){return 'EDITOR'}
  if($name -in @('msmpeng.exe','searchindexer.exe','everything.exe')){return 'INDEXER_OR_SECURITY'}
  if($name -in @('handle64.exe','handle.exe')){return 'INSPECTOR_SELF'}
  return 'OTHER_PROCESS'
}
function PlainDirectory([string]$p) {
  try{
    $f=Get-Item -LiteralPath $p -Force -ErrorAction Stop
    return ($f.PSIsContainer -and
      ($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0)
  }catch{return $false}
}
function PathBelow([string]$p,[string]$base) {
  try{
    $a=[IO.Path]::GetFullPath($p).TrimEnd('\','/')
    $b=[IO.Path]::GetFullPath($base).TrimEnd('\','/')
    return ($a.Equals($b,[StringComparison]::OrdinalIgnoreCase) -or
            $a.StartsWith(($b+'\'),[StringComparison]::OrdinalIgnoreCase))
  }catch{return $false}
}
$phase='INITIAL'
$scratch=$null
try{
  if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){throw 'WINDOWS_REQUIRED'}
  if(-not [Environment]::Is64BitProcess){throw 'X64_POWERSHELL_REQUIRED'}
  if(-not $AcceptMicrosoftHandleEula){throw 'EXPLICIT_MICROSOFT_EULA_ACCEPTANCE_REQUIRED'}
  if($HostedFixtureRoot.Length -gt 0){
    if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
       $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
       [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){throw 'HOSTED_FIXTURE_OVERRIDE_DENIED'}
    $fixture=[IO.Path]::GetFullPath($HostedFixtureRoot)
    $runner=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
    if(-not $fixture.StartsWith(($runner+'\'),[StringComparison]::OrdinalIgnoreCase)){
      throw 'HOSTED_FIXTURE_OUTSIDE_RUNNER'
    }
    $root=Join-Path $fixture 'LocalAppData\SpotifyControl'
  }else{
    $root=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'SpotifyControl'
  }
  $bin=Join-Path $root 'bin'
  if(-not(PlainDirectory $root) -or -not(PlainDirectory $bin)){throw 'ROOT_OR_BIN_UNSAFE'}
  $cwd=[IO.Path]::GetFullPath([Environment]::CurrentDirectory)
  $messages.Add('CALLING_POWERSHELL_CWD_INSIDE_BIN='+$(if(PathBelow $cwd $bin){'YES'}else{'NO'}))
  $messages.Add('CALLING_POWERSHELL_CWD_INSIDE_APP='+$(if(PathBelow $cwd $root){'YES'}else{'NO'}))
  $admin=$false
  try{
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    $principal=New-Object Security.Principal.WindowsPrincipal($identity)
    $admin=$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  }catch{}
  $messages.Add('ELEVATED_TOKEN='+$(if($admin){'YES'}else{'NO'}))
  $transaction=Join-Path $root 'self-update-last-transaction.json'
  $txnOriginal=$null
  if($HostedFixtureRoot.Length -eq 0){
    try{
      $f=Get-Item -LiteralPath $transaction -Force -ErrorAction Stop
      if($f.PSIsContainer -or
         ($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
         $f.Length -gt 1048576 -or $f.Length -lt 2){throw 'JOURNAL_UNSAFE'}
      [byte[]]$txnOriginal=[IO.File]::ReadAllBytes($transaction)
      $txnHash=HashBytes $txnOriginal
      $text=[IO.File]::ReadAllText($transaction,[Text.Encoding]::UTF8)
      $doc=$text|ConvertFrom-Json -ErrorAction Stop
      if([string]$doc.status -cne 'prepared' -or
         [string]$doc.source_commit -cne 'bb6d90146f20b73d36fbf8cb813f1b190f403c48' -or
         [string]$doc.payload_set_sha256 -cne '4be96c5d41c2160ed9ac96001b469998595629232929b82c8b0f34b11fda3b43'){
         throw 'TRANSACTION_NOT_EXACT_OFFICIAL_PREPARED'
      }
      $messages.Add('TRANSACTION=EXACT_STILL_PREPARED')
    }catch{throw 'TRANSACTION_NOT_SAFE_TO_INSPECT'}
  }else{
    $messages.Add('TRANSACTION=HOSTED_SYNTHETIC_ONLY')
  }
  $phase='CREATE_PRIVATE_SCRATCH'
  $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')
  $scratch=Join-Path $temp ('spotify-r20-handle-inspect-'+[guid]::NewGuid().ToString('N'))
  if(Test-Path -LiteralPath $scratch){throw 'SCRATCH_COLLISION'}
  [void][IO.Directory]::CreateDirectory($scratch)
  $zip=Join-Path $scratch 'official-Handle.zip'
  $extract=Join-Path $scratch 'extracted'
  [void][IO.Directory]::CreateDirectory($extract)
  $phase='DOWNLOAD_OFFICIAL_MICROSOFT_HANDLE'
  if($HostedExactHandleZipPath.Length -gt 0){
    if($HostedFixtureRoot.Length -eq 0 -or
       $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
       [IO.Path]::GetFullPath($HostedExactHandleZipPath) -cne
       [IO.Path]::GetFullPath((Join-Path $env:RUNNER_TEMP 'r20-microsoft-Handle.zip'))){
      throw 'HOSTED_ZIP_PATH_NOT_PERMITTED'
    }
    [byte[]]$zipRaw=[IO.File]::ReadAllBytes($HostedExactHandleZipPath)
  }else{
    $wc=New-Object Net.WebClient
    try{[byte[]]$zipRaw=$wc.DownloadData('https://download.sysinternals.com/files/Handle.zip')}
    finally{$wc.Dispose()}
  }
  if($zipRaw.Length -gt 3000000 -or
     (HashBytes $zipRaw) -cne '279aaf8eccb6f79147f4dcc6ba091fb895c4cb8b199a0dd186a4c76bc519d2cd'){
    throw 'OFFICIAL_HANDLE_ZIP_PIN_FAILED'
  }
  [IO.File]::WriteAllBytes($zip,$zipRaw)
  $phase='VERIFY_MICROSOFT_EXE'
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  [IO.Compression.ZipFile]::ExtractToDirectory($zip,$extract)
  $exe=Join-Path $extract 'handle64.exe'
  if(-not(Test-Path -LiteralPath $exe)){throw 'HANDLE64_NOT_PRESENT'}
  if((Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant() -cne
     '24bafcc570cc9bbb6b6e6652a57a519e0464e3996891aaba6f55299cce20b04f'){
     throw 'HANDLE64_EXE_HASH_CHANGED'
  }
  $sig=Get-AuthenticodeSignature -FilePath $exe -ErrorAction Stop
  if([string]$sig.Status -cne 'Valid' -or
     [string]$sig.SignerCertificate.Subject -notmatch 'Microsoft'){
     throw 'MICROSOFT_SIGNATURE_INVALID'
  }
  $messages.Add('OFFICIAL_MICROSOFT_HANDLE=SHA256_AND_AUTHENTICODE_PASS')
  $phase='QUERY_OPEN_BIN_HANDLES'
  $psi=New-Object Diagnostics.ProcessStartInfo
  $psi.FileName=$exe
  $psi.Arguments='-nobanner -accepteula -v "'+$bin+'"'
  $psi.WorkingDirectory=$scratch
  $psi.CreateNoWindow=$true
  $psi.UseShellExecute=$false
  $psi.RedirectStandardOutput=$true
  $psi.RedirectStandardError=$true
  $p=New-Object Diagnostics.Process
  $p.StartInfo=$psi
  try{
    [void]$p.Start()
    $stdout=$p.StandardOutput.ReadToEndAsync()
    $stderr=$p.StandardError.ReadToEndAsync()
    if(-not $p.WaitForExit(30000)){
      try{$p.Kill()}catch{}
      throw 'HANDLE_QUERY_DEADLINE_EXCEEDED'
    }
    $raw=[string]$stdout.Result
    [void]$stderr.Result
    if($raw.Length -gt 4000000){throw 'HANDLE_OUTPUT_OVERSIZED'}
    if($p.ExitCode -ne 0 -and $p.ExitCode -ne 1){throw 'HANDLE_QUERY_NONZERO_OR_PERMISSION'}
    $lines=@($raw -split '\r?\n')
    if($HostedFixtureRoot.Length -gt 0 -and $env:GITHUB_ACTIONS -ceq 'true'){
      $messages.Add('HOSTED_CAPTURE_LINE_COUNT='+[string]$lines.Count)
      $messages.Add('HOSTED_CAPTURE_CMD='+$(if($raw -match '(?i)cmd\.exe,\s*[0-9]+,'){'YES'}else{'NO'}))
      $messages.Add('HOSTED_CAPTURE_BIN='+$(if($raw.Contains($bin)){'YES'}else{'NO'}))
      $messages.Add('HOSTED_CAPTURE_ESCAPE_PATH='+$(if($raw.Contains('SpotifyControl')){'YES'}else{'NO'}))
    }
    $categories=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $owners=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $exactOwners=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $literal=[regex]::Escape($bin)
    foreach($line in $lines){
      if($line.Length -gt 8192){continue}
      if($line -cnotmatch '^\s*(?<exe>[A-Za-z0-9_.-]+\.exe)\s*,\s*(?<pid>[0-9]{1,10})\s*,'){continue}
      if($line -notmatch ('(?i)'+$literal+'(?:\\|,|$)')){continue}
      $exeName=[string]$Matches['exe']
      # Previous -match populated $Matches with the pathname regexp;
      # reparse process identity explicitly before reporting any label.
      $match=[regex]::Match($line,'^\s*(?<exe>[A-Za-z0-9_.-]+\.exe)\s*,\s*(?<pid>[0-9]{1,10})\s*,')
      if(-not $match.Success){continue}
      $pidText=$match.Groups['pid'].Value
      $cat=CategorizeExe $match.Groups['exe'].Value
      [void]$categories.Add($cat)
      [void]$owners.Add($pidText)
      if($line -match ('(?i)'+$literal+'(?:\s*(?:,|$))')){
        [void]$exactOwners.Add($pidText)
      }
    }
    [string[]]$found=@($categories | ForEach-Object {[string]$_})
    [Array]::Sort([string[]]$found,[StringComparer]::Ordinal)
    $messages.Add('BIN_HANDLE_OWNER_PROCESS_COUNT='+[string]$owners.Count)
    $messages.Add('BIN_DIRECTORY_EXACT_HANDLE_OWNER_COUNT='+[string]$exactOwners.Count)
    $messages.Add('BIN_HANDLE_OWNER_CATEGORIES='+$(if($found.Count){$found -join ','}else{'NONE_OBSERVED'}))
    $messages.Add('HANDLE_INVENTORY_SCOPE='+$(if($admin){'ELEVATED_PROCESS_VIEW'}else{'STANDARD_USER_LIMITED_VIEW'}))
  }finally{
    $p.Dispose()
  }
  if($null -ne $txnOriginal){
    if((HashBytes ([IO.File]::ReadAllBytes($transaction))) -cne $txnHash){
      $messages.Add('TRANSACTION_STABLE_DURING_AUDIT=NO_OR_UNVERIFIED')
      throw 'TRANSACTION_CHANGED_DURING_DIAGNOSIS'
    }
    $messages.Add('TRANSACTION_STABLE_DURING_AUDIT=YES')
  }
  $messages.Add('RESULT=READONLY_BIN_HANDLE_INVENTORY_COMPLETE')
 }catch{
  # Only exact script-authored categorical errors, never OS exception text.
  $kind=[string]$_.Exception.Message
  $allowed=@(
    'WINDOWS_REQUIRED','X64_POWERSHELL_REQUIRED',
    'EXPLICIT_MICROSOFT_EULA_ACCEPTANCE_REQUIRED',
    'HOSTED_FIXTURE_OVERRIDE_DENIED','HOSTED_FIXTURE_OUTSIDE_RUNNER',
    'ROOT_OR_BIN_UNSAFE','TRANSACTION_NOT_SAFE_TO_INSPECT',
    'SCRATCH_COLLISION','HOSTED_ZIP_PATH_NOT_PERMITTED',
    'OFFICIAL_HANDLE_ZIP_PIN_FAILED','HANDLE64_NOT_PRESENT',
    'HANDLE64_EXE_HASH_CHANGED','MICROSOFT_SIGNATURE_INVALID',
    'HANDLE_QUERY_DEADLINE_EXCEEDED','HANDLE_OUTPUT_OVERSIZED',
    'HANDLE_QUERY_NONZERO_OR_PERMISSION',
    'TRANSACTION_CHANGED_DURING_DIAGNOSIS'
  )
  if($kind -cnotin $allowed){$kind='UNVERIFIED_EXTERNAL_OR_WINDOWS_EXCEPTION'}
  $messages.Add('FAILED_PHASE='+$phase)
  $messages.Add('HOLD_REASON='+$kind)
  if($env:GITHUB_ACTIONS -ceq 'true'){
    $messages.Add('HOSTED_EXCEPTION_TYPE='+$_.Exception.GetType().Name)
    $messages.Add('HOSTED_FAILED_LINE='+[string]$_.InvocationInfo.ScriptLineNumber)
    $messages.Add('HOSTED_EXCEPTION_HRESULT='+[string]$_.Exception.HResult)
  }
  $messages.Add('RESULT=HOLD_DIAGNOSTIC_INCOMPLETE')
}finally{
  if($null -ne $scratch -and (Test-Path -LiteralPath $scratch)){
    try{[IO.Directory]::Delete($scratch,$true);$messages.Add('TEMP_CLEANUP=REMOVED')}
    catch{$messages.Add('TEMP_CLEANUP=UNVERIFIED')}
  }
}
$messages.Add('RAW_PATHS_PIDS_USERS_HANDLES_AND_ERRORS_EXPORTED=NO')
if($HostedFixtureRoot.Length -eq 0){
  try{Set-Clipboard -Value ($messages -join [Environment]::NewLine) -ErrorAction Stop}catch{}
}
$messages | ForEach-Object {Write-Output $_}
