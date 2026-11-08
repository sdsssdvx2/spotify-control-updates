# V058 disposable hosted scratch task only; independent PowerShell process.
# No production task name is accepted by the imported module.
param([Parameter(Mandatory=$true)][string]$JournalPath)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
. (Join-Path $PSScriptRoot 'scheduler-scratch-quiescence-v058.ps1')
$result=Restore-V058OwnedScratchFromJournal -JournalPath $JournalPath
if(-not[bool]$result.recovered_in_fresh_process -or
   -not[bool]$result.enabled_state_restored -or
   -not[bool]$result.scratch_task_deleted -or
   [bool]$result.production_mutation_authorized -or
   [bool]$result.user_task_mutation){
 throw 'V058_FRESH_RECOVERY_OUTPUT_NOT_SAFE'
}
Write-Host 'V058_SEPARATE_POWERSHELL_PROCESS_RESTORED_AND_REMOVED_ONLY_OWNED_SCRATCH_TASK_PASS'
