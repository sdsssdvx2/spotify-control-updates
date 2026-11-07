# Exact Windows synthetic multi-app profile, legacy-state and new DPAPI
# enrollment cutover NO-WRITE acceptance. Uses the real V041/V042 source
# resolution and XPUI tree proof; never runs CLI or starts Spotify.
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if($env:GITHUB_ACTIONS -cne 'true' -or
   $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   [string]::IsNullOrWhiteSpace($env:RUNNER_TEMP)){
 throw 'V046_TARGETED_TEST_ONLY_GITHUB_HOSTED_WINDOWS'
}
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $repo 'validation/custom-app-update-transaction-protocol-v0.1.0/custom-app-update-transaction.ps1')
. (Join-Path $repo 'validation/approved-installed-xpui-readonly/installed-xpui-readonly.ps1')
. (Join-Path $repo 'validation/approved-installed-xpui-readonly/actual-custom-app-origins-v041.ps1')
. (Join-Path $repo 'validation/approved-installed-xpui-readonly/verified-source-xpui-binding-v042.ps1')
. (Join-Path $PSScriptRoot 'cutover-admission-v046.ps1')
function Assert-V046Test([bool]$ok,[string]$label){if(-not$ok){throw ('V046_TEST_'+$label)}}
function Must-BlockV046([scriptblock]$body,[string]$reason){
 $r=& $body
 if([string]$r.status -cne 'blocked' -or [string]$r.reason -cne $reason){
   Write-Host ('V046_HOSTED_DENIAL_DIAG=status:'+([string]$r.status)+
     ';reason:'+([string]$r.reason)+
     ';expected:'+$reason+
     ';safe-fields:'+([string](-not[bool]$r.production_mutation_authorized)))
 }
 Assert-V046Test ([string]$r.status -ceq 'blocked' -and
  [string]$r.reason -ceq $reason -and
  -not[bool]$r.production_mutation_authorized -and
  -not[bool]$r.production_enrollment_authorized -and
  -not[bool]$r.live_execution_authorized) ('DID_NOT_BLOCK_'+$reason)
}
$root=Join-Path $env:RUNNER_TEMP ('v046-test-layout-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
$local=Join-Path $root 'Local'
$legacy=Join-Path $local 'SpotifyControl'
$state=Join-Path $legacy 'addons-state.json'
$pending=Join-Path $legacy 'addon-last-transaction.json'
$enrollment=Join-Path $local 'SpotifyControlUpdates-CustomApp-State'
$roaming=Join-Path $root 'Roaming'
$configRoot=Join-Path $roaming 'spicetify'
$config=Join-Path $configRoot 'config-xpui.ini'
$spotify=Join-Path $root 'FakeSpotify'
$xpui=Join-Path $spotify 'Apps\xpui'
$prefs=Join-Path $roaming 'Spotify\prefs'
$cli=Join-Path $root 'VendorCLI\spicetify.exe'
$cliApps=Join-Path $root 'VendorCLI\CustomApps'
$names=@('ivlyrics','better-local-files','eternal-jukebox','unmanaged-app')
foreach($dir in @($legacy,$configRoot,$xpui,(Split-Path -Parent $prefs),
 (Split-Path -Parent $cli))){
 [IO.Directory]::CreateDirectory($dir)|Out-Null
}
[IO.File]::WriteAllText($state,'{"version":1,"original-legacy":"V046-only"}')
[IO.File]::WriteAllText($cli,'V046_SYNTHETIC_NONEXECUTABLE_CLI')
[IO.File]::WriteAllText($prefs,'V046_USER_PREFS_DO_NOT_OPEN')
[IO.File]::WriteAllText((Join-Path $xpui 'foreign-original.dat'),'V046_UNMANAGED_XPUI_DO_NOT_CHANGE')
foreach($name in $names){
 $dir=Join-Path $cliApps $name
 [IO.Directory]::CreateDirectory($dir)|Out-Null
 [IO.File]::WriteAllText((Join-Path $dir 'index.js'),('V046_JS_'+$name))
 [IO.File]::WriteAllText((Join-Path $dir 'manifest.json'),('{"name":"'+$name+'"}'))
}
$ini=('[Setting]'+[Environment]::NewLine+'spotify_path = '+$spotify+
 [Environment]::NewLine+'prefs_path = '+$prefs+
 [Environment]::NewLine+'[AdditionalOptions]'+[Environment]::NewLine+
 'custom_apps = '+($names -join '|')+[Environment]::NewLine)
[IO.File]::WriteAllText($config,$ini,[Text.UTF8Encoding]::new($false))
$fixtureArgs=@{HostedFixtureRoot=$root;HostedFixtureCliPath=$cli}
$legacyStart=(Get-FileHash $state -Algorithm SHA256).Hash
$unknown=Join-Path $cliApps 'unmanaged-app\index.js'
$unknownStart=(Get-FileHash $unknown -Algorithm SHA256).Hash
$foreign=Join-Path $xpui 'foreign-original.dat'
$foreignStart=(Get-FileHash $foreign -Algorithm SHA256).Hash
$profile=Get-CustomAppCutoverReadOnlyAdmissionV046 @fixtureArgs
Assert-V046Test ($profile.status -ceq 'observed-readonly' -and
 $profile.reason -ceq 'V046_CANDIDATE_ELIGIBLE_FOR_FUTURE_ISOLATED_PREPARATION_ONLY' -and
 $profile.profile_sha256 -cmatch '^[a-f0-9]{64}$' -and
 $profile.full_xpui_snapshot_sha256 -cmatch '^[a-f0-9]{64}$' -and
 $profile.approved_configured_apps -eq 3 -and
 $profile.unmanaged_configured_apps -eq 1 -and
 $profile.legacy_transaction_absent -and $profile.new_dpapi_engine_unenrolled -and
 -not$profile.production_mutation_authorized -and
 -not$profile.production_enrollment_authorized -and
 -not$profile.actual_backup_created -and
 -not$profile.rollback_snapshot_durable -and
 $profile.explicit_owner_rollout_approval_required -and
 -not$profile.full_quiescence_proven -and
 -not$profile.process_lease_held) 'VALID_4_APP_CUTOVER_NOT_NONAUTHORIZING'
$pin=[string]$profile.profile_sha256
$again=Test-CustomAppCutoverReadOnlyAdmissionV046 -ExpectedProfileSha256 $pin @fixtureArgs
Assert-V046Test ([bool]$again.ok -and -not$again.production_mutation_authorized) 'SAME_READONLY_ADMISSION_NOT_STABLE'
$json=$profile|ConvertTo-Json -Compress
foreach($leak in @($root,'unmanaged-app','better-local-files','ivlyrics','V046_USER_PREFS','V046_UNMANAGED')){
 Assert-V046Test (-not$json.Contains($leak)) 'PRIVATE_PATH_OR_USER_APP_SOURCE_EXPOSED'
}
Write-Host 'V046_FOUR_APP_READONLY_LEGACY_TO_NEW_ADMISSION_IDENTITY_PASS'
[IO.File]::WriteAllText($pending,'{"status":"awaiting-apply"}')
Must-BlockV046 {Get-CustomAppCutoverReadOnlyAdmissionV046 @fixtureArgs} 'V046_LEGACY_TRANSACTION_STILL_PRESENT_DO_NOT_MIGRATE'
Assert-V046Test ([IO.File]::Exists($pending)) 'PENDING_OLD_JOURNAL_DELETED_BY_CHECK'
[IO.File]::Delete($pending) # Hosted synthetic fixture only
[IO.Directory]::CreateDirectory($enrollment)|Out-Null
Must-BlockV046 {Get-CustomAppCutoverReadOnlyAdmissionV046 @fixtureArgs} 'V046_NEW_ENGINE_ALREADY_ENROLLED_REQUIRE_EXISTING_JOURNAL_RECOVERY'
Assert-V046Test ([IO.Directory]::Exists($enrollment)) 'NEW_DPAPI_STORE_DELETED'
[IO.Directory]::Delete($enrollment) # empty hosted fixture marker
[IO.File]::WriteAllText($enrollment,'malformed-new-ledger')
Must-BlockV046 {Get-CustomAppCutoverReadOnlyAdmissionV046 @fixtureArgs} 'V046_NEW_ENGINE_ALREADY_ENROLLED_REQUIRE_EXISTING_JOURNAL_RECOVERY'
Assert-V046Test ([IO.File]::Exists($enrollment)) 'MALFORMED_NEW_LEDGER_REMOVED'
[IO.File]::Delete($enrollment)
Write-Host 'V046_ACTIVE_LEGACY_JOURNAL_AND_ANY_NEW_ENROLLMENT_BLOCKED_PASS'
$simulated=Get-CustomAppCutoverReadOnlyAdmissionV046 -SimulatedSpotifyRunning @fixtureArgs
Assert-V046Test ($simulated.status -ceq 'deferred' -and
 $simulated.reason -ceq 'V046_SPOTIFY_RUNNING_OPERATION_DEFERRED' -and
 $simulated.profile_sha256 -ceq $pin -and
 -not$simulated.production_mutation_authorized) 'RUNNING_SPOTIFY_SHOULD_DEFER_NOT_CREATE_LEDGER'
Assert-V046Test (-not[bool](Test-CustomAppCutoverReadOnlyAdmissionV046 -ExpectedProfileSha256 $pin @fixtureArgs).production_mutation_authorized) 'CANDIDATE_READBACK_GRANTED_MUTATION'
Write-Host 'V046_RUNNING_SPOTIFY_DEFERRED_NO_PROCESS_TERMINATION_PASS'
# Real installed source and XPUI drift are both rejected on next admission.
$original=[IO.File]::ReadAllBytes((Join-Path $cliApps 'ivlyrics\index.js'))
[IO.File]::AppendAllText((Join-Path $cliApps 'ivlyrics\index.js'),'CHANGED')
Assert-V046Test (-not[bool](Test-CustomAppCutoverReadOnlyAdmissionV046 -ExpectedProfileSha256 $pin @fixtureArgs).ok) 'APP_TREE_DRIFT_NOT_DETECTED'
[IO.File]::WriteAllBytes((Join-Path $cliApps 'ivlyrics\index.js'),$original)
$foreignOriginal=[IO.File]::ReadAllBytes($foreign)
[IO.File]::AppendAllText($foreign,'CHANGED')
Assert-V046Test (-not[bool](Test-CustomAppCutoverReadOnlyAdmissionV046 -ExpectedProfileSha256 $pin @fixtureArgs).ok) 'FOREIGN_XPUI_DRIFT_NOT_DETECTED'
[IO.File]::WriteAllBytes($foreign,$foreignOriginal)
$oldState=[IO.File]::ReadAllBytes($state)
[IO.File]::AppendAllText($state,' ')
Assert-V046Test (-not[bool](Test-CustomAppCutoverReadOnlyAdmissionV046 -ExpectedProfileSha256 $pin @fixtureArgs).ok) 'LEGACY_STATE_DRIFT_NOT_DETECTED'
[IO.File]::WriteAllBytes($state,$oldState)
Assert-V046Test ([bool](Test-CustomAppCutoverReadOnlyAdmissionV046 -ExpectedProfileSha256 $pin @fixtureArgs).ok) 'READONLY_STABLE_REPLAY_AFTER_FIXTURE_RESTORE'
Write-Host 'V046_APPROVED_SOURCE_FOREIGN_XPUI_LEGACY_STATE_CHANGES_DENIED_PASS'
# No binary execution, no credentials/prefs body opened, no enrollment or
# old transaction writes in the subject code. The fixture itself is disposable.
Assert-V046Test ((Get-FileHash $state -Algorithm SHA256).Hash -ceq $legacyStart -and
 (Get-FileHash $unknown -Algorithm SHA256).Hash -ceq $unknownStart -and
 (Get-FileHash $foreign -Algorithm SHA256).Hash -ceq $foreignStart -and
 -not(Test-Path $pending) -and -not(Test-Path $enrollment)) 'USER_SURFACES_MODIFIED_OR_ENROLLED'
Write-Host 'V046_NO_REAL_SPOTIFY_NO_LEDGER_NO_NETWORK_NO_USER_PRIVACY_EXPOSURE_PASS'
