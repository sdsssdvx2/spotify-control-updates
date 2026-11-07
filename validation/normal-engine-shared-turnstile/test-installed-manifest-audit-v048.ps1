# V048 focused hosted actual-layout manifest inspection under V047 OS lease.
# Reuse previously-qualified V046 synthetic fixture and negative tests;
# do not reconstruct existing Addon Manager or launch official CLI again.
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
 throw 'V048_MANIFEST_AUDIT_TEST_GITHUB_HOSTED_WINDOWS_ONLY'
}
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $repo 'validation/normal-engine-cutover-readonly/test-cutover-admission-v046.ps1')
. (Join-Path $PSScriptRoot 'engine-turnstile-v047.ps1')
. (Join-Path $PSScriptRoot 'locked-cutover-admission-v047.ps1')
. (Join-Path $repo 'validation/approved-native-manifest-scope/manifest-owned-xpui-v044.ps1')
. (Join-Path $PSScriptRoot 'installed-manifest-audit-v048.ps1')
function Assert-V048([bool]$ok,[string]$why){if(-not$ok){throw ('V048_TEST_'+$why)}}
$iv=Join-Path $cliApps 'ivlyrics'
[IO.Directory]::CreateDirectory((Join-Path $iv 'extensions'))|Out-Null
foreach($name in @('a.js','b.js','c.js')){
 [IO.File]::WriteAllText((Join-Path $iv ('extensions\'+$name)),'const '+$name.Replace('.','_')+'=true;')
}
[IO.File]::WriteAllText((Join-Path $iv 'manifest.json'),
 '{"name":"ivlyrics","subfiles_extension":["extensions/a.js","extensions/b.js","extensions/c.js"]}',
 [Text.UTF8Encoding]::new($false))
$better=Join-Path $cliApps 'better-local-files'
[IO.File]::WriteAllText((Join-Path $better 'extension.js'),'const owned=true;')
[IO.Directory]::CreateDirectory((Join-Path $better 'assets\images'))|Out-Null
[IO.File]::WriteAllText((Join-Path $better 'assets\images\cover.svg'),'<svg/>')
[IO.File]::WriteAllText((Join-Path $better 'manifest.json'),
 '{"name":"better-local-files","subfiles_extension":["extension.js"],"assets":["assets/images/cover.svg"]}',
 [Text.UTF8Encoding]::new($false))
$fixtureArgs=@{HostedFixtureRoot=$root;HostedFixtureCliPath=$cli}
$baseAdmission=Get-CustomAppCutoverReadOnlyAdmissionV046 @fixtureArgs
Assert-V048 ($baseAdmission.status -ceq 'observed-readonly' -and
 [string]$baseAdmission.profile_sha256 -cmatch '^[a-f0-9]{64}$') 'MULTI_MANIFEST_CUTOVER_NOT_ADMITTED'
$expected=[string]$baseAdmission.profile_sha256
$unknownOriginal=(Get-FileHash $unknown -Algorithm SHA256).Hash
$foreignOriginal=(Get-FileHash $foreign -Algorithm SHA256).Hash
$stateOriginal=(Get-FileHash $state -Algorithm SHA256).Hash
$lease=Open-CustomAppCutoverReadOnlyLeaseV047 -ExpectedProfileSha256 $expected @fixtureArgs
try{
 $audit=Get-CustomAppInstalledManifestAuditV048 -CutoverLease $lease -ExpectedProfileSha256 $expected @fixtureArgs
 Assert-V048 ($audit.status -ceq 'observed-readonly' -and
   [int]$audit.approved_manifest_count -eq 3 -and
   [int]$audit.unmanaged_configured_apps -eq 1 -and
   [int]$audit.owned_output_files -eq 14 -and
   [int]$audit.declared_extensions -eq 4 -and
   [int]$audit.declared_asset_files -eq 1 -and
   [string]$audit.manifest_footprint_sha256 -cmatch '^[a-f0-9]{64}$' -and
   [bool]$audit.os_turnstile_held_during_audit -and
   [bool]$audit.unmanaged_app_source_not_inspected -and
   -not[bool]$audit.release_provenance_verified -and
   -not[bool]$audit.actual_backup_created -and
   -not[bool]$audit.production_mutation_authorized -and
   -not[bool]$audit.production_enrollment_authorized) ('V048_THREE_APP_MANIFEST_SCOPE_NOT_QUALIFIED_'+[string]$audit.reason)
 $json=$audit|ConvertTo-Json -Compress
 foreach($secret in @($root,'better-local-files','ivlyrics','unmanaged-app','V046_USER_PREFS')){
    Assert-V048 (-not$json.Contains($secret)) 'MANIFEST_AUDIT_EXPOSED_PRIVATE_APP_NAME_OR_PATH'
 }
 $again=Get-CustomAppInstalledManifestAuditV048 -CutoverLease $lease -ExpectedProfileSha256 $expected @fixtureArgs
 Assert-V048 ($again.status -ceq 'observed-readonly' -and
  $again.manifest_footprint_sha256 -ceq $audit.manifest_footprint_sha256) 'FRESH_MANIFEST_AGGREGATE_NOT_STABLE'
 Write-Host 'V048_REAL_LAYOUT_THREE_APPROVED_MANIFESTS_FOUR_EXTENSIONS_ASSET_BOUND_PASS'
 # The fourth configured app is not inspected, modified or managed.
 [IO.File]::AppendAllText($unknown,'UNMANAGED_SOURCE_CHANGE_ALLOWED')
 $other=Get-CustomAppInstalledManifestAuditV048 -CutoverLease $lease -ExpectedProfileSha256 $expected @fixtureArgs
 Assert-V048 ($other.status -ceq 'observed-readonly' -and
  $other.manifest_footprint_sha256 -ceq $audit.manifest_footprint_sha256) 'UNMANAGED_SOURCE_WAS_WRONGLY_INCLUDED'
 [IO.File]::WriteAllText($unknown,'V046_JS_unmanaged-app')
 Assert-V048 ((Get-FileHash $unknown -Algorithm SHA256).Hash -ceq $unknownOriginal) 'FIXTURE_UNMANAGED_CONTENT_RESTORE_FAILED'
 Write-Host 'V048_UNMANAGED_CONFIGURED_APP_IGNORED_AND_FOREIGN_XPUI_BOUND_PASS'
 # Existing last-transaction creates a NO-GO result while lease is held;
 # does not create a second engine state.
 [IO.File]::WriteAllText($pending,'{"status":"awaiting-apply"}')
 $blocked=Get-CustomAppInstalledManifestAuditV048 -CutoverLease $lease -ExpectedProfileSha256 $expected @fixtureArgs
 Assert-V048 ($blocked.status -ceq 'blocked' -and
   $blocked.reason -ceq 'V048_PROFILE_OR_LEGACY_STATE_CHANGED_BEFORE_MANIFEST_AUDIT' -and
   -not$blocked.production_mutation_authorized) 'PENDING_LEGACY_TRANSACTION_NOT_REFUSED'
 Assert-V048 ([IO.File]::Exists($pending)) 'PENDING_LEGACY_TRANSACTION_DELETED'
 [IO.File]::Delete($pending)
 # Direct V044 installed-readonly manifest parser must reject unsafe source
 # declarations; actual audit must also reject modified source binding.
 $manifest=Join-Path $iv 'manifest.json'
 $bytes=[IO.File]::ReadAllBytes($manifest)
 [IO.File]::WriteAllText($manifest,'{"subfiles_extension":["../secrets.js"]}')
 $bad=$false
 try{[void](Get-ApprovedNativeManifestOwnedScopeV044 -Name 'ivlyrics' -SourceAppPath $iv -InstalledReadOnlyAudit)}
 catch{if([string]$_.Exception.Message -ceq 'V044_MANIFEST_UNSAFE_RELATIVE_SOURCE'){$bad=$true}else{throw}}
 Assert-V048 $bad 'REAL_READONLY_MANIFEST_PARSER_ALLOWED_TRAVERSAL'
 $blocked=Get-CustomAppInstalledManifestAuditV048 -CutoverLease $lease -ExpectedProfileSha256 $expected @fixtureArgs
 Assert-V048 ($blocked.status -ceq 'blocked' -and -not$blocked.production_enrollment_authorized) 'MUTATED_APPROVED_SOURCE_ACCEPTED'
 [IO.File]::WriteAllBytes($manifest,$bytes)
 $recovered=Get-CustomAppInstalledManifestAuditV048 -CutoverLease $lease -ExpectedProfileSha256 $expected @fixtureArgs
 Assert-V048 ($recovered.status -ceq 'observed-readonly' -and
    $recovered.manifest_footprint_sha256 -ceq $audit.manifest_footprint_sha256) 'ORIGINAL_MANIFEST_NOT_STABLE_AFTER_RESTORE'
 Write-Host 'V048_PENDING_LEGACY_JOURNAL_SOURCE_TRAVERSAL_AND_RACE_DENIED_PASS'
}finally{
 if($null-ne$lease.lock_handle){$lease.lock_handle.Dispose()}
}
$closed=Get-CustomAppInstalledManifestAuditV048 -CutoverLease $lease -ExpectedProfileSha256 $expected @fixtureArgs
Assert-V048 ($closed.status -ceq 'blocked' -and
 $closed.reason -ceq 'V048_OS_TURNSTILE_HANDLE_NOT_LIVE_OR_WRONG_PROFILE') 'DISPOSED_LOCK_WAS_ACCEPTED'
Assert-V048 ((Get-FileHash $foreign -Algorithm SHA256).Hash -ceq $foreignOriginal -and
 (Get-FileHash $state -Algorithm SHA256).Hash -ceq $stateOriginal -and
 -not(Test-Path $pending) -and -not(Test-Path $enrollment)) 'SUBJECT_MUTATED_USER_STATE'
Write-Host 'V048_CLOSED_ENGINE_LEASE_REFUSED_AND_NO_USER_STATE_WRITTEN_PASS'
Write-Host 'V048_REAL_PROFILE_MANIFEST_READONLY_ONLY_NO_CLI_NO_USER_SPOTIFY_PASS'
