$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$base='validation/spotify-exit-immediate-maintenance-HOLD/'
$p=$base+'out/owner-postadoption-default-hold-R134/spotify-control.ps1'
$err=$null;$tok=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($p,[ref]$tok,[ref]$err)
if(@($err).Count -ne 0){throw 'R134_WINPS51_FULL_SOURCE_NOT_PARSEABLE'}
$names=@('Test-R134OwnerReconciledMutationHold','Start-SpicetifyCliTransaction',
         'Rollback-SpicetifyCliTransaction','Invoke-MaintenanceMutationPhase','Maintain')
$defs=@($ast.FindAll({param($node)
  $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
  $node.Name -cin $names
},$true))
if($defs.Count -ne $names.Count){throw 'R134_FIVE_PRODUCTION_FUNCTIONS_NOT_UNIQUE'}
. ([ScriptBlock]::Create((@($defs|ForEach-Object{$_.Extent.Text}) -join [Environment]::NewLine)))
$script:OwnerTxn=[pscustomobject]@{id='20261113-215000-aabbccdd';status='owner-reviewed-preimage'}
$script:VerifyOwnerEvidenceCount=0
$script:SideEffects=0
$script:FailEvidence=$false
function Get-SpicetifyTransaction{return $script:OwnerTxn}
function Assert-SpicetifyOwnerPreimageAdoption {
  param($Txn)
  $script:VerifyOwnerEvidenceCount++
  if($script:FailEvidence){throw 'R132_ADOPTION_EVIDENCE_SHA_INVALID'}
  return $true
}
function Test-SpotifyRunning{$script:SideEffects++;throw 'R134_NATIVE_NOT_ADMITTED'}
function Ensure-StateShape{param($State);return $State}
function Write-Log{param($Message,$Level)}
function Save-State{$script:SideEffects++;throw 'R134_STATE_WOULD_BE_WRITTEN'}
function Backup-Config{$script:SideEffects++;throw 'R134_CONFIG_WOULD_BE_MODIFIED'}
function Enter-SpotifyControlMutex{param($Purpose);return 'synthetic-exclusive-lease'}
function Exit-SpotifyControlMutex{param($Mutex)}
function Load-State{return [pscustomobject]@{agent_mutation_enabled=$true;pending_maintenance=$true}}
function Migrate-StateFromLog{param($State);$script:SideEffects++;throw 'R134_AGENT_STATE_WOULD_BE_MUTATED'}
$script:Spicetify='synthetic-present'
if((Test-R134OwnerReconciledMutationHold) -cne $true){
  throw 'R134_OWNER_ADOPTED_STATUS_NOT_RECOGNIZED'
}
$held=$false
try{[void](Start-SpicetifyCliTransaction)}catch{
  $held=$_.Exception.Message -ceq 'R134_OWNER_ADOPTION_NOT_UPGRADE_APPROVAL'
}
if(-not $held){throw 'R134_DIRECT_NEW_CLI_TRANSACTION_NOT_HELD'}
$held=$false
try{[void](Rollback-SpicetifyCliTransaction)}catch{
  $held=$_.Exception.Message -ceq 'R134_OWNER_ADOPTION_NOT_ROLLBACK_PERMISSION'
}
if(-not $held){throw 'R134_DIRECT_OLD_TRANSACTION_ROLLBACK_NOT_HELD'}
$s=[pscustomobject]@{pending_spicetify_upgrade=$true;agent_mutation_enabled=$true}
$m=Invoke-MaintenanceMutationPhase $s
if($null -eq $m -or $m -ne $s){throw 'R134_MUTATION_PHASE_NOT_HELD'}
Maintain -FromResidentAgent
if($script:SideEffects -ne 0 -or $script:VerifyOwnerEvidenceCount -lt 4){
  throw 'R134_MUTATION_ENTRY_NOT_PROVEN_DEFAULT_DENY'
}
Write-Host 'R134_DIRECT_CLI_START_ROLLBACK_AND_RESIDENT_MUTATION_DEFAULT_DENY=PASS'
Write-Host 'R134_POST_ADOPTION_EVIDENCE_VERIFIED_ON_EACH_ADMISSION=PASS'
$script:FailEvidence=$true
$deny=$false
try{[void](Test-R134OwnerReconciledMutationHold)}catch{
  $deny=$_.Exception.Message -ceq 'R132_ADOPTION_EVIDENCE_SHA_INVALID'
}
if(-not $deny){throw 'R134_TAMPERED_ADOPTION_EVIDENCE_ALLOWED'}
$script:FailEvidence=$false
$script:OwnerTxn=[pscustomobject]@{id='new-valid';status='committed'}
if((Test-R134OwnerReconciledMutationHold) -ne $false){
  throw 'R134_SETTLED_TRANSACTION_UNEXPECTED_HOLD'
}
Write-Host 'R134_TAMPERED_PROVENANCE_BLOCKED_AND_EXISTING_SETTLED_UNCHANGED=PASS'
Write-Host 'R134_REAL_USER_AND_NATIVE_SPICETIFY_CALLS=ZERO'
