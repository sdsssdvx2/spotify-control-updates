# TARGETED acceptance only. Reuses existing v025/v027 vendor CLI evidence;
# invokes genuine original Addon Manager persistence BACKUP functions on a
# disposable RUNNER_TEMP fixture, not real Spotify profile or installation.
param([Parameter(Mandatory=$true)][string]$OriginalAddonPath)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
if([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
   $env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ENVIRONMENT -cne 'github-hosted'){
    throw 'V031_TARGETED_HOSTED_ONLY'
}
$env:TEMP=[IO.Path]::GetFullPath($env:RUNNER_TEMP)
$env:TMP=$env:TEMP
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
foreach($inc in @('validation/v0.6.21/addon_policy_registry.ps1.inc',
                  'validation/v0.6.22/addon_source_adapter_engine.ps1.inc')){
    . ([ScriptBlock]::Create([IO.File]::ReadAllText((Join-Path $root $inc),[Text.Encoding]::UTF8)))
}
foreach($file in @(
   'validation/marketplace-source-topology-v0.1.0/marketplace-source-topology.ps1',
   'validation/custom-app-remote-source-contract-v0.1.0/custom-app-remote-source-contract.ps1',
   'validation/custom-app-local-runtime-baseline-v0.1.0/custom-app-local-runtime-baseline.ps1',
   'validation/custom-app-remote-observation-collector-v0.1.0/custom-app-remote-observer.ps1',
   'validation/custom-app-stage-acquisition-contract-v0.1.0/custom-app-stage-acquisition.ps1',
   'validation/custom-app-production-permit-v0.1.0/custom-app-production-permit.ps1',
   'validation/custom-app-update-transaction-protocol-v0.1.0/custom-app-update-transaction.ps1',
   'validation/custom-app-production-atomic-live-swap-v0.1.0/custom-app-production-atomic-live-swap.ps1',
   'validation/custom-app-production-crash-recovery-journal-v0.1.0/custom-app-production-crash-recovery-journal.ps1',
   'validation/custom-app-production-pre-apply-preparation-v0.1.0/custom-app-production-pre-apply-preparation.ps1',
   'validation/approved-custom-app-native-scope/approved-scoped-native.ps1',
   'validation/approved-live-source-acquisition/approved-live-source-acquisition.ps1',
   'validation/approved-live-hmac-consumed-stage/approved-live-hmac-stage.ps1',
   'validation/approved-hmac-to-prepared-central-journal/approved-prepared-journal.ps1',
   'validation/approved-real-persistence-adapter/real-addon-persistence-core.ps1',
   'validation/approved-real-persistence-adapter/approved-real-persistence-journal.ps1'
)){
    . (Join-Path $root $file)
}
$script:Version='0.6.5-r17'
. (Get-ExactAddonPersistenceFunctionsV031 -OriginalAddonPath $OriginalAddonPath)
function Assert-V031([bool]$Okay,[string]$What){
    if(-not$Okay){throw ('V031_REAL_ADDON_PERSISTENCE_TARGETED_FAILED: '+$What)}
}
$item=[pscustomobject]@{
  name='better-local-files';kind='custom-app';policy='auto'
  source='Pithaya/spicetify-apps-dist';installed=$true
}
$acquired=Invoke-ApprovedLiveSourceAcquireV028 -Item $item
Assert-V031 ([bool]$acquired.ok) 'genuine live GitHub source not acquired'
$parent=Join-Path $env:RUNNER_TEMP ('v031-real-addon-'+[Guid]::NewGuid().ToString('N'))
$work=Join-Path $parent 'v031-fixture'
$live=Join-Path (Join-Path $work 'CustomApps') $item.name
$local=Join-Path $work 'ProtectedSpotify\Local'
$roaming=Join-Path $work 'ProtectedSpotify\Roaming'
foreach($p in @((Join-Path $work 'CustomApps'),$local,$roaming)){
    [IO.Directory]::CreateDirectory($p)|Out-Null
}
$definitions=@(Get-SpotifyPersistenceSurfaceDefinitions -LocalAppDataRoot $local -AppDataRoot $roaming)
Assert-V031 ($definitions.Count -ge 4) 'actual original Addon Manager inventory not imported'
$count=0
foreach($surface in $definitions){
    $full=Assert-CustomAppProductionCrashJournalPathV010 -AllowedRoot $env:RUNNER_TEMP -Path ([string]$surface.path)
    if([string]$surface.kind -ceq 'Directory'){
        [IO.Directory]::CreateDirectory($full)|Out-Null
        $testFile=Join-Path $full ('v031-protected-'+$count+'.dat')
    }else{
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($full))|Out-Null
        $testFile=$full
    }
    [IO.File]::WriteAllText($testFile,('V031_SENSITIVE_SPOTIFY_FIXTURE_ONLY_'+$count),[Text.UTF8Encoding]::new($false))
    $count++
}
$actualDef=Assert-RealAddonPersistenceRootsV031 -RunnerRoot $env:RUNNER_TEMP -LocalRoot $local -RoamingRoot $roaming
Assert-V031 (@($actualDef).Count -eq $definitions.Count) 'real surface inventory changed after independent source path checking'
$before=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot $local -AppDataRoot $roaming
Assert-V031 ([string]$before.fingerprint -cmatch '^[0-9a-f]{64}$' -and
    [int]$before.surface_count -eq $definitions.Count) 'actual real original snapshot invalid'
