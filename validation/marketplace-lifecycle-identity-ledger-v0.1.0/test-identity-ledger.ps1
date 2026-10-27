$ErrorActionPreference='Stop'
$here=Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'marketplace-identity-ledger.ps1')

function Assert-True { param([bool]$Condition,[string]$Message) if(-not $Condition){throw $Message} }
function Assert-Eq { param($Actual,$Expected,[string]$Message) if([string]$Actual -cne [string]$Expected){throw ("{0}: actual={1} expected={2}" -f $Message,$Actual,$Expected)} }
function Get-Sha256Text { param([string]$Text) $s=[Security.Cryptography.SHA256]::Create();try{return ([BitConverter]::ToString($s.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-','').ToLowerInvariant())}finally{$s.Dispose()} }
function Get-StateJson { param($State) return ($State|ConvertTo-Json -Depth 30 -Compress) }

function New-GitHubRecord {
    param([string]$Owner,[string]$Repo,[string]$Artifact,[string]$Kind='extension',[string[]]$Profiles=@('Browser'))
    return [pscustomobject]@{
        key=('marketplace:installed:{0}/{1}/{2}' -f $Owner,$Repo,$Artifact)
        kind=$Kind; source_kind='github-repository-key'; github_owner=$Owner; github_repo=$Repo; artifact_path=$Artifact
        repository_url=('https://github.com/{0}/{1}' -f $Owner,$Repo); profiles=@($Profiles); mutation_authorized=$false
    }
}
function New-SnippetRecord { param([string]$Name,[string[]]$Profiles=@('Browser')) return [pscustomobject]@{key=('marketplace:installed:snippet:'+$Name);kind='snippet';source_kind='snippet-key';github_owner=$null;github_repo=$null;artifact_path=$Name;repository_url=$null;profiles=@($Profiles);mutation_authorized=$false} }
function New-Report {
    param([object[]]$Records=@(),[string]$Status='ok',[object[]]$Conflicts=@(),[bool]$SafeToExpand=$false)
    $keys=@($Records|ForEach-Object{[string]$_.key}|Sort-Object)
    $fp=Get-Sha256Text ($keys -join "`n")
    return [pscustomobject]@{schema=1;collector_version='0.1.0';read_only=$true;mutation_performed=$false;status=$Status;record_count=@($Records).Count;identity_fingerprint=$fp;records=@($Records);profile_conflicts=@($Conflicts);derived=[pscustomobject]@{safe_to_expand_mutation_authority=$SafeToExpand}}
}
function Get-Row { param($State,[string]$MarketplaceKey) $k=Get-MarketplaceIdentityLedgerKey $MarketplaceKey; if(-not $State.lifecycle.PSObject.Properties[$k]){return $null};return $State.lifecycle.PSObject.Properties[$k].Value }

$ext=New-GitHubRecord 'alice' 'ext-repo' 'dist/ext.js' 'extension' @('Browser')
$theme=New-GitHubRecord 'bob' 'theme-repo' 'user.css' 'theme' @('Browser','Default')
$snippet=New-SnippetRecord 'My-Snippet' @('Default')
$orphan=New-GitHubRecord 'carol' 'orphan-repo' 'orphan.js' 'unlisted' @('Browser')
$state=[pscustomobject]@{schema=3;lifecycle=[pscustomobject]@{}}

# 1. First authoritative discovery creates deny-by-default rows in the same lifecycle ledger.
$r1=Update-MarketplaceIdentityLifecycleLedger -State $state -MarketplaceReport (New-Report @($ext,$theme,$snippet)) -ObservedAt '2026-10-27T16:00:00Z'
Assert-True $r1.conclusive 'first discovery must be conclusive'
Assert-Eq $r1.new_count 3 'first discovery new count'
Assert-Eq @($state.lifecycle.PSObject.Properties).Count 3 'ledger row count after first discovery'
foreach($record in @($ext,$theme,$snippet)){
    $row=Get-Row $state $record.key
    Assert-True ($null -ne $row) ('missing ledger row: '+$record.key)
    Assert-True $row.present ('new row not present: '+$record.key)
    Assert-True (-not $row.user_removed) ('new row unexpectedly tombstoned: '+$record.key)
    Assert-Eq $row.mutation_mode 'deny' ('new row mutation mode: '+$record.key)
    Assert-True (-not (Test-MarketplaceIdentityMutationAllowed -State $state -MarketplaceKey $record.key)) ('mutation unexpectedly allowed: '+$record.key)
}
Assert-Eq (Get-Row $state $ext.key).source_identity 'github:alice/ext-repo:dist/ext.js' 'normalized source identity'
Assert-Eq (Get-Row $state $snippet.key).source_identity 'snippet:my-snippet' 'snippet source identity'

# 2. Idempotent observation updates last_seen but does not add/remove rows or authorize mutation.
$r2=Update-MarketplaceIdentityLifecycleLedger -State $state -MarketplaceReport (New-Report @($ext,$theme,$snippet)) -ObservedAt '2026-10-27T16:01:00Z'
Assert-Eq $r2.new_count 0 'idempotent new count';Assert-Eq $r2.removed_count 0 'idempotent removed count'
Assert-Eq (Get-Row $state $ext.key).last_seen '2026-10-27T16:01:00Z' 'last_seen update'

# 3. Authoritative disappearance is treated as user removal, preventing resurrection.
$r3=Update-MarketplaceIdentityLifecycleLedger -State $state -MarketplaceReport (New-Report @($theme,$snippet)) -ObservedAt '2026-10-27T16:02:00Z'
Assert-Eq $r3.removed_count 1 'user-removal count'
$extRow=Get-Row $state $ext.key
Assert-True (-not $extRow.present) 'removed extension still present'
Assert-True $extRow.user_removed 'removed extension missing tombstone'
Assert-Eq $extRow.removed_at '2026-10-27T16:02:00Z' 'removed timestamp'
Assert-True (-not (Test-MarketplaceIdentityMutationAllowed -State $state -MarketplaceKey $ext.key)) 'removed extension became mutation eligible'

# 4. Explicit reappearance clears the user-removal tombstone but still remains deny-by-default.
$r4=Update-MarketplaceIdentityLifecycleLedger -State $state -MarketplaceReport (New-Report @($ext,$theme,$snippet)) -ObservedAt '2026-10-27T16:03:00Z'
Assert-Eq $r4.reinstalled_count 1 'reappearance count'
$extRow=Get-Row $state $ext.key
Assert-True $extRow.present 'reappeared extension not present';Assert-True (-not $extRow.user_removed) 'reappeared extension tombstone not cleared'
Assert-Eq $extRow.reinstalled_at '2026-10-27T16:03:00Z' 'reinstalled timestamp'
Assert-Eq $extRow.mutation_mode 'deny' 'reappearance expanded mutation authority'

# 5. Transaction-owned disappearance is not misclassified as user deletion and cannot auto-resurrect.
$r5=Update-MarketplaceIdentityLifecycleLedger -State $state -MarketplaceReport (New-Report @($ext,$snippet)) -ObservedAt '2026-10-27T16:04:00Z' -TransactionOwnedAbsenceKeys @($theme.key)
Assert-Eq $r5.transaction_absence_count 1 'transaction-owned absence count'
$themeRow=Get-Row $state $theme.key
Assert-True (-not $themeRow.present) 'transaction-owned absent row still present';Assert-True (-not $themeRow.user_removed) 'transaction-owned absence became user deletion'
Assert-True (-not (Test-MarketplaceIdentityMutationAllowed -State $state -MarketplaceKey $theme.key)) 'transaction-owned absent row became mutation eligible'

# 6. Inconclusive/corrupt evidence must not alter lifecycle state.
$before=Get-StateJson $state
$inconclusive=New-Report @() 'inconclusive'
$r6=Update-MarketplaceIdentityLifecycleLedger -State $state -MarketplaceReport $inconclusive -ObservedAt '2026-10-27T16:05:00Z'
Assert-True (-not $r6.conclusive) 'inconclusive report accepted as conclusive';Assert-True (-not $r6.state_changed) 'inconclusive report claims state change'
Assert-Eq (Get-StateJson $state) $before 'inconclusive report mutated state'

# 7. Cross-profile conflicts also fail closed without touching state.
$before=Get-StateJson $state
$conflicted=New-Report @($ext,$snippet) 'ok' @([pscustomobject]@{key=$ext.key;reason='profile-identity-conflict'})
$r7=Update-MarketplaceIdentityLifecycleLedger -State $state -MarketplaceReport $conflicted -ObservedAt '2026-10-27T16:06:00Z'
Assert-True (-not $r7.conclusive) 'profile conflict accepted as conclusive';Assert-Eq (Get-StateJson $state) $before 'profile conflict mutated state'

# 8. A key/source mismatch throws before any partial ledger mutation.
$bad=New-GitHubRecord 'mallory' 'evil' 'evil.js' 'extension' @('Browser')
$bad.github_owner='alice'
$before=Get-StateJson $state;$threw=$false
try{Update-MarketplaceIdentityLifecycleLedger -State $state -MarketplaceReport (New-Report @($ext,$bad)) -ObservedAt '2026-10-27T16:07:00Z'|Out-Null}catch{$threw=$true}
Assert-True $threw 'source/key mismatch did not fail closed';Assert-Eq (Get-StateJson $state) $before 'source/key mismatch caused partial mutation'

# 9. Duplicate Marketplace keys fail before state mutation.
$before=Get-StateJson $state;$threw=$false
try{Update-MarketplaceIdentityLifecycleLedger -State $state -MarketplaceReport (New-Report @($ext,$ext)) -ObservedAt '2026-10-27T16:08:00Z'|Out-Null}catch{$threw=$true}
Assert-True $threw 'duplicate identity did not fail closed';Assert-Eq (Get-StateJson $state) $before 'duplicate identity caused partial mutation'

# 10. Collector contract can never self-authorize expansion.
$before=Get-StateJson $state;$threw=$false
try{Update-MarketplaceIdentityLifecycleLedger -State $state -MarketplaceReport (New-Report @($ext) 'ok' @() $true) -ObservedAt '2026-10-27T16:09:00Z'|Out-Null}catch{$threw=$true}
Assert-True $threw 'safe_to_expand_mutation_authority=true was accepted';Assert-Eq (Get-StateJson $state) $before 'authority-contract failure mutated state'

# 11. Repository URL mismatch fails closed.
$badUrl=New-GitHubRecord 'alice' 'ext-repo' 'dist/ext.js' 'extension' @('Browser');$badUrl.repository_url='https://github.com/other/repo'
$before=Get-StateJson $state;$threw=$false
try{Update-MarketplaceIdentityLifecycleLedger -State $state -MarketplaceReport (New-Report @($badUrl)) -ObservedAt '2026-10-27T16:10:00Z'|Out-Null}catch{$threw=$true}
Assert-True $threw 'repository URL mismatch was accepted';Assert-Eq (Get-StateJson $state) $before 'repository URL mismatch mutated state'

# 12. Source-key replacement never silently aliases identities: old record tombstones, new record is first-seen.
$newExt=New-GitHubRecord 'alice' 'ext-repo' 'dist/ext-v2.js' 'extension' @('Browser')
# First make theme reappear so the snapshot is fully authoritative before the replacement.
Update-MarketplaceIdentityLifecycleLedger -State $state -MarketplaceReport (New-Report @($ext,$theme,$snippet)) -ObservedAt '2026-10-27T16:11:00Z'|Out-Null
$r12=Update-MarketplaceIdentityLifecycleLedger -State $state -MarketplaceReport (New-Report @($newExt,$theme,$snippet)) -ObservedAt '2026-10-27T16:12:00Z'
Assert-Eq $r12.new_count 1 'replacement new identity count';Assert-Eq $r12.removed_count 1 'replacement old identity tombstone count'
Assert-True (Get-Row $state $ext.key).user_removed 'old source identity not tombstoned'
Assert-True (Get-Row $state $newExt.key).present 'new source identity not first-seen'
Assert-Eq (Get-Row $state $newExt.key).mutation_mode 'deny' 'new source identity got mutation authority'

# 13. An unlisted/orphan live key remains discoverable but denied.
$r13=Update-MarketplaceIdentityLifecycleLedger -State $state -MarketplaceReport (New-Report @($newExt,$theme,$snippet,$orphan)) -ObservedAt '2026-10-27T16:13:00Z'
Assert-Eq $r13.new_count 1 'orphan discovery count';Assert-Eq (Get-Row $state $orphan.key).kind 'unlisted' 'orphan kind';Assert-Eq (Get-Row $state $orphan.key).mutation_mode 'deny' 'orphan mutation mode'

# 14. Local lifecycle rows owned by the previous dynamic-spicetify layer coexist and are never modified by Marketplace reconciliation.
$localKey='extension:local-only.js';$local=[pscustomobject]@{key=$localKey;managed_by='dynamic-spicetify-v1';kind='extension';name='local-only.js';present=$true;user_removed=$false;mutation_mode='deny'}
$state.lifecycle|Add-Member -NotePropertyName $localKey -NotePropertyValue $local
$localBefore=($local|ConvertTo-Json -Depth 10 -Compress)
Update-MarketplaceIdentityLifecycleLedger -State $state -MarketplaceReport (New-Report @($newExt,$theme,$snippet,$orphan)) -ObservedAt '2026-10-27T16:14:00Z'|Out-Null
Assert-Eq ($state.lifecycle.PSObject.Properties[$localKey].Value|ConvertTo-Json -Depth 10 -Compress) $localBefore 'Marketplace reconciliation touched local lifecycle row'

# 15. All Marketplace rows remain in deny mode; this phase proves identity/user-intent semantics only.
foreach($prop in @($state.lifecycle.PSObject.Properties)){
    $row=$prop.Value
    if([string]$row.managed_by -ceq 'marketplace-record-v1'){
        Assert-Eq $row.mutation_mode 'deny' ('final authority drift: '+$prop.Name)
        Assert-True (-not (Test-MarketplaceIdentityMutationAllowed -State $state -MarketplaceKey ([string]$row.marketplace_key))) ('final mutation authority unexpectedly true: '+$prop.Name)
    }
}

Write-Host 'MARKETPLACE_IDENTITY_LEDGER_MATRIX_PASS scenarios=15'
Write-Host ('MARKETPLACE_IDENTITY_LEDGER_FINAL_ROWS={0}' -f @($state.lifecycle.PSObject.Properties).Count)
