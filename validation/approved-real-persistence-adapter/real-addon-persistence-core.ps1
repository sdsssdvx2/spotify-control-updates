# V031 uses the ACTUAL pinned Addon Manager's Spotify persistence
# functions, never a recreated list of protected Spotify data paths.
# The exact source is only executed in disposable hosted Windows fixtures.
function Assert-RealAddonPersistenceHostedV031 {
    if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
       $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
       $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
       [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
        throw 'V031_HOSTED_WINDOWS_ONLY_NO_REAL_PROFILE'
    }
}
function Get-ExactAddonPersistenceFunctionsV031 {
    param([Parameter(Mandatory=$true)][string]$OriginalAddonPath)
    Assert-RealAddonPersistenceHostedV031
    $file=[IO.Path]::GetFullPath($OriginalAddonPath)
    if(-not[IO.File]::Exists($file) -or
       ([IO.FileInfo]::new($file)).Length -ne 1453028 -or
       (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -cne
          '0cb2362dd14772f19ba2970e5f4c2bc07bf0512c0de31494af7b01cb2a98fdd6'){
       throw 'V031_EXACT_QUALIFIED_REAL_ADDON_SOURCE_REQUIRED'
    }
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw 'V031_QUALIFIED_REAL_ADDON_PARSE_FAILED'}
    $fns=@($ast.FindAll({param($n)
        $n -is [Management.Automation.Language.FunctionDefinitionAst]},$true))
    $required=@('Get-StringSha256Lower','Test-PathSafe','Copy-TreeSafe',
        'Get-PathContentFingerprint','Get-SpotifyPersistenceSurfaceDefinitions',
        'Get-SpotifyPersistenceSnapshot','New-RequiredSpotifyPersistenceBackup')
    $def=New-Object 'System.Collections.Generic.List[string]'
    foreach($name in $required){
        $found=@($fns|Where-Object{$_.Name -ceq $name})
        if($found.Count -ne 1){throw ('V031_TRUSTED_PERSISTENCE_FUNCTION_NOT_UNIQUE_'+$name)}
        $def.Add([string]$found[0].Extent.Text)
    }
    # Safe by construction: only the pinned original function declarations,
    # not startup, update, elevation, commands, or local disk automation.
    return [ScriptBlock]::Create(($def.ToArray() -join ([Environment]::NewLine+[Environment]::NewLine)))
}
function Assert-RealAddonPersistenceRootsV031 {
    param([Parameter(Mandatory=$true)][string]$RunnerRoot,
          [Parameter(Mandatory=$true)][string]$LocalRoot,
          [Parameter(Mandatory=$true)][string]$RoamingRoot)
    Assert-RealAddonPersistenceHostedV031
    $runner=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
    if(-not $runner.Equals([IO.Path]::GetFullPath($RunnerRoot).TrimEnd('\','/'),[StringComparison]::OrdinalIgnoreCase)){
       throw 'V031_RUNNER_ROOT_NOT_CURRENT_RUNNER_TEMP'
    }
    foreach($s in @($LocalRoot,$RoamingRoot)){
        $p=Assert-CustomAppProductionCrashJournalPathV010 -AllowedRoot $runner -Path $s -RequireExisting:$true
        if(-not[IO.Directory]::Exists($p)){throw 'V031_PERSISTENCE_ROOT_NOT_EXISTING_DIRECTORY'}
    }
    $defs=@(Get-SpotifyPersistenceSurfaceDefinitions -LocalAppDataRoot $LocalRoot -AppDataRoot $RoamingRoot)
    if($defs.Count -lt 4){throw 'V031_REAL_ADDON_SURFACE_DEFINITIONS_UNEXPECTEDLY_FEW'}
    $seen=@{}
    foreach($def in $defs){
        $id=[string]$def.id
        $kind=[string]$def.kind
        if($id -cnotmatch '^[A-Za-z0-9_-]{2,80}$' -or $seen.ContainsKey($id) -or
           $kind -notin @('Directory','File')){
           throw 'V031_REAL_ADDON_SURFACE_ID_KIND_AMBIGUOUS'
        }
        $seen[$id]=$true
        $path=[IO.Path]::GetFullPath([string]$def.path)
        $local=[IO.Path]::GetFullPath($LocalRoot).TrimEnd('\','/')
        $roaming=[IO.Path]::GetFullPath($RoamingRoot).TrimEnd('\','/')
        if(-not $path.StartsWith(($local+'\'),[StringComparison]::OrdinalIgnoreCase) -and
           -not $path.StartsWith(($roaming+'\'),[StringComparison]::OrdinalIgnoreCase)){
           throw 'V031_REAL_ADDON_PERSISTENCE_DEFINITION_ESCAPE'
        }
        [void](Assert-CustomAppProductionCrashJournalPathV010 -AllowedRoot $runner -Path $path)
    }
    return $defs
}
function Invoke-ActualAddonPersistenceGuardedBackupV031 {
    param([Parameter(Mandatory=$true)][string]$RunnerRoot,
          [Parameter(Mandatory=$true)][string]$LocalRoot,
          [Parameter(Mandatory=$true)][string]$RoamingRoot,
          [Parameter(Mandatory=$true)][string]$BackupRoot)
    Assert-RealAddonPersistenceHostedV031
    $defs=Assert-RealAddonPersistenceRootsV031 -RunnerRoot $RunnerRoot -LocalRoot $LocalRoot -RoamingRoot $RoamingRoot
    $runner=[IO.Path]::GetFullPath($RunnerRoot)
    $backup=Assert-CustomAppProductionCrashJournalPathV010 -AllowedRoot $runner -Path $BackupRoot
    if([IO.Directory]::Exists($backup) -or [IO.File]::Exists($backup)){
       throw 'V031_REAL_PERSISTENCE_BACKUP_ALREADY_EXISTS'
    }
    foreach($root in @($LocalRoot,$RoamingRoot)){
       if(Test-CustomAppAtomicPathsOverlapV010 -A $root -B $backup){
           throw 'V031_BACKUP_OVERLAPS_ORIGINAL_SPOTIFY_DATA'
       }
    }
    $before=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $LocalRoot -AppDataRoot $RoamingRoot
    if([int]$before.surface_count -ne $defs.Count -or
       [string]$before.fingerprint -cnotmatch '^[0-9a-f]{64}$'){
        throw 'V031_REAL_BACKEND_SNAPSHOT_INCOMPLETE'
    }
    # The original function copies exactly its OWN inventory and hashes every
    # declared surface. No new external persistence inventory is invented.
    [IO.Directory]::CreateDirectory($backup)|Out-Null
    $copy=New-RequiredSpotifyPersistenceBackup -LocalAppDataRoot $LocalRoot -AppDataRoot $RoamingRoot -BackupRootOverride $backup
    if([string]$copy.fingerprint -cne [string]$before.fingerprint -or
       [int]$copy.surface_count -ne [int]$before.surface_count){
       throw 'V031_ACTUAL_ADDON_BACKUP_RECEIPT_DIFFERENT_FROM_SOURCE'
    }
    $check=Test-CustomAppProductionPersistenceBackupV010 -BackupPath ([string]$copy.path) -ExpectedFingerprint ([string]$before.fingerprint)
    if(-not[bool]$check.ok){throw ('V031_ACTUAL_BACKEND_BACKUP_MANIFEST_DENIED:'+ [string]$check.reason)}
    $after=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $LocalRoot -AppDataRoot $RoamingRoot
    if([string]$after.fingerprint -cne [string]$before.fingerprint){
       throw 'V031_SPOTIFY_PROTECTED_SURFACE_CHANGED_DURING_BACKUP'
    }
    return [pscustomobject]@{
       ok=$true;backup_path=[string]$copy.path
       persistence_fingerprint=[string]$before.fingerprint
       surface_count=[int]$before.surface_count
       source_baseline=$before
       original_addon_persistence_backend=$true
       every_originally_declared_surface_verified=$true
       every_possible_spotify_data_path_proven=$false
       operating_profile_changed=$false
       production_mutation_authorized=$false
    }
}
