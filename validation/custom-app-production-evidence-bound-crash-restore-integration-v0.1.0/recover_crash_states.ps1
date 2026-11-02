param(
  [Parameter(Mandatory=$true)][string]$RecoveryRoot,
  [Parameter(Mandatory=$true)][string]$StatePath,
  [Parameter(Mandatory=$true)][string]$ResultPath
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
. (Join-Path $RecoveryRoot 'validation/custom-app-production-recovery-restore-executor-v0.1.0/test_custom_app_production_recovery_restore_executor.ps1')

$states=@(Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json)
if($states.Count -ne 2){throw 'recovery state count mismatch'}
$out=@()
foreach($s in $states){
  $env:SC_RX_COUNT=[string]$s.count_path
  $env:SC_RX_LIVE=Join-Path ([string]$s.live_path) 'index.js'
  $env:SC_RX_APPLIED=[string]$s.applied_path
  $env:SC_RX_MODE='success'
  try {
    $r=Invoke-CustomAppProductionRecoveryRestoreExecutorV010 -AllowedRoot ([string]$s.allowed_root) -StoreDirectory ([string]$s.store_directory) -ExpectedTransactionId ([string]$s.transaction_id) -LocalAppDataRoot ([string]$s.local_app_data_root) -AppDataRoot ([string]$s.app_data_root) -SpicetifyAllowedRoot ([string]$s.allowed_root) -SpicetifyPath $fakeExe -ExpectedSpicetifySha256 $fakeSha -TimeoutSeconds 15
    if($null -eq $r -or -not [bool]$r.ok){throw "$([string]$s.label) executor denied: $([string]$r.reason)"}
    $ck=Test-CustomAppProductionRecoveryRestoreExecutorResultV010 -Result $r.result
    if(-not [bool]$ck.ok){throw "$([string]$s.label) result invalid: $([string]$ck.reason)"}
    $journal=Read-CustomAppProductionCrashJournalV010 -AllowedRoot ([string]$s.allowed_root) -StoreDirectory ([string]$s.store_directory)
    if(-not [bool]$journal.ok -or [string]$journal.entry.phase -cne 'rollback-complete'){throw "$([string]$s.label) final journal mismatch"}
    $app=Get-CustomAppUpdateTreeSnapshotV010 -Root ([string]$s.live_path)
    if([string]$app.tree_sha256 -cne [string]$s.expected_old_app_tree_sha256){throw "$([string]$s.label) old app restore mismatch"}
    $persist=Get-SpotifyPersistenceSnapshot -LocalAppDataRoot ([string]$s.local_app_data_root) -AppDataRoot ([string]$s.app_data_root)
    if([string]$persist.fingerprint -cne [string]$s.expected_persistence_fingerprint){throw "$([string]$s.label) persistence restore mismatch"}
    $evidence=Read-CustomAppProductionRecoveryEvidenceV010 -AllowedRoot ([string]$s.allowed_root) -StoreDirectory ([string]$s.store_directory) -ExpectedTransactionId ([string]$s.transaction_id)
    if(-not [bool]$evidence.ok -or [string]$evidence.evidence_fingerprint -cne [string]$s.expected_evidence_fingerprint){throw "$([string]$s.label) evidence continuity mismatch"}
    if(-not (Test-Path -LiteralPath ([string]$s.count_path) -PathType Leaf)){throw "$([string]$s.label) apply count missing"}
    $count=[int]([IO.File]::ReadAllText([string]$s.count_path).Trim())
    if($count -ne 1){throw "$([string]$s.label) apply count $count"}
    $out += [pscustomobject]@{label=[string]$s.label;started_phase=[string]$r.result.started_phase;final_phase=[string]$journal.entry.phase;transaction_id=[string]$journal.transaction_id;apply_count=$count;result_fingerprint=[string]$r.result.result_fingerprint;evidence_fingerprint=[string]$evidence.evidence_fingerprint;old_app_tree_sha256=[string]$app.tree_sha256;persistence_fingerprint=[string]$persist.fingerprint;production_mutation_authorized=[bool]$r.result.production_mutation_authorized}
  } finally {
    foreach($n in @('SC_RX_COUNT','SC_RX_LIVE','SC_RX_APPLIED','SC_RX_MODE')){[Environment]::SetEnvironmentVariable($n,$null,'Process')}
  }
}
$out | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $ResultPath -Encoding UTF8
Write-Output 'CUSTOM_APP_PRODUCTION_EVIDENCE_BOUND_CRASH_RESTORE_RECOVERY_PASS cases=2'