$base=Copy-CustomAppAtomicTreeV010 -Source ([string]$acquired.stage_path) -Destination $live
[IO.File]::AppendAllText((Join-Path $live 'index.js'),'/*V031_PREVIOUS_INSTALLED_APP_CODE*/')
$old=Get-CustomAppLocalRuntimeBaseline -Name ([string]$item.name) -AppPath $live
Assert-V031 ([bool]$old.installable -and [string]$old.tree_sha256 -cne [string]$acquired.runtime_tree_sha256) 'live app simulated old revision not valid'
$state=Join-Path $parent 'spent-hmac-tokens'
[IO.Directory]::CreateDirectory($state)|Out-Null
$key=New-Object byte[] 32
$bytes=New-Object byte[] 16
$rng=[Security.Cryptography.RandomNumberGenerator]::Create()
try{$rng.GetBytes($key);$rng.GetBytes($bytes)}finally{$rng.Dispose()}
$nonce=([BitConverter]::ToString($bytes)).Replace('-','').ToLowerInvariant()
try{
   $permit=New-ApprovedLiveHmacStagePermitV029 -Item $item -Acquired $acquired -SessionKey $key -Nonce $nonce
   $spent=Consume-ApprovedLiveHmacStageOnceV029 -Item $item -Acquired $acquired -Permit $permit -SessionKey $key -ReceiptStore $state
   Assert-V031 ([bool]$spent.ok -and [bool]$spent.single_use_consumed) 'true HMAC not consumed'
   $joined=Invoke-ApprovedRealPersistPreparedV031 -Item $item -Acquired $acquired -Permit $permit -SessionKey $key -ReceiptStore $state -WorkRoot $work
   Assert-V031 ([bool]$joined.ok -and
      [string]$joined.central_phase -ceq 'prepared' -and
      [int]$joined.central_revision -eq 0 -and
      [bool]$joined.exact_original_addon_core_used -and
      [int]$joined.protected_surface_count -eq $definitions.Count -and
      -not[bool]$joined.all_possible_spotify_data_covered -and
      -not[bool]$joined.production_mutation_authorized) 'real original guarded backup not enrolled in central CAS'
   $child=Join-Path $PSScriptRoot 'read-original-persistence-fresh-process.ps1'
   & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $child -WorkRoot $work -Name ([string]$item.name) -TokenId ([string]$permit.token_id) -ReceiptStore $state -TransactionId ([string]$joined.transaction_id) -OriginalAddonPath $OriginalAddonPath
   Assert-V031 ($LASTEXITCODE -eq 0) 'fresh process did not verify original actual guarded backup'
   Write-Host ('V031_REAL_GENERATED_ADDON_PERSISTENCE_SURFACES_GUARDED_BACKUP_PREPARED_PASS count='+$definitions.Count)
   $check=Read-ApprovedRealPersistPreparedV031 -WorkRoot $work -Name ([string]$item.name) -TokenId ([string]$permit.token_id) -ReceiptStore $state -TransactionId ([string]$joined.transaction_id)
   Assert-V031 ([bool]$check.ok) 'pre-modification prepared CAS missing'
   $manifest=Get-Content -LiteralPath (Join-Path ([string]$joined.backup_path) 'guard-manifest.json') -Raw|ConvertFrom-Json
   $existing=@($manifest.before.surfaces|Where-Object{[bool]$_.exists})
   Assert-V031 ($existing.Count -ge 2) 'real Addon Manager did not capture multi-surface persistence'
   $chosen=$existing[0]
   $copy=Join-Path (Join-Path ([string]$joined.backup_path) 'surfaces') ([string]$chosen.id)
   $tamperPath=if([string]$chosen.kind -ceq 'Directory'){
        (Get-ChildItem -LiteralPath $copy -Recurse -File -Force | Select-Object -First 1).FullName
   }else{$copy}
   Assert-V031 ([IO.File]::Exists($tamperPath)) 'no byte-real protected backup object'
   $txn=Join-Path (Join-Path $work 'transactions') ([string]$permit.token_id)
   $p=Get-ApprovedRealPersistJournalPathsV031 -WorkRoot $work -Name ([string]$item.name) -TokenId ([string]$permit.token_id)
   $proof=Get-ApprovedPreparedSealedPathV030 -Paths $p -TransactionId ([string]$joined.transaction_id)
   $vulnerables=@($tamperPath,([string]$definitions[0].path))
   if([string]$definitions[0].kind -ceq 'Directory'){
       $vulnerables[1]=(Get-ChildItem -LiteralPath ([string]$definitions[0].path) -Recurse -File -Force|Select-Object -First 1).FullName
   }
   $vulnerables+=@( (Join-Path ([string]$p.app_backup) 'index.js'),([string]$acquired.archive_path),(Join-Path ([string]$acquired.stage_path) 'index.js'))
   foreach($path in $vulnerables){
       $saved=[IO.File]::ReadAllBytes($path)
       try{
           [IO.File]::AppendAllText($path,'V031_UNAUTHORIZED_AFTER_PREPARE')
           $denied=Read-ApprovedRealPersistPreparedV031 -WorkRoot $work -Name ([string]$item.name) -TokenId ([string]$permit.token_id) -ReceiptStore $state -TransactionId ([string]$joined.transaction_id)
           Assert-V031 (-not[bool]$denied.ok) ('tampered original/backup ZIP or stage accepted: '+[IO.Path]::GetFileName($path))
       }finally{[IO.File]::WriteAllBytes($path,$saved)}
   }
   $proofBytes=[IO.File]::ReadAllBytes($proof)
   try{
       $altered=New-Object byte[] $proofBytes.Length
       [Array]::Copy($proofBytes,$altered,$proofBytes.Length)
       $altered[2]=$altered[2] -bxor 1
       [IO.File]::WriteAllBytes($proof,$altered)
       $denied=Read-ApprovedRealPersistPreparedV031 -WorkRoot $work -Name ([string]$item.name) -TokenId ([string]$permit.token_id) -ReceiptStore $state -TransactionId ([string]$joined.transaction_id)
       Assert-V031 (-not[bool]$denied.ok) 'altered DPAPI evidence accepted'
   }finally{[IO.File]::WriteAllBytes($proof,$proofBytes)}
   $dup=$false
   try{[void](Invoke-ApprovedRealPersistPreparedV031 -Item $item -Acquired $acquired -Permit $permit -SessionKey $key -ReceiptStore $state -WorkRoot $work)}
   catch{$dup=$true}
   Assert-V031 $dup 'duplicate central transaction was allowed'
   $valid=Read-ApprovedRealPersistPreparedV031 -WorkRoot $work -Name ([string]$item.name) -TokenId ([string]$permit.token_id) -ReceiptStore $state -TransactionId ([string]$joined.transaction_id)
   Assert-V031 ([bool]$valid.ok) 'negative tests destroyed original prepared state'
   Write-Host 'V031_REAL_SPOTIFY_GUARD_MANIFEST_BACKUP_STAGE_APP_DPAPI_TAMPER_AND_REPLAY_DENIED_PASS'
   Write-Host 'V031_REAL_ADDON_PERSISTENCE_FUNCTIONS_WITH_ACTUAL_RELEASE_HMAC_CENTRAL_PREPARED_PASS'
   Write-Host 'V031_HOLD_ORIGINAL_ADDON_EXACT_SNAPSHOT_ONLY_NO_USER_SPOTIFY_NATIVE_APPLY_OR_MUTATION_PASS'
}finally{
   [Array]::Clear($key,0,$key.Length)
}
