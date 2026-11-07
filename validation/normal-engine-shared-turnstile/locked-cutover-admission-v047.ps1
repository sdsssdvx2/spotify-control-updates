# V047 bridge: the NEW candidate must enter the SAME cooperative OS
# turnstile as the generated legacy Update/Commit/Rollback handlers BEFORE
# trusting V046's installed profile and outstanding-journal admission.
# No user-profile source, XPUI, ledger or Spicetify mutation is authorized.
# Caller owns returned lock_handle and MUST Dispose() when finished.
# It may be used for future backup/commit work ONLY after a separate approved
# real-path executor is qualified; never treat its read-only hash as a permit.
function Open-CustomAppCutoverReadOnlyLeaseV047 {
 param([Parameter(Mandatory=$true)][string]$ExpectedProfileSha256,
       [string]$HostedFixtureRoot=$null,
       [string]$HostedFixtureCliPath=$null,
       [switch]$SimulatedSpotifyRunning)
 if($ExpectedProfileSha256 -cnotmatch '^[a-f0-9]{64}$'){
    throw 'V047_CUTOVER_EXPECTED_SOURCE_SNAPSHOT_INVALID'
 }
 $fixture=-not[string]::IsNullOrWhiteSpace($HostedFixtureRoot)
 if($fixture){
    if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
       $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
       [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
       throw 'V047_CUTOVER_TEST_OVERRIDE_NOT_HOSTED'
    }
    $leaseRoot=Join-Path $HostedFixtureRoot 'Local'
 }else{
    if(-not[string]::IsNullOrWhiteSpace($HostedFixtureCliPath) -or
       [bool]$SimulatedSpotifyRunning){
       throw 'V047_CUTOVER_REAL_PROFILE_OVERRIDE_FORBIDDEN'
    }
    $leaseRoot=$null
 }
 $lease=$null
 try{
    $lease=Enter-CustomAppEngineTurnstileV047 -HostedCiRoot $leaseRoot
    $admission=Get-CustomAppCutoverReadOnlyAdmissionV046 -HostedFixtureRoot $HostedFixtureRoot -HostedFixtureCliPath $HostedFixtureCliPath -SimulatedSpotifyRunning:$SimulatedSpotifyRunning
    if([string]$admission.status -cne 'observed-readonly' -or
       [string]$admission.profile_sha256 -cne $ExpectedProfileSha256 -or
       -not[bool]$admission.legacy_transaction_absent -or
       -not[bool]$admission.new_dpapi_engine_unenrolled -or
       -not[bool]$admission.no_files_modified -or
       [bool]$admission.production_mutation_authorized){
       throw 'V047_LOCKED_PROFILE_NOT_QUALIFIED'
    }
    # Preserve lock ownership until a future process-side transaction
    # decides to release. No automatic enrollment, configuration change,
    # app rename, or irreversible process action is initiated.
    return [pscustomobject]@{
       schema=1;status='locked-readonly'
       lock_handle=$lease
       binding_sha256=[string]$admission.profile_sha256
       full_xpui_snapshot_sha256=[string]$admission.full_xpui_snapshot_sha256
       legacy_transaction_absent=$true
       new_engine_not_enrolled=$true
       cooperative_legacy_engine_lease_held=$true
       older_unpatched_processes_excluded=$false
       no_software_launch=$true
       no_spotify_or_custom_app_write=$true
       backup_preimage_durable=$false
       apply_authorized=$false
       enrollment_authorized=$false
       production_mutation_authorized=$false
    }
 }catch{
    if($null-ne$lease){$lease.Dispose()}
    throw
 }
}
