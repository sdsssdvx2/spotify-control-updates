# V060 development HOLD. Reentrant layer over existing verified V047
# FileShare.None OS handle, to allow Update-AutoApps -> Rollback-LastTransaction
# within the SAME PowerShell thread/runspace without reopening the lock file.
# Different process, thread, or runspace must NEVER bypass the file lease.
# Caller must dot-source engine-turnstile-v047.ps1 before this module.
# No real-user caller is enrolled by this module.
Set-StrictMode -Version 2.0
if(-not(Get-Variable -Scope Script -Name V060AddonLeaseState -ErrorAction SilentlyContinue)){
 $script:V060AddonLeaseState=$null
}
function Enter-CustomAppReentrantTurnstileV060 {
 param([string]$HostedCiRoot=$null)
 if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){
   throw 'V060_REENTRANT_WINDOWS_ONLY'
 }
 $run=[Management.Automation.Runspaces.Runspace]::DefaultRunspace
 if($null-eq$run){throw 'V060_NO_ACTIVE_POWERSHELL_RUNSPACE'}
 $runId=[string]$run.InstanceId
 $thread=[Threading.Thread]::CurrentThread.ManagedThreadId
 $fixture=if([string]::IsNullOrWhiteSpace($HostedCiRoot)){''}
   else{[IO.Path]::GetFullPath($HostedCiRoot).TrimEnd('\','/')}
 $current=$script:V060AddonLeaseState
 if($null-ne$current){
   if([string]$current.runspace_id -cne $runId -or
      [int]$current.thread_id -ne $thread -or
      [string]$current.fixture_root -cne $fixture){
     throw 'V060_REENTRANT_CROSS_OWNER_OR_CROSS_ROOT_DENIED'
   }
   if($current.tokens.Count -ge 32){throw 'V060_REENTRANT_MAX_DEPTH'}
 }else{
   $handle=Enter-CustomAppEngineTurnstileV047 -HostedCiRoot $HostedCiRoot
   if($null-eq$handle -or $handle -isnot [IO.FileStream]){
     throw 'V060_REENTRANT_V047_BASE_HANDLE_UNVERIFIED'
   }
   $current=[pscustomobject]@{
      runspace_id=$runId;thread_id=$thread;fixture_root=$fixture
      generation=[guid]::NewGuid().ToString('N')
      handle=$handle
      tokens=(New-Object 'System.Collections.Generic.List[object]')
   }
   $script:V060AddonLeaseState=$current
 }
 try{
    $token=[pscustomobject]@{
      generation=[string]$current.generation
      token_id=[guid]::NewGuid().ToString('N')
      runspace_id=$runId;thread_id=$thread
      fixture_root=$fixture
    }
    $current.tokens.Add($token)
    return $token
 }catch{
    if($current.tokens.Count -eq 0){
       try{$current.handle.Dispose()}finally{$script:V060AddonLeaseState=$null}
    }
    throw
 }
}
function Exit-CustomAppReentrantTurnstileV060 {
 param([Parameter(Mandatory=$true)]$Token)
 $current=$script:V060AddonLeaseState
 $run=[Management.Automation.Runspaces.Runspace]::DefaultRunspace
 if($null-eq$current -or $null-eq$run -or
    $current.tokens.Count -lt 1 -or
    [string]$current.runspace_id -cne [string]$run.InstanceId -or
    [int]$current.thread_id -ne [Threading.Thread]::CurrentThread.ManagedThreadId){
   throw 'V060_REENTRANT_RELEASE_WITHOUT_OWNER'
 }
 $last=$current.tokens[$current.tokens.Count-1]
 if(-not[object]::ReferenceEquals($last,$Token) -or
    [string]$Token.generation -cne [string]$current.generation -or
    [string]$Token.token_id -cne [string]$last.token_id){
   throw 'V060_REENTRANT_RELEASE_TOKEN_NOT_LIFO'
 }
 $current.tokens.RemoveAt($current.tokens.Count-1)
 if($current.tokens.Count -eq 0){
    try{
       $current.handle.Dispose()
    }finally{
       $script:V060AddonLeaseState=$null
    }
 }
}
function Assert-CustomAppReentrantLeaseInvariantV060 {
 # Read-only internal health assertion used by hosted acceptance only.
 $current=$script:V060AddonLeaseState
 if($null-eq$current){
   return [pscustomobject]@{active=$false;depth=0;production_mutation_authorized=$false}
 }
 if($null-eq$current.handle -or $current.handle.SafeFileHandle.IsClosed -or
    $current.tokens.Count -lt 1 -or $current.tokens.Count -gt 32){
   throw 'V060_REENTRANT_OWNER_STATE_INVALID'
 }
 return [pscustomobject]@{
    active=$true;depth=[int]$current.tokens.Count
    production_mutation_authorized=$false
 }
}
