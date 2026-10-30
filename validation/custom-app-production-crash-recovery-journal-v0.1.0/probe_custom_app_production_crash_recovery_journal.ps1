param(
    [Parameter(Mandatory=$true)][string]$CorePath,
    [Parameter(Mandatory=$true)][string]$AllowedRoot,
    [Parameter(Mandatory=$true)][string]$StoreDirectory,
    [Parameter(Mandatory=$true)][string]$ExpectedTransactionId,
    [Parameter(Mandatory=$true)][string]$OutPath
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
. $CorePath
$r=Read-CustomAppProductionCrashJournalV010 -AllowedRoot $AllowedRoot -StoreDirectory $StoreDirectory
if(-not [bool]$r.ok -or -not [bool]$r.reloaded_from_persistent_store){throw 'restart probe could not durably reload journal'}
$c=Resolve-CustomAppProductionCrashRecoveryClassificationV010 -StoreRead $r -ExpectedTransactionId $ExpectedTransactionId
if(-not [bool]$c.ok){throw ('restart probe classification denied: '+[string]$c.reason)}
if([bool]$c.journal_is_authority -or [bool]$c.production_execution_authorized -or [bool]$c.production_mutation_authorized){throw 'restart probe observed escaped authority'}
[ordered]@{schema=1;transaction_id=[string]$r.transaction_id;revision=[int64]$r.revision;phase=[string]$r.entry.phase;classification=[string]$c.classification;no_action=[bool]$c.no_action;housekeeping_only=[bool]$c.housekeeping_only;requires_recovery_executor=[bool]$c.requires_recovery_executor;reloaded_from_persistent_store=[bool]$r.reloaded_from_persistent_store;journal_is_authority=$false;production_execution_authorized=$false;production_mutation_authorized=$false}|ConvertTo-Json -Compress|Set-Content -LiteralPath $OutPath -Encoding UTF8
