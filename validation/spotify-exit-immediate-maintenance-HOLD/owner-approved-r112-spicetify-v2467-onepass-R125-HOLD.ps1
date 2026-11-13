# Spotify Control R125: one approved owner acceptance. No install, no public publication.
# Expected user PC: official main v0.6.30, official Spicetify 2.46.4,
# signed Spotify 1.3.6.1921, existing authenticated Spicetify backup.
[CmdletBinding()]
param(
  [ValidateSet('BuildOnly','Once')][string]$Mode='BuildOnly',
  [string]$SourcePath='',
  [string]$ApprovalPhrase=''
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$OriginalSHA='b2b2fbf1afb60b58d501312160f7e2437c2452e90cb61ca8c2be0d877f92232d'
$CandidateSHA='beb850064670c078a679585ace25f8071daa88c0b264185c03ef3364329b431b'
$AgentSHA='e56609ed8927512595f55c01ea50dbb9c8c59e4a2c86dcb3d16195a565c604d5'
$AddonSHA='5ab556c1d90b9f8e6d5784e238ffd1798c5363a0f7cd7b8313d1f106b5b6a285'
$BootSHA='d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6'
$OldCliSHA='3563f26acd7527adc97e6c19272fa1b48ce976a913625d9804ac57d3c54fb4db'
$OfficialZipSHA='c5a723d31eae529ba13f6922a7a027124238c7f3da7edd182a73eab03c447e9e'
$Phase='START'
# Script-scope variables are read by helpers/finally. Define them in
# that SAME scope even when this file is invoked via ScriptBlock.Create().
# The previous unscoped declarations left $script:SourceSwapped undefined
# under StrictMode and suppressed the original HOLD receipt.
$script:StageRoot=$null
$script:OriginalMain=$null
$script:PatchedMain=$null
$script:AgentStarted=$false
$script:Succeeded=$false
$script:SourceSwapped=$false
$script:ExpectedNewExe=$null
$Report=[System.Collections.Generic.List[string]]::new()
function Emit([string]$k,[string]$v){[void]$Report.Add($k+'='+$v)}
function Fail([string]$reason){throw [InvalidOperationException]::new($reason)}
function HashBytes([byte[]]$data){
  $alg=[Security.Cryptography.SHA256]::Create()
  try {return ([BitConverter]::ToString($alg.ComputeHash($data))).Replace('-','').ToLowerInvariant()}
  finally {$alg.Dispose()}
}
function HashFile([string]$p){return (Get-FileHash -LiteralPath $p -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()}
function Regular([string]$p,[long]$max){
  try {
    $f=Get-Item -LiteralPath $p -Force -ErrorAction Stop
    return (-not $f.PSIsContainer -and
      ($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -and
      [long]$f.Length -gt 0 -and [long]$f.Length -le $max)
  }catch{return $false}
}
function UniqueReplace([string]$s,[string]$old,[string]$new,[string]$reason){
  $i=$s.IndexOf($old,[StringComparison]::Ordinal)
  if($i -lt 0 -or $s.IndexOf($old,$i+$old.Length,[StringComparison]::Ordinal) -ge 0){
    Fail ('R125_PINNED_PATCH_ANCHOR_DRIFT_'+$reason)
  }
  return $s.Substring(0,$i)+$new+$s.Substring($i+$old.Length)
}
function FunctionSlice([string]$s,[string]$name){
  $mark=([string][char]10)+'function '+$name+' {'
  $i=$s.IndexOf($mark,[StringComparison]::Ordinal)
  if($i -lt 0 -or $s.IndexOf($mark,$i+$mark.Length,[StringComparison]::Ordinal) -ge 0){
    Fail ('R125_PINNED_FUNCTION_DRIFT_'+$name)
  }
  $start=$i+1
  $next=$s.IndexOf(([string][char]10)+'function ',$start+$mark.Length,[StringComparison]::Ordinal)
  if($next -lt 0){$next=$s.Length}
  return [pscustomobject]@{Start=$start;Length=$next-$start;Text=$s.Substring($start,$next-$start)}
}
function PatchExactR112([byte[]]$raw){
  if((HashBytes $raw) -cne $OriginalSHA){Fail 'R125_ORIGINAL_MAIN_SHA_MISMATCH'}
  $bom=($raw.Length -gt 3 -and $raw[0] -eq 239 -and $raw[1] -eq 187 -and $raw[2] -eq 191)
  $offset=if($bom){3}else{0}
  $enc=[Text.UTF8Encoding]::new($false,$true)
  $text=$enc.GetString($raw,$offset,$raw.Length-$offset)
  $crlf=([string][char]13)+([string][char]10)
  $lf=[string][char]10
  $newline=if($text.Contains($crlf)){$crlf}else{$lf}
  $s=$text.Replace($crlf,$lf)
  $self=FunctionSlice $s 'Get-SelfUpdateCheckResult'
  $selfText=$self.Text
  $old='    if ($r.ExitCode -ne 0 -or $null -eq $r.Report -or -not [bool]$r.Report.success) {'
  $new=@'
    # The official v1.0.6 bootstrap authenticated the stable manifest and
    # then refused a forward-only plan because a private, exact version is
    # already ahead of published stable. This is NOT a failed Spicetify check.
    # Never treat an arbitrary bootstrap/network/integrity error as benign.
    $privateAhead=$false
    if ($r.ExitCode -eq 1 -and $null -ne $r.Report -and
        $r.Report.success -eq $false -and
        [string]$r.Report.action -ceq "Check" -and
        [string]$r.Report.bootstrap_version -ceq "1.0.6" -and
        [string]$r.Report.installed_version -ceq "0.6.30" -and
        [string]$ScriptVersion -ceq "0.6.30" -and
        [string]$r.Report.manifest_url -ceq
          "https://raw.githubusercontent.com/sdsssdvx2/spotify-control-updates/main/manifest.json" -and
        [string]$r.Report.error -ceq
          "Automatic Spotify Control downgrade refused: installed=0.6.30 latest=0.6.28" -and
        [string]$r.Report.transaction_status -cin @("","committed")) {
        try {
            $boot=(Get-Item -LiteralPath $SelfUpdater -Force -ErrorAction Stop)
            if (-not $boot.PSIsContainer -and
                ($boot.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0 -and
                [long]$boot.Length -eq 42963 -and
                (Get-FileHash -LiteralPath $SelfUpdater -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant() -ceq
                "d9b28007eb95874f02c48ed50d8ada71134e15e6492fef0e2d45dd2522053fe6") {
                $privateAhead=$true
            }
        } catch { $privateAhead=$false }
    }
    if ($privateAhead) {
        return [pscustomobject]@{
            Verified=$false;TrustedStableBehindPrivate=$true;
            UpdateAvailable=$false;InstalledVersion=$ScriptVersion;
            LatestVersion="0.6.28";BootstrapVersion="1.0.6";
            SourceCommit=$null;PayloadSetSha256=$null;
            TransactionId=[string]$r.Report.transaction_id;
            TransactionStatus=[string]$r.Report.transaction_status;
            Error="trusted-private-version-ahead-of-public-stable-self-update-disabled"
        }
    }
    if ($r.ExitCode -ne 0 -or $null -eq $r.Report -or -not [bool]$r.Report.success) {
'@
  $new=$new.Replace($crlf,$lf)
  $selfText=UniqueReplace $selfText $old $new 'SELFUPDATE_AHEAD_GUARD'
  $selfText=UniqueReplace $selfText 'Verified=$false; UpdateAvailable=$false; InstalledVersion=$ScriptVersion;' 'Verified=$false; TrustedStableBehindPrivate=$false; UpdateAvailable=$false; InstalledVersion=$ScriptVersion;' 'SELFUPDATE_ERROR_FALSE'
  $selfText=UniqueReplace $selfText ('        Verified=$true'+$lf) ('        Verified=$true'+$lf+'        TrustedStableBehindPrivate=$false'+$lf) 'SELFUPDATE_SUCCESS_FALSE'
  $s=$s.Substring(0,$self.Start)+$selfText+$s.Substring($self.Start+$self.Length)
  $check=FunctionSlice $s 'Invoke-MaintenanceCheckPhase'
  $checkText=$check.Text
  $oldCheck='        if (-not $selfUpdate.Verified) { $errors.Add("Spotify Control self-update discovery: $($selfUpdate.Error)") }'
  $newCheck=@'
        if (-not $selfUpdate.Verified) {
            if ($selfUpdate.TrustedStableBehindPrivate -eq $true) {
                # No self-update is permitted. Independent Spicetify/addon
                # checks still have to pass their existing fail-closed guards.
                $warnings.Add("Pinned private v0.6.30 is newer than authenticated public stable v0.6.28; self-update disabled.")
            } else {
                $errors.Add("Spotify Control self-update discovery: $($selfUpdate.Error)")
            }
        }
'@
  $newCheck=$newCheck.Replace($crlf,$lf)
  $checkText=UniqueReplace $checkText $oldCheck $newCheck 'INDEPENDENT_DISCOVERY_AHEAD'
  $oldCache='            Verified=(-not [string]::IsNullOrWhiteSpace([string]$State.self_update_latest_version))'
  $checkText=UniqueReplace $checkText $oldCache ($oldCache+$lf+'            TrustedStableBehindPrivate=$false') 'CACHE_NOT_AHEAD'
  $s=$s.Substring(0,$check.Start)+$checkText+$s.Substring($check.Start+$check.Length)
  $encoded=$enc.GetBytes($s.Replace($lf,$newline))
  if($bom){
    $bytes=New-Object byte[] ($encoded.Length+3)
    [Array]::Copy(([byte[]]@(239,187,191)),$bytes,3)
    [Array]::Copy($encoded,0,$bytes,3,$encoded.Length)
  }else{$bytes=$encoded}
  $actualCandidateSHA=HashBytes $bytes
  if($actualCandidateSHA -cne $CandidateSHA){
    Emit 'R125_BUILD_CANDIDATE_SHA256' $actualCandidateSHA
    Emit 'R125_BUILD_CANDIDATE_BYTES' ([string]$bytes.Length)
    Fail 'R125_R112_TARGET_SHA_MISMATCH'
  }
  return ,$bytes
}
function Acquire([string]$purpose,[string]$sid){
  $m=[Threading.Mutex]::new($false,('Local\SpotifyControl-'+$purpose+'-'+$sid))
  try {
    if(-not $m.WaitOne(0)){Fail ('R125_'+$purpose.ToUpperInvariant()+'_BUSY')}
    return $m
  }catch{$m.Dispose();throw}
}
function Release($m){
  if($null -ne $m){try{$m.ReleaseMutex()}finally{$m.Dispose()}}
}
function ReplaceMain([string]$expected,[byte[]]$contents,[string]$backupName){
  $m1=$null;$m2=$null
  try{
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $m1=Acquire 'Maintenance' $sid
    $m2=Acquire 'AgentTick' $sid
    if(-not (Regular $script:OriginalMain 500000) -or
       (HashFile $script:OriginalMain) -cne $expected){
      Fail 'R125_MAIN_CHANGED_DURING_TRANSACTION'
    }
    if(@(Get-Process -Name Spotify -ErrorAction SilentlyContinue).Count -ne 0){
      Fail 'R125_SPOTIFY_STARTED_DURING_TRANSACTION'
    }
    $targetDir=Split-Path -Path $script:OriginalMain -Parent
    $temp=Join-Path $targetDir ('r125-'+[guid]::NewGuid().ToString('N')+'.new')
    if(Test-Path -LiteralPath $temp){Fail 'R125_STAGE_COLLISION'}
    [IO.File]::WriteAllBytes($temp,$contents)
    if((HashFile $temp) -cne (HashBytes $contents)){Fail 'R125_STAGE_READBACK_BAD'}
    $backup=Join-Path $script:StageRoot $backupName
    if(Test-Path $backup){Fail 'R125_BACKUP_COLLISION'}
    [IO.File]::Replace($temp,$script:OriginalMain,$backup,$false)
    $script:SourceSwapped=$true
    if((HashFile $script:OriginalMain) -cne (HashBytes $contents) -or
       (HashFile $backup) -cne $expected){
      Fail 'R125_ATOMIC_PUBLICATION_NOT_VERIFIED'
    }
  }finally{Release $m2;Release $m1}
}
# A resident agent is not a static state machine. Since the previous read-only
# probe it may have completed a normal tick and changed its last decision,
# pending work, or cached discovery health. None is an authorization grant.
# The actual agent MUST rerun fresh discovery and verify its own state under
# the existing cross-process mutex before any mutation.
function MainIdentityClass([string]$sha) {
  if($sha -ceq $OriginalSHA){return 'ORIGINAL_V0630'}
  if($sha -ceq $CandidateSHA){return 'R112_ALREADY_INSTALLED'}
  return 'OTHER_OR_UNTRUSTED'
}
function StateClass($state) {
  if($null -eq $state){return 'STATE_MISSING'}
  $arm=$state.PSObject.Properties['agent_mutation_enabled']
  if($null -eq $arm -or $arm.Value -isnot [bool]){return 'MUTATION_APPROVAL_UNVERIFIED'}
  if($arm.Value -ne $true){return 'MUTATION_DISARMED'}
  $a=$state.PSObject.Properties['pending_addon_auto_ambiguous']
  if($null -eq $a){return 'AUTO_AMBIGUITY_UNVERIFIED'}
  $number=0
  if(-not [int]::TryParse([string]$a.Value,[ref]$number) -or
     $number -lt 0){return 'AUTO_AMBIGUITY_UNVERIFIED'}
  if($number -gt 0){return 'AUTO_AMBIGUITY_PRESENT'}
  return 'ARMED_FRESH_DISCOVERY_REQUIRED'
}
function StateFlag($state,[string]$name){
  if($null -eq $state){return 'UNKNOWN'}
  $p=$state.PSObject.Properties[$name]
  if($null -eq $p -or $p.Value -isnot [bool]){return 'UNKNOWN'}
  if($p.Value){return 'TRUE'}
  return 'FALSE'
}
function StateDecisionClass($state){
  if($null -eq $state){return 'UNKNOWN'}
  $p=$state.PSObject.Properties['last_agent_decision']
  if($null -eq $p){return 'UNKNOWN'}
  $v=[string]$p.Value
  if($v -cin @('closed-check-not-due','closed-idle-or-not-due',
      'maintenance-phase-entered','maintenance-deferred-or-lease-busy',
      'pending-observed-mutation-disarmed','mutation-blocked-unhealthy-or-auto-ambiguous',
      'check-only-closed-no-pending','check-only-running','observe-only-closed',
      'running-idle-or-not-due')){return $v}
  return 'OTHER_OR_ABSENT'
}
function StopRunningCondition{
  if(@(Get-Process -Name Spotify -ErrorAction SilentlyContinue).Count -ne 0){Fail 'R125_SPOTIFY_RUNNING'}
}
function R125Field($obj,[string]$name){
  if($null -eq $obj){return $null}
  $p=$obj.PSObject.Properties[$name]
  if($null -eq $p){return $null}
  return $p.Value
}
function Test-R125CommittedUpgrade($txn,$state,[string]$priorId,
    [DateTimeOffset]$attemptUtc,[string]$expectedExe,[string]$installedExe,
    [string]$mainSha){
  # This is a read-only verdict over the product's own schema-3 journal.
  # Neither agent admission nor a stale "committed" field proves success.
  $code='UNVERIFIED_LEDGER'
  if($null -eq $txn -or $null -eq $state){return $code}
  if([string](R125Field $txn 'status') -cne 'committed'){return 'NO_COMMITTED_TXN'}
  $id=[string](R125Field $txn 'id')
  if([string]::IsNullOrWhiteSpace($id) -or $id -ceq $priorId){
    return 'NO_NEW_TRANSACTION_ID'
  }
  if([string](R125Field $txn 'schema') -cne '3' -or
     (R125Field $txn 'root_transaction') -cne $true){
    return 'NOT_ROOT_TRANSACTION'
  }
  if([string](R125Field $txn 'before_version') -cne '2.46.4' -or
     [string](R125Field $txn 'after_version') -cne '2.46.7' -or
     [string](R125Field $txn 'release_tag') -cne 'v2.46.7'){
    return 'NOT_PINNED_VERSION_TRANSITION'
  }
  if([string](R125Field $txn 'before_sha256') -cne $OldCliSHA -or
     [string](R125Field $txn 'after_sha256') -cne $expectedExe -or
     $installedExe -cne $expectedExe -or $mainSha -cne $CandidateSHA){
    return 'EXACT_BINARY_OR_MAIN_MISMATCH'
  }
  $pin='sha256:'+$OfficialZipSHA
  if([string](R125Field $txn 'asset_digest') -cne $pin){
    return 'RELEASE_ASSET_DIGEST_UNPROVEN'
  }
  foreach($flag in @('apply_attempted','apply_succeeded',
      'post_apply_guard_succeeded','extras_preserved')){
    if((R125Field $txn $flag) -cne $true){
      return 'APPLY_GUARD_OR_EXTRAS_UNPROVEN'
    }
  }
  $extraBefore=[string](R125Field $txn 'extras_before_tree_sha256')
  $extraAfter=[string](R125Field $txn 'extras_after_tree_sha256')
  if($extraBefore -cnotmatch '^[a-f0-9]{64}$' -or
     $extraBefore -cne $extraAfter){
    return 'USER_EXTRAS_PRESERVATION_UNPROVEN'
  }
  $when=[DateTimeOffset]::MinValue
  if(-not [DateTimeOffset]::TryParse([string](R125Field $txn 'committed_at'),[ref]$when) -or
     $when -lt $attemptUtc){
    return 'COMMIT_NOT_NEWER_THAN_ATTEMPT'
  }
  if([string](R125Field $state 'spicetify_last_transaction_id') -cne $id -or
     [string](R125Field $state 'spicetify_last_transaction_status') -cne 'committed' -or
     [string](R125Field $state 'spicetify_installed_version') -cne '2.46.7' -or
     (R125Field $state 'pending_spicetify_upgrade') -cne $false){
    return 'STATE_AND_LEDGER_NOT_CORRELATED'
  }
  return 'FRESH_COMMITTED_ROOT_APPLY_AND_EXTRAS_VERIFIED'
}
function AuthOfficialRelease([string]$scratch){
  $asset=Join-Path $scratch 'official-spicetify-2467-PINNED.zip'
  if(Test-Path $asset){Fail 'R125_OFFICIAL_ASSET_COLLISION'}
  $url='https://github.com/spicetify/cli/releases/download/v2.46.7/spicetify-2.46.7-windows-x64.zip'
  $previous=[Net.ServicePointManager]::SecurityProtocol
  try{
    [Net.ServicePointManager]::SecurityProtocol=([Net.SecurityProtocolType]::Tls12)
    Invoke-WebRequest -Uri $url -UseBasicParsing -OutFile $asset -TimeoutSec 120 -ErrorAction Stop | Out-Null
  }finally{[Net.ServicePointManager]::SecurityProtocol=$previous}
  if(-not(Regular $asset 12000000) -or (HashFile $asset) -cne $OfficialZipSHA){
    Fail 'R125_OFFICIAL_RELEASE_ASSET_NOT_PINNED'
  }
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive=[IO.Compression.ZipFile]::OpenRead($asset)
  try {
    $exe=@($archive.Entries | Where-Object{$_.Name -ceq 'spicetify.exe'})
    if($exe.Count -ne 1){Fail 'R125_OFFICIAL_CLI_ARCHIVE_EXE_UNIQUE_REQUIRED'}
    $stream=$exe[0].Open()
    $sha=[Security.Cryptography.SHA256]::Create()
    try {
      $digest=([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant()
    }finally{$stream.Dispose();$sha.Dispose()}
  }finally{$archive.Dispose()}
  return $digest
}
Emit 'DIAGNOSTIC' 'SPOTIFY_R125_OWNER_R112_2467_ONE_SHOT'
Emit 'NETWORK' $(if($Mode -ceq 'BuildOnly'){'NO'}else{'OFFICIAL_SPICETIFY_ASSET_AND_EXISTING_PRODUCT_ONLY'})
Emit 'AUTO_RETRY' 'NO'
Emit 'PUBLIC_MAIN_WRITE' 'NO'
Emit 'PROCESS_KILL' 'NO_UNCERTAIN_TRANSACTION_KILL'
Emit 'SPOTIFY_INSTALL' 'NO'
Emit 'CONFIG_OR_TASK_DIRECT_WRITE' 'NO'
try {
  if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
     $PSVersionTable.PSEdition -cne 'Desktop' -or
     $PSVersionTable.PSVersion.Major -ne 5 -or -not [Environment]::Is64BitProcess){
    Fail 'R125_WINDOWS_POWERSHELL_51_X64_REQUIRED'
  }
  if($Mode -ceq 'BuildOnly'){
    if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
       $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
       [string]::IsNullOrWhiteSpace($SourcePath)){
      Fail 'R125_BUILDONLY_REQUIRES_PINNED_HOSTED_FIXTURE'
    }
    if(-not(Regular $SourcePath 500000)){Fail 'R125_FIXTURE_ABSENT'}
    $Phase='BUILD_PATCH'
    $candidate=PatchExactR112 ([IO.File]::ReadAllBytes($SourcePath))
    Emit 'R125_TWO_FUNCTION_PATCH' 'EXACT_SHA_PASS'
    Emit 'R125_SOURCE_WRITES' 'ZERO'
    Emit 'RESULT' 'BUILDONLY_PASS_NO_MUTATION'
  }else{
    if($ApprovalPhrase -cne 'APPROVE_R125_ONCE_SPOTIFY_CONTROL_AND_SPICETIFY'){
      Fail 'R125_EXPLICIT_APPROVAL_REQUIRED'
    }
    $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
    if(([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole(
      [Security.Principal.WindowsBuiltInRole]::Administrator)){
      Fail 'R125_STANDARD_OWNER_REQUIRED'
    }
    $root=Join-Path $env:LOCALAPPDATA 'SpotifyControl'
    $bin=Join-Path $root 'bin'
    $script:OriginalMain=Join-Path $bin 'spotify-control.ps1'
    $agent=Join-Path $bin 'spotify-control-agent.vbs'
    $addon=Join-Path $bin 'addon-manager.ps1'
    $boot=Join-Path $root 'bootstrap\spotify-control-self-updater.ps1'
    $cli=Join-Path $env:LOCALAPPDATA 'spicetify\spicetify.exe'
    $vendor=Join-Path $env:APPDATA 'Spotify\Spotify.exe'
    $cfg=Join-Path $env:APPDATA 'spicetify\config-xpui.ini'
    $spiceBackup=Join-Path $env:APPDATA 'spicetify\Backup'
    $statePath=Join-Path $root 'state.json'
    $txnPath=Join-Path $root 'spicetify-last-transaction.json'
    $Phase='READONLY_PREFLIGHT'
    StopRunningCondition
    # The owner may already have the exact, previously verified R112 bytes
    # installed. A repeated source swap is unnecessary and could overwrite
    # a legitimate current main during an otherwise read-only preflight.
    # Only the TWO pinned identities below are accepted; no unknown variant.
    if(-not(Regular $script:OriginalMain 500000)){
      Fail 'R125_MAIN_NOT_REGULAR_OR_MISSING'
    }
    $mainPreflightSHA=HashFile $script:OriginalMain
    $mainMode=MainIdentityClass $mainPreflightSHA
    Emit 'R125_MAIN_PREEXISTING_CLASS' $mainMode
    if($mainMode -ceq 'OTHER_OR_UNTRUSTED'){
      Fail 'R125_MAIN_UNRECOGNIZED_NO_OVERWRITE'
    }
    foreach($x in @(
      @('AGENT',$agent,200000,$AgentSHA),
      @('ADDON',$addon,500000,$AddonSHA),
      @('BOOTSTRAP',$boot,100000,$BootSHA),
      @('SPICETIFY',$cli,40000000,$OldCliSHA))){
      if(-not(Regular ([string]$x[1]) ([long]$x[2])) -or
         (HashFile ([string]$x[1])) -cne ([string]$x[3])){
        Emit 'R125_FAILED_FILE_CLASS' ([string]$x[0])
        Fail 'R125_OPERATING_FILE_EXACT_SHA_REQUIRED'
      }
    }
    if(-not(Regular $vendor 300000000) -or -not(Regular $cfg 1000000) -or
       -not(Test-Path -LiteralPath $spiceBackup -PathType Container) -or
       @(Get-ChildItem -LiteralPath $spiceBackup -File -Filter '*.spa').Count -lt 1){
      Fail 'R125_EXISTING_VENDOR_CONFIG_BACKUP_REQUIRED'
    }
    $sig=Get-AuthenticodeSignature -LiteralPath $vendor
    $vendorVersion=[string]([Diagnostics.FileVersionInfo]::GetVersionInfo($vendor).ProductVersion)
    if($sig.Status -ne 'Valid' -or $null -eq $sig.SignerCertificate -or
       $sig.SignerCertificate.Subject -cnotmatch '(?i)(^|,)\s*O=Spotify AB(,|$)' -or
       $vendorVersion -cnotmatch '^1\.3\.6\.1921(\.|$)'){
      Fail 'R125_SIGNED_COMPATIBLE_SPOTIFY_REQUIRED'
    }
    if(-not(Regular $statePath 2097152)){Fail 'R125_STATE_MISSING'}
    $stateReadSha=HashFile $statePath
    $state=Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    $beforeStateSha=HashFile $statePath
    if($beforeStateSha -cne $stateReadSha){
      Fail 'R125_STATE_CHANGED_DURING_READ'
    }
    $admission=StateClass $state
    Emit 'R125_STATE_ADMISSION' $admission
    Emit 'R125_SAVED_DISCOVERY_HEALTH' (StateFlag $state 'maintenance_check_healthy')
    Emit 'R125_SAVED_PENDING_MAINTENANCE' (StateFlag $state 'pending_maintenance')
    Emit 'R125_SAVED_PENDING_SPICETIFY' (StateFlag $state 'pending_spicetify_upgrade')
    Emit 'R125_LAST_DECISION_CLASS' (StateDecisionClass $state)
    if($admission -cne 'ARMED_FRESH_DISCOVERY_REQUIRED'){
      Fail 'R125_OWNER_STATE_UNSAFE_OR_NOT_ARMED'
    }
    # Last decision and pending flags are stale observations, not a lease,
    # not an approval grant, and not proof of currently due maintenance.
    # The pinned product's fresh check and guarded admission remain mandatory.
    $priorTxnId=''
    $priorTxnSha='ABSENT'
    if(Test-Path -LiteralPath $txnPath){
      if(-not(Regular $txnPath 2097152)){
        Fail 'R125_PREVIOUS_LEDGER_NOT_REGULAR'
      }
      $priorTxnSha=HashFile $txnPath
      $priorTxn=Get-Content -LiteralPath $txnPath -Raw | ConvertFrom-Json
      if((HashFile $txnPath) -cne $priorTxnSha){
        Fail 'R125_PREVIOUS_LEDGER_CHANGED_DURING_READ'
      }
      if([string](R125Field $priorTxn 'status') -cnotin @('committed','rolled-back')){
        Fail 'R125_PREVIOUS_TRANSACTION_NOT_SETTLED'
      }
      $priorTxnId=[string](R125Field $priorTxn 'id')
      if([string]::IsNullOrWhiteSpace($priorTxnId)){
        Fail 'R125_PREVIOUS_TRANSACTION_ID_UNVERIFIED'
      }
    }
    Emit 'R125_PREVIOUS_LEDGER_CLASS' $(if($priorTxnSha -ceq 'ABSENT'){'ABSENT'}else{'SETTLED_PINNED'})
    $oldBytes=[IO.File]::ReadAllBytes($script:OriginalMain)
    if((HashBytes $oldBytes) -cne $mainPreflightSHA){
      Fail 'R125_MAIN_CHANGED_DURING_READ'
    }
    if($mainMode -ceq 'ORIGINAL_V0630'){
      $script:PatchedMain=PatchExactR112 $oldBytes
      Emit 'R125_R112_PATCH' 'EXACT_SOURCE_BYTES_PROVEN'
    }else{
      $script:PatchedMain=$null
      Emit 'R125_R112_PATCH' 'ALREADY_PINNED_NO_MAIN_WRITE'
    }
    $Phase='BACKUP_STAGING'
    $script:StageRoot=Join-Path $env:LOCALAPPDATA ('SpotifyControl-R125-Recovery-'+([guid]::NewGuid().ToString('N')))
    if(Test-Path $script:StageRoot){Fail 'R125_RECOVERY_PATH_COLLISION'}
    [void][IO.Directory]::CreateDirectory($script:StageRoot)
    $persistent=Join-Path $script:StageRoot 'PREEXISTING-MAIN-SHA-PINNED.ps1'
    [IO.File]::WriteAllBytes($persistent,$oldBytes)
    if((HashFile $persistent) -cne $mainPreflightSHA){
      Fail 'R125_RECOVERY_SOURCE_NOT_VERIFIED'
    }
    Emit 'R125_PREEXISTING_MAIN_BACKUP' 'SHA_PINNED_AND_RETAINED'
    $Phase='OFFICIAL_RELEASE_PROVENANCE'
    $script:ExpectedNewExe=AuthOfficialRelease $script:StageRoot
    Emit 'R125_OFFICIAL_2467_ZIP_SHA' 'PASS'
    StopRunningCondition
    if((HashFile $statePath) -cne $beforeStateSha){
      Fail 'R125_STATE_CHANGED_SINCE_PREFLIGHT'
    }
    if($priorTxnSha -ceq 'ABSENT'){
      if(Test-Path -LiteralPath $txnPath){
        Fail 'R125_LEDGER_CHANGED_SINCE_PREFLIGHT'
      }
    }elseif((HashFile $txnPath) -cne $priorTxnSha){
      Fail 'R125_LEDGER_CHANGED_SINCE_PREFLIGHT'
    }
    $Phase='SOURCE_ATOMIC_SWAP'
    if($mainMode -ceq 'ORIGINAL_V0630'){
      ReplaceMain $OriginalSHA $script:PatchedMain 'R125-BEFORE-SWAP-ORIGINAL.ps1'
      $script:SourceSwapped=$true
      Emit 'R125_TWO_FUNCTION_PUBLICATION' 'EXACT_R112_SHA_PASS'
    }else{
      # Check again immediately before the action, but never re-apply R112.
      if((HashFile $script:OriginalMain) -cne $CandidateSHA){
        Fail 'R125_EXISTING_R112_CHANGED_BEFORE_AGENT'
      }
      Emit 'R125_TWO_FUNCTION_PUBLICATION' 'ALREADY_INSTALLED_NO_SOURCE_WRITE'
    }
    $Phase='AGENT_ONESHOT'
    $psExe=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $stdout=Join-Path $script:StageRoot 'AgentTick-PRIVATE.stdout'
    $stderr=Join-Path $script:StageRoot 'AgentTick-PRIVATE.stderr'
    $args='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+$script:OriginalMain+'" -Action AgentTick -AgentEvent SpotifyExit'
    $script:AttemptStartedUtc=[DateTimeOffset]::UtcNow
    $script:AgentStarted=$true
    $proc=Start-Process -FilePath $psExe -ArgumentList $args -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
    if(-not $proc.WaitForExit(300000)){
      # The product can be midway through full-root swap, backup/apply or
      # rollback. Killing it risks leaving the journal in an uncertain phase.
      # Stop waiting, never auto-retry, preserve owner recovery materials.
      Fail 'R125_AGENT_TIMEOUT_LEFT_RUNNING_FOR_OWNER_REVIEW'
    }
    $childExit=$proc.ExitCode
    Emit 'R125_AGENT_EXIT' $(if($childExit -eq 0){'ZERO'}else{'NONZERO'})
    $Phase='FINAL_TRANSACTION_EVIDENCE'
    if(-not(Regular $cli 40000000)){Fail 'R125_CLI_AFTER_MISSING'}
    $installedDigest=HashFile $cli
    $sourceDigest=HashFile $script:OriginalMain
    $afterState=$null
    $afterTxn=$null
    try{
      if(Regular $statePath 2097152){
        $afterState=Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
      }
      if(Regular $txnPath 2097152){
        $afterTxn=Get-Content -LiteralPath $txnPath -Raw | ConvertFrom-Json
      }
    }catch{}
    $proof=Test-R125CommittedUpgrade $afterTxn $afterState $priorTxnId `
      $script:AttemptStartedUtc $script:ExpectedNewExe $installedDigest $sourceDigest
    Emit 'R125_PRODUCT_COMMIT_EVIDENCE' $proof
    if($childExit -eq 0 -and
       $proof -ceq 'FRESH_COMMITTED_ROOT_APPLY_AND_EXTRAS_VERIFIED' -and
       (Regular $cfg 1000000) -and
       @(Get-ChildItem -LiteralPath $spiceBackup -File -Filter '*.spa').Count -gt 0){
      $script:Succeeded=$true
      Emit 'R125_OFFICIAL_SPICETIFY_2467_EXACT' 'PASS'
      Emit 'R125_PRODUCT_TRANSACTION' 'FRESH_COMMIT_APPLY_GUARD_AND_EXTRAS_PASS'
      Emit 'R125_R112_MAIN_INSTALLED' 'EXACT'
      Emit 'RESULT' 'AUTO_UPDATE_2467_VERIFIED_REVIEW_OWNER'
    }else{
      Emit 'R125_CLI_MATCHES_EXACT_2467' $(if($installedDigest -ceq $script:ExpectedNewExe){'YES'}else{'NO'})
      Emit 'R125_TRANSACTION_STATUS' 'NOT_PROVEN_NO_AUTO_RETRY'
      Fail 'R125_TRANSACTION_AND_POSTFLIGHT_NOT_PROVEN'
    }
  }
}catch{
  $message=[string]$_.Exception.Message
  $known=@(
    'R125_WINDOWS_POWERSHELL_51_X64_REQUIRED','R125_BUILDONLY_REQUIRES_PINNED_HOSTED_FIXTURE',
    'R125_FIXTURE_ABSENT','R125_EXPLICIT_APPROVAL_REQUIRED','R125_STANDARD_OWNER_REQUIRED',
    'R125_OPERATING_FILE_EXACT_SHA_REQUIRED','R125_EXISTING_VENDOR_CONFIG_BACKUP_REQUIRED',
    'R125_SIGNED_COMPATIBLE_SPOTIFY_REQUIRED','R125_STATE_MISSING',
    'R125_OWNER_STATE_DRIFT_OR_NOT_HEALTHY','R125_RECOVERY_PATH_COLLISION',
    'R125_RECOVERY_SOURCE_NOT_VERIFIED','R125_STATE_CHANGED_SINCE_PREFLIGHT',
    'R125_SPOTIFY_RUNNING','R125_SPOTIFY_STARTED_DURING_TRANSACTION',
    'R125_OFFICIAL_RELEASE_ASSET_NOT_PINNED','R125_OFFICIAL_CLI_ARCHIVE_EXE_UNIQUE_REQUIRED',
    'R125_MAIN_CHANGED_DURING_TRANSACTION','R125_ATOMIC_PUBLICATION_NOT_VERIFIED',
    'R125_TRANSACTION_AND_POSTFLIGHT_NOT_PROVEN','R125_AGENT_ONESHOT_TIMEOUT_UNCERTAIN',
    'R125_R112_TARGET_SHA_MISMATCH','R125_ORIGINAL_MAIN_SHA_MISMATCH',
    'R125_OWNER_STATE_UNSAFE_OR_NOT_ARMED','R125_STATE_CHANGED_DURING_READ',
    'R125_MAIN_NOT_REGULAR_OR_MISSING','R125_MAIN_UNRECOGNIZED_NO_OVERWRITE',
    'R125_MAIN_CHANGED_DURING_READ','R125_EXISTING_R112_CHANGED_BEFORE_AGENT',
    'R125_PREVIOUS_LEDGER_NOT_REGULAR','R125_PREVIOUS_LEDGER_CHANGED_DURING_READ',
    'R125_PREVIOUS_TRANSACTION_NOT_SETTLED','R125_PREVIOUS_TRANSACTION_ID_UNVERIFIED',
    'R125_LEDGER_CHANGED_SINCE_PREFLIGHT','R125_AGENT_TIMEOUT_LEFT_RUNNING_FOR_OWNER_REVIEW'
  )
  $reason=if($message -cin $known -or
      $message -match '^R125_PINNED_PATCH_ANCHOR_DRIFT_[A-Z_]+$' -or
      $message -match '^R125_PINNED_FUNCTION_DRIFT_[A-Za-z_-]+$'){
    $message
  }else{'R125_UNCLASSIFIED_HOLD'}
  $errClass=$_.Exception.GetType().Name
  if($errClass -cin @('InvalidOperationException','ArgumentException','ArgumentOutOfRangeException',
    'MethodException','RuntimeException','NullReferenceException','ParameterBindingException',
    'FormatException','IOException','FileNotFoundException')){
    Emit 'R125_ERROR_CLASS' $errClass
  }
  Emit 'HOLD_REASON' $reason
  Emit 'FAILED_PHASE' $Phase
  Emit 'RESULT' 'HOLD_NO_AUTOMATIC_RETRY'
}finally{
  if($Mode -ceq 'Once' -and $script:SourceSwapped -and -not $script:Succeeded -and -not $script:AgentStarted){
    try{
      if((HashFile $script:OriginalMain) -ceq $CandidateSHA){
        $originalBytes=[IO.File]::ReadAllBytes((Join-Path $script:StageRoot 'PREEXISTING-MAIN-SHA-PINNED.ps1'))
        if((HashBytes $originalBytes) -cne $OriginalSHA){Fail 'R125_RECOVERY_SOURCE_CHANGED'}
        ReplaceMain $CandidateSHA $originalBytes 'R125-FAILED-R112-RETAIN.ps1'
        Emit 'R125_MAIN_SOURCE_ROLLBACK' 'ORIGINAL_V0630_SHA_PASS'
      }else{Emit 'R125_MAIN_SOURCE_ROLLBACK' 'SKIPPED_SOURCE_DRIFT_REVIEW_REQUIRED'}
    }catch{Emit 'R125_MAIN_SOURCE_ROLLBACK' 'FAILED_REVIEW_REQUIRED'}
  }
  if($Mode -ceq 'Once' -and $script:SourceSwapped -and -not $script:Succeeded -and $script:AgentStarted){
    Emit 'R125_MAIN_ROLLBACK' 'NOT_ATTEMPTED_AFTER_AGENT_START_UNCERTAIN_MUTATION'
    Emit 'R125_OWNER_REVIEW' 'REQUIRED_NO_AUTO_RETRY_OR_AUTOMATIC_RECOVERY'
  }
  if($null -ne $script:StageRoot){
    Emit 'R125_RECOVERY_FOLDER' 'RETAINED_IN_LOCALAPPDATA'
  }
  Emit 'SPOTIFY_CONTROL_PUBLIC_MAIN' 'UNCHANGED'
  Emit 'ORIGINAL_USER_FILES_DELETED' 'NO'
  $out=$Report -join [Environment]::NewLine
  try{Set-Clipboard -Value $out -ErrorAction Stop}catch{}
  Write-Output $out
}
