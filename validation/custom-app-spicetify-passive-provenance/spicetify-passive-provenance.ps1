# Observe canonical per-user Spicetify files WITHOUT invoking the CLI.
# Upstream -v/-c can create directories via Go initialization; neither is
# called here. The cooperative global lock itself may create its lockfile.
# This is NOT a signed enrollment, binary trust check or apply authorization.
function Get-CustomAppSpicetifyPassiveFileSha256V015 {
    param([Parameter(Mandatory=$true)][string]$Path)
    $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,
        [IO.FileAccess]::Read,[IO.FileShare]::Read)
    try{
        $sha=[Security.Cryptography.SHA256]::Create()
        try{return ([BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','').ToLowerInvariant())}
        finally{$sha.Dispose()}
    }finally{$stream.Dispose()}
}
function Get-CustomAppSpicetifyPassiveObservationV015 {
    param(
        [string]$HostedCiRoot,
        [string]$HostedCiLocalAppDataRoot,
        [string]$HostedCiAppDataRoot,
        $HeldCrossEngineSession
    )
    $deny={param([string]$Reason)[pscustomobject]@{
        schema=1;ok=$false;reason=$Reason
        executable_path='';config_path='';exe_sha256='';config_sha256=''
        exe_bytes=0;config_bytes=0;observation_fingerprint=''
        binary_trusted=$false;enrolled_executable_pin=$false
        config_identity_authenticated=$false;recovery_apply_eligible=$false
        result_is_authority=$false;production_execution_authorized=$false
        production_mutation_authorized=$false
    }}
    if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){
        return & $deny 'spicetify-observation-windows-only'
    }
    if(-not[string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable('SPICETIFY_CONFIG')) -or
       -not[string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable('SPICETIFY_STATE'))){
        return & $deny 'spicetify-unenrolled-environment-override'
    }
    $global=$null;$ownsGlobal=$false
    try{
        if($null-ne$HeldCrossEngineSession){$global=$HeldCrossEngineSession}
        else{
            $global=Open-CustomAppCrossEngineTransactionLockV010 -HostedCiRoot $HostedCiRoot
            $ownsGlobal=$true
        }
        [void](Assert-CustomAppCrossEngineTransactionLockHeldV010 -Session $global)
        $local=[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
        $roaming=[Environment]::GetFolderPath([Environment+SpecialFolder]::ApplicationData)
        $root=$local
        if(-not[string]::IsNullOrWhiteSpace($HostedCiRoot)){
            if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
               $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
               [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
                throw 'spicetify-observation-profile-override-not-hosted'
            }
            $runner=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
            foreach($x in @($HostedCiRoot,$HostedCiLocalAppDataRoot,$HostedCiAppDataRoot)){
                if([string]::IsNullOrWhiteSpace($x) -or
                   -not[IO.Path]::IsPathRooted($x) -or $x.StartsWith('\\') -or
                   -not[IO.Path]::GetFullPath($x).StartsWith(($runner+'\'),[StringComparison]::OrdinalIgnoreCase)){
                    throw 'spicetify-observation-hosted-root-unqualified'
                }
            }
            $root=[IO.Path]::GetFullPath($HostedCiRoot)
            $local=[IO.Path]::GetFullPath($HostedCiLocalAppDataRoot)
            $roaming=[IO.Path]::GetFullPath($HostedCiAppDataRoot)
        }elseif(-not[string]::IsNullOrWhiteSpace($HostedCiLocalAppDataRoot) -or
                -not[string]::IsNullOrWhiteSpace($HostedCiAppDataRoot)){
            throw 'spicetify-observation-unhosted-profile-override'
        }
        if(-not[IO.Path]::GetFullPath([string]$global.root).Equals(
            [IO.Path]::GetFullPath($root),[StringComparison]::OrdinalIgnoreCase)){
            throw 'spicetify-observation-global-lock-wrong-profile-root'
        }
        foreach($dir in @($root,$local,$roaming)){
            [void](Assert-CustomAppUserTxnJournalLocalPathV010 -Path $dir -RequireDirectory)
        }
        $exeDir=Join-Path $local 'spicetify'
        $exe=Join-Path $exeDir 'spicetify.exe'
        $configDir=Join-Path $roaming 'spicetify'
        $config=Join-Path $configDir 'config-xpui.ini'
        foreach($dir in @($exeDir,$configDir)){
            if(-not[IO.Directory]::Exists($dir)){
                return & $deny 'spicetify-observation-expected-directory-missing'
            }
            [void](Assert-CustomAppUserTxnJournalLocalPathV010 -Path $dir -RequireDirectory)
        }
        foreach($file in @($exe,$config)){
            Assert-CustomAppUserTxnNoReparseV010 -Path $file
            if(-not[IO.File]::Exists($file)){
                return & $deny 'spicetify-observation-expected-file-missing'
            }
            $f=Get-Item -LiteralPath $file -Force -ErrorAction Stop
            if($f.PSIsContainer -or
               ($f.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
                throw 'spicetify-observation-regular-file-required'
            }
        }
        $exi=Get-Item -LiteralPath $exe -Force -ErrorAction Stop
        $cfi=Get-Item -LiteralPath $config -Force -ErrorAction Stop
        if($exi.Length -lt 1024 -or $exi.Length -gt 104857600){
            return & $deny 'spicetify-observation-executable-size-invalid'
        }
        if($cfi.Length -lt 1 -or $cfi.Length -gt 4194304){
            return & $deny 'spicetify-observation-config-size-invalid'
        }
        $exeSha=Get-CustomAppSpicetifyPassiveFileSha256V015 -Path $exe
        $cfgSha=Get-CustomAppSpicetifyPassiveFileSha256V015 -Path $config
        if($exeSha -cne (Get-CustomAppSpicetifyPassiveFileSha256V015 -Path $exe) -or
           $cfgSha -cne (Get-CustomAppSpicetifyPassiveFileSha256V015 -Path $config) -or
           $exi.Length -ne (Get-Item -LiteralPath $exe).Length -or
           $cfi.Length -ne (Get-Item -LiteralPath $config).Length){
            throw 'spicetify-observation-file-changed-while-reading'
        }
        [void](Assert-CustomAppCrossEngineTransactionLockHeldV010 -Session $global)
        $material=@('spicetify-observation-v1',$exe.ToLowerInvariant(),$exeSha,
            [string]$exi.Length,$config.ToLowerInvariant(),$cfgSha,[string]$cfi.Length) -join [Environment]::NewLine
        $digest=[Security.Cryptography.SHA256]::Create()
        try{$fingerprint=[BitConverter]::ToString($digest.ComputeHash(
            [Text.Encoding]::UTF8.GetBytes($material))).Replace('-','').ToLowerInvariant()}
        finally{$digest.Dispose()}
        return [pscustomobject]@{
            schema=1;ok=$true;reason='files-observed-not-enrolled-or-trusted'
            executable_path=$exe;config_path=$config
            exe_sha256=$exeSha;config_sha256=$cfgSha
            exe_bytes=[long]$exi.Length;config_bytes=[long]$cfi.Length
            observation_fingerprint=$fingerprint
            binary_trusted=$false;enrolled_executable_pin=$false
            config_identity_authenticated=$false;recovery_apply_eligible=$false
            result_is_authority=$false;production_execution_authorized=$false
            production_mutation_authorized=$false
        }
    }catch{
        return & $deny ('spicetify-observation-denied:'+[string]$_.Exception.Message)
    }finally{
        if($ownsGlobal -and $null-ne$global -and $null-ne$global.lock_handle){
            $global.lock_handle.Dispose()
        }
    }
}
function Test-CustomAppSpicetifyPassiveObservationSelfTestV015 {
    if([bool]$script:CustomAppProductionPipelineEnabled){
        throw 'spicetify-observation-production-pipeline-enabled'
    }
    foreach($fn in @('Get-CustomAppSpicetifyPassiveFileSha256V015',
                     'Get-CustomAppSpicetifyPassiveObservationV015')){
        if(-not(Get-Command $fn -CommandType Function -ErrorAction SilentlyContinue)){
            throw ('spicetify-observation-missing-'+$fn)
        }
    }
    Write-Host 'SPICETIFY_PASSIVE_SOURCE_SELFTEST_PASS no_cli_invocation=true no_spicetify_tree_mutation=true no_recovery_authority=true'
}
