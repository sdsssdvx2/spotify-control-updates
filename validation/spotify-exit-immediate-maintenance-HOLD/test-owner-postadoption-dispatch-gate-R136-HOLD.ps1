$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
$path='validation/spotify-exit-immediate-maintenance-HOLD/out/owner-postadoption-dispatch-gate-R136/spotify-control.ps1'
$t=$null;$err=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$t,[ref]$err)
if(@($err).Count -ne 0){throw 'R136_PRODUCT_WINDOWS_PS51_SYNTAX_INVALID'}
$targets=@('Assert-R136NoBypassFromOwnerHold','Test-R134OwnerReconciledMutationHold','Launch-ManagedSpotify')
$defs=@($ast.FindAll({param($node)
  $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
  $node.Name -cin $targets
},$true))
if($defs.Count -ne $targets.Count){throw 'R136_REAL_SOURCE_FUNCTIONS_MISSING'}
. ([ScriptBlock]::Create((@($defs|ForEach-Object{$_.Extent.Text}) -join [Environment]::NewLine)))
$script:Status='owner-reviewed-preimage'
$script:ClaimPresent=$false
# Real R135 product initializes these at startup; mirror it in the isolated AST fixture.
$script:R135ActiveOwnerAttempt=$false
$script:R135AttemptCalls=0
$script:R135ClaimSHA=$null
$script:R135OwnerId=$null
$script:ProofVisits=0
function Get-SpicetifyTransaction {return [pscustomobject]@{status=$script:Status}}
function Read-R135OwnerAttempt {
  if($script:ClaimPresent){return [pscustomobject]@{schema=1}}
  return $null
}
function Assert-SpicetifyOwnerPreimageAdoption {param($Txn);$script:ProofVisits++;return $true}
$protected=@('UpdateMarketplace','UpdateSpicetify','SpicetifyRollbackTest',
 'RollbackSpicetify','UpdateSpotify','SpotifyRollbackTest','RollbackSpotify',
 'InstallTasks','SelfUpdate','SelfUpdateRollbackTest','RollbackSelfUpdate','GuardUpdates')
foreach($name in $protected){
  $blocked=$false
  try{Assert-R136NoBypassFromOwnerHold $name}catch{
    $blocked=$_.Exception.Message -ceq 'R136_OWNER_ADOPTION_NOT_APPROVAL_FOR_OTHER_MUTATIONS'
  }
  if(-not $blocked){throw ('R136_UNAPPROVED_MUTATION_ROUTED='+$name)}
}
foreach($allowed in @('Launch','CheckOnly','Status','AgentTick','SpicetifyPreflight','OwnerSpicetifyOnce','Audit')){
  Assert-R136NoBypassFromOwnerHold $allowed
}
if($script:ProofVisits -lt $protected.Count){
 throw 'R136_OWNER_EVIDENCE_NOT_READ_ON_EACH_MODIFYING_ROUTE'
}
$script:Status='committed'
$script:ClaimPresent=$true
foreach($name in $protected){
  $blocked=$false
  try{Assert-R136NoBypassFromOwnerHold $name}catch{
    $blocked=$_.Exception.Message -ceq 'R136_OWNER_ADOPTION_NOT_APPROVAL_FOR_OTHER_MUTATIONS'
  }
  if(-not $blocked){throw ('R136_POST_ATTEMPT_MUTATION_ROUTED='+$name)}
}
Write-Host 'R136_ALL_DIRECT_MUTATION_COMMANDS_BLOCKED_AFTER_ADOPTION_OR_ATTEMPT=PASS'
# Launch intentionally remains a real Spotify playback action. An old
# cached compatibility guard must never cause spicetify auto in HOLD.
$script:LastGuardResult=[pscustomobject]@{CurrentSupported=$true}
$script:Spicetify='present'
$script:LaunchCount=0
$script:SpiceCount=0
function Get-SpotifyExecutable{return 'C:\synthetic\Spotify.exe'}
function Test-SpotifyRunning {return $false}
function Maintain { }
function Write-Log {param($Message,$Level)}
function Invoke-Spice {param($Arguments,$AllowFailure);$script:SpiceCount++;throw 'R136_SPICETIFY_AUTO_UNAPPROVED'}
function Start-Process {param($FilePath);$script:LaunchCount++}
function Start-Sleep {param($Seconds)}
function Start-PerformanceSnapshotAsync { }
Launch-ManagedSpotify
if($script:SpiceCount -ne 0 -or $script:LaunchCount -ne 1){
  throw 'R136_SPOTIFY_PLAYBACK_OR_AUTO_BOUNDARY_INVALID'
}
$script:Status='committed'
$script:ClaimPresent=$false
$script:LaunchCount=0
$script:SpiceCount=0
$script:LastGuardResult=[pscustomobject]@{CurrentSupported=$false}
Launch-ManagedSpotify
if($script:SpiceCount -ne 0 -or $script:LaunchCount -ne 1){
  throw 'R136_NON_ADOPTED_LAUNCH_REGRESSED'
}
Write-Host 'R136_NORMAL_SPOTIFY_LAUNCH_PRESERVED_AND_SPICETIFY_AUTO_DENIED_DURING_HOLD=PASS'
