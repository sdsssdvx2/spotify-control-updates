param([Parameter(Mandatory=$true)][string]$StatePath)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$root=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
. (Join-Path $root 'validation/custom-app-production-evidence-bound-journal-atomic-v0.1.0/test_custom_app_production_evidence_bound_journal_atomic.ps1')

function New-IntegrationStateV010 {
  param($Fixture,[string]$Label,[string]$Nonce,[string]$Fault)
  $r=Invoke-EBFixtureV010 -Fixture $Fixture -Nonce $Nonce -Label $Label -Fault $Fault
  if($Fault -ceq 'none'){
    if(-not [bool]$r.ok){throw "$Label mutation denied: $([string]$r.reason)"}
  } else {
    if([bool]$r.ok){throw "$Label crash injection unexpectedly succeeded"}
  }
  if($Fault -ceq 'after-live-move-before-journal'){
    $ia=Get-EBInspectionArgsV010 $Fixture $Label
    $inspect=Resolve-CustomAppProductionJournalAwareAtomicStartingInspectionV010 @ia
    if(-not [bool]$inspect.ok -or [string]$inspect.receipt.state -cne 'first-rename-complete-unjournaled'){throw "$Label inspection mismatch"}
    $repair=Invoke-CustomAppProductionJournalAwareAtomicStartingRepairV010 @ia
    if(-not [bool]$repair.ok -or [string]$repair.phase -cne 'live-moved-to-old'){throw "$Label repair mismatch"}
  }
  $journal=Get-EBJournalV010 $Fixture $Label
  if(-not [bool]$journal.ok){throw "$Label journal unreadable"}
  $evidence=Get-EBEvidenceV010 $Fixture $Label ([string]$journal.transaction_id)
  if(-not [bool]$evidence.ok){throw "$Label evidence unreadable"}
  $p=$Fixture.prepared.result
  $control=Join-Path $env:RUNNER_TEMP ('crash-restore-'+$Label+'-'+[Guid]::NewGuid().ToString('N'))
  [IO.Directory]::CreateDirectory($control)|Out-Null
  return [pscustomobject]@{
    label=$Label
    initial_phase=[string]$journal.entry.phase
    allowed_root=(Get-EBTrustRootV010)
    store_directory=(Get-EBStoreV010 $Fixture $Label)
    transaction_id=[string]$journal.transaction_id
    local_app_data_root=[string]$Fixture.q.persistence.local
    app_data_root=[string]$Fixture.q.persistence.roaming
    live_path=[string]$Fixture.q.x.live
    expected_old_app_tree_sha256=[string]$p.app_backup_tree_sha256
    expected_persistence_fingerprint=[string]$p.persistence_fingerprint
    expected_evidence_fingerprint=[string]$evidence.evidence_fingerprint
    count_path=(Join-Path $control 'count.txt')
    applied_path=(Join-Path $control 'applied.txt')
  }
}

$a=New-AtomicFixtureV010 'crash-restore-live-moved' -Nonce '51515151515151515151515151515151'
$b=New-AtomicFixtureV010 'crash-restore-candidate-live' -Nonce '52525252525252525252525252525252'
$states=@(
  (New-IntegrationStateV010 -Fixture $a -Label 'live-moved-normalized' -Nonce 'abababababababababababababababab' -Fault 'after-live-move-before-journal'),
  (New-IntegrationStateV010 -Fixture $b -Label 'candidate-live-durable' -Nonce 'cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd' -Fault 'none')
)
if([string]$states[0].initial_phase -cne 'live-moved-to-old'){throw 'first durable phase mismatch'}
if([string]$states[1].initial_phase -cne 'candidate-live'){throw 'second durable phase mismatch'}
$states | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $StatePath -Encoding UTF8
Write-Output 'CUSTOM_APP_PRODUCTION_EVIDENCE_BOUND_CRASH_RESTORE_PREPARE_PASS cases=2'