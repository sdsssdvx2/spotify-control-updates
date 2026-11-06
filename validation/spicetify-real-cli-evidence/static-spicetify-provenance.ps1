# Static CurrentUser Spicetify binary/config provenance: NO PROCESS START.
# Does not trust PATH, SC_RX_* test variables, SPICETIFY_CONFIG, or an archive
# checksum as a substitute for the SHA-256 of the ACTUAL executable bytes.
# This is a read-only evidence primitive, not update/recovery authority.
function Get-CustomAppSpicetifyCanonicalEvidenceV015 {
    param([string]$HostedCiProfileRoot,
          [AllowNull()][string]$ExpectedExecutableSha256=$null)
    if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT){
        throw 'spicetify-profile-evidence-windows-only'
    }
    $deny={param([string]$Reason)
        return [pscustomobject]@{
            schema=1;ok=$false;reason=$Reason
            config_path_known=$false;config_file_present=$false
            executable_present=$false;executable_sha256=''
            executable_pin_matched=$false
            executable_was_started=$false;spotify_was_started=$false
            no_app_state_modified=$true;result_is_authority=$false
            production_execution_authorized=$false
            production_mutation_authorized=$false
        }
    }
    if(-not[string]::IsNullOrWhiteSpace($ExpectedExecutableSha256) -and
       $ExpectedExecutableSha256 -cnotmatch '^[0-9a-f]{64}$'){
        return & $deny 'spicetify-profile-expected-exe-hash-format-invalid'
    }
    if([string]::IsNullOrWhiteSpace($HostedCiProfileRoot)){
        if(-not[string]::IsNullOrWhiteSpace($env:SPICETIFY_CONFIG) -or
           -not[string]::IsNullOrWhiteSpace($env:SPICETIFY_STATE)){
            return & $deny 'spicetify-profile-environment-path-override-unqualified'
        }
        $local=[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
        $roaming=[Environment]::GetFolderPath([Environment+SpecialFolder]::ApplicationData)
    }else{
        if($env:GITHUB_ACTIONS -cne 'true' -or
           $env:RUNNER_OS -cne 'Windows' -or
           $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
           [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
            throw 'spicetify-profile-override-hosted-Windows-only'
        }
        if(-not[IO.Path]::IsPathRooted($HostedCiProfileRoot) -or
           $HostedCiProfileRoot.StartsWith('\\')){
            throw 'spicetify-profile-hosted-root-not-local-absolute'
        }
        $ci=[IO.Path]::GetFullPath($env:RUNNER_TEMP).TrimEnd('\','/')
        $base=[IO.Path]::GetFullPath($HostedCiProfileRoot).TrimEnd('\','/')
        if(-not $base.StartsWith(($ci+'\'),[StringComparison]::OrdinalIgnoreCase)){
            throw 'spicetify-profile-hosted-root-outside-runner'
        }
        $local=Join-Path $base 'profile-local'
        $roaming=Join-Path $base 'profile-roaming'
    }
    foreach($p in @($local,$roaming)){
        if([string]::IsNullOrWhiteSpace($p) -or
           -not[IO.Directory]::Exists($p) -or
           (Get-Item -LiteralPath $p -Force -ErrorAction Stop).Attributes -band
              [IO.FileAttributes]::ReparsePoint){
            return & $deny 'spicetify-profile-user-root-missing-or-reparse'
        }
    }
    $exe=Join-Path (Join-Path $local 'spicetify') 'spicetify.exe'
    $cfg=Join-Path (Join-Path $roaming 'spicetify') 'config-xpui.ini'
    foreach($target in @($exe,$cfg)){
        $parent=[IO.Path]::GetDirectoryName($target)
        while(-not[string]::IsNullOrWhiteSpace($parent)){
            $info=Get-Item -LiteralPath $parent -Force -ErrorAction SilentlyContinue
            if($null-ne$info -and ($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
                return & $deny 'spicetify-profile-target-ancestor-reparse'
            }
            $next=[IO.Path]::GetDirectoryName($parent)
            if([string]::IsNullOrWhiteSpace($next) -or $next -ceq $parent){break}
            $parent=$next
        }
    }
    if(-not[IO.File]::Exists($exe)){
        return & $deny 'spicetify-profile-canonical-exe-missing'
    }
    $item=Get-Item -LiteralPath $exe -Force -ErrorAction Stop
    if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
       $item.Length -lt 100000 -or $item.Length -gt 50000000){
        return & $deny 'spicetify-profile-exe-reparse-or-size-invalid'
    }
    $handle=$null;$sha=[Security.Cryptography.SHA256]::Create()
    try{
        $handle=[IO.File]::Open($exe,[IO.FileMode]::Open,[IO.FileAccess]::Read,
            [IO.FileShare]::Read)
        $digest=([BitConverter]::ToString($sha.ComputeHash($handle))).Replace('-','').ToLowerInvariant()
    }finally{
        if($null-ne$handle){$handle.Dispose()}
        $sha.Dispose()
    }
    if($digest -cnotmatch '^[0-9a-f]{64}$'){
        throw 'spicetify-profile-exe-hash-algorithm-failed'
    }
    if([IO.File]::Exists($cfg) -and
       ((Get-Item -LiteralPath $cfg -Force -ErrorAction Stop).Attributes -band
        [IO.FileAttributes]::ReparsePoint) -ne 0){
        return & $deny 'spicetify-profile-config-reparse'
    }
    $present=[IO.File]::Exists($cfg)
    $pin=([string]$ExpectedExecutableSha256 -ceq $digest)
    if(-not[string]::IsNullOrWhiteSpace($ExpectedExecutableSha256) -and -not $pin){
        return & $deny 'spicetify-profile-enrolled-exe-pin-mismatch'
    }
    return [pscustomobject]@{
        schema=1;ok=$true
        reason='spicetify-profile-static-read-only-evidence'
        config_path_known=$true;config_file_present=[bool]$present
        executable_present=$true;executable_sha256=$digest
        executable_pin_matched=[bool]$pin
        expected_pin_supplied=(-not[string]::IsNullOrWhiteSpace($ExpectedExecutableSha256))
        executable_was_started=$false;spotify_was_started=$false
        no_app_state_modified=$true;result_is_authority=$false
        production_execution_authorized=$false
        production_mutation_authorized=$false
        # Return only a stable canonical profile-relative locator so a
        # consumer does not accidentally treat arbitrary user path text as
        # authorization. Full paths are not needed in the result.
        executable_relative='spicetify/spicetify.exe'
        config_relative='spicetify/config-xpui.ini'
    }
}

function Test-CustomAppSpicetifyCanonicalEvidenceSelfTestV015 {
    if([bool]$script:CustomAppProductionPipelineEnabled){
        throw 'spicetify-canonical-evidence-cannot-enable-fullchain'
    }
    if(-not(Get-Command Get-CustomAppSpicetifyCanonicalEvidenceV015 -CommandType Function -ErrorAction SilentlyContinue)){
        throw 'spicetify-canonical-evidence-export-missing'
    }
    Write-Host 'SPICETIFY_CANONICAL_EVIDENCE_SELFTEST_PASS no_cli_execution=true canonical_currentuser_profile=true no_caller_executable_path=true zero_mutation_authority=true'
}
