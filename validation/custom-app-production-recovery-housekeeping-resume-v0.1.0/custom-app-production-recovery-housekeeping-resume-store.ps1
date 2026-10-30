$CustomAppProductionRecoveryHousekeepingResumeMaxBytes = 4194304

function Get-CustomAppProductionRecoveryHousekeepingResumePathsV010 {
    param([Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory)
    $store=Assert-CustomAppProductionCrashJournalPathV010 -AllowedRoot $AllowedRoot -Path $StoreDirectory -Label 'housekeeping resume store' -RequireExisting:$true
    if(-not(Test-Path -LiteralPath $store -PathType Container)){throw 'housekeeping resume store not directory'}
    $item=Get-Item -LiteralPath $store -Force -ErrorAction Stop
    if(($item.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'housekeeping resume store reparse point'}
    return [pscustomobject]@{store=$store;file=(Join-Path $store 'housekeeping-resume.json');lock=(Join-Path $store '.housekeeping-resume.lock')}
}
function Open-CustomAppProductionRecoveryHousekeepingResumeLockV010 {
    param([Parameter(Mandatory=$true)]$Paths)
    try{return [IO.File]::Open([string]$Paths.lock,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch [IO.IOException]{throw 'housekeeping-resume-lock-busy'}
}
function Read-CustomAppProductionRecoveryHousekeepingResumeEnvelopeUnlockedV010 {
    param([Parameter(Mandatory=$true)]$Paths)
    if(-not(Test-Path -LiteralPath ([string]$Paths.file))){return [pscustomobject]@{ok=$false;reason='housekeeping-resume-envelope-missing';envelope=$null}}
    $item=Get-Item -LiteralPath ([string]$Paths.file) -Force -ErrorAction Stop
    if(($item.Attributes-band[IO.FileAttributes]::ReparsePoint)-ne0){throw 'housekeeping-resume-envelope-reparse-point'}
    if($item.PSIsContainer){throw 'housekeeping-resume-envelope-not-file'}
    if([int64]$item.Length -gt [int64]$CustomAppProductionRecoveryHousekeepingResumeMaxBytes){throw 'housekeeping-resume-envelope-too-large'}
    $raw=[IO.File]::ReadAllText([string]$Paths.file,(New-Object Text.UTF8Encoding($false)))
    try{$e=$raw|ConvertFrom-Json}catch{throw 'housekeeping-resume-envelope-JSON-invalid'}
    $check=Test-CustomAppProductionRecoveryHousekeepingResumeEnvelopeV010 $e
    if(-not[bool]$check.ok){throw ('housekeeping-resume-envelope-invalid:'+[string]$check.reason)}
    return [pscustomobject]@{ok=$true;reason='housekeeping-resume-envelope-reloaded';envelope=$e;path=[string]$Paths.file;reloaded_from_persistent_store=$true}
}
function Read-CustomAppProductionRecoveryHousekeepingResumeEnvelopeV010 {
    param([Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory)
    $paths=Get-CustomAppProductionRecoveryHousekeepingResumePathsV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory;$lock=$null
    try{$lock=Open-CustomAppProductionRecoveryHousekeepingResumeLockV010 $paths;return Read-CustomAppProductionRecoveryHousekeepingResumeEnvelopeUnlockedV010 $paths}
    finally{if($null-ne$lock){$lock.Dispose()}}
}
function Write-CustomAppProductionRecoveryHousekeepingResumeEnvelopeFileV010 {
    param([Parameter(Mandatory=$true)][string]$AllowedRoot,[Parameter(Mandatory=$true)][string]$StoreDirectory,[Parameter(Mandatory=$true)]$Envelope)
    $deny={param([string]$Reason)[pscustomobject]@{ok=$false;reason=$Reason;persisted=$false;read_after_write_verified=$false;resume_is_authority=$false;cleanup_authorized=$false;execution_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false}}
    $check=Test-CustomAppProductionRecoveryHousekeepingResumeEnvelopeV010 $Envelope
    if(-not[bool]$check.ok){return & $deny ('housekeeping-resume-envelope-invalid-before-write:'+[string]$check.reason)}
    $paths=$null;$lock=$null
    try{
        $paths=Get-CustomAppProductionRecoveryHousekeepingResumePathsV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory
        $lock=Open-CustomAppProductionRecoveryHousekeepingResumeLockV010 $paths
        if(Test-Path -LiteralPath ([string]$paths.file)){return & $deny 'housekeeping-resume-envelope-already-exists-replay-denied'}
        $json=$Envelope|ConvertTo-Json -Depth 50 -Compress
        $bytes=(New-Object Text.UTF8Encoding($false)).GetBytes($json)
        if($bytes.Length -gt $CustomAppProductionRecoveryHousekeepingResumeMaxBytes){return & $deny 'housekeeping-resume-envelope-too-large-before-write'}
        $stream=$null
        try{$stream=[IO.File]::Open([string]$paths.file,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None);$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}
        finally{if($null-ne$stream){$stream.Dispose()}}
        $verify=Read-CustomAppProductionRecoveryHousekeepingResumeEnvelopeUnlockedV010 $paths
        if(-not[bool]$verify.ok -or ([string]$verify.envelope.resume_fingerprint).Trim().ToLowerInvariant()-cne([string]$Envelope.resume_fingerprint).Trim().ToLowerInvariant()){throw 'housekeeping-resume-envelope-readback-mismatch'}
        return [pscustomobject]@{ok=$true;reason='housekeeping-resume-envelope-durable-readback-verified';persisted=$true;read_after_write_verified=$true;path=[string]$paths.file;envelope=$verify.envelope;resume_is_authority=$false;cleanup_authorized=$false;execution_authorized=$false;production_execution_authorized=$false;production_mutation_authorized=$false}
    }catch{return & $deny ('housekeeping-resume-envelope-write-failed:'+[string]$_.Exception.Message)}
    finally{if($null-ne$lock){$lock.Dispose()}}
}
