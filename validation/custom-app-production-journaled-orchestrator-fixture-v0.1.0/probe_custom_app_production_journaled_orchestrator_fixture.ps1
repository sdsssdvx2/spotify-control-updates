param(
    [Parameter(Mandatory=$true)][string]$JournalCore,
    [Parameter(Mandatory=$true)][string]$OrchestratorCore,
    [Parameter(Mandatory=$true)][string]$AllowedRoot,
    [Parameter(Mandatory=$true)][string]$StoreDirectory,
    [Parameter(Mandatory=$true)][string]$ExpectedTransactionId,
    [Parameter(Mandatory=$true)][string]$ExpectedPhase,
    [Parameter(Mandatory=$true)][string]$ExpectedClassification
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
. $JournalCore
. $OrchestratorCore
$r=Get-CustomAppProductionJournaledFixtureRecoveryV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory -ExpectedTransactionId $ExpectedTransactionId
if(-not [bool]$r.ok){throw ('probe recovery denied: '+[string]$r.reason)}
if([string]$r.phase -cne $ExpectedPhase){throw "probe phase mismatch actual=$([string]$r.phase) expected=$ExpectedPhase"}
if([string]$r.classification -cne $ExpectedClassification){throw "probe classification mismatch actual=$([string]$r.classification) expected=$ExpectedClassification"}
foreach($f in @('orchestrator_is_authority','journal_is_authority','production_execution_authorized','production_mutation_authorized')){if([bool]$r.$f){throw "probe authority escaped through $f"}}
Write-Host ("CUSTOM_APP_PRODUCTION_JOURNALED_ORCHESTRATOR_FIXTURE_RESTART_PROBE_PASS phase={0} classification={1}" -f $r.phase,$r.classification)
