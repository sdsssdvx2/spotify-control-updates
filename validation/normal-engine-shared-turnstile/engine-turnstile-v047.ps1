# Shared legacy/new engine coordination primitive for the actual generated
# Addon Manager. Same persistent zero-byte lock across Update-AutoApps,
# Commit-LastTransaction and Rollback-LastTransaction. Future new executor
# MUST take this exact lock before enrollment or any source/XPUI mutation.
#
# FileShare.None holds an OS handle until Dispose/process exit. The 0-byte
# lock file is never deleted, migrated, replaced, or treated as a journal.
# Alone it cannot stop older unpatched processes or hostile same-user code.
function Enter-CustomAppEngineTurnstileV047 {
 param([string]$HostedCiRoot=$null)
 if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){
    throw 'V047_ENGINE_TURNSTILE_WINDOWS_ONLY'
 }
 $fixture=-not[string]::IsNullOrWhiteSpace($HostedCiRoot)
 if($fixture){
    if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
       $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
       [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
       throw 'V047_ENGINE_FIXTURE_OVERRIDE_NOT_HOSTED'
    }
    $runner=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
    $local=[IO.Path]::GetFullPath($HostedCiRoot).TrimEnd('\','/')
    if(-not$local.StartsWith(($runner+'\'),[StringComparison]::OrdinalIgnoreCase)){
       throw 'V047_ENGINE_FIXTURE_PATH_NOT_IN_RUNNER'
    }
 }else{
    $local=[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
 }
 if([string]::IsNullOrWhiteSpace($local) -or
    -not[IO.Path]::IsPathRooted($local) -or
    $local.StartsWith('\\',[StringComparison]::Ordinal)){
    throw 'V047_ENGINE_LOCAL_ROOT_INVALID'
 }
 $local=[IO.Path]::GetFullPath($local).TrimEnd('\','/')
 $legacy=Join-Path $local 'SpotifyControl'
 if(-not[IO.Directory]::Exists($local) -or
    -not[IO.Directory]::Exists($legacy)){
    throw 'V047_ENGINE_LEGACY_ROOT_NOT_FOUND'
 }
 foreach($d in @($local,$legacy)){
    $info=Get-Item -LiteralPath $d -Force -ErrorAction Stop
    if(($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
       throw 'V047_ENGINE_LOCK_PARENT_REPARSE'
    }
 }
 $name='.engine-cutover-turnstile.lock'
 $file=Join-Path $legacy $name
 $matches=@(Get-ChildItem -LiteralPath $legacy -Force -ErrorAction Stop |
    Where-Object{$_.Name.Equals($name,[StringComparison]::OrdinalIgnoreCase)})
 if($matches.Count -gt 1){
    throw 'V047_ENGINE_LOCK_FILE_NAME_COLLISION'
 }
 if($matches.Count -eq 1){
    $entry=$matches[0]
    if(($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
       $entry.PSIsContainer -or [int64]$entry.Length -ne 0){
       throw 'V047_ENGINE_LOCK_FILE_REPARSE_OR_INVALID'
    }
 }
 $handle=$null
 try{
    $handle=[IO.File]::Open($file,[IO.FileMode]::OpenOrCreate,
       [IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    if([int64]$handle.Length -ne 0){
       throw 'V047_ENGINE_LOCK_NOT_EMPTY'
    }
    # Detect a reparse-point swap at open time; never follow an unknown
    # user file for any write. Only the 0-byte cooperative lock is created.
    $item=Get-Item -LiteralPath $file -Force -ErrorAction Stop
    if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
       $item.PSIsContainer){
       throw 'V047_ENGINE_LOCK_CHANGED_DURING_OPEN'
    }
    return $handle
 }catch [IO.IOException]{
    if($null-ne$handle){$handle.Dispose()}
    throw 'V047_ENGINE_TURNSTILE_BUSY_OR_IO_UNSAFE'
 }catch{
    if($null-ne$handle){$handle.Dispose()}
    throw
 }
}